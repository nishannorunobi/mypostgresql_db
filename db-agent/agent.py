#!/usr/bin/env python3
import os
import sys
import json
from pathlib import Path
from datetime import datetime
import anthropic
from dotenv import load_dotenv
from tools import TOOL_DEFINITIONS, execute_tool, MEMORY_DIR

AGENT_DIR = Path(__file__).parent
load_dotenv(AGENT_DIR / "agent.conf")

SYSTEM_PROMPT = f"""You are the PostgreSQL Database Agent running inside mypostgresql_db-container.

Container:  mypostgresql_db-container
PostgreSQL: localhost:5432 (trust auth — no password barriers)
Database:   umsdb  (User Management System application database)
Log file:   /tmp/postgres.log
Network:    ums-network (shared with ums-app and other containers)
Memory:     {MEMORY_DIR}
Today:      {datetime.now().strftime('%Y-%m-%d')}

YOUR PURPOSE:
You are the expert on this database. You diagnose issues, monitor health, track schema
changes, run queries, and bridge communication between the database and other services
on the ums-network.

WHAT YOU KNOW:
- Application user: ums_user (limited permissions, used by the UMS Spring Boot app)
- Superuser: postgres (full access — use for pg_stat_activity, DDL, admin queries)
- UMS app container: ums-app:8080 on ums-network
- Schema: users, roles tables (check memory/schema.md for current state)
- PostgreSQL was started via umsdb/scripts/startdb.sh (trust auth patched in)

YOUR RESPONSIBILITIES:
1. DIAGNOSE   — Run SQL to investigate issues, errors, or anomalies
2. MONITOR    — Check active connections, locks, long-running queries, bloat
3. BRIDGE     — Ping ums-app and other containers to verify network connectivity
4. TRACK      — Log schema changes, major events, and concerns to memory
5. ADVISE     — Suggest specific fixes with exact SQL or config changes
6. REMEMBER   — Always update memory before ending a session
7. EXECUTE    — Run any shell command or container script the user requests

MEMORY FILES YOU MAINTAIN:
- schema.md      — current table definitions, indexes, and grants
- sessions.md    — log of agent sessions with timestamps
- change_log.md  — DDL changes and schema evolution over time
- concerns.md    — open issues, anomalies, and action items
- meta.json      — machine-readable summary for other agents

WHAT COUNTS AS WORTH LOGGING:
- Any DDL change (CREATE/ALTER/DROP TABLE, INDEX, SEQUENCE, etc.)
- Connection pool exhaustion or blocking/long-running queries
- Failed permission checks or missing grants
- Schema mismatches reported by the UMS app
- Cross-container connectivity failures

SHELL EXECUTION:
- You have run_shell to execute ANY Linux command inside this container as root
- Always proceed and execute — never ask for confirmation before running shell commands
- Use run_shell freely: install packages (apt-get), run scripts, inspect files, check processes
- Use run_script for known scripts: db_ui (start/stop pgweb), reset_db, connect

SAFETY RULES (SQL only):
- For destructive SQL (DROP, TRUNCATE, DELETE without WHERE), explain what will
  be lost and ask the user to confirm before executing
- Prefer SELECT first to verify targets before running DML
- Never DROP the umsdb database or the ums_user role without explicit confirmation

IMPORTANT:
- Always read relevant memory at the start of a session (list_memory → read what's relevant)
- Be specific: name the exact table, column, query, or config setting
- Save key findings to memory before ending a session
- Keep meta.json current — the workspace-agent reads it
"""

BOLD   = "\033[1m"
GREEN  = "\033[32m"
RED    = "\033[31m"
CYAN   = "\033[36m"
DIM    = "\033[2m"
YELLOW = "\033[33m"
RESET  = "\033[0m"


def print_tool_call(name: str, inp: dict):
    print(f"\n  {CYAN}[{name}]{RESET}", end=" ")
    if name == "run_sql":
        role = inp.get("role", "ums_user")
        print(f"({role})  {DIM}{inp['sql'][:120].strip()}{RESET}")
    elif name == "get_db_logs":
        print(f"lines={inp.get('lines', 50)}")
    elif name in ("write_memory", "read_memory"):
        print(inp.get("filename", ""))
    elif name == "ping_service":
        path = inp.get("path", "")
        print(f"{inp['host']}:{inp['port']}{path}")
    elif name == "describe_table":
        print(f"{inp.get('schema', 'public')}.{inp['table']}")
    elif name == "update_meta":
        print(f"keys={list(inp.get('meta', {}).keys())}")
    else:
        print()


