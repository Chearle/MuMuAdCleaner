#!/system/bin/sh
# SPDX-License-Identifier: MIT

. /data/local/tmp/mumu-adclean-common.sh

echo "==== restore $(date) ===="
stop_launcher
enable_widgets
restore_launcher_db
restore_search
echo "engine=$(getprop nemud.player_engine)"
rm -rf /data/adb/modules/mumu_adclean
rm -rf /data/local/tmp/mumu-adclean-state
rm -f /data/adb/service.d/99-mumu-adclean.sh
restart_launcher
echo "DONE"
