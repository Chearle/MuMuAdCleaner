#!/system/bin/sh
# SPDX-License-Identifier: MIT
# Restore MuMu desktop ads. Must run as root.

echo "==== restore $(date) ===="

enable_one() {
  comp="$1"
  if pm enable "$comp" >/dev/null 2>&1; then
    echo "enabled $comp"
  else
    echo "skip $comp"
  fi
}

enable_one "com.mumu.store/.widget.appWidgetProvider.AdBannerWidgetProvider"
enable_one "com.mumu.store/.widget.appWidgetProvider.DailyDiscoveryWidgetProvider"
enable_one "com.mumu.store/.widget.appWidgetProvider.HotActivityWidgetProvider"
enable_one "com.mumu.store/.widget.appWidgetProvider.FlashSaleWidgetProvider"
enable_one "com.mumu.store/.widget.receiver.WidgetOperateReceiver"

for db in /data/user/0/app.lawnchair/databases/launcher*.db /data/data/app.lawnchair/databases/launcher*.db; do
  [ -f "$db" ] || continue
  bak="${db}.adclean.bak"
  if [ -f "$bak" ]; then
    cp "$bak" "$db"
    echo "restored $db"
  fi
done

rm -rf /data/adb/modules/mumu_adclean
rm -f /data/adb/service.d/99-mumu-adclean.sh
echo "removed persist scripts"

am force-stop app.lawnchair >/dev/null 2>&1 || true
sleep 1
input keyevent 3 >/dev/null 2>&1 || true
echo "DONE"
