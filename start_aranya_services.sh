#!/bin/bash

# Script to start all Aranya services: daemon and REST API
# This script starts both services in the foreground with clean shutdown on Ctrl+C

set -e

# Display usage information
usage() {
    echo "Usage: $0 -p PORT -s SYNC_PORT [OPTIONS]"
    echo "Start Aranya daemon and REST API services."
    echo
    echo "Required arguments:"
    echo "  -p, --port PORT      Specify the REST API port"
    echo "  -s, --sync-port PORT Specify the Sync server port"
    echo
    echo "Optional arguments:"
    echo "  -d, --debug          Enable debug mode (sets log level to debug)"
    echo "  -t, --trace          Enable trace mode (sets log level to trace)"
    echo "  -l, --log-level LEVEL Set specific log level (info, debug, trace, warn, error)"
    echo "  -h, --help           Display this help message and exit"
    exit 1
}

# Parse command-line arguments
REST_PORT=""
SYNC_PORT=""
# Default log level
LOG_LEVEL="info"
DEBUG_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -p|--port)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: --port requires a value"
                usage
            fi
            REST_PORT="$2"
            shift 2
            ;;
        -s|--sync-port)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: --sync-port requires a value"
                usage
            fi
            SYNC_PORT="$2"
            shift 2
            ;;
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
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: --log-level requires a value"
                usage
            fi
            LOG_LEVEL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check if required arguments are provided
if [ -z "$REST_PORT" ] || [ -z "$SYNC_PORT" ]; then
    echo "Error: Both REST API port and Sync port must be specified"
    usage
fi

# Make scripts executable
chmod +x start_aranya_daemon.sh
chmod +x start_aranya_rest_api.sh

# Project directories
ARANYA_DIR="$(pwd)/aranya"

# Generate a unique identifier for this run
RUN_ID="aranya-$(date +%Y%m%d-%H%M%S)-$$"

# Create a unique base directory for this run
BASE_DIR="/tmp/$RUN_ID"
mkdir -p "$BASE_DIR"

# Configuration with unique paths
WORK_DIR="$BASE_DIR/work"
DAEMON_SOCK_PATH="$BASE_DIR/daemon.sock"
AFC_SHM_PATH="/aranya-$RUN_ID-afc.shm"  # Keep in root but with unique name
PID_FILE="$BASE_DIR/daemon.pid"
CONFIG_FILE="$BASE_DIR/daemon-config.json"
SYNC_ADDR="127.0.0.1:$SYNC_PORT"
MAX_AFC_CHANNELS=1024
AFC_LISTEN_ADDRESS="127.0.0.1:0"  # AFC still uses dynamic port for flexibility
BIND_ADDRESS="127.0.0.1"
PORT=$REST_PORT
NAME="aranya-daemon-$RUN_ID"  # Make daemon name unique
DAEMON_LOG="$BASE_DIR/daemon.log"
REST_API_LOG="$BASE_DIR/rest-api.log"

# Set environment variables for logging
export ARANYA_LOG_LEVEL="${LOG_LEVEL}"
export RUST_LOG="${LOG_LEVEL},aranya_rest_api=${LOG_LEVEL},aranya_daemon=${LOG_LEVEL}"
export ARANYA_DAEMON="${LOG_LEVEL}"

if [ "$DEBUG_MODE" = true ]; then
    echo "Debug mode enabled. Log level: ${LOG_LEVEL}"
    echo "ARANYA_LOG_LEVEL=${ARANYA_LOG_LEVEL}"
    echo "ARANYA_DAEMON=${ARANYA_DAEMON}"
    echo "RUST_LOG=${RUST_LOG}"
fi

# Function to clean up processes and files on exit
cleanup() {
    echo "Stopping Aranya services..."
    if [ -n "$DAEMON_PID" ]; then
        echo "Stopping daemon (PID $DAEMON_PID)..."
        kill $DAEMON_PID 2>/dev/null || true
    fi
    if [ -n "$REST_API_PID" ]; then
        echo "Stopping REST API (PID $REST_API_PID)..."
        kill $REST_API_PID 2>/dev/null || true
    fi
    
    # Give processes time to shut down cleanly
    sleep 2
    
    # Clean up the shared memory file if it exists
    if [ -e "$AFC_SHM_PATH" ]; then
        echo "Removing shared memory file $AFC_SHM_PATH"
        rm -f "$AFC_SHM_PATH"
    fi
    
    # Clean up the base directory and all its contents
    echo "Removing temporary directory $BASE_DIR"
    rm -rf "$BASE_DIR"
    
    echo "Cleanup complete."
    exit 0
}

