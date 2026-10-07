#!/usr/bin/env bash
set -euo pipefail

PLATFORM="${PLATFORM:-linux/arm64}"
API_SRC="${API_SRC:-../ReqsAI/reqsai-api}"
WEB_SRC="${WEB_SRC:-../ReqsAI/reqsai-web}"
OUT_DIR="${OUT_DIR:-dist/images}"

mkdir -p "${OUT_DIR}"

save() {
  local name="$1" src="$2"
  [[ -f "${src}/Dockerfile" ]] || { echo "No Dockerfile in ${src}" >&2; exit 1; }
  echo ">> ${name}:archive (${PLATFORM}) from ${src}"
  docker buildx build --platform "${PLATFORM}" --tag "${name}:archive" --load "${src}"
  docker save "${name}:archive" | gzip -1 > "${OUT_DIR}/${name}.tar.gz"
  ls -lh "${OUT_DIR}/${name}.tar.gz"
}

save reqsai-api "${API_SRC}"
save reqsai-web "${WEB_SRC}"
