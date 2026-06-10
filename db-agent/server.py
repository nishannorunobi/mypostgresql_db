"""
DB Agent HTTP Server — runs inside mypostgresql_db-container on port 8890.

Endpoints:
  GET  /                 standalone web UI
  GET  /health           liveness + pg_isready status
  GET  /api/db/status    PostgreSQL running state
  POST /api/db/start     start PostgreSQL
  POST /api/db/stop      stop PostgreSQL
  POST /api/initdb/{db}  create user + database
  POST /api/dbui/start   start pgweb
  POST /api/dbui/stop    stop pgweb
  POST /api/chat/clear   clear chat history
  POST /api/tasks        AI agent task (called by docker-manager-agent)
  WS   /ws/chat          streaming chat
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
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
import anthropic as _anthropic
from loguru import logger
from pydantic import BaseModel

# ── Loguru setup ──────────────────────────────────────────────────────────────
import logging as _logging

class _Interceptor(_logging.Handler):
    def emit(self, record):
        try:
            level = logger.level(record.levelname).name
        except ValueError:
            level = record.levelno
        frame, depth = _logging.currentframe(), 2
        while frame and frame.f_code.co_filename == _logging.__file__:
            frame = frame.f_back
            depth += 1
        logger.opt(depth=depth, exception=record.exc_info).log(level, record.getMessage())

_logging.basicConfig(handlers=[_Interceptor()], level=0, force=True)
logger.remove()
logger.add(
    sys.stderr,
    format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level:<8}</level> | <cyan>{name}</cyan>:<cyan>{line}</cyan> — <level>{message}</level>",
    level="INFO",
    colorize=True,
)

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
BACKUP_DIR       = AGENT_DIR / "backup_db"
CLOUD_DIR        = AGENT_DIR / "sync_cloud_backup_db"
BACKUPS_ROOT     = Path("/backups")
GDRIVE_REMOTE    = "gdrive:myworkspace-backups"

_INITDB_SCRIPTS = {
    "umsdb":    STARTDB,
    "mydocsdb": MYDOCSDB_STARTDB,
}
_CLEANDB_SCRIPTS = {
    "umsdb":    AGENT_DIR.parent / "umsdb"    / "scripts" / "cleandb.sh",
    "mydocsdb": AGENT_DIR.parent / "mydocsdb" / "scripts" / "cleandb.sh",
    "all":      AGENT_DIR.parent / "scripts"  / "cleandb_all.sh",
}

# Metadata shown in the UI for each schema — add new entries here when new DBs are added
_SCHEMA_META: dict[str, dict] = {
    "umsdb": {
        "label":       "UMS Database",
        "description": "User Management System — users, roles, permissions, sessions",
        "icon":        "👤",
        "color":       "#58a6ff",
    },
    "mydocsdb": {
        "label":       "Docs Database",
        "description": "Plane documentation platform — issues, projects, workspace data",
        "icon":        "📚",
        "color":       "#bc8cff",
    },
}


def _db_exists(name: str) -> bool:
    try:
        r = subprocess.run(
            ["psql", "-U", "postgres", "-h", "localhost", "-p", "5432",
             "-tAc", f"SELECT 1 FROM pg_database WHERE datname='{name}'"],
            capture_output=True, text=True, timeout=5,
        )
        return r.stdout.strip() == "1"
    except Exception:
        return False


def _stream_script(cmd: list[str]):
    """Run a subprocess and yield its output as SSE data lines."""
    from fastapi.responses import StreamingResponse as _SR

    def generate():
        try:
            proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1,
            )
            for line in proc.stdout:
                clean = line.rstrip()
                if clean:
                    yield f"data: {clean}\n\n"
            proc.wait()
            if proc.returncode != 0:
                yield f"data: [exit {proc.returncode}]\n\n"
        except Exception as e:
            yield f"data: [ERROR] {e}\n\n"
        yield "data: __done__\n\n"

    return _SR(generate(), media_type="text/event-stream",
               headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})

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

STATIC_DIR = AGENT_DIR / "static"
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

logger.info("DB Agent server starting up")


# ── UI ─────────────────────────────────────────────────────────────────────────

@app.get("/")
def root():
    return FileResponse(str(STATIC_DIR / "index.html"))


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
        "status":            "ok",
        "agent":             "db-agent",
        "postgres_running":  pg_up,
        "pgweb_running":     _pgweb_running(),
        "rclone_ui_running": _rclone_ui_running(),
        "issues":            list(_issues),
        "time":              datetime.now().isoformat(),
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
    logger.info("Starting PostgreSQL")
    if not STARTDB.exists():
        raise HTTPException(status_code=500, detail=f"startdb.sh not found at {STARTDB}")
    try:
        r = subprocess.run(
            ["bash", str(STARTDB), "--prepare-only"],
            capture_output=True, text=True, timeout=60,
        )
        ok = r.returncode == 0
        (logger.info if ok else logger.error)("PostgreSQL start: rc={}", r.returncode)
        return {"success": ok, "output": (r.stdout + r.stderr).strip()[-800:]}
    except subprocess.TimeoutExpired:
        logger.error("PostgreSQL startdb.sh timed out")
        return {"success": False, "output": "startdb.sh timed out after 60s"}
    except Exception as e:
        logger.error("PostgreSQL start error: {}", e)
        return {"success": False, "output": str(e)}


@app.post("/api/initdb/{db_name}")
def initdb(db_name: str):
    logger.info("Initialising database: {}", db_name)
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
        ok = r.returncode == 0
        (logger.info if ok else logger.error)("initdb {}: rc={}", db_name, r.returncode)
        return {"success": ok, "output": (r.stdout + r.stderr).strip()[-800:]}
    except subprocess.TimeoutExpired:
        logger.error("initdb {} timed out", db_name)
        return {"success": False, "output": f"{db_name} startdb.sh timed out after 60s"}
    except Exception as e:
        logger.error("initdb {} error: {}", db_name, e)
        return {"success": False, "output": str(e)}


@app.post("/api/dbui/start")
def dbui_start():
    logger.info("Starting pgweb")
    if not DB_UI_SCRIPT.exists():
        raise HTTPException(status_code=500, detail=f"db_ui.sh not found at {DB_UI_SCRIPT}")
    try:
        r = subprocess.run(
            ["bash", str(DB_UI_SCRIPT), "start"],
            capture_output=True, text=True, timeout=120,
        )
        ok = r.returncode == 0
        (logger.info if ok else logger.error)("pgweb start: rc={}", r.returncode)
        return {"success": ok, "output": (r.stdout + r.stderr).strip()[-800:]}
    except subprocess.TimeoutExpired:
        logger.error("pgweb start timed out")
        return {"success": False, "output": "db_ui.sh timed out"}
    except Exception as e:
        logger.error("pgweb start error: {}", e)
        return {"success": False, "output": str(e)}


@app.post("/api/dbui/stop")
def dbui_stop():
    logger.info("Stopping pgweb")
    if not DB_UI_SCRIPT.exists():
        raise HTTPException(status_code=500, detail=f"db_ui.sh not found at {DB_UI_SCRIPT}")
    try:
        r = subprocess.run(
            ["bash", str(DB_UI_SCRIPT), "stop"],
            capture_output=True, text=True, timeout=30,
        )
        ok = r.returncode == 0
        (logger.info if ok else logger.error)("pgweb stop: rc={}", r.returncode)
        return {"success": ok, "output": (r.stdout + r.stderr).strip()}
    except Exception as e:
        logger.error("pgweb stop error: {}", e)
        return {"success": False, "output": str(e)}


@app.post("/api/db/stop")
def db_stop():
    logger.info("Stopping PostgreSQL")
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


# ── Schema registry ────────────────────────────────────────────────────────────

@app.get("/api/schemas")
def list_schemas():
    pg_up = subprocess.run(
        ["pg_isready", "-h", "localhost", "-p", "5432"], capture_output=True
    ).returncode == 0
    schemas = []
    for name, script in _INITDB_SCRIPTS.items():
        meta = _SCHEMA_META.get(name, {})
        initialized = _db_exists(name) if pg_up else None
        schemas.append({
            "name":          name,
            "label":         meta.get("label",       name),
            "description":   meta.get("description", ""),
            "icon":          meta.get("icon",        "🗄"),
            "color":         meta.get("color",       "#58a6ff"),
            "initialized":   initialized,
            "script_exists": script.exists(),
        })
    return {"schemas": schemas}


# ── Streaming action endpoints (SSE) ──────────────────────────────────────────

@app.post("/api/stream/db/start")
def stream_db_start():
    logger.info("Streaming: start PostgreSQL")
    return _stream_script(["bash", str(STARTDB), "--prepare-only"])


@app.post("/api/stream/db/stop")
def stream_db_stop():
    logger.info("Streaming: stop PostgreSQL")
    return _stream_script(
        ["gosu", "postgres", "pg_ctl", "-D", PGDATA, "stop", "-m", "fast"]
    )


@app.post("/api/stream/initdb/{db_name}")
def stream_initdb(db_name: str):
    logger.info("Streaming: initdb {}", db_name)
    script = _INITDB_SCRIPTS.get(db_name)
    if not script:
        from fastapi.responses import StreamingResponse as _SR
        def _err():
            yield f"data: [ERROR] Unknown database: '{db_name}'\n\n"
            yield "data: __done__\n\n"
        return _SR(_err(), media_type="text/event-stream",
                   headers={"Cache-Control": "no-cache"})
    return _stream_script(["bash", str(script), "--prepare-only"])


@app.post("/api/stream/cleandb/{db_name}")
def stream_cleandb(db_name: str):
    logger.info("Streaming: cleandb {}", db_name)
    script = _CLEANDB_SCRIPTS.get(db_name)
    if not script:
        from fastapi.responses import StreamingResponse as _SR
        def _err():
            yield f"data: [ERROR] Unknown database: '{db_name}'\n\n"
            yield "data: __done__\n\n"
        return _SR(_err(), media_type="text/event-stream",
                   headers={"Cache-Control": "no-cache"})
    return _stream_script(["bash", str(script), "--yes"])


@app.post("/api/stream/dbui/start")
def stream_dbui_start():
    logger.info("Streaming: start pgweb")
    return _stream_script(["bash", str(DB_UI_SCRIPT), "start"])


@app.post("/api/stream/dbui/stop")
def stream_dbui_stop():
    logger.info("Streaming: stop pgweb")
    return _stream_script(["bash", str(DB_UI_SCRIPT), "stop"])


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


# ── Backup & restore ──────────────────────────────────────────────────────────

_BACKUP_SCRIPTS = {
    "ums":     BACKUP_DIR / "backup_ums.sh",
    "mydocs":  BACKUP_DIR / "backup_mydocs.sh",
    "wholedb": BACKUP_DIR / "backup_wholedb.sh",
}
_RESTORE_SCRIPTS = {
    "ums":     BACKUP_DIR / "restore_ums.sh",
    "mydocs":  BACKUP_DIR / "restore_mydocs.sh",
    "wholedb": BACKUP_DIR / "restore_wholedb.sh",
}


@app.get("/api/backup/files/{db_name}")
def backup_files(db_name: str):
    folder = BACKUPS_ROOT / db_name
    if not folder.exists():
        return {"files": []}
    files = sorted(
        (f.name for f in folder.iterdir() if f.suffix in (".gz", ".sql")),
        reverse=True,
    )
    return {"files": files}


@app.post("/api/stream/backup/{db_name}")
def stream_backup(db_name: str):
    script = _BACKUP_SCRIPTS.get(db_name)
    if not script:
        from fastapi.responses import StreamingResponse as _SR
        def _err():
            yield f"data: [ERROR] Unknown database: '{db_name}'\n\n"
            yield "data: __done__\n\n"
        return _SR(_err(), media_type="text/event-stream", headers={"Cache-Control": "no-cache"})
    logger.info("Streaming: backup {}", db_name)
    return _stream_script(["bash", str(script)])


@app.post("/api/stream/restore/{db_name}")
def stream_restore(db_name: str, file: str):
    script = _RESTORE_SCRIPTS.get(db_name)
    if not script:
        from fastapi.responses import StreamingResponse as _SR
        def _err():
            yield f"data: [ERROR] Unknown database: '{db_name}'\n\n"
            yield "data: __done__\n\n"
        return _SR(_err(), media_type="text/event-stream", headers={"Cache-Control": "no-cache"})
    backup_file = str(BACKUPS_ROOT / db_name / file)
    logger.info("Streaming: restore {} from {}", db_name, backup_file)
    return _stream_script(["bash", str(script), backup_file])


# ── Cloud sync ────────────────────────────────────────────────────────────────

def _rclone_available() -> bool:
    return subprocess.run(["which", "rclone"], capture_output=True).returncode == 0


def _rclone_remote_configured() -> bool:
    try:
        r = subprocess.run(["rclone", "listremotes"], capture_output=True, text=True, timeout=5)
        return "gdrive:" in r.stdout
    except Exception:
        return False


RCLONE_PORT     = 5572
RCLONE_PID_FILE = Path("/tmp/rclone-ui.pid")


def _rclone_ui_running() -> bool:
    try:
        pid = int(RCLONE_PID_FILE.read_text().strip())
        os.kill(pid, 0)
        return True
    except Exception:
        return False


@app.get("/api/cloud/status")
def cloud_status():
    installed  = _rclone_available()
    configured = _rclone_remote_configured() if installed else False
    return {
        "rclone_installed": installed,
        "gdrive_configured": configured,
        "rclone_ui_running": _rclone_ui_running(),
    }


@app.post("/api/stream/cloud/ui/start")
def stream_rclone_ui_start():
    logger.info("Starting rclone web UI")
    def generate():
        try:
            proc = subprocess.Popen(
                ["rclone", "rcd", "--rc-web-gui",
                 f"--rc-addr=0.0.0.0:{RCLONE_PORT}",
                 "--rc-no-auth"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            )
            RCLONE_PID_FILE.write_text(str(proc.pid))
            yield f"data: [INFO] rclone web UI started (pid {proc.pid}) on port {RCLONE_PORT}\n\n"
            yield f"data: [INFO] Open: http://localhost:{RCLONE_PORT}\n\n"
        except Exception as e:
            yield f"data: [ERROR] {e}\n\n"
        yield "data: __done__\n\n"
    from fastapi.responses import StreamingResponse as _SR
    return _SR(generate(), media_type="text/event-stream",
               headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@app.post("/api/stream/cloud/ui/stop")
def stream_rclone_ui_stop():
    logger.info("Stopping rclone web UI")
    def generate():
        try:
            pid = int(RCLONE_PID_FILE.read_text().strip())
            os.kill(pid, 15)
            RCLONE_PID_FILE.unlink(missing_ok=True)
            yield "data: [INFO] rclone web UI stopped.\n\n"
        except Exception as e:
            yield f"data: [ERROR] {e}\n\n"
        yield "data: __done__\n\n"
    from fastapi.responses import StreamingResponse as _SR
    return _SR(generate(), media_type="text/event-stream",
               headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


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


@app.post("/api/chat/clear")
def chat_clear():
    try:
        if _CHAT_LOG.exists():
            _CHAT_LOG.unlink()
        logger.info("Chat history cleared")
        return {"success": True}
    except Exception as e:
        logger.error("Chat clear error: {}", e)
        return {"success": False, "error": str(e)}


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
