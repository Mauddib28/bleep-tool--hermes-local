---
name: direct-hermes
description: Send an objective to the Hermes agent through the protocol broker. Use when the user wants Hermes to perform the work.
---

# Direct Hermes

Hermes performs the work. This agent only submits the objective.

Run exactly one command, with the user's objective as the JSON `input` string:

```bash
curl -sS -m 180 -H 'Content-Type: application/json' \
  --data '{"input":"OBJECTIVE"}' \
  http://protocol-broker:8787/objectives
```

Replace OBJECTIVE with the user's request. Do not add a shell pipeline, do not call Ollama yourself, and do not use a browser or the filesystem to carry out the objective. Report the JSON the broker returns. If the status is 429, say a delegated run is already in progress.
