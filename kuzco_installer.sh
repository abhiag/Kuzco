#!/bin/bash

KUZCO_DIR="$HOME/.kuzco"
WORKER_FILE="$KUZCO_DIR/worker_info"

# Ensure all required dependencies are installed
echo "🔧 Installing required packages..."
sudo apt update
sudo apt install -y gnupg lsb-release wget curl

# Function to check NVIDIA GPU
check_nvidia_gpu() {
    echo "🔍 Checking for NVIDIA GPU..."
    if ! command -v nvidia-smi &> /dev/null; then
        echo "❌ NVIDIA GPU not detected! Install NVIDIA drivers first."
        exit 1
    fi
    echo "✅ NVIDIA GPU detected!"
}

# Function to check CUDA
check_cuda() {
    echo "🔍 Checking for CUDA..."
    if ! command -v nvcc &> /dev/null; then
        echo "❌ CUDA not installed! Installing CUDA..."
        install_cuda
    else
        echo "✅ CUDA is already installed!"
    fi
}

# Function to install NVIDIA Container Toolkit
install_nvidia_container_toolkit() {
    echo "🔧 Installing NVIDIA Container Toolkit..."
    sudo apt install -y nvidia-container-toolkit
    echo "✅ NVIDIA Container Toolkit installed!"
}

echo "✅ NVIDIA GPU detected!"

# Check if NVIDIA Container Toolkit is installed
echo "🔧 Installing NVIDIA Container Toolkit..."
yes | curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
apt list --upgradable

echo "✅ NVIDIA Container Toolkit installed!"

# Function to install CUDA Toolkit 12.8 in WSL or Ubuntu 24.04
install_cuda() {
    if $IS_WSL; then
        echo "🖥️ Installing CUDA for WSL 2..."
        # Define file names and URLs for WSL
        PIN_FILE="cuda-wsl-ubuntu.pin"
        PIN_URL="https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin"
        DEB_FILE="cuda-repo-wsl-ubuntu-12-8-local_12.8.0-1_amd64.deb"
        DEB_URL="https://developer.download.nvidia.com/compute/cuda/12.8.0/local_installers/cuda-repo-wsl-ubuntu-12-8-local_12.8.0-1_amd64.deb"
    else
        echo "🖥️ Installing CUDA for Ubuntu 24.04..."
        # Define file names and URLs for Ubuntu 24.04
        PIN_FILE="cuda-ubuntu2404.pin"
        PIN_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin"
        DEB_FILE="cuda-repo-ubuntu2404-12-8-local_12.8.0-570.86.10-1_amd64.deb"
        DEB_URL="https://developer.download.nvidia.com/compute/cuda/12.8.0/local_installers/cuda-repo-ubuntu2404-12-8-local_12.8.0-570.86.10-1_amd64.deb"
    fi

    # Download the .pin file
    echo "📥 Downloading $PIN_FILE from $PIN_URL..."
    wget "$PIN_URL" || { echo "❌ Failed to download $PIN_FILE from $PIN_URL"; exit 1; }

    # Move the .pin file to the correct location
    sudo mv "$PIN_FILE" /etc/apt/preferences.d/cuda-repository-pin-600 || { echo "❌ Failed to move $PIN_FILE to /etc/apt/preferences.d/"; exit 1; }

    # Remove the .deb file if it exists, then download a fresh copy
    if [ -f "$DEB_FILE" ]; then
        echo "🗑️ Deleting existing $DEB_FILE..."
        rm -f "$DEB_FILE"
    fi
    echo "📥 Downloading $DEB_FILE from $DEB_URL..."
    wget "$DEB_URL" || { echo "❌ Failed to download $DEB_FILE from $DEB_URL"; exit 1; }

    # Install the .deb file
    sudo dpkg -i "$DEB_FILE" || { echo "❌ Failed to install $DEB_FILE"; exit 1; }

    # Copy the keyring
    sudo cp /var/cuda-repo-*/cuda-*-keyring.gpg /usr/share/keyrings/ || { echo "❌ Failed to copy CUDA keyring to /usr/share/keyrings/"; exit 1; }

    # Update the package list and install CUDA Toolkit 12.8
    echo "🔄 Updating package list..."
    sudo apt-get update || { echo "❌ Failed to update package list"; exit 1; }
    apt list --upgradable
    echo "🔧 Installing CUDA Toolkit 12.8..."
    sudo apt-get install -y cuda-toolkit-12-8 || { echo "❌ Failed to install CUDA Toolkit 12.8"; exit 1; }

    echo "✅ CUDA Toolkit 12.8 installed successfully."
    setup_cuda_env
}

# Set up CUDA environment variables
setup_cuda_env() {
    echo "🔧 Setting up CUDA environment variables..."
    echo 'export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}' | sudo tee /etc/profile.d/cuda.sh
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' | sudo tee -a /etc/profile.d/cuda.sh
    source /etc/profile.d/cuda.sh
}

# Function to install Kuzco CLI
install_kuzco() {
    echo "🔧 Installing Kuzco CLI..."
    curl -fsSL https://inference.supply/install.sh | sh
    echo "✅ Kuzco CLI installed!"
}

# Function to start Kuzco worker
start_kuzco_worker() {
    if [[ -f "$WORKER_FILE" ]]; then
        source "$WORKER_FILE"
        echo "✅ Using saved Worker ID: $WORKER_ID"
        echo "✅ Using saved Registration Code: $REGISTRATION_CODE"
    else
        read -p "Enter Worker ID: " WORKER_ID
        read -p "Enter Registration Code: " REGISTRATION_CODE
        echo "WORKER_ID=$WORKER_ID" > "$WORKER_FILE"
        echo "REGISTRATION_CODE=$REGISTRATION_CODE" >> "$WORKER_FILE"
    fi

    sudo kuzco worker start --background --worker "$WORKER_ID" --code "$REGISTRATION_CODE"
    echo "✅ Kuzco Worker started!"
}

# Function to check Kuzco worker status
check_worker_status() {
    kuzco worker status
}

# Function to stop Kuzco worker
stop_worker() {
    sudo kuzco worker stop
    echo "✅ Kuzco Worker stopped!"
}

# Function to restart Kuzco worker
restart_worker() {
    sudo kuzco worker restart
    echo "✅ Kuzco Worker restarted!"
}

# Function to view Kuzco worker logs
view_worker_logs() {
    sudo kuzco worker logs
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
            check_cuda
            install_nvidia_container_toolkit
            install_cuda
            set_cuda_env
            install_kuzco
            start_kuzco_worker
            ;;
        2) check_worker_status ;;
        3) stop_worker ;;
        4) restart_worker ;;
        5) view_worker_logs ;;
        6) echo "🚀 Exiting Kuzco Manager!"; exit 0 ;;
        *) echo "❌ Invalid option, try again!" ;;
    esac
done
