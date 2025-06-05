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

export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"

###############################################################################################
##########                                OPAM                                        #########
###############################################################################################

echo "(*) Initializing opam..."

opam init --bare --no-setup --bypass-checks --no-opamrc --disable-sandboxing --enable-shell-hook

echo "(*) Creating default opam switch..."

opam switch create 5.3.0 --no-install 
eval $(opam env)

echo "(*) Installing common tools into opam switch..."

opam install --yes opam-dune-lint ocaml-lsp-server patdiff utop

echo "(*) Configuring automatic opam environment initialization..."
cat ~/.opam/opam-init/init.sh >> ~/.bashrc
cat ~/.opam/opam-init/init.zsh >> ~/.zshrc

echo "Done!"
