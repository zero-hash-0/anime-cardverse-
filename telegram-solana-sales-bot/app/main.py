import asyncio
import json
import logging
import os
import urllib.request
import html
import time
from collections import deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Deque, Dict, Iterable, List, Optional, Tuple

from dotenv import load_dotenv
import secrets

from fastapi import Depends, FastAPI, Form, HTTPException, Request, status
from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from telegram import Bot
from telegram.error import TelegramError

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("solana-sales-bot")

LAMPORTS_PER_SOL = 1_000_000_000


def _parse_csv(value: str) -> List[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "").strip()
ADMIN_USER = os.getenv("ADMIN_USER", "").strip()
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "").strip()
HELIUS_API_KEY = os.getenv("HELIUS_API_KEY", "").strip()
TENSOR_COLLECTION_ID = os.getenv("TENSOR_COLLECTION_ID", "").strip()
HOWRARE_API_KEY = os.getenv("HOWRARE_API_KEY", "").strip()
WHALE_SOL = float(os.getenv("WHALE_SOL", "50") or 50)
SWEEP_COUNT = int(os.getenv("SWEEP_COUNT", "3") or 3)
SWEEP_WINDOW_SEC = int(os.getenv("SWEEP_WINDOW_SEC", "120") or 120)
ALERT_GIF_URL = os.getenv("ALERT_GIF_URL", "").strip()
SEND_LISTING_ALERTS = os.getenv("SEND_LISTING_ALERTS", "false").strip().lower() in {"1", "true", "yes"}
WATCH_MINTS = set(_parse_csv(os.getenv("WATCH_MINTS", "")))
_watch_sources_env = _parse_csv(os.getenv("WATCH_SOURCES", ""))
WATCH_SOURCES = set(s.lower() for s in _watch_sources_env) if _watch_sources_env else {"tensor"}
WATCH_MINTLIST_URL = os.getenv("WATCH_MINTLIST_URL", "").strip()

BASE_DIR = Path(__file__).resolve().parent
ENV_PATH = BASE_DIR.parent / ".env"
BUILD_ID = os.getenv("BUILD_ID", "build-2026-02-10")

app = FastAPI(title="Solana NFT Sales Telegram Bot")
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")
templates = Jinja2Templates(directory=str(BASE_DIR / "templates"))
security = HTTPBasic()
templates.env.globals["build_id"] = BUILD_ID

# Simple in-memory de-dupe for recent signatures
_recent_signatures = deque(maxlen=500)
_recent_signature_set = set()
_recent_sales: Deque[Dict[str, Any]] = deque(maxlen=40)
_recent_listings: Deque[Dict[str, Any]] = deque(maxlen=40)
_sales_seen = 0
_sales_sent = 0
_last_event_time: Optional[str] = None
_metadata_cache: Dict[str, Dict[str, Any]] = {}
_metadata_cache_order: Deque[str] = deque(maxlen=500)
_floor_cache: Dict[str, Any] = {}
_floor_cache_time: Optional[float] = None
_rarity_cache: Dict[str, Dict[str, Any]] = {}
_rarity_cache_time: Dict[str, float] = {}
_sales_window: Deque[Tuple[float, float, str]] = deque(maxlen=2000)


@app.on_event("startup")
async def _startup() -> None:
    if not TELEGRAM_BOT_TOKEN:
        logger.warning("TELEGRAM_BOT_TOKEN is not set. Webhook will accept but cannot send messages.")
    if not TELEGRAM_CHAT_ID:
        logger.warning("TELEGRAM_CHAT_ID is not set. Webhook will accept but cannot send messages.")
    if WATCH_MINTLIST_URL:
        await _load_mintlist(WATCH_MINTLIST_URL)


@app.get("/health")
async def health() -> Dict[str, str]:
    return {"status": "ok"}


@app.get("/", response_class=HTMLResponse)
async def landing(request: Request) -> HTMLResponse:
    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "stats": _status_snapshot(),
        },
    )


def _require_admin(credentials: HTTPBasicCredentials = Depends(security)) -> HTTPBasicCredentials:
    if not ADMIN_USER or not ADMIN_PASSWORD:
        raise HTTPException(status_code=503, detail="Admin credentials not configured")

    user_ok = secrets.compare_digest(credentials.username, ADMIN_USER)
    pass_ok = secrets.compare_digest(credentials.password, ADMIN_PASSWORD)
    if not (user_ok and pass_ok):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials


@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard(request: Request, _: HTTPBasicCredentials = Depends(_require_admin)) -> HTMLResponse:
    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "config": _config_snapshot(),
        },
    )


