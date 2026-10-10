# rungic-docker: rootless Docker for the desktop users (docs/85).
D=$SRC/system/docker
install -Dm644 "$D/docker.service" "$DESTDIR/usr/lib/systemd/user/docker.service"
install -Dm644 "$D/rungic-docker-prepare.service" "$DESTDIR/usr/lib/systemd/system/rungic-docker-prepare.service"
install -Dm755 "$D/dockerd-child" "$DESTDIR/usr/libexec/rungic-docker/dockerd-child"
install -Dm755 "$D/prepare" "$DESTDIR/usr/libexec/rungic-docker/prepare"
install -Dm644 "$D/environment.conf" "$DESTDIR/usr/lib/environment.d/60-rungic-docker.conf"
install -Dm644 "$D/profile.sh" "$DESTDIR/etc/profile.d/rungic-docker.sh"
# Default daemon settings (registry mirrors, log rotation) for a fresh install. Shipped as a
# conffile: an existing user copy under ~/.config/docker/daemon.json keeps dockerd's own
# precedence, and upgrades leave edited copies alone.
install -Dm644 "$D/daemon.json" "$DESTDIR/etc/docker/daemon.json"
