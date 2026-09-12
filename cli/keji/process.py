"""Safe subprocess streaming for long-running local AI tools."""
import os
import signal
import subprocess
import threading
from typing import IO, List, Optional, Sequence, Tuple


def run_streaming(
    cmd: Sequence[str], cwd: str, log_file: str, env: Optional[dict] = None,
    timeout: Optional[float] = None,
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
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
        stdout_thread.join(timeout=2)
        stderr_thread.join(timeout=2)
        proc.stdout.close()
        proc.stderr.close()
        log.write("--- exit %s ---\n" % proc.returncode)
    return int(proc.returncode), lines


def _tee(stream: IO[str], log: IO[str], lines: Optional[List[str]], lock: threading.Lock, prefix: str) -> None:
    for line in iter(stream.readline, ""):
        if lines is not None:
            lines.append(line.rstrip("\n"))
        with lock:
            log.write(prefix + line)
            log.flush()


def _shell_quote(value: str) -> str:
    if not value or any(ch in value for ch in " \t\n\"'$`\\"):
        return "'" + value.replace("'", "'\\''") + "'"
    return value
