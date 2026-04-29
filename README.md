# Nostr Groups Relay

A [NIP-29](https://github.com/nostr-protocol/nips/blob/master/29.md) relay for group chats on Nostr, with pubkey whitelisting and role-based permissions.

Forked from [verse-pbc/groups_relay](https://github.com/verse-pbc/groups_relay).

## Quick Start

```bash
git clone https://github.com/fabricio333/nostr-relay.git
cd nostr-relay
./setup.sh
```

That's it. The setup wizard will walk you through everything:

1. Checks Docker is installed
2. Asks for your relay domain
3. Asks for your admin npub
4. Lets you add whitelisted pubkeys
5. Generates config and starts the relay

## What It Does

- **NIP-29 groups** — Create and manage group chats at the relay level
- **Pubkey whitelist** — Only approved Nostr identities can connect
- **Roles & permissions** — Admin, moderator, member with different access levels
- **Private groups** — Content only visible to members
- **Invite codes** — Share time-limited invite links
- **Web UI** — Built-in Preact frontend at the relay URL
- **Cashu wallet** — NIP-60/61 micropayment support

## Management

```bash
./start.sh status    # Is it running?
./start.sh logs      # View relay logs
./start.sh restart   # Restart after config changes
./start.sh stop      # Stop the relay
```

## Configuration

Edit `config/settings.local.yml` to change settings:

```yaml
relay:
  relay_url: "wss://relay.yourdomain.com"
  whitelisted_pubkeys:
    - "hex_pubkey_here"
```

Restart after changes: `./start.sh restart`

## Supported NIPs

- NIP-29 (Relay-based Groups) — all event kinds
- NIP-09 (Event Deletion)
- NIP-40 (Expiration Timestamp)
- NIP-42 (Authentication)
- NIP-70 (Protected Events)

## Roadmap

See [ROADMAP.md](ROADMAP.md) — includes a Nostr-authenticated admin panel for content moderation.

## Architecture

See [CLAUDE.md](CLAUDE.md) for full architecture docs and [AGENTS.md](AGENTS.md) for the internal processing pipeline.

## License

[AGPL](LICENSE)
