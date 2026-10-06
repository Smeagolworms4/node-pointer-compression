#!/usr/bin/env bash
# Copies README.md to the description of the Docker Hub repository.
# Usage: IMAGE=owner/name DOCKER_USERNAME=... DOCKER_PASSWORD=... tools/dockerhub-readme.sh
# The repository only exists on Docker Hub once a first image is pushed: before that, nothing is done.
set -euo pipefail
: "${IMAGE:?}" "${DOCKER_USERNAME:?}" "${DOCKER_PASSWORD:?}"
cd "$(dirname "$0")/.."
if [ "$(curl -s -o /dev/null -w '%{http_code}' "https://hub.docker.com/v2/repositories/$IMAGE/")" != 200 ]; then
  echo "Docker Hub repository $IMAGE does not exist yet: README not pushed."
  exit 0
fi
token="$(jq -n --arg u "$DOCKER_USERNAME" --arg p "$DOCKER_PASSWORD" '{username: $u, password: $p}' \
  | curl -fsS -X POST -H 'Content-Type: application/json' -d @- https://hub.docker.com/v2/users/login/ | jq -r .token)"
jq -n --rawfile readme README.md '{full_description: $readme, description: "Node.js with V8 pointer compression, on Alpine, for amd64 and arm64"}' \
  | curl -fsS --fail-with-body -X PATCH -H "Authorization: JWT $token" -H 'Content-Type: application/json' -d @- "https://hub.docker.com/v2/repositories/$IMAGE/" > /dev/null
echo "README pushed to Docker Hub repository $IMAGE."
