#!/bin/bash

CONFIG_DIR="$HOME/.kuzco"
CONFIG_FILE="$CONFIG_DIR/config"

# Function to check for an NVIDIA GPU
check_nvidia_gpu() {
    if ! command -v nvidia-smi &> /dev/null; then
        echo "❌ NVIDIA GPU not detected. Make sure your drivers are installed."
        exit 1
    fi

    GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader)
    if [[ -z "$GPU_INFO" ]]; then
        echo "❌ No NVIDIA GPU found! Ensure your GPU is properly connected."
        exit 1
    else
        echo "✅ NVIDIA GPU detected: $GPU_INFO"
    fi
}

# Function to check if CUDA is installed
check_cuda() {
    if ! command -v nvcc &> /dev/null; then
        echo "⚠️ CUDA is not installed. Installing NVIDIA Container Toolkit..."
        install_nvidia_container_toolkit
    else
        CUDA_VERSION=$(nvcc --version | grep "release" | awk '{print $6}')
        echo "✅ CUDA detected: $CUDA_VERSION"
    fi
}

install_gpg() {
    echo "🔧 Checking and installing GPG if missing..."
    if ! command -v gpg &> /dev/null; then
        sudo apt update && sudo apt install -y gnupg2 gnupg-agent
    fi
    if command -v gpg &> /dev/null; then
        echo "✅ GPG installed successfully."
    else
        echo "❌ GPG installation failed. Exiting."
        exit 1
    fi
}

install_gpg

# Function to install NVIDIA Container Toolkit
install_nvidia_container_toolkit() {
    echo "🔧 Installing GPG..."
    sudo apt update && sudo apt install -y gnupg

    echo "Installing NVIDIA Container Toolkit..."
    
    # Configure the repository
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
    && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

    # Optionally enable experimental packages
    sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list

    # Update package list
    sudo apt-get update

    # Install NVIDIA Container Toolkit
    sudo apt-get install -y nvidia-container-toolkit

    echo "✅ NVIDIA Container Toolkit installed successfully."
}

# Function to install Kuzco CLI
install_kuzco_cli() {
    echo "Installing Kuzco CLI..."
    curl -fsSL https://inference.supply/install.sh | sh
    echo "✅ Kuzco CLI installed successfully!"
}

# Function to save worker credentials
save_credentials() {
    mkdir -p "$CONFIG_DIR"
    echo "WORKER_ID=$WORKER_ID" > "$CONFIG_FILE"
    echo "REG_CODE=$REG_CODE" >> "$CONFIG_FILE"
}

# Function to load worker credentials
load_credentials() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        echo "🔹 Loaded saved Worker ID: $WORKER_ID"
    else
        return 1  # No credentials found
    fi
}

# Function to install Kuzco Worker Node
install_kuzco_worker() {
    if ! load_credentials; then
        read -p "Enter your Worker ID: " WORKER_ID
        read -p "Enter your Registration Code: " REG_CODE

        if [[ -z "$WORKER_ID" || -z "$REG_CODE" ]]; then
            echo "❌ Error: Worker ID and Registration Code cannot be empty."
            return
        fi

        save_credentials
    fi

    echo "Installing and starting Kuzco Worker Node..."
    sudo kuzco worker start --background --worker "$WORKER_ID" --code "$REG_CODE"

    echo "✅ Kuzco Worker started successfully!"
}

# Function to reset saved credentials
reset_credentials() {
    rm -f "$CONFIG_FILE"
    echo "🔄 Credentials have been reset. You will be asked for Worker ID and Registration Code again."
}

# Function to check worker status
check_worker_status() {
    echo "Checking Kuzco Worker status..."
    kuzco worker status
}

# Function to stop the worker
stop_worker() {
    echo "Stopping Kuzco Worker..."
    sudo kuzco worker stop
}

# Function to restart the worker
restart_worker() {
    echo "Restarting Kuzco Worker..."
    sudo kuzco worker restart
}

# Function to view worker logs
view_worker_logs() {
    echo "Fetching Kuzco Worker logs..."
    sudo kuzco worker logs
}

# Run NVIDIA and CUDA checks before proceeding
check_nvidia_gpu
check_cuda

# Menu function
while true; do
    echo "=========================="
    echo " Kuzco Worker Manager Menu"
    echo "=========================="
    echo "1. Install Kuzco Worker Node"
    echo "2. Check Worker Status"
    echo "3. Stop Worker"
    echo "4. Restart Worker"
    echo "5. View Worker Logs"
    echo "6. Reset Credentials"
    echo "7. Install Kuzco CLI"
    echo "8. Exit"
    echo "=========================="
    read -p "Select an option (1-8): " choice

    case $choice in
        1) install_kuzco_worker ;;
        2) check_worker_status ;;
        3) stop_worker ;;
        4) restart_worker ;;
        5) view_worker_logs ;;
        6) reset_credentials ;;
        7) install_kuzco_cli ;;
        8) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid choice! Please enter a number between 1-8." ;;
    esac
    echo ""
done
