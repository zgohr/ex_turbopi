#!/bin/bash
#
# TurboPi Deploy - Run from Mac
# Use this for subsequent deployments after initial setup.sh
#
set -e

PI_HOST="${PI_HOST:-pi@192.168.0.90}"
PI_PATH="/home/pi/ex_turbopi_umbrella"
SERVICE_NAME="ex_turbopi"
PI_PASS="${PI_PASS:-raspberrypi}"

# Use sshpass if available and password is set
if command -v sshpass &> /dev/null && [ -n "$PI_PASS" ]; then
    SSH_CMD="sshpass -p $PI_PASS ssh -o StrictHostKeyChecking=no"
    RSYNC_CMD="sshpass -p $PI_PASS rsync"
else
    SSH_CMD="ssh"
    RSYNC_CMD="rsync"
fi

echo "=========================================="
echo "TurboPi Deploy"
echo "=========================================="

# Sync project files
echo "[*] Syncing files to Pi..."
$RSYNC_CMD -avz --progress \
    --exclude '_build' \
    --exclude 'deps' \
    --exclude '.git' \
    --exclude '.elixir_ls' \
    --exclude 'node_modules' \
    --exclude '.env' \
    -e "ssh -o StrictHostKeyChecking=no" \
    ./ "$PI_HOST:$PI_PATH/"

# Ensure Flask is installed for camera streaming
echo "[*] Checking Python dependencies..."
$SSH_CMD "$PI_HOST" "pip3 install --quiet flask 2>/dev/null || true"

# Build and restart on Pi
echo "[*] Building on Pi..."
$SSH_CMD -T "$PI_HOST" "cd /home/pi/ex_turbopi_umbrella && \
    export PATH=\"\$HOME/.asdf/shims:\$HOME/.asdf/bin:\$PATH\" && \
    export MIX_ENV=prod && \
    if [ -f .env ]; then source .env; fi && \
    echo '[*] Fetching dependencies...' && \
    mix deps.get --only prod && \
    echo '[*] Compiling...' && \
    mix compile && \
    echo '[*] Building assets...' && \
    cd apps/ex_turbopi_web && mix assets.deploy && cd ../.. && \
    echo '[*] Building release...' && \
    mix release --overwrite"

# Restart the service
echo "[*] Restarting service..."
$SSH_CMD "$PI_HOST" "sudo systemctl restart $SERVICE_NAME"

# Wait and check status
sleep 2
if $SSH_CMD "$PI_HOST" "sudo systemctl is-active --quiet $SERVICE_NAME"; then
    PI_IP=$($SSH_CMD "$PI_HOST" "hostname -I | awk '{print \$1}'")
    echo ""
    echo "=========================================="
    echo "Deploy successful!"
    echo "=========================================="
    echo ""
    echo "Web UI: http://${PI_IP}:4000"
    echo ""
else
    echo ""
    echo "[!] Service may have failed to start. Check logs:"
    echo "    ssh $PI_HOST 'sudo journalctl -u $SERVICE_NAME -n 50'"
fi
