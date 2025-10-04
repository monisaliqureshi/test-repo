# You can base on the OpenVPN image so Easy-RSA and dirs are present,
# or on a slim base and mount /etc/openvpn from your OpenVPN container.
FROM kylemanna/openvpn:latest

# Install Python + FastAPI runtime
RUN apk add --no-cache python3 py3-pip && \
    pip3 install --no-cache-dir fastapi "uvicorn[standard]" pydantic

# Copy app
WORKDIR /opt/ovpn-api
COPY app.py /opt/ovpn-api/app.py

# Defaults: adjust via env at deploy time
ENV OVPN_DIR=/etc/openvpn \
    EASYRSA_BIN=/usr/share/easy-rsa/easyrsa \
    OVPN_REMOTE_HOST=yourservice-12345.proxy.koyeb.app \
    OVPN_REMOTE_PORT=443 \
    OVPN_REMOTE_PROTO=tcp \
    OVPN_TLS_AUTH=true \
    OVPN_TLS_CRYPT=false \
    API_TOKEN=change-me

EXPOSE 8000/tcp

# Start API
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]

