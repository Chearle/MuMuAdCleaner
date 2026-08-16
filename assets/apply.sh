#!/system/bin/sh
# SPDX-License-Identifier: MIT

. /data/local/tmp/mumu-adclean-common.sh

echo "==== apply $(date) ===="
hide_search
echo "engine=$(getprop nemud.player_engine)"
disable_widgets
clean_launcher_db

MOD=/data/adb/modules/mumu_adclean
mkdir -p "$MOD"
cp /data/local/tmp/mumu-adclean-common.sh "$MOD/common.sh"
cp /data/local/tmp/mumu-adclean-persist.sh "$MOD/service.sh"
chmod 755 "$MOD/common.sh" "$MOD/service.sh"
cat > "$MOD/module.prop" <<'EOF'
id=mumu_adclean
name=MuMu Desktop Ad Clean
version=v1.0.0
versionCode=1
author=Chearle
description=Hide MuMu search bar, Daily Discovery, and Tools folder ads
EOF

# Old installs used both module and service.d; keep a single boot path.
rm -f /data/adb/service.d/99-mumu-adclean.sh

restart_launcher
echo "DONE"
