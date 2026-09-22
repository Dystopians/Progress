#!/usr/bin/env python3
"""货币刻度迁移：1 U = 1e6 μU  →  1 U = 1e9 μU（裁定 R-SCALE-01）。

动机（实测，非推测）：
  基年季度名义 GDP = 25 000 000 μU，就业约 920 万人
  ⇒ 人均季度劳动报酬约 1.4 μU，工资只能取 {1,2,3}，技能溢价被迫 100%/50%；
  住房约 793 万套，租金合法下限 1 μU/套/季 已等于季度 GDP 的约 32%；
  ±2%~±3% 的有界平滑对 1..3 的整数永远算出 0，工资与租金在整局内被冻结。
整数刻度在「每人 / 每套」这一层塌掉了。把 μU 细化 1000 倍即可同时解决三处。

迁移规则（只做这两件事，别的一律不动）：
  1. 键名中含 `uu` 词元（正则 `(^|_)uu(_|$)`）的字段 → 其**整个子树**内的所有整数 ×1000。
  2. 参数身份证（含 parameter_id 与 unit 的对象）中 unit 以 `μU` 开头的 → value 与 valid_range ×1000。
`_uqs` / `_ppm` / `_persons` / `_units` / `_q` / `_count` 一律不动（它们与货币刻度无关）。

用法：
  python tools/migrate_currency_scale.py --dry-run     # 只报告，不写盘
  python tools/migrate_currency_scale.py --apply       # 写盘
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content"
FACTOR = 1000

UU_KEY = re.compile(r"(?:^|_)uu(?:_|$)")
LONG_NUMBER_IN_TEXT = re.compile(r"\d[\d\s_,]{5,}")

stats: Counter[str] = Counter()
samples: list[str] = []
text_hits: list[str] = []


def is_money_unit(unit: object) -> bool:
    return isinstance(unit, str) and unit.startswith("μU")


def scale_subtree(node: object, path: str, depth: int = 0) -> object:
    """把子树内的所有整数 ×FACTOR。布尔值不是数（Python 里 bool 是 int 的子类，必须先排除）。"""
    if isinstance(node, bool):
        return node
    if isinstance(node, int):
        stats["scaled_numbers"] += 1
        if len(samples) < 25:
            samples.append(f"    {path}: {node} -> {node * FACTOR}")
        return node * FACTOR
    if isinstance(node, float):
        stats["float_encountered"] += 1
        samples.append(f"  !! 浮点值（协议禁止）{path}: {node}")
        return node
    if isinstance(node, dict):
        return {k: scale_subtree(v, f"{path}/{k}", depth + 1) for k, v in node.items()}
    if isinstance(node, list):
        return [scale_subtree(v, f"{path}[{i}]", depth + 1) for i, v in enumerate(node)]
    if isinstance(node, str):
        if LONG_NUMBER_IN_TEXT.search(node) and len(text_hits) < 200:
            text_hits.append(f"    {path}: {node[:110]}")
        return node
    return node


def walk(node: object, path: str) -> object:
    """顶层遍历：遇到 uu 键就整棵子树缩放；参数卡按 unit 判定。"""
    if isinstance(node, dict):
        is_card = "parameter_id" in node and "unit" in node
        card_is_money = is_card and is_money_unit(node.get("unit"))
        if card_is_money:
            stats["money_param_cards"] += 1
        out: dict[str, object] = {}
        for k, v in node.items():
            if UU_KEY.search(k):
                stats["uu_keys"] += 1
                out[k] = scale_subtree(v, f"{path}/{k}")
            elif card_is_money and k in ("value", "valid_range", "default", "typical_value"):
                out[k] = scale_subtree(v, f"{path}/{k}")
            else:
                out[k] = walk(v, f"{path}/{k}")
        return out
    if isinstance(node, list):
        return [walk(v, f"{path}[{i}]") for i, v in enumerate(node)]
    if isinstance(node, str):
        if LONG_NUMBER_IN_TEXT.search(node) and len(text_hits) < 200:
            text_hits.append(f"    {path}: {node[:110]}")
    return node


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    if not args.apply and not args.dry_run:
        print("必须指定 --dry-run 或 --apply")
        return 2

    files = sorted(CONTENT.rglob("*.json"))
    print(f"内容文件 {len(files)} 个，缩放因子 ×{FACTOR}\n")
    per_file: list[tuple[str, int]] = []

    for path in files:
        before = stats["scaled_numbers"]
        raw = io.open(path, encoding="utf-8").read()
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as exc:
            print(f"  !! JSON 解析失败 {path.relative_to(ROOT).as_posix()}: {exc}")
            stats["parse_errors"] += 1
            continue
        out = walk(data, path.stem)
        changed = stats["scaled_numbers"] - before
        per_file.append((path.relative_to(ROOT).as_posix(), changed))
        if args.apply and changed:
            io.open(path, "w", encoding="utf-8", newline="\n").write(
                json.dumps(out, ensure_ascii=False, indent=2) + "\n"
            )

    print("按文件缩放的数字个数：")
    for name, n in per_file:
        if n:
            print(f"  {n:6d}  {name}")
    zero = [n for n, c in per_file if c == 0]
    if zero:
        print(f"  （{len(zero)} 个文件无货币字段：{', '.join(Path(z).name for z in zero[:8])}{' …' if len(zero) > 8 else ''}）")

    print("\n样本（前 25 处）：")
    for s in samples[:25]:
        print(s)

    print(f"\n统计：uu 键 {stats['uu_keys']} 个 ｜ 货币参数卡 {stats['money_param_cards']} 张 "
          f"｜ 缩放数字 {stats['scaled_numbers']} 个 ｜ 浮点 {stats['float_encountered']} 个 "
          f"｜ 解析失败 {stats['parse_errors']} 个")

    if text_hits:
        print(f"\n⚠ 文本字符串里出现的长数字 {len(text_hits)} 处（迁移器不动字符串，需人工/后续智能体同步）：")
        for t in text_hits[:30]:
            print(t)
        if len(text_hits) > 30:
            print(f"    …… 另有 {len(text_hits) - 30} 处")

    print("\n" + ("已写盘（--apply）" if args.apply else "未写盘（--dry-run）"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
