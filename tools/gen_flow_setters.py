#!/usr/bin/env python3
"""为每个状态块生成 set_flow_array / set_flow_scalar（与 flow_array / flow_scalar 逐项对称）。

背景（R-SAVE-01）：骨架契约遗漏了流量的写回方法，24 个模块无一实现；JWSimState 读档时
「块没有 set_flow_array() → 不写，由读回比对判 SAVE_CORRUPT」。于是任何一季之后的存档都读不回来，
即使读回，下一季 S01 用上季流量更新需求预期时读到的也全是 0，存档续跑与直跑必然分叉（INV-133）。

本工具只做机械对称：解析 flow_array(i) / flow_scalar(i) 中「下标 → 直接 return 某成员」的映射
（支持 `if i == N:` 与 `match i:` 两种写法），生成等价的写回方法。遇到非「直接返回成员」的分支就报告并跳过，
绝不猜测。已存在写回方法的文件不动。

用法：
  python tools/gen_flow_setters.py --dry-run [文件...]
  python tools/gen_flow_setters.py --apply [文件...]
不给文件时处理 sim/ 与 systems/ 下全部含 flow_array 的文件；--exclude 可排除若干文件。
"""

from __future__ import annotations

import argparse
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

IF_CASE = re.compile(r"^\tif i == (\d+):\n\t\treturn ([A-Za-z_][A-Za-z0-9_]*)\s*$", re.M)
MATCH_CASE = re.compile(r"^\t\t(\d+):\n\t\t\treturn ([A-Za-z_][A-Za-z0-9_]*)\s*$", re.M)


def func_body(src: str, name: str) -> str | None:
    m = re.search(rf"^func {name}\(i: int\)[^\n]*:\n", src, re.M)
    if not m:
        return None
    start = m.end()
    nxt = re.search(r"^(func |## |static func |var |const |@)", src[start:], re.M)
    end = start + nxt.start() if nxt else len(src)
    return src[start:end]


def cases(body: str) -> list[tuple[int, str]]:
    out = [(int(a), b) for a, b in IF_CASE.findall(body)]
    out += [(int(a), b) for a, b in MATCH_CASE.findall(body)]
    return sorted(set(out))


def gen_array_setter(cs: list[tuple[int, str]]) -> str:
    lines = [
        "",
        "",
        "## §1.6 状态块协议：读档时写回流量数组（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_array 逐项对称生成）。",
        "## 步骤：LOAD（JWSaves 经 JWSimState 调用）",
        "## 前置：v 的长度与本块当前分配的长度一致（长度是 schema 的一部分，INV-136）",
        "## 后置：对应成员被整体替换",
        "## 不变量：INV-133（读档后与原进程逐位相同）",
        "## 失败：下标越界或长度不符 → INDEX_OUT_OF_RANGE",
        "func set_flow_array(i: int, v: PackedInt64Array) -> int:",
    ]
    for idx, member in cs:
        lines += [
            f"\tif i == {idx}:",
            f"\t\tif v.size() != {member}.size():",
            f"\t\t\treturn JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())",
            f"\t\t{member} = v.duplicate()",
            "\t\treturn JWResult.OK",
        ]
    lines += ["\treturn JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())", ""]
    return "\n".join(lines)


def gen_scalar_setter(cs: list[tuple[int, str]]) -> str:
    lines = [
        "",
        "",
        "## §1.6 状态块协议：读档时写回流量标量（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_scalar 逐项对称生成）。",
        "## 步骤：LOAD",
        "## 前置：无",
        "## 后置：对应成员被赋值",
        "## 不变量：INV-133",
        "## 失败：下标越界 → INDEX_OUT_OF_RANGE",
        "func set_flow_scalar(i: int, v: int) -> int:",
    ]
    for idx, member in cs:
        lines += [f"\tif i == {idx}:", f"\t\t{member} = v", "\t\treturn JWResult.OK"]
    lines += ["\treturn JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())", ""]
    return "\n".join(lines)


def expected_count(src: str, const: str) -> int:
    m = re.search(rf"const {const}: PackedStringArray = \[(.*?)\]", src, re.S)
    return len(re.findall(r'"[^"]+"', m.group(1))) if m else 0


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--exclude", nargs="*", default=[])
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()
    if a.files:
        files = [ROOT / f for f in a.files]
    else:
        files = sorted(p for d in ("sim", "systems") for p in (ROOT / d).rglob("*.gd"))
    excl = {str((ROOT / e).resolve()) for e in a.exclude}
    rc = 0
    for f in files:
        if str(f.resolve()) in excl:
            continue
        src = io.open(f, encoding="utf-8").read()
        rel = f.relative_to(ROOT).as_posix()
        add = ""
        for getter, setter, const, gen in (
            ("flow_array", "set_flow_array", "FLOW_ARRAY_IDS", gen_array_setter),
            ("flow_scalar", "set_flow_scalar", "FLOW_SCALAR_IDS", gen_scalar_setter),
        ):
            body = func_body(src, getter)
            if body is None or re.search(rf"^func {setter}\(", src, re.M):
                continue
            want = expected_count(src, const)
            if want == 0:
                continue
            cs = cases(body)
            if len(cs) != want:
                print(f"  ! {rel}: {getter} 解析出 {len(cs)} 项，{const} 登记 {want} 项——不一致，跳过（需人工处理）")
                rc = 1
                continue
            add += gen(cs)
            print(f"  + {rel}: 生成 {setter}（{len(cs)} 项）")
        if add and a.apply:
            io.open(f, "w", encoding="utf-8", newline="\n").write(src.rstrip("\n") + "\n" + add)
    print("已写盘" if a.apply else "未写盘（--dry-run）")
    return rc


if __name__ == "__main__":
    sys.exit(main())
