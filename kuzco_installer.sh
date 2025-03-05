#!/bin/bash

CONFIG_FILE="$HOME/.kuzco_config"
LOG_FILE="/var/log/kuzco_worker.log"
SCREEN_NAME="kuzco"  # Name of the screen session

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

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
    log_message "Kuzco credentials saved to $CONFIG_FILE."
}

# Function to validate input
validate_input() {
    if [[ -z "$1" ]]; then
        log_message "Error: Input cannot be empty."
        return 1
    fi
    return 0
}

# Function to set timezone to Asia/Kolkata
setup_timezone() {
    log_message "Setting timezone to Asia/Kolkata..."
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update > /dev/null 2>&1
    sudo apt-get install -y tzdata > /dev/null 2>&1

    echo "Asia/Kolkata" | sudo tee /etc/timezone > /dev/null
    sudo ln -fs /usr/share/zoneinfo/Asia/Dubai /etc/localtime
    sudo dpkg-reconfigure -f noninteractive tzdata > /dev/null 2>&1

    log_message "Timezone successfully set to $(date)."
}

# Function to install pciutils and lshw if not installed
install_gpu_tools() {
    if ! command -v lspci &> /dev/null || ! command -v lshw &> /dev/null; then
        log_message "Installing required GPU detection tools (pciutils & lshw)..."
        sudo apt update > /dev/null 2>&1
        sudo apt install -y pciutils lshw > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_message "GPU detection tools installed successfully."
        else
            log_message "Error: Failed to install GPU detection tools!" >&2
            return 1
        fi
    else
        log_message "Required GPU detection tools are already installed."
    fi
    return 0
}

# Function to check if NVIDIA GPU is available
check_nvidia_gpu() {
    if ! command -v lspci &> /dev/null; then
        log_message "Error: 'lspci' command not found. Install pciutils first." >&2
        return 1
    fi

    log_message "Checking for NVIDIA GPU..."
    if lspci | grep -i nvidia &> /dev/null; then
        log_message "NVIDIA GPU detected."
        if command -v nvidia-smi &> /dev/null; then
            log_message "NVIDIA drivers are installed."
            nvidia-smi  # Display GPU information
            return 0
        else
            log_message "NVIDIA GPU detected, but drivers are not installed. Install NVIDIA drivers and CUDA."
            return 1
        fi
    else
        log_message "No NVIDIA GPU detected."
        return 1
    fi
}

# Function to check if AMD GPU is available
check_amd_gpu() {
    if ! command -v lspci &> /dev/null; then
        log_message "Error: 'lspci' command not found. Install pciutils first." >&2
        return 1
    fi

    log_message "Checking for AMD GPU..."
    if lspci | grep -i amd | grep -i vga &> /dev/null; then
        log_message "AMD GPU detected."
        if command -v rocm-smi &> /dev/null; then
            log_message "AMD drivers are installed."
            rocm-smi  # Display GPU information
            return 0
        else
            log_message "AMD GPU detected, but drivers are not installed. Install AMD drivers."
            return 1
        fi
    else
        log_message "No AMD GPU detected."
        return 1
    fi
}

# Function to check for any GPU (NVIDIA or AMD)
check_gpu() {
    if check_nvidia_gpu; then
        return 0
    elif check_amd_gpu; then
        return 0
    else
        log_message "No supported GPU detected."
        return 1
    fi
}

# Function to set up CUDA environment variables
setup_cuda_env() {
    log_message "Setting up CUDA environment..."

    if [ ! -d "/usr/local/cuda-12.8/bin" ] || [ ! -d "/usr/local/cuda-12.8/lib64" ]; then
        log_message "Warning: CUDA directories do not exist. CUDA might not be installed!" >&2
    fi

    {
        echo 'export PATH=/usr/local/cuda-12.8/bin${PATH:+:${PATH}}'
        echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.8/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}'
    } | sudo tee /etc/profile.d/cuda.sh >/dev/null

    source /etc/profile.d/cuda.sh

    if echo "$PATH" | grep -q "/usr/local/cuda-12.8/bin"; then
        log_message "CUDA PATH successfully updated!"
    else
        log_message "Error: CUDA PATH not set correctly!" >&2
    fi

    if echo "$LD_LIBRARY_PATH" | grep -q "/usr/local/cuda-12.8/lib64"; then
        log_message "CUDA LD_LIBRARY_PATH successfully updated!"
    else
        log_message "Error: CUDA LD_LIBRARY_PATH not set correctly!" >&2
    fi
}

