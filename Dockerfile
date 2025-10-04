FROM kylemanna/openvpn:latest

# Python + FastAPI (avoid uvicorn[standard] to skip watchfiles/maturin on py3.8)
RUN apk add --no-cache python3 py3-pip bash && \
    python3 -m pip install --upgrade pip wheel "setuptools<77" && \
    pip3 install --no-cache-dir fastapi==0.115.0 uvicorn==0.30.6 pydantic==2.9.2

WORKDIR /opt/ovpn-api
# Use your current app.py (tokenless, or keep API_TOKEN unset)
COPY app.py /opt/ovpn-api/app.py

# Init + process supervisor (simple shell; OpenVPN bg + uvicorn fg)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Defaults; override at runtime
ENV OVPN_DIR=/etc/openvpn \
    EASYRSA_BIN=/usr/share/easy-rsa/easyrsa \
    OVPN_REMOTE_PROTO=tcp \
    OVPN_LISTEN_PORT=443

EXPOSE 443/tcp 8000/tcp
CMD ["/entrypoint.sh"]
