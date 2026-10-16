# svxlink-antijam

**Anti-jamming protection system for a SvxLink repeater on UDOO NEO and other SBC**

Author  : IZ0ABD Francesco - https://iz0abd.wordpress.com
License : MIT  
Hardware: UDOO NEO (Ubuntu 18.04, ARM) or any other SBC — SvxLink 26.05.1

---

## Overview

Detects radio jamming attempts, also known as repeated TX requests in a short period, acting as  "Flapping Squelch Suppression", on a SvxLink-managed repeater and blocks
transmission via a hardware GPIO for a configurable duration.


The system works on two cooperative levels:

| Level | Component | Role |
|---|---|---|
| Detection | `antijam.tcl` (TCL / SvxLink events) | Counts squelch opens, computes lockout, logs |
| PTT block | `antijam_gpio.py` (Python + sysfs) | Forces GPIO PTT = 0 every 50 ms during lockout |

The second level is necessary because SvxLink activates the PTT hardware
**before** calling TCL event handlers — TCL alone cannot prevent transmission.
The Python daemon exploits the `TX_DELAY` window (typically 250 ms) to pull
the PTT pin low before any audio reaches the transmitter.

---

## Detection logic

- Squelch opens are counted inside a sliding window of `JAM_WINDOW_MS` ms.
- When `JAM_COUNT` opens are reached within the window → **lockout**.
- During lockout the repeater does not transmit for `LOCKOUT_MS` ms.
- An acoustic warning tone is played periodically (configurable).
- After lockout expires the counter resets and a new cycle can begin.

### Parameters (in `antijam.tcl`)

| Variable | Default | Description |
|---|---|---|
| `JAM_COUNT` | `3` | Squelch opens that trigger lockout |
| `JAM_WINDOW_MS` | `15000` | Detection sliding window (ms) |
| `LOCKOUT_MS` | `30000` | Lockout duration (ms) |
| `WARN_ON_LOCKOUT` | `1` | Play warning tone during lockout (`0` = disabled) |
| `WARN_REPEAT_MS` | `5000` | Interval between warning tones (ms) |

---

## Repository layout

```
svxlink-antijam/
├── tcl/
│   ├── antijam.tcl          # TCL logic: detection and lockout state
│   └── RepeaterLogic.tcl    # Squelch hook wired into SvxLink
├── python/
│   └── antijam_gpio.py      # GPIO PTT enforcer (Python 3.6+)
├── systemd/
│   └── antijam-gpio.service # systemd unit
├── install.sh               # Automated install script
└── README.md
```

---

## Quick install

```bash
git clone https://github.com/Doctor-IoT/svxlink-antijam
cd svxlink-antijam
sudo bash install.sh
```

The script copies files to the correct locations, enables the systemd service,
and restarts SvxLink.

### Destination paths

| Source | Destination |
|---|---|
| `tcl/antijam.tcl` | `/usr/share/svxlink/events.d/local/` |
| `tcl/RepeaterLogic.tcl` | `/usr/share/svxlink/events.d/local/` |
| `python/antijam_gpio.py` | `/usr/local/lib/svxlink/` |
| `systemd/antijam-gpio.service` | `/etc/systemd/system/` |

---

## Verifying the installation

```bash
# Check service status
systemctl status svxlink.service
systemctl status antijam-gpio.service

# Follow live logs from both services
journalctl -f -u svxlink -u antijam-gpio
```

Open and close the squelch ≥ 3 times within 15 seconds to trigger a test
lockout. The log should show the counter incrementing (#1 → #2 → #3 → lockout
activated), then the repeater staying silent for 30 s, then the lockout
releasing automatically.

---

## Technical notes

### Why `after` does not work in SvxLink

SvxLink uses the Asynclib C++ event loop. Its TCL integration does not call
`Tcl_DoOneEvent()` between hardware squelch events: `after` callbacks are
enqueued in the TCL timer queue but are never dispatched during quiet radio
periods. Version 1.5 removes all `after` calls and instead stores the lockout
expiry timestamp in `lockout_end_ms`, checking it with `clock milliseconds`
on every incoming squelch event.

### TX_DELAY requirement

`TX_DELAY` in `svxlink.conf` must be ≥ 100 ms (recommended: 250 ms).
The Python daemon writes GPIO = 0 every 50 ms; it must have enough time to
intervene before audio is actually transmitted.

```ini
# /etc/svxlink/svxlink.conf
[Tx1]
TX_DELAY=250
```

### GPIO hardware (UDOO NEO)

The PTT line is connected to `gpio177` (connector J5). To adapt the system to
other hardware, change `GPIO_NUM` in `antijam_gpio.py` and the hardcoded
references in `antijam-gpio.service`.

---

## Changelog

| Version | Change |
|---|---|
| v1.0–v1.3 | Initial development, various TCL fixes |
| v1.4 | `after`-based timer — lockout fires only once (bug) |
| **v1.5** | **Timestamp-based timing — `after` removed entirely** |

---

## License

MIT License — free to use, modify and redistribute with attribution.
