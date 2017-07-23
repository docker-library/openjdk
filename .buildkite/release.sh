#!/usr/bin/env bash

BUILDKITE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BASE_DIR="$( cd "$BUILDKITE_DIR/.." && pwd )"
BIN_DIR="$BASE_DIR/bin"

# Load lib functions
lib_functions="$BIN_DIR/functions"
echo "Using version: ${SCRIPTS_VERSION:-stable}"
curl -Ls -o "${lib_functions}" "https://s3.amazonaws.com/bit-ops-artifacts/scripts/lib/${SCRIPTS_VERSION:-stable}/functions"
source "${lib_functions}"

RELEASE_NAME=$(buildkite-agent meta-data get release-name)
RELEASE_BODY=$(buildkite-agent meta-data get release-notes)
RELEASE_TYPE=$(buildkite-agent meta-data get release-type)

test -n "${RELEASE_NAME}" || { error "Please set the variable 'RELEASE_NAME' to release on Github." ; exit 1;}
test -n "${RELEASE_BODY}" || { error "Please set the variable 'RELEASE_BODY' to release on Github." ; exit 1;}
test -n "${RELEASE_TYPE}" || { error "Please set the variable 'RELEASE_TYPE' to release on Github." ; exit 1;}

export RELEASE_NAME
export RELEASE_BODY
export RELEASE_IS_DRAFT=$(test "draft" = "$RELEASE_TYPE" && echo "true" || echo "false")
export RELEASE_IS_PRERELEASE=$(test "pre-release" = "$RELEASE_TYPE" && echo "true" || echo "false")

release_github