# CDNA5-M1 design console

A small FastAPI browser console around the CoreSmith project in
`designs/cdna5-m1/project`.

```bash
cd designs/cdna5-m1
../../venv/bin/python gui/app.py --host 0.0.0.0 --port 20910
# open http://127.0.0.1:20910/
```

The console reads `.env.local` (DeepSeek key/base URL/model) from the
CoreSmith root, and shells out to `bin/coresmith` with the design project root.

Tabs:

* **Overview** — stage, daemon, architecture status, peak compute.
* **Requirements** — lists PRD/FRD items and adds new ones through
  `coresmith prd add` / `coresmith frd add`.
* **Architecture / Run** — submits requirements to the CoreSmith architecture
  graph (DeepSeek worker), displays the PRD questions/park, and accepts
  human feedback via `architecture resume --action feedback`.  Also advances
  the stage machine.
* **Evidence** — measured synthesis/P&R/DV numbers and links to the docs.
* **Progress logs** — renders `progress_logs/*.md`.

The separate read-only CoreSmith run dashboard is on
`http://127.0.0.1:20911/` (`orchestrator/vscode-ext/serve.py`).
