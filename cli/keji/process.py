"""Safe subprocess streaming for long-running local AI tools."""
import os
import signal
import subprocess
import threading
import time
from typing import IO, List, Optional, Sequence, Tuple

MAX_CAPTURED_LINES = 10_000
MAX_LOG_BYTES = 10 * 1024 * 1024


def run_streaming(
    cmd: Sequence[str], cwd: str, log_file: str, env: Optional[dict] = None,
    timeout: Optional[float] = None, cancel_event: Optional[threading.Event] = None,
) -> Tuple[int, List[str]]:
    lines: List[str] = []
    run_env = dict(os.environ)
    for key in list(run_env):
        if key.startswith("CLAUDE"):
            run_env.pop(key, None)
    if env:
        run_env.update(env)
    with open(log_file, "a", encoding="utf-8") as log, open(os.devnull, "rb") as devnull:
        log.write("$ " + " ".join(_shell_quote(part) for part in cmd) + "\n")
        log.flush()
        proc = subprocess.Popen(
            list(cmd), cwd=cwd, stdin=devnull, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=run_env, text=True, bufsize=1, start_new_session=True,
        )
        assert proc.stdout is not None and proc.stderr is not None
        lock = threading.Lock()
        stdout_thread = threading.Thread(target=_tee, args=(proc.stdout, log, lines, lock, ""), daemon=True)
        stderr_thread = threading.Thread(target=_tee, args=(proc.stderr, log, None, lock, "[stderr] "), daemon=True)
        stdout_thread.start()
        stderr_thread.start()
        deadline = None if timeout is None else time.monotonic() + timeout
        while proc.poll() is None:
            if cancel_event is not None and cancel_event.wait(.2):
                _terminate_group(proc)
                break
            if deadline is not None and time.monotonic() >= deadline:
                _terminate_group(proc)
                break
            if cancel_event is None:
                try:
                    proc.wait(timeout=min(.2, timeout) if timeout is not None else .2)
                except subprocess.TimeoutExpired:
                    pass
        stdout_thread.join(timeout=2)
        stderr_thread.join(timeout=2)
        proc.stdout.close()
        proc.stderr.close()
        log.write("--- exit %s ---\n" % proc.returncode)
    return int(proc.returncode), lines


def _terminate_group(proc: subprocess.Popen) -> None:
    os.killpg(proc.pid, signal.SIGTERM)
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()


def _tee(stream: IO[str], log: IO[str], lines: Optional[List[str]], lock: threading.Lock, prefix: str) -> None:
    for line in iter(stream.readline, ""):
        if lines is not None:
            lines.append(line.rstrip("\n"))
            if len(lines) > MAX_CAPTURED_LINES:
                del lines[:len(lines) - MAX_CAPTURED_LINES]
        with lock:
            if log.tell() < MAX_LOG_BYTES:
                log.write((prefix + line)[:max(0, MAX_LOG_BYTES - log.tell())])
                log.flush()


def _shell_quote(value: str) -> str:
    if not value or any(ch in value for ch in " \t\n\"'$`\\"):
        return "'" + value.replace("'", "'\\''") + "'"
    return value
