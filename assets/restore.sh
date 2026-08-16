#!/system/bin/sh
# SPDX-License-Identifier: MIT

. /data/local/tmp/mumu-adclean-common.sh

echo "==== restore $(date) ===="
enable_widgets
restore_launcher_db
rm -rf /data/adb/modules/mumu_adclean
rm -f /data/adb/service.d/99-mumu-adclean.sh
restart_launcher
echo "DONE"
