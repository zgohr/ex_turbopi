#!/bin/bash
#
# TurboPi Initial Setup Script
# Run this on the Raspberry Pi to set up the Elixir environment
#
set -e

PROJECT_PATH="/home/pi/ex_turbopi_umbrella"
SERVICE_NAME="ex_turbopi"

echo "=========================================="
echo "TurboPi Elixir Setup"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[!]${NC} $1"
}

# Check if running as pi user
if [ "$USER" != "pi" ]; then
    print_error "This script should be run as the 'pi' user"
    exit 1
fi

# ==========================================
# Step 1: System Dependencies
# ==========================================
print_step "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    autoconf \
    m4 \
    libncurses5-dev \
    libwxgtk3.2-dev \
    libwxgtk-webview3.2-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    libpng-dev \
    libssh-dev \
    unixodbc-dev \
    xsltproc \
    fop \
    libxml2-utils \
    libssl-dev \
    curl \
    git

# ==========================================
# Step 2: Install asdf
# ==========================================
if [ ! -d "$HOME/.asdf" ]; then
    print_step "Installing asdf..."
    git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.18.0

    # Add to bashrc if not already there
    if ! grep -q "asdf.sh" ~/.bashrc; then
        echo '' >> ~/.bashrc
        echo '# asdf version manager' >> ~/.bashrc
        echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
        echo '. "$HOME/.asdf/completions/asdf.bash"' >> ~/.bashrc
    fi
else
    print_step "asdf already installed"
fi

# Source asdf for this session
export ASDF_DIR="$HOME/.asdf"
. "$HOME/.asdf/asdf.sh"

# ==========================================
# Step 3: Install Erlang and Elixir plugins
# ==========================================
print_step "Setting up asdf plugins..."

if ! asdf plugin list | grep -q erlang; then
    asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
fi

if ! asdf plugin list | grep -q elixir; then
    asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
fi

# ==========================================
# Step 4: Install Erlang and Elixir
# ==========================================
cd "$PROJECT_PATH"

# Read versions from .tool-versions
ERLANG_VERSION=$(grep erlang .tool-versions | awk '{print $2}')
ELIXIR_VERSION=$(grep elixir .tool-versions | awk '{print $2}')

print_step "Installing Erlang ${ERLANG_VERSION}..."
print_warn "This may take 30-60 minutes on Raspberry Pi"

if ! asdf list erlang | grep -q "$ERLANG_VERSION"; then
    # Erlang build options for Pi
    export KERL_CONFIGURE_OPTIONS="--disable-debug --without-javac --without-odbc"
    asdf install erlang "$ERLANG_VERSION"
fi
asdf global erlang "$ERLANG_VERSION"

print_step "Installing Elixir ${ELIXIR_VERSION}..."
if ! asdf list elixir | grep -q "$ELIXIR_VERSION"; then
    asdf install elixir "$ELIXIR_VERSION"
fi
asdf global elixir "$ELIXIR_VERSION"

# Verify installation
print_step "Verifying installation..."
elixir --version

# Install hex and rebar
print_step "Installing Hex and Rebar..."
mix local.hex --force
mix local.rebar --force

# ==========================================
# Step 5: Disable Docker ROS2 Stack
# ==========================================
print_step "Disabling Docker ROS2 stack..."

if docker ps -a --format '{{.Names}}' | grep -q TurboPi; then
    docker stop TurboPi 2>/dev/null || true
    docker update --restart=no TurboPi
    print_step "TurboPi Docker container disabled"
else
    print_warn "TurboPi Docker container not found (may already be removed)"
fi

# Optional: disable Docker service entirely
# sudo systemctl disable docker
# print_step "Docker service disabled"

# ==========================================
# Step 6: Build the Application
# ==========================================
print_step "Building application..."
cd "$PROJECT_PATH"

export MIX_ENV=prod

mix deps.get --only prod
mix compile

# Build assets if the script exists
if [ -f "apps/ex_turbopi_web/mix.exs" ]; then
    print_step "Building assets..."
    mix assets.deploy 2>/dev/null || print_warn "No assets to deploy"
fi

# Generate secret if not set
if [ -z "$SECRET_KEY_BASE" ]; then
    export SECRET_KEY_BASE=$(mix phx.gen.secret)
    echo "SECRET_KEY_BASE=$SECRET_KEY_BASE" > "$PROJECT_PATH/.env"
    print_step "Generated SECRET_KEY_BASE (saved to .env)"
fi

# Build release
print_step "Building release..."
mix release --overwrite

# ==========================================
# Step 7: Create Systemd Service
# ==========================================
print_step "Creating systemd service..."

# Load secret from .env if it exists
if [ -f "$PROJECT_PATH/.env" ]; then
    source "$PROJECT_PATH/.env"
fi

# Get the Pi's IP address
PI_IP=$(hostname -I | awk '{print $1}')

sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=TurboPi Elixir Controller
After=network.target

[Service]
Type=exec
User=pi
Group=pi
WorkingDirectory=${PROJECT_PATH}
Environment=MIX_ENV=prod
Environment=PORT=4000
Environment=PHX_HOST=${PI_IP}
Environment=PHX_SERVER=true
Environment=SECRET_KEY_BASE=${SECRET_KEY_BASE}
Environment=HOME=/home/pi
Environment=PATH=/home/pi/.asdf/shims:/home/pi/.asdf/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=${PROJECT_PATH}/_build/prod/rel/ex_turbopi_umbrella/bin/ex_turbopi_umbrella start
ExecStop=${PROJECT_PATH}/_build/prod/rel/ex_turbopi_umbrella/bin/ex_turbopi_umbrella stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# ==========================================
# Step 8: Enable and Start Service
# ==========================================
print_step "Enabling and starting service..."

sudo systemctl daemon-reload
sudo systemctl enable ${SERVICE_NAME}
sudo systemctl start ${SERVICE_NAME}

# Wait a moment for it to start
sleep 3

# Check status
if sudo systemctl is-active --quiet ${SERVICE_NAME}; then
    echo ""
    echo -e "${GREEN}=========================================="
    echo "Setup Complete!"
    echo "==========================================${NC}"
    echo ""
    echo "The TurboPi controller is now running!"
    echo ""
    echo "  Web UI:  http://${PI_IP}:4000"
    echo ""
    echo "Useful commands:"
    echo "  sudo systemctl status ${SERVICE_NAME}  # Check status"
    echo "  sudo journalctl -u ${SERVICE_NAME} -f  # View logs"
    echo "  sudo systemctl restart ${SERVICE_NAME} # Restart"
    echo ""
    echo "To re-enable the original ROS2 stack:"
    echo "  docker update --restart=always TurboPi"
    echo "  sudo systemctl stop ${SERVICE_NAME}"
    echo "  sudo reboot"
else
    print_error "Service failed to start. Check logs with:"
    echo "  sudo journalctl -u ${SERVICE_NAME} -n 50"
fi
