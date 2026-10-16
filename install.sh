#!/bin/bash
# install.sh - Install the anti-jam system on SvxLink
# https://github.com/Doctor-IoT/svxlink-antijam
#
# Tested on: UDOO NEO - Ubuntu 18.04 ARM - SvxLink 26.05.1
# Requires : root

set -e

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

echo "=== Installing svxlink-antijam ==="

# 1. TCL scripts
echo "[1/4] Copying TCL files..."
cp tcl/antijam.tcl       /usr/share/svxlink/events.d/local/
cp tcl/RepeaterLogic.tcl /usr/share/svxlink/events.d/local/
echo "      -> /usr/share/svxlink/events.d/local/"

# 2. Python script
echo "[2/4] Copying antijam_gpio.py..."
mkdir -p /usr/local/lib/svxlink
cp python/antijam_gpio.py /usr/local/lib/svxlink/
chmod +x /usr/local/lib/svxlink/antijam_gpio.py
echo "      -> /usr/local/lib/svxlink/antijam_gpio.py"

# 3. systemd service
echo "[3/4] Installing systemd service..."
cp systemd/antijam-gpio.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable antijam-gpio.service
echo "      -> /etc/systemd/system/antijam-gpio.service (enabled)"

# 4. Restart services
echo "[4/4] Starting / restarting services..."
systemctl start antijam-gpio.service
systemctl restart svxlink.service

echo ""
echo "=== Installation complete ==="
echo ""
echo "Check service status:"
echo "  systemctl status svxlink.service"
echo "  systemctl status antijam-gpio.service"
echo ""
echo "Follow live logs:"
echo "  journalctl -f -u svxlink -u antijam-gpio"
