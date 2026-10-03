#!/system/bin/sh
# Rungic 开机自启与保活。由 Magisk service.d 在 late_start 执行。
# 只拉起进程，不检查前台、不抢焦点。
LOG=/data/local/tmp/rungic-autostart.log
(
echo "[$(date '+%Y-%m-%d %H:%M:%S')] rungic-autostart begin"

# 等待 Android 完成启动。
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 300 ]; do
    sleep 2
    i=$((i + 1))
done

# 等待共享存储就绪。
i=0
while [ ! -d /storage/emulated/0/Android ] && [ "$i" -lt 300 ]; do
    sleep 2
    i=$((i + 1))
done

am start -n com.rungic.plasma/.MainActivity >/dev/null 2>&1 || true

while true; do
    if ! pidof com.rungic.plasma >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] process missing; starting"
        am start -n com.rungic.plasma/.MainActivity >/dev/null 2>&1 || true
    fi
    sleep 30
done
) >>"$LOG" 2>&1 &
