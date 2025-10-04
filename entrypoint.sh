#!/bin/sh
set -eu

: "${SB_STATE_DIR:=/opt/outline/persisted-state}"
: "${SB_CERTIFICATE_FILE:=/tmp/shadowbox.crt}"
: "${SB_PRIVATE_KEY_FILE:=/tmp/shadowbox.key}"
: "${SB_API_PORT:=443}"

# Determine hostname for config & cert CN:
# Prefer KOYEB_APP_DOMAIN if present, else SB_HOSTNAME, else system hostname
HOST="${KOYEB_APP_DOMAIN:-${SB_HOSTNAME:-$(hostname -f 2>/dev/null || hostname)}}"

# Generate API prefix if not provided (so it's stable if you set it in env)
if [ -z "${SB_API_PREFIX:-}" ]; then
  SB_API_PREFIX="$(cat /proc/sys/kernel/random/uuid)"
  export SB_API_PREFIX
fi

# Prepare state dir
mkdir -p "$SB_STATE_DIR"

# Create a self-signed cert if not already present (ephemeral on Koyeb Free)
if [ ! -s "$SB_CERTIFICATE_FILE" ] || [ ! -s "$SB_PRIVATE_KEY_FILE" ]; then
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout "$SB_PRIVATE_KEY_FILE" \
    -out    "$SB_CERTIFICATE_FILE" \
    -subj "/CN=${HOST}"
fi

# Write the required Shadowbox server config (hostname + single-port rollout)
cat > "$SB_STATE_DIR/shadowbox_server_config.json" <<EOF
{"rollouts":[{"id":"single-port","enabled":true}],"portForNewAccessKeys":${SB_API_PORT},"hostname":"${HOST}"}
EOF

# Print helpful connection info to logs (so you can copy into Outline Manager)
CERT_SHA256="$(openssl x509 -in "$SB_CERTIFICATE_FILE" -noout -fingerprint -sha256 | sed 's/^SHA256 Fingerprint=//; s/://g;')"
echo "== Outline Manager setup =="
echo "apiUrl: https://${HOST}:${SB_API_PORT}/${SB_API_PREFIX}"
echo "certSha256: ${CERT_SHA256}"
echo "==========================="

# Run Shadowbox
exec node /opt/outline-server/app/main.js
