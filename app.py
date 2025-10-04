import os
import subprocess
from pathlib import Path
from typing import Optional, List

from fastapi import FastAPI, HTTPException, Depends, Header, Response
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel

app = FastAPI(title="OpenVPN OVPN Generator")

# ====== Configuration via env ======
OVPN_DIR = Path(os.getenv("OVPN_DIR", "/etc/openvpn"))            # OpenVPN config dir
PKI_DIR = OVPN_DIR / "pki"                                        # Easy-RSA PKI
EASYRSA_BIN = Path(os.getenv("EASYRSA_BIN", "/usr/share/easy-rsa/easyrsa"))
API_TOKEN = os.getenv("API_TOKEN")                                # simple bearer token protection (optional)
REMOTE_HOST = os.getenv("OVPN_REMOTE_HOST", "example.com")        # e.g. yourapp-12345.proxy.koyeb.app
REMOTE_PORT = int(os.getenv("OVPN_REMOTE_PORT", "443"))           # public TCP proxy port
REMOTE_PROTO = os.getenv("OVPN_REMOTE_PROTO", "tcp")              # "tcp" (recommended on Koyeb)
TLS_AUTH_ENABLED = os.getenv("OVPN_TLS_AUTH", "true").lower() in ("1", "true", "yes")
TLS_AUTH_KEY = OVPN_DIR / "ta.key"                                # kylemanna default
TLS_CRYPT_ENABLED = os.getenv("OVPN_TLS_CRYPT", "false").lower() in ("1", "true", "yes")
TLS_CRYPT_KEY = OVPN_DIR / "tc.key"

# Optional: extra inline directives (one per line)
EXTRA_CLIENT_OPTS = os.getenv("OVPN_EXTRA_CLIENT_OPTS", "")

# ====== Auth dependency ======
def require_token(authorization: Optional[str] = Header(None)):
    if API_TOKEN:
        if not authorization or not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Missing Bearer token")
        token = authorization.split(" ", 1)[1].strip()
        if token != API_TOKEN:
            raise HTTPException(status_code=403, detail="Invalid token")

# ====== Models ======
class CreateClientRequest(BaseModel):
    name: str
    password: Optional[str] = None        # if None or empty and nopass True, cert will be without password
    nopass: bool = True
    overwrite: bool = False               # if True, revoke/remove existing and re-create

# ====== Helpers ======
def run(cmd: List[str], cwd: Optional[Path] = None) -> str:
    try:
        res = subprocess.run(
            cmd,
            cwd=str(cwd) if cwd else None,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env={**os.environ, "EASYRSA_PKI": str(PKI_DIR)},
        )
        return res.stdout
    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail=f"Command failed: {' '.join(cmd)}\n{e.stdout}")

def ensure_paths():
    # sanity checks
    if not OVPN_DIR.exists():
        raise HTTPException(status_code=500, detail=f"OpenVPN dir not found: {OVPN_DIR}")
    if not PKI_DIR.exists():
        raise HTTPException(status_code=500, detail=f"PKI dir not found (initialize Easy-RSA first): {PKI_DIR}")
    if not EASYRSA_BIN.exists():
        raise HTTPException(status_code=500, detail=f"easyrsa not found at {EASYRSA_BIN}")
    if TLS_AUTH_ENABLED and not TLS_AUTH_KEY.exists() and not TLS_CRYPT_ENABLED:
        # tls-auth is optional, just warn later in template if absent
        pass

def client_paths(name: str):
    crt = PKI_DIR / "issued" / f"{name}.crt"
    key = PKI_DIR / "private" / f"{name}.key"
    req = PKI_DIR / "reqs" / f"{name}.req"
    return crt, key, req

