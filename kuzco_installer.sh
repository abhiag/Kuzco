#!/bin/bash

CONFIG_FILE="$HOME/.kuzco_config"
LOG_FILE="/var/log/kuzco_worker.log"

# Function to load Kuzco credentials from config file
load_kuzco_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        WORKER_ID=""
        CODE=""
    fi
}

# Function to save Kuzco credentials
save_kuzco_config() {
    echo "WORKER_ID=\"$WORKER_ID\"" > "$CONFIG_FILE"
    echo "CODE=\"$CODE\"" >> "$CONFIG_FILE"
}

# Function to set timezone to Asia/Kolkata
setup_timezone() {
    echo "Checking and installing tzdata if necessary..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update
    sudo apt-get install -y tzdata

    echo "Configuring timezone to Asia/Kolkata..."
    echo "Asia/Dubai" | sudo tee /etc/timezone
    sudo ln -fs /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
    sudo dpkg-reconfigure -f noninteractive tzdata

    echo "Timezone successfully set to $(date)"
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

    # Ensure the directory exists
    if [ ! -d "/usr/local/cuda-12.8/bin" ] || [ ! -d "/usr/local/cuda-12.8/lib64" ]; then
        echo "Warning: CUDA directories do not exist. CUDA might not be installed!" >&2
    fi

    # Write environment variables to profile script
    {
        echo 'export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}'
        echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}'
    } | sudo tee /etc/profile.d/cuda.sh >/dev/null

    # Apply the changes
    source /etc/profile.d/cuda.sh

    # Verify changes
    if echo "$PATH" | grep -q "/usr/local/cuda-12.8/bin"; then
        echo "CUDA PATH successfully updated!"
    else
        echo "Error: CUDA PATH not set correctly!" >&2
    fi

    if echo "$LD_LIBRARY_PATH" | grep -q "/usr/local/cuda-12.8/lib64"; then
        echo "CUDA LD_LIBRARY_PATH successfully updated!"
    else
        echo "Error: CUDA LD_LIBRARY_PATH not set correctly!" >&2
    fi
}

# Function to check and install CUDA
check_install_cuda() {
    setup_cuda_env  # Set up CUDA environment before checking installation
    
    if command -v nvcc &> /dev/null; then
        echo "CUDA is already installed!"
    else
        echo "CUDA is not installed. Installing CUDA..."
        curl -fsSL https://raw.githubusercontent.com/abhiag/CUDA/main/Cuda.sh | bash
        echo "CUDA installation completed."
    fi

    read -rp "Press Enter to return to the main menu..."
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
        stdbuf -oL kuzco worker start --worker "$WORKER_ID" --code "$CODE" 2>&1 | tee -a "$LOG_FILE"

        echo "Kuzco worker crashed! Restarting in 5 seconds..." | tee -a "$LOG_FILE"
        sleep 5
    done
}

# Function to set up and start the Kuzco worker node
setup_worker_node() {
    load_kuzco_config  # Load saved credentials if available

    # Ask for Worker ID and Code if not already saved
    if [[ -z "$WORKER_ID" || -z "$CODE" ]]; then
        read -rp "Enter Kuzco Worker ID: " WORKER_ID
        read -rp "Enter Kuzco Registration Code: " CODE
        save_kuzco_config  # Save for future use
    fi

    setup_timezone
    install_gpu_tools
    setup_cuda_env
    check_nvidia_gpu

    if ! check_kuzco_installed; then
        install_kuzco
    fi

    start_worker
}

# Function to display the menu
show_menu() {
    clear
    echo "=== Kuzco Setup Menu ==="
    echo "1) Install & Run Kuzco Worker"
    echo "2) Check & Install CUDA"
    echo "3) Start Kuzco Worker Node (Save Credentials)"
    echo "4) Exit"
    echo "========================="
    read -rp "Enter your choice: " choice

    case $choice in
        1)
            install_gpu_tools
            setup_cuda_env
            check_nvidia_gpu
            if ! check_kuzco_installed; then
                setup_cuda_env
                install_kuzco
            fi
            start_worker
            ;;
        2)
            check_install_cuda
            ;;
        3)
            setup_worker_node
            ;;
        4)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            sleep 2
            show_menu
            ;;
    esac

    read -rp "Press Enter to return to the main menu..."
    show_menu
}

# Run the menu
show_menu
