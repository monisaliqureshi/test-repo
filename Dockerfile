# Use the official Outline Shadowbox image
FROM quay.io/outline/shadowbox:stable

# Make sure we have openssl (works for Alpine or Debian/Ubuntu bases)
SHELL ["/bin/sh", "-c"]
RUN set -eux; \
  if command -v apk >/dev/null 2>&1; then \
    apk add --no-cache openssl ca-certificates; \
  elif command -v apt-get >/dev/null 2>&1; then \
    apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*; \
  else \
    echo "No supported package manager found to install openssl" >&2; exit 1; \
  fi

# Reasonable defaults (can be overridden at deploy time)
ENV SB_API_PORT=443 \
    SB_STATE_DIR=/opt/outline/persisted-state \
    SB_CERTIFICATE_FILE=/tmp/shadowbox.crt \
    SB_PRIVATE_KEY_FILE=/tmp/shadowbox.key

# Add a tiny entrypoint that prepares certs + config, then runs shadowbox
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 443 80 21350

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

