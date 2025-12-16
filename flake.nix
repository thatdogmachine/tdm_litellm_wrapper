{
  description = "Development environment for litellm";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      supportedSystems = [ "aarch64-darwin" ];
      forAllSystems = lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (system: nixpkgs.legacyPackages.${system});

      # --- Configuration for LiteLLM ---
      litellmVersion = "v1.80.10.rc.2"; # <-- Git tag or commit for litellm eg "main"
      litellmPath = "../litellm"; # <-- Path to the litellm repository
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
          stdenv = pkgs.stdenv;
          pythonPackages = pkgs.python3Packages;

          # Define local scripts here
          gemini-script = pkgs.writeShellScriptBin "gemini-ap" ''
            #!/bin/sh
            npx @google/gemini-cli@0.9.0 --include-directories . ../litellm "$@"
          '';
          llxprt-script = pkgs.writeShellScriptBin "llxprt" ''
            #!/bin/sh
            npx @vybestack/llxprt-code@0.6.1 --include-directories . ../litellm "$@"
          '';
          
          # PostgreSQL status and management script
          postgres-status-script = pkgs.writeShellScriptBin "postgres-info" ''
            #!/bin/bash
            echo "=== PostgreSQL Server Information ==="
            
            if [ -z "$PGDATA" ]; then
              echo "ERROR: PGDATA environment variable not set."
              exit 1
            fi
            
            echo "Data Directory: $PGDATA"
            
            if [ ! -d "$PGDATA" ]; then
              echo "Status: Data directory does not exist. PostgreSQL has not been initialized."
              exit 1
            fi
            
            echo "Status: Checking server..."
            if ${pkgs.postgresql}/bin/pg_ctl -D "$PGDATA" status > /dev/null 2>&1; then
              echo "[OK] PostgreSQL server is RUNNING"
              echo ""
              echo "Connection Information:"
              echo "  Host: localhost"
              echo "  Port: 5432"
              echo "  Access method: trust (local connections)"
              echo ""
              echo "PostgreSQL Management Commands:"
              echo "  • Stop server:"
              echo "    pg_ctl -D \"$PGDATA\" stop"
              echo "  • View logs:"
              echo "    tail -f \"$PGDATA/postgres.log\""
              echo "  • Restart:"
              echo "    pg_ctl -D \"$PGDATA\" restart"
              echo ""
              echo "Databases:"
              if ${pkgs.postgresql}/bin/psql -d postgres -c "SELECT datname FROM pg_database WHERE datistemplate = false;" --username=postgres 2>/dev/null; then
                ${pkgs.postgresql}/bin/psql -d postgres -c "SELECT datname FROM pg_database WHERE datistemplate = false;" --username=postgres | tail -n +3 | head -n -2
              else
                echo "  No databases found or connection failed"
              fi
            else
              echo "[ERROR] PostgreSQL server is STOPPED"
              echo ""
              echo "To start PostgreSQL:"
              echo "  • Enter the nix shell (automatic)"
              echo "  • Or manually:"
              echo "    pg_ctl -D \"$PGDATA\" start"
            fi
            
            echo ""
            echo "=== LiteLLM Integration ==="
            echo "Example connection string for your config.yaml:"
            echo "  database_url: \"postgresql://postgres@localhost:5432/mylitellm\""
            echo ""
            echo "Database Management:"
            echo "  - List databases:"
            echo "    psql -U postgres -l"
            echo "  - Create a new database:"
            echo "    createdb -U postgres <new_db_name>"
            echo "  - Delete a database:"
            echo "    dropdb -U postgres <db_name_to_delete>"

            echo ""
            echo "Configuration Directory: $POSTGRES_CONFIG_DIR"
            echo "Main Config: $POSTGRES_CONFIG_DIR/postgresql.conf"
            echo "Auth Config: $POSTGRES_CONFIG_DIR/pg_hba.conf"
            
            echo ""
            echo "=== Troubleshooting ==="
            echo "!! IMPORTANT: If you see 'role \"postgres\" does not exist' errors, you must reset the database !!"
            echo "Run the command: \`postgres-reset\` and then restart the shell."
            echo ""
            echo "If the server seems running but is unresponsive, there might be a stale process."
            echo "Check for processes:"
            echo "  ps aux | grep postgres"
            echo "Force stop all processes:"
            echo "  pkill postgres"
            echo ""
            echo "If the database is corrupt (e.g., 'invalid checkpoint' errors), you can reset it."
            echo "Run the command:"
            echo "  postgres-reset"
            echo "Then, re-enter the 'nix develop' shell to re-initialize the database."
          '';

          # Help script for the development environment
          dev-help-script = pkgs.writeShellScriptBin "dev-help" ''
            #!/bin/bash
            echo "=== Development Environment Help ==="
            echo ""
            echo "Available custom commands:"
            echo "  - gemini-ap:         Run the Gemini CLI."
            echo "  - llxprt:            Run the llxprt CLI."
            echo "  - postgres-info:     Display status and info about the PostgreSQL server."
            echo "  - postgres-reset:    Deletes and resets the PostgreSQL database if it becomes corrupt."
            echo "  - dev-help:          Show this help message."
            echo ""
            
            echo "--- Python Virtual Environment ---"
            ${pkgs.poetry}/bin/poetry env info
            echo ""

            echo "--- PostgreSQL Server Information ---"
            if [ -z "$PGDATA" ]; then
              echo "ERROR: PGDATA environment variable not set."
            else
              if ${pkgs.postgresql}/bin/pg_ctl -D "$PGDATA" status > /dev/null 2>&1; then
                echo "Status: Server is running."
              elif ${pkgs.postgresql}/bin/pg_isready -h localhost -p 5432 > /dev/null 2>&1; then
                echo "Status: Stale process detected on port 5432. Run 'pkill postgres' and restart the shell."
              else
                echo "Status: Server is stopped."
              fi
              echo "  - Data directory: $PGDATA"
              echo "  - Log file: $PGDATA/postgres.log"
              echo ""
              echo "Management Commands:"
              echo "  - Start: (automatic on shell entry) or manually:"
              echo "    pg_ctl -D \"$PGDATA\" start"
              echo "  - Stop: exit the shell or manually:"
              echo "    pg_ctl -D \"$PGDATA\" stop"
              echo "  - Status:"
              echo "    pg_ctl -D \"$PGDATA\" status"
              echo "  - Logs:"
              echo "    tail -f \"$PGDATA/postgres.log\""
            fi
            echo ""
          '';

          # Script to reset the PostgreSQL database
          postgres-reset-script = pkgs.writeShellScriptBin "postgres-reset" ''
            #!/bin/bash
            echo "--- PostgreSQL Database Reset ---"
            if [ -z "$PGDATA" ]; then
              echo "ERROR: PGDATA environment variable not set. Must be run in the nix shell."
              exit 1
            fi
            
            echo "Stopping PostgreSQL server (if running)..."
            ${pkgs.postgresql}/bin/pg_ctl -D "$PGDATA" stop -m immediate > /dev/null 2>&1
            
            if [ -d "$PGDATA" ]; then
              echo "Deleting data directory: $PGDATA"
              rm -rf "$PGDATA"
              echo "Data directory deleted."
            else
              echo "Data directory does not exist. Nothing to delete."
            fi
            
            echo ""
            echo "PostgreSQL database has been reset."
            echo "Please exit and re-enter the 'nix develop' shell to re-initialize."
          '';
          
          venvDir = "./.venv";

        in
        {
          default = pkgs.mkShell {
            
            packages = with pkgs;[
              gemini-script
              nodejs_22
              nodePackages.prisma # prisma CLI for database migrations
              poetry
              llxprt-script
              postgres-status-script
              postgres-reset-script
              dev-help-script
              zsh
              postgresql
            ];

            buildInputs = [
              pythonPackages.python
            ];
            
            LITELLM_VERSION = litellmVersion;
            LITELLM_PATH = litellmPath;

            shellHook = ''
              unset SOURCE_DATE_EPOCH
              
              # --- 0. Define Paths ---
              export WRAPPER_DIR="$(pwd)"
              export LITELLM_DIR="$(cd "$LITELLM_PATH" && pwd)" # Resolve to absolute path
              # --- 1. LiteLLM Version Checkout & Tag Sync ---
              echo "--- Ensuring correct litellm version and tags ---"
              if [ -d "$LITELLM_DIR" ]; then
                (
                  cd "$LITELLM_DIR"

                  echo "--- Cleaning up git repository state ---"
                  find .git -type f -name "*.lock" -delete

                  echo "--- Fetching from remotes, avoiding problematic ref ---"
                  git fetch origin --tags --prune
                  
                  if git remote | grep -q "upstream"; then
                    # Fetch from upstream, but explicitly exclude the 'litellm_release_notes' branch
                    git fetch upstream --tags --prune "refs/heads/*:refs/remotes/upstream/*" "^refs/heads/litellm_release_notes" || echo "--- WARNING: Upstream fetch failed, continuing... ---"
                  fi

                  echo "--- Checking out version: $LITELLM_VERSION ---"
                  if git checkout "$LITELLM_VERSION" >/dev/null 2>&1; then
                      echo "--- litellm version set to $LITELLM_VERSION ---"
                  else
                      echo "--- ERROR: Failed to checkout litellm version '$LITELLM_VERSION'. Please check the version string in flake.nix. ---"
                      exit 1
                  fi
                )
              else
                echo "--- FATAL: litellm directory not found at '$LITELLM_DIR'. Aborting. ---"
                exit 1
              fi

              # --- 2. Environment Setup ---
              export POSTGRES_CONFIG_DIR="$WRAPPER_DIR/postgresql"
              export PGDATA="$POSTGRES_CONFIG_DIR/data"
              export POETRY_VIRTUALENVS_IN_PROJECT=true
              
              # --- 3. Venv Sync (in litellm dir) ---
              echo "--- Syncing Python Virtual Environment in $LITELLM_DIR ---"
              (
                cd "$LITELLM_DIR"
                ${pkgs.poetry}/bin/poetry install --with dev,proxy-dev --extras proxy
              )
              echo "--- Python environment is up to date. ---"
              VENV_DIR="$LITELLM_DIR/.venv"
              
              # Activate the virtual environment by adding it to the PATH
              export PATH="$VENV_DIR/bin:$PATH"

              # --- 4. Prisma Client Generation (in litellm dir) ---
              echo "--- Generating Prisma client ---"
              (
                cd "$LITELLM_DIR"
                ${pkgs.poetry}/bin/poetry run prisma generate
              )

              # --- 5. PostgreSQL Setup ---
              if [ ! -d "$PGDATA" ]; then
                echo "--- Initializing PostgreSQL data directory ---"
                mkdir -p "$POSTGRES_CONFIG_DIR"
                ${pkgs.postgresql}/bin/initdb -D "$PGDATA" --auth-local=trust --auth-host=trust -U postgres --no-locale
                echo "--- PostgreSQL data directory initialized with 'postgres' superuser. ---"
              else
                echo "--- PostgreSQL data directory already exists ---"
              fi

              if [ -f "$POSTGRES_CONFIG_DIR/postgresql.conf" ]; then
                echo "--- Applying custom PostgreSQL configuration ---"
                cp "$POSTGRES_CONFIG_DIR/postgresql.conf" "$PGDATA/postgresql.conf"
                cp "$POSTGRES_CONFIG_DIR/pg_hba.conf" "$PGDATA/pg_hba.conf"
              fi

              # Set a trap to stop the database when the shell exits.
              trap 'echo ""; echo "--- Stopping PostgreSQL server ---"; ${pkgs.postgresql}/bin/pg_ctl -D "$PGDATA" stop' EXIT

              # Check status using both pg_ctl and pg_isready to detect stale processes
              if ${pkgs.postgresql}/bin/pg_ctl -D "$PGDATA" status > /dev/null 2>&1; then
                # pg_ctl says it's running, which is the most reliable check.
                echo "--- PostgreSQL server for this project is already running. ---"
              elif ${pkgs.postgresql}/bin/pg_isready -h localhost -p 5432 > /dev/null 2>&1; then
                # pg_ctl failed, but the port is occupied. This indicates a stale process.
                echo "---"
                echo "--- WARNING: Stale PostgreSQL process detected. ---"
                echo "A PostgreSQL process is occupying port 5432 but does not belong to this project."
                echo "This can happen if a previous shell exited uncleanly."
                echo "To fix this, stop the stale process by running:"
                echo "  pkill postgres"
                echo "After running the command, please exit and re-enter the shell."
                echo "---"
              else
                # Both checks failed, so the server is definitely not running.
                echo "--- Starting PostgreSQL server ---"
                LOGFILE="$PGDATA/postgres.log"
                if ${pkgs.postgresql}/bin/pg_ctl -D "$PGDATA" -l "$LOGFILE" start; then
                  echo "--- PostgreSQL server started successfully ---"
                else
                  echo "--- ERROR: PostgreSQL failed to start. See log for details. ---"
                  tail -n 5 "$LOGFILE"
                fi
              fi
              
              # --- 6. Application Database Setup ---
              if ${pkgs.postgresql}/bin/pg_ctl -D "$PGDATA" status > /dev/null 2>&1; then
                # Check if we can connect as the 'postgres' user. This is the most reliable way
                # to determine if the DB is initialized correctly for our application.
                if ! ${pkgs.postgresql}/bin/psql -U postgres -c '\q' > /dev/null 2>&1; then
                  # The connection failed, which implies the 'postgres' role doesn't exist or auth is wrong.
                  echo "---"
                  echo "--- ERROR: PostgreSQL is not initialized with the correct 'postgres' user. ---"
                  echo "The database needs to be reset to create the correct user roles."
                  echo "Please run the command:"
                  echo "  postgres-reset"
                  echo "After the reset is complete, exit and re-enter this shell."
                  echo "---"
                else
                  # The 'postgres' role exists and we can connect. Proceed to check for the database.
                  echo "--- Ensuring 'mylitellm' database exists ---"
                  if ! ${pkgs.postgresql}/bin/psql -U postgres -lqt | cut -d \| -f 1 | grep -qw mylitellm; then
                    echo "Database 'mylitellm' not found. Creating..."
                    ${pkgs.postgresql}/bin/createdb -U postgres mylitellm
                    echo "Database 'mylitellm' created."
                  else
                    echo "Database 'mylitellm' already exists."
                  fi
                fi
              fi

              # --- 7. Environment ---
              export LD_LIBRARY_PATH=${lib.makeLibraryPath [stdenv.cc.cc]}
              
              echo ""
              echo "Welcome to the LiteLLM development environment."
              echo "Run 'dev-help' for a list of commands and environment details."
              echo "The 'litellm' repo is at: $LITELLM_DIR"
              echo ""
              echo "To start the LiteLLM Proxy Server, you can now run:"
              echo ""
              echo 'cd $LITELLM_DIR && EXPERIMENTAL_MULTI_INSTANCE_RATE_LIMITING="True" python litellm/proxy/proxy_cli.py --config "$WRAPPER_DIR/proxy_server_config-local-example.yaml" --host localhost --add_key "not-needed"'
              echo ""
              echo ""

              # --- 8. Zsh Shell Switch (LAST STEP) ---
              if [ -z "$IN_NIX_SHELL_ZSH" ]; then
                export IN_NIX_SHELL_ZSH=1
                export SHELL=${pkgs.zsh}/bin/zsh
                echo "Switching to zsh..."
                $SHELL
                exit
              fi
            '';
          };
        });
    };
}