# Set up trap to catch Ctrl+C and other termination signals
trap cleanup SIGINT SIGTERM EXIT

# Check if aranya directory exists
if [ ! -d "$ARANYA_DIR" ]; then
    echo "Error: Aranya directory not found at $ARANYA_DIR"
    echo "Make sure to run this script from the root directory containing the aranya repo"
    exit 1
fi

# Create working directory
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
        "unlink_at_exit": true,
        "create": true,
        "max_chans": $MAX_AFC_CHANNELS
    }
}
EOL

echo "Created Aranya daemon configuration at $CONFIG_FILE"
echo "Starting Aranya services from $ARANYA_DIR using unique run ID: $RUN_ID"
echo "All temporary files will be stored in $BASE_DIR"
echo "Using ports - REST API: $REST_PORT, Sync: $SYNC_PORT"

# Change to aranya directory to run cargo
cd "$ARANYA_DIR"

# Start the daemon in foreground mode, but save its PID
echo "Starting the daemon..."
ARANYA_LOG_LEVEL="$LOG_LEVEL" ARANYA_DAEMON="$LOG_LEVEL" RUST_LOG="$RUST_LOG" cargo run --bin aranya-daemon -- "$CONFIG_FILE" > "$DAEMON_LOG" 2>&1 &
DAEMON_PID=$!
echo "Daemon started with PID $DAEMON_PID (logs at $DAEMON_LOG)"

# Wait for daemon to start up
echo "Waiting for daemon to initialize..."
sleep 5

# Extract the AFC listen address port if available (still dynamic)
AFC_PORT=$(grep -o "AFC server listening on 127.0.0.1:[0-9]\+" "$DAEMON_LOG" | grep -o "[0-9]\+$" | tail -1)
if [ -n "$AFC_PORT" ]; then
    echo "AFC server is using port: $AFC_PORT"
    AFC_LISTEN_ADDRESS="127.0.0.1:$AFC_PORT"
fi

# Set environment variables for the REST API
export ARANYA_REST_BIND_ADDRESS="$BIND_ADDRESS"
export ARANYA_REST_PORT="$PORT"
export ARANYA_DAEMON_SOCK_PATH="$DAEMON_SOCK_PATH"
export ARANYA_AFC_SHM_PATH="$AFC_SHM_PATH"
export ARANYA_MAX_AFC_CHANNELS="$MAX_AFC_CHANNELS"
export ARANYA_AFC_LISTEN_ADDRESS="$AFC_LISTEN_ADDRESS"
# Keep log level settings 
export ARANYA_LOG_LEVEL="${LOG_LEVEL}"
export RUST_LOG="${LOG_LEVEL},aranya_rest_api=${LOG_LEVEL},aranya_daemon=${LOG_LEVEL}"
export ARANYA_DAEMON="${LOG_LEVEL}"

# Start the REST API in foreground mode, but save its PID
echo "Starting the REST API..."
ARANYA_LOG_LEVEL="$LOG_LEVEL" ARANYA_DAEMON="$LOG_LEVEL" RUST_LOG="$RUST_LOG" cargo run --bin aranya-rest-api > "$REST_API_LOG" 2>&1 &
REST_API_PID=$!
echo "REST API started with PID $REST_API_PID (logs at $REST_API_LOG)"

# Wait for REST API to start up
echo "Waiting for REST API to initialize..."
sleep 5

echo
echo "All Aranya services started!"
echo
echo "Instance ID: $RUN_ID"
echo "Log level: $LOG_LEVEL"
echo "REST API is available at http://$BIND_ADDRESS:$REST_PORT/api/v1"
echo
echo "Web UI can connect using the following settings:"
echo "  Daemon Socket Path: $DAEMON_SOCK_PATH"
echo "  AFC SHM Path: $AFC_SHM_PATH"
echo "  Max AFC Channels: $MAX_AFC_CHANNELS"
echo "  AFC Listen Address: $AFC_LISTEN_ADDRESS"
echo "  Sync Address: $SYNC_ADDR"
echo
echo "Press Ctrl+C to stop all services and clean up temporary files"
echo
echo "Watching logs in real-time:"
echo "------------------------"

# Use tail -f to follow both log files, blocking until Ctrl+C is pressed
tail -f "$DAEMON_LOG" "$REST_API_LOG" 