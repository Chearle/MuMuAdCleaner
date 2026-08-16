#!/system/bin/sh
# SPDX-License-Identifier: MIT
# Remove MuMu desktop ads. Must run as root.

echo "==== apply $(date) ===="

FAV_SQL="DELETE FROM favorites WHERE title IN ('RE文件管理器','谷歌安装器','小工具') OR appWidgetProvider LIKE '%AdBannerWidgetProvider%' OR appWidgetProvider LIKE '%DailyDiscoveryWidgetProvider%' OR appWidgetProvider LIKE '%HotActivityWidgetProvider%' OR appWidgetProvider LIKE '%FlashSaleWidgetProvider%' OR intent LIKE '%com.speedsoftware.rootexplorer%' OR intent LIKE '%com.nemu.googleinstaller%';"

hide_search() {
  if [ -x /data/adb/ksu/bin/resetprop ]; then
    /data/adb/ksu/bin/resetprop nemud.player_engine WOAPRO
    echo "resetprop ksu: nemud.player_engine=WOAPRO"
  elif command -v resetprop >/dev/null 2>&1; then
    resetprop nemud.player_engine WOAPRO
    echo "resetprop: nemud.player_engine=WOAPRO"
  else
    setprop nemud.player_engine WOAPRO
    echo "setprop: nemud.player_engine=WOAPRO"
  fi
}

disable_one() {
  comp="$1"
  if pm disable "$comp" >/dev/null 2>&1; then
    echo "disabled $comp"
  elif pm disable-user --user 0 "$comp" >/dev/null 2>&1; then
    echo "disabled-user $comp"
  else
    echo "skip $comp"
  fi
}

clean_db() {
  db="$1"
  [ -f "$db" ] || return 0
  bak="${db}.adclean.bak"
  if [ ! -f "$bak" ]; then
    cp "$db" "$bak"
    echo "backup $db"
  fi
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$db" "$FAV_SQL"
    echo "cleaned $db"
  else
    echo "sqlite3 missing, skip $db"
  fi
}

hide_search

disable_one "com.mumu.store/.widget.appWidgetProvider.AdBannerWidgetProvider"
disable_one "com.mumu.store/.widget.appWidgetProvider.DailyDiscoveryWidgetProvider"
disable_one "com.mumu.store/.widget.appWidgetProvider.HotActivityWidgetProvider"
disable_one "com.mumu.store/.widget.appWidgetProvider.FlashSaleWidgetProvider"
disable_one "com.mumu.store/.widget.receiver.WidgetOperateReceiver"

for db in /data/user/0/app.lawnchair/databases/launcher*.db /data/data/app.lawnchair/databases/launcher*.db; do
  clean_db "$db"
done

MOD=/data/adb/modules/mumu_adclean
mkdir -p "$MOD"
cat > "$MOD/module.prop" <<'EOF'
id=mumu_adclean
name=MuMu Desktop Ad Clean
version=v1.2
versionCode=3
author=Chearle
description=Hide MuMu search bar, Daily Discovery, and Tools folder ads
EOF

cat > "$MOD/service.sh" <<EOF
#!/system/bin/sh
until [ "\$(getprop sys.boot_completed)" = "1" ]; do
  sleep 2
done
sleep 4
i=0
while [ \$i -lt 15 ]; do
  if [ -x /data/adb/ksu/bin/resetprop ]; then
    /data/adb/ksu/bin/resetprop nemud.player_engine WOAPRO
  else
    setprop nemud.player_engine WOAPRO
  fi
  i=\$((i+1))
  sleep 2
done
for c in \\
  com.mumu.store/.widget.appWidgetProvider.AdBannerWidgetProvider \\
  com.mumu.store/.widget.appWidgetProvider.DailyDiscoveryWidgetProvider \\
  com.mumu.store/.widget.appWidgetProvider.HotActivityWidgetProvider \\
  com.mumu.store/.widget.appWidgetProvider.FlashSaleWidgetProvider \\
  com.mumu.store/.widget.receiver.WidgetOperateReceiver
do
  pm disable "\$c" >/dev/null 2>&1 || true
done
for db in /data/user/0/app.lawnchair/databases/launcher*.db /data/data/app.lawnchair/databases/launcher*.db; do
  [ -f "\$db" ] || continue
  sqlite3 "\$db" "$FAV_SQL" >/dev/null 2>&1 || true
done
am force-stop app.lawnchair >/dev/null 2>&1 || true
sleep 1
input keyevent 3 >/dev/null 2>&1 || true
EOF
chmod 755 "$MOD/service.sh"
echo "installed module $MOD"

mkdir -p /data/adb/service.d
cp "$MOD/service.sh" /data/adb/service.d/99-mumu-adclean.sh
chmod 755 /data/adb/service.d/99-mumu-adclean.sh
echo "installed service.d script"

am force-stop app.lawnchair >/dev/null 2>&1 || true
sleep 1
input keyevent 3 >/dev/null 2>&1 || true
echo "launcher restarted"
echo "DONE"
