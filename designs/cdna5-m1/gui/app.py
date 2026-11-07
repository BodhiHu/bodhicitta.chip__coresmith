#!/usr/bin/env python3
"""CDNA5-M1 design console.

A small local web GUI for the CDNA5-M1 CoreSmith project:

* view the design status, specs, synthesis/P&R evidence and progress logs;
* add PRD/FRD requirements to the CoreSmith project database;
* start the CoreSmith architecture graph (DeepSeek worker) and watch its state;
* advance/resume the CoreSmith stage machine.

It is a thin wrapper around the CoreSmith CLI, not a replacement for the
engine.  Run:

    ../coresmith/venv/bin/python gui/app.py --host 0.0.0.0 --port 20910
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
import uvicorn

HERE = Path(__file__).resolve().parent
DESIGN = HERE.parent
CORESMITH = (DESIGN / ".." / "..").resolve()
PROJECT = DESIGN / "project"
CLI = CORESMITH / "bin" / "coresmith"
PDK = CORESMITH / ".pdk"

sys.path.insert(0, str(CORESMITH))


def _load_env_local() -> None:
    """Load coresmith/.env.local (keys stay in the process environment)."""
    p = CORESMITH / ".env.local"
    if not p.exists():
        return
    for raw in p.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip().strip("'\"")
        if k and v and k not in os.environ:
            os.environ[k] = v


def _env() -> dict[str, str]:
    env = os.environ.copy()
    env["CORESMITH_PROJECT_ROOT"] = str(PROJECT)
    env["PDK_ROOT"] = str(PDK)
    env["PATH"] = f"{CORESMITH/'bin'}:/opt/eda/oss-cad-suite/bin:" + env.get("PATH", "")
    env.setdefault("CORESMITH_ALLOW_NO_OPENRAM", "1")
    return env


def cli(*args: str, timeout: int = 120) -> dict:
    cmd = [str(CLI), *args, "--project-root", str(PROJECT)]
    proc = subprocess.run(
        cmd, cwd=str(CORESMITH), env=_env(), text=True,
        capture_output=True, timeout=timeout,
    )
    out = (proc.stdout or "").strip()
    err = (proc.stderr or "").strip()
    body = out
    # Some CLI verbs print a human line before/after the JSON document.
    if body and body[0] != "{":
        i = body.find("{")
        if i >= 0:
            body = body[i:]
    try:
        data = json.loads(body) if body else {}
    except json.JSONDecodeError:
        data = {"raw": out or err}
    if proc.returncode != 0:
        data.setdefault("ok", False)
        data.setdefault("error", err or out or f"exit {proc.returncode}")
    return data


app = FastAPI(title="CDNA5-M1 design console")


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    return INDEX_HTML


@app.get("/api/status")
def api_status() -> dict:
    status = cli("status", "--json")
    stage = cli("stage", "status", "--json")
    arch = cli("architecture", "state")
    daemon = cli("daemon", "status", "--json")
    return {
        "design": "CDNA5-M1",
        "project": str(PROJECT),
        "stage": stage,
        "status": status,
        "architecture": arch,
        "daemon": daemon,
    }


@app.get("/api/requirements")
def api_requirements() -> dict:
    prd = cli("prd", "list", "--json")
    frd = cli("frd", "list", "--json")
    return {"prd": prd, "frd": frd}


@app.post("/api/requirements")
async def api_add_requirement(req: Request) -> dict:
    body = await req.json()
    kind = str(body.get("kind", "prd")).lower()
    rid = str(body.get("id", "")).strip()
    text = str(body.get("text", "")).strip()
    priority = str(body.get("priority", "must_have")).strip() or "must_have"
    acceptance = str(body.get("acceptance", "")).strip()
    if not rid or not text:
        raise HTTPException(400, "id and text are required")
    if kind == "prd":
        args = ["prd", "add", text, "--id", rid, "--priority", priority]
        if acceptance:
            args += ["--acceptance", acceptance]
        args += ["--json"]
        return cli(*args)
    if kind == "frd":
        args = ["frd", "add", text, "--id", rid, "--priority", priority]
        if acceptance:
            args += ["--acceptance", acceptance]
        metric = str(body.get("metric", "")).strip()
        if metric:
            args += ["--metric", metric]
            for key in ("min", "max"):
                val = str(body.get(key, "")).strip()
                if val:
                    args += [f"--{key}", val]
            unit = str(body.get("unit", "")).strip()
            if unit:
                args += ["--unit", unit]
        args += ["--json"]
        return cli(*args)
    raise HTTPException(400, "kind must be prd or frd")


@app.post("/api/architecture/start")
async def api_arch_start(req: Request) -> dict:
    body = await req.json()
    requirements = str(body.get("requirements", "")).strip()
    if not requirements:
        raise HTTPException(400, "requirements text is required")
    clock = str(body.get("target_clock_mhz", "100")).strip() or "100"
    return cli(
        "architecture", "start",
        "--requirements", requirements,
        "--target-clock-mhz", clock,
        "--json",
        timeout=180,
    )


@app.post("/api/architecture/resume")
async def api_arch_resume(req: Request) -> dict:
    body = await req.json()
    action = str(body.get("action", "")).strip()
    if action not in {"continue", "retry", "accept", "feedback", "abort"}:
        raise HTTPException(400, "invalid action")
    args = ["architecture", "resume", "--action", action, "--json"]
    feedback = str(body.get("feedback", "")).strip()
    if feedback:
        args += ["--feedback", feedback]
    return cli(*args, timeout=180)


@app.post("/api/stage/next")
def api_stage_next() -> dict:
    return cli("stage", "next", "--json")


@app.get("/api/progress")
def api_progress() -> dict:
    files = []
    for p in sorted((DESIGN / "progress_logs").glob("*.md")):
        files.append({"name": p.name, "text": p.read_text(errors="replace")})
    return {"files": files}


@app.get("/api/file")
def api_file(path: str) -> dict:
    p = (DESIGN / path).resolve()
    if DESIGN not in p.parents:
        raise HTTPException(403, "path outside design")
    if not p.is_file():
        raise HTTPException(404, "not found")
    return {"path": str(p.relative_to(DESIGN)), "text": p.read_text(errors="replace")}


@app.get("/files/{path:path}")
def files(path: str):
    p = (DESIGN / path).resolve()
    if DESIGN not in p.parents:
        raise HTTPException(403, "path outside design")
    if not p.is_file():
        raise HTTPException(404, "not found")
    return FileResponse(p)


INDEX_HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CDNA5-M1 · Design Console</title>
<style>
  :root { --bg:#0f1218; --panel:#171b24; --panel2:#1e2430; --ink:#e7ecf5;
          --muted:#9aa7bd; --accent:#6ee7ff; --good:#65e6a4; --warn:#ffcc66; --bad:#ff7a8a;
          --line:#2a3242; }
  * { box-sizing: border-box; }
  body { margin:0; font:14px/1.45 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;
         color:var(--ink); background:var(--bg); }
  header { padding:20px 26px 12px; border-bottom:1px solid var(--line);
           background:linear-gradient(120deg,#131a25,#0f1218 60%); }
  h1 { margin:0; font-size:22px; letter-spacing:.3px; }
  h2 { margin:0 0 10px; font-size:15px; color:var(--accent); }
  .sub { color:var(--muted); margin-top:5px; }
  nav { display:flex; gap:4px; padding:0 20px; border-bottom:1px solid var(--line);
        background:var(--panel); position:sticky; top:0; z-index:5; overflow:auto; }
  nav button { background:none; border:0; color:var(--muted); padding:12px 14px;
               cursor:pointer; font:inherit; border-bottom:2px solid transparent; }
  nav button.on { color:var(--ink); border-bottom-color:var(--accent); }
  main { max-width:1220px; margin:0 auto; padding:20px; }
  .tab { display:none; } .tab.on { display:block; }
  .grid { display:grid; gap:14px; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); }
  .card { background:var(--panel); border:1px solid var(--line); border-radius:12px;
          padding:15px 16px; }
  .card h3 { margin:0 0 8px; font-size:13px; color:var(--muted); text-transform:uppercase;
             letter-spacing:.08em; }
  .big { font-size:24px; font-weight:650; }
  .ok { color:var(--good); } .warn { color:var(--warn); } .bad { color:var(--bad); }
  .muted { color:var(--muted); }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th,td { text-align:left; padding:7px 8px; border-bottom:1px solid var(--line); vertical-align:top; }
  th { color:var(--muted); font-weight:600; }
  input,select,textarea { width:100%; background:var(--panel2); color:var(--ink);
        border:1px solid var(--line); border-radius:8px; padding:8px 10px; font:inherit; }
  textarea { min-height:120px; resize:vertical; }
  label { display:block; margin:8px 0 4px; color:var(--muted); font-size:12px; }
  button.act { background:var(--accent); color:#06222a; border:0; border-radius:8px;
               padding:9px 14px; font-weight:650; cursor:pointer; }
  button.ghost { background:transparent; color:var(--ink); border:1px solid var(--line);
                 border-radius:8px; padding:8px 12px; cursor:pointer; }
  pre { white-space:pre-wrap; word-break:break-word; background:var(--panel2);
        border:1px solid var(--line); border-radius:9px; padding:12px; max-height:520px;
        overflow:auto; font-size:12px; }
  .row { display:flex; gap:10px; align-items:end; flex-wrap:wrap; }
  .row > * { flex:1 1 160px; }
  .pill { display:inline-block; padding:2px 8px; border-radius:999px; border:1px solid var(--line);
          color:var(--muted); font-size:12px; margin-right:6px; }
  a { color:var(--accent); text-decoration:none; }
  .msg { min-height:18px; color:var(--muted); margin-top:8px; font-size:12px; }
  .files { columns:2; column-gap:20px; }
  @media (max-width:800px){ .files{columns:1;} }
</style>
</head>
<body>
<header>
  <h1>CDNA5-M1 · Design Console</h1>
  <div class="sub">0.1 TFLOP/s MXFP4 · CDNA5-derived · Sky130 · CoreSmith + DeepSeek
    &nbsp;·&nbsp;<a href="http://127.0.0.1:20911/" target="_blank">CoreSmith run dashboard ↗</a></div>
</header>
<nav>
  <button class="on" data-tab="overview">Overview</button>
  <button data-tab="requirements">Requirements</button>
  <button data-tab="architecture">Architecture / Run</button>
  <button data-tab="evidence">Evidence</button>
  <button data-tab="progress">Progress logs</button>
</nav>
<main>
  <section id="overview" class="tab on">
    <div class="grid" id="statCards"></div>
    <div class="grid" style="margin-top:14px">
      <div class="card"><h2>Design</h2><div id="designSummary" class="muted">Loading…</div></div>
      <div class="card"><h2>CoreSmith stage</h2><div id="stageBox" class="muted">Loading…</div></div>
    </div>
  </section>

  <section id="requirements" class="tab">
    <div class="grid">
      <div class="card">
        <h2>Add a requirement</h2>
        <div class="row">
          <div><label>Kind</label><select id="reqKind"><option value="prd">PRD</option><option value="frd">FRD</option></select></div>
          <div><label>ID</label><input id="reqId" placeholder="KPI-002 / PERF-002"></div>
          <div><label>Priority</label><select id="reqPrio"><option>must_have</option><option>should_have</option><option>nice_to_have</option></select></div>
        </div>
        <label>Requirement text</label><textarea id="reqText" placeholder="e.g. The matrix core sustains 102.4 GFLOP/s MXFP4 at 100 MHz."></textarea>
        <label>Acceptance criterion</label><input id="reqAccept" placeholder="102.4 GFLOP/s -- measured WMMA throughput">
        <div class="row">
          <div><label>Metric (FRD only)</label><input id="reqMetric" placeholder="flops"></div>
          <div><label>Min</label><input id="reqMin" placeholder="102400000000"></div>
          <div><label>Max</label><input id="reqMax" placeholder=""></div>
          <div><label>Unit</label><input id="reqUnit" placeholder="flop/s"></div>
        </div>
        <div style="margin-top:12px"><button class="act" onclick="addRequirement()">Add to CoreSmith</button></div>
        <div class="msg" id="reqMsg"></div>
      </div>
      <div class="card">
        <h2>Current requirements</h2>
        <div id="reqList" class="muted">Loading…</div>
      </div>
    </div>
  </section>

  <section id="architecture" class="tab">
    <div class="grid">
      <div class="card">
        <h2>Start architecture generation</h2>
        <div class="muted">The text is handed to CoreSmith's architecture graph; the worker
          model is <b id="modelName">DeepSeek</b> via the configured provider.</div>
        <label>Requirements intake</label>
        <textarea id="archReq">Build a CDNA5-derived 0.1 TFLOP/s MXFP4 AI accelerator slice on Sky130: one WGP with one CU (2 x SIMD32, wave32), 4 KB LDS, a 16x16x32 MXFP4 matrix core, a 1-D TDM, AXI4-Lite host control and AXI4 memory. Target 100 MHz, 4-8 mm^2, <=2 W. RTL is Verilog-2005, synchronous reset.</textarea>
        <div class="row">
          <div><label>Target clock (MHz)</label><input id="archClock" value="100"></div>
          <div><label></label><button class="act" onclick="startArch()">Start architecture</button></div>
        </div>
        <div class="msg" id="archMsg"></div>
        <h2 style="margin-top:16px">Open questions / human feedback</h2>
        <pre id="archQuestions">—</pre>
        <label>Answers / feedback to the architecture graph</label>
        <textarea id="archFeedback" placeholder="Answer the questions above; the DeepSeek worker consumes this as human feedback."></textarea>
        <div class="row" style="margin-top:8px">
          <div><button class="act" onclick="resumeArch('feedback')">Submit answers</button></div>
          <div><button class="ghost" onclick="resumeArch('continue')">Continue</button></div>
        </div>
        <h2 style="margin-top:16px">Architecture state</h2>
        <pre id="archState">—</pre>
        <div class="row">
          <div><button class="ghost" onclick="stageNext()">Advance stage</button></div>
          <div><button class="ghost" onclick="refreshAll()">Refresh</button></div>
        </div>
        <div class="msg" id="stageMsg"></div>
      </div>
      <div class="card">
        <h2>Run state / interrupts</h2>
        <pre id="runState">—</pre>
      </div>
    </div>
  </section>

  <section id="evidence" class="tab">
    <div class="grid" id="evidenceCards"></div>
    <div class="card" style="margin-top:14px">
      <h2>Documents</h2>
      <div class="files" id="docLinks"></div>
    </div>
  </section>

  <section id="progress" class="tab">
    <div id="progressBox"></div>
  </section>
</main>
<script>
const $ = s => document.querySelector(s);
const esc = s => String(s ?? "").replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));

document.querySelectorAll('nav button').forEach(b => b.onclick = () => {
  document.querySelectorAll('nav button').forEach(x => x.classList.remove('on'));
  document.querySelectorAll('.tab').forEach(x => x.classList.remove('on'));
  b.classList.add('on'); document.getElementById(b.dataset.tab).classList.add('on');
});

async function jget(u){ const r=await fetch(u); return await r.json(); }
async function jpost(u,b){ const r=await fetch(u,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(b||{})}); return await r.json(); }

function card(title, value, note, cls){ return `<div class="card"><h3>${esc(title)}</h3>
  <div class="big ${cls||''}">${esc(value)}</div><div class="muted">${esc(note||'')}</div></div>`; }

async function refreshStatus(){
  try {
    const s = await jget('/api/status');
    const st = s.stage || {};
    const arch = s.architecture || {};
    const daemon = s.daemon || {};
    $('#statCards').innerHTML =
      card('CoreSmith stage', st.stage || 'unknown', (st.can_advance ? 'ready to advance' : 'blocked / in progress'), st.can_advance ? 'ok' : 'warn') +
      card('Architecture phase', arch.status || arch.phase || 'idle', 'DeepSeek worker via claude provider', '') +
      card('Daemon', daemon.alive ? 'alive' : 'down', `port ${daemon.port || '—'}`, daemon.alive ? 'ok' : 'bad') +
      card('Peak compute', '102.4 GFLOP/s', 'MXFP4 · 512 MAC/clk · 100 MHz', 'ok');
    $('#designSummary').innerHTML = `1 WGP / 1 CU / 2×SIMD32 · 4 KB LDS · 16×16×32 matrix core<br>
      <span class="pill">RTL PASS 3/3</span><span class="pill">WMMA 126,245 cells / 1.218 mm²</span>
      <span class="pill">TDM P&R WNS 0 / 10.1 mW</span>`;
    const bl = (st.blocked_by || []).map(b => `<li><b>${esc(b.code)}</b> — ${esc(b.text)}</li>`).join('');
    $('#stageBox').innerHTML = `<div class="big">${esc(st.stage || '—')}</div>
      <div class="muted">${bl ? '<ul>'+bl+'</ul>' : 'no blockers'}</div>`;
  } catch(e){ $('#statCards').innerHTML = card('Error', 'API', String(e), 'bad'); }
}

function renderReqs(data){
  const rows = [];
  for (const [kind, doc] of [['PRD', data.prd], ['FRD', data.frd]]){
    const items = (doc && (doc.items || doc.rows || doc.data)) || [];
    for (const it of items){
      rows.push(`<tr><td>${esc(kind)}</td><td>${esc(it.id)}</td><td>${esc(it.priority)}</td>
        <td>${esc(it.text)}</td><td class="muted">${esc(it.acceptance||it.metric||'')}</td></tr>`);
    }
  }
  $('#reqList').innerHTML = rows.length ? `<table><thead><tr><th>Kind</th><th>ID</th><th>Prio</th><th>Text</th><th>Acceptance / metric</th></tr></thead><tbody>${rows.join('')}</tbody></table>` : '<span class="muted">No requirements registered yet.</span>';
}

async function refreshReqs(){ try { renderReqs(await jget('/api/requirements')); } catch(e){} }

async function addRequirement(){
  const kind = $('#reqKind').value;
  const body = {kind, id:$('#reqId').value.trim(), text:$('#reqText').value.trim(),
    priority:$('#reqPrio').value, acceptance:$('#reqAccept').value.trim(),
    metric:$('#reqMetric').value.trim(), min:$('#reqMin').value.trim(),
    max:$('#reqMax').value.trim(), unit:$('#reqUnit').value.trim()};
  $('#reqMsg').textContent = 'Submitting…';
  const r = await jpost('/api/requirements', body);
  $('#reqMsg').textContent = r.ok === false ? ('Failed: ' + (r.error || JSON.stringify(r))) : 'Added.';
  await refreshReqs(); await refreshStatus();
}

async function startArch(){
  $('#archMsg').textContent = 'Starting architecture graph…';
  const r = await jpost('/api/architecture/start', {requirements:$('#archReq').value, target_clock_mhz:$('#archClock').value});
  $('#archMsg').textContent = JSON.stringify(r).slice(0,500);
  setTimeout(refreshArch, 1500);
}

async function resumeArch(action){
  const feedback = $('#archFeedback').value.trim();
  const r = await jpost('/api/architecture/resume', {action, feedback});
  $('#archMsg').textContent = JSON.stringify(r).slice(0,500);
  setTimeout(refreshArch, 1500);
}

async function stageNext(){
  const r = await jpost('/api/stage/next');
  $('#stageMsg').textContent = JSON.stringify(r).slice(0,500);
  await refreshStatus();
}

async function refreshArch(){
  try {
    const s = await jget('/api/status');
    $('#archState').textContent = JSON.stringify(s.architecture, null, 2).slice(0,12000);
    const qs = [];
    for (const intr of (s.architecture.interrupts || [])) {
      for (const q of ((intr.payload && intr.payload.questions) || [])) {
        qs.push(`[${q.id}] ${q.question}\n  options: ${(q.options||[]).join(' | ')}\n  context: ${q.context||''}`);
      }
    }
    $('#archQuestions').textContent = qs.length ? qs.join('\n\n') : 'No open questions.';
    $('#runState').textContent = JSON.stringify({status:s.status, stage:s.stage}, null, 2).slice(0,12000);
    if (s.architecture && s.architecture.model) $('#modelName').textContent = s.architecture.model;
  } catch(e){ $('#archState').textContent = String(e); }
}

async function refreshEvidence(){
  const cards = [
    ['Matrix core peak','102.4 GFLOP/s','512 MXFP4 MAC/cycle × 2 FLOP × 100 MHz'],
    ['Matrix core area','126,245 cells / 1.218 mm²','Yosys 0.70, Sky130 tt_025C_1v80'],
    ['TDM P&R','WNS 0.00 ns / 10.1 mW','OpenROAD, 100 MHz, 0 detailed-route DRC'],
    ['Functional DV','3/3 PASS','WMMA unit · full-chip vecadd · TDM→LDS→WMMA→AXI'],
  ];
  $('#evidenceCards').innerHTML = cards.map(c => card(c[0], c[1], c[2], 'ok')).join('');
  const docs = [
    ['README','README.md'],['ISA','spec/ISA.md'],['UARCH','spec/UARCH.md'],
    ['PRD','spec/PRD.md'],['FRD','spec/FRD.md'],['SAD','spec/SAD.md'],
    ['Performance','doc/PERFORMANCE.md'],['Verification','doc/VERIFICATION.md'],
    ['Backend','doc/BACKEND.md'],['CoreSmith integration','doc/CORESMITH_INTEGRATION.md'],
    ['Synthesis summary','syn/SUMMARY.md'],['P&R summary','pnr/SUMMARY.md'],
  ];
  $('#docLinks').innerHTML = docs.map(d => `<div><a href="/files/${d[1]}" target="_blank">${d[0]}</a> <span class="muted">${d[1]}</span></div>`).join('');
}

async function refreshProgress(){
  const p = await jget('/api/progress');
  $('#progressBox').innerHTML = (p.files||[]).map(f => `<div class="card"><h2>${esc(f.name)}</h2><pre>${esc(f.text)}</pre></div>`).join('') || '<div class="card muted">No logs yet.</div>';
}

async function refreshAll(){ await refreshStatus(); await refreshReqs(); await refreshArch(); await refreshEvidence(); await refreshProgress(); }
refreshAll();
setInterval(refreshStatus, 5000);
setInterval(refreshArch, 5000);
</script>
</body>
</html>
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=20910)
    args = ap.parse_args()
    _load_env_local()
    print(f"CDNA5-M1 design console: http://{args.host}:{args.port}")
    print(f"  design  : {DESIGN}")
    print(f"  project : {PROJECT}")
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