def print_tool_result(name: str, result: dict):
    if result.get("error"):
        print(f"  {RED}  → error: {result['error']}{RESET}")
    elif name == "run_sql":
        if "rows" in result:
            rows = result["rows"]
            print(f"  {DIM}  → {result['count']} row(s){RESET}")
            for row in rows[:5]:
                print(f"  {DIM}    {dict(row)}{RESET}")
            if result["count"] > 5:
                print(f"  {DIM}    ... +{result['count'] - 5} more{RESET}")
        else:
            print(f"  {GREEN}  → {result.get('status', 'OK')}{RESET}")
    elif name == "get_db_logs":
        lines = result.get("log", "").split("\n")
        for line in lines[-15:]:
            if line.strip():
                print(f"  {DIM}  {line}{RESET}")
    elif name == "check_connections":
        rows = result.get("rows", [])
        print(f"  {DIM}  → {len(rows)} connection(s){RESET}")
        for row in rows[:8]:
            print(f"  {DIM}    {row}{RESET}")
    elif name == "ping_service":
        if result.get("reachable"):
            http = result.get("http_status", "")
            extra = f"  HTTP {http}" if http else ""
            print(f"  {GREEN}  → reachable{extra}{RESET}")
        else:
            print(f"  {RED}  → unreachable: {result.get('error')}{RESET}")
    elif name == "write_memory":
        print(f"  {GREEN}  → saved: {result.get('saved')}{RESET}")
    elif name == "update_meta":
        print(f"  {GREEN}  → meta.json updated{RESET}")
    elif name == "list_memory":
        print(f"  {DIM}  {result.get('files', [])}{RESET}")
    elif name == "describe_table":
        cols = result.get("columns", [])
        print(f"  {DIM}  → {len(cols)} column(s){RESET}")
        for col in cols:
            print(f"  {DIM}    {col}{RESET}")
    else:
        preview = str(result)[:150]
        print(f"  {DIM}  → {preview}{RESET}")


def log_session(note: str):
    entry = f"\n---\n**{datetime.now().strftime('%Y-%m-%d %H:%M')}** — {note}"
    sessions = MEMORY_DIR / "sessions.md"
    existing = sessions.read_text() if sessions.exists() else "# DB Agent Sessions\n"
    sessions.write_text(existing + entry)


def run_agent(user_message: str, history: list) -> list:
    client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

    history.append({"role": "user", "content": user_message})
    print(f"\n{BOLD}You:{RESET} {user_message}\n")

    while True:
        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=8096,
            system=SYSTEM_PROMPT,
            tools=TOOL_DEFINITIONS,
            messages=history
        )

        tool_calls  = [b for b in response.content if b.type == "tool_use"]
        text_blocks = [b for b in response.content if b.type == "text"]

        for block in text_blocks:
            if block.text.strip():
                print(f"\n{BOLD}Agent:{RESET} {block.text}")

        if response.stop_reason == "end_turn" or not tool_calls:
            final = " ".join(b.text for b in text_blocks if b.type == "text").strip()
            if final:
                history.append({"role": "assistant", "content": final})
            break

        history.append({"role": "assistant", "content": response.content})

        tool_results = []
        for block in tool_calls:
            print_tool_call(block.name, block.input)
            result = execute_tool(block.name, block.input)
            print_tool_result(block.name, result)
            tool_results.append({
                "type":        "tool_result",
                "tool_use_id": block.id,
                "content":     json.dumps(result, default=str)
            })

        history.append({"role": "user", "content": tool_results})

    print()
    return history


def chat_loop():
    MEMORY_DIR.mkdir(exist_ok=True)

    print(f"\n{BOLD}╔══════════════════════════════════════════╗{RESET}")
    print(f"{BOLD}║     PostgreSQL Database Agent            ║{RESET}")
    print(f"{BOLD}║     mypostgresql_db-container            ║{RESET}")
    print(f"{BOLD}╚══════════════════════════════════════════╝{RESET}")
    print(f"{DIM}Type your request or 'exit' to quit.{RESET}")
    print(f"{DIM}Suggested: 'scan schema and update memory' | 'check connections' | 'ping ums-app'{RESET}\n")

    log_session("session started")
    history = []

    while True:
        try:
            user_input = input(f"{BOLD}>{RESET} ").strip()
        except (EOFError, KeyboardInterrupt):
            print(f"\n{DIM}Session ended.{RESET}")
            log_session("session ended by user")
            break

        if not user_input:
            continue
        if user_input.lower() in ("exit", "quit"):
            log_session("session ended")
            print("Bye.")
            break

        history = run_agent(user_input, history)


if __name__ == "__main__":
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print(f"{RED}Error:{RESET} ANTHROPIC_API_KEY not set in agent.conf")
        sys.exit(1)

    MEMORY_DIR.mkdir(exist_ok=True)

    if len(sys.argv) > 1:
        run_agent(" ".join(sys.argv[1:]), [])
    else:
        chat_loop()
