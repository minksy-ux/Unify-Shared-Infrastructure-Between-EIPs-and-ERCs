#!/usr/bin/env bash
# bootstrap.sh

set -euo pipefail

echo "Bootstrapping EIPs/ERCs development environment..."

if [ ! -d "infra/shared" ]; then
  echo "Adding shared infra submodule..."
  git submodule add https://github.com/ethereum/eip-infra.git infra/shared
fi

git submodule update --init --recursive

echo "Done! You are using shared infra at commit:"
git -C infra/shared log -1 --oneline --decorate
