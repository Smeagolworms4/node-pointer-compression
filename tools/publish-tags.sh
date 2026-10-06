#!/usr/bin/env bash
# Creates the multi-architecture tags of every version whose two per-architecture images are on Docker Hub.
# Usage: IMAGE=owner/name tools/publish-tags.sh '<JSON list of versions, the "all" of tools/versions.mjs>'
# Each architecture is built by its own workflow: whichever finishes last finds both images and tags the version.
# Idempotent: tagging again points the tags at the same images.
set -euo pipefail
: "${IMAGE:?}"
versions="$1"
count="$(jq length <<< "$versions")"
for i in $(seq 0 $((count - 1))); do
  version="$(jq -r ".[$i].version" <<< "$versions")"
  prefixes="$(jq -r ".[$i].tags" <<< "$versions")"
  latest="$(jq -r ".[$i].latest" <<< "$versions")"
  for variant in alpine alpine-slim; do
    sources=()
    missing=""
    for arch in amd64 arm64; do
      if docker buildx imagetools inspect "$IMAGE:$version-$variant-$arch" > /dev/null 2>&1; then sources+=("$IMAGE:$version-$variant-$arch"); else missing="$missing $arch"; fi
    done
    if [ -n "$missing" ]; then
      echo "- Node.js $version $variant: waiting for$missing" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
      continue
    fi
    tags=()
    for prefix in $prefixes; do tags+=(-t "$IMAGE:$prefix-$variant"); done
    if [ "$latest" = true ]; then
      tags+=(-t "$IMAGE:$variant")
      if [ "$variant" = alpine ]; then tags+=(-t "$IMAGE:latest"); else tags+=(-t "$IMAGE:slim"); fi
    fi
    docker buildx imagetools create "${tags[@]}" "${sources[@]}"
    echo "- Node.js $version $variant: ${tags[*]//-t /}" | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
  done
done
