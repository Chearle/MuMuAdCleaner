#!/system/bin/sh
# SPDX-License-Identifier: MIT

WIDGETS="
com.mumu.store/.widget.appWidgetProvider.AdBannerWidgetProvider
com.mumu.store/.widget.appWidgetProvider.DailyDiscoveryWidgetProvider
com.mumu.store/.widget.appWidgetProvider.HotActivityWidgetProvider
com.mumu.store/.widget.appWidgetProvider.FlashSaleWidgetProvider
com.mumu.store/.widget.receiver.WidgetOperateReceiver
"

FAV_SQL="DELETE FROM favorites WHERE title IN ('RE文件管理器','谷歌安装器','小工具') OR appWidgetProvider LIKE '%AdBannerWidgetProvider%' OR appWidgetProvider LIKE '%DailyDiscoveryWidgetProvider%' OR appWidgetProvider LIKE '%HotActivityWidgetProvider%' OR appWidgetProvider LIKE '%FlashSaleWidgetProvider%' OR intent LIKE '%com.speedsoftware.rootexplorer%' OR intent LIKE '%com.nemu.googleinstaller%';"

hide_search() {
  if [ -x /data/adb/ksu/bin/resetprop ]; then
    /data/adb/ksu/bin/resetprop nemud.player_engine WOAPRO
  elif command -v resetprop >/dev/null 2>&1; then
    resetprop nemud.player_engine WOAPRO
  else
    setprop nemud.player_engine WOAPRO
  fi
}

disable_widgets() {
  for c in $WIDGETS; do
    pm disable "$c" >/dev/null 2>&1 || true
  done
}

enable_widgets() {
  for c in $WIDGETS; do
    pm enable "$c" >/dev/null 2>&1 || true
  done
}

clean_launcher_db() {
  for db in /data/user/0/app.lawnchair/databases/launcher*.db; do
    [ -f "$db" ] || continue
    bak="${db}.adclean.bak"
    [ -f "$bak" ] || cp "$db" "$bak"
    sqlite3 "$db" "$FAV_SQL" >/dev/null 2>&1 || true
  done
}

restore_launcher_db() {
  for db in /data/user/0/app.lawnchair/databases/launcher*.db; do
    [ -f "$db" ] || continue
    bak="${db}.adclean.bak"
    [ -f "$bak" ] && cp "$bak" "$db"
  done
}

restart_launcher() {
  am force-stop app.lawnchair >/dev/null 2>&1 || true
  sleep 1
  input keyevent 3 >/dev/null 2>&1 || true
}
