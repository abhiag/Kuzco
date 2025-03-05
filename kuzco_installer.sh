#!/bin/bash

# Kuzco Worker Configuration
WORKER_ID="DNGWvzoY65IK078B35aUc"
CODE="b384e8c5-b220-4a3a-8fd7-2ae85bea13f4"
LOG_FILE="/var/log/kuzco_worker.log"

# Function to check if Kuzco is installed
check_kuzco_installed() {
    if command -v kuzco &> /dev/null; then
        echo "Kuzco is already installed."
        return 0
    else
        return 1
    fi
}

# Function to install pciutils and lshw if not installed
install_gpu_tools() {
    if ! command -v lspci &> /dev/null || ! command -v lshw &> /dev/null; then
        echo "Installing required GPU detection tools (pciutils & lshw)..."
        sudo apt update
        sudo apt install -y pciutils lshw
    else
        echo "Required GPU detection tools are already installed."
    fi
}

# Function to check if NVIDIA GPU is available
check_nvidia_gpu() {
    if command -v lspci &> /dev/null && lspci | grep -i nvidia &> /dev/null; then
        echo "NVIDIA GPU detected."
        return 0
    else
        echo "No NVIDIA GPU detected! Make sure drivers and CUDA are installed."
        return 1
    fi
}

# Function to set up CUDA environment variables
setup_cuda_env() {
    echo "Setting up CUDA environment..."
    echo 'export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}' | sudo tee /etc/profile.d/cuda.sh
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' | sudo tee -a /etc/profile.d/cuda.sh
    source /etc/profile.d/cuda.sh
}

# Function to check and install CUDA
check_install_cuda() {
    setup_cuda_env  # Set up CUDA environment before checking installation
    if command -v nvcc &> /dev/null; then
        echo "CUDA is already installed!"
    else
        echo "CUDA is not installed. Installing CUDA..."
        curl -fsSL https://raw.githubusercontent.com/abhiag/CUDA/main/Cuda.sh | bash
    fi
}

# Function to install Kuzco
install_kuzco() {
    echo "Installing Kuzco..."
    curl -fsSL https://inference.supply/install.sh | sh
}

# Function to start the Kuzco worker
start_worker() {
    echo "Starting Kuzco worker..."
    while true; do
        kuzco worker start --worker "$WORKER_ID" --code "$CODE" >> "$LOG_FILE" 2>&1
        echo "Kuzco worker crashed! Restarting in 5 seconds..." | tee -a "$LOG_FILE"
        sleep 5
    done
}

# Function to display the menu
show_menu() {
    clear
    echo "=== Kuzco Setup Menu ==="
    echo "1) Install & Run Kuzco Worker"
    echo "2) Check & Install CUDA"
    echo "3) Exit"
    echo "========================="
    read -rp "Enter your choice: " choice

    case $choice in
        1)
            install_gpu_tools
            setup_cuda_env
            check_nvidia_gpu
            if ! check_kuzco_installed; then
                install_kuzco
            fi
            start_worker
            ;;
        2)
            check_install_cuda
            ;;
        3)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            sleep 2
            show_menu
            ;;
    esac
}

# Run the menu
show_menu
