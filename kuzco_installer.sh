#!/bin/bash

# Function to install Kuzco CLI
install_kuzco_cli() {
    echo "Installing Kuzco CLI..."
    curl -fsSL https://inference.supply/install.sh | sh
    if [[ $? -eq 0 ]]; then
        echo "✅ Kuzco CLI installed successfully!"
    else
        echo "❌ Error: Failed to install Kuzco CLI."
        exit 1
    fi
}

# Function to check if Kuzco CLI is installed
check_kuzco_cli() {
    if ! command -v kuzco &> /dev/null; then
        echo "⚠️ Kuzco CLI is not installed!"
        read -p "Would you like to install it now? (y/n): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            install_kuzco_cli
        else
            echo "❌ Kuzco CLI is required. Exiting..."
            exit 1
        fi
    fi
}

# Function to install Kuzco Worker Node
install_kuzco_worker() {
    read -p "Enter your Worker ID: " WORKER_ID
    read -p "Enter your Registration Code: " REG_CODE

    if [[ -z "$WORKER_ID" || -z "$REG_CODE" ]]; then
        echo "Error: Worker ID and Registration Code cannot be empty."
        return
    fi

    echo "Installing and starting Kuzco Worker Node..."
    sudo kuzco worker start --background --worker "$WORKER_ID" --code "$REG_CODE"

    if [[ $? -eq 0 ]]; then
        echo "✅ Kuzco Worker started successfully!"
    else
        echo "❌ Error: Failed to start Kuzco Worker."
    fi
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

# Check if Kuzco CLI is installed before showing the menu
check_kuzco_cli

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
    echo "6. Exit"
    echo "=========================="
    read -p "Select an option (1-6): " choice

    case $choice in
        1) install_kuzco_worker ;;
        2) check_worker_status ;;
        3) stop_worker ;;
        4) restart_worker ;;
        5) view_worker_logs ;;
        6) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid choice! Please enter a number between 1-6." ;;
    esac
    echo ""
done
