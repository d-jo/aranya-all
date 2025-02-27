#!/bin/bash

# Script to spawn Aranya instances and get device IDs via REST API

set -e

# Default number of instances and ports
NUM_INSTANCES=10
BASE_REST_PORT=8800
BASE_SYNC_PORT=9900
# Default log level
LOG_LEVEL="info"
DEBUG_MODE=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--num-instances)
            if [[ -z "$2" || "$2" =~ ^- ]]; then
                echo "Error: --num-instances requires a value"
                exit 1
            fi
            NUM_INSTANCES="$2"
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
                exit 1
            fi
            LOG_LEVEL="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Spawn multiple Aranya instances and query their device IDs."
            echo
            echo "Options:"
            echo "  -n, --num-instances N    Number of instances to spawn (default: 10)"
            echo "  -d, --debug              Enable debug mode (sets log level to debug)"
            echo "  -t, --trace              Enable trace mode (sets log level to trace)" 
            echo "  -l, --log-level LEVEL    Set specific log level (info, debug, trace, warn, error)"
            echo "  -h, --help               Display this help message and exit"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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

# Project directory
ARANYA_DIR="$(pwd)/aranya"

# Check if aranya directory exists
if [ ! -d "$ARANYA_DIR" ]; then
    echo "Error: Aranya directory not found at $ARANYA_DIR"
    echo "Make sure to run this script from the root directory containing the aranya repo"
    exit 1
fi

# Create a temp directory for instance data
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Array to track PIDs for both the daemon and REST API
declare -a DAEMON_PIDS
declare -a REST_PIDS

# Cleanup function
cleanup() {
    echo "Terminating all Aranya instances..."
    
    # Kill all processes by their stored PIDs
    for i in "${!DAEMON_PIDS[@]}"; do
        if ps -p ${DAEMON_PIDS[$i]} > /dev/null 2>&1; then
            echo "Killing daemon process ${DAEMON_PIDS[$i]}"
            kill ${DAEMON_PIDS[$i]} 2>/dev/null || true
        fi
    done
    
    for i in "${!REST_PIDS[@]}"; do
        if ps -p ${REST_PIDS[$i]} > /dev/null 2>&1; then
            echo "Killing REST API process ${REST_PIDS[$i]}"
            kill ${REST_PIDS[$i]} 2>/dev/null || true
        fi
    done
    
    # Give processes time to shut down
    sleep 2
    
    # Force kill any remaining processes
    for i in "${!DAEMON_PIDS[@]}"; do
        if ps -p ${DAEMON_PIDS[$i]} > /dev/null 2>&1; then
            kill -9 ${DAEMON_PIDS[$i]} 2>/dev/null || true
        fi
    done
    
    for i in "${!REST_PIDS[@]}"; do
        if ps -p ${REST_PIDS[$i]} > /dev/null 2>&1; then
            kill -9 ${REST_PIDS[$i]} 2>/dev/null || true
        fi
    done
    
    # Clean up shared memory files
    find / -maxdepth 1 -name "aranya-instance-*-afc.shm" -user $(whoami) -exec rm -f {} \; 2>/dev/null || true
    
    # Remove temp directory
    rm -rf "$TEMP_DIR" || true
    
    echo "All instances terminated."
    exit 0
}

# Set up trap
trap cleanup SIGINT SIGTERM EXIT

# Function to check if port is available
is_port_available() {
    local port=$1
    if command -v lsof &> /dev/null; then
        if lsof -i :$port -sTCP:LISTEN &> /dev/null; then
            return 1  # Port is in use
        fi
    elif command -v netstat &> /dev/null; then
        if netstat -tuln | grep ":$port " &> /dev/null; then
            return 1  # Port is in use
        fi
    fi
    return 0  # Port is available
}

echo "Starting $NUM_INSTANCES Aranya instances in parallel..."

# First, prepare all port assignments and configurations
declare -a REST_PORTS
declare -a SYNC_PORTS
declare -a INSTANCE_DIRS

