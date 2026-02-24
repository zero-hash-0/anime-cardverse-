import asyncio
import os

from dotenv import load_dotenv
from telegram import Bot

load_dotenv()

TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()


async def main() -> None:
    if not TOKEN:
        raise SystemExit("TELEGRAM_BOT_TOKEN is not set")

    bot = Bot(TOKEN)
    updates = await bot.get_updates()

    if not updates:
        print("No updates yet. Send a message to your bot first.")
        return

    seen = set()
    for update in updates:
        chat = update.effective_chat
        if not chat or chat.id in seen:
            continue
        seen.add(chat.id)
        print(f"chat_id={chat.id} type={chat.type} title={chat.title} username={chat.username}")


if __name__ == "__main__":
    asyncio.run(main())
