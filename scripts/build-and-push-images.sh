#!/usr/bin/env bash
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/kntro-soft}"
PLATFORM="${PLATFORM:-linux/amd64}"
API_SRC="${API_SRC:-../ReqsAI/reqsai-api}"
WEB_SRC="${WEB_SRC:-../ReqsAI/reqsai-web}"
TARGETS="${TARGETS:-api web}"
PUSH="${PUSH:-1}"

source_tag() {
  local src="$1" tag
  tag="$(git -C "${src}" rev-parse --short=8 HEAD)"
  if [[ -n "$(git -C "${src}" status --porcelain)" ]]; then
    tag="${tag}-dirty"
  fi
  printf '%s' "${tag}"
}

source_url() {
  git -C "$1" remote get-url origin 2>/dev/null \
    | sed -E 's#^git@github\.com:#https://github.com/#; s#\.git$##' || true
}

build() {
  local name="$1" src="$2" tag output url
  [[ -f "${src}/Dockerfile" ]] || { echo "No Dockerfile in ${src}" >&2; exit 1; }
  tag="${TAG:-$(source_tag "${src}")}"
  if [[ "${PUSH}" == "1" ]]; then
    output="--push"
  else
    output="--load"
  fi
  url="$(source_url "${src}")"
  echo ">> ${REGISTRY}/${name}:${tag} (${PLATFORM}) from ${src}"
  docker buildx build \
    --platform "${PLATFORM}" \
    --label "org.opencontainers.image.source=${url}" \
    --label "org.opencontainers.image.revision=$(git -C "${src}" rev-parse HEAD)" \
    --tag "${REGISTRY}/${name}:${tag}" \
    --tag "${REGISTRY}/${name}:latest" \
    "${output}" \
    "${src}"
}

for target in ${TARGETS}; do
  case "${target}" in
    api) build reqsai-api "${API_SRC}" ;;
    web) build reqsai-web "${WEB_SRC}" ;;
    *) echo "Unknown target: ${target} (expected api or web)" >&2; exit 1 ;;
  esac
done
