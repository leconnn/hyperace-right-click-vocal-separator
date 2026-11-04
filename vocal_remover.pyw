"""Windows Explorer context-menu entry point for HyperACE source separation."""

from __future__ import annotations

import msvcrt
import os
import sys
import tempfile
import threading
import time
import tkinter as tk
from pathlib import Path
from tkinter import ttk


SCRIPT_DIR = Path(__file__).resolve().parent
os.chdir(SCRIPT_DIR)
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

MODES = {"vocals", "instrumental"}
args = sys.argv[1:]
MODE = args[0].lower() if args and args[0].lower() in MODES else "both"
FILES = args[1:] if MODE != "both" else args
AUDIO_EXTENSIONS = {
    ".aac", ".aiff", ".alac", ".amr", ".ape", ".au", ".flac", ".m4a",
    ".mp1", ".mp2", ".mp3", ".ogg", ".opus", ".ra", ".tta", ".wav", ".wma",
}
LOG_FILE = Path(tempfile.gettempdir()) / "hyperace_right_click.log"
QUEUE_DIR = Path(tempfile.gettempdir()) / f"hyperace_{MODE}_queue"
LOCK_FILE = Path(tempfile.gettempdir()) / f"hyperace_{MODE}.lock"


def log(message: str) -> None:
    try:
        with LOG_FILE.open("a", encoding="utf-8") as stream:
            stream.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}\n")
    except OSError:
        pass


def enqueue(paths: list[str]) -> None:
    QUEUE_DIR.mkdir(exist_ok=True)
    for path in paths:
        job = QUEUE_DIR / f"{os.getpid()}_{time.time_ns()}.job"
        job.write_text(path, encoding="utf-8")


def dequeue() -> str | None:
    QUEUE_DIR.mkdir(exist_ok=True)
    for job in sorted(QUEUE_DIR.glob("*.job")):
        try:
            path = job.read_text(encoding="utf-8").strip()
            job.unlink()
            return path
        except OSError:
            continue
    return None


_lock_stream = None


def take_lock() -> bool:
    # Windows releases this byte-range lock if the process dies, so a crashed
    # run can never leave a stale lock behind.
    global _lock_stream
    try:
        stream = LOCK_FILE.open("a+b")
    except OSError:
        return False
    try:
        stream.seek(0)
        msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        stream.close()
        return False
    _lock_stream = stream
    return True


def release_lock() -> None:
    global _lock_stream
    if _lock_stream is None:
        return
    try:
        _lock_stream.seek(0)
        msvcrt.locking(_lock_stream.fileno(), msvcrt.LK_UNLCK, 1)
    except OSError:
        pass
    _lock_stream.close()
    _lock_stream = None


def process_file(path: str, set_status) -> str | None:
    input_path = Path(path)
    if not input_path.is_file() or input_path.suffix.lower() not in AUDIO_EXTENSIONS:
        return None
    try:
        from hyperace_separator import separate_file

        separate_file(input_path, MODE, set_status)
        return None
    except Exception as error:
        log(f"Failed to separate {input_path}: {error}")
        return str(error)


def worker(set_status, root: tk.Tk) -> None:
    processed = 0
    errors: list[str] = []
    try:
        time.sleep(0.3)
        empty_checks = 0
        while empty_checks < 3:
            path = dequeue()
            if path is None:
                empty_checks += 1
                time.sleep(0.15)
                continue
            empty_checks = 0
            error = process_file(path, set_status)
            if error:
                errors.append(f"{Path(path).name}: {error}")
            else:
                processed += 1
    finally:
        release_lock()

    if errors:
        set_status(f"Finished {processed}; {len(errors)} failed. See {LOG_FILE.name}.")
        time.sleep(4)
    else:
        set_status(f"Finished {processed} file(s).")
        time.sleep(1)
    root.after(0, root.destroy)


def main() -> None:
    enqueue(FILES)
    if not take_lock():
        return

    titles = {
        "vocals": "HyperACE — Vocals",
        "instrumental": "HyperACE — Instrumentals",
        "both": "HyperACE — Separate",
    }
    root = tk.Tk()
    root.title(titles[MODE])
    root.resizable(False, False)
    frame = tk.Frame(root, padx=20, pady=16)
    frame.pack(fill="both", expand=True)
    status = tk.StringVar(value="Preparing HyperACE…")
    tk.Label(frame, textvariable=status, wraplength=360, justify="left", anchor="w").pack(fill="x")
    progress = ttk.Progressbar(frame, mode="indeterminate", length=360)
    progress.pack(pady=(10, 0))
    progress.start(12)
    root.geometry(f"400x90+{(root.winfo_screenwidth() - 400) // 2}+{(root.winfo_screenheight() - 90) // 2}")
    threading.Thread(
        target=worker,
        args=(lambda message: root.after(0, status.set, message), root),
        daemon=True,
    ).start()
    root.mainloop()


if __name__ == "__main__":
    main()
