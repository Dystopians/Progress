#!/usr/bin/env bash
# 经纬总闸门：分层检查 → 解析检查 → 全部测试。任一失败即整体失败。
set -uo pipefail
JW="C:/Users/Fiber Memory/Documents/Jingwei"
rc=0
echo "### 1/3 分层闸门"
python "$JW/tools/layer_check.py" || rc=1
echo "### 2/3 解析闸门"
bash "$JW/tools/check.sh" || rc=1
echo "### 3/3 测试闸门"
bash "$JW/tools/test.sh" "$@" || rc=1
echo ""
if [ "$rc" -eq 0 ]; then echo "总闸门：通过 ✓"; else echo "总闸门：未通过 ✗"; fi
exit "$rc"
