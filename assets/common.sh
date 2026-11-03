#!/system/bin/sh
# SPDX-License-Identifier: MIT

STATE_DIR=/data/adb/modules/mumu_adclean
ENGINE_PROP=nemud.player_engine

WIDGETS="
com.mumu.store/.widget.appWidgetProvider.AdBannerWidgetProvider
com.mumu.store/.widget.appWidgetProvider.DailyDiscoveryWidgetProvider
com.mumu.store/.widget.appWidgetProvider.HotActivityWidgetProvider
com.mumu.store/.widget.appWidgetProvider.FlashSaleWidgetProvider
com.mumu.store/.widget.receiver.WidgetOperateReceiver
"

FAV_SQL="DELETE FROM favorites WHERE title IN ('RE文件管理器','谷歌安装器','小工具') OR appWidgetProvider LIKE '%AdBannerWidgetProvider%' OR appWidgetProvider LIKE '%DailyDiscoveryWidgetProvider%' OR appWidgetProvider LIKE '%HotActivityWidgetProvider%' OR appWidgetProvider LIKE '%FlashSaleWidgetProvider%' OR intent LIKE '%com.speedsoftware.rootexplorer%' OR intent LIKE '%com.nemu.googleinstaller%';"

set_engine_prop() {
  value="$1"
  if [ -x /data/adb/ksu/bin/resetprop ]; then
    /data/adb/ksu/bin/resetprop "$ENGINE_PROP" "$value"
  elif command -v resetprop >/dev/null 2>&1; then
    resetprop "$ENGINE_PROP" "$value"
  else
    setprop "$ENGINE_PROP" "$value"
  fi
}

save_original_engine() {
  target_dir="$1"
  mkdir -p "$target_dir" || return 1
  [ -f "$target_dir/original_engine" ] && return 0

  if [ "$target_dir" != "$STATE_DIR" ] && [ -f "$STATE_DIR/original_engine" ]; then
    cp "$STATE_DIR/original_engine" "$target_dir/original_engine" && return 0
  fi
  getprop "$ENGINE_PROP" > "$target_dir/original_engine" || return 1
}

find_engine_backup() {
  if [ -f "$STATE_DIR/original_engine" ]; then
    echo "$STATE_DIR/original_engine"
  elif [ -f /data/local/tmp/mumu-adclean-state/original_engine ]; then
    echo /data/local/tmp/mumu-adclean-state/original_engine
  fi
}

hide_search() {
  set_engine_prop WOAPRO
}

restore_search() {
  backup="$(find_engine_backup)"
  [ -n "$backup" ] || return 0
  value="$(cat "$backup")"
  if [ -z "$value" ]; then
    if [ -x /data/adb/ksu/bin/resetprop ]; then
      /data/adb/ksu/bin/resetprop --delete "$ENGINE_PROP"
    elif command -v resetprop >/dev/null 2>&1; then
      resetprop --delete "$ENGINE_PROP"
    else
      setprop "$ENGINE_PROP" ""
    fi
  else
    set_engine_prop "$value"
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

stop_launcher() {
  am force-stop app.lawnchair >/dev/null 2>&1 || true
  sleep 1
}

backup_launcher_db() {
  db="$1"
  bak="${db}.adclean.bak"
  [ -f "$bak" ] && return 0

  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "$db" ".timeout 3000" ".backup '$bak'" >/dev/null 2>&1 && return 0
  fi
  cp "$db" "$bak"
}

clean_launcher_db() {
  for db in /data/user/0/app.lawnchair/databases/launcher*.db; do
    [ -f "$db" ] || continue
    bak="${db}.adclean.bak"
    if ! backup_launcher_db "$db"; then
      echo "WARN: cannot back up $db"
      continue
    fi
    if command -v sqlite3 >/dev/null 2>&1; then
      sqlite3 "$db" ".timeout 3000" "$FAV_SQL" >/dev/null 2>&1 \
        || echo "WARN: cannot clean $db"
    else
      echo "WARN: sqlite3 is unavailable; launcher database was not changed"
    fi
  done
}

restore_launcher_db() {
  for db in /data/user/0/app.lawnchair/databases/launcher*.db; do
    [ -f "$db" ] || continue
    bak="${db}.adclean.bak"
    [ -f "$bak" ] || continue

    if command -v sqlite3 >/dev/null 2>&1; then
      sqlite3 "$bak" ".timeout 3000" ".backup '$db'" >/dev/null 2>&1 \
        || cp "$bak" "$db"
    else
      cp "$bak" "$db"
    fi
    rm -f "${db}-wal" "${db}-shm"
  done
}

restart_launcher() {
  stop_launcher
  sleep 1
  input keyevent 3 >/dev/null 2>&1 || true
}
