#!/bin/bash
#
# TurboPi Deploy - Run from Mac
# Use this for subsequent deployments after initial setup.sh
#
set -e

PI_HOST="${PI_HOST:-pi@192.168.0.90}"
PI_PATH="/home/pi/ex_turbopi_umbrella"
SERVICE_NAME="ex_turbopi"

echo "=========================================="
echo "TurboPi Deploy"
echo "=========================================="

# Sync project files
echo "[*] Syncing files to Pi..."
rsync -avz --progress \
    --exclude '_build' \
    --exclude 'deps' \
    --exclude '.git' \
    --exclude '.elixir_ls' \
    --exclude 'node_modules' \
    --exclude '.env' \
    ./ "$PI_HOST:$PI_PATH/"

# Build and restart on Pi
echo "[*] Building on Pi..."
ssh "$PI_HOST" << 'EOF'
    set -e
    cd /home/pi/ex_turbopi_umbrella

    # Source asdf
    . "$HOME/.asdf/asdf.sh"

    export MIX_ENV=prod

    # Load secret
    if [ -f .env ]; then
        source .env
    fi

    echo "[*] Fetching dependencies..."
    mix deps.get --only prod

    echo "[*] Compiling..."
    mix compile

    echo "[*] Building assets..."
    mix assets.deploy 2>/dev/null || true

    echo "[*] Building release..."
    mix release --overwrite
EOF

# Restart the service
echo "[*] Restarting service..."
ssh "$PI_HOST" "sudo systemctl restart $SERVICE_NAME"

# Wait and check status
sleep 2
if ssh "$PI_HOST" "sudo systemctl is-active --quiet $SERVICE_NAME"; then
    PI_IP=$(ssh "$PI_HOST" "hostname -I | awk '{print \$1}'")
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
