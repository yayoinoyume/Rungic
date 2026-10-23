# SPDX-License-Identifier: MIT
"""Container /tmp stays bounded and temporary files default to the rootfs disk."""
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "system/plasma.config"
PROFILE = ROOT / "system/config/etc/profile.d/50-rungic-tmpdir.sh"
SYSTEM_CONF = ROOT / "system/config/etc/systemd/system.conf.d/50-rungic-tmpdir.conf"
USER_CONF = ROOT / "system/config/etc/systemd/user.conf.d/50-rungic-tmpdir.conf"


def tmp_mount_options():
    for line in CONFIG.read_text().splitlines():
        if line.startswith("lxc.mount.entry = tmpfs tmp tmpfs"):
            return line.split()[5].split(",")
    raise AssertionError("no /tmp mount entry in system/plasma.config")


# covers: install.container-tmp/E1
def test_tmp_tmpfs_is_capped_and_keeps_expected_flags():
    options = tmp_mount_options()
    assert "size=2G" in options
    assert "mode=1777" in options
    assert "nosuid" in options
    assert "nodev" in options


# covers: install.container-tmp/E1
def test_login_shells_keep_temporary_files_on_disk():
    assert "export TMPDIR=/var/tmp" in PROFILE.read_text()


# covers: install.container-tmp/E1
@pytest.mark.parametrize("path", [SYSTEM_CONF, USER_CONF])
def test_systemd_managers_default_tmpdir_to_disk(path):
    text = path.read_text()
    assert "[Manager]" in text
    assert "DefaultEnvironment=TMPDIR=/var/tmp" in text
