#!/usr/bin/env bash
set -euo pipefail

# ╔══════════════════════════════���═══════════════════════════════╗
# ║          Nostr Relay — Interactive Setup Wizard              ║
# ║                                                              ║
# ║  Run this once after cloning. It will:                       ��
# ║    1. Check prerequisites (Docker, ports)                    ║
# ║    2. Configure your relay domain & admin npub               ║
# ║    3. Generate relay keys                                    ║
# ║    4. Add whitelisted pubkeys                                ║
# ║    5. Build & start the relay                                ║
# ║                                                              ║
# ║  Usage:  ./setup.sh                                          ║
# ╚══════════���══════════════════════════════���════════════════════╝

RELAY_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${RELAY_DIR}/config"
CONFIG_FILE="${CONFIG_DIR}/settings.local.yml"

cd "$RELAY_DIR"

# ── Colors & formatting ──��───────────────────────────────────

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Box drawing
BOX_TL='╭' BOX_TR='╮' BOX_BL='╰' BOX_BR='╯'
BOX_H='─' BOX_V='│'

banner() {
  local text="$1"
  local len=${#text}
  local pad=$(( (56 - len) / 2 ))
  local right_pad=$(( 56 - len - pad ))
  echo ""
  echo -e "${CYAN}${BOX_TL}$(printf '%0.s─' $(seq 1 58))${BOX_TR}${NC}"
  echo -e "${CYAN}${BOX_V}${NC}$(printf '%*s' $pad '')${BOLD}${text}${NC}$(printf '%*s' $right_pad '')${CYAN}${BOX_V}${NC}"
  echo -e "${CYAN}${BOX_BL}$(printf '%0.s─' $(seq 1 58))${BOX_BR}${NC}"
  echo ""
}

section() {
  echo ""
  echo -e "${MAGENTA}━━━ ${BOLD}$1${NC} ${MAGENTA}$(printf '%0.s━' $(seq 1 $(( 52 - ${#1} ))))${NC}"
  echo ""
}

ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}!${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; }
info()  { echo -e "  ${DIM}$1${NC}"; }
ask()   { echo -en "  ${CYAN}?${NC} ${BOLD}$1${NC} "; }

# Prompt with default value
prompt_default() {
  local prompt_text="$1"
  local default="$2"
  local var_name="$3"
  ask "${prompt_text} ${DIM}[${default}]${NC}: "
  read -r input
  eval "${var_name}=\"${input:-$default}\""
}

# Yes/no prompt
prompt_yn() {
  local prompt_text="$1"
  local default="${2:-y}"
  local yn_hint
  if [ "$default" = "y" ]; then yn_hint="Y/n"; else yn_hint="y/N"; fi
  ask "${prompt_text} ${DIM}[${yn_hint}]${NC}: "
  read -r input
  input="${input:-$default}"
  case "$input" in
    [yY]*) return 0 ;;
    *) return 1 ;;
  esac
}

# ── Bech32 decode (npub → hex) ────────────────────────────────
# Pure bash bech32 decoder — no external tools needed

BECH32_CHARSET="qpzry9x8gf2tvdw0s3jn54khce6mua7l"

bech32_polymod() {
  local -a values=("$@")
  local chk=1
  local -a generator=(0x3b6a57b2 0x26508e6d 0x1ea119fa 0x3d4233dd 0x2a1462b3)
  for v in "${values[@]}"; do
    local top=$(( (chk >> 25) ))
    chk=$(( ((chk & 0x1ffffff) << 5) ^ v ))
    for i in 0 1 2 3 4; do
      if (( (top >> i) & 1 )); then
        chk=$(( chk ^ ${generator[$i]} ))
      fi
    done
  done
  echo "$chk"
}

