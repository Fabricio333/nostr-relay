#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Obelisk Nostr Relay — Start Script
#
# Usage:
#   ./start.sh          # Build and start the relay
#   ./start.sh stop     # Stop the relay
#   ./start.sh logs     # Tail relay logs
#   ./start.sh status   # Check if relay is running
#   ./start.sh restart  # Restart the relay
# ============================================================

RELAY_DIR="$(cd "$(dirname "$0")" && pwd)"
RELAY_DOMAIN="relay.obelisk.ar"
RELAY_PORT="8080"
OBELISK_DIR="/root/obelisk_repo"
CADDY_CONTAINER="obelisk_repo-caddy-1"

cd "$RELAY_DIR"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

# ── Commands ──────────────────────────────────────────────

case "${1:-start}" in
  stop)
    echo "Stopping relay..."
    docker compose down
    ok "Relay stopped."
    exit 0
    ;;
  logs)
    docker compose logs -f --tail=50 groups_relay
    exit 0
    ;;
  status)
    if docker compose ps --format json 2>/dev/null | grep -q '"running"'; then
      ok "Relay is running."
      docker compose ps
      echo ""
      if curl -sf --max-time 3 "http://localhost:${RELAY_PORT}/health" > /dev/null 2>&1; then
        ok "Health check passed."
      else
        fail "Health check failed (port ${RELAY_PORT} not responding)."
      fi
    else
      fail "Relay is not running."
    fi
    exit 0
    ;;
  restart)
    echo "Restarting relay..."
    docker compose down
    exec "$0" start
    ;;
  start) ;; # fall through
  *)
    echo "Usage: $0 {start|stop|logs|status|restart}"
    exit 1
    ;;
esac

# ── Pre-flight checks ────────────────────────────────────

echo "============================================"
echo "  Obelisk Nostr Relay — Starting Up"
echo "============================================"
echo ""

# Check Docker
if ! command -v docker &> /dev/null; then
  fail "Docker not found. Install Docker first."
  exit 1
fi
ok "Docker found."

# Check config
if [ ! -f config/settings.local.yml ]; then
  fail "config/settings.local.yml not found."
  echo "  Copy .env.example and config/settings.yml to get started."
  exit 1
fi
ok "Config found (config/settings.local.yml)."

# Count whitelisted pubkeys
PUBKEY_COUNT=$(grep -c '^\s*- "' config/settings.local.yml 2>/dev/null || echo "0")
ok "Whitelisted pubkeys: ${PUBKEY_COUNT}"

# ── Configure Caddy (if obelisk stack exists) ────────────

CADDY_BLOCK="
${RELAY_DOMAIN} {
	reverse_proxy host.docker.internal:${RELAY_PORT} {
		header_up Connection {>Connection}
		header_up Upgrade {>Upgrade}
	}
}
"

if [ -f "${OBELISK_DIR}/Caddyfile" ]; then
  if grep -q "${RELAY_DOMAIN}" "${OBELISK_DIR}/Caddyfile" 2>/dev/null; then
    ok "Caddy already configured for ${RELAY_DOMAIN}."
  else
    warn "Adding ${RELAY_DOMAIN} to Caddy config..."
    echo "$CADDY_BLOCK" >> "${OBELISK_DIR}/Caddyfile"
    ok "Added ${RELAY_DOMAIN} vhost to ${OBELISK_DIR}/Caddyfile."

    # Reload Caddy if running
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "${CADDY_CONTAINER}"; then
      docker exec "${CADDY_CONTAINER}" caddy reload --config /etc/caddy/Caddyfile 2>/dev/null && \
        ok "Caddy reloaded." || \
        warn "Could not reload Caddy — you may need to restart it manually."
    fi
  fi
else
  warn "Obelisk Caddyfile not found at ${OBELISK_DIR}/Caddyfile."
  warn "You'll need to set up a reverse proxy for ${RELAY_DOMAIN} → localhost:${RELAY_PORT} yourself."
fi

# ── Check DNS ─────────────────────────────────────────────

echo ""
echo "Checking DNS for ${RELAY_DOMAIN}..."
if command -v dig &> /dev/null; then
  DNS_RESULT=$(dig +short "${RELAY_DOMAIN}" 2>/dev/null)
  if [ -n "$DNS_RESULT" ]; then
    ok "DNS resolves: ${RELAY_DOMAIN} → ${DNS_RESULT}"
  else
    warn "DNS does not resolve for ${RELAY_DOMAIN}."
    warn "Add an A record pointing to this server's IP."
    warn "The relay will still start on localhost:${RELAY_PORT}."
  fi
else
  warn "dig not found — skipping DNS check."
fi

# ── Build and start ───────────────────────────────────────

echo ""
echo "Building and starting the relay..."
echo "(This may take a few minutes on first build)"
echo ""

docker compose up -d --build

echo ""

# ── Wait for health ───────────────────────────────────────

echo "Waiting for relay to be healthy..."
for i in $(seq 1 30); do
  if curl -sf --max-time 3 "http://localhost:${RELAY_PORT}/health" > /dev/null 2>&1; then
    echo ""
    ok "Relay is healthy!"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo ""
    fail "Relay did not become healthy in 90 seconds."
    echo "  Check logs: docker compose logs groups_relay"
    exit 1
  fi
  sleep 3
  echo -n "."
done

# ── Summary ───────────────────────────────────────────────

echo ""
echo "============================================"
echo "  Relay is running!"
echo "============================================"
echo ""
echo "  WebSocket:  ws://localhost:${RELAY_PORT}"
echo "  Health:     http://localhost:${RELAY_PORT}/health"
echo "  Metrics:    http://localhost:${RELAY_PORT}/metrics"
echo "  Web UI:     http://localhost:${RELAY_PORT}/"
echo ""
if dig +short "${RELAY_DOMAIN}" &>/dev/null 2>&1 && [ -n "$(dig +short "${RELAY_DOMAIN}" 2>/dev/null)" ]; then
  echo "  Public:     wss://${RELAY_DOMAIN}"
fi
echo ""
echo "  Logs:       ./start.sh logs"
echo "  Stop:       ./start.sh stop"
echo "  Status:     ./start.sh status"
echo ""
