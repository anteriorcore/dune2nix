{
  nix,
  demo,
  runCommand,
}:

# Ensure the dependencies aren’t included in the final build closure.
runCommand "no-deps-closure" { nativeBuildInputs = [ nix ]; } ''
  f="$(mktemp)"
  nix-store --query --requisites ${demo} > "$f"
  cat "$f"
  ! grep --quiet -F ${demo.passthru.duneDeps} "$f"
  touch $out
''
