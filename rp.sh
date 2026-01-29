#!/bin/bash

# LiteLLM Proxy Run Script
# This script provides options for running the litellm proxy with appropriate cache handling

set -e

# Default behavior: don't clear cache (Python will auto-recompile on changes)
CLEAR_CACHE=false
USE_POETRY=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --clear-cache)
            CLEAR_CACHE=true
            shift
            ;;
        --poetry)
            USE_POETRY=true
            shift
            ;;
        --plain-python)
            USE_POETRY=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --clear-cache    Clear Python cache before running (use when updating dependencies)"
            echo "  --poetry         Use poetry to run litellm (default)"
            echo "  --plain-python   Run with plain python (no poetry)"
            echo "  --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Run with poetry, no cache clear (recommended for dev)"
            echo "  $0 --clear-cache       # Clear cache before running"
            echo "  $0 --plain-python      # Run with plain python"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Source environment variables
if [ -f ./.env ]; then
    source ./.env
fi

# Determine LITELLM_DIR
if [ -z "$LITELLM_DIR" ]; then
    LITELLM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../litellm" && pwd)"
fi

# Determine WRAPPER_DIR
if [ -z "$WRAPPER_DIR" ]; then
    WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

echo "LiteLLM Proxy Configuration:"
echo "  LITELLM_DIR: $LITELLM_DIR"
echo "  WRAPPER_DIR: $WRAPPER_DIR"
echo ""

# Clear Python cache if requested
if [ "$CLEAR_CACHE" = true ]; then
    echo "Clearing Python cache..."
    find "$LITELLM_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$LITELLM_DIR" -name "*.pyc" -delete 2>/dev/null || true
    find "$LITELLM_DIR" -name "*.pyo" -delete 2>/dev/null || true
    echo "Python cache cleared"
fi

cd $LITELLM_DIR
pwd
python3 -m venv $LITELLM_DIR/.venv
source $LITELLM_DIR/.venv/bin/activate
pip3 install -e "$LITELLM_DIR" # > /dev/null 2>&1
    echo "repo re-linked."
    echo ""

python3 -c "import litellm.main; print(litellm.main.__file__)"  

# Run litellm
if [ "$USE_POETRY" = true ]; then
    echo "Starting litellm with poetry..."
    cd "$LITELLM_DIR"
    EXPERIMENTAL_MULTI_INSTANCE_RATE_LIMITING="True" poetry run litellm \
        --config "$WRAPPER_DIR/proxy_server_config-local-example.yaml" \
        --host 0.0.0.0
else
    echo "Starting litellm with plain python..."
    cd "$LITELLM_DIR"
    EXPERIMENTAL_MULTI_INSTANCE_RATE_LIMITING="True" python litellm/proxy/proxy_cli.py \
        --config "$WRAPPER_DIR/proxy_server_config-local-example.yaml" \
        --host 0.0.0.0
    # python3 repro_bug.py
    # python3 test_model_extraction.py
fi