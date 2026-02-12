include "shared";
to_entries

| .[]
| .key as $major
| .value

| if $ARGS.positional | length > 0 then
	select(IN($major; $ARGS.positional[]))
else . end

| tag_version as $version

# generate a list of "version tags", stopping the vector at the first "-ea" or "-rc" component suffix
# "AA-ea-BB.CC" -> [ "AA-ea-BB.CC", "AA-ea-BB", "AA-ea" ]
| [
	$version
	| [ scan("(?x) ^[0-9a-z]+ | [.-][0-9a-z]+") ] # [ "AA", "-ea", "-BB", ".CC" ]
	| label $stopEarly
	| .[:length-range(length)] # [ "AA", "-ea", "-BB", ".CC" ], [ "AA", "-ea", "-BB" ], ...
	| add # "AA-ea-BB.CC", "AA-ea-BB", "AA-ea", "AA"
	| if endswith("-ea") or endswith("-rc") then
		., break $stopEarly
	else . end
] as $versionTags

# now inject all the "-jdk" variations of those too
| ($versionTags | map(. + "-jdk", .)) as $versionTags

| first(.variants[] | select(startswith("oraclelinux"))) as $latestOracle
| first(.variants[] | select(startswith("slim-"))) as $latestSlim

| .variants[] as $variant # "oraclelinux9", "slim-trixie", "windows/windowsservercore-ltsc2025"

| ($variant | split("/")[-1]) as $variantName # "windowsservercore-ltsc2025", etc

| [
	$variantName,

	if $variant == $latestOracle then
		"oracle"
	else empty end,

	if $variant == $latestSlim then
		"slim"
	else empty end,

	empty

	| $versionTags[] as $versionTag
	| [ $versionTag, . | select(. != "") ]
	| join("-")
] as $tags

| [
	if $variant | startswith("windows/") then
		$variantName | split("-")[0]
	else empty end,

	if $variant == $latestOracle or ($variant | startswith("windows/windowsservercore-")) then
		""
	else empty end,

	empty

	| $versionTags[] as $versionTag
	| [ $versionTag, . | select(. != "") ]
	| join("-")
] as $sharedTags

| (
	.arches
	| keys_unsorted
	| map(select(
		startswith("windows-")
		| if $variant | startswith("windows/") then . else not end
	))
) as $arches

| (
	"",
	"Tags: \($tags | join(", "))",
	if $sharedTags != [] then "SharedTags: \($sharedTags | join(", "))" else empty end,
	"Directory: \($major)/\($variant)",
	"Architectures: \($arches | join(", "))",
	if $variant | startswith("windows/") then
		$variant
		| windows_release as $winver
		| [
			# TODO use windows_variant from shared.jq?
			if startswith("windows/nanoserver-") then
				"nanoserver-" + $winver
			else empty end,
			"windowsservercore-" + $winver,
			empty
		]
		| "Constraints: " + join(", ")
	else empty end,
	empty
)
