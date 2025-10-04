#!/bin/sh
set -e

: "${OVPN_REMOTE_PROTO:=tcp}"
: "${OVPN_REMOTE_PORT:=443}"
: "${OVPN_LISTEN_PORT:=443}"

if [ -z "${OVPN_REMOTE_HOST:-}" ]; then
  echo "ERROR: OVPN_REMOTE_HOST is required (e.g. yourservice-12345.proxy.koyeb.app)"
  exit 1
fi

echo "[init] Using public endpoint: ${OVPN_REMOTE_PROTO}://${OVPN_REMOTE_HOST}:${OVPN_REMOTE_PORT}"
echo "[init] OpenVPN will listen on tcp/${OVPN_LISTEN_PORT}"

# Initialize config + PKI on first boot
if [ ! -f /etc/openvpn/pki/ca.crt ]; then
  echo "[init] Generating server config and PKI..."
  ovpn_genconfig -u "${OVPN_REMOTE_PROTO}://${OVPN_REMOTE_HOST}:${OVPN_REMOTE_PORT}"

  # force TCP + desired listen port
  CFG="/etc/openvpn/openvpn.conf"
  [ -f "$CFG" ] || CFG="/etc/openvpn/server.conf"
  if [ -f "$CFG" ]; then
    sed -i 's/^proto .*/proto tcp/' "$CFG"
    sed -i "s/^port .*/port ${OVPN_LISTEN_PORT}/" "$CFG"
  fi

  EASYRSA_BATCH=1 EASYRSA_REQ_CN="${OVPN_REMOTE_HOST}" ovpn_initpki nopass
  [ -f /etc/openvpn/ta.key ] || openvpn --genkey --secret /etc/openvpn/ta.key
fi

echo "[run] starting openvpn on tcp/${OVPN_LISTEN_PORT} ..."
ovpn_run &

echo "[run] starting FastAPI ..."
exec uvicorn app:app --host 0.0.0.0 --port 8000
