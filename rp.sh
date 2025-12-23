#!/bin/bash

source ./.env

# cd $LITELLM_DIR && \
#     EXPERIMENTAL_MULTI_INSTANCE_RATE_LIMITING="True" python litellm/proxy/proxy_cli.py \
#         --config "$WRAPPER_DIR/proxy_server_config-local-example.yaml" \
#         --host localhost

# align with:
# https://github.com/BerriAI/litellm/blob/main/CONTRIBUTING.md?plain=1#L228
cd $LITELLM_DIR && \
    EXPERIMENTAL_MULTI_INSTANCE_RATE_LIMITING="True" poetry run litellm \
        --config "$WRAPPER_DIR/proxy_server_config-local-example.yaml" \
        --host localhost