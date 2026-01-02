#!/bin/bash
#
# TurboPi Setup - Run from Mac
# This syncs the project to the Pi and runs the setup script
#
set -e

PI_HOST="${PI_HOST:-pi@192.168.0.90}"
PI_PATH="/home/pi/ex_turbopi_umbrella"

echo "=========================================="
echo "TurboPi Setup"
echo "=========================================="
echo ""
echo "Target: $PI_HOST"
echo "Path:   $PI_PATH"
echo ""

# Check if we can reach the Pi
echo "[*] Checking connection to Pi..."
if ! ssh -o ConnectTimeout=5 "$PI_HOST" "echo 'Connected!'" 2>/dev/null; then
    echo "[!] Cannot connect to $PI_HOST"
    echo ""
    echo "Make sure:"
    echo "  1. The Pi is powered on and connected to your network"
    echo "  2. You can SSH to it: ssh $PI_HOST"
    echo "  3. Or set PI_HOST environment variable: PI_HOST=pi@192.168.x.x ./setup.sh"
    exit 1
fi

# Sync project files
echo "[*] Syncing project files..."
rsync -avz --progress \
    --exclude '_build' \
    --exclude 'deps' \
    --exclude '.git' \
    --exclude '.elixir_ls' \
    --exclude 'node_modules' \
    ./ "$PI_HOST:$PI_PATH/"

# Make scripts executable
echo "[*] Setting script permissions..."
ssh "$PI_HOST" "chmod +x $PI_PATH/scripts/*.sh $PI_PATH/*.sh 2>/dev/null || true"

# Run the Pi setup script
echo ""
echo "[*] Running setup on Pi..."
echo "[*] Note: Erlang compilation can take 30-60 minutes on Raspberry Pi"
echo ""
ssh -t "$PI_HOST" "cd $PI_PATH && ./scripts/pi_setup.sh"

echo ""
echo "Setup complete!"
