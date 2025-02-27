#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default ports
WEB_UI_PORT=8080
API_PORT=8000

# Default log level
LOG_LEVEL="info"
DEBUG_MODE=false

# Process command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            WEB_UI_PORT="$2"
            shift 2
            ;;
        --api-port)
            API_PORT="$2"
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
                echo -e "${RED}Error: --log-level requires a value${NC}"
                exit 1
            fi
            LOG_LEVEL="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --port PORT      Specify the port for the Web UI (default: 8080)"
            echo "  --api-port PORT  Specify the port for the REST API (default: 8000)"
            echo "  -d, --debug      Enable debug mode (sets log level to debug)"
            echo "  -t, --trace      Enable trace mode (sets log level to trace)"
            echo "  -l, --log-level LEVEL  Set specific log level (info, debug, trace, warn, error)"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Set environment variables for logging based on options
export ARANYA_LOG_LEVEL="${LOG_LEVEL}"
export RUST_LOG="${LOG_LEVEL},aranya_rest_api=${LOG_LEVEL},aranya_daemon=${LOG_LEVEL},aranya_web_ui=${LOG_LEVEL}"
export ARANYA_DAEMON="${LOG_LEVEL}"

if [ "$DEBUG_MODE" = true ]; then
    echo -e "${GREEN}Debug mode enabled. Log level: ${LOG_LEVEL}${NC}"
    echo -e "${GREEN}ARANYA_LOG_LEVEL=${ARANYA_LOG_LEVEL}${NC}"
    echo -e "${GREEN}ARANYA_DAEMON=${ARANYA_DAEMON}${NC}"
    echo -e "${GREEN}RUST_LOG=${RUST_LOG}${NC}"
fi

echo -e "${GREEN}Starting Aranya Web UI on port ${WEB_UI_PORT}...${NC}"
echo -e "${GREEN}Will connect to API on port ${API_PORT}...${NC}"
echo -e "${GREEN}Log level: ${LOG_LEVEL}${NC}"

# Determine the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Check if the REST API is running
if ! nc -z localhost $API_PORT >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: Aranya REST API doesn't appear to be running on port ${API_PORT}.${NC}"
    echo -e "${YELLOW}The Web UI will start, but won't be able to communicate with the API.${NC}"
    echo -e "${YELLOW}Please make sure the Aranya REST API is running on port ${API_PORT}.${NC}"
    echo -e "${YELLOW}You might want to run the start_aranya_rest_api.sh script first.${NC}"
    echo ""
    read -p "Do you want to continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Aborting...${NC}"
        exit 1
    fi
fi

# Build and run the web UI with configured ports
echo -e "${GREEN}Building and running the Aranya Web UI...${NC}"

# Change to the aranya directory
cd "$SCRIPT_DIR/aranya"
WEB_UI_DIR="$SCRIPT_DIR/aranya/crates/aranya-web-ui"

# Set environment variables
export ARANYA_WEB_UI_PORT=$WEB_UI_PORT
export ARANYA_API_PORT=$API_PORT
export ARANYA_LOG_LEVEL="${LOG_LEVEL}"
export RUST_LOG="${LOG_LEVEL},aranya_rest_api=${LOG_LEVEL},aranya_daemon=${LOG_LEVEL},aranya_web_ui=${LOG_LEVEL}"
export ARANYA_DAEMON="${LOG_LEVEL}"

# Create correct symlink for templates directory
if [ -e "templates" ]; then
    # If templates is a symlink, use rm -f, otherwise use rm -rf for directory
    if [ -L "templates" ]; then
        rm -f templates
    else
        echo -e "${YELLOW}Found existing templates directory, backing up before replacing with symlink...${NC}"
        # Save the existing templates directory with timestamp
        mv templates templates.backup.$(date +%Y%m%d%H%M%S)
    fi
fi
ln -sf "$WEB_UI_DIR/templates" templates

# Run from the base aranya directory
ARANYA_LOG_LEVEL="$LOG_LEVEL" ARANYA_DAEMON="$LOG_LEVEL" RUST_LOG="$RUST_LOG" cargo run --bin aranya-web-ui

echo -e "${GREEN}Aranya Web UI has been stopped.${NC}" 