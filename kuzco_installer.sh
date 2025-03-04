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

# Function to check and install required tools (lspci or lshw)
install_tools() {
    log_message "🔍 Checking for system tools..."
    if ! command -v lspci &> /dev/null && ! command -v lshw &> /dev/null; then
        log_message "⚠️ Neither 'lspci' nor 'lshw' found. Installing dependencies..."
        sudo apt update
        sudo apt install -y pciutils lshw || handle_error "Failed to install pciutils/lshw"
    else
        log_message "✅ 'lspci' or 'lshw' is already installed."
    fi
}

# Function to detect NVIDIA GPU
detect_nvidia_gpu() {
    log_message "🔍 Detecting NVIDIA GPU..."
    if command -v lspci &> /dev/null && lspci | grep -i nvidia &> /dev/null; then
        log_message "✅ NVIDIA GPU detected (via lspci)."
        return 0
    elif command -v lshw &> /dev/null && sudo lshw -C display | grep -i nvidia &> /dev/null; then
        log_message "✅ NVIDIA GPU detected (via lshw)."
        return 0
    else
        log_message "❌ No NVIDIA GPU detected."
        return 1
    fi
}

# Function to install Kuzco CLI
install_kuzco() {
    log_message "🔧 Installing Kuzco CLI..."
    curl -fsSL https://inference.supply/install.sh | sh || handle_error "Failed to install Kuzco CLI"
    log_message "✅ Kuzco CLI installed!"
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

    log_message "🚀 Starting Kuzco Worker..."
    sudo kuzco worker start --worker "$WORKER_ID" --code "$REGISTRATION_CODE" &>> "$LOG_FILE" &
    log_message "✅ Kuzco Worker started!"
}

# Function to check Kuzco worker status
check_worker_status() {
    log_message "🔍 Checking Kuzco Worker status..."
    kuzco worker status || handle_error "Failed to check worker status"
}

# Function to stop Kuzco worker
stop_worker() {
    log_message "🛑 Stopping Kuzco Worker..."
    sudo kuzco worker stop || handle_error "Failed to stop Kuzco Worker"
    log_message "✅ Kuzco Worker stopped!"
}

# Function to restart Kuzco worker
restart_worker() {
    log_message "🔄 Restarting Kuzco Worker..."
    sudo kuzco worker restart || handle_error "Failed to restart Kuzco Worker"
    log_message "✅ Kuzco Worker restarted!"
}

# Function to view Kuzco worker logs
view_worker_logs() {
    log_message "📜 Viewing Kuzco Worker logs..."
    sudo kuzco worker logs || handle_error "Failed to view worker logs"
}

# Function to force kill Kuzco Worker
force_kill_worker() {
    log_message "🛑 Forcing Kuzco Worker to stop..."
    
    # Find the PID of the Kuzco worker process
    PID=$(pgrep -f "kuzco worker start")
    
    if [[ -n "$PID" ]]; then
        sudo kill -9 "$PID"
        log_message "✅ Kuzco Worker process ($PID) forcefully stopped!"
    else
        log_message "❌ No running Kuzco Worker process found!"
    fi
}

# Main menu
while true; do
    echo "======================================"
    echo "🚀 Kuzco Manager - Node Setup 🚀"
    echo "======================================"
    echo "1) Install Kuzco Worker Node"
    echo "2) Start Worker"
    echo "3) Check Worker Status"
    echo "4) Stop Worker"
    echo "5) Restart Worker"
    echo "6) View Worker Logs"
    echo "7) Force Kill Worker Process"
    echo "8) Exit"
    echo "======================================"
    read -p "Choose an option: " choice

    case $choice in
        1) install_tools && detect_nvidia_gpu && install_kuzco ;;
        2) start_worker ;;
        3) check_worker_status ;;
        4) stop_worker ;;
        5) restart_worker ;;
        6) view_worker_logs ;;
        7) force_kill_worker ;;
        8) log_message "🚀 Exiting Kuzco Manager!"; exit 0 ;;
        *) log_message "❌ Invalid option, try again!" ;;
    esac
    read -rp "Press Enter to return to the main menu..."
done
