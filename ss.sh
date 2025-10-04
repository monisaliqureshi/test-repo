# Run this on your laptop/PC (replace the host):
openssl s_client -connect general-valerye-monisaliqureshi-063c432d.koyeb.app:443 -servername general-valerye-monisaliqureshi-063c432d.koyeb.app  </dev/null 2>/dev/null \
| openssl x509 -noout -fingerprint -sha256 \
| sed 's/^SHA256 Fingerprint=//; s/://g;'
