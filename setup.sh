#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# LearnCard setup script
#
# Usage:
#   ./setup.sh           # production  (docker-compose.yaml)
#   ./setup.sh --local   # local dev   (docker-compose-local.yaml)
#
# What it does:
#   1. Generates cryptographically secure seeds (once, idempotent)
#   2. Starts backend services (brain, cloud, api + databases)
#   3. Waits for the brain service to be healthy
#   4. Creates the network consent contract on the brain service
#   5. Saves the contract URI to the .env file
#   6. Builds and starts the frontend app
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOCAL=false
for arg in "$@"; do
  [[ "$arg" == "--local" ]] && LOCAL=true
done

if $LOCAL; then
  COMPOSE_FILE="docker-compose-local.yaml"
  ENV_FILE=".env.local"
  BRAIN_URL="http://localhost:4000/trpc"
  CLOUD_URL="http://localhost:4100/trpc"
else
  COMPOSE_FILE="docker-compose.yaml"
  ENV_FILE=".env.production"
  BRAIN_URL="https://brain.poc17.eduwallet.nl/trpc"
  CLOUD_URL="https://cloud.poc17.eduwallet.nl/trpc"
fi

COMPOSE="docker compose -f $COMPOSE_FILE --env-file $ENV_FILE"

echo ""
echo "══════════════════════════════════════════════════"
echo "  LearnCard Setup"
echo "  Environment : $($LOCAL && echo 'local' || echo 'production')"
echo "  Compose file: $COMPOSE_FILE"
echo "  Env file    : $ENV_FILE"
echo "══════════════════════════════════════════════════"
echo ""

# ── Step 1: Create .env file, seeding from base .env if it exists ─────────────
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Creating $ENV_FILE..."
  touch "$ENV_FILE"
fi

