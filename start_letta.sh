#!/bin/bash

# 1. Configuration
# Try to get bridge IP (container gateway), fallback to en0
export HOST_IP=$(ifconfig bridge100 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -n 1)
if [ -z "$HOST_IP" ]; then
    export HOST_IP=$(ipconfig getifaddr en0)
fi
IMAGE="letta/letta:latest"
CONTAINER_NAME="letta-server"
LLM_MODEL="openai/glm-4-5-air-mlx" # letta server bug?
# LLM_MODEL="openai/glm-4-5-air-mlx"
EMBED_MODEL="openai/local-bge-small-en-v1-5"

echo "Using Host IP: $HOST_IP"

# 2. Cleanup
container stop $CONTAINER_NAME 2>/dev/null
container rm $CONTAINER_NAME 2>/dev/null

# 3. Start Letta Server
echo "Starting Letta Server..."
container run \
  --name $CONTAINER_NAME \
  --detach \
  -p 8283:8283 \
  -e LETTA_PG_URI="postgresql://letta@$HOST_IP:5432/letta" \
  -e OPENAI_API_BASE="http://$HOST_IP:4000/v1" \
  -e OPENAI_API_KEY="sk-1234" \
  -e LETTA_LLM_ENDPOINT_TYPE="openai" \
  -e LETTA_LLM_MODEL="$LLM_MODEL" \
  -e LETTA_LLM_CONTEXT_WINDOW="260000" \
  -e LETTA_EMBEDDING_ENDPOINT_TYPE="openai" \
  -e LETTA_EMBEDDING_MODEL="$EMBED_MODEL" \
  -e LETTA_EMBEDDING_DIM="384" \
  -e SECURE=false \
  $IMAGE

# 4. Wait for Health Check
echo "Waiting for server to initialize..."
until curl -s -L http://localhost:8283/v1/health/ | grep -q "ok"; do
    printf '.'
    sleep 2
done
echo -e "\nServer is UP."

# 5. Create the 'skills' block independently (Required for 0.16.x)
echo "Initializing core memory blocks..."
BLOCK_RESPONSE=$(curl -s -L --post301 --post302 --post303 \
     -X POST "http://localhost:8283/v1/blocks/" \
     -H "Content-Type: application/json" \
     -d '{"label": "skills", "value": " ", "limit": 10000}')

BLOCK_ID=$(echo "$BLOCK_RESPONSE" | grep -oE "block-[a-z0-9-]{36}" | head -n 1)

if [ -z "$BLOCK_ID" ]; then
    echo "Fatal: Could not create skills block. Response: $BLOCK_RESPONSE"
    exit 1
fi

# 6. Create Agent and link the Block ID directly
echo "Creating Agent and linking memory..."
AGENT_RESPONSE=$(curl -s -L --post301 --post302 --post303 \
     -X POST "http://localhost:8283/v1/agents/" \
     -H "Content-Type: application/json" \
     -d '{
       "name": "letta_code_clean",
       "model": "'$LLM_MODEL'",
       "embedding": "'$EMBED_MODEL'",
       "block_ids": ["'$BLOCK_ID'"],
       "llm_config": {
         "model": "'$LLM_MODEL'",
         "model_endpoint_type": "openai",
         "model_endpoint": "http://'$HOST_IP':4000/v1",
         "context_window": 260000
       },
       "embedding_config": {
         "embedding_model": "'$EMBED_MODEL'",
         "embedding_endpoint_type": "openai",
         "embedding_endpoint": "http://'$HOST_IP':4000/v1",
         "embedding_dim": 384
       }
     }')

AGENT_ID=$(echo "$AGENT_RESPONSE" | grep -oE "agent-[a-z0-9-]{36}" | head -n 1)

if [ -z "$AGENT_ID" ]; then
    echo "Fatal: Agent creation failed. Response: $AGENT_RESPONSE"
    exit 1
fi

echo "Agent ready: $AGENT_ID"
echo "------------------------------------------------"

# 7. Execute Letta Code
LETTA_BASE_URL="http://localhost:8283" npx @letta-ai/letta-code --agent "$AGENT_ID"