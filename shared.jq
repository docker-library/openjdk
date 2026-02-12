def tag_version:
	.version
	| . as $ver
	| gsub("[+]"; "-")
	# if fullVersion is only digits, add "-rc" to the end (because we're probably in the final-phases of pre-release before GA when we drop support from the image)
	| if test("^[0-9]+$") then
		. + "-rc"
	else . end
	| if contains("-ea") or contains("-rc") then . else
		error("invalid version; too GA: \(.) (\($ver))")
	end
;
def windows_variant: # "servercore", "nanoserver"
	if env.variant then env.variant else . end
	| split("/")[-1]
	| split("-")[0]
	| ltrimstr("windows")
;
def windows_release: # "ltsc2025", "ltsc2022"
	if env.variant then env.variant else . end
	| split("-")[-1]
;