# Copy any variables from base .env that are not yet set in the target env file
if [[ -f ".env" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and blank lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    key="${line%%=*}"
    [[ -z "$key" ]] && continue
    if ! grep -q "^$key=" "$ENV_FILE" 2>/dev/null; then
      echo "$line" >> "$ENV_FILE"
    fi
  done < ".env"
fi

# Helper: read a value from the env file
get_env() {
  grep -m1 "^$1=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- || echo ""
}

# Helper: set a value in the env file (add or update)
set_env() {
  local key="$1" val="$2"
  if grep -q "^$key=" "$ENV_FILE" 2>/dev/null; then
    sed -i.bak "s|^$key=.*|$key=$val|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else
    echo "$key=$val" >> "$ENV_FILE"
  fi
}

# ── Step 2: Generate seeds if not set ─────────────────────────────────────────
echo "► Checking seeds..."

BRAIN_SEED=$(get_env BRAIN_SEED)
CLOUD_SEED=$(get_env CLOUD_SEED)
API_SEED=$(get_env API_SEED)

if [[ -z "$BRAIN_SEED" ]]; then
  BRAIN_SEED=$(openssl rand -hex 32)
  set_env BRAIN_SEED "$BRAIN_SEED"
  echo "  Generated BRAIN_SEED"
else
  echo "  BRAIN_SEED already set"
fi

if [[ -z "$CLOUD_SEED" ]]; then
  CLOUD_SEED=$(openssl rand -hex 32)
  set_env CLOUD_SEED "$CLOUD_SEED"
  echo "  Generated CLOUD_SEED"
else
  echo "  CLOUD_SEED already set"
fi

if [[ -z "$API_SEED" ]]; then
  API_SEED=$(openssl rand -hex 32)
  set_env API_SEED "$API_SEED"
  echo "  Generated API_SEED"
else
  echo "  API_SEED already set"
fi

# ── Step 3: Build and start backend services (skip app for now) ───────────────
echo ""
echo "► Building backend service images (this may take a few minutes)..."
$COMPOSE build brain cloud api

echo ""
echo "► Starting backend services..."
$COMPOSE up -d traefik brain cloud api neo4j mongodb redis redis2 redis3 elasticmq

# ── Step 4: Wait for brain to be ready ────────────────────────────────────────
echo ""
echo "► Waiting for brain service to be ready..."
MAX_WAIT=120
ELAPSED=0
until curl -sf "http://localhost:4000/api/health-check" > /dev/null 2>&1; do
  if [[ $ELAPSED -ge $MAX_WAIT ]]; then
    echo "  ✗ Brain service did not become ready within ${MAX_WAIT}s"
    echo "  Check logs: docker compose -f $COMPOSE_FILE logs brain"
    exit 1
  fi
  sleep 3
  ELAPSED=$((ELAPSED + 3))
  echo "  ...waiting (${ELAPSED}s)"
done
echo "  ✓ Brain service is ready"

# ── Step 5: Create the network consent contract ──────────────────────────────
EXISTING_CONTRACT=$(get_env NETWORK_CONSENT_CONTRACT_URI)

if [[ -n "$EXISTING_CONTRACT" ]]; then
  echo ""
  echo "► Network consent contract already exists, skipping creation"
  echo "  URI: $EXISTING_CONTRACT"
else
  echo ""
  echo "► Creating network consent contract..."
  # Run the seed script inside the already-running api container — it has
  # @learncard/init and all plugins installed as workspace dependencies
  API_CONTAINER=$($COMPOSE ps -q api)
  docker cp "$SCRIPT_DIR/scripts/seed-network-contract.mjs" "$API_CONTAINER:/app/seed-network-contract.mjs"

  SEED_TMPOUT=$(mktemp)
  docker exec \
    -e LCN_URL="http://brain:4000/trpc" \
    -e CLOUD_URL="http://cloud:4100/trpc" \
    -e SEED="$BRAIN_SEED" \
    "$API_CONTAINER" \
    node /app/seed-network-contract.mjs 2>&1 | tee "$SEED_TMPOUT" || {
    echo "  ✗ Seed script failed. Output above."
    rm -f "$SEED_TMPOUT"
    exit 1
  }

  SEED_OUTPUT=$(cat "$SEED_TMPOUT")
  rm -f "$SEED_TMPOUT"

  CONTRACT_URI=$(echo "$SEED_OUTPUT" | grep "^NETWORK_CONSENT_CONTRACT_URI=" | cut -d'=' -f2-)
  CONTRACT_DID=$(echo "$SEED_OUTPUT" | grep "^NETWORK_CONSENT_CONTRACT_OWNER_DID=" | cut -d'=' -f2-)

  if [[ -z "$CONTRACT_URI" || -z "$CONTRACT_DID" ]]; then
    echo "  ✗ Failed to extract contract URI/DID from seed script output"
    exit 1
  fi

  set_env NETWORK_CONSENT_CONTRACT_URI "$CONTRACT_URI"
  set_env NETWORK_CONSENT_CONTRACT_OWNER_DID "$CONTRACT_DID"
  echo "  ✓ Contract created and saved to $ENV_FILE"
fi

# ── Step 6: Build and start the app ───────────────────────────────────────────
echo ""
echo "► Building app image (this may take a few minutes)..."
$COMPOSE build app

echo ""
echo "► Starting app..."
$COMPOSE up -d app

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════"
echo "  ✓ Setup complete!"
echo ""
if $LOCAL; then
  echo "  Frontend : https://frontend.local"
  echo "  Brain API: https://brain.local/trpc"
  echo "  Cloud API: https://cloud.local/trpc"
  echo "  LCA API  : https://lca.local/trpc"
else
  echo "  Frontend : https://frontend.poc17.eduwallet.nl"
  echo "  Brain API: https://brain.poc17.eduwallet.nl/trpc"
  echo "  Cloud API: https://cloud.poc17.eduwallet.nl/trpc"
  echo "  LCA API  : https://lca.poc17.eduwallet.nl/trpc"
fi
echo ""
echo "  Secrets stored in: $ENV_FILE"
echo "  (keep this file safe and do not commit it)"
echo "══════════════════════════════════════════════════"
