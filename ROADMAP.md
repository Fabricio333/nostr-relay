# ROADMAP.md — Obelisk Nostr Relay

## Current State (v0.1)

What's working:
- [x] NIP-29 groups relay (all event kinds 9000-9009, 9021-9022, 39000-39003)
- [x] Group types: public/private, open/closed, broadcast
- [x] Role-based permissions (admin, moderator, member)
- [x] Join requests and invite codes
- [x] Pubkey whitelist (config-based)
- [x] Preact web UI with group management
- [x] Cashu wallet integration (NIP-60/61)
- [x] Docker deployment with health checks
- [x] Prometheus metrics
- [x] LMDB storage with scoped multi-tenant support

What's configured but not yet live:
- [ ] Caddy vhost for `relay.obelisk.ar`
- [ ] DNS record for `relay.obelisk.ar`
- [ ] Production deployment on the Obelisk server

---

## v0.2 — Admin Panel (Nostr-Authenticated)

### Overview

A web-based admin panel where relay operators manage the relay **using their Nostr identity** for authentication. No separate login system — you sign in with NIP-07 (browser extension) or NIP-46 (bunker), and the relay checks if your pubkey is in the admin list.

### Features

#### Authentication
- [ ] **NIP-07 login** — Sign admin challenge with browser extension (nos2x, Alby, etc.)
- [ ] **NIP-46 bunker login** — Remote signer support with QR code
- [ ] **Admin pubkey list** — Configurable list of pubkeys with admin access (separate from whitelist)
- [ ] **Session management** — Short-lived sessions with re-authentication

#### Whitelist Management
- [ ] **View whitelisted pubkeys** — List all with npub, hex, and profile info (fetched from other relays)
- [ ] **Add pubkey** — Add by npub or hex, with optional note/label
- [ ] **Remove pubkey** — Remove with confirmation, shows active group memberships
- [ ] **Bulk import** — Paste a list of npubs to add
- [ ] **Hot reload** — Apply whitelist changes without relay restart

#### Content Moderation
- [ ] **Event browser** — Search and browse all stored events by kind, pubkey, group, time
- [ ] **Event inspector** — View full event JSON, tags, signatures
- [ ] **Delete event** — Remove specific events (sends kind 9005 as relay)
- [ ] **Delete by filter** — Bulk delete by pubkey, kind, group, or time range
- [ ] **Content reports** — View flagged content (NIP-56 reports)
- [ ] **Moderation log** — Full audit trail of all admin actions

#### User Management
- [ ] **User directory** — All pubkeys that have interacted with the relay
- [ ] **User profile** — Events published, groups joined, last seen, storage used
- [ ] **Ban user** — Block pubkey from connecting (different from whitelist removal)
- [ ] **Mute user** — Prevent publishing but allow reading
- [ ] **User activity timeline** — Chronological view of a user's actions

#### Group Management
- [ ] **Group list** — All groups with member count, message count, last activity
- [ ] **Group details** — Full metadata, member list, role assignments
- [ ] **Edit group** — Change metadata, privacy settings, broadcast mode
- [ ] **Delete group** — Remove group and all associated events
- [ ] **Transfer ownership** — Change group admin
- [ ] **Force add/remove members** — Override normal permission checks

#### Relay Health
- [ ] **Dashboard** — Connection count, events/sec, storage size, uptime
- [ ] **Metrics graphs** — Prometheus data visualized (or link to Grafana)
- [ ] **Connection inspector** — Active WebSocket connections with pubkey, subscriptions, duration
- [ ] **Database stats** — Event count by kind, storage per group, growth rate

### Technical Approach

The admin panel will be built as part of the existing Preact frontend with admin-only routes:

```
/admin              → Dashboard
/admin/whitelist    → Whitelist management
/admin/users        → User directory
/admin/groups       → Group management
/admin/events       → Event browser
/admin/moderation   → Moderation log
/admin/health       → Relay health
```

Backend: New Axum API routes under `/api/admin/*` that:
1. Require NIP-42 authentication
2. Verify the authenticated pubkey is in the admin list
3. Return JSON responses consumed by the Preact frontend

The admin list is separate from the whitelist — you can be whitelisted (allowed to use the relay) without being an admin (allowed to manage it).

---

## v0.3 — Dynamic Whitelist via Nostr Events

Instead of a static config file, manage the whitelist through Nostr events:

- [ ] **Whitelist event kind** — Define a custom replaceable event kind for whitelist management
- [ ] **Relay-signed whitelist** — Relay publishes the current whitelist as a Nostr event
- [ ] **Admin commands via DM** — Send encrypted DMs to the relay to add/remove pubkeys
- [ ] **Whitelist sync** — Multiple relays can share a whitelist via Nostr events

---

## v0.4 — Web of Trust Integration

Leverage Nostr's social graph for automated trust decisions:

- [ ] **WoT-based auto-whitelist** — Automatically whitelist pubkeys within N degrees of existing members
- [ ] **Trust scores** — Display WoT distance in admin panel
- [ ] **Vouching system** — Whitelisted users can vouch for others (with configurable limits)
- [ ] **Integration with nostr-wot** — Use the WoT toolkit from the Obelisk ecosystem

---

## v0.5 — Obelisk Integration

Deep integration with the Obelisk chat platform:

- [ ] **Obelisk as NIP-29 client** — Obelisk servers can use this relay for group persistence
- [ ] **Shared identity** — Same Nostr login for both Obelisk and the relay admin panel
- [ ] **Cross-platform moderation** — Actions in Obelisk reflect on the relay and vice versa
- [ ] **Relay status in Obelisk** — Show relay health/connection status in the Obelisk UI

---

## v0.6 — Advanced Features

- [ ] **Rate limiting** — Per-pubkey event rate limits
- [ ] **Storage quotas** — Per-user or per-group storage limits
- [ ] **Event expiration** — Auto-delete events after configurable TTL
- [ ] **Paid relay** — Lightning/Cashu payments for access (NIP-11 limitations)
- [ ] **Relay federation** — Sync groups between multiple relay instances via negentropy
- [ ] **Custom event kinds** — Allow relay operators to define accepted event kinds
- [ ] **Backup/restore UI** — One-click database backup and restore from admin panel
- [ ] **Webhook notifications** — HTTP webhooks for relay events (new user, new group, moderation action)

---

## Contributing

This relay is maintained as part of the Obelisk ecosystem. To contribute:

1. Fork [fabricio333/nostr-relay](https://github.com/fabricio333/nostr-relay)
2. Create a feature branch
3. Run `just check` (format + lint + tests)
4. Submit a PR

For the admin panel (v0.2), the main work areas are:
- `src/handler.rs` — Add admin API routes
- `src/server.rs` — Register admin routes with auth middleware
- `frontend/src/components/admin/` — New Preact admin components
- `config/settings.local.yml` — Add `admin_pubkeys` config field
