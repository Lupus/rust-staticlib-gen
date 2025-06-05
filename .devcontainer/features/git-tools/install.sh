#!/usr/bin/env bash

set -euo pipefail

# Load EXISTING_NON_ROOT_USER from the common-utils feature file
source /usr/local/etc/vscode-dev-containers/common

if [ -z "${EXISTING_NON_ROOT_USER:-}" ]; then
  echo "Warning: EXISTING_NON_ROOT_USER is not set, defaulting to root"
  EXISTING_NON_ROOT_USER="root"
fi

# Install git-split
echo "(*) Installing git-split..."
(
  git clone https://github.com/tomjaguarpaw/git-split.git /tmp/git-split
  cd /tmp/git-split
  git -c advice.detachedHead=false checkout 2b723a7d859f4b6e568c087576a5dc6978df5047
  cp split.sh /usr/local/bin/git-split
  chmod +x /usr/local/bin/git-split
  rm -rf /tmp/git-split
)

# Install git-subrepo
echo "(*) Installing git-subrepo..."
(
  git clone https://github.com/ingydotnet/git-subrepo.git /tmp/git-subrepo
  cd /tmp/git-subrepo
  git -c advice.detachedHead=false checkout ec1d487312d6f20473b7eac94ef87d8bde422f8b # Release 0.4.9
  make install
  rm -rf /tmp/git-subrepo
)

# Install git-imerge
echo "(*) Installing git-imerge..."
pipx install git-imerge

# Install git-absorb
echo "(*) Installing git-absorb..."
su - "$EXISTING_NON_ROOT_USER" -c "cargo install git-absorb"

# Install git-interactive-rebase-tool
echo "(*) Installing git-interactive-rebase-tool..."
su - "$EXISTING_NON_ROOT_USER" -c "cargo install git-interactive-rebase-tool"

# Install tag-it
echo "(*) Installing tag-it..."
cp tag-it.sh /usr/local/bin/tag-it
chmod a+x /usr/local/bin/tag-it

echo "(*) Installing git-tools post-create script..."

# Create the post-create script
cat << 'EOF' > /usr/local/bin/git-tools-post-create-script.sh
#!/bin/sh
set -e
eval "$(opam env)"
git config --global sequence.editor interactive-rebase-tool
git config --global diff.external $(which patdiff-git-wrapper)
EOF

chmod +x /usr/local/bin/git-tools-post-create-script.sh

echo "Done!"
