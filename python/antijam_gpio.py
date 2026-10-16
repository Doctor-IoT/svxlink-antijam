#!/usr/bin/env python3
"""
antijam_gpio.py - Hardware PTT enforcer for the SvxLink anti-jam system
Version : 1.0
Author  : IZ0ABD Francesco - https://iz0abd.wordpress.com
Repo    : https://github.com/Doctor-IoT/svxlink-antijam
Hardware: UDOO NEO (Ubuntu 18.04, ARM) — GPIO177 = PTT (connector J5)

Monitors the systemd journal for lockout messages produced by antijam.tcl
and forces gpio177 = 0 every POLL_INTERVAL seconds during the lockout,
exploiting the TX_DELAY window configured in svxlink.conf (typically 250 ms).

Python 3.6 compatible (Ubuntu 18.04): uses universal_newlines=True instead
of text=True, which was introduced in Python 3.7.
"""

import re
import subprocess
import threading
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
GPIO_NUM       = 177       # PTT GPIO number on UDOO NEO (connector J5)
POLL_INTERVAL  = 0.050     # seconds between GPIO writes during lockout
GUARD_EXTRA_S  = 2         # extra guard seconds added on top of TCL lockout

GPIO_BASE      = Path(f"/sys/class/gpio/gpio{GPIO_NUM}")
GPIO_EXPORT    = Path("/sys/class/gpio/export")
GPIO_VALUE     = GPIO_BASE / "value"
GPIO_DIRECTION = GPIO_BASE / "direction"

# These strings must match the printInfo messages in antijam.tcl exactly.
RE_LOCKOUT_START = re.compile(r'ANTIJAM: lockout attivato per (\d+)s')
RE_LOCKOUT_END   = re.compile(r'ANTIJAM: lockout terminato')


def log(msg: str) -> None:
    print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} [antijam-gpio] {msg}", flush=True)


def gpio_setup() -> None:
    """Export and configure the GPIO pin as output, initially low (PTT off)."""
    if not GPIO_BASE.exists():
        GPIO_EXPORT.write_text(str(GPIO_NUM))
        time.sleep(0.3)
    GPIO_DIRECTION.write_text("out")
    GPIO_VALUE.write_text("0")
    log(f"gpio{GPIO_NUM} configured as output (PTT initially off).")


class LockoutState:
    """Thread-safe lockout state."""

    def __init__(self) -> None:
        self._lock  = threading.Lock()
        self._until = 0.0

    def activate(self, seconds: int) -> None:
        with self._lock:
            self._until = time.monotonic() + seconds + GUARD_EXTRA_S
        log(f"GPIO lockout activated for {seconds}s (+ {GUARD_EXTRA_S}s guard).")

    def deactivate(self) -> None:
        with self._lock:
            self._until = 0.0
        log("GPIO lockout released.")

    @property
    def active(self) -> bool:
        with self._lock:
            return time.monotonic() < self._until


def enforcer_loop(state: LockoutState) -> None:
    """Keep PTT low every POLL_INTERVAL seconds while lockout is active."""
    while True:
        if state.active:
            try:
                GPIO_VALUE.write_text("0")
            except OSError:
                pass
            time.sleep(POLL_INTERVAL)
        else:
            time.sleep(0.2)


def journal_monitor(state: LockoutState) -> None:
    """Follow the svxlink journal and update lockout state on matching lines."""
    cmd = [
        "journalctl", "--unit=svxlink",
        "--follow", "--lines=0", "--output=cat"
    ]
    log("Starting journald monitor (unit: svxlink)...")
    while True:
        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                universal_newlines=True,   # Python 3.6 compat (text= is 3.7+)
            )
            for raw_line in proc.stdout:
                line = raw_line.strip()
                m = RE_LOCKOUT_START.search(line)
                if m:
                    state.activate(int(m.group(1)))
                elif RE_LOCKOUT_END.search(line):
                    state.deactivate()
            proc.wait()
        except Exception as exc:
            log(f"Monitor error: {exc}. Retrying in 3 s...")
        time.sleep(3)


def main() -> None:
    log(f"Starting antijam-gpio — PTT pin: gpio{GPIO_NUM}")
    gpio_setup()
    state = LockoutState()
    threading.Thread(target=enforcer_loop, args=(state,), daemon=True).start()
    try:
        journal_monitor(state)
    except KeyboardInterrupt:
        pass
    finally:
        GPIO_VALUE.write_text("0")
        log("Exiting — PTT forced low.")


if __name__ == "__main__":
    main()
