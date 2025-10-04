#!/bin/sh
set -e

: "${OVPN_REMOTE_HOST:?OVPN_REMOTE_HOST is required (public proxy host, e.g. xyz.proxy.koyeb.app)}"
: "${OVPN_REMOTE_PORT:=443}"          # public proxy port (Koyeb-assigned)
: "${OVPN_REMOTE_PROTO:=tcp}"         # Koyeb is TCP-only
: "${OVPN_LISTEN_PORT:=443}"          # container's OpenVPN listen port

# Initialize config + PKI on first boot
if [ ! -f /etc/openvpn/pki/ca.crt ]; then
  echo "[init] Generating server config and PKI..."
  ovpn_genconfig -u "${OVPN_REMOTE_PROTO}://${OVPN_REMOTE_HOST}:${OVPN_REMOTE_PORT}"

  # Force TCP and desired listen port in server config (kylemanna uses openvpn.conf)
  if [ -f /etc/openvpn/openvpn.conf ]; then
    sed -i 's/^proto .*/proto tcp/' /etc/openvpn/openvpn.conf
    sed -i "s/^port .*/port ${OVPN_LISTEN_PORT}/" /etc/openvpn/openvpn.conf
  elif [ -f /etc/openvpn/server.conf ]; then
    sed -i 's/^proto .*/proto tcp/' /etc/openvpn/server.conf
    sed -i "s/^port .*/port ${OVPN_LISTEN_PORT}/" /etc/openvpn/server.conf
  fi

  EASYRSA_BATCH=1 EASYRSA_REQ_CN="${OVPN_REMOTE_HOST}" ovpn_initpki nopass
  # Ensure tls-auth key exists (belt & suspenders)
  [ -f /etc/openvpn/ta.key ] || openvpn --genkey --secret /etc/openvpn/ta.key
fi

echo "[run] starting openvpn on tcp/${OVPN_LISTEN_PORT} ..."
ovpn_run &

echo "[run] starting FastAPI ..."
exec uvicorn app:app --host 0.0.0.0 --port 8000