@app.get("/status", response_class=HTMLResponse)
async def status_page(request: Request) -> HTMLResponse:
    snapshot = _status_snapshot()
    return templates.TemplateResponse(
        "status.html",
        {
            "request": request,
            "stats": snapshot,
            "recent_sales": list(_recent_sales),
            "recent_listings": list(_recent_listings),
        },
    )


@app.get("/api/stream")
async def api_stream(request: Request) -> StreamingResponse:
    async def event_generator():
        while True:
            if await request.is_disconnected():
                break
            payload = {
                "stats": _status_snapshot(),
                "recent_sales": list(_recent_sales),
                "recent_listings": list(_recent_listings),
            }
            yield f"data: {json.dumps(payload)}\n\n"
            await asyncio.sleep(5)

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@app.get("/api/status")
async def api_status() -> Dict[str, Any]:
    return {
        "stats": _status_snapshot(),
        "recent_sales": list(_recent_sales),
        "recent_listings": list(_recent_listings),
    }


@app.post("/dashboard/update")
async def update_dashboard(
    request: Request,
    _: HTTPBasicCredentials = Depends(_require_admin),
    telegram_bot_token: str = Form(""),
    telegram_chat_id: str = Form(""),
    watch_sources: str = Form(""),
    watch_mintlist_url: str = Form(""),
    helius_api_key: str = Form(""),
    tensor_collection_id: str = Form(""),
    howrare_api_key: str = Form(""),
    send_listing_alerts: str = Form(""),
    admin_user: str = Form(""),
    admin_password: str = Form(""),
) -> HTMLResponse:
    updates = {
        "TELEGRAM_BOT_TOKEN": telegram_bot_token.strip(),
        "TELEGRAM_CHAT_ID": telegram_chat_id.strip(),
        "WATCH_SOURCES": watch_sources.strip(),
        "WATCH_MINTLIST_URL": watch_mintlist_url.strip(),
        "HELIUS_API_KEY": helius_api_key.strip(),
        "TENSOR_COLLECTION_ID": tensor_collection_id.strip(),
        "HOWRARE_API_KEY": howrare_api_key.strip(),
        "SEND_LISTING_ALERTS": send_listing_alerts.strip(),
        "ADMIN_USER": admin_user.strip(),
        "ADMIN_PASSWORD": admin_password.strip(),
    }
    updates = {key: value for key, value in updates.items() if value}
    _write_env_updates(updates)
    await _apply_runtime_updates(updates)

    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "config": _config_snapshot(),
            "notice": "Configuration updated. If changes do not apply, restart the server.",
        },
    )


@app.post("/dashboard/test")
async def dashboard_test(
    request: Request,
    _: HTTPBasicCredentials = Depends(_require_admin),
) -> HTMLResponse:
    error = None
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        error = "Missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID."
    else:
        bot = Bot(TELEGRAM_BOT_TOKEN)
        await bot.send_message(chat_id=TELEGRAM_CHAT_ID, text="Test message from GeckoPulse.")

    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "config": _config_snapshot(),
            "notice": "Test message sent." if not error else None,
            "error": error,
        },
    )


@app.post("/dashboard/simulate")
async def dashboard_simulate(
    request: Request,
    _: HTTPBasicCredentials = Depends(_require_admin),
) -> HTMLResponse:
    fake_event, fake_nft = _fake_sale()
    enriched = _enrich_metadata(fake_nft)
    _record_sale(fake_event, enriched)

    error = None
    if TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID:
        bot = Bot(TELEGRAM_BOT_TOKEN)
        try:
            await _send_alert(bot, _format_sale_message(fake_event, enriched), enriched)
        except TelegramError as exc:
            error = f"Telegram error: {exc}"
    else:
        error = "Missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID."

    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "config": _config_snapshot(),
            "notice": "Simulated sale added." if not error else None,
            "error": error,
        },
    )


@app.post("/dashboard/simulate-listing")
async def dashboard_simulate_listing(
    request: Request,
    _: HTTPBasicCredentials = Depends(_require_admin),
) -> HTMLResponse:
    fake_event, fake_nft = _fake_listing()
    enriched = _enrich_metadata(fake_nft)
    _record_listing(fake_event, enriched)

    error = None
    if SEND_LISTING_ALERTS and TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID:
        bot = Bot(TELEGRAM_BOT_TOKEN)
        try:
            await _send_alert(bot, _format_listing_message(fake_event, enriched), enriched)
        except TelegramError as exc:
            error = f"Telegram error: {exc}"

    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "config": _config_snapshot(),
            "notice": "Simulated listing added." if not error else None,
            "error": error,
        },
    )


