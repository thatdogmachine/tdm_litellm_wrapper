{
  description = "Development environment for litellm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      supportedSystems = [ "aarch64-darwin" ]; # inc: hardcoded container cli usage
      forAllSystems = lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (system: nixpkgs.legacyPackages.${system});

      litellmVer = "v1.80.10.rc.2";
      litellmRelPath = "../litellm";
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};

          dev-help-script = pkgs.writeShellScriptBin "dev-help" ''
            echo "----------------------------------------------------------------"
            echo -e "\033[1;36m LITELLM DEVELOPMENT ENVIRONMENT\033[0m"
            echo "----------------------------------------------------------------"
            echo "Commands:"
            echo "  dev-help        : Show this menu"
            echo "  gemini-ap       : Run Gemini CLI"
            echo "  llxprt          : Run llxprt CLI"
            echo "  pga             : Start pgAdmin 4 Desktop"
            echo "  exitkeep        : Exit shell but leave Postgres and Redis running"
            echo ""
            echo "PostgreSQL:"
            echo "  postgres-info   : Status and connection info"
            echo "  postgres-reset  : Factory reset the database"
            echo "  postgres-logs   : Tail database logs"
            echo ""
            echo "Redis:"
            echo "  redis-info      : Status and connection info (not yet implemented)"
            echo "  redis-logs      : Tail Redis logs (not yet implemented)"
            echo ""
            echo "LiteLLM Proxy:"
            echo "  To start the server, run: ./rp.sh"
            echo ""
            echo "Python Environment:"
            if [ -d "$LITELLM_DIR" ]; then
              (cd "$LITELLM_DIR" && ${pkgs.poetry}/bin/poetry env info | grep -E "^Python:" | head -n 1)
              echo "Virtual env"
              (cd "$LITELLM_DIR" && ${pkgs.poetry}/bin/poetry env info | grep -E "^Python:" | tail -n 1)
              echo "  Location: $LITELLM_DIR"
            fi
            echo "----------------------------------------------------------------"
          '';

          postgres-logs-script = pkgs.writeShellScriptBin "postgres-logs" ''
            tail -f "$PGDATA/postgres.log"
          '';

          postgres-status-script = pkgs.writeShellScriptBin "postgres-info" ''
            echo -e "\033[1;34m=== PostgreSQL Status ===\033[0m"
            ${pkgs.postgresql}/bin/pg_ctl -D "$PGDATA" status
          '';

          postgres-reset-script = pkgs.writeShellScriptBin "postgres-reset" ''
            echo -e "\033[1;31m⚠️  WARNING: This will delete all data in $PGDATA\033[0m"
            read -p "Are you sure? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
              ${pkgs.postgresql}/bin/pg_ctl -D "$PGDATA" stop -m immediate || true
              rm -rf "$PGDATA"
              echo -e "\033[1;32mDatabase wiped. Re-enter shell to re-init.\033[0m"
            fi
          '';

          llxprt-script = pkgs.writeShellScriptBin "llxprt" ''
            #!/bin/sh
            npx @vybestack/llxprt-code@0.7.0-nightly.251217.ed1785109 "$@"
            # 0.7.0-nightly.251217.ed1785109 fixes many scroll issues
          '';

          pgadmin-start-script = pkgs.writeShellScriptBin "pga" ''
            export PGADMIN_CONFIG_DIR="$WRAPPER_DIR/pgadmin_config"
            mkdir -p "$PGADMIN_CONFIG_DIR/data"
            
            # Add config directory to PYTHONPATH so config_local.py is imported
            export PYTHONPATH="$PGADMIN_CONFIG_DIR:$PYTHONPATH"
            
            echo -e "\033[1;32mStarting pgAdmin 4...\033[0m"
            echo "Data directory: $PGADMIN_CONFIG_DIR/data"
            
            ${pkgs.pgadmin4-desktopmode}/bin/pgadmin4
          '';
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              google-cloud-sdk nodejs_22 nodePackages.prisma
              llxprt-script
              poetry postgres-status-script postgres-reset-script
              postgres-logs-script dev-help-script zsh postgresql
              pkgs.redis pgadmin-start-script pkgs.pgadmin4-desktopmode
            ];

            LITELLM_TARGET_VERSION = litellmVer;

            shellHook = ''
              set -e
              export WRAPPER_DIR="$PWD"
              export LITELLM_DIR="$(cd "${litellmRelPath}" && pwd)"
              export PGDATA="$WRAPPER_DIR/postgresql/data"
              export REDIS_DIR="$WRAPPER_DIR/redis/data" # Define REDIS_DIR

              # 1. Resolve ZSH path
              DETECTED_ZSH=$(zsh -i -c 'echo $ZSH' 2>/dev/null | head -n 1)
              if [ -z "$DETECTED_ZSH" ]; then
                DETECTED_ZSH=$(readlink -f "/etc/profiles/per-user/$USER/share/oh-my-zsh" 2>/dev/null)
              fi

              # 2. Sync LiteLLM
              if [ -d "$LITELLM_DIR" ]; then
                echo "--- Attempting to update LiteLLM to $LITELLM_TARGET_VERSION ---"
                cd "$LITELLM_DIR" && git checkout "$LITELLM_TARGET_VERSION"
              fi

              # 3. Sync Python & Prisma
              echo "--- Syncing Python Environment & Prisma ---"
              (
                cd "$LITELLM_DIR"
                ${pkgs.poetry}/bin/poetry install --with dev,proxy-dev --extras "proxy extra_proxy caching" 2>/dev/null
                ${pkgs.poetry}/bin/poetry run prisma generate 2>/dev/null
              )
              export PATH="$LITELLM_DIR/.venv/bin:$PATH"

              # 4. DB Setup
              if [ ! -d "$PGDATA" ]; then
                echo "--- Initializing PostgreSQL data directory ---"
                mkdir -p "$(dirname "$PGDATA")"
                ${pkgs.postgresql}/bin/initdb -D "$PGDATA" --auth-local=trust -U postgres --no-locale >/dev/null
              fi
              if ! ${pkgs.postgresql}/bin/pg_ctl -D "$PGDATA" status > /dev/null 2>&1; then
                echo "--- Starting PostgreSQL server ---"
                ${pkgs.postgresql}/bin/pg_ctl -D "$PGDATA" -l "$PGDATA/postgres.log" start >/dev/null
                echo "--- PostgreSQL server started. ---"
                ${pkgs.postgresql}/bin/createdb -U postgres mylitellm 2>/dev/null || true
              else
                echo "--- PostgreSQL server already running. ---"
              fi

              # Redis 8 Stack Setup
              echo "--- Checking Redis Stack Status ---"
              
              if command -v container &> /dev/null; then
                  container system start # TODO: better error handling
                  # Capture the inspect output
                  STATUS=$(container inspect litellm-redis 2>/dev/null)
                  echo "\STATUS: $STATUS"
                  # Explicitly check for "[]" which means "Not Found"
                  if [ "$STATUS" = "[]" ] || [ -z "$STATUS" ]; then
                      echo "--- Starting Redis Stack Container (Search/JSON enabled) ---"
                      container run -d --name litellm-redis -p 6379:6379 redis/redis-stack-server:latest
                  else
                      echo "--- Redis Container is already running ---"
                  fi
              else
                  echo -e "\033[1;31mWarning: 'container' tool not found. Redis may not be running!\033[0m"
                  echo -e "   Manual install dependency on:"
                  echo -e "   https://github.com/apple/container"
                  exit 1
              fi

              # 4. Connection Health Check
              echo -n "Waiting for Redis connection..."
              MAX_RETRIES=10
              COUNT=0
              until redis-cli -p 6379 ping >/dev/null 2>&1; do
                 sleep 1
                 echo -n "."
                 COUNT=$((COUNT+1))
                 if [ $COUNT -ge $MAX_RETRIES ]; then
                    echo -e "\n\033[1;31mFailed to connect to Redis. Is the container running?\033[0m"
                    break
                 fi
              done
              echo " Connected to Redis!"

              # 5. Shell Handoff
              if [ -z "$IN_LITELLM_ZSH" ]; then
                export IN_LITELLM_ZSH=1
                ZDIR=$(mktemp -d)
                
                if [ -f "$HOME/.zshrc" ]; then
                  if [ -n "$DETECTED_ZSH" ]; then
                    sed "s|^source .*oh-my-zsh.sh|source $DETECTED_ZSH/oh-my-zsh.sh|g" "$HOME/.zshrc" > "$ZDIR/.zshrc.actual"
                  else
                    cp "$HOME/.zshrc" "$ZDIR/.zshrc.actual"
                  fi
                  USER_RC="source $ZDIR/.zshrc.actual"
                else
                  USER_RC="# No .zshrc"
                fi

                cat <<EOF > "$ZDIR/.zshrc"
