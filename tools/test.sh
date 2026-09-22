#!/usr/bin/env bash
# 经纬测试入口：先确保类缓存是最新的，再跑无界面测试。
# 用法：tools/test.sh [--suite=unit] [--filter=xxx] [--verbose]
set -uo pipefail
JW="C:/Users/Fiber Memory/Documents/Jingwei"
GODOT="C:/Users/Fiber Memory/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path "$JW" --import >/dev/null 2>&1
"$GODOT" --headless --path "$JW" --script "res://tests/run_tests.gd" -- "$@" 2>&1 | tr -d '\r'
exit "${PIPESTATUS[0]}"
