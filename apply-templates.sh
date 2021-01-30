#!/usr/bin/env bash
set -Eeuo pipefail

[ -f versions.json ] # run "versions.sh" first

jqt='.jq-template.awk'
if [ -n "${BASHBREW_SCRIPTS:-}" ]; then
	jqt="$BASHBREW_SCRIPTS/jq-template.awk"
elif [ "$BASH_SOURCE" -nt "$jqt" ]; then
	wget -qO "$jqt" 'https://github.com/docker-library/bashbrew/raw/00e281f36edd19f52541a6ba2f215cc3c4645128/scripts/jq-template.awk'
fi

if [ "$#" -eq 0 ]; then
	versions="$(jq -r 'keys | map(@sh) | join(" ")' versions.json)"
	eval "set -- $versions"
fi

generated_warning() {
	cat <<-EOH
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

	EOH
}

for version; do
	export version

	rm -rf "$version/"

	variants="$(jq -r '.[env.version].variants | map(@sh) | join(" ")' versions.json)"
	eval "variants=( $variants )"

	for javaType in jdk jre; do
		export javaType

		if ! hasJavaType="$(jq -r '.[env.version] | if has(env.javaType) then "1" else "" end' versions.json)" || [ -z "$hasJavaType" ]; then
			continue
		fi

		for variant in "${variants[@]}"; do
			export variant

			if [ "$javaType" = 'jre' ] && [[ "$variant" == oraclelinux* ]]; then
				continue # no Oracle-based JRE images (for now? gotta figure a few things out to do that)
			fi

			dir="$version/$javaType/$variant"
			mkdir -p "$dir"

			case "$variant" in
				windows/*)
					variant="$(basename "$dir")" # "buster", "windowsservercore-1809", etc
					windowsVariant="${variant%%-*}" # "windowsservercore", "nanoserver"
					windowsRelease="${variant#$windowsVariant-}" # "1809", "ltsc2016", etc
					windowsVariant="${windowsVariant#windows}" # "servercore", "nanoserver"
					export windowsVariant windowsRelease
					template='Dockerfile-windows.template'
					;;

				*)
					template='Dockerfile-linux.template'
					;;
			esac

			echo "processing $dir ..."

			{
				generated_warning
				gawk -f "$jqt" "$template"
			} > "$dir/Dockerfile"
		done
	done
done
