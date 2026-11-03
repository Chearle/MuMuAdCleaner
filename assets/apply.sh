#!/system/bin/sh
# SPDX-License-Identifier: MIT

. /data/local/tmp/mumu-adclean-common.sh

MODE=persistent
if [ "$1" = "--transient" ]; then
  MODE=transient
fi

echo "==== apply $(date) mode=$MODE ===="
if [ "$MODE" = "transient" ]; then
  APPLY_STATE=/data/local/tmp/mumu-adclean-state
else
  APPLY_STATE="$STATE_DIR"
  mkdir -p /data/local/tmp/mumu-adclean-state
fi
save_original_engine "$APPLY_STATE" || echo "WARN: cannot remember the original engine property"
if [ "$MODE" = "transient" ] && [ -f "$STATE_DIR/original_engine" ]; then
  cp "$STATE_DIR/original_engine" "$APPLY_STATE/original_engine"
fi
hide_search
echo "engine=$(getprop nemud.player_engine)"
stop_launcher
disable_widgets
clean_launcher_db

MOD="$STATE_DIR"
if [ "$MODE" = "persistent" ]; then
  mkdir -p "$MOD"
  cp /data/local/tmp/mumu-adclean-common.sh "$MOD/common.sh"
  cp /data/local/tmp/mumu-adclean-persist.sh "$MOD/service.sh"
  chmod 755 "$MOD/common.sh" "$MOD/service.sh"
  cat > "$MOD/module.prop" <<'EOF'
id=mumu_adclean
name=MuMu Desktop Ad Clean
version=v1.1.0
versionCode=2
author=Chearle
description=Hide MuMu search bar, Daily Discovery, and Tools folder ads
EOF
else
  rm -rf "$MOD"
fi

# Old installs used both module and service.d; keep a single boot path.
rm -f /data/adb/service.d/99-mumu-adclean.sh

restart_launcher
echo "DONE mode=$MODE"
