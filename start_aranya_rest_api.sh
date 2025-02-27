#!/bin/bash

# Script to start the Aranya REST API server
# This script configures and starts the REST API server to communicate with the daemon

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Project directories
ARANYA_DIR="$(pwd)/aranya"

# Default configuration
BIND_ADDRESS="127.0.0.1"
PORT=8000  # Changed to 8000 to match the web UI default expectation
DAEMON_SOCK_PATH="/tmp/aranya-daemon.sock"
AFC_SHM_PATH="/aranya-afc.shm"
MAX_AFC_CHANNELS=1024
AFC_LISTEN_ADDRESS="127.0.0.1:0"

# Default log level
LOG_LEVEL="info"
DEBUG_MODE=false

# Process command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            PORT="$2"
            shift 2
            ;;
        --bind)
            BIND_ADDRESS="$2"
            shift 2
            ;;
        --daemon-socket)
            DAEMON_SOCK_PATH="$2"
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
            LOG_LEVEL="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --port PORT          Specify the port for the REST API (default: 8000)"
            echo "  --bind ADDRESS       Specify the bind address (default: 127.0.0.1)"
            echo "  --daemon-socket PATH Specify the daemon socket path (default: /tmp/aranya-daemon.sock)"
            echo "  -d, --debug          Enable debug mode (sets log level to debug)"
            echo "  -t, --trace          Enable trace mode (sets log level to trace)"
            echo "  -l, --log-level LEVEL Set specific log level (info, debug, trace, warn, error)"
            echo "  -h, --help           Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Check if aranya directory exists
if [ ! -d "$ARANYA_DIR" ]; then
    echo -e "${RED}Error: Aranya directory not found at $ARANYA_DIR${NC}"
    echo -e "${RED}Make sure to run this script from the root directory containing the aranya repo${NC}"
    exit 1
fi

# Set environment variables for logging
export ARANYA_LOG_LEVEL="${LOG_LEVEL}"
export RUST_LOG="${LOG_LEVEL},aranya_rest_api=${LOG_LEVEL},aranya_daemon=${LOG_LEVEL}"
export ARANYA_DAEMON="${LOG_LEVEL}"

if [ "$DEBUG_MODE" = true ]; then
    echo -e "${GREEN}Debug mode enabled. Log level: ${LOG_LEVEL}${NC}"
    echo -e "${GREEN}ARANYA_LOG_LEVEL=${ARANYA_LOG_LEVEL}${NC}"
    echo -e "${GREEN}ARANYA_DAEMON=${ARANYA_DAEMON}${NC}"
    echo -e "${GREEN}RUST_LOG=${RUST_LOG}${NC}"
fi

# Set environment variables for the REST API
export ARANYA_REST_BIND_ADDRESS="$BIND_ADDRESS"
export ARANYA_REST_PORT="$PORT"
export ARANYA_DAEMON_SOCK_PATH="$DAEMON_SOCK_PATH"
export ARANYA_AFC_SHM_PATH="$AFC_SHM_PATH"
export ARANYA_MAX_AFC_CHANNELS="$MAX_AFC_CHANNELS"
export ARANYA_AFC_LISTEN_ADDRESS="$AFC_LISTEN_ADDRESS"

echo -e "${GREEN}Starting Aranya REST API server with the following configuration:${NC}"
echo -e "  Bind Address: ${YELLOW}$BIND_ADDRESS${NC}"
echo -e "  Port: ${YELLOW}$PORT${NC}"
echo -e "  Daemon Socket Path: ${YELLOW}$DAEMON_SOCK_PATH${NC}"
echo -e "  AFC SHM Path: ${YELLOW}$AFC_SHM_PATH${NC}"
echo -e "  Max AFC Channels: ${YELLOW}$MAX_AFC_CHANNELS${NC}"
echo -e "  AFC Listen Address: ${YELLOW}$AFC_LISTEN_ADDRESS${NC}"
echo -e "  Log Level: ${YELLOW}$LOG_LEVEL${NC}"
echo

# Change to aranya directory to run cargo
cd "$ARANYA_DIR"

# Start the REST API server
echo -e "${GREEN}Starting the REST API server from $ARANYA_DIR...${NC}"
ARANYA_LOG_LEVEL="$LOG_LEVEL" ARANYA_DAEMON="$LOG_LEVEL" RUST_LOG="$RUST_LOG" cargo run --bin aranya-rest-api

echo -e "${GREEN}REST API server stopped${NC}" 