@app.post("/webhook/helius")
async def helius_webhook(request: Request) -> Dict[str, Any]:
    payload = await request.json()
    if not isinstance(payload, list):
        raise HTTPException(status_code=400, detail="Expected list payload")

    events = [event for event in payload if isinstance(event, dict)]
    if not events:
        return {"received": 0, "sent": 0}

    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        logger.error("Missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID")
        raise HTTPException(status_code=500, detail="Bot not configured")

    bot = Bot(TELEGRAM_BOT_TOKEN)
    sent = 0

    for event in events:
        if event.get("type") != "NFT_SALE":
            if event.get("type") != "NFT_LISTING":
                continue

        _increment_seen()

        signature = _get_signature(event)
        if signature and _seen_signature(signature):
            continue

        source = (event.get("source") or "").lower()
        if WATCH_SOURCES and source not in WATCH_SOURCES:
            continue

        nft_info = _extract_nft_info(event)
        if WATCH_MINTS and nft_info.get("mint") not in WATCH_MINTS:
            continue

        enriched = _enrich_metadata(nft_info)

        if event.get("type") == "NFT_SALE":
            message = _format_sale_message(event, enriched)
            try:
                await _send_alert(bot, message, enriched)
            except TelegramError as exc:
                logger.warning("Telegram send failed: %s", exc)
                continue
            sent += 1
            _record_sale(event, enriched)
        else:
            message = _format_listing_message(event, enriched)
            if SEND_LISTING_ALERTS:
                try:
                    await _send_alert(bot, message, enriched)
                except TelegramError as exc:
                    logger.warning("Telegram send failed: %s", exc)
                    continue
                sent += 1
            _record_listing(event, enriched)

    return {"received": len(events), "sent": sent}


def _get_signature(event: Dict[str, Any]) -> Optional[str]:
    signature = event.get("signature")
    if signature:
        return signature
    return (event.get("events") or {}).get("nft", {}).get("signature")


def _seen_signature(signature: str) -> bool:
    if signature in _recent_signature_set:
        return True
    if _recent_signatures.maxlen and len(_recent_signatures) >= _recent_signatures.maxlen:
        oldest = _recent_signatures.popleft()
        _recent_signature_set.discard(oldest)
    _recent_signatures.append(signature)
    _recent_signature_set.add(signature)
    return False


async def _load_mintlist(url: str) -> None:
    try:
        mints = await asyncio.to_thread(_fetch_mintlist, url)
    except Exception as exc:
        logger.warning("Failed to load mintlist from %s: %s", url, exc)
        return

    if not mints:
        logger.warning("Mintlist from %s was empty.", url)
        return

    WATCH_MINTS.update(mints)
    logger.info("Loaded %d mints from mintlist.", len(mints))


def _fetch_mintlist(url: str) -> List[str]:
    with urllib.request.urlopen(url, timeout=15) as response:
        data = json.load(response)

    def _extract_mints(value: Any) -> List[str]:
        if isinstance(value, list):
            if value and isinstance(value[0], dict):
                found = []
                for item in value:
                    mint = item.get("mint") if isinstance(item, dict) else None
                    if mint:
                        found.append(str(mint))
                return found
            return [str(item) for item in value if item]
        if isinstance(value, dict):
            if "mints" in value:
                return _extract_mints(value.get("mints"))
            if "result" in value:
                return _extract_mints(value.get("result"))
            if "data" in value:
                return _extract_mints(value.get("data"))
        return []

    mints = _extract_mints(data)
    if mints:
        return mints

    raise ValueError("Unsupported mintlist format")


def _extract_nft_info(event: Dict[str, Any]) -> Dict[str, Any]:
    nft_event = (event.get("events") or {}).get("nft", {})
    nfts: Iterable[Dict[str, Any]] = nft_event.get("nfts") or []
    first = next(iter(nfts), {})
    amount = nft_event.get("amount")
    if amount is None:
        amount = nft_event.get("price") or nft_event.get("listingPrice")

    return {
        "mint": first.get("mint"),
        "name": first.get("name"),
        "seller": nft_event.get("seller"),
        "buyer": nft_event.get("buyer"),
        "amount_lamports": amount,
        "marketplace": event.get("source"),
        "signature": _get_signature(event),
        "description": event.get("description"),
    }


