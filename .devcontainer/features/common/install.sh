#!/usr/bin/env bash

set -euo pipefail

sudo apt-get update

echo "(*) Installing fzf..."
sudo apt-get install fzf

echo "Done!"
