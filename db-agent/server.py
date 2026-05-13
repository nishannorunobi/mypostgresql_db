"""
DB Agent HTTP Server — runs inside mypostgresql_db-container on port 8890.

Endpoints:
  GET  /health           liveness + pg_isready status
  GET  /api/db/status    PostgreSQL running state
  POST /api/db/start     start PostgreSQL via startdb.sh --prepare-only
  POST /api/db/stop      stop PostgreSQL via pg_ctl stop
  POST /api/tasks        AI agent task (called by docker-manager-agent)
  WS   /ws/chat          streaming chat (proxied by orchestrator)
"""
import asyncio
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
import anthropic as _anthropic
from pydantic import BaseModel

AGENT_DIR = Path(__file__).parent
load_dotenv(AGENT_DIR / "agent.conf")

sys.path.insert(0, str(AGENT_DIR))
import agent as ai_agent
from tools import TOOL_DEFINITIONS, execute_tool, MEMORY_DIR

STARTDB          = AGENT_DIR.parent / "umsdb"    / "scripts" / "startdb.sh"
MYDOCSDB_STARTDB = AGENT_DIR.parent / "mydocsdb" / "scripts" / "startdb.sh"
PGDATA           = os.environ.get("PGDATA", "/var/lib/postgresql/data")
DB_UI_SCRIPT     = AGENT_DIR.parent / "dockerspace" / "container_scripts" / "db_ui.sh"
PGWEB_PID_FILE   = "/tmp/pgweb.pid"

_INITDB_SCRIPTS = {
    "umsdb":    STARTDB,
    "mydocsdb": MYDOCSDB_STARTDB,
}

_CHAT_LOG = MEMORY_DIR / "chat_history.log"

# Active operational issues — polled by docker-manager-agent and forwarded to dashboard
_issues: list[str] = []


def _record_issue(msg: str):
    clean = str(msg)
    if clean not in _issues:
        _issues.append(clean)


def _clear_issues():
    _issues.clear()

