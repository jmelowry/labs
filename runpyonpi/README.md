# Project: PiRun (working name)

## Overview

PiRun is a single-binary Go tool that provides a per-directory, sandboxed web UI and CLI for:
- Listing and editing files under a project directory.
- Executing Python scripts via that directory’s isolated virtual environment.
- Synchronizing the directory with a remote Git repository.

Primary goals:
- Ultra-lightweight install and runtime footprint on Raspberry Pi.
- No access outside the configured project directory.
- Python-only execution with a per-project venv.
- Simple, fast feedback loops from a browser or CLI.

Non-goals:
- Multi-tenant security hardening beyond directory sandboxing.
- Arbitrary shell execution.
- IDE-level editing; provide basic text editing only.

## Requirements

Functional
- Initialize a project directory with configuration, venv, and scaffolding.
- Serve a minimal web UI and JSON API to list/edit files, run scripts, and sync Git.
- Run Python scripts using the project’s venv with arguments and timeouts.
- Show live or recent output logs per run.
- Git operations: status, pull, push; initial clone/init if missing.

Non-functional
- Single static binary for ARM/ARM64.
- Minimal memory/CPU usage; suitable for Pi Zero 2 W and up.
- Safe-by-default path handling; no traversal outside base directory.
- Default bind to 127.0.0.1; opt-in LAN exposure later.

## Architecture

High level
- One Go binary (net/http, encoding/json) with an embedded static UI.
- Project-scoped runtime:
  - Base directory (baseDir)
  - Config file: .pirun.yaml
  - Python venv: .venv/
  - Logs: var/logs/
  - Optional: scripts/ starter folder

Key components
- HTTP server: REST-ish JSON API + minimal static UI.
- File service: list, read, write, delete within baseDir.
- Exec service: Python-only exec via .venv/bin/python.
- Git service: go-git based repo management under baseDir.
- CLI: wraps init/serve/run/git commands and talks to local API when serving.

Data flow
- Web/CLI -> API handlers -> services (file/exec/git) -> filesystem/venv/.git -> logs/status back to client.

## Security and Sandbox

- BaseDir confinement: All paths are treated as relative; joined via filepath.Clean and validated to remain under baseDir. Reject absolute paths and “..”.
- Symlinks: Option 1 (default) reject symlinks on write/exec; Option 2 resolve real path and verify prefix.
- Execution: Only .py files, executed via .venv/bin/python with argument slice (no shell). Timeouts and cancellation supported.
- Network exposure: Bind to 127.0.0.1 by default. For LAN exposure, recommend a reverse proxy with basic auth. Run as non-root user.

## CLI

Commands
- pirun init /path/to/project
  - Creates .pirun.yaml, .venv via python3 -m venv .venv, var/logs, and optional scripts/ scaffold.
- pirun serve /path/to/project [--addr 127.0.0.1:8080]
  - Starts the HTTP server bound to the address, using the project config.
- pirun run /path/to/project scripts/foo.py -- --arg1 val
  - Invokes the same execution service as the API; prints log tail to stdout.
- pirun git status|pull|push /path/to/project
  - Uses the git service for the configured project.

Configuration (.pirun.yaml)
- name: friendly project name
- base_dir: absolute path (computed on init)
- venv_python: base_dir/.venv/bin/python
- git:
  - remote: <url or empty>
  - branch: <main or default>
  - auth: { type: https|ssh, token_path: …, ssh_key_path: … }
- server:
  - addr: 127.0.0.1:8080
  - read_timeout_ms: 5000
  - write_timeout_ms: 15000
  - run_timeout_ms: 30000
  - max_upload_bytes: 5_000_000

## API

Base URL: /api

- GET /files?path=relative/
  - Lists entries: name, size, modtime, type(file|dir).
- GET /file?path=relative
  - Returns file contents as text or JSON.
- PUT /file?path=relative
  - Writes text body to file (0644); creates parent dirs as needed. Rejects outside-base paths.
- DELETE /file?path=relative
  - Removes a file.
- POST /run
  - Body: { "path":"scripts/foo.py", "args":["--fast"] }
  - Returns: { "run_id":"uuid", "started_at":..., "timeout_ms":... }
- GET /run/status?run_id=...
  - Returns state: queued|running|succeeded|failed|killed, exit_code, started_at, ended_at.
- GET /run/log?run_id=...&tail_kb=64
  - Returns the last N KB of combined stdout/stderr.
- POST /git/pull
  - Fast-forward pull if clean; returns summary.
- POST /git/push
  - Push current branch; returns summary.
- GET /git/status
  - Branch, ahead/behind, dirty/untracked summary, last commit.

Notes
- All JSON endpoints set Content-Type: application/json and return structured errors: { "error":"message" }.
- CORS: disabled by default; add flag if a separate front-end is used.

## Execution Model

- Command: exec.CommandContext(venvPython, scriptPath, args...)
- Environment: inherit minimal env; add VIRTUAL_ENV and PATH=.venv/bin:$PATH
- Working directory: baseDir
- Timeouts: per-request context with default run_timeout_ms; cancel endpoint kills process.
- Logging: stdout and stderr multiplexed to var/logs/<run_id>.log; also buffered in-memory ring for fast UI updates.

## Git Model

- Library: go-git; no shelling out to git.
- Init: if .git absent, allow “init” or “clone” via remote URL.
- Pull: fetch and fast-forward merge; reject if dirty (return error with status so user can commit or stash).
- Push: HTTPS (PAT) or SSH (key) based on config; credentials stored in project-local files with 0600 perms.
- Status: file changes, branch, ahead/behind using remote tracking.

## Web UI (minimal)

- Single-page, minimal HTML+JS served from /.
- Views:
  - File browser: list, open, edit text files, save.
  - Runner: pick .py file, pass args, see live log tail.
  - Git: status, pull, push with feedback errors.
- No heavy frameworks; plain fetch() calls to API. Optional Tailwind for basic styles.

## Error Handling and Observability

- Structured errors with HTTP codes: 400 invalid path/args, 403 forbidden outside base, 404 not found, 409 git dirty/conflict, 500 internal.
- Logs:
  - Server log (stderr): requests, errors, panics with recover middleware.
  - Run logs per run_id.
- Health: GET /health returns { "ok": true }.

## Systemd Integration

Unit template (pirun@.service)
- WorkingDirectory=%i
- ExecStart=/usr/local/bin/pirun serve %i --addr 127.0.0.1:8080
- User=pirun
- Restart=on-failure
- MemoryAccounting=yes

Enable with:
- sudo systemctl enable pirun@/path/to/project
- sudo systemctl start pirun@/path/to/project

## Edge Cases and Decisions

- Large files: enforce max_upload_bytes; reject binary editing via UI (download/upload only).
- Long runs: encourage scripts to log progress; log tail endpoint supports paging by offset if needed later.
- Symlinks: default reject on write/exec; can allow with resolve+prefix-check flag.
- Concurrency: allow multiple runs; cap to N parallel with a semaphore; queue beyond N.
