# Barq-e Man Telegram Bot

A Bash-based Telegram bot that tracks and notifies users about planned and current electricity outages using the [Barq-e Man](https://bargheman.com) service. It supports user subscription management, periodic checks, and uses a Telegram webhook for interaction.

## Features

- Integrates with the **Barq-e Man** blackout APIs
- Telegram bot with basic command handling:
  - `/start` – Greets the user
  - `/add <bill_id>` – Subscribes a user to outage alerts for a bill
  - `/remove <bill_id>` – Unsubscribes a user
  - `/list` – (Planned) Lists all bill IDs the user is subscribed to
- Uses `proxychains` and `serveo.net` for webhook tunneling
- JSON-based persistent data storage
- Auto-installs as a systemd service with `install` argument

## Requirements

- `bash` (v4+)
- `jq`
- `netcat`
- `curl`
- `proxychains`
- `tor` (or other socks4/socks5 proxies)
- `ssh`
- `python3`
- Python package: `jdatetime`

### Install Python Requirements

```bash
pip install jdatetime
```

## Setup

### 1. Create `.env` File

Create a `.env` file in the project root directory with the following contents:

```env
BOT_TOKEN=<your_telegram_bot_token>
BARQ_TOKEN=<your_barq_e_man_api_token>
BOT_WEBHOOK_URL=<optional_webhook_url>
PORT=8080
```

### 2. Install as a systemd Service

```bash
bash bot.sh install
```

This creates and enables a systemd service to run the bot in the background.

### 3. Run Manually (Optional)

To run the bot without installing as a service:

```bash
bash bot.sh
```

## Data Storage

The script uses a `data.json` file to store:

- User subscriptions (bill IDs)
- Last alerts sent per user

If the file does not exist, it will be created automatically.

## Telegram Commands

Users can interact with the bot using these commands:

- `/start` – Greeting message
- `/add <bill_id>` – Add subscription
- `/remove <bill_id>` – Remove subscription
- `/list` – *(coming soon)* View subscriptions

## Notes

- Webhook functionality uses an SSH tunnel via `serveo.net`, which may reconnect intermittently.
- All HTTP requests are routed through `proxychains`, so ensure your proxy configuration is working correctly.
- The `.env` file is used to configure bot tokens and webhook settings. If `BOT_WEBHOOK_URL` is set, the bot will use this address as the webhook endpoint. If it's not set, the bot will automatically create a temporary webhook using `serveo.net`. The second option (Use `serveo.net`) is good for run bot locally in your PC, RaspberryPi, Termux (on android devices) or ...

## License

This project is licensed under the MIT License.
