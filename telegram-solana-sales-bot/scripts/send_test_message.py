import asyncio
import os

from dotenv import load_dotenv
from telegram import Bot

load_dotenv()

TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "").strip()


async def main() -> None:
    if not TOKEN or not CHAT_ID:
        raise SystemExit("TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is not set")

    bot = Bot(TOKEN)
    await bot.send_message(chat_id=CHAT_ID, text="Test message from your Solana sales bot.")
    print("Sent.")


if __name__ == "__main__":
    asyncio.run(main())
