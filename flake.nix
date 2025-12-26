{
  description = "Development environment for litellm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      supportedSystems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (system: nixpkgs.legacyPackages.${system});

      litellmVer = "v1.80.10.rc.3";
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
            echo "  exitkeep        : Exit shell but leave Postgres running"
            echo ""
            echo "PostgreSQL:"
            echo "  postgres-info   : Status and connection info"
            echo "  postgres-reset  : Factory reset the database"
            echo "  postgres-logs   : Tail database logs"
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

          gemini-script = pkgs.writeShellScriptBin "gemini" ''
            #!/bin/sh
            npx @google/gemini-cli@0.22.2                              --include-directories . --include-directories ../litellm "$@"
          '';
          gemini-script-ap = pkgs.writeShellScriptBin "gemini-ap" ''
            #!/bin/sh
            npx @google/gemini-cli@0.9.0                              --include-directories . --include-directories ../litellm --include-directories ../llxprt-code --include-directories ../goose "$@"
          '';
          llxprt-script = pkgs.writeShellScriptBin "llxprt" ''
            #!/bin/sh
            npx @vybestack/llxprt-code@0.7.0-nightly.251217.ed1785109 --include-directories . --include-directories ../litellm --include-directories ../llxprt-code --include-directories ../goose "$@"
            # 0.7.0-nightly.251217.ed1785109 fixes many scroll issues
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

        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              google-cloud-sdk nodejs_22
              nodePackages.prisma
              poetry postgres-status-script
              postgres-reset-script
              postgres-logs-script
              dev-help-script
              gemini-script
              gemini-script-ap
              llxprt-script
              zsh
              postgresql
            ];

            LITELLM_TARGET_VERSION = litellmVer;

            shellHook = ''
              export WRAPPER_DIR="$PWD"
              export LITELLM_DIR="$(cd "${litellmRelPath}" && pwd)"
              export PGDATA="$WRAPPER_DIR/postgresql/data"

              # 1. Resolve ZSH path
              DETECTED_ZSH=$(zsh -i -c 'echo $ZSH' 2>/dev/null | head -n 1)
              if [ -z "$DETECTED_ZSH" ]; then
                DETECTED_ZSH=$(readlink -f "/etc/profiles/per-user/$USER/share/oh-my-zsh" 2>/dev/null)
              fi

              # 2. Sync LiteLLM
              if [ -d "$LITELLM_DIR" ]; then
                echo "--- Updating LiteLLM to $LITELLM_TARGET_VERSION ---"
                (cd "$LITELLM_DIR" && git checkout "$LITELLM_TARGET_VERSION" 2>/dev/null)
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
                ${pkgs.postgresql}/bin/createdb -U postgres mylitellm 2>/dev/null || true
              fi

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
  echo -e "\033[1;32m✔ Postgres remains running.\033[0m"
  builtin exit
}

cleanup() { 
  if [ "\$STOP_ON_EXIT" = true ]; then 
    echo -e "\n\033[1;33m--- Stopping PostgreSQL server ---\033[0m"
    ${pkgs.postgresql}/bin/pg_ctl -D "\$PGDATA" stop > /dev/null 2>&1
  fi
  rm -rf "$ZDIR"
}
trap cleanup EXIT

dev-help
EOF
                export ZDOTDIR="$ZDIR"
                exec ${pkgs.zsh}/bin/zsh -i
              fi
            '';
          };
        });
    };
}