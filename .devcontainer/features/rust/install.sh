#!/usr/bin/env bash

set -euo pipefail

# Load EXISTING_NON_ROOT_USER from the common-utils feature file
source /usr/local/etc/vscode-dev-containers/common

if [ -z "${EXISTING_NON_ROOT_USER:-}" ]; then
  echo "Warning: EXISTING_NON_ROOT_USER is not set, defaulting to root"
  EXISTING_NON_ROOT_USER="root"
fi

if [ "${1:-}" != "--as-user" ]; then
  # Re-run the script as the target user, passing --as-user to avoid recursion
  SCRIPT=$(readlink -f "$0")
  PWD=$(pwd)
  exec su - "$EXISTING_NON_ROOT_USER" -c "bash -c \"cd $PWD && $SCRIPT --as-user\""
fi

# Install Rust
echo "(*) Installing Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Configure bash and zsh to source Rust environment
echo "(*) Configuring bash and zsh to source Rust environment..."

for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rcfile" ]; then
        if ! grep -q 'source "$HOME/.cargo/env"' "$rcfile" && ! grep -q '\. "$HOME/.cargo/env"' "$rcfile"; then
            echo 'Adding Rust environment source to '"$rcfile"
            echo '. "$HOME/.cargo/env"' >> "$rcfile"
        fi
    fi
done

echo "Done!"