export HOME="$HOME"
export USER="$USER"
export ZSH="$DETECTED_ZSH"
export LITELLM_DIR="$LITELLM_DIR"
export PGDATA="$PGDATA"
export DATABASE_URL="postgresql://postgres@localhost:5432/mylitellm"

$USER_RC

export PROMPT="%F{cyan}[litellm]%f \$PROMPT"

STOP_ON_EXIT=true
exitkeep() { 
  STOP_ON_EXIT=false
  echo -e "\033[1;32m✔ Postgres and Redis remain running.\033[0m"
  builtin exit
}

cleanup() { 
  if [ "\$STOP_ON_EXIT" = true ]; then 
    echo -e "\n\033[1;33m--- Stopping PostgreSQL server ---\033[0m"
    ${pkgs.postgresql}/bin/pg_ctl -D "\$PGDATA" stop > /dev/null 2>&1
    echo "--- PostgreSQL server stopped. ---"

    set -e
    echo -e "\n\033[1;33m--- Stopping Redis Stack container ---\033[0m"
    container stop "litellm-redis" >/dev/null 2>&1
    container rm "litellm-redis" >/dev/null 2>&1
    echo "--- Redis Stack container stopped and removed. ---"
  fi
  rm -rf "$ZDIR"
}
trap cleanup EXIT

dev-help
EOF
                export ZDOTDIR="$ZDIR"
                cd $WRAPPER_DIR
                exec ${pkgs.zsh}/bin/zsh -i
              fi
            '';
          };
        });
    };
}