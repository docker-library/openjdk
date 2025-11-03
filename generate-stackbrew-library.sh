#!/usr/bin/env bash
set -Eeuo pipefail

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

# get the most recent commit which modified any files related to a build context
commit="$(git log -1 --format='format:%H' HEAD -- '[^.]*/**')"

# TODO fetch parent arches so we can exclude things from "versions.json" that our base image doesn't support (if any)

selfCommit="$(git log -1 --format='format:%H' HEAD -- "$self")"
cat <<-EOH
# this file is generated via https://github.com/docker-library/openjdk/blob/$selfCommit/$self

Maintainers: Tianon Gravi <admwiggin@gmail.com> (@tianon),
             Joseph Ferguson <yosifkit@gmail.com> (@yosifkit)
GitRepo: https://github.com/docker-library/openjdk.git
GitCommit: $commit
EOH

exec jq \
	--raw-output \
	--from-file generate-stackbrew-library.jq \
	versions.json \
	--args -- "$@"