for i in $(seq 1 $NUM_INSTANCES); do
    # Find available ports
    REST_PORT=$((BASE_REST_PORT + i))
    while ! is_port_available $REST_PORT; do
        echo "Port $REST_PORT is in use, trying next port..."
        REST_PORT=$((REST_PORT + 1))
    done
    REST_PORTS[$i]=$REST_PORT
    
    SYNC_PORT=$((BASE_SYNC_PORT + i))
    while ! is_port_available $SYNC_PORT; do
        echo "Port $SYNC_PORT is in use, trying next port..."
        SYNC_PORT=$((SYNC_PORT + 1))
    done
    SYNC_PORTS[$i]=$SYNC_PORT
    
    # Create instance directory
    INSTANCE_DIR="$TEMP_DIR/instance_$i"
    INSTANCE_DIRS[$i]=$INSTANCE_DIR
    mkdir -p "$INSTANCE_DIR"
    mkdir -p "$INSTANCE_DIR/work"
    
    # Save port information for later use
    echo "REST_PORT=$REST_PORT" > "$INSTANCE_DIR/ports.txt"
    echo "SYNC_PORT=$SYNC_PORT" >> "$INSTANCE_DIR/ports.txt"
    
    # Create configuration file
    RUN_ID="aranya-instance-$i"
    DAEMON_SOCK_PATH="$INSTANCE_DIR/daemon.sock"
    AFC_SHM_PATH="/$RUN_ID-afc.shm"
    PID_FILE="$INSTANCE_DIR/daemon.pid"
    CONFIG_FILE="$INSTANCE_DIR/config.json"
    
    cat > "$CONFIG_FILE" << EOL
{
    "name": "$RUN_ID",
    "work_dir": "$INSTANCE_DIR/work",
    "uds_api_path": "$DAEMON_SOCK_PATH",
    "pid_file": "$PID_FILE",
    "sync_addr": "127.0.0.1:$SYNC_PORT",
    "afc": {
        "shm_path": "$AFC_SHM_PATH",
        "unlink_on_startup": true,
        "unlink_at_exit": true,
        "create": true,
        "max_chans": 1024
    }
}
EOL
    
    # Save paths for later use
    echo "$AFC_SHM_PATH" > "$INSTANCE_DIR/afc_path.txt"
    echo "$CONFIG_FILE" > "$INSTANCE_DIR/config_path.txt"
    echo "$DAEMON_SOCK_PATH" > "$INSTANCE_DIR/sock_path.txt"
    
    echo "Prepared configuration for instance $i (REST port: $REST_PORT, Sync port: $SYNC_PORT)"
done

# Now start all daemons in parallel
echo "Starting all daemon instances..."
for i in $(seq 1 $NUM_INSTANCES); do
    INSTANCE_DIR="${INSTANCE_DIRS[$i]}"
    CONFIG_FILE=$(cat "$INSTANCE_DIR/config_path.txt")
    
    # Start the daemon in background
    (cd "$ARANYA_DIR" && ARANYA_LOG_LEVEL="$LOG_LEVEL" ARANYA_DAEMON="$LOG_LEVEL" RUST_LOG="$RUST_LOG" cargo run --bin aranya-daemon -- "$CONFIG_FILE" > "$INSTANCE_DIR/daemon.log" 2>&1) &
    DAEMON_PID=$!
    DAEMON_PIDS[$i]=$DAEMON_PID
    echo $DAEMON_PID > "$INSTANCE_DIR/daemon.pid"
    echo "Started daemon for instance $i (PID: $DAEMON_PID)"
done

# Wait briefly for daemons to start
echo "Waiting for daemons to initialize (10 seconds)..."
sleep 10

