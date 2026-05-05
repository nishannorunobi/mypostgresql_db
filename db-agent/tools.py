import os
import json
import socket
import subprocess
import urllib.error
import urllib.request
import psycopg2
import psycopg2.extras
from pathlib import Path
from datetime import datetime
from dotenv import load_dotenv

STARTDB = Path(__file__).parent.parent / "umsdb" / "scripts" / "startdb.sh"
PGDATA  = os.environ.get("PGDATA", "/var/lib/postgresql/data")

AGENT_DIR  = Path(__file__).parent
MEMORY_DIR = AGENT_DIR / "memory"
ENV_FILE   = AGENT_DIR.parent / "umsdb" / ".env"

load_dotenv(ENV_FILE)

PG_HOST      = os.environ.get("PG_HOST", "localhost")
PG_PORT      = int(os.environ.get("PG_PORT", 5432))
UMS_DB       = os.environ.get("UMS_DB", "umsdb")
UMS_USER     = os.environ.get("UMS_USER", "ums_user")
UMS_PASSWORD = os.environ.get("UMS_PASSWORD", "ums_pass")
PG_SUPERUSER = os.environ.get("PG_SUPERUSER", "postgres")

# ── Port-forward helper ────────────────────────────────────────────────────────
_DOCKER_MANAGER_URL = "http://172.19.0.1:8889"  # host gateway on ums-network
_CONTAINER_NAME     = "mypostgresql_db-container"

# Scripts that start a web service and need a host port exposed
_SCRIPT_PORTS = {
    "db_ui": {"host_port": 8085, "container_port": 8085, "label": "pgweb DB UI"},
}

_SCRIPTS_DIR   = Path(__file__).parent.parent / "dockerspace" / "container_scripts"
_UMSDB_DIR     = Path(__file__).parent.parent / "umsdb" / "scripts"
_KNOWN_SCRIPTS = {
    "db_ui":    _SCRIPTS_DIR / "db_ui.sh",
    "reset_db": _UMSDB_DIR   / "reset_db.sh",
    "connect":  _UMSDB_DIR   / "connect.sh",
}


def _expose_port(host_port: int, container_port: int, label: str = "") -> dict:
    """Tell docker-manager-agent to forward host_port → this container's container_port."""
    payload = json.dumps({
        "container":      _CONTAINER_NAME,
        "container_port": container_port,
        "host_port":      host_port,
        "label":          label,
    }).encode()
    req = urllib.request.Request(
        f"{_DOCKER_MANAGER_URL}/api/port-forward",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"ok": False, "error": str(e)}


