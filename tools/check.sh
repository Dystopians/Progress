#!/usr/bin/env bash
# 解析闸门：所有 .gd 必须可解析。
set -uo pipefail
JW="C:/Users/Fiber Memory/Documents/Jingwei"
GODOT="C:/Users/Fiber Memory/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path "$JW" --import >/dev/null 2>&1
"$GODOT" --headless --path "$JW" --script "res://tools/parse_check.gd" 2>&1 | tr -d '\r'
exit "${PIPESTATUS[0]}"
