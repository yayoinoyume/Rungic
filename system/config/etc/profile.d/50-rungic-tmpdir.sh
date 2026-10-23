# Rungic: keep large temporary files on the rootfs disk. /tmp is a 2 GiB tmpfs
# (system/plasma.config) that shares the container's memory budget; builds and
# agent work directories must not exhaust it.
export TMPDIR=/var/tmp
