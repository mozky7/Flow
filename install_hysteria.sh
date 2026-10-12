#!/bin/bash
# Server setup script for Hysteria v1 (UDP D&T&A-64kbs & E-SAN UDP) on cheapvp.drmozky.online
set -e

OBFS_PASS="agnudp"
LISTEN_PORT="36712"
PORT_START="10000"
PORT_END="50000"

echo "[*] Installing Hysteria v1 binary..."
if ! command -v hysteria &>/dev/null; then
    curl -Lo /usr/local/bin/hysteria https://github.com/apernet/hysteria/releases/download/v1.3.5/hysteria-linux-amd64
    chmod +x /usr/local/bin/hysteria
fi

mkdir -p /etc/hysteria

# Generate self-signed TLS cert if needed
if [ ! -f /etc/hysteria/cert.crt ]; then
    echo "[*] Generating self-signed TLS certificate for Hysteria..."
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/C=TH/ST=Bangkok/L=Bangkok/O=Server/CN=cheapvp.drmozky.online" \
        -keyout /etc/hysteria/cert.key -out /etc/hysteria/cert.crt
fi

# Write server config - supports all auth variations (memduh, 1234, memduh:1234, esan, esan:esan)
cat <<EOF > /etc/hysteria/config.json
{
  "listen": ":${LISTEN_PORT}",
  "protocol": "udp",
  "cert": "/etc/hysteria/cert.crt",
  "key": "/etc/hysteria/cert.key",
  "obfs": "${OBFS_PASS}",
  "auth": {
    "mode": "passwords",
    "config": ["memduh", "1234", "memduh:1234", "esan", "esan:esan"]
  },
  "up_mbps": 100,
  "down_mbps": 100
}
EOF

# Setup systemd service
cat <<EOF > /etc/systemd/system/hysteria-server.service
[Unit]
Description=Hysteria Server Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.json
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Setup iptables UDP port hopping (ports 10000:50000 -> 36712 and 443 UDP -> 36712)
echo "[*] Setting up UDP port hopping (ports ${PORT_START}:${PORT_END} -> ${LISTEN_PORT})..."
iptables -t nat -D PREROUTING -p udp --dport ${PORT_START}:${PORT_END} -j REDIRECT --to-ports ${LISTEN_PORT} 2>/dev/null || true
iptables -t nat -A PREROUTING -p udp --dport ${PORT_START}:${PORT_END} -j REDIRECT --to-ports ${LISTEN_PORT}

echo "[*] Setting up UDP port 443 redirect -> ${LISTEN_PORT}..."
iptables -t nat -D PREROUTING -p udp --dport 443 -j REDIRECT --to-ports ${LISTEN_PORT} 2>/dev/null || true
iptables -t nat -A PREROUTING -p udp --dport 443 -j REDIRECT --to-ports ${LISTEN_PORT}

systemctl daemon-reload
systemctl enable hysteria-server
systemctl restart hysteria-server

echo "[+] Hysteria Server is active on cheapvp.drmozky.online!"
echo "[+] Listening on UDP port range ${PORT_START}-${PORT_END} and port 443 UDP with obfs='${OBFS_PASS}'"
echo "[+] Supported credentials: memduh:1234, memduh, 1234"
