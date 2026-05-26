#!/usr/bin/env bash
# 从 OUI-Master-Database 更新厂商识别数据
# https://github.com/Ringmast4r/OUI-Master-Database
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../Sources/Netra/Resources" && pwd)"
BASE="https://raw.githubusercontent.com/Ringmast4r/OUI-Master-Database/master/LISTS"
mkdir -p "$ROOT"
echo "Downloading master_oui.txt..."
curl -fsSL "$BASE/master_oui.txt" -o "$ROOT/master_oui.txt"
echo "Downloading kismet_manuf.txt..."
curl -fsSL "$BASE/kismet_manuf.txt" -o "$ROOT/kismet_manuf.txt"
echo "Done. Files in $ROOT"