def _format_sale_message(event: Dict[str, Any], nft: Dict[str, Any]) -> str:
    name = nft.get("name") or "Unknown NFT"
    mint = nft.get("mint") or "Unknown mint"
    marketplace = nft.get("marketplace") or "Unknown marketplace"

    amount_lamports = nft.get("amount_lamports")
    amount_str = "Unknown price"
    if isinstance(amount_lamports, (int, float)):
        amount_str = f"{amount_lamports / LAMPORTS_PER_SOL:.4f} SOL"

    seller = nft.get("seller") or "Unknown seller"
    buyer = nft.get("buyer") or "Unknown buyer"
    signature = nft.get("signature") or "Unknown signature"
    collection = nft.get("collection")
    traits = nft.get("traits") or []
    short_mint = _shorten(mint)
    short_buyer = _shorten(buyer)
    short_seller = _shorten(seller)
    tensor_url = _tensor_url(mint)
    solscan_url = _solscan_url(mint, signature)
    official_url = "https://galacticgeckos.io/"
    community_url = "https://linktr.ee/GalacticGeckoSpaceGarage"

    floor_info = _floor_snapshot()
    floor_line = ""
    if floor_info and amount_lamports:
        floor_sol = floor_info.get("price_sol")
        if floor_sol:
            delta = (amount_lamports / LAMPORTS_PER_SOL - floor_sol) / floor_sol * 100
            floor_line = f"Floor: {floor_sol:.2f} SOL ({delta:+.1f}%)"

    rarity_line = ""
    rarity = _rarity_snapshot(mint)
    if rarity and rarity.get("rank"):
        rarity_line = f"Rarity: Top {rarity['percentile']:.1f}% (#{rarity['rank']})"

    tags = _sale_tags(amount_lamports, floor_info, buyer)
    tag_line = " ".join(tags) if tags else ""

    lines = [
        "<b>🦎 GeckoPulse • Tensor Sale</b>",
        f"<b>{_h(name)}</b>",
    ]

    if collection:
        lines.append(f"Collection: {_h(collection)}")

    lines.append(f"Price: <b>{_h(amount_str)}</b>")
    if tag_line:
        lines.append(tag_line)
    if floor_line:
        lines.append(_h(floor_line))
    if rarity_line:
        lines.append(_h(rarity_line))
    lines.append(f"Marketplace: {_h(marketplace)}")
    lines.append(f"Mint: <code>{_h(short_mint)}</code>")
    lines.append(f"Buyer: <code>{_h(short_buyer)}</code>")
    lines.append(f"Seller: <code>{_h(short_seller)}</code>")

    if traits:
        lines.append("Traits: " + " · ".join(_h(t) for t in traits[:3]))

    lines.append(f"<a href=\"{_h(tensor_url)}\">View on Tensor</a> · <a href=\"{_h(solscan_url)}\">Solscan</a>")
    lines.append(f"<a href=\"{_h(official_url)}\">Official Site</a> · <a href=\"{_h(community_url)}\">Community Links</a>")

    description = nft.get("description")
    if description:
        lines.append(f"Note: {_h(description)}")

    return "\n".join(lines)


def _format_listing_message(event: Dict[str, Any], nft: Dict[str, Any]) -> str:
    name = nft.get("name") or "Unknown NFT"
    mint = nft.get("mint") or "Unknown mint"
    marketplace = nft.get("marketplace") or "Unknown marketplace"

    amount_lamports = nft.get("amount_lamports")
    amount_str = "Unknown price"
    if isinstance(amount_lamports, (int, float)):
        amount_str = f"{amount_lamports / LAMPORTS_PER_SOL:.4f} SOL"

    seller = nft.get("seller") or "Unknown seller"
    signature = nft.get("signature") or "Unknown signature"
    collection = nft.get("collection")
    traits = nft.get("traits") or []
    short_mint = _shorten(mint)
    short_seller = _shorten(seller)
    tensor_url = _tensor_url(mint)
    solscan_url = _solscan_url(mint, signature)
    official_url = "https://galacticgeckos.io/"
    community_url = "https://linktr.ee/GalacticGeckoSpaceGarage"

    lines = [
        "<b>🦎 GeckoPulse • New Listing</b>",
        f"<b>{_h(name)}</b>",
    ]

    if collection:
        lines.append(f"Collection: {_h(collection)}")

    lines.append(f"Listed: <b>{_h(amount_str)}</b>")
    lines.append(f"Marketplace: {_h(marketplace)}")
    lines.append(f"Mint: <code>{_h(short_mint)}</code>")
    lines.append(f"Seller: <code>{_h(short_seller)}</code>")

    if traits:
        lines.append("Traits: " + " · ".join(_h(t) for t in traits[:3]))

    lines.append(f"<a href=\"{_h(tensor_url)}\">View on Tensor</a> · <a href=\"{_h(solscan_url)}\">Solscan</a>")
    lines.append(f"<a href=\"{_h(official_url)}\">Official Site</a> · <a href=\"{_h(community_url)}\">Community Links</a>")

    description = nft.get("description")
    if description:
        lines.append(f"Note: {_h(description)}")

    return "\n".join(lines)


