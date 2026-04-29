# CLAUDE.md — Obelisk Nostr Relay

This is the **Obelisk NIP-29 Groups Relay** — a whitelisted Nostr relay for relay-based group chat, forked from [verse-pbc/groups_relay](https://github.com/verse-pbc/groups_relay) and customized for the Obelisk ecosystem.

Production URL: `wss://relay.obelisk.ar`

## What This Relay Does

A NIP-29 relay manages **group chats at the relay level**. Unlike regular Nostr relays that just store and forward events, this relay:

- **Enforces group membership** — only members can post to a group
- **Manages roles** — admin, moderator, member with different permissions
- **Controls visibility** — private groups are only readable by members
- **Handles invites** — invite codes with expiration and usage limits
- **Whitelists pubkeys** — only approved Nostr identities can connect at all

## Architecture

```
Internet → Caddy (:443, HTTPS) → relay container (:8080)
                                    ├── Axum HTTP server
                                    │   ├── WebSocket upgrade → Nostr protocol
                                    │   ├── /health
                                    │   ├── /metrics (Prometheus)
                                    │   └── / (Preact frontend)
                                    ├── GroupsRelayProcessor (NIP-29 logic)
                                    ├── ValidationMiddleware (event validation)
                                    └── nostr-lmdb (LMDB database)
```

### Core Components

| File | Lines | Purpose |
|------|-------|---------|
| `src/main.rs` | 163 | Entry point, Tokio runtime setup, CLI args |
| `src/server.rs` | 224 | Axum router, WebSocket handler, relay builder setup |
| `src/groups_event_processor.rs` | 422 | **Main brain** — NIP-29 business logic, whitelist enforcement |
| `src/groups.rs` | 2078 | Group state management, DashMap with scoped storage |
| `src/group.rs` | 3189 | Individual group logic — metadata, members, roles, permissions |
| `src/validation_middleware.rs` | 131 | Validates events have required tags (h-tag for groups) |
| `src/config.rs` | 138 | Config loading from YAML + env vars |
| `src/handler.rs` | 143 | HTTP handlers (health, metrics, frontend) |
| `src/metrics.rs` | 239 | Prometheus metrics collection |

### Event Processing Flow

```
Client sends EVENT → WebSocket
  → ValidationMiddleware (checks h-tag, basic structure)
  → GroupsRelayProcessor.handle_event()
    → is_allowed() — whitelist check
    → Route by event kind:
        9007 → create group
        9000 → add user
        9001 → remove user
        9002 → edit metadata
        9005 → delete event
        9006 → set roles
        9009 → create invite
        9021 → join request
        9022 → leave request
        other → group content (if h-tag present)
    → StoreCommand(s) → nostr-lmdb
  → Broadcast to subscribers
```

### Whitelist Mechanism

The relay enforces a pubkey whitelist defined in `config/settings.local.yml`:

```yaml
whitelisted_pubkeys:
  - "hex_pubkey_1"  # Only these can connect
  - "hex_pubkey_2"
```

**How it works** (`src/groups_event_processor.rs`):
- `is_allowed()` checks if the authenticated pubkey is in the whitelist
- Empty whitelist = no restriction (all pubkeys allowed)
- Relay's own pubkey always has access
- Enforced at both `verify_filters()` (read) and `handle_event()` (write)
- Requires NIP-42 authentication when whitelist is active

### Current Whitelisted Pubkeys (3)

| npub | Hex |
|------|-----|
| `npub1m9vsm9d8sy0pevcjhenwm4ny6l37dm2hsg4dnusna43ql3n5305qy4zlg4` | `d9590d95...` (owner) |
| `npub1gxdhmu9swqduwhr6zptjy4ya693zp3ql28nemy4hd97kuufyrqdqwe5zfk` | `419b7df0...` |
| `npub1ur853z967pvl8mnzglzvedgnzqsznkmzeuw7rvzw0dappfvke53srvd97k` | `e0cf4888...` |

To add a new pubkey: edit `config/settings.local.yml`, add the hex pubkey, restart the container.

## NIP-29 Event Kinds

| Kind | Name | Who Can Send |
|------|------|-------------|
| 9000 | Add user to group | Admin |
| 9001 | Remove user from group | Admin |
| 9002 | Edit group metadata | Admin |
| 9005 | Delete event from group | Admin/Moderator |
| 9006 | Set roles | Admin |
| 9007 | Create group | Any whitelisted user |
| 9008 | Delete group | Admin |
| 9009 | Create invite | Admin |
| 9021 | Join request | Any whitelisted user |
| 9022 | Leave request | Group member |
| 39000 | Group metadata (replaceable) | Relay |
| 39001 | Group admins (replaceable) | Relay |
| 39002 | Group members (replaceable) | Relay |
| 39003 | Group roles (replaceable) | Relay |

## Group Types

- **Public/Private** — Private groups require membership to read events
- **Open/Closed** — Open groups auto-accept join requests; closed require admin approval
- **Broadcast** — Only admins can post content; members can only join/leave

## Configuration

Config is loaded in priority order (later overrides earlier):
1. `config/settings.yml` — defaults
2. `config/settings.local.yml` — production overrides (whitelist, keys, URL)
3. Environment variables with `NIP29__` prefix

Key settings in `config/settings.local.yml`:
```yaml
relay:
  relay_secret_key: "hex_private_key"
  relay_url: "wss://relay.obelisk.ar"
  local_addr: "0.0.0.0:8080"
  db_path: "/app/db"
  whitelisted_pubkeys: [...]
  max_subscriptions: 50
  max_limit: 500
  websocket:
    max_connection_duration: "24h"
    idle_timeout: "30m"
    max_connections: 300
```

## Development Commands

```bash
just test              # Run all tests
just test-name <name>  # Run specific test
just run               # Debug mode
just run-debug         # Debug with verbose logging
just build-release     # Production build
just fmt               # Format code
just clippy            # Lint
just check             # Format + clippy + tests
just bench             # Benchmarks
```

## Docker Deployment

```bash
# Build and start
docker compose up -d --build

# Check health
curl http://localhost:8080/health

# View logs
docker compose logs -f groups_relay

# Stop
docker compose down
```

The relay listens on port 8080. Caddy (in the obelisk stack) reverse-proxies `relay.obelisk.ar` → `localhost:8080` with WebSocket support.

## Frontend

Preact-based web UI in `frontend/`:
- 37 TypeScript components
- NDK for Nostr protocol
- Cashu wallet integration (NIP-60/61)
- Tailwind CSS styling
- Built with Vite, served by the relay at `/`

## Database

Uses **nostr-lmdb** with scoped storage for multi-tenant subdomain support. Data stored in Docker volume `relay-db` mounted at `/app/db`.

Included utilities (in Docker image):
- `nostr-lmdb-dump` — export database
- `nostr-lmdb-integrity` — check integrity
- `export_import` — export/import relay data
- `negentropy_sync` — relay-to-relay sync

## Tech Stack

- **Rust** (Tokio async runtime, Axum web framework)
- **relay_builder** + **websocket_builder** — Nostr relay framework by verse-pbc
- **nostr-sdk** — Nostr protocol implementation
- **nostr-lmdb** — LMDB database with scoped storage
- **Preact** + **TypeScript** — Frontend
- **Docker** — Deployment

## Upstream

Forked from [verse-pbc/groups_relay](https://github.com/verse-pbc/groups_relay). Our customizations:
- Pubkey whitelist in `config/settings.local.yml`
- Production config for `wss://relay.obelisk.ar`
- `start.sh` launcher script
- Roadmap for admin panel with Nostr authentication