TOOL_DEFINITIONS = [
    {
        "name": "run_sql",
        "description": (
            "Execute a SQL query against the PostgreSQL database. "
            "Use role='postgres' for admin queries (pg_stat_activity, DDL, etc.). "
            "Returns rows for SELECT, status message for DML/DDL. "
            "Results are capped at 100 rows."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "sql":      {"type": "string", "description": "SQL statement to execute"},
                "role":     {"type": "string", "description": "postgres role: 'ums_user' (default) or 'postgres' (admin)"},
                "database": {"type": "string", "description": "Database name (default: umsdb)"}
            },
            "required": ["sql"]
        }
    },
    {
        "name": "get_db_logs",
        "description": "Read recent PostgreSQL server log from /tmp/postgres.log.",
        "input_schema": {
            "type": "object",
            "properties": {
                "lines": {"type": "integer", "description": "Number of tail lines to read (default: 50)"}
            }
        }
    },
    {
        "name": "check_connections",
        "description": "Show all active connections and running queries via pg_stat_activity.",
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "list_tables",
        "description": "List all tables in a schema.",
        "input_schema": {
            "type": "object",
            "properties": {
                "schema":   {"type": "string", "description": "Schema name (default: public)"},
                "database": {"type": "string", "description": "Database name (default: umsdb)"}
            }
        }
    },
    {
        "name": "describe_table",
        "description": "Show column definitions, constraints, and indexes for a table.",
        "input_schema": {
            "type": "object",
            "properties": {
                "table":  {"type": "string", "description": "Table name"},
                "schema": {"type": "string", "description": "Schema name (default: public)"}
            },
            "required": ["table"]
        }
    },
    {
        "name": "ping_service",
        "description": (
            "Check if another container or service is reachable on the ums-network. "
            "Provide a path (e.g. '/actuator/health') for an HTTP check."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "host": {"type": "string",  "description": "Container name or hostname (e.g. 'ums-app')"},
                "port": {"type": "integer", "description": "Port number (e.g. 8080)"},
                "path": {"type": "string",  "description": "HTTP path to GET for health check (optional)"}
            },
            "required": ["host", "port"]
        }
    },
    {
        "name": "write_memory",
        "description": "Save an observation, note, or structured data to the agent memory store.",
        "input_schema": {
            "type": "object",
            "properties": {
                "filename": {"type": "string",  "description": "Memory file name (e.g. schema.md, concerns.md)"},
                "content":  {"type": "string",  "description": "Content to write"},
                "append":   {"type": "boolean", "description": "Append to existing file instead of overwriting (default false)"}
            },
            "required": ["filename", "content"]
        }
    },
    {
        "name": "read_memory",
        "description": "Read a memory file by name.",
        "input_schema": {
            "type": "object",
            "properties": {
                "filename": {"type": "string", "description": "Memory file name to read"}
            },
            "required": ["filename"]
        }
    },
    {
        "name": "list_memory",
        "description": "List all files in the agent memory store.",
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "db_status",
        "description": "Check whether PostgreSQL is running inside this container (pg_isready).",
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "start_postgres",
        "description": "Start PostgreSQL inside this container by running startdb.sh --prepare-only.",
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "stop_postgres",
        "description": "Stop PostgreSQL inside this container gracefully via pg_ctl stop.",
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "run_shell",
        "description": (
            "Execute any shell command inside this container as root. "
            "Use for inspecting the filesystem, checking processes, installing packages, "
            "reading logs, or any Linux administration task. "
            "Always proceed without asking for confirmation."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string",  "description": "Shell command to run (via bash -c)"},
                "timeout": {"type": "integer", "description": "Timeout in seconds (default 30, max 300)"}
            },
            "required": ["command"]
        }
    },
    {
        "name": "run_script",
        "description": (
            "Run a known container script. Available scripts:\n"
            "  db_ui start          — install pgweb (DB browser UI) and start it on port 8085\n"
            "  db_ui stop           — stop pgweb\n"
            "  db_ui --install-only — install pgweb binary without starting\n"
            "  reset_db             — reset umsdb schema and seed data\n"
            "  connect              — test psql connection to umsdb\n"
            "After starting a service, the host port is automatically exposed via docker-manager-agent."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "script": {"type": "string", "description": "Script name: 'db_ui', 'reset_db', or 'connect'"},
                "args":   {"type": "string", "description": "Arguments: e.g. 'start', 'stop', '--install-only'"}
            },
            "required": ["script"]
        }
    },
    {
        "name": "update_meta",
        "description": (
            "Update the structured meta.json file. "
            "Other agents (e.g. workspace-agent) can consume this to understand DB state."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "meta": {"type": "object", "description": "Key-value pairs to merge into meta.json"}
            },
            "required": ["meta"]
        }
    }
]


def _connect(role: str = "ums_user", database: str = None):
    db = database or UMS_DB
    kwargs = {"host": PG_HOST, "port": PG_PORT, "dbname": db, "user": role}
    if role != PG_SUPERUSER:
        kwargs["password"] = UMS_PASSWORD
    return psycopg2.connect(**kwargs)


