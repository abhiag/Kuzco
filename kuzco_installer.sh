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

# Function to check if a package is installed
is_installed() {
    dpkg -l "$1" &> /dev/null
    return $?
}

# Show upgradable packages
log_message "🔍 Checking for upgradable packages..."
UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." || true)

if [ -z "$UPGRADABLE" ]; then
    log_message "✅ All packages are up to date. Skipping upgrade."
else
    log_message "🔧 Upgradable packages found:"
    echo "$UPGRADABLE"
    log_message "🔧 Upgrading packages..."
    sudo apt upgrade -y || handle_error "Failed to upgrade packages"
fi

# Install required packages only if not already installed
REQUIRED_PACKAGES=(nvtop sudo curl wget htop systemd fonts-noto-color-emoji)
ALL_INSTALLED=true

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! is_installed "$pkg"; then
        log_message "🔧 Installing $pkg..."
        sudo apt install -y "$pkg" || handle_error "Failed to install $pkg"
        ALL_INSTALLED=false
    else
        log_message "✅ $pkg is already installed, skipping."
    fi
done

if $ALL_INSTALLED; then
    log_message "✅ All required packages are already installed. Skipping installation."
fi

# Function to check NVIDIA GPU
check_nvidia_gpu() {
    log_message "🔍 Checking for NVIDIA GPU..."
    if ! command -v nvidia-smi &> /dev/null; then
        handle_error "NVIDIA GPU not detected! Install NVIDIA drivers first."
    fi
    log_message "✅ NVIDIA GPU detected!"
}

# Function to check if CUDA is installed and matches the required version
is_cuda_installed() {
    if command -v nvcc &> /dev/null; then
        CUDA_VERSION=$(nvcc --version | grep -oP 'release \K[0-9]+\.[0-9]+')
        REQUIRED_CUDA_VERSION="12.8"
        if [[ "$CUDA_VERSION" == "$REQUIRED_CUDA_VERSION" ]]; then
            log_message "✅ CUDA $REQUIRED_CUDA_VERSION is already installed!"
            return 0
        else
            log_message "⚠️ CUDA is installed, but the version ($CUDA_VERSION) does not match the required version ($REQUIRED_CUDA_VERSION)."
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
    log_message "✅ CUDA environment variables set up successfully."
}

# Function to install CUDA Toolkit 12.8 in WSL or Ubuntu 24.04
install_cuda() {
    if is_cuda_installed; then
        log_message "⏩ CUDA is already installed. Skipping installation."
        return
    fi

    log_message "🔧 Setting up CUDA environment before installation..."
    setup_cuda_env

    if $IS_WSL; then
        log_message "🖥️ Installing CUDA for WSL 2..."
        # Define file names and URLs for WSL
        PIN_FILE="cuda-wsl-ubuntu.pin"
        PIN_URL="https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin"
        DEB_FILE="cuda-repo-wsl-ubuntu-12-8-local_12.8.0-1_amd64.deb"
        DEB_URL="https://developer.download.nvidia.com/compute/cuda/12.8.0/local_installers/cuda-repo-wsl-ubuntu-12-8-local_12.8.0-1_amd64.deb"
    else
        log_message "🖥️ Installing CUDA for Ubuntu 24.04..."
        # Define file names and URLs for Ubuntu 24.04
        PIN_FILE="cuda-ubuntu2404.pin"
        PIN_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin"
        DEB_FILE="cuda-repo-ubuntu2404-12-8-local_12.8.0-570.86.10-1_amd64.deb"
        DEB_URL="https://developer.download.nvidia.com/compute/cuda/12.8.0/local_installers/cuda-repo-ubuntu2404-12-8-local_12.8.0-570.86.10-1_amd64.deb"
    fi

    # Download the .pin file
    log_message "📥 Downloading $PIN_FILE from $PIN_URL..."
    wget "$PIN_URL" || handle_error "Failed to download $PIN_FILE from $PIN_URL"

    # Move the .pin file to the correct location
    sudo mv "$PIN_FILE" /etc/apt/preferences.d/cuda-repository-pin-600 || handle_error "Failed to move $PIN_FILE to /etc/apt/preferences.d/"

    # Remove the .deb file if it exists, then download a fresh copy
    if [ -f "$DEB_FILE" ]; then
        log_message "🗑️ Deleting existing $DEB_FILE..."
        rm -f "$DEB_FILE"
    fi
    log_message "📥 Downloading $DEB_FILE from $DEB_URL..."
    wget "$DEB_URL" || handle_error "Failed to download $DEB_FILE from $DEB_URL"

    # Install the .deb file
    sudo dpkg -i "$DEB_FILE" || handle_error "Failed to install $DEB_FILE"

    # Copy the keyring
    sudo cp /var/cuda-repo-*/cuda-*-keyring.gpg /usr/share/keyrings/ || handle_error "Failed to copy CUDA keyring to /usr/share/keyrings/"

    # Update the package list and install CUDA Toolkit 12.8
    log_message "🔄 Updating package list..."
    sudo apt-get update || handle_error "Failed to update package list"
    apt list --upgradable
    log_message "🔧 Installing CUDA Toolkit 12.8..."
    sudo apt-get install -y cuda-toolkit-12-8 || handle_error "Failed to install CUDA Toolkit 12.8"

    log_message "✅ CUDA Toolkit 12.8 installed successfully."
    setup_cuda_env
}

