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
          postgresql = pkgs.postgresql.withPackages (ps: [ ps.pgvector ]);

          db-backup-script = pkgs.writeShellScriptBin "db-backup" ''
            #!/usr/bin/env bash
            # Usage: db-backup [database_name]
            # If database_name is provided, backs up only that database.
            # If database_name is omitted, backs up ALL non-template databases.

            TIMESTAMP=$(date +%Y%m%d_%H%M%S)

            if [ -n "$1" ]; then
                DATABASES="$1"
            else
                # Fetch all databases except templates using unaligned output (-A) and tuples only (-t)
                DATABASES=$(psql -U postgres -A -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;")
            fi

            printf "\033[1;34m=== PostgreSQL Backup ===\033[0m\n"

            FAILURES=0
            for DB in $DATABASES; do
                BACKUP_FILE="./''${DB}-''${TIMESTAMP}.sql"
                printf "Backing up database '\033[1;33m%s\033[0m' to '%s'...\n" "$DB" "$BACKUP_FILE"

                # Use pg_dump to create a plain SQL backup.
                pg_dump -U postgres -F p "$DB" > "$BACKUP_FILE"

                if [ $? -eq 0 ]; then
                  printf "\033[1;32m✔ Backup successful: %s\033[0m\n" "$BACKUP_FILE"
                else
                  printf "\033[1;31m❌ Backup failed for: %s\033[0m\n" "$DB"
                  FAILURES=1
                fi
            done

            if [ "$FAILURES" -ne 0 ]; then
              exit 1
            fi
          '';

          db-restore-script = pkgs.writeShellScriptBin "db-restore" ''
            #!/usr/bin/env bash
            # Usage: db-restore <backup_file_path> [target_database_name]
            # If target_database_name is omitted, it attempts to infer it from the backup file name,
            # or defaults to 'mylitellm'.

            BACKUP_FILE="$1"
            if [ -z "$BACKUP_FILE" ]; then
              echo -e "\033[1;31m❌ Error: Backup file path is required.\033[0m"
              echo "Usage: db-restore <backup_file_path> [target_database_name]"
              exit 1
            fi

            # Attempt to infer DB name from common backup file naming convention
            # e.g., mylitellm-20231027_103000.sql -> mylitellm
            INFERRED_DB_NAME=$(basename "$BACKUP_FILE" | sed -E 's/-[0-9]{8}_[0-9]{6}\.sql$//; s/\.sql$//')
            TARGET_DB_NAME=''${2:-''${INFERRED_DB_NAME:-mylitellm}}

            echo -e "\033[1;34m=== PostgreSQL Restore ===\033[0m"
            echo "Backup File: $BACKUP_FILE"
            echo "Target Database: $TARGET_DB_NAME"

            read -p "This will drop and recreate the database '$TARGET_DB_NAME'. Are you sure? [y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
              echo "Restore cancelled."
              exit 0
            fi

            echo "Dropping and recreating database '$TARGET_DB_NAME'..."
            # Use psql to drop and create the database.
            psql -U postgres -c "DROP DATABASE IF EXISTS \"$TARGET_DB_NAME\";"
            if [ $? -ne 0 ]; then
              echo -e "\033[1;31m❌ Failed to drop database '$TARGET_DB_NAME'. Check permissions or if it's in use.\033[0m"
              exit 1
            fi

            psql -U postgres -c "CREATE DATABASE \"$TARGET_DB_NAME\";"
            if [ $? -ne 0 ]; then
              echo -e "\033[1;31m❌ Failed to create database '$TARGET_DB_NAME'.\033[0m"
              exit 1
            fi

            echo "Restoring data into '$TARGET_DB_NAME'..."
            # Use psql to restore from the SQL file.
            psql -U postgres -d "$TARGET_DB_NAME" < "$BACKUP_FILE"

            if [ $? -eq 0 ]; then
              echo -e "\033[1;32m✔ Restore successful.\033[0m"
            else
              echo -e "\033[1;31m❌ Restore failed.\033[0m"
              exit 1
            fi
          '';

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
            echo "  db-backup       : Backup PostgreSQL databases"
            echo "  db-restore      : Restore a PostgreSQL database from a backup file"
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
            ${postgresql}/bin/pg_ctl -D "$PGDATA" status
          '';

          postgres-reset-script = pkgs.writeShellScriptBin "postgres-reset" ''
            echo -e "\033[1;31m⚠️  WARNING: This will delete all data in $PGDATA\033[0m"
            read -p "Are you sure? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
              ${postgresql}/bin/pg_ctl -D "$PGDATA" stop -m immediate || true
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
              google-cloud-sdk
              nodejs_22
              nodePackages.prisma
              llxprt-script
              poetry postgres-status-script
              postgres-reset-script
              postgres-logs-script
              dev-help-script
              zsh
              postgresql
              redis
              pgadmin-start-script
              pgadmin4-desktopmode
              db-backup-script
              db-restore-script
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
                ${postgresql}/bin/initdb -D "$PGDATA" --auth-local=trust -U postgres --no-locale >/dev/null
              fi
              if ! ${postgresql}/bin/pg_ctl -D "$PGDATA" status > /dev/null 2>&1; then
                echo "--- Starting PostgreSQL server ---"
                ${postgresql}/bin/pg_ctl -D "$PGDATA" -l "$PGDATA/postgres.log" start >/dev/null
                echo "--- PostgreSQL server started. ---"
                ${postgresql}/bin/createdb -U postgres mylitellm 2>/dev/null || true
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
    ${postgresql}/bin/pg_ctl -D "$PGDATA" stop > /dev/null 2>&1
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