def make_ovpn(name: str) -> str:
    """Build an inline .ovpn from files in /etc/openvpn/pki"""
    ca = (PKI_DIR / "ca.crt").read_text().strip()
    crt, key, _ = client_paths(name)
    if not crt.exists() or not key.exists():
        raise HTTPException(status_code=404, detail=f"Client cert or key missing for '{name}'")
    cert_text = crt.read_text().strip()
    key_text = key.read_text().strip()

    ta_directive = ""
    ta_block = ""
    if TLS_CRYPT_ENABLED and TLS_CRYPT_KEY.exists():
        ta_directive = "key-direction 1"
        ta_block = f"<tls-crypt>\n{TLS_CRYPT_KEY.read_text().strip()}\n</tls-crypt>"
    elif TLS_AUTH_ENABLED and TLS_AUTH_KEY.exists():
        ta_directive = "key-direction 1"
        ta_block = f"<tls-auth>\n{TLS_AUTH_KEY.read_text().strip()}\n</tls-auth>"
    # Client template (sane defaults; adjust as needed)
    template = f"""client
dev tun
proto {REMOTE_PROTO}
remote {REMOTE_HOST} {REMOTE_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
verb 3
{ta_directive}
{EXTRA_CLIENT_OPTS}

<ca>
{ca}
</ca>

<cert>
{cert_text}
</cert>

<key>
{key_text}
</key>
{ta_block}
"""
    # cleanup any double blank lines
    return "\n".join(template.splitlines()) + "\n"  # ensures trailing newline too

# ====== Endpoints ======
@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.post("/clients")
def create_client(req: CreateClientRequest):
    ensure_paths()
    name = req.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Client name is required")

    crt, key, reqf = client_paths(name)
    exists = crt.exists() and key.exists()

    if exists and not req.overwrite:
        return {"message": "Client already exists", "name": name}

    if exists and req.overwrite:
        # Revoke & clean
        run([str(EASYRSA_BIN), "revoke", name])
        run([str(EASYRSA_BIN), "gen-crl"])
        # Remove old files
        for p in [crt, key, reqf]:
            try:
                p.unlink(missing_ok=True)
            except Exception:
                pass

    # Build client cert
    if req.nopass or not req.password:
        run([str(EASYRSA_BIN), "build-client-full", name, "nopass"])
    else:
        # Provide password via stdin; Easy-RSA will prompt twice
        proc = subprocess.Popen(
            [str(EASYRSA_BIN), "build-client-full", name],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, env={**os.environ, "EASYRSA_PKI": str(PKI_DIR)}
        )
        if proc.stdin:
            proc.stdin.write(f"{req.password}\n{req.password}\n")
            proc.stdin.flush()
        out, _ = proc.communicate()
        if proc.returncode != 0:
            raise HTTPException(status_code=500, detail=f"easyrsa build failed:\n{out}")

    return {"message": "Client created", "name": name}

@app.get("/clients/{name}.ovpn", response_class=PlainTextResponse)
def get_ovpn(name: str, override_host: Optional[str] = None, override_port: Optional[int] = None, proto: Optional[str] = None):
    """Download an inline .ovpn; you can override host/port via query params."""
    global REMOTE_HOST, REMOTE_PORT, REMOTE_PROTO
    if override_host:
        REMOTE_HOST = override_host
    if override_port:
        REMOTE_PORT = int(override_port)
    if proto:
        REMOTE_PROTO = proto
    ensure_paths()
    ovpn = make_ovpn(name)
    # Set download headers
    headers = {
        "Content-Disposition": f'attachment; filename="{name}.ovpn"',
        "Content-Type": "application/x-openvpn-profile",
    }
    return Response(content=ovpn, media_type="text/plain", headers=headers)

@app.delete("/clients/{name}", dependencies=[Depends(require_token)])
def revoke_client(name: str):
    ensure_paths()
    # revoke & generate CRL
    out1 = run([str(EASYRSA_BIN), "revoke", name])
    out2 = run([str(EASYRSA_BIN), "gen-crl"])
    # Optionally remove issued keys (kept by default)
    return {"message": "Client revoked", "name": name, "revoke": out1.splitlines()[-1:], "crl": out2.splitlines()[-1:]}