# Function to check and install CUDA
check_install_cuda() {
    setup_cuda_env

    if command -v nvcc &> /dev/null; then
        log_message "CUDA is already installed!"
    else
        log_message "CUDA is not installed. Installing CUDA..."
        curl -fsSL https://raw.githubusercontent.com/abhiag/CUDA/main/Cuda.sh | bash
        if [ $? -eq 0 ]; then
            log_message "CUDA installation completed."
        else
            log_message "Error: CUDA installation failed!" >&2
        fi
    fi
}

# Function to install Kuzco
install_kuzco() {
    log_message "Installing Kuzco..."
    curl -fsSL https://inference.supply/install.sh | sh
    if [ $? -eq 0 ]; then
        log_message "Kuzco installation completed."
    else
        log_message "Error: Kuzco installation failed!" >&2
    fi
}

# Function to start the Kuzco worker in a screen session
start_worker() {
    log_message "Starting Kuzco worker in screen session '$SCREEN_NAME'..."

    screen -S "$SCREEN_NAME" -dm bash -c "
    while true; do
        stdbuf -oL kuzco worker start --worker \"$WORKER_ID\" --code \"$CODE\" 2>&1 | tee -a \"$LOG_FILE\"
        log_message \"Kuzco worker crashed! Restarting in 5 seconds...\"
        sleep 5
    done
    "
    log_message "Kuzco worker is now running in the background. Use option 5 to Check Active Logs."
}

# Function to stop the Kuzco worker by terminating the screen session
stop_worker() {
    log_message "Stopping Kuzco worker..."

    screen -ls | awk '/[0-9]+\.kuzco/ {print $1}' | xargs -r -I{} screen -X -S {} quit
    find /var/run/screen -type s -name "*kuzco*" -exec sudo rm -rf {} + 2>/dev/null

    log_message "Kuzco worker stopped."
}

# Function to check Kuzco active logs
check_kuzco_logs() {
    if screen -list | grep -q "$SCREEN_NAME"; then
        log_message "Attaching to the Kuzco worker screen session..."
        screen -r "$SCREEN_NAME"
    else
        log_message "No active Kuzco worker session found!"
    fi
}

# Function to set up and start the Kuzco worker node
setup_worker_node() {
    load_kuzco_config

    if [[ -z "$WORKER_ID" || -z "$CODE" ]]; then
        read -rp "Enter Kuzco Worker ID: " WORKER_ID
        validate_input "$WORKER_ID" || return 1
        read -rp "Enter Kuzco Registration Code: " CODE
        validate_input "$CODE" || return 1
        save_kuzco_config
    fi

    setup_timezone
    install_gpu_tools
    setup_cuda_env
    check_nvidia_gpu || return 1

    if ! command -v kuzco &> /dev/null; then
        install_kuzco
    fi

    start_worker
}

# Function to uninstall Kuzco
uninstall_kuzco() {
    log_message "Removing Kuzco..."
    sudo rm -f /usr/local/bin/kuzco
    rm -rf ~/.kuzco ~/.config/kuzco
    sudo rm -f /var/log/kuzco_worker.log

    log_message "Kuzco has been uninstalled successfully!"
}

# Function to display the menu
show_menu() {
    clear
    echo "====================================================="
    echo "=== Kuzco Setup Menu - 📌Only GPU Users Can Run ==="
    echo "====================================================="
    echo "1) Check & Install CUDA"
    echo "2) Install & Run Kuzco Worker"
    echo "3) ReStart Kuzco Worker Node"
    echo "4) Stop Kuzco Worker"
    echo "5) Check Kuzco Active LOGs"
    echo "6) Exit"
    echo "7) Uninstall Kuzco Worker"
    echo "========================="
    read -rp "Enter your choice: " choice

    case $choice in
        1)
            setup_timezone
            check_install_cuda
            ;;
        2)
            install_gpu_tools && setup_worker_node
            ;;
        3)
            start_worker
            ;;
        4)
            stop_worker
            ;;
        5)
            check_kuzco_logs
            ;;
        6)
            log_message "Exiting..."
            exit 0
            ;;
        7)
            uninstall_kuzco
            ;;
        *)
            log_message "Invalid option. Please try again."
            sleep 2
            ;;
    esac

    read -rp "Press Enter to return to the main menu..."
    show_menu
}

# Check for required dependencies
check_dependencies() {
    if ! command -v curl &> /dev/null; then
        log_message "Error: 'curl' is not installed. Please install it and try again."
        exit 1
    fi
    if ! command -v screen &> /dev/null; then
        log_message "Error: 'screen' is not installed. Please install it and try again."
        exit 1
    fi
}

# Main execution
check_dependencies
show_menu