async def _send_alert(bot: Bot, message: str, nft: Dict[str, Any]) -> None:
    image_url = nft.get("image")
    tags = nft.get("tags") or []
    has_special = any("Whale" in tag or "Sweep" in tag or "Above Floor" in tag for tag in tags)
    if ALERT_GIF_URL and has_special:
        await bot.send_animation(chat_id=TELEGRAM_CHAT_ID, animation=ALERT_GIF_URL, caption=message, parse_mode="HTML")
        return
    if image_url:
        await bot.send_photo(chat_id=TELEGRAM_CHAT_ID, photo=image_url, caption=message, parse_mode="HTML")
    else:
        await bot.send_message(chat_id=TELEGRAM_CHAT_ID, text=message, parse_mode="HTML", disable_web_page_preview=True)


def _mask_value(value: str, visible: int = 4) -> str:
    if not value:
        return ""
    if len(value) <= visible:
        return "*" * len(value)
    return f"{'*' * (len(value) - visible)}{value[-visible:]}"


def _current_time() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def _increment_seen() -> None:
    global _sales_seen
    _sales_seen += 1


def _record_sale(event: Dict[str, Any], nft: Dict[str, Any]) -> None:
    global _sales_sent, _last_event_time

    _sales_sent += 1
    timestamp = event.get("timestamp") or event.get("time") or _current_time()
    _last_event_time = str(timestamp)
    event_ts = _parse_event_time(timestamp)

    amount_lamports = nft.get("amount_lamports")
    amount_str = "Unknown"
    if isinstance(amount_lamports, (int, float)):
        amount_str = f"{amount_lamports / LAMPORTS_PER_SOL:.4f} SOL"

    enriched = _enrich_metadata(nft)
    tags = _sale_tags(nft.get("amount_lamports"), _floor_snapshot(), nft.get("buyer"))
    _recent_sales.appendleft(
        {
            "name": enriched.get("name") or "Unknown NFT",
            "mint": enriched.get("mint") or "Unknown",
            "price": amount_str,
            "marketplace": nft.get("marketplace") or "Unknown",
            "buyer": nft.get("buyer") or "Unknown",
            "seller": nft.get("seller") or "Unknown",
            "signature": nft.get("signature") or "Unknown",
            "timestamp": _last_event_time,
            "image": enriched.get("image"),
            "traits": enriched.get("traits") or [],
            "collection": enriched.get("collection"),
            "tags": tags,
        }
    )

    if isinstance(amount_lamports, (int, float)) and event_ts:
        _sales_window.append((event_ts, amount_lamports / LAMPORTS_PER_SOL, nft.get("buyer") or ""))
        _prune_sales_window()


def _record_listing(event: Dict[str, Any], nft: Dict[str, Any]) -> None:
    timestamp = event.get("timestamp") or event.get("time") or _current_time()
    amount_lamports = nft.get("amount_lamports")
    amount_str = "Unknown"
    if isinstance(amount_lamports, (int, float)):
        amount_str = f"{amount_lamports / LAMPORTS_PER_SOL:.4f} SOL"

    _recent_listings.appendleft(
        {
            "name": nft.get("name") or "Unknown NFT",
            "mint": nft.get("mint") or "Unknown",
            "price": amount_str,
            "marketplace": nft.get("marketplace") or "Unknown",
            "seller": nft.get("seller") or "Unknown",
            "signature": nft.get("signature") or "Unknown",
            "timestamp": str(timestamp),
            "image": nft.get("image"),
            "traits": nft.get("traits") or [],
            "collection": nft.get("collection"),
        }
    )


def _status_snapshot() -> Dict[str, Any]:
    volume_24h, sales_24h = _rolling_volume_24h()
    return {
        "sales_seen": _sales_seen,
        "sales_sent": _sales_sent,
        "last_event_time": _last_event_time or "No sales yet",
        "watch_sources": sorted(WATCH_SOURCES),
        "watch_mints_count": len(WATCH_MINTS),
        "mintlist_url": WATCH_MINTLIST_URL or "Not set",
        "volume_24h": volume_24h,
        "sales_24h": sales_24h,
    }


def _config_snapshot() -> Dict[str, Any]:
    return {
        "bot_token": _mask_value(TELEGRAM_BOT_TOKEN),
        "chat_id": TELEGRAM_CHAT_ID or "Not set",
        "watch_sources": ", ".join(sorted(WATCH_SOURCES)) or "Not set",
        "watch_mints_count": len(WATCH_MINTS),
        "mintlist_url": WATCH_MINTLIST_URL or "Not set",
        "webhook_path": "/webhook/helius",
        "helius_api_key": _mask_value(HELIUS_API_KEY),
        "tensor_collection_id": _mask_value(TENSOR_COLLECTION_ID),
        "howrare_api_key": _mask_value(HOWRARE_API_KEY),
        "send_listing_alerts": str(SEND_LISTING_ALERTS),
    }

def _enrich_metadata(nft: Dict[str, Any]) -> Dict[str, Any]:
    if nft.get("image") or nft.get("traits"):
        return nft
    mint = nft.get("mint")
    if not mint:
        return nft

    cached = _metadata_cache.get(mint)
    if cached:
        return {**nft, **cached}

    metadata = _fetch_metadata(mint)
    if metadata:
        _metadata_cache[mint] = metadata
        _metadata_cache_order.append(mint)
        if _metadata_cache_order.maxlen and len(_metadata_cache) > _metadata_cache_order.maxlen:
            while len(_metadata_cache) > _metadata_cache_order.maxlen:
                oldest = _metadata_cache_order.popleft()
                _metadata_cache.pop(oldest, None)
        return {**nft, **metadata}
    return nft


def _fetch_metadata(mint: str) -> Dict[str, Any]:
    if not HELIUS_API_KEY:
        return {}

    url = f"https://mainnet.helius-rpc.com/?api-key={HELIUS_API_KEY}"
    payload = json.dumps(
        {
            "jsonrpc": "2.0",
            "id": "1",
            "method": "getAsset",
            "params": {"id": mint},
        }
    ).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            data = json.load(response)
    except Exception as exc:
        logger.warning("Failed to fetch metadata for %s: %s", mint, exc)
        return {}

    result = (data or {}).get("result") if isinstance(data, dict) else None
    if not isinstance(result, dict):
        return {}

    content = result.get("content") or {}
    name = (result.get("content") or {}).get("metadata", {}).get("name") or content.get("metadata", {}).get("name")
    image = _extract_image_from_content(content)
    traits, collection = _extract_offchain_traits(content)

    return {
        "name": name,
        "image": image,
        "traits": traits,
        "collection": collection,
    }


def _extract_image_from_content(content: Dict[str, Any]) -> Optional[str]:
    links = content.get("links") or {}
    image = links.get("image") if isinstance(links, dict) else None

    files = content.get("files") or []
    if not image and isinstance(files, list) and files:
        first = files[0]
        if isinstance(first, dict):
            image = first.get("uri")
        elif isinstance(first, str):
            image = first

    image = _normalize_image_url(image)

    if not image:
        json_uri = content.get("json_uri")
        json_uri = _normalize_image_url(json_uri)
        if json_uri:
            try:
                with urllib.request.urlopen(json_uri, timeout=15) as response:
                    offchain = json.load(response)
                image = _normalize_image_url(offchain.get("image") or offchain.get("image_url"))
            except Exception as exc:
                logger.warning("Failed to fetch offchain JSON %s: %s", json_uri, exc)
                return None
    return image


def _extract_offchain_traits(content: Dict[str, Any]) -> Tuple[List[str], Optional[str]]:
    json_uri = content.get("json_uri")
    json_uri = _normalize_image_url(json_uri)
    if not json_uri:
        return [], None

    try:
        with urllib.request.urlopen(json_uri, timeout=15) as response:
            offchain = json.load(response)
    except Exception as exc:
        logger.warning("Failed to fetch traits from %s: %s", json_uri, exc)
        return [], None

    traits = []
    attributes = offchain.get("attributes") or []
    if isinstance(attributes, list):
        for attr in attributes[:4]:
            if not isinstance(attr, dict):
                continue
            trait_type = attr.get("trait_type") or attr.get("type")
            value = attr.get("value")
            if trait_type and value is not None:
                traits.append(f"{trait_type}: {value}")

    collection = offchain.get("collection", {}).get("name") if isinstance(offchain.get("collection"), dict) else offchain.get("collection")
    return traits, collection


def _normalize_image_url(url: Optional[str]) -> Optional[str]:
    if not url:
        return None
    if url.startswith("ipfs://"):
        return "https://ipfs.io/ipfs/" + url.replace("ipfs://", "").lstrip("/")
    if url.startswith("ar://"):
        return "https://arweave.net/" + url.replace("ar://", "").lstrip("/")
    return url


