# Solana NFT Sales Telegram Bot

Telegram bot that posts NFT sale events to a chat. It expects an enhanced webhook payload from Helius and filters for `NFT_SALE`.

## Quickstart

1. Create a bot with BotFather and copy the token.
2. Create and activate a virtualenv, then install deps:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

3. Create a `.env` file based on `.env.example` and fill in the values.
4. Start the webhook server:

```bash
uvicorn app.main:app --reload --port 8000
```

5. Expose your server (e.g., via a tunnel) and configure a Helius enhanced webhook to POST to:

```
https://<public-host>/webhook/helius
```

Set the webhook to use transaction type `NFT_SALE`, and include the NFT mint addresses you want to track.

## Utilities

- `scripts/get_chat_id.py` prints chat IDs after you message the bot.
- `scripts/send_test_message.py` sends a test message.

## Filtering

Set any of these in `.env`:

- `WATCH_MINTS`: comma-separated list of mint addresses to allow.
- `WATCH_MINTLIST_URL`: URL to a JSON mintlist (array of mint addresses). Loaded at startup and merged into `WATCH_MINTS`.
- `WATCH_SOURCES`: comma-separated list of marketplaces (e.g. `MAGICEDEN,TENSOR`). If omitted, defaults to `TENSOR`.
- `ADMIN_USER` and `ADMIN_PASSWORD`: required for Basic Auth access to `/dashboard`.
- `HELIUS_API_KEY`: used to fetch NFT images and traits for the UI and Telegram photo alerts.
- `TENSOR_COLLECTION_ID`: optional; used to fetch floor price for Telegram alerts.
- `HOWRARE_API_KEY`: optional; used for rarity badges in alerts.
- `WHALE_SOL`: SOL threshold to mark whale buys (default 50).
- `SWEEP_COUNT`: number of buys within the sweep window to mark a sweep.
- `SWEEP_WINDOW_SEC`: time window for sweep detection (seconds).
- `ALERT_GIF_URL`: optional GIF URL for whale/sweep/above-floor alerts.
- `SEND_LISTING_ALERTS`: set `true` to send Telegram alerts for new listings.

## Notes

- Helius webhooks can retry delivery, so the server keeps a small in-memory de-duplication cache.
- This service is stateless; restart clears the cache.

## Web UI

- `/` landing page
- `/dashboard` configuration view (Basic Auth protected)
- `/status` live status + recent sales
- `/api/status` JSON endpoint
- `/api/stream` Server-Sent Events stream

## Demo

Use the Dashboard button "Simulate sale" to add a fake sale to the status table and optionally send a test Telegram alert.
