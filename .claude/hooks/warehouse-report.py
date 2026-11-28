#!/usr/bin/env python3
"""Session hook: tells Warehouse how this session's turn ended, and when the owner replied.

On `Stop` it reads the hook event from stdin, takes the end of Claude's last message (which
carries the `Статус: …` line), and posts it to the Warehouse service together with the session
id, repository and branch. On `UserPromptSubmit` it reports only that the session is working
again, so a request the owner has just answered stops waiting for them.

It must never get in the session's way: it prints nothing, always exits 0, and gives up after
five seconds whatever happens.

A session that starts in the folder above several repositories has no repository settings, so
the hook is also installed for the user: `python3 warehouse-report.py --install` adds it to
~/.claude/settings.json (an environment's setup script does it). When both copies fire for one
turn, the first reports and the second stays quiet. The repository it reports is the session's
own, or, from a folder above repositories, the one touched last.

Configuration (environment):
  WAREHOUSE_URL           base URL of the service; defaults to DEFAULT_URL below, empty = off
  WAREHOUSE_REPORT_TOKEN  bearer token; in cloud sessions leave it unset — the environment's
                          network proxy puts the real token into the request
"""
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time

# The deployed service. Empty would make the hook stay silent and send nothing anywhere.
DEFAULT_URL = "https://warehouse-henna-pi.vercel.app"
TAIL_CHARS = 2000
TRANSCRIPT_BYTES = 400_000
# The same turn reported twice within this many seconds (the repository's hook and the user's) goes once.
DEDUP_SECONDS = 60
HOOK_EVENTS = ("Stop", "UserPromptSubmit")


def git(cwd, *args):
    try:
        out = subprocess.run(
            ["git", *args], cwd=cwd, capture_output=True, text=True, timeout=1.5
        )
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:
        return ""


def repo_of(cwd):
    """owner/name from the origin URL, whatever its form (https, ssh, a local proxy)."""
    url = git(cwd, "remote", "get-url", "origin")
    m = re.search(r"([\w.-]+)/([\w.-]+?)(?:\.git)?/?$", url.replace(":", "/"))
    return f"{m.group(1)}/{m.group(2)}" if m else None


def work_dir(cwd):
    """The repository the session works in.

    A session with several repositories starts in the folder that holds them, which is not a
    repository itself: then it is the one among them touched last (a commit, a checkout, a
    status refreshes .git/index or .git/logs/HEAD).
    """
    if git(cwd, "rev-parse", "--show-toplevel"):
        return cwd
    best, newest = cwd, 0.0
    try:
        names = os.listdir(cwd)
    except Exception:
        return cwd
    for name in names:
        dot_git = os.path.join(cwd, name, ".git")
        if not os.path.isdir(dot_git):
            continue
        for marker in ("index", "HEAD", os.path.join("logs", "HEAD")):
            try:
                t = os.path.getmtime(os.path.join(dot_git, marker))
            except OSError:
                continue
            if t > newest:
                best, newest = os.path.join(cwd, name), t
    return best


def last_message_from_transcript(path):
    """The last text Claude wrote, for versions that do not pass it in the event."""
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            f.seek(max(0, f.tell() - TRANSCRIPT_BYTES))
            lines = f.read().decode("utf-8", "replace").splitlines()
    except Exception:
        return ""
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except Exception:
            continue
        if not isinstance(entry, dict) or entry.get("type") != "assistant":
            continue
        content = (entry.get("message") or {}).get("content")
        if isinstance(content, str) and content.strip():
            return content
        if isinstance(content, list):
            text = "\n".join(
                b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"
            )
            if text.strip():
                return text
    return ""


def first_to_report(session_id, kind, message):
    """True for the first hook to report this turn; a second copy of the hook stays quiet."""
    key = hashlib.sha256(f"{session_id}|{kind}|{message}".encode("utf-8")).hexdigest()[:20]
    path = os.path.join(tempfile.gettempdir(), f"warehouse-report-{key}")
    try:
        os.close(os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600))
        return True
    except FileExistsError:
        try:
            if time.time() - os.path.getmtime(path) < DEDUP_SECONDS:
                return False
            os.utime(path)
            return True
        except OSError:
            return True
    except OSError:
        return True


