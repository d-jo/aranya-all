#!/bin/bash

# Script to start the Aranya daemon for use with the web UI
# This script creates a daemon configuration and starts the daemon

set -e

# Parse command line options
DEBUG_MODE=false
REST_API_ENABLED=true
LOG_LEVEL="info"

function show_help {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -d, --debug     Enable debug mode (sets log level to debug)"
    echo "  -t, --trace     Enable trace mode (sets log level to trace)" 
    echo "  -l, --log-level LEVEL  Set specific log level (info, debug, trace, warn, error)"
    echo "  --no-rest-api   Don't start the REST API"
    echo "  -h, --help      Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--debug)
            DEBUG_MODE=true
            LOG_LEVEL="debug"
            shift
            ;;
        -t|--trace)
            DEBUG_MODE=true
            LOG_LEVEL="trace"
            shift
            ;;
        -l|--log-level)
            LOG_LEVEL="$2"
            shift
            shift
            ;;
        --no-rest-api)
            REST_API_ENABLED=false
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

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
REST_API_PORT=8801
REST_API_BIND_ADDRESS="127.0.0.1"

# Set environment variables for logging based on options
export ARANYA_LOG_LEVEL="${LOG_LEVEL}"
# Also set RUST_LOG for backwards compatibility with other components
export RUST_LOG="${LOG_LEVEL},aranya_rest_api=${LOG_LEVEL},aranya_daemon=${LOG_LEVEL}"
# Set specific variable for aranya-daemon (which uses ARANYA_DAEMON env var)
export ARANYA_DAEMON="${LOG_LEVEL}"

if [ "$DEBUG_MODE" = true ]; then
    echo "Debug mode enabled. Log level: ${LOG_LEVEL}"
    echo "ARANYA_LOG_LEVEL=${ARANYA_LOG_LEVEL}"
    echo "ARANYA_DAEMON=${ARANYA_DAEMON}"
    echo "RUST_LOG=${RUST_LOG}"
fi

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
ARANYA_DAEMON="${LOG_LEVEL}" cargo run --bin aranya-daemon -- "$CONFIG_FILE" >  &
DAEMON_PID=$!

echo "Aranya daemon started with PID: $DAEMON_PID"
# Give the daemon a moment to start up
sleep 2

# Start the REST API if enabled
if [ "$REST_API_ENABLED" = true ]; then
    echo "Starting Aranya REST API..."
    # Set environment variables for the REST API
    export ARANYA_DAEMON_SOCK_PATH="$DAEMON_SOCK_PATH"
    export ARANYA_AFC_SHM_PATH="$AFC_SHM_PATH" 
    export ARANYA_MAX_AFC_CHANNELS="$MAX_AFC_CHANNELS"
    export ARANYA_AFC_LISTEN_ADDRESS="$AFC_LISTEN_ADDRESS"
    export ARANYA_REST_PORT="$REST_API_PORT"
    export ARANYA_REST_BIND_ADDRESS="$REST_API_BIND_ADDRESS"
    
    # Start the REST API
    cargo run --bin aranya-rest-api &
    REST_API_PID=$!
    echo "Aranya REST API started with PID: $REST_API_PID"
fi

echo
echo "Services are now running in the background. Press Ctrl+C to stop."
echo
echo "Web UI can connect using the following settings:"
echo "  Daemon Socket Path: $DAEMON_SOCK_PATH"
echo "  AFC SHM Path: $AFC_SHM_PATH"
echo "  Max AFC Channels: $MAX_AFC_CHANNELS"
echo "  AFC Listen Address: $AFC_LISTEN_ADDRESS"
if [ "$REST_API_ENABLED" = true ]; then
    echo "  REST API: http://${REST_API_BIND_ADDRESS}:${REST_API_PORT}"
fi
echo
echo "To manually start the REST API, you can use the following environment variables:"
echo "  ARANYA_LOG_LEVEL=${LOG_LEVEL}"
echo "  ARANYA_DAEMON=${LOG_LEVEL}"
echo "  RUST_LOG=${RUST_LOG}"
echo "  ARANYA_DAEMON_SOCK_PATH=$DAEMON_SOCK_PATH"
echo "  ARANYA_AFC_SHM_PATH=$AFC_SHM_PATH"
echo "  ARANYA_MAX_AFC_CHANNELS=$MAX_AFC_CHANNELS"
echo "  ARANYA_AFC_LISTEN_ADDRESS=$AFC_LISTEN_ADDRESS"
echo "  ARANYA_REST_PORT=$REST_API_PORT"
echo "  ARANYA_REST_BIND_ADDRESS=$REST_API_BIND_ADDRESS"

# Wait for user to press Ctrl+C
function cleanup {
    echo "Stopping services..."
    if [ "$REST_API_ENABLED" = true ]; then
        kill $REST_API_PID 2>/dev/null || true
    fi
    kill $DAEMON_PID 2>/dev/null || true
    echo "Services stopped."
    exit 0
}

trap cleanup INT TERM
wait 