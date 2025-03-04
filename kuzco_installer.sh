#!/bin/bash

KUZCO_DIR="$HOME/.kuzco"
WORKER_FILE="$KUZCO_DIR/worker_info"

# Create Kuzco directory if not exists
mkdir -p "$KUZCO_DIR"

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
    sudo apt update
    sudo apt install -y nvidia-container-toolkit
    sudo systemctl restart docker || sudo systemctl restart nvidia-container-runtime
    echo "✅ NVIDIA Container Toolkit installed!"
}

# Function to install CUDA (Latest Version)
install_cuda() {
    echo "🔧 Installing CUDA..."

    UBUNTU_VERSION=$(lsb_release -rs)

    if [[ "$UBUNTU_VERSION" == "24.04" ]]; then
        echo "🚀 Installing CUDA for Ubuntu 24.04..."
        wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin
        sudo mv cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600

        wget https://developer.download.nvidia.com/compute/cuda/12.2.2/local_installers/cuda-repo-ubuntu2404-12-2-local_12.2.2-1_amd64.deb
        sudo dpkg -i cuda-repo-ubuntu2404-12-2-local_12.2.2-1_amd64.deb
        sudo cp /var/cuda-repo-ubuntu2404-12-2-local/cuda-*-keyring.gpg /usr/share/keyrings/

    elif [[ -d "/mnt/wsl" ]]; then
        echo "🚀 Installing CUDA for WSL..."
        wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-wsl-ubuntu.pin
        sudo mv cuda-wsl-ubuntu.pin /etc/apt/preferences.d/cuda-repository-pin-600

        wget https://developer.download.nvidia.com/compute/cuda/repos/wsl-ubuntu/x86_64/cuda-repo-wsl-ubuntu-12-2-local_12.2.2-1_amd64.deb
        sudo dpkg -i cuda-repo-wsl-ubuntu-12-2-local_12.2.2-1_amd64.deb
        sudo cp /var/cuda-repo-wsl-ubuntu-12-2-local/cuda-*-keyring.gpg /usr/share/keyrings/

    else
        echo "❌ Unsupported OS version! Exiting..."
        exit 1
    fi

    sudo apt update
    sudo apt install -y cuda
    echo "✅ CUDA installed successfully!"
}

# Function to set environment variables
set_cuda_env() {
    echo "🔧 Setting CUDA environment variables..."
    echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
    echo 'export CUDA_HOME=/usr/local/cuda' >> ~/.bashrc
    source ~/.bashrc
    echo "✅ CUDA environment variables set!"
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