def _h(text: str) -> str:
    return html.escape(text or "")


def _shorten(value: str, left: int = 4, right: int = 4) -> str:
    if not value or value.startswith("Unknown"):
        return value
    if len(value) <= left + right + 3:
        return value
    return f"{value[:left]}…{value[-right:]}"


def _tensor_url(mint: str) -> str:
    if not mint or mint.startswith("Unknown"):
        return "https://www.tensor.trade/"
    return f"https://www.tensor.trade/item/{mint}"


def _solscan_url(mint: str, signature: str) -> str:
    if signature and not signature.startswith("Unknown"):
        return f"https://solscan.io/tx/{signature}"
    if mint and not mint.startswith("Unknown"):
        return f"https://solscan.io/token/{mint}"
    return "https://solscan.io/"


def _floor_snapshot() -> Dict[str, Any]:
    global _floor_cache_time, _floor_cache
    if not TENSOR_COLLECTION_ID:
        return {}
    now = datetime.now(timezone.utc).timestamp()
    if _floor_cache_time and now - _floor_cache_time < 60 and _floor_cache:
        return _floor_cache

    url = f"https://api.tensor.so/sol/collections/{TENSOR_COLLECTION_ID}/floor"
    try:
        with urllib.request.urlopen(url, timeout=15) as response:
            data = json.load(response)
    except Exception as exc:
        logger.warning("Failed to fetch Tensor floor: %s", exc)
        return {}

    price_lamports = data.get("price") if isinstance(data, dict) else None
    if not isinstance(price_lamports, (int, float)):
        return {}

    _floor_cache = {
        "price_sol": price_lamports / LAMPORTS_PER_SOL,
        "raw": data,
    }
    _floor_cache_time = now
    return _floor_cache


def _rarity_snapshot(mint: str) -> Dict[str, Any]:
    if not HOWRARE_API_KEY or not mint or mint.startswith("Unknown"):
        return {}
    now = time.time()
    cached = _rarity_cache.get(mint)
    if cached and now - _rarity_cache_time.get(mint, 0) < 3600:
        return cached

    url = f"https://api.howrare.is/v0.1/rarity/{mint}"
    req = urllib.request.Request(url, headers={"X-HOWRARE-API-KEY": HOWRARE_API_KEY})
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            data = json.load(response)
    except Exception as exc:
        logger.warning("Failed to fetch rarity for %s: %s", mint, exc)
        return {}

    result = (data or {}).get("result", {}) if isinstance(data, dict) else {}
    info = result.get("data") if isinstance(result, dict) else {}
    if not info:
        return {}

    rank = info.get("rank")
    total = len(WATCH_MINTS) if WATCH_MINTS else 10000
    percentile = (rank / total) * 100 if isinstance(rank, (int, float)) and total else None

    rarity = {
        "rank": rank,
        "percentile": percentile or 0,
    }
    _rarity_cache[mint] = rarity
    _rarity_cache_time[mint] = now
    return rarity


def _sale_tags(amount_lamports: Optional[float], floor_info: Dict[str, Any], buyer: Optional[str]) -> List[str]:
    tags: List[str] = []
    if isinstance(amount_lamports, (int, float)):
        price_sol = amount_lamports / LAMPORTS_PER_SOL
        if price_sol >= WHALE_SOL:
            tags.append("🐋 Whale")
        floor_sol = floor_info.get("price_sol") if floor_info else None
        if floor_sol:
            if price_sol <= floor_sol * 0.98:
                tags.append("🟢 Under Floor")
            elif price_sol >= floor_sol * 1.2:
                tags.append("🔥 Above Floor")
            else:
                tags.append("🟡 Near Floor")

    sweep = _detect_sweep(buyer)
    if sweep:
        tags.append(f"🧹 Sweep x{sweep}")
    return tags


def _detect_sweep(buyer: Optional[str]) -> int:
    if not buyer:
        return 0
    now = time.time()
    cutoff = now - SWEEP_WINDOW_SEC
    count = 0
    for ts, _, b in _sales_window:
        if ts >= cutoff and b == buyer:
            count += 1
    return count if count >= SWEEP_COUNT else 0


def _prune_sales_window() -> None:
    cutoff = time.time() - 86400
    while _sales_window and _sales_window[0][0] < cutoff:
        _sales_window.popleft()


def _rolling_volume_24h() -> Tuple[float, int]:
    cutoff = time.time() - 86400
    total = 0.0
    count = 0
    for ts, price, _ in _sales_window:
        if ts >= cutoff:
            total += price
            count += 1
    return round(total, 2), count


def _parse_event_time(value: Any) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return dt.timestamp()
        except Exception:
            return time.time()
    return time.time()


def _fake_sale() -> Tuple[Dict[str, Any], Dict[str, Any]]:
    mint = next(iter(sorted(WATCH_MINTS)), "SimMint111111111111111111111111111111111")
    timestamp = _current_time()
    event = {
        "type": "NFT_SALE",
        "source": "TENSOR",
        "timestamp": timestamp,
        "description": "Simulated Tensor sale for preview.",
        "events": {
            "nft": {
                "seller": "SimSeller11111111111111111111111111111111",
                "buyer": "SimBuyer1111111111111111111111111111111111",
                "amount": 12_340_000_000,
                "nfts": [
                    {
                        "mint": mint,
                        "name": "Galactic Gecko #4242",
                    }
                ],
            }
        },
    }

    nft = _extract_nft_info(event)
    return event, nft


def _fake_listing() -> Tuple[Dict[str, Any], Dict[str, Any]]:
    mint = next(iter(sorted(WATCH_MINTS)), "SimMint111111111111111111111111111111111")
    timestamp = _current_time()
    event = {
        "type": "NFT_LISTING",
        "source": "TENSOR",
        "timestamp": timestamp,
        "description": "Simulated Tensor listing for preview.",
        "events": {
            "nft": {
                "seller": "SimSeller11111111111111111111111111111111",
                "amount": 9_990_000_000,
                "nfts": [
                    {
                        "mint": mint,
                        "name": "Galactic Gecko #6060",
                    }
                ],
            }
        },
    }

    nft = _extract_nft_info(event)
    return event, nft


def _read_env() -> Dict[str, str]:
    if not ENV_PATH.exists():
        return {}
    data = {}
    for line in ENV_PATH.read_text().splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


def _write_env_updates(updates: Dict[str, str]) -> None:
    env = _read_env()
    for key, value in updates.items():
        env[key] = value
    lines = [f"{key}={value}" for key, value in sorted(env.items())]
    ENV_PATH.write_text("\n".join(lines) + ("\n" if lines else ""))


async def _apply_runtime_updates(updates: Dict[str, str]) -> None:
    global TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, ADMIN_USER, ADMIN_PASSWORD, HELIUS_API_KEY, TENSOR_COLLECTION_ID, HOWRARE_API_KEY, SEND_LISTING_ALERTS
    global WATCH_SOURCES, WATCH_MINTLIST_URL, WATCH_MINTS

    TELEGRAM_BOT_TOKEN = updates.get("TELEGRAM_BOT_TOKEN", TELEGRAM_BOT_TOKEN) or TELEGRAM_BOT_TOKEN
    TELEGRAM_CHAT_ID = updates.get("TELEGRAM_CHAT_ID", TELEGRAM_CHAT_ID) or TELEGRAM_CHAT_ID
    ADMIN_USER = updates.get("ADMIN_USER", ADMIN_USER) or ADMIN_USER
    ADMIN_PASSWORD = updates.get("ADMIN_PASSWORD", ADMIN_PASSWORD) or ADMIN_PASSWORD
    HELIUS_API_KEY = updates.get("HELIUS_API_KEY", HELIUS_API_KEY) or HELIUS_API_KEY
    TENSOR_COLLECTION_ID = updates.get("TENSOR_COLLECTION_ID", TENSOR_COLLECTION_ID) or TENSOR_COLLECTION_ID
    HOWRARE_API_KEY = updates.get("HOWRARE_API_KEY", HOWRARE_API_KEY) or HOWRARE_API_KEY
    if "SEND_LISTING_ALERTS" in updates:
        SEND_LISTING_ALERTS = updates.get("SEND_LISTING_ALERTS", "").strip().lower() in {"1", "true", "yes"}

    watch_sources = updates.get("WATCH_SOURCES")
    if watch_sources is not None:
        parsed = _parse_csv(watch_sources)
        WATCH_SOURCES = set(s.lower() for s in parsed) if parsed else {"tensor"}

    watch_mintlist_url = updates.get("WATCH_MINTLIST_URL")
    if watch_mintlist_url is not None:
        WATCH_MINTLIST_URL = watch_mintlist_url.strip()
        WATCH_MINTS = set(_parse_csv(os.getenv("WATCH_MINTS", "")))
        if WATCH_MINTLIST_URL:
            await _load_mintlist(WATCH_MINTLIST_URL)