# Now start all REST APIs in parallel
echo "Starting all REST API instances..."
for i in $(seq 1 $NUM_INSTANCES); do
    INSTANCE_DIR="${INSTANCE_DIRS[$i]}"
    REST_PORT="${REST_PORTS[$i]}"
    DAEMON_SOCK_PATH=$(cat "$INSTANCE_DIR/sock_path.txt")
    AFC_SHM_PATH=$(cat "$INSTANCE_DIR/afc_path.txt")
    
    # Set environment variables for the REST API
    (
        cd "$ARANYA_DIR" 
        ARANYA_LOG_LEVEL="$LOG_LEVEL" \
        RUST_LOG="$RUST_LOG" \
        ARANYA_REST_BIND_ADDRESS="127.0.0.1" \
        ARANYA_REST_PORT="$REST_PORT" \
        ARANYA_DAEMON_SOCK_PATH="$DAEMON_SOCK_PATH" \
        ARANYA_AFC_SHM_PATH="$AFC_SHM_PATH" \
        ARANYA_MAX_AFC_CHANNELS="1024" \
        ARANYA_AFC_LISTEN_ADDRESS="127.0.0.1:0" \
        ARANYA_SKIP_TRACING_INIT="true" \
        cargo run --bin aranya-rest-api > "$INSTANCE_DIR/rest.log" 2>&1
    ) &
    REST_PID=$!
    REST_PIDS[$i]=$REST_PID
    echo $REST_PID > "$INSTANCE_DIR/rest.pid"
    echo "Started REST API for instance $i (PID: $REST_PID, Port: $REST_PORT)"
done

# Wait for all REST APIs to initialize
echo "Waiting for all REST APIs to initialize (10 seconds)..."
sleep 10

echo "Retrieving device IDs from all instances..."
echo "----------------------------------------"
echo "Instance | REST Port | Device ID"
echo "----------------------------------------"

# Query each instance for its device ID using the /device/id endpoint
for i in $(seq 1 $NUM_INSTANCES); do
    INSTANCE_DIR="${INSTANCE_DIRS[$i]}"
    
    # Get the REST port from the saved configuration
    source "$INSTANCE_DIR/ports.txt"
    
    # Check if REST API is still running
    if [ -f "$INSTANCE_DIR/rest.pid" ]; then
        REST_PID=$(cat "$INSTANCE_DIR/rest.pid")
        if ! ps -p $REST_PID > /dev/null; then
            echo "Warning: REST API for instance $i has crashed or failed to start"
            # Display log tail for troubleshooting
            tail -n 5 "$INSTANCE_DIR/rest.log"
            printf "%-9s| %-10s| %s\n" "$i" "$REST_PORT" "ERROR: REST API not running"
            continue
        fi
    else
        printf "%-9s| %-10s| %s\n" "$i" "$REST_PORT" "ERROR: No PID file found"
        continue
    fi
    
    # Query the device ID with retries
    MAX_RETRIES=3
    RETRY_COUNT=0
    DEVICE_ID="ERROR: Could not connect"
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        DEVICE_ID=$(curl -s -m 5 "http://127.0.0.1:$REST_PORT/api/v1/device/id" 2>/dev/null || echo "ERROR: Could not connect")
        if [[ "$DEVICE_ID" != ERROR* ]]; then
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        sleep 1
    done
    
    # Display the result
    printf "%-9s| %-10s| %s\n" "$i" "$REST_PORT" "$DEVICE_ID"
    
    # If we still couldn't connect, show more diagnostic info
    if [[ "$DEVICE_ID" == ERROR* ]]; then
        # Use verbose curl for more detailed error info
        curl -v -m 5 "http://127.0.0.1:$REST_PORT/api/v1/device/id" 2>&1 | head -n 20
        
        # Check if process is listening on the expected port
        if command -v lsof &> /dev/null; then
            LISTENING_PORT=$(lsof -Pan -p $REST_PID -i | grep LISTEN | awk '{print $9}' | sed 's/.*://' | head -1)
            if [ -n "$LISTENING_PORT" ] && [ "$LISTENING_PORT" != "$REST_PORT" ]; then
                echo "Instance $i is actually listening on port $LISTENING_PORT instead of $REST_PORT"
                # Try with the correct port
                curl -s -m 5 "http://127.0.0.1:$LISTENING_PORT/api/v1/device/id" || echo "Still could not connect"
            fi
        fi
    fi
done

echo "----------------------------------------"
echo "All instances are running. Instances will be terminated when you press Ctrl+C."
echo "Logs are stored in $TEMP_DIR if you need to investigate issues."
echo "Log level: $LOG_LEVEL"
echo "ARANYA_LOG_LEVEL=$ARANYA_LOG_LEVEL"
echo "ARANYA_DAEMON=$ARANYA_DAEMON"
echo "RUST_LOG=$RUST_LOG"

# Keep the script running until Ctrl+C
while true; do
    sleep 1
done