# Function to install Kuzco CLI
install_kuzco() {
    log_message "🔧 Installing Kuzco CLI..."
    curl -fsSL https://inference.supply/install.sh | sh || handle_error "Failed to install Kuzco CLI"
    log_message "✅ Kuzco CLI installed!"
}

# Function to check if systemd is available
is_systemd() {
    if command -v systemctl &> /dev/null && systemctl --version &> /dev/null; then
        return 0
    else
        return 1
    fi
}

start_kuzco_worker() {
    if [[ -f "$WORKER_FILE" ]]; then
        source "$WORKER_FILE"
        log_message "✅ Using saved Worker ID: $WORKER_ID"
        log_message "✅ Using saved Registration Code: $REGISTRATION_CODE"
    else
        read -p "Enter Worker ID: " WORKER_ID
        read -p "Enter Registration Code: " REGISTRATION_CODE
        echo "WORKER_ID=$WORKER_ID" > "$WORKER_FILE"
        echo "REGISTRATION_CODE=$REGISTRATION_CODE" >> "$WORKER_FILE"
    fi

    if is_systemd; then
        log_message "🔧 Starting Kuzco Worker using systemd..."
        sudo systemctl enable kuzco.service || handle_error "Failed to enable Kuzco service"
        sudo systemctl start kuzco.service || handle_error "Failed to start Kuzco Worker"
    else
        log_message "🔧 Starting Kuzco Worker directly (non-systemd system)..."
        nohup kuzco worker start --worker "$WORKER_ID" --code "$REGISTRATION_CODE" > "$KUZCO_DIR/kuzco.log" 2>&1 &
        if [ $? -eq 0 ]; then
            log_message "✅ Kuzco Worker started!"
        else
            handle_error "Failed to start Kuzco Worker"
        fi
    fi
}

# Function to check Kuzco worker status
check_worker_status() {
    if is_systemd; then
        sudo systemctl status kuzco.service || handle_error "Failed to check worker status"
    else
        log_message "🔧 Checking Kuzco Worker status directly (non-systemd system)..."
        if pgrep -f "kuzco worker" > /dev/null; then
            log_message "✅ Kuzco Worker is running."
        else
            log_message "❌ Kuzco Worker is not running."
        fi
    fi
}

# Function to stop Kuzco worker
stop_worker() {
    if is_systemd; then
        log_message "🔧 Stopping Kuzco Worker using systemd..."
        sudo systemctl stop kuzco.service || handle_error "Failed to stop Kuzco Worker"
    else
        log_message "🔧 Stopping Kuzco Worker directly (non-systemd system)..."
        pkill -f "kuzco worker" || handle_error "Failed to stop Kuzco Worker"
    fi
    log_message "✅ Kuzco Worker stopped!"
}

# Function to restart Kuzco worker
restart_worker() {
    if is_systemd; then
        log_message "🔧 Restarting Kuzco Worker using systemd..."
        sudo systemctl restart kuzco.service || handle_error "Failed to restart Kuzco Worker"
    else
        log_message "🔧 Restarting Kuzco Worker directly (non-systemd system)..."
        stop_worker
        start_kuzco_worker
    fi
    log_message "✅ Kuzco Worker restarted!"
}

# Function to view Kuzco worker logs
view_worker_logs() {
    if is_systemd; then
        sudo journalctl -u kuzco.service || handle_error "Failed to view worker logs"
    else
        log_message "🔧 Viewing Kuzco Worker logs directly (non-systemd system)..."
        sudo tail -n 100 /var/log/kuzco.log || handle_error "Failed to view worker logs"
    fi
}

# Main menu
while true; do
    echo "======================================"
    echo "🚀 Kuzco Manager - GPU & CUDA Ready 🚀"
    echo "======================================"
    echo "1) Install Kuzco Worker Node"
    echo "2) Check Worker Status"
    echo "3) Stop Worker"
    echo "4) Restart Worker"
    echo "5) View Worker Logs"
    echo "6) Exit"
    echo "======================================"
    read -p "Choose an option: " choice

    case $choice in
        1)
            check_nvidia_gpu
            if ! is_cuda_installed; then
                setup_cuda_env
                install_cuda
            fi
            install_kuzco
            start_kuzco_worker
            ;;
        2) check_worker_status ;;
        3) stop_worker ;;
        4) restart_worker ;;
        5) view_worker_logs ;;
        6) log_message "🚀 Exiting Kuzco Manager!"; exit 0 ;;
        *) log_message "❌ Invalid option, try again!" ;;
    esac
done