def install(settings_path):
    """Adds this script to a Claude Code settings file for both events, once, keeping the rest."""
    me = os.path.abspath(__file__)
    command = f'python3 "{me}" >/dev/null 2>&1 || true'
    try:
        with open(settings_path, encoding="utf-8") as f:
            settings = json.load(f)
        if not isinstance(settings, dict):
            settings = {}
    except (OSError, ValueError):
        settings = {}
    hooks = settings.setdefault("hooks", {})
    for event in HOOK_EVENTS:
        groups = hooks.setdefault(event, [])
        present = any(
            isinstance(h, dict) and h.get("command") == command
            for g in groups if isinstance(g, dict)
            for h in g.get("hooks", [])
        )
        if not present:
            groups.append({"hooks": [{"type": "command", "command": command, "timeout": 10}]})
    os.makedirs(os.path.dirname(os.path.abspath(settings_path)), exist_ok=True)
    with open(settings_path, "w", encoding="utf-8") as f:
        json.dump(settings, f, ensure_ascii=False, indent=2)
        f.write("\n")


def main():
    # An explicitly empty WAREHOUSE_URL switches the hook off (tests, or a machine that should stay quiet).
    base = os.environ.get("WAREHOUSE_URL", DEFAULT_URL).rstrip("/")
    if not base.startswith(("https://", "http://127.0.0.1", "http://localhost")):
        return  # not configured, or not a transport that keeps the message private
    event = json.loads(sys.stdin.read())
    if not isinstance(event, dict) or event.get("stop_hook_active"):
        return

    # A cloud session is known to the owner by the id in its URL, session_<x>;
    # inside the container the same id is spelled cse_<x>.
    remote = os.environ.get("CLAUDE_CODE_REMOTE_SESSION_ID", "")
    session_id = "session_" + remote[4:] if remote.startswith("cse_") else event.get("session_id")
    if not session_id or not isinstance(session_id, str):
        return

    kind = event.get("hook_event_name") or "Stop"
    if kind == "UserPromptSubmit":
        # The owner answered: whatever the session was waiting for, it is working again.
        # Only that fact is reported — never what the owner wrote.
        message = "Статус: работаю — получено новое сообщение"
    elif kind == "Stop":
        message = event.get("last_assistant_message")
        if not isinstance(message, str):
            message = last_message_from_transcript(event.get("transcript_path") or "")
    else:
        return

    if not first_to_report(session_id, kind, message[-TAIL_CHARS:]):
        return

    cwd = event.get("cwd") if isinstance(event.get("cwd"), str) and os.path.isdir(event.get("cwd")) else os.getcwd()
    cwd = work_dir(cwd)
    body = {
        "session_id": session_id[:200],
        "repo": repo_of(cwd),
        "branch": git(cwd, "branch", "--show-current") or None,
        "message_tail": message[-TAIL_CHARS:],
        "sent_at": subprocess.run(
            ["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"], capture_output=True, text=True, timeout=1
        ).stdout.strip(),
    }

    token = os.environ.get("WAREHOUSE_REPORT_TOKEN") or "proxy-injected"
    subprocess.run(
        [
            "curl", "--silent", "--output", os.devnull,
            "--max-time", "4", "--connect-timeout", "3",
            "--request", "POST",
            "--header", "Content-Type: application/json",
            "--header", f"Authorization: Bearer {token}",
            "--data-binary", "@-",
            f"{base}/api/report/session",
        ],
        input=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=4.5,
    )


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "--install":
        # Set-up, run by hand or by an environment's setup script: here errors may be seen.
        install(sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.claude/settings.json"))
        sys.exit(0)
    # Whatever happens below, the session sees silence and success.
    try:
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, 1)
        os.dup2(devnull, 2)
        signal.signal(signal.SIGALRM, lambda *_: os._exit(0))
        signal.alarm(5)
        main()
    except BaseException:
        pass
    os._exit(0)
