FROM quay.io/outline/shadowbox:stable
RUN apk add --no-cache openssl
ENV SB_API_PORT=443
ENV SB_API_PREFIX=6f6e42c2-3d1a-4b8c-8b5d-9b6e0f46c2b7
ENV SB_CERTIFICATE_FILE=/tmp/shadowbox.crt
ENV SB_PRIVATE_KEY_FILE=/tmp/shadowbox.key
ENTRYPOINT ["/bin/sh","-c", "\
  set -eu; \
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout $SB_PRIVATE_KEY_FILE -out $SB_CERTIFICATE_FILE \
    -subj \"/CN=${KOYEB_APP_DOMAIN:-$HOSTNAME}\"; \
  exec node /opt/outline-server/app/main.js"]
