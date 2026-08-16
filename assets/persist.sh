#!/system/bin/sh
# SPDX-License-Identifier: MIT
# KernelSU late-start service. Keep this short: MuMu may rewrite nemud.* once.

MODDIR=${0%/*}
. "$MODDIR/common.sh"

until [ "$(getprop sys.boot_completed)" = "1" ]; do
  sleep 1
done

hide_search
disable_widgets
clean_launcher_db

i=0
while [ $i -lt 5 ]; do
  sleep 1
  hide_search
  i=$((i + 1))
done

restart_launcher