app = FastAPI(title="DB Agent", version="1.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


# ── Root ───────────────────────────────────────────────────────────────────────

@app.get("/")
def root():
    return RedirectResponse(url="/docs")


# ── Health ─────────────────────────────────────────────────────────────────────

def _pgweb_running() -> bool:
    try:
        pid = int(Path(PGWEB_PID_FILE).read_text().strip())
        os.kill(pid, 0)
        return True
    except Exception:
        return False


@app.get("/health")
def health():
    pg_up = subprocess.run(
        ["pg_isready", "-h", "localhost", "-p", "5432"],
        capture_output=True
    ).returncode == 0
    return {
        "status":           "ok",
        "agent":            "db-agent",
        "postgres_running": pg_up,
        "pgweb_running":    _pgweb_running(),
        "issues":           list(_issues),
        "time":             datetime.now().isoformat(),
    }


# ── DB control ─────────────────────────────────────────────────────────────────

@app.get("/api/db/status")
def db_status():
    pg_up = subprocess.run(
        ["pg_isready", "-h", "localhost", "-p", "5432"],
        capture_output=True
    ).returncode == 0
    return {"postgres_running": pg_up}


@app.post("/api/db/start")
def db_start():
    if not STARTDB.exists():
        raise HTTPException(status_code=500, detail=f"startdb.sh not found at {STARTDB}")
    try:
        r = subprocess.run(
            ["bash", str(STARTDB), "--prepare-only"],
            capture_output=True, text=True, timeout=60,
        )
        return {
            "success": r.returncode == 0,
            "output":  (r.stdout + r.stderr).strip()[-800:],
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "output": "startdb.sh timed out after 60s"}
    except Exception as e:
        return {"success": False, "output": str(e)}


@app.post("/api/initdb/{db_name}")
def initdb(db_name: str):
    script = _INITDB_SCRIPTS.get(db_name)
    if not script:
        raise HTTPException(status_code=404, detail=f"Unknown db: '{db_name}'. Known: {list(_INITDB_SCRIPTS)}")
    if not script.exists():
        raise HTTPException(status_code=500, detail=f"startdb.sh not found at {script}")
    try:
        r = subprocess.run(
            ["bash", str(script), "--prepare-only"],
            capture_output=True, text=True, timeout=60,
        )
        return {
            "success": r.returncode == 0,
            "output":  (r.stdout + r.stderr).strip()[-800:],
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "output": f"{db_name} startdb.sh timed out after 60s"}
    except Exception as e:
        return {"success": False, "output": str(e)}


@app.post("/api/dbui/start")
def dbui_start():
    if not DB_UI_SCRIPT.exists():
        raise HTTPException(status_code=500, detail=f"db_ui.sh not found at {DB_UI_SCRIPT}")
    try:
        r = subprocess.run(
            ["bash", str(DB_UI_SCRIPT), "start"],
            capture_output=True, text=True, timeout=120,
        )
        return {"success": r.returncode == 0, "output": (r.stdout + r.stderr).strip()[-800:]}
    except subprocess.TimeoutExpired:
        return {"success": False, "output": "db_ui.sh timed out"}
    except Exception as e:
        return {"success": False, "output": str(e)}


@app.post("/api/dbui/stop")
def dbui_stop():
    if not DB_UI_SCRIPT.exists():
        raise HTTPException(status_code=500, detail=f"db_ui.sh not found at {DB_UI_SCRIPT}")
    try:
        r = subprocess.run(
            ["bash", str(DB_UI_SCRIPT), "stop"],
            capture_output=True, text=True, timeout=30,
        )
        return {"success": r.returncode == 0, "output": (r.stdout + r.stderr).strip()}
    except Exception as e:
        return {"success": False, "output": str(e)}


@app.post("/api/db/stop")
def db_stop():
    try:
        r = subprocess.run(
            ["gosu", "postgres", "pg_ctl", "-D", PGDATA, "stop", "-m", "fast"],
            capture_output=True, text=True, timeout=30,
        )
        return {
            "success": r.returncode == 0,
            "output":  (r.stdout + r.stderr).strip(),
        }
    except Exception as e:
        return {"success": False, "output": str(e)}


# ── Service management ─────────────────────────────────────────────────────────

@app.get("/api/services")
def list_services():
    from tools import _SERVICES_JSON
    if not _SERVICES_JSON.exists():
        return {"services": {}, "discovered": False}
    data = json.loads(_SERVICES_JSON.read_text())
    return {
        "discovered":    True,
        "discovered_at": data.get("discovered_at"),
        "services":      data.get("services", {}),
    }


@app.post("/api/services/{project}/{service}/start")
def service_start(project: str, service: str):
    return execute_tool("run_service", {"service": f"{project}/{service}", "action": "start"})


@app.post("/api/services/{project}/{service}/stop")
def service_stop(project: str, service: str):
    return execute_tool("run_service", {"service": f"{project}/{service}", "action": "stop"})


# ── AI task endpoint (called by docker-manager-agent HTTP connector) ───────────

class TaskRequest(BaseModel):
    task: str


@app.post("/api/tasks")
async def handle_task(body: TaskRequest):
    if not body.task.strip():
        raise HTTPException(status_code=400, detail="task field required")
    if not os.environ.get("ANTHROPIC_API_KEY"):
        raise HTTPException(status_code=503, detail="ANTHROPIC_API_KEY not set in agent.conf")

    loop = asyncio.get_event_loop()

    def _run():
        client   = _anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
        history  = [{"role": "user", "content": body.task.strip()}]
        response = ""
        while True:
            resp = client.messages.create(
                model="claude-sonnet-4-6", max_tokens=4096,
                system=ai_agent.SYSTEM_PROMPT,
                tools=TOOL_DEFINITIONS,
                messages=history,
            )
            tool_calls = [b for b in resp.content if b.type == "tool_use"]
            texts      = [b for b in resp.content if b.type == "text"]

            if resp.stop_reason == "end_turn" or not tool_calls:
                response = " ".join(b.text for b in texts).strip()
                break

            history.append({"role": "assistant", "content": resp.content})
            results = []
            for b in tool_calls:
                result = execute_tool(b.name, b.input)
                results.append({
                    "type":        "tool_result",
                    "tool_use_id": b.id,
                    "content":     json.dumps(result, default=str),
                })
            history.append({"role": "user", "content": results})

        return response

    try:
        result = await loop.run_in_executor(None, _run)
        _clear_issues()
        return {"result": result or "(no response)"}
    except Exception as e:
        _record_issue(f"Anthropic API error: {e}")
        raise HTTPException(status_code=503, detail=f"AI agent error: {e}")


# ── WebSocket chat ─────────────────────────────────────────────────────────────

def _append_chat(role: str, content: str):
    _CHAT_LOG.parent.mkdir(exist_ok=True)
    ts   = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = json.dumps({"ts": ts, "role": role, "content": content}, ensure_ascii=False)
    with open(_CHAT_LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def _load_chat() -> list:
    if not _CHAT_LOG.exists():
        return []
    lines = _CHAT_LOG.read_text(encoding="utf-8").splitlines()
    lines = lines[-60:]
    result = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            result.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return result


async def _chat_turn(ws: WebSocket, history: list, client) -> list:
    loop = asyncio.get_event_loop()
    while True:
        resp = await loop.run_in_executor(None, lambda: client.messages.create(
            model="claude-sonnet-4-6", max_tokens=4096,
            system=ai_agent.SYSTEM_PROMPT,
            tools=TOOL_DEFINITIONS,
            messages=history,
        ))
        tool_calls = [b for b in resp.content if b.type == "tool_use"]
        texts      = [b for b in resp.content if b.type == "text"]

        for b in texts:
            if b.text.strip():
                await ws.send_json({"type": "text", "content": b.text})

        if resp.stop_reason == "end_turn" or not tool_calls:
            final = " ".join(b.text for b in texts).strip()
            if final:
                history.append({"role": "assistant", "content": final})
                _append_chat("assistant", final)
            break

        history.append({"role": "assistant", "content": resp.content})
        results = []
        for b in tool_calls:
            await ws.send_json({"type": "tool_call", "id": b.id, "name": b.name, "input": b.input})
            result = await loop.run_in_executor(None, lambda blk=b: execute_tool(blk.name, blk.input))
            await ws.send_json({"type": "tool_result", "id": b.id, "name": b.name, "result": result})
            results.append({
                "type":        "tool_result",
                "tool_use_id": b.id,
                "content":     json.dumps(result, default=str),
            })
        history.append({"role": "user", "content": results})

    await ws.send_json({"type": "done"})
    return history


@app.websocket("/ws/chat")
async def ws_chat(ws: WebSocket):
    await ws.accept()

    if not os.environ.get("ANTHROPIC_API_KEY"):
        await ws.send_json({"type": "error", "content": "ANTHROPIC_API_KEY not set in agent.conf"})
        await ws.close()
        return

    client  = _anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])
    saved   = _load_chat()
    history = [{"role": m["role"], "content": m["content"]} for m in saved]

    for m in saved:
        await ws.send_json({
            "type":    "history_msg",
            "role":    m["role"],
            "content": m["content"],
            "ts":      m.get("ts", ""),
        })

    try:
        while True:
            data = await ws.receive_text()
            text = json.loads(data).get("content", "").strip()
            if not text:
                continue
            history.append({"role": "user", "content": text})
            _append_chat("user", text)
            try:
                history = await _chat_turn(ws, history, client)
                _clear_issues()
            except Exception as e:
                _record_issue(f"Anthropic API error: {e}")
                await ws.send_json({"type": "error", "content": f"Agent error: {e}"})
                await ws.send_json({"type": "done"})
    except WebSocketDisconnect:
        pass
