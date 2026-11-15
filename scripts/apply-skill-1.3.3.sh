#!/usr/bin/env bash
# Install skill 1.3.3 and append the same sentence to the report cron.
# Refuses while the image still writes db_report_YYYYMMDD_HHMMSS.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SENTENCE='A terminal db report with no --out prints the markdown and does not write a file. Run that command once. The remote user is bleep. Do not use hermes@bleep. Do not read a path under /home/bleep. Do not cat or redirect the report into /opt/data/cache. Do not run a second db report in the same job. After the quote, do not add a command description. scan --variant pokey does not connect. classic-enum --connectionless does not extract GATT.'

if docker exec bleep grep -q -F 'db_report_{' /opt/bleep/bleep/modes/db.py; then
  echo "refusing: this image still writes db_report_YYYYMMDD_HHMMSS when --out is omitted" >&2
  echo "The 1.3.3 sentence would describe a writer this container does not have." >&2
  exit 2
fi

python3 - "$ROOT/skills/bluetooth/bleep/SKILL.md" "$SENTENCE" <<'PY'
import pathlib, sys
path, sentence = pathlib.Path(sys.argv[1]), sys.argv[2]
text = path.read_text(encoding="utf-8")
text = text.replace("version: 1.3.2\n", "version: 1.3.3\n", 1)
if "version: 1.3.3" not in text.split("---", 2)[1]:
    raise SystemExit("seed skill is not 1.3.2 or 1.3.3")
if sentence not in text:
    needle = "classic-enum --connectionless` reads advertisement and inquiry data and does not extract GATT.\n"
    if needle not in text:
        raise SystemExit("database-report paragraph not found")
    text = text.replace(needle, needle + "\n" + sentence + "\n", 1)
path.write_text(text, encoding="utf-8")
PY

docker cp "$ROOT/skills/bluetooth/bleep/SKILL.md" \
  hermes-agent:/opt/data/skills/bluetooth/bleep/SKILL.md
docker exec -u 0 hermes-agent chown 10000:10000 /opt/data/skills/bluetooth/bleep/SKILL.md
docker exec -u 0 hermes-agent chmod 644 /opt/data/skills/bluetooth/bleep/SKILL.md

seed=$(sha256sum "$ROOT/skills/bluetooth/bleep/SKILL.md" | awk '{print $1}')
live=$(docker exec hermes-agent sha256sum /opt/data/skills/bluetooth/bleep/SKILL.md | awk '{print $1}')
if [[ "$seed" != "$live" ]]; then
  echo "seed $seed live $live" >&2
  exit 1
fi
echo "skill 1.3.3 $live"

python3 - "$SENTENCE" <<'PY' > /tmp/append-skill-133.py
import sys
sentence = sys.argv[1]
print(f'''import json, subprocess
from pathlib import Path
sentence = {sentence!r}
path = Path("/opt/data/cron/jobs.json")
data = json.loads(path.read_text(encoding="utf-8"))
jobs = data["jobs"] if isinstance(data, dict) and "jobs" in data else data
items = jobs.items() if isinstance(jobs, dict) else ((item.get("id", ""), item) for item in jobs)
found = False
for job_id, job in items:
    if job_id != "8f19578228c5":
        continue
    found = True
    prompt = job.get("prompt") or ""
    if "Do not pass --out" not in prompt:
        raise SystemExit("report prompt is missing the --out rule")
    if sentence in prompt:
        print("report prompt already has the sentence")
        break
    text = prompt.rstrip() + "\\n\\n" + sentence + "\\n"
    completed = subprocess.run(["hermes", "cron", "edit", job_id, "--prompt", text], check=False)
    print(f"edit {{job_id}} rc={{completed.returncode}} len={{len(text)}}")
    raise SystemExit(completed.returncode)
if not found:
    raise SystemExit("report job 8f19578228c5 not found")
''')
PY
docker cp /tmp/append-skill-133.py hermes-agent:/tmp/append-skill-133.py
rm -f /tmp/append-skill-133.py
docker exec -u 0 hermes-agent chmod 644 /tmp/append-skill-133.py
docker exec -u 10000 -e HOME=/opt/data hermes-agent python3 /tmp/append-skill-133.py
docker exec hermes-agent rm -f /tmp/append-skill-133.py
docker exec -u 10000 -e HOME=/opt/data hermes-agent ls -l /opt/data/cron/jobs.json
