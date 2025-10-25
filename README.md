# Fr0g Blockchain Node

This repository contains a simple way to run a Fr0g blockchain node using Docker Compose.
With this setup, you can easily validate transactions and participate in the Fr0g network.

# Prerequisites
- Docker Compose
- Fr0g Account. Ensure your account has registered as a block producer. For example with 'cleos regproducer <your_account_name>'.

# Startup

Edit the 'example.env' file with details and rename it to '.env'.

Then run the following command to start the node:

```bash
docker compose down && docker compose build && docker compose up -d && docker compose logs -f
```