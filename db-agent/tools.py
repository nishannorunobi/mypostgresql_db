import os
import json
import socket
import subprocess
import urllib.request
import urllib.error
import psycopg2
import psycopg2.extras
from pathlib import Path
from datetime import datetime
from dotenv import load_dotenv

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
                "sql":  {"type": "string",  "description": "SQL statement to execute"},
                "role": {"type": "string",  "description": "postgres role: 'ums_user' (default) or 'postgres' (admin)"},
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
        "name": "update_meta",
        "description": (
            "Update the structured meta.json file. "
            "Other agents (e.g. workspace-agent) can consume this to understand DB state."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "meta": {
                    "type": "object",
                    "description": "Key-value pairs to merge into meta.json"
                }
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
            database=inp.get("database")
        )

    if name == "get_db_logs":
        lines = inp.get("lines", 50)
        log_file = "/tmp/postgres.log"
        if not os.path.exists(log_file):
            return {"error": f"{log_file} not found — start PostgreSQL via umsdb/scripts/startdb.sh"}
        try:
            result = subprocess.run(
                ["tail", f"-{lines}", log_file],
                capture_output=True, text=True, timeout=5
            )
            return {"log": result.stdout, "file": log_file}
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
        return {"columns": cols.get("rows", []), "indexes": idxs.get("rows", []),
                "error": cols.get("error") or idxs.get("error")}

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
                result["http_status"] = resp.status
                result["http"] = "ok"
                result["url"] = url
            except urllib.error.HTTPError as e:
                result["http_status"] = e.code
                result["http"] = "error"
                result["url"] = url
            except Exception as e:
                result["http"] = f"error: {e}"
                result["url"] = url
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

    if name == "update_meta":
        MEMORY_DIR.mkdir(exist_ok=True)
        meta_path = MEMORY_DIR / "meta.json"
        existing  = json.loads(meta_path.read_text()) if meta_path.exists() else {}
        existing.update(inp["meta"])
        existing["last_updated"] = datetime.now().isoformat()
        meta_path.write_text(json.dumps(existing, indent=2))
        return {"saved": str(meta_path)}

    return {"error": f"Unknown tool: {name}"}