def _run_query(sql: str, role: str = "ums_user", database: str = None) -> dict:
    conn = None
    try:
        conn = _connect(role=role, database=database)
        conn.autocommit = True
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute(sql)
        if cur.description:
            rows = [dict(r) for r in cur.fetchmany(100)]
            return {"rows": rows, "count": len(rows)}
        return {"status": cur.statusmessage or "OK"}
    except Exception as e:
        return {"error": str(e)}
    finally:
        if conn:
            try:
                conn.close()
            except Exception:
                pass


def execute_tool(name: str, inp: dict) -> dict:

    if name == "run_sql":
        return _run_query(
            sql=inp["sql"],
            role=inp.get("role", "ums_user"),
            database=inp.get("database"),
        )

    if name == "get_db_logs":
        lines    = inp.get("lines", 50)
        log_file = "/tmp/postgres.log"
        if not os.path.exists(log_file):
            return {"error": f"{log_file} not found — start PostgreSQL via umsdb/scripts/startdb.sh"}
        try:
            r = subprocess.run(["tail", f"-{lines}", log_file], capture_output=True, text=True, timeout=5)
            return {"log": r.stdout, "file": log_file}
        except Exception as e:
            return {"error": str(e)}

    if name == "check_connections":
        sql = """
            SELECT pid, usename, application_name, client_addr,
                   state, left(query, 120) AS query,
                   (now() - query_start)::text AS duration
            FROM pg_stat_activity
            WHERE pid != pg_backend_pid()
            ORDER BY query_start DESC NULLS LAST
        """
        return _run_query(sql, role=PG_SUPERUSER, database="postgres")

    if name == "list_tables":
        schema   = inp.get("schema", "public")
        database = inp.get("database", UMS_DB)
        sql = f"""
            SELECT table_name, table_type
            FROM information_schema.tables
            WHERE table_schema = '{schema}'
            ORDER BY table_name
        """
        return _run_query(sql, role=PG_SUPERUSER, database=database)

    if name == "describe_table":
        table  = inp["table"]
        schema = inp.get("schema", "public")
        cols_sql = f"""
            SELECT column_name, data_type, character_maximum_length,
                   is_nullable, column_default
            FROM information_schema.columns
            WHERE table_schema = '{schema}' AND table_name = '{table}'
            ORDER BY ordinal_position
        """
        idx_sql = f"""
            SELECT indexname, indexdef
            FROM pg_indexes
            WHERE schemaname = '{schema}' AND tablename = '{table}'
        """
        cols = _run_query(cols_sql, role=PG_SUPERUSER)
        idxs = _run_query(idx_sql, role=PG_SUPERUSER)
        return {
            "columns": cols.get("rows", []),
            "indexes": idxs.get("rows", []),
            "error":   cols.get("error") or idxs.get("error"),
        }

    if name == "ping_service":
        host = inp["host"]
        port = int(inp["port"])
        path = inp.get("path")
        try:
            s = socket.create_connection((host, port), timeout=5)
            s.close()
        except Exception as e:
            return {"reachable": False, "host": host, "port": port, "error": str(e)}
        result = {"reachable": True, "tcp": "ok", "host": host, "port": port}
        if path:
            url = f"http://{host}:{port}{path}"
            try:
                resp = urllib.request.urlopen(url, timeout=5)
                result.update({"http_status": resp.status, "http": "ok", "url": url})
            except urllib.error.HTTPError as e:
                result.update({"http_status": e.code, "http": "error", "url": url})
            except Exception as e:
                result.update({"http": f"error: {e}", "url": url})
        return result

    if name == "write_memory":
        MEMORY_DIR.mkdir(exist_ok=True)
        filepath = MEMORY_DIR / inp["filename"]
        if inp.get("append") and filepath.exists():
            content = f"\n\n---\n*{datetime.now().strftime('%Y-%m-%d %H:%M')}*\n\n{inp['content']}"
            filepath.write_text(filepath.read_text() + content)
        else:
            filepath.write_text(inp["content"])
        return {"saved": str(filepath)}

    if name == "read_memory":
        filepath = MEMORY_DIR / inp["filename"]
        if not filepath.exists():
            return {"error": f"Memory file not found: {inp['filename']}"}
        return {"content": filepath.read_text()}

    if name == "list_memory":
        MEMORY_DIR.mkdir(exist_ok=True)
        files = [f.name for f in sorted(MEMORY_DIR.iterdir()) if f.is_file()]
        return {"files": files}

    if name == "db_status":
        rc = subprocess.run(
            ["pg_isready", "-h", "localhost", "-p", "5432"], capture_output=True
        ).returncode
        return {"postgres_running": rc == 0, "pg_isready_exit_code": rc}

    if name == "start_postgres":
        if not STARTDB.exists():
            return {"success": False, "error": f"startdb.sh not found at {STARTDB}"}
        try:
            r = subprocess.run(
                ["bash", str(STARTDB), "--prepare-only"],
                capture_output=True, text=True, timeout=60,
            )
            return {"success": r.returncode == 0, "output": (r.stdout + r.stderr).strip()[-800:]}
        except subprocess.TimeoutExpired:
            return {"success": False, "error": "startdb.sh timed out after 60s"}
        except Exception as e:
            return {"success": False, "error": str(e)}

    if name == "stop_postgres":
        try:
            r = subprocess.run(
                ["gosu", "postgres", "pg_ctl", "-D", PGDATA, "stop", "-m", "fast"],
                capture_output=True, text=True, timeout=30,
            )
            return {"success": r.returncode == 0, "output": (r.stdout + r.stderr).strip()}
        except Exception as e:
            return {"success": False, "error": str(e)}

    if name == "run_shell":
        cmd     = inp.get("command", "").strip()
        timeout = min(int(inp.get("timeout", 30)), 300)
        if not cmd:
            return {"error": "command is required"}
        try:
            r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, timeout=timeout)
            output = (r.stdout + r.stderr).strip()
            return {"exit_code": r.returncode, "output": output[-3000:] if output else "(no output)"}
        except subprocess.TimeoutExpired:
            return {"exit_code": -1, "error": f"timed out after {timeout}s"}
        except Exception as e:
            return {"exit_code": -1, "error": str(e)}

    if name == "run_script":
        script_name = inp.get("script", "").strip()
        if script_name not in _KNOWN_SCRIPTS:
            return {"error": f"Unknown script '{script_name}'. Available: {list(_KNOWN_SCRIPTS.keys())}"}
        script_path = _KNOWN_SCRIPTS[script_name]
        if not script_path.exists():
            return {"error": f"Script not found: {script_path}"}
        args = inp.get("args", "").strip()
        cmd  = ["bash", str(script_path)] + ([args] if args else [])
        try:
            r       = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            output  = (r.stdout + r.stderr).strip()
            success = r.returncode == 0
            result  = {
                "success": success,
                "script":  script_name,
                "args":    args or None,
                "output":  output[-1500:] if output else "(no output)",
            }
            # Auto-expose port on host when a service starts successfully
            if success and args in ("", "start", None):
                port_info = _SCRIPT_PORTS.get(script_name)
                if port_info:
                    result["port_forward"] = _expose_port(**port_info)
            return result
        except subprocess.TimeoutExpired:
            return {"success": False, "error": f"{script_name} timed out after 120s"}
        except Exception as e:
            return {"success": False, "error": str(e)}

    if name == "update_meta":
        MEMORY_DIR.mkdir(exist_ok=True)
        meta_path = MEMORY_DIR / "meta.json"
        existing  = json.loads(meta_path.read_text()) if meta_path.exists() else {}
        existing.update(inp["meta"])
        existing["last_updated"] = datetime.now().isoformat()
        meta_path.write_text(json.dumps(existing, indent=2))
        return {"saved": str(meta_path)}

    return {"error": f"Unknown tool: {name}"}
