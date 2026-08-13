# Adapted from nixpkgs stdenv generic setup
prependToPath() {
	local varName="$1"
	local dir="$2"
	if [[ -d "$dir" && "${!varName:+:${!varName}:}" != *":${dir}:"* ]]; then
		export "${varName}=${dir}${!varName:+:${!varName}}"
	fi
}
