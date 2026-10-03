#!/system/bin/sh
# fallback: bind-mount over the stock modules if magic mount did not apply
MODDIR=/data/adb/modules/lxc6_kernel_modules
for m in gspca_main rmnet_perf rmnet_shs; do
  SRC="$MODDIR/vendor/lib/modules/$m.ko"
  DST="/vendor/lib/modules/$m.ko"
  [ -f "$SRC" ] && [ -f "$DST" ] && mount -o bind "$SRC" "$DST" 2>/dev/null
done
