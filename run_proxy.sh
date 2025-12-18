#!/bin/bash

source ./.env

cd $LITELLM_DIR && \
    EXPERIMENTAL_MULTI_INSTANCE_RATE_LIMITING="True" python litellm/proxy/proxy_cli.py \
        --config "$WRAPPER_DIR/proxy_server_config-local-example.yaml" \
        --host localhost