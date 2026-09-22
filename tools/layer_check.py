#!/usr/bin/env python3
"""分层闸门：机器检查计划书 §12 规定的四层禁止事项。

用法：python tools/layer_check.py
退出码：0 无违规；1 存在违规。

本工具是纯静态文本检查，属于计划书允许的「Python 只用于离线分析」，不含任何模拟逻辑。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# 每条规则：(层目录, 正则, 说明, 允许的例外文件名后缀)
RULES: list[tuple[str, str, str, tuple[str, ...]]] = [
    # SimCore 不得依赖场景树、UI 节点和叙事文案
    ("sim", r"\bextends\s+(Node|Control|CanvasItem|Node2D|Node3D)\b",
     "SimCore 不得继承场景树节点（计划书 §12）", ()),
    ("sim", r"\bget_tree\s*\(", "SimCore 不得访问场景树（计划书 §12）", ()),
    ("sim", r"\bSceneTree\b", "SimCore 不得引用 SceneTree（计划书 §12）", ()),
    ("sim", r"\b(Control|Button|Label|VBoxContainer|HBoxContainer|RichTextLabel|GridContainer)\b",
     "SimCore 不得引用 UI 节点类型（计划书 §12）", ()),
    ("sim", r"\bpreload\s*\(\s*\"res://ui/", "SimCore 不得预载 UI 资源（计划书 §12）", ()),

    # SimCore 内禁止 float 影响状态（本项目锁定的整数定点算术）
    ("sim", r":\s*float\b", "SimCore 内禁止 float 类型（整数定点算术契约）", ()),
    ("sim", r"\bfloat\s*\(", "SimCore 内禁止 float() 转换（整数定点算术契约）", ()),
    ("sim", r"\b(randf|randf_range|randfn)\s*\(", "SimCore 内禁止浮点随机（确定性重放契约）", ()),
    ("sim", r"(?<![\w.])\d+\.\d+(?![\w])", "SimCore 内禁止浮点字面量（整数定点算术契约）", ()),

    # Presentation 不得直接修改状态
    ("ui", r"\bSimState\b.*=", "界面层不得直接写入 SimState（计划书 §12）", ()),
    ("ui", r"\bLedger\b\s*\.\s*(post|transfer|credit|debit)\s*\(",
     "界面层不得直接记账（计划书 §12）", ()),
]

# 注释与文档字符串不参与检查：先剥掉行内注释。
COMMENT = re.compile(r"(?<!\")#.*$")


def strip_comments(line: str) -> str:
    return COMMENT.sub("", line)


def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except (AttributeError, OSError):
        pass
    violations: list[str] = []
    checked = 0
    for layer, pattern, reason, exempt in RULES:
        base = ROOT / layer
        if not base.is_dir():
            continue
        rx = re.compile(pattern)
        for path in sorted(base.rglob("*.gd")):
            if path.name.endswith(exempt) if exempt else False:
                continue
            checked += 1
            try:
                text = path.read_text(encoding="utf-8")
            except OSError as exc:
                violations.append(f"{path}: 无法读取 —— {exc}")
                continue
            for lineno, raw in enumerate(text.splitlines(), start=1):
                line = strip_comments(raw)
                if not line.strip() or line.lstrip().startswith("##"):
                    continue
                if rx.search(line):
                    rel = path.relative_to(ROOT).as_posix()
                    violations.append(f"  ✗ {rel}:{lineno}  {reason}\n      {raw.strip()}")

    print("")
    print("──────────── 分层闸门 ────────────")
    if violations:
        print(f"违规 {len(violations)} 处：")
        for v in violations:
            print(v)
    else:
        print("无违规。")
    print("──────────────────────────────────")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
