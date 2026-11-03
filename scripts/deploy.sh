#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DOCKERHUB_USERNAME:=harathi2026}"
: "${IMAGE_TAG:?Set IMAGE_TAG to an actually published successful CI 40-character SHA}"
export DOCKERHUB_USERNAME IMAGE_TAG
bash scripts/01-prepare-env.sh
bash scripts/02-apply-prerequisites.sh
bash scripts/03-deploy-in-order.sh
bash scripts/04-verify.sh
