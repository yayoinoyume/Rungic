# SPDX-License-Identifier: MIT
"""The K40S systemd 255 reconciliation keeps its pin, payload checks and no-restart promise."""
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "munch-build-kit/rootfs-scripts/reconcile-systemd-255.sh"


def test_script_is_syntactically_valid():
    subprocess.run(["bash", "-n", str(SCRIPT)], check=True)


# covers: delivery.munch-systemd-255/E1
def test_pin_template_matches_the_running_systemd_255():
    text = SCRIPT.read_text()
    pin = re.search(r"cat > \"\$PIN_FILE\" <<'PIN'\n(.*?)\nPIN\n", text, re.S)
    assert pin, "pin heredoc is missing"
    body = pin.group(1)
    assert "Pin: version 255.4-1ubuntu8.17" in body
    assert "Pin: version 1.2-1ubuntu5.1+rungic255.1" in body
    assert body.count("Pin-Priority: 1001") == 3
    assert "Package: systemd systemd-sysv systemd-dev" in body
    assert "Package: netplan.io netplan-generator" in body


# covers: delivery.munch-systemd-255/E2
def test_check_and_rollback_are_available_without_restarting():
    text = SCRIPT.read_text()
    assert "--check" in text and "--dry-run" in text and "--rollback" in text
    for forbidden in ("systemctl restart", "systemctl reboot", "lxc-stop", "reboot"):
        assert forbidden not in text
    assert "refusing to touch a different runtime" in text
    assert re.search(r'--apply\)\s+MODE="apply"', text)
    assert re.search(r'^MODE="check"$', text, re.M)


# covers: delivery.munch-systemd-255/E3
def test_netplan_repack_verifies_the_payload_before_installing():
    text = SCRIPT.read_text()
    assert "list_tree" in text
    assert "repacked $name payload differs from the original" in text
    assert "s/systemd (>= 258~)/systemd (>= 255~)/g" in text
