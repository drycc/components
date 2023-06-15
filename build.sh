#!/bin/bash
set -e
set -u
# Build a base image
DRYCC_REGISTRY=${DRYCC_REGISTRY:-${DEV_REGISTRY:-registry.drycc.cc}}

# make sure we are in this dir
CURRENT_DIR=$(cd "$(dirname "$0")"; pwd)
#dist dir
DIST_DIR="${CURRENT_DIR}"/_dist

# codename
CODENAME="${CODENAME:?codename is required}"
# buildpack-dep image name
BUILDPACK_DEP_IMAGE="${DRYCC_REGISTRY}"/drycc/buildpack-dep:"${CODENAME}"

function create-buildpack-dep {
  # build buildpack-dep image
  docker build --pull -f "${CURRENT_DIR}"/Dockerfile --build-arg CODENAME="${CODENAME}" --build-arg DRYCC_REGISTRY="${DRYCC_REGISTRY}" . -t "${BUILDPACK_DEP_IMAGE}"
}

function build {
  mkdir -p "$DIST_DIR"
  STACK_NAME="${1:?STACK_NAME is required}"
  stack_version="${2:?stack_version is required}"
  create-buildpack-dep
  docker run --rm \
    --privileged=true \
    --env STACK_DOWNLOAD_URL="${STACK_DOWNLOAD_URL:-}" \
    --env STACK_NAME="${STACK_NAME}" \
    --env STACK_VERSION="${stack_version}" \
    -v "${DIST_DIR}":"${DIST_DIR}" \
    -v "${CURRENT_DIR}/stacks/${STACK_NAME}":/workspace \
    -v "${CURRENT_DIR}/scripts/stack-utils":/usr/bin/stack-utils \
    -w /workspace \
    "${BUILDPACK_DEP_IMAGE}" \
    ./build.sh "${DIST_DIR}"
}

function upload {
  STACK_NAME="${1:?stack_name is required}"
  create-buildpack-dep
  docker run --rm \
    --env OSS_ENDPOINT=${OSS_ENDPOINT} \
    --env OSS_ACCESS_KEY_ID=${OSS_ACCESS_KEY_ID} \
    --env OSS_ACCESS_KEY_SECRET=${OSS_ACCESS_KEY_SECRET} \
    -v "${DIST_DIR}":"${DIST_DIR}" \
    -v "${CURRENT_DIR}/stacks:/workspace" \
    -v "${CURRENT_DIR}/scripts:/scripts" \
    -w /workspace \
    "${BUILDPACK_DEP_IMAGE}" \
    python3 /scripts/storage.py upload "${STACK_NAME}" "${DIST_DIR}"
}

function symlink {
  docker run --rm \
    --env OSS_ENDPOINT=${OSS_ENDPOINT} \
    --env OSS_ACCESS_KEY_ID=${OSS_ACCESS_KEY_ID} \
    --env OSS_ACCESS_KEY_SECRET=${OSS_ACCESS_KEY_SECRET} \
    -v "${DIST_DIR}":"${DIST_DIR}" \
    -v "${CURRENT_DIR}/stacks:/workspace" \
    -v "${CURRENT_DIR}/scripts:/scripts" \
    -w /workspace \
    "${BUILDPACK_DEP_IMAGE}" \
    python3 /scripts/storage.py symlink "${1}" "${2}"
}


function renew() {
  git tag -d "$1"
  git push origin :refs/tags/"$1"
  git tag "$1"
  git push --tag
}

function clean-tags() {
  for tag in $(git tag --sort creatordate|head -n "$1")
  do
    git tag -d ${tag}
    git push origin :refs/tags/${tag}
  done
}

function all() {
  STACK_NAME=$(echo "${1}" | cut -d '@' -f 1)
  STACK_VERSION=$(echo "${1}" | cut -d '@' -f 2)

  build "${STACK_NAME}" "${STACK_VERSION}"
  upload "${STACK_NAME}"
}

_is_sourced() {
	# https://unix.stackexchange.com/a/215279
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}
if ! _is_sourced; then
  action=$1
  shift 1
  $action "$@"
fi