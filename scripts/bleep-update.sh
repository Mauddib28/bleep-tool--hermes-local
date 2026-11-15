#!/usr/bin/env bash
# Rebuild the BLEEP image from upstream main, migrate the observation DB forward, record the ledger.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Run this from Ubuntu-22.04: bash scripts/bleep-update.sh" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$ROOT/scripts/lib.sh"
load_env

if [[ -z "${BLEEP_REVISION:-}" ]]; then
  BLEEP_REVISION="$(bleep_revision)"
  export BLEEP_REVISION
fi
[[ -n "$BLEEP_REVISION" ]] || { echo "Could not resolve BLEEP main." >&2; exit 1; }

schema_of() {
  printf '%s\n' "$1" | sed -n 's/.*DB schema v\([0-9][0-9]*\).*/\1/p' | head -n 1
}

ledger() {
  python3 - "$ROOT/docs/bleep-fidelity.md" "$@" <<'PY'
import sys
from pathlib import Path
path, date, result, sha, version, before, after, snapshot, notes = sys.argv[1:]

def cell(value: str) -> str:
    return " ".join(value.replace("|", "/").split())

row = (
    f"| {cell(date)} | {cell(result)} | `{cell(sha)}` | {cell(version)} | "
    f"{cell(before)} | {cell(after)} | {cell(snapshot)} | {cell(notes)} |\n"
)
file = Path(path)
lines = file.read_text(encoding="utf-8").splitlines(keepends=True)
skill = next(i for i, line in enumerate(lines) if line.startswith("## Skill allow list"))
insert_at = skill
for i in range(skill - 1, -1, -1):
    if lines[i].startswith("| 20"):
        insert_at = i + 1
        break
lines.insert(insert_at, row)
file.write_text("".join(lines), encoding="utf-8")
PY
}

restore_snapshot() {
  local snap="$1"
  [[ "$snap" == NOFILE || -z "$snap" ]] && return 0
  docker run --rm -v bleep-home:/home/bleep alpine:latest \
    sh -c "set -e
      db=/home/bleep/.bleep/observations.db
      cp -a '$snap' \"\$db\"
      if [ -f '$snap-wal' ]; then cp -a '$snap-wal' \"\$db-wal\"; else rm -f \"\$db-wal\"; fi
      if [ -f '$snap-shm' ]; then cp -a '$snap-shm' \"\$db-shm\"; else rm -f \"\$db-shm\"; fi
      chown 10001:bluetooth \"\$db\" \"\$db-wal\" \"\$db-shm\" 2>/dev/null || chown 10001:bluetooth \"\$db\""
}

current_sha=""
old_image=""
if docker inspect bleep >/dev/null 2>&1; then
  current_sha="$(docker inspect -f '{{ index .Config.Labels "org.opencontainers.image.revision" }}' bleep 2>/dev/null || true)"
  old_image="$(docker inspect -f '{{.Image}}' bleep)"
fi

health_now=""
if docker inspect bleep >/dev/null 2>&1; then
  health_now="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' bleep 2>/dev/null || true)"
fi
patches_present() {
  docker exec bleep grep -q 'continuing with SDP' /opt/bleep/bleep/ble_ops/classic/sdp.py \
    && docker exec bleep grep -q 'records skipped: browse and xml already returned records' \
      /opt/bleep/bleep/ble_ops/classic/sdp.py \
    && docker exec bleep test -x /usr/local/sbin/bleep-hostnetd
}

if [[ "$current_sha" == "$BLEEP_REVISION" ]] \
  && [[ "$health_now" == "healthy" ]] \
  && docker image inspect "bleep-local:${BLEEP_REVISION}" >/dev/null 2>&1; then
  if patches_present; then
    echo "BLEEP image already ${BLEEP_REVISION}; not rebuilding."
    compose up -d --no-deps bleep
    exit 0
  fi
  echo "BLEEP label matches ${BLEEP_REVISION} but a local patch is missing; rebuilding."
fi

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
before_text=""
before_schema="none"
snap="NOFILE"
if [[ -n "$current_sha" ]]; then
  before_text="$(docker exec -u bleep -e BLEEP_DB_PATH=/home/bleep/.bleep/observations.db bleep bleep --version 2>/dev/null || true)"
  before_schema="$(schema_of "$before_text")"
  [[ -n "$before_schema" ]] || before_schema="none"
  snap="$(docker exec -u bleep bleep sh -c "
    db=/home/bleep/.bleep/observations.db
    if [ ! -f \"\$db\" ]; then echo NOFILE; exit 0; fi
    dest=\"\$db.${stamp}.schema${before_schema}\"
    cp -a \"\$db\" \"\$dest\"
    [ -f \"\$db-wal\" ] && cp -a \"\$db-wal\" \"\$dest-wal\"
    [ -f \"\$db-shm\" ] && cp -a \"\$db-shm\" \"\$dest-shm\"
    echo \"\$dest\"
  ")"
fi

built=no
for _ in 1 2; do
  if compose build bleep; then
    built=yes
    break
  fi
  echo "BLEEP image build failed; resolving main and retrying once."
  BLEEP_REVISION="$(bleep_revision)"
  export BLEEP_REVISION
done
[[ "$built" == yes ]] || { echo "BLEEP image build failed." >&2; exit 1; }

compose up -d --no-deps bleep

health=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  health="$(docker inspect -f '{{.State.Health.Status}}' bleep 2>/dev/null || true)"
  [[ "$health" == "healthy" ]] && break
  sleep 2
done
if [[ "$health" != "healthy" ]]; then
  ledger "$stamp" failed "$BLEEP_REVISION" "container not healthy" \
    "$before_schema" "none" "$snap" "health=${health:-absent}"
  exit 1
fi

set +e
after_text="$(docker exec -u bleep -e BLEEP_DB_PATH=/home/bleep/.bleep/observations.db bleep bleep --version 2>&1)"
version_rc=$?
db_text="$(docker exec -u bleep -e BLEEP_DB_PATH=/home/bleep/.bleep/observations.db bleep bleep db list 2>&1)"
db_rc=$?
set -e
after_schema="$(schema_of "$after_text")"

fail_reason=""
if [[ "$version_rc" -ne 0 || -z "$after_schema" ]]; then
  fail_reason="bleep --version failed"
elif [[ "$db_rc" -ne 0 ]]; then
  fail_reason="bleep db list failed"
elif [[ "$before_schema" != "none" && "$after_schema" -lt "$before_schema" ]]; then
  fail_reason="schema decreased ${before_schema} -> ${after_schema}"
fi

if [[ -n "$fail_reason" ]]; then
  restore_snapshot "$snap"
  if [[ -n "$old_image" && -n "$current_sha" ]]; then
    docker tag "$old_image" "bleep-local:${current_sha}"
    BLEEP_REVISION="$current_sha" compose up -d --no-deps --no-build bleep
  fi
  ledger "$stamp" failed "$BLEEP_REVISION" "${after_text:-none}" \
    "$before_schema" "${after_schema:-none}" "$snap" "$fail_reason"
  echo "BLEEP update failed: ${fail_reason}" >&2
  printf '%s\n' "$db_text" >&2
  exit 1
fi

note="db list exited 0"
if [[ "$snap" == "NOFILE" ]]; then
  note="no database file before build; db list exited 0"
fi
ledger "$stamp" built "$BLEEP_REVISION" "$after_text" \
  "$before_schema" "$after_schema" "$snap" "$note"
echo "BLEEP ${after_text}"
