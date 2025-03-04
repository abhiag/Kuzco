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
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

echo "✅ NVIDIA Container Toolkit installed!"

# Install CUDA
echo "🔧 Installing CUDA..."
UBUNTU_VERSION=$(lsb_release -rs)

if [[ -d "/mnt/wsl" ]]; then
    echo "🚀 Installing CUDA for WSL..."
    CUDA_REPO_URL="https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64"
    CUDA_DEB=$(curl -s $CUDA_REPO_URL/ | grep -o 'cuda-repo-wsl-ubuntu-[0-9-]*_amd64.deb' | sort -V | tail -n 1)
    if [[ -z "$CUDA_DEB" ]]; then
        echo "❌ Failed to find a valid CUDA package for WSL! Exiting..."
        exit 1
    fi
    wget $CUDA_REPO_URL/$CUDA_DEB
    sudo dpkg -i $CUDA_DEB
    sudo cp /var/cuda-repo-wsl-ubuntu-*/cuda-*-keyring.gpg /usr/share/keyrings/
elif [[ "$UBUNTU_VERSION" == "24.04" ]]; then
    echo "🚀 Installing CUDA for Ubuntu 24.04..."
    CUDA_REPO_URL="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64"
    CUDA_DEB=$(curl -s $CUDA_REPO_URL/ | grep -o 'cuda-repo-ubuntu2404-[0-9-]*_amd64.deb' | sort -V | tail -n 1)
    if [[ -z "$CUDA_DEB" ]]; then
        echo "❌ Failed to find a valid CUDA package for Ubuntu 24.04! Exiting..."
        exit 1
    fi
    wget $CUDA_REPO_URL/$CUDA_DEB
    sudo dpkg -i $CUDA_DEB
    sudo cp /var/cuda-repo-ubuntu2404-*/cuda-*-keyring.gpg /usr/share/keyrings/
else
    echo "❌ Unsupported OS version! Exiting..."
    exit 1
fi

sudo apt update
sudo apt install -y cuda

# Set CUDA environment variables
echo "🔧 Setting CUDA environment variables..."
echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
echo 'export CUDA_HOME=/usr/local/cuda' >> ~/.bashrc
source ~/.bashrc

echo "✅ CUDA installation complete!"

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