bech32_hrp_expand() {
  local hrp="$1"
  local -a result=()
  for (( i=0; i<${#hrp}; i++ )); do
    result+=( $(( $(printf '%d' "'${hrp:$i:1}") >> 5 )) )
  done
  result+=( 0 )
  for (( i=0; i<${#hrp}; i++ )); do
    result+=( $(( $(printf '%d' "'${hrp:$i:1}") & 31 )) )
  done
  echo "${result[@]}"
}

npub_to_hex() {
  local npub="$1"

  # Validate prefix
  if [[ ! "$npub" =~ ^npub1 ]]; then
    echo ""
    return 1
  fi

  # Decode bech32 data part
  local data_part="${npub:5}"  # skip "npub1"
  local -a data5=()

  for (( i=0; i<${#data_part}; i++ )); do
    local ch="${data_part:$i:1}"
    local idx=-1
    for (( j=0; j<${#BECH32_CHARSET}; j++ )); do
      if [ "${BECH32_CHARSET:$j:1}" = "$ch" ]; then
        idx=$j
        break
      fi
    done
    if [ $idx -eq -1 ]; then
      echo ""
      return 1
    fi
    data5+=( $idx )
  done

  # Remove the 6-character checksum
  local data_len=$(( ${#data5[@]} - 6 ))
  if [ $data_len -le 0 ]; then
    echo ""
    return 1
  fi

  # Convert from 5-bit to 8-bit groups
  local acc=0
  local bits=0
  local hex=""

  for (( i=0; i<data_len; i++ )); do
    acc=$(( (acc << 5) | ${data5[$i]} ))
    bits=$(( bits + 5 ))
    while [ $bits -ge 8 ]; do
      bits=$(( bits - 8 ))
      local byte=$(( (acc >> bits) & 0xff ))
      hex+=$(printf '%02x' $byte)
    done
  done

  # A valid nostr pubkey is 32 bytes = 64 hex chars
  if [ ${#hex} -eq 64 ]; then
    echo "$hex"
    return 0
  else
    echo ""
    return 1
  fi
}

# Convert hex to npub for display
hex_to_npub_display() {
  local hex="$1"
  echo "${hex:0:8}...${hex: -8}"
}

# Validate a pubkey input (npub or hex) and return hex
validate_pubkey() {
  local input="$1"

  # Remove whitespace
  input="$(echo "$input" | tr -d '[:space:]')"

  # If it's an npub
  if [[ "$input" =~ ^npub1 ]]; then
    local hex
    hex=$(npub_to_hex "$input")
    if [ -n "$hex" ]; then
      echo "$hex"
      return 0
    else
      echo ""
      return 1
    fi
  fi

  # If it's already hex (64 chars, 0-9a-f)
  if [[ "$input" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "${input,,}"  # lowercase
    return 0
  fi

  echo ""
  return 1
}

# Generate a random 32-byte hex key
generate_hex_key() {
  if command -v openssl &>/dev/null; then
    openssl rand -hex 32
  elif [ -r /dev/urandom ]; then
    head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
  else
    # Fallback: use $RANDOM (not cryptographically secure, but works)
    local key=""
    for i in $(seq 1 32); do
      key+=$(printf '%02x' $(( RANDOM % 256 )))
    done
    echo "$key"
  fi
}


# ══════════════════════════════════════════════════════════════
#  START OF WIZARD
# ═════════════��════════════════════���═══════════════════════════

clear 2>/dev/null || true

banner "Nostr Relay — Setup Wizard"

echo -e "  Welcome! This wizard will configure your NIP-29 groups relay."
echo -e "  It takes about ${BOLD}2 minutes${NC} and then your relay will be live."
echo ""
echo -e "  ${DIM}You can re-run this wizard anytime to change settings.${NC}"
echo -e "  ${DIM}Press Ctrl+C at any point to cancel.${NC}"

# ── Step 1: Prerequisites ─────────────��──────────────────────

section "Step 1/5 — Checking Prerequisites"

# Docker
if command -v docker &>/dev/null; then
  DOCKER_VER=$(docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
  ok "Docker ${DOCKER_VER}"
else
  fail "Docker is not installed."
  echo ""
  echo "  Install Docker first:"
  echo "    curl -fsSL https://get.docker.com | sh"
  echo ""
  exit 1
fi

# Docker Compose
if docker compose version &>/dev/null; then
  COMPOSE_VER=$(docker compose version --short 2>/dev/null)
  ok "Docker Compose ${COMPOSE_VER}"
else
  fail "Docker Compose plugin not found."
  echo "  Install with: apt install docker-compose-plugin"
  exit 1
fi

# Port 8080
if command -v ss &>/dev/null; then
  if ss -tlnp 2>/dev/null | grep -q ':8080 '; then
    warn "Port 8080 is already in use. The relay may fail to start."
    info "Check with: ss -tlnp | grep 8080"
  else
    ok "Port 8080 is available"
  fi
fi

# Disk space
DISK_AVAIL=$(df -BG . 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G')
if [ -n "$DISK_AVAIL" ] && [ "$DISK_AVAIL" -gt 2 ]; then
  ok "Disk space: ${DISK_AVAIL}GB available"
else
  warn "Low disk space (${DISK_AVAIL:-?}GB). Need at least 2GB for Docker build."
fi

# ── Step 2: Relay Domain ─────────────────────────────────────

section "Step 2/5 — Relay Domain"

echo -e "  Your relay needs a domain name so Nostr clients can connect."
echo -e "  ${DIM}Examples: relay.yourdomain.com, nostr.example.org${NC}"
echo ""

prompt_default "Relay domain" "localhost" RELAY_DOMAIN

if [ "$RELAY_DOMAIN" = "localhost" ]; then
  RELAY_URL="ws://localhost:8080"
  RELAY_SCHEME="ws"
  warn "Using localhost — relay will only be accessible locally."
  info "You can change this later in config/settings.local.yml"
else
  RELAY_URL="wss://${RELAY_DOMAIN}"
  RELAY_SCHEME="wss"
  ok "Relay URL: ${RELAY_URL}"

  # Check DNS
  if command -v dig &>/dev/null; then
    DNS=$(dig +short "$RELAY_DOMAIN" 2>/dev/null)
    if [ -n "$DNS" ]; then
      ok "DNS resolves to: ${DNS}"
    else
      warn "DNS not set up yet for ${RELAY_DOMAIN}"
      info "Add an A record pointing to this server's public IP"
      if command -v curl &>/dev/null; then
        PUBLIC_IP=$(curl -sf --max-time 3 https://ifconfig.me 2>/dev/null || echo "")
        if [ -n "$PUBLIC_IP" ]; then
          info "This server's IP: ${PUBLIC_IP}"
        fi
      fi
    fi
  fi
fi

echo ""
echo -e "  ${DIM}Tip: You'll also need a reverse proxy (Caddy, nginx) to handle"
echo -e "  TLS and forward wss:// traffic to localhost:8080.${NC}"

# ── Step 3: Admin pubkey ──���──────────────────────��───────────

section "Step 3/5 — Admin Pubkey"

echo -e "  Your admin pubkey controls the relay. It will be:"
echo -e "    • Whitelisted to connect"
echo -e "    • Able to create and manage groups"
echo -e "    • The relay operator identity"
echo ""
echo -e "  ${DIM}Paste your npub (starts with npub1...) or hex pubkey (64 chars).${NC}"
echo -e "  ${DIM}Find your npub in your Nostr client's profile settings.${NC}"
echo ""

ADMIN_HEX=""
while [ -z "$ADMIN_HEX" ]; do
  ask "Admin npub or hex pubkey: "
  read -r admin_input

  if [ -z "$admin_input" ]; then
    warn "Pubkey is required. The relay needs at least one admin."
    continue
  fi

  ADMIN_HEX=$(validate_pubkey "$admin_input") || true

  if [ -z "$ADMIN_HEX" ]; then
    fail "Invalid pubkey format."
    echo ""
    info "npub should be 63 characters starting with npub1..."
    info "hex should be exactly 64 hex characters (0-9, a-f)"
    echo ""
  else
    ok "Admin pubkey: ${ADMIN_HEX:0:16}...${ADMIN_HEX: -8}"
    if [[ "$admin_input" =~ ^npub1 ]]; then
      ADMIN_NPUB="$admin_input"
      info "npub: ${admin_input:0:20}...${admin_input: -6}"
    else
      ADMIN_NPUB=""
    fi
  fi
done

# ── Step 4: Additional whitelisted pubkeys ────────────────────

section "Step 4/5 — Whitelist"

echo -e "  Add more pubkeys that can connect to your relay."
echo -e "  ${DIM}You can always add more later via config/settings.local.yml${NC}"
echo -e "  ${DIM}or through the admin panel (coming soon).${NC}"
echo ""

declare -a EXTRA_PUBKEYS=()
declare -a EXTRA_NPUBS=()

while true; do
  if [ ${#EXTRA_PUBKEYS[@]} -eq 0 ]; then
    if ! prompt_yn "Add more whitelisted pubkeys?" "n"; then
      break
    fi
  else
    ok "${#EXTRA_PUBKEYS[@]} extra pubkey(s) added"
    if ! prompt_yn "Add another?" "n"; then
      break
    fi
  fi

  echo ""
  ask "npub or hex pubkey: "
  read -r extra_input

  if [ -z "$extra_input" ]; then
    continue
  fi

  extra_hex=$(validate_pubkey "$extra_input") || true

  if [ -z "$extra_hex" ]; then
    fail "Invalid pubkey. Skipping."
  elif [ "$extra_hex" = "$ADMIN_HEX" ]; then
    warn "That's your admin pubkey — already included."
  else
    EXTRA_PUBKEYS+=("$extra_hex")
    if [[ "$extra_input" =~ ^npub1 ]]; then
      EXTRA_NPUBS+=("$extra_input")
    else
      EXTRA_NPUBS+=("")
    fi
    ok "Added: ${extra_hex:0:16}...${extra_hex: -8}"
  fi
done

# ── Step 5: Generate relay key & write config ─────────────────

section "Step 5/5 — Generating Config"

echo -e "  Generating relay identity key..."
RELAY_SECRET_KEY=$(generate_hex_key)
ok "Relay secret key generated"

# Build the YAML config
{
  cat <<YAML
relay:
  relay_secret_key: "${RELAY_SECRET_KEY}"
  relay_url: "${RELAY_URL}"
  db_path: "/app/db"
  local_addr: "0.0.0.0:8080"

  # Whitelisted pubkeys (hex) — only these can connect
  whitelisted_pubkeys:
YAML

  # Admin pubkey
  if [ -n "$ADMIN_NPUB" ]; then
    echo "    # ${ADMIN_NPUB} (admin)"
  else
    echo "    # Admin"
  fi
  echo "    - \"${ADMIN_HEX}\""

  # Extra pubkeys
  for i in "${!EXTRA_PUBKEYS[@]}"; do
    npub="${EXTRA_NPUBS[$i]}"
    hex="${EXTRA_PUBKEYS[$i]}"
    if [ -n "$npub" ]; then
      echo "    # ${npub}"
    fi
    echo "    - \"${hex}\""
  done

  cat <<YAML

  max_subscriptions: 50
  max_limit: 500

  websocket:
    max_connection_duration: "24h"
    idle_timeout: "30m"
    max_connections: 300
YAML
} > "$CONFIG_FILE"

ok "Config written to config/settings.local.yml"

# Update compose.yml relay_url
sed -i "s|NIP29__relay__relay_url:.*|NIP29__relay__relay_url: \"${RELAY_URL}\"|" compose.yml 2>/dev/null && \
  ok "Updated compose.yml with relay URL" || true

# ── Summary before launch ─────────────��──────────────────────

echo ""
echo -e "${CYAN}${BOX_TL}$(printf '%0.s─' $(seq 1 58))${BOX_TR}${NC}"
echo -e "${CYAN}${BOX_V}${NC}  ${BOLD}Configuration Summary${NC}                                   ${CYAN}${BOX_V}${NC}"
echo -e "${CYAN}${BOX_V}$(printf '%0.s─' $(seq 1 58))${BOX_V}${NC}"
echo -e "${CYAN}${BOX_V}${NC}                                                          ${CYAN}${BOX_V}${NC}"
printf "${CYAN}${BOX_V}${NC}  %-18s %-38s ${CYAN}${BOX_V}${NC}\n" "Relay URL:" "${RELAY_URL}"
printf "${CYAN}${BOX_V}${NC}  %-18s %-38s ${CYAN}${BOX_V}${NC}\n" "Admin:" "${ADMIN_HEX:0:20}...${ADMIN_HEX: -8}"
TOTAL_WL=$(( 1 + ${#EXTRA_PUBKEYS[@]} ))
printf "${CYAN}${BOX_V}${NC}  %-18s %-38s ${CYAN}${BOX_V}${NC}\n" "Whitelisted:" "${TOTAL_WL} pubkey(s)"
printf "${CYAN}${BOX_V}${NC}  %-18s %-38s ${CYAN}${BOX_V}${NC}\n" "Config:" "config/settings.local.yml"
printf "${CYAN}${BOX_V}${NC}  %-18s %-38s ${CYAN}${BOX_V}${NC}\n" "Port:" "8080"
echo -e "${CYAN}${BOX_V}${NC}                                                          ${CYAN}${BOX_V}${NC}"
echo -e "${CYAN}${BOX_BL}$(printf '%0.s─' $(seq 1 58))${BOX_BR}${NC}"

echo ""

# ── Launch ────────────────��───────────────────────────────────

if prompt_yn "Build and start the relay now?" "y"; then
  echo ""
  echo -e "  ${BOLD}Building the relay...${NC}"
  echo -e "  ${DIM}(First build takes 3-10 min — compiling Rust + frontend)${NC}"
  echo ""

  docker compose up -d --build 2>&1 | while IFS= read -r line; do
    echo -e "  ${DIM}${line}${NC}"
  done

  echo ""
  echo -e "  Waiting for relay to be healthy..."

  HEALTHY=false
  for i in $(seq 1 40); do
    if curl -sf --max-time 3 http://localhost:8080/health > /dev/null 2>&1; then
      HEALTHY=true
      break
    fi
    sleep 3
    echo -n "."
  done

  echo ""
  echo ""

  if [ "$HEALTHY" = true ]; then
    banner "Relay is live!"

    echo -e "  ${GREEN}${BOLD}Your Nostr relay is running.${NC}"
    echo ""
    echo -e "  ${BOLD}Connect with a Nostr client:${NC}"
    echo -e "    ${CYAN}${RELAY_URL}${NC}"
    echo ""
    echo -e "  ${BOLD}Web UI (local):${NC}"
    echo -e "    ${CYAN}http://localhost:8080/${NC}"
    echo ""
    echo -e "  ${BOLD}Health check:${NC}"
    echo -e "    ${CYAN}http://localhost:8080/health${NC}"
    echo ""

    if [ "$RELAY_DOMAIN" != "localhost" ]; then
      echo -e "  ${YELLOW}${BOLD}Next steps:${NC}"
      echo -e "    1. Point DNS for ${BOLD}${RELAY_DOMAIN}${NC} to this server"
      echo -e "    2. Set up a reverse proxy (Caddy/nginx) for TLS:"
      echo ""
      echo -e "       ${DIM}# Example Caddyfile entry:${NC}"
      echo -e "       ${DIM}${RELAY_DOMAIN} {${NC}"
      echo -e "       ${DIM}    reverse_proxy localhost:8080 {${NC}"
      echo -e "       ${DIM}        header_up Connection {>Connection}${NC}"
      echo -e "       ${DIM}        header_up Upgrade {>Upgrade}${NC}"
      echo -e "       ${DIM}    }${NC}"
      echo -e "       ${DIM}}${NC}"
      echo ""
    fi

    echo -e "  ${BOLD}Management commands:${NC}"
    echo -e "    ${DIM}./start.sh status${NC}    Check relay status"
    echo -e "    ${DIM}./start.sh logs${NC}      View relay logs"
    echo -e "    ${DIM}./start.sh restart${NC}   Restart the relay"
    echo -e "    ${DIM}./start.sh stop${NC}      Stop the relay"
    echo ""
    echo -e "  ${BOLD}Edit whitelist:${NC}"
    echo -e "    ${DIM}nano config/settings.local.yml${NC}"
    echo -e "    ${DIM}./start.sh restart${NC}"
    echo ""
  else
    fail "Relay did not become healthy in 2 minutes."
    echo ""
    echo "  Check logs for errors:"
    echo "    docker compose logs groups_relay"
    echo ""
    exit 1
  fi
else
  echo ""
  ok "Config saved. Start the relay anytime with:"
  echo ""
  echo -e "    ${CYAN}./start.sh${NC}"
  echo ""
fi
