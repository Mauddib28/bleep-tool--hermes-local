# Shared by up.sh, down.sh, and verify.sh. Caller sets ROOT.

load_env() {
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env.example"
  set +a
  if [[ -z "${BLEEP_REVISION:-}" ]]; then
    BLEEP_REVISION="$(docker inspect -f '{{ index .Config.Labels "org.opencontainers.image.revision" }}' bleep 2>/dev/null || true)"
    export BLEEP_REVISION
  fi
}

compose() {
  docker compose --env-file "$ROOT/.env.example" "$@"
}

bleep_revision() {
  git ls-remote https://github.com/Mauddib28/bleep-tool.git refs/heads/main \
    | awk 'NR==1 {print $1}'
}
