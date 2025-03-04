#!/bin/bash

KUZCO_DIR="$HOME/.kuzco"
WORKER_FILE="$KUZCO_DIR/worker_info"
LOG_FILE="$KUZCO_DIR/kuzco_manager.log"

# Ensure the Kuzco directory exists
mkdir -p "$KUZCO_DIR"

# Function to log messages
log_message() {
    local TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

# Function to handle errors
handle_error() {
    log_message "❌ Error: $1"
    exit 1
}

# Check if the script is running in WSL
IS_WSL=$(grep -qi microsoft /proc/version && echo true || echo false)

# Function to check if a package is installed
is_installed() {
    dpkg -s "$1" &>/dev/null
    return $?
}

# Show upgradable packages
log_message "🔍 Checking for upgradable packages..."
if ! sudo apt update; then
    handle_error "Failed to update package lists"
fi

UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." || true)

if [ -z "$UPGRADABLE" ]; then
    log_message "✅ All packages are up to date."
else
    log_message "🔧 Upgradable packages found:\n$UPGRADABLE"
    log_message "🔧 Upgrading packages..."
    sudo apt upgrade -y || handle_error "Failed to upgrade packages"
fi

# Install required packages only if not already installed
REQUIRED_PACKAGES=(nvtop sudo curl wget htop systemd fonts-noto-color-emoji)
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! is_installed "$pkg"; then
        log_message "🔧 Installing $pkg..."
        sudo apt install -y "$pkg" || handle_error "Failed to install $pkg"
    else
        log_message "✅ $pkg is already installed."
    fi
done

# Function to check NVIDIA GPU
check_nvidia_gpu() {
    log_message "🔍 Checking for NVIDIA GPU..."
    if ! command -v nvidia-smi &>/dev/null; then
        handle_error "NVIDIA GPU not detected! Install NVIDIA drivers first."
    fi
    log_message "✅ NVIDIA GPU detected!"
}

# Function to check if CUDA is installed
is_cuda_installed() {
    if command -v nvcc &>/dev/null; then
        CUDA_VERSION=$(nvcc --version | grep -oP 'release \K[0-9]+\.[0-9]+')
        REQUIRED_CUDA_VERSION="12.8"
        if [[ "$CUDA_VERSION" == "$REQUIRED_CUDA_VERSION" ]]; then
            log_message "✅ CUDA $REQUIRED_CUDA_VERSION is installed."
            return 0
        else
            log_message "⚠️ Installed CUDA version ($CUDA_VERSION) does not match required version ($REQUIRED_CUDA_VERSION)."
            return 1
        fi
    else
        log_message "❌ CUDA is not installed."
        return 1
    fi
}

# Function to set up CUDA environment variables
setup_cuda_env() {
    log_message "🔧 Setting up CUDA environment variables..."
    echo 'export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}' | sudo tee /etc/profile.d/cuda.sh
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' | sudo tee -a /etc/profile.d/cuda.sh
    source /etc/profile.d/cuda.sh
    log_message "✅ CUDA environment variables set."
}

# Function to install CUDA Toolkit 12.8
install_cuda() {
    if is_cuda_installed; then
        log_message "⏩ CUDA is already installed."
        return
    fi

    setup_cuda_env
    local CUDA_URL
    local CUDA_DEB

    if $IS_WSL; then
        CUDA_URL="https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64"
        CUDA_DEB="cuda-repo-wsl-ubuntu-12-8-local_12.8.0-1_amd64.deb"
    else
        CUDA_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64"
        CUDA_DEB="cuda-repo-ubuntu2404-12-8-local_12.8.0-570.86.10-1_amd64.deb"
    fi

    log_message "📥 Downloading CUDA installer..."
    wget "$CUDA_URL/$CUDA_DEB" || handle_error "Failed to download CUDA installer"

    log_message "🔧 Installing CUDA..."
    sudo dpkg -i "$CUDA_DEB" || handle_error "Failed to install CUDA"
    sudo apt-get update
    sudo apt-get install -y cuda-toolkit-12-8 || handle_error "CUDA installation failed."

    setup_cuda_env
    log_message "✅ CUDA Toolkit 12.8 installed."
}

# Function to install Kuzco CLI
install_kuzco() {
    log_message "🔧 Installing Kuzco CLI..."
    curl -fsSL https://inference.supply/install.sh | sh || handle_error "Failed to install Kuzco CLI"
    log_message "✅ Kuzco CLI installed."
}

# Function to start Kuzco worker
start_worker() {
    if [[ -f "$WORKER_FILE" ]]; then
        source "$WORKER_FILE"
    else
        read -p "Enter Worker ID: " WORKER_ID
        read -p "Enter Registration Code: " REGISTRATION_CODE
        echo "WORKER_ID=$WORKER_ID" > "$WORKER_FILE"
        echo "REGISTRATION_CODE=$REGISTRATION_CODE" >> "$WORKER_FILE"
    fi

    if systemctl list-unit-files | grep -q kuzco.service; then
        log_message "🔧 Starting Kuzco Worker..."
        sudo systemctl enable kuzco.service
        sudo systemctl start kuzco.service
    else
        log_message "🔧 Starting Kuzco Worker without systemd..."
        nohup kuzco worker start --worker "$WORKER_ID" --code "$REGISTRATION_CODE" > "$KUZCO_DIR/kuzco_manager.log" 2>&1 &
    fi
}

# Function to restart Kuzco worker
restart_worker() {
    log_message "🔧 Restarting Kuzco Worker..."

    # Check if systemd is available and service exists
    if command -v systemctl &>/dev/null && systemctl list-unit-files | grep -q kuzco.service; then
        if sudo systemctl restart kuzco.service; then
            log_message "✅ Kuzco Worker restarted (systemd mode)."
            return
        else
            log_message "⚠️ Failed to restart Kuzco Worker using systemd. Trying manual restart..."
        fi
    fi

    # Fallback for non-systemd systems or if systemctl fails
    if pgrep -f "kuzco worker" &>/dev/null; then
        log_message "🔧 Stopping Kuzco Worker (non-systemd mode)..."
        pkill -f "kuzco worker" && log_message "✅ Kuzco Worker stopped."
    fi

    # Start Kuzco Worker again
    log_message "🔧 Starting Kuzco Worker..."
    nohup kuzco worker start --worker "$WORKER_ID" --code "$REGISTRATION_CODE" > "$KUZCO_DIR/kuzco_manager.log" 2>&1 &
    
    if [ $? -eq 0 ]; then
        log_message "✅ Kuzco Worker restarted successfully!"
    else
        handle_error "Failed to restart Kuzco Worker"
    fi
}

# Function to check Kuzco worker status
check_worker_status() {
    if command -v systemctl &>/dev/null && systemctl list-unit-files | grep -q kuzco.service; then
        systemctl status kuzco.service || log_message "❌ Worker is not running."
    else
        # Check if the Kuzco process is running manually
        if pgrep -f "kuzco worker" &>/dev/null; then
            log_message "✅ Kuzco Worker is running (non-systemd mode)."
        else
            log_message "❌ Kuzco Worker is not running."
        fi
    fi
}


# Function to stop Kuzco worker
stop_worker() {
    log_message "🔧 Stopping Kuzco Worker..."

    # Check if systemd is available and service exists
    if command -v systemctl &>/dev/null && systemctl list-unit-files | grep -q kuzco.service; then
        if sudo systemctl stop kuzco.service; then
            log_message "✅ Kuzco Worker stopped (systemd mode)."
        else
            log_message "⚠️ Failed to stop Kuzco Worker using systemd. Trying manual process kill..."
        fi
    fi

    # Fallback for non-systemd systems or if systemctl failed
    if pgrep -f "kuzco worker" &>/dev/null; then
        pkill -f "kuzco worker" && log_message "✅ Kuzco Worker stopped (non-systemd mode)."
    else
        log_message "⚠️ No Kuzco Worker process found running."
    fi
}

view_worker_logs() {
    log_message "🔧 Fetching Kuzco Worker logs (live)..."

    if command -v systemctl &>/dev/null && systemctl list-unit-files | grep -q kuzco.service; then
        log_message "📜 Viewing live logs from systemd..."
        sudo journalctl -u kuzco.service -f
    else
        if [ -f "$KUZCO_DIR/kuzco_manager.log" ]; then
            log_message "📜 Viewing live logs from log file..."
            tail -f "$KUZCO_DIR/kuzco_manager.log"
        else
            log_message "⚠️ No logs found! The worker might not have started yet."
        fi
    fi
}


# Main menu
while true; do
    echo -e "\n🚀 Kuzco Manager 🚀"
    echo "1) Install Worker"
    echo "2) Check Worker Status"
    echo "3) Stop Worker"
    echo "4) Restart Worker"
    echo "5) Exit"
    echo "6) View Worker Logs"
    read -p "Choose an option: " choice

    case $choice in
        1) check_nvidia_gpu; install_cuda; install_kuzco; start_worker ;;
        2) check_worker_status ;;
        3) stop_worker ;;
        4) restart_worker ;;
        5) exit 0 ;;
        6) view_worker_logs ;;
        *) log_message "❌ Invalid option!" ;;
    esac
    read -rp "Press Enter to return to the main menu..."
done
