#!/bin/bash

# Script to start the Aranya daemon for use with the web UI
# This script creates a daemon configuration and starts the daemon

set -e

# Project directories
ARANYA_DIR="$(pwd)/aranya"

# Configuration
WORK_DIR="/tmp/aranya-work"
DAEMON_SOCK_PATH="/tmp/aranya-daemon.sock"
AFC_SHM_PATH="/aranya-afc.shm"
PID_FILE="/tmp/aranya-daemon.pid"
CONFIG_FILE="/tmp/aranya-daemon-config.json"
SYNC_ADDR="127.0.0.1:4321"
MAX_AFC_CHANNELS=1024
AFC_LISTEN_ADDRESS="127.0.0.1:0"
NAME="aranya-daemon"

# Check if aranya directory exists
if [ ! -d "$ARANYA_DIR" ]; then
    echo "Error: Aranya directory not found at $ARANYA_DIR"
    echo "Make sure to run this script from the root directory containing the aranya repo"
    exit 1
fi

# Create working directory if it doesn't exist
mkdir -p "$WORK_DIR"

# Create configuration file
cat > "$CONFIG_FILE" << EOL
{
    "name": "$NAME",
    "work_dir": "$WORK_DIR",
    "uds_api_path": "$DAEMON_SOCK_PATH",
    "pid_file": "$PID_FILE",
    "sync_addr": "$SYNC_ADDR",
    "afc": {
        "shm_path": "$AFC_SHM_PATH",
        "unlink_on_startup": true,
        "unlink_at_exit": false,
        "create": true,
        "max_chans": $MAX_AFC_CHANNELS
    }
}
EOL

echo "Created Aranya daemon configuration at $CONFIG_FILE"
echo "Starting Aranya daemon from $ARANYA_DIR..."

# Change to aranya directory to run cargo
cd "$ARANYA_DIR"

# Start the daemon
cargo run --bin aranya-daemon -- "$CONFIG_FILE"

# Note: the script will exit when the daemon is stopped
# The daemon will continue running in the background

echo "Aranya daemon started"
echo
echo "Web UI can connect using the following settings:"
echo "  Daemon Socket Path: $DAEMON_SOCK_PATH"
echo "  AFC SHM Path: $AFC_SHM_PATH"
echo "  Max AFC Channels: $MAX_AFC_CHANNELS"
echo "  AFC Listen Address: $AFC_LISTEN_ADDRESS"
echo
echo "To start the REST API, you can use the following environment variables:"
echo "  ARANYA_DAEMON_SOCK_PATH=$DAEMON_SOCK_PATH"
echo "  ARANYA_AFC_SHM_PATH=$AFC_SHM_PATH"
echo "  ARANYA_MAX_AFC_CHANNELS=$MAX_AFC_CHANNELS"
echo "  ARANYA_AFC_LISTEN_ADDRESS=$AFC_LISTEN_ADDRESS" 