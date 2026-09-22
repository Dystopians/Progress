#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""参数登记表生成器（离线分析工具，不含任何模拟逻辑）

对应：
  计划书 §14「每个参数都带一张身份证」「本版本的证据状态」
  docs/11_data_contract.md §5.15 `ParameterCard`、§7 错误码表、V-PC-01..V-PC-07
  docs/10_variable_dictionary.md §0.1 记数单位、§0.2 字段后缀、§0.9 整数算术三条铁律
  docs/12_simulation_contract.md（只读引用，不实现）

职责边界（计划书 §12「Python 只用于离线分析，不维护第二套重复的模拟核心」）：
  本工具只做「读 JSON → 抽卡 → 查 → 出报表」。它不结算、不写状态、不改内容文件、
  不为任何缺字段补默认值。发现问题时**报告**，绝不**修正**。

输入：<project>/content/ 下全部 *.json（递归）
输出：
  <project>/content/parameters/registry.json   机读汇总（整数，严格无浮点）
  <project>/docs/14_parameter_registry.md      人读报告，顶部为「证据状态」仪表盘

退出码：0 = 无 ERROR；1 = 存在 ERROR；2 = 工具自身无法运行（路径缺失等）。
  --warn-as-error 时 WARN 也计入退出码 1。

用法（Windows）：
  py -3.12 "C:/Users/Fiber Memory/Documents/Jingwei/tools/build_param_registry.py"
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import unicodedata
from collections import Counter, OrderedDict
from typing import Any

TOOL_VERSION = 1
SCHEMA_KIND = "parameter_registry"
SCHEMA_VERSION = 1

# ---------------------------------------------------------------------------
# 0  契约常量（全部可回指文档条款；本工具不自造规则）
# ---------------------------------------------------------------------------

# 11_data_contract.md §5.15 字段表：九项必填
REQUIRED_FIELDS: tuple[str, ...] = (
    "parameter_id",
    "value",
    "unit",
    "source_type",
    "source_ref",
    "reference_year",
    "definition",
    "valid_range",
    "confidence",
    "calibration_note",
)
# 注：上表列出十个键名，但计划书 §14 的「身份证」把 parameter_id 视作卡片的标识而非字段之一，
#     契约 V-PC-01 写「九字段齐全」。两处口径差一个 parameter_id，本工具一律按十个键全查，
#     缺 parameter_id 与缺 value 同等严重。差异登记为 OQ（见返回值）。

# §5.15：只能是这四者
SOURCE_TYPES: tuple[str, ...] = ("observed", "literature", "design_assumption", "derived")

# §5.15：low / medium / high
CONFIDENCE_LEVELS: tuple[str, ...] = ("low", "medium", "high")

# §5.15 可选键（契约正文出现过、但不在九字段表内）
OPTIONAL_FIELDS: tuple[str, ...] = ("derivation_expr",)

# 11 号文件 §4：param_id = ^param\.[a-z][a-z0-9_]*$
RE_PARAM_ID = re.compile(r"^param\.[a-z][a-z0-9_]*$")

# 11 号文件 §3：整数绝对值 ≤ 2^53（JSON 互操作安全区）
INT_SAFE_MAX = 2 ** 53

# --- 单位允许集合 ---------------------------------------------------------
# A 层：10 号文件 §0.1「记数单位（唯一定义，任何地方不得另立）」+ §5.15 允许的 dimensionless
UNITS_CORE: tuple[str, ...] = (
    "U", "μU", "Q_s", "μQ_s", "μU/Q_s", "μQ_s/季",
    "ppm", "persons", "units", "q", "dimensionless",
)
# B 层：11 号文件 §5.15 自己的「首版必备参数最小集」表里实际使用、但 §0.1 未列的写法。
#       它们是契约正文的既成事实，工具接受但单独标注，见 PR-018 的拼写冲突告警。
UNITS_CONTRACT_EXTRA: tuple[str, ...] = (
    "季",          # §5.15 用「季」，§0.1 用 `q`：同一概念两种拼写
    "人/套",       # param.persons_per_housing_unit
    "μU/人/季",    # param.wage_floor_uu / wage_ceil_uu
    "次", "行", "批", "人",
    "int64",       # param.rng_salt[6]
)
# C 层：部门特化的 μQ_s 族（§0.1「每部门各有自己的 Q_s」）与其「每季」派生形式。
RE_UNIT_SECTOR_QTY = re.compile(r"^μQ_(agri|manu|energy|services|s|e)(/季)?$")
RE_UNIT_PER_QUARTER = re.compile(r"^(μU|ppm|persons|units)/季$")
RE_UNIT_PER_THING_Q = re.compile(r"^μU/(units|人|persons|套)/季$")

# 同一概念的不同拼写：报 PR-018，提醒契约收敛到一种写法
UNIT_SPELLING_COLLISIONS: tuple[tuple[str, str], ...] = (
    ("q", "季"),
    ("persons", "人"),
)

# 10 号文件 §0.2 字段后缀 → 期望单位（交叉校验，只报 WARN）。
# 规则**有序**，首个匹配者生效：`..._uu_per_q` 的语义后缀是「每季的金额」而不是「季度索引」，
# 必须先于裸 `_q` 规则匹配，否则会把正确的 `μU/季` 误报成错。
#
# `_per_q` 不在这张表里：内容包中「每季金额」同时存在 `μU` 与 `μU/季` 两种写法，
# 而两份契约都没有裁定哪种为准（§5.1 只说 `_uu` = 金额）。逐卡报错会把一个**待裁定的约定分歧**
# 伪装成 14 个各自独立的缺陷。它改由 PR-025 在语料层面报告一次，附双方计数。
SUFFIX_UNIT_RULES: tuple[tuple[re.Pattern, str, Any], ...] = (
    (re.compile(r"_ppm$"), "ppm", lambda u: u == "ppm"),
    (re.compile(r"_persons$"), "persons 或 人", lambda u: u in ("persons", "人")),
    (re.compile(r"_units$"), "units", lambda u: u == "units"),
    (re.compile(r"_uu$"), "μU 或其派生", lambda u: u.startswith("μU")),
    (re.compile(r"_uqs(_per_q)?$"), "μQ_<部门> 或其派生", lambda u: u.startswith("μQ")),
    # 裸 `_q` = 季度索引。`_per_q` 系列已在上面的注释中说明由 PR-025 处理，此处必须排除，
    # 否则 `..._uu_per_q` 会被误当成季度索引而报「单位应为 q」。
    (re.compile(r"(?<!_per)(?<!_seat)(?<!_kperson)(?<!_capita)_q$"), "q 或 季",
     lambda u: u in ("q", "季")),
    (re.compile(r"_count$"), "计数类", lambda u: u in ("次", "行", "批", "dimensionless")),
)

# observed / literature 的出处必须可核验：source_ref 里要能看到下载日期（§5.15 V-PC-03）
RE_DOWNLOAD_DATE = re.compile(r"(19|20)\d{2}\s*[-年/.]\s*\d{1,2}\s*[-月/.]\s*\d{1,2}")

# 扫描时跳过的相对路径前缀（生成物与机读 schema 不是内容来源）
SKIP_RELPATH_PREFIXES: tuple[str, ...] = ("schemas/",)

SEV_ERROR = "ERROR"
SEV_WARN = "WARN"

SEVERITY_ORDER = {SEV_ERROR: 0, SEV_WARN: 1}


# ---------------------------------------------------------------------------
# 1  整数工具（镜像 11 号文件 §5.2，只用于报表里的占比；不参与任何结算）
# ---------------------------------------------------------------------------

def split_largest_remainder(total: int, weights: list[int]) -> list[int]:
    """最大余数法：Σ result == total 精确成立（10 号文件 §0.9 铁律 2）。

    本工具用它把「各 source_type 的卡片数」折成合计恰好 1 000 000 的 ppm 占比，
    以免仪表盘上出现 99.9999% 这种因取整而失真的数字。
    """
    n = len(weights)
    if n == 0:
        return []
    wsum = sum(weights)
    if wsum <= 0 or total <= 0:
        return [0] * n
    base: list[int] = []
    rems: list[tuple[int, int, int]] = []
    for i, w in enumerate(weights):
        num = total * w
        q = num // wsum                      # rounding: floor, reason=最大余数法先取下界
        base.append(q)
        rems.append((num - q * wsum, -i, i))  # 余数大者优先；同余数按下标升序（确定性）
    left = total - sum(base)
    rems.sort(reverse=True)
    for k in range(left):
        base[rems[k % n][2]] += 1
    return base


def ppm_to_pct_text(ppm: int) -> str:
    """只在报表字符串里做展示格式化（计划书：浮点只允许出现在展示层）。"""
    whole, frac = divmod(ppm, 10_000)
    return f"{whole}.{frac:04d}%"


# ---------------------------------------------------------------------------
# 2  数据结构
# ---------------------------------------------------------------------------

class Finding:
    __slots__ = ("code", "severity", "error_code", "parameter_id", "location", "message")

    def __init__(self, code: str, severity: str, error_code: str,
                 parameter_id: str, location: str, message: str) -> None:
        self.code = code
        self.severity = severity
        self.error_code = error_code
        self.parameter_id = parameter_id
        self.location = location
        self.message = message

    def as_dict(self) -> "OrderedDict[str, Any]":
        d: OrderedDict[str, Any] = OrderedDict()
        d["check"] = self.code
        d["severity"] = self.severity
        d["contract_error_code"] = self.error_code
        d["parameter_id"] = self.parameter_id
        d["location"] = self.location
        d["message"] = self.message
        return d

    def sort_key(self) -> tuple:
        return (SEVERITY_ORDER.get(self.severity, 9), self.code,
                self.parameter_id, self.location)


class Card:
    __slots__ = ("raw", "file_rel", "pointer", "parameter_id")

    def __init__(self, raw: dict, file_rel: str, pointer: str) -> None:
        self.raw = raw
        self.file_rel = file_rel
        self.pointer = pointer
        pid = raw.get("parameter_id")
        self.parameter_id = pid if isinstance(pid, str) else "<未命名>"

    @property
    def location(self) -> str:
        return f"{self.file_rel}{self.pointer}"


# ---------------------------------------------------------------------------
# 3  扫描与抽卡
# ---------------------------------------------------------------------------

# 什么算一张「参数身份证」——只有 `parameter_id` 键在场才算。
# 理由：契约 §5.15 明写 ParameterCard **只覆盖 `param.*` 命名空间**（行为系数与工程常量）；
# 剧本初值、政策的 player_params 与成本字段是**内容数据**，由 V-PD-*/V-FIN-* 等校验器负责，
# 「不需要也不允许逐个建卡」。若把带卡片字段的 player_params 也收进登记表，
# 这张表就会从「param.* 的唯一索引」退化成「所有带注释的数字的大杂烩」，
# 而 V-PC-06（SimCore 里每个裸数字都有卡）将无法据此判定覆盖率。
#
# 但「长得像卡却没有 parameter_id」的对象仍必须被**看见**：它可能是作者漏写了 ID 的真卡。
# 这类对象登记为 PR-024 近似卡（WARN），**不进登记表**——工具报告，不替作者认领。
NEAR_MISS_MARKER_KEYS = ("source_type", "calibration_note")
NEAR_MISS_MIN_FIELD_HITS = 4
# 近似卡可能使用的替代标识键（内容作者已在用的写法）
ALT_ID_KEYS = ("content_ref", "key", "field_ref", "id")


def is_card(node: dict) -> bool:
    return "parameter_id" in node


def is_near_miss(node: dict) -> bool:
    if "parameter_id" in node:
        return False
    if not any(k in node for k in NEAR_MISS_MARKER_KEYS):
        return False
    hits = sum(1 for k in REQUIRED_FIELDS if k in node)
    return hits >= NEAR_MISS_MIN_FIELD_HITS


def alt_identity(node: dict) -> str:
    for k in ALT_ID_KEYS:
        v = node.get(k)
        if isinstance(v, str) and v.strip():
            return f"{k} = {v.strip()}"
    return "无任何标识键"


def collect_cards(node: Any, file_rel: str, pointer: str,
                  out: list[Card], near: list[Card]) -> None:
    """递归抽卡。命中的卡片不再向下递归（一张卡里不会再有一张卡）。"""
    if isinstance(node, dict):
        if is_card(node):
            out.append(Card(node, file_rel, pointer))
            return
        if is_near_miss(node):
            near.append(Card(node, file_rel, pointer))
            return
        for key in node:
            # `_note_*` 是注释（加载器一律不读）：注释里的「待建卡」不是卡，也不该被当成残缺的卡报错
            # （policy_P02.json 的 `_note_parameters_pending` 自己写明「注释里的卡等于没有卡」）。
            if isinstance(key, str) and key.startswith("_note_"):
                continue
            child = pointer + "/" + str(key).replace("~", "~0").replace("/", "~1")
            collect_cards(node[key], file_rel, child, out, near)
    elif isinstance(node, list):
        for i, item in enumerate(node):
            collect_cards(item, file_rel, f"{pointer}/{i}", out, near)


def scan_files(content_root: str, out_json_abs: str, findings: list[Finding],
               near: list[Card]) -> tuple[list[Card], list[str], list[str]]:
    """返回 (卡片列表, 已扫描文件相对路径, 已跳过文件相对路径)。任何单文件失败都不中断整体。"""
    cards: list[Card] = []
    scanned: list[str] = []
    skipped: list[str] = []

    if not os.path.isdir(content_root):
        findings.append(Finding(
            "PR-020", SEV_ERROR, "E_FILE_FORMAT", "-", content_root,
            "内容目录不存在，无卡片可登记。首版内容包尚未创建时这是预期状态。"))
        return cards, scanned, skipped

    paths: list[str] = []
    for dirpath, dirnames, filenames in os.walk(content_root):
        dirnames.sort()
        for name in sorted(filenames):
            if name.lower().endswith(".json"):
                paths.append(os.path.join(dirpath, name))

    for path in sorted(paths):
        rel = os.path.relpath(path, content_root).replace(os.sep, "/")
        if os.path.abspath(path) == out_json_abs:
            skipped.append(rel + "（本工具自身的生成物，排除以避免自指重复登记）")
            continue
        if any(rel.startswith(p) for p in SKIP_RELPATH_PREFIXES):
            skipped.append(rel + "（机读 schema，不是参数来源）")
            continue

        try:
            with open(path, "rb") as fh:
                blob = fh.read()
        except OSError as exc:
            findings.append(Finding("PR-020", SEV_ERROR, "E_FILE_FORMAT", "-", rel,
                                    f"文件无法读取：{exc}"))
            continue

        if blob.startswith(b"\xef\xbb\xbf"):
            findings.append(Finding("PR-021", SEV_ERROR, "E_FILE_FORMAT", "-", rel,
                                    "文件带 UTF-8 BOM（11 号文件 §3 要求无 BOM），已按去 BOM 解析。"))
            blob = blob[3:]
        if b"\r\n" in blob:
            findings.append(Finding("PR-021", SEV_WARN, "E_FILE_FORMAT", "-", rel,
                                    "文件含 CRLF 换行（11 号文件 §3 要求 LF），会使 content_hash 随平台漂移。"))

        try:
            text = blob.decode("utf-8")
        except UnicodeDecodeError as exc:
            findings.append(Finding("PR-020", SEV_ERROR, "E_FILE_FORMAT", "-", rel,
                                    f"文件不是合法 UTF-8：{exc}"))
            continue

        try:
            data = json.loads(text)
        except (json.JSONDecodeError, RecursionError, ValueError) as exc:
            findings.append(Finding("PR-020", SEV_ERROR, "E_FILE_FORMAT", "-", rel,
                                    f"JSON 解析失败，本文件全部卡片未登记：{exc}"))
            continue

        scanned.append(rel)
        before, before_n = len(cards), len(near)
        try:
            collect_cards(data, rel, "", cards, near)
        except RecursionError:
            del cards[before:]
            del near[before_n:]
            findings.append(Finding("PR-020", SEV_ERROR, "E_FILE_FORMAT", "-", rel,
                                    "JSON 嵌套过深，递归抽卡中止，本文件卡片未登记。"))
    return cards, scanned, skipped


# ---------------------------------------------------------------------------
# 4  单卡校验
# ---------------------------------------------------------------------------

def is_int(v: Any) -> bool:
    """bool 是 int 的子类，但 true/false 不是整数值（11 号文件 §1 要求 TYPE_INT）。"""
    return isinstance(v, int) and not isinstance(v, bool)


def blank(v: Any) -> bool:
    return not isinstance(v, str) or v.strip() == ""


def find_floats(node: Any, pointer: str, out: list[str], depth: int = 0) -> None:
    if depth > 64:
        return
    if isinstance(node, float):
        out.append(pointer or "/")
    elif isinstance(node, dict):
        for k, v in node.items():
            find_floats(v, f"{pointer}/{k}", out, depth + 1)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            find_floats(v, f"{pointer}/{i}", out, depth + 1)


def unit_verdict(unit: Any) -> str:
    """返回 'core' | 'contract_extra' | 'family' | 'unknown' | 'not_a_string'。"""
    if not isinstance(unit, str):
        return "not_a_string"
    u = unicodedata.normalize("NFC", unit).strip()
    if u in UNITS_CORE:
        return "core"
    if u in UNITS_CONTRACT_EXTRA:
        return "contract_extra"
    if RE_UNIT_SECTOR_QTY.match(u) or RE_UNIT_PER_QUARTER.match(u) or RE_UNIT_PER_THING_Q.match(u):
        return "family"
    return "unknown"


def check_card(card: Card, findings: list[Finding]) -> None:
    raw = card.raw
    pid = card.parameter_id
    loc = card.location

    def add(code: str, sev: str, err: str, msg: str) -> None:
        findings.append(Finding(code, sev, err, pid, loc, msg))

    # --- PR-001 九（十）字段齐全 -----------------------------------------
    missing = [f for f in REQUIRED_FIELDS if f not in raw]
    if missing:
        add("PR-001", SEV_ERROR, "E_PARAM_CARD",
            "身份证缺字段：" + "、".join(missing) + "。契约 V-PC-01「缺一即失败」。")

    # --- PR-002 必填字符串不得为空 ---------------------------------------
    for f in ("source_ref", "definition", "calibration_note"):
        if f in raw and blank(raw[f]):
            add("PR-002", SEV_ERROR, "E_PARAM_CARD", f"`{f}` 存在但为空或非字符串。")
    if "definition" in raw and isinstance(raw["definition"], str):
        d = raw["definition"].strip()
        if d and len(d) < 8:
            add("PR-002", SEV_WARN, "E_PARAM_CARD",
                f"`definition` 过短（{len(d)} 字），契约要求「说明口径而非重复名字」。")
    if "calibration_note" in raw and isinstance(raw["calibration_note"], str):
        c = raw["calibration_note"].strip()
        if c and len(c) < 8:
            add("PR-002", SEV_WARN, "E_PARAM_CARD",
                "`calibration_note` 过短，契约要求至少写明「如何检验它」或「先调谁」。")

    # --- PR-003 parameter_id 形态 ----------------------------------------
    pid_raw = raw.get("parameter_id")
    if "parameter_id" in raw:
        if not isinstance(pid_raw, str):
            add("PR-003", SEV_ERROR, "E_ID_FORMAT", "`parameter_id` 不是字符串。")
        elif not RE_PARAM_ID.match(pid_raw):
            add("PR-003", SEV_ERROR, "E_ID_FORMAT",
                f"`{pid_raw}` 不匹配 11 号文件 §4 的 `^param\\.[a-z][a-z0-9_]*$`。")

    # --- PR-005 source_type 枚举 ------------------------------------------
    st = raw.get("source_type")
    st_ok = isinstance(st, str) and st in SOURCE_TYPES
    if "source_type" in raw and not st_ok:
        add("PR-005", SEV_ERROR, "E_PARAM_CARD",
            f"`source_type` = {st!r} 不在 {{{'|'.join(SOURCE_TYPES)}}} 内。")

    # --- PR-009 confidence 枚举 -------------------------------------------
    conf = raw.get("confidence")
    if "confidence" in raw and not (isinstance(conf, str) and conf in CONFIDENCE_LEVELS):
        add("PR-009", SEV_ERROR, "E_PARAM_CARD",
            f"`confidence` = {conf!r} 不在 {{{'|'.join(CONFIDENCE_LEVELS)}}} 内。")

    # --- PR-013 无浮点（Godot 的 JSON.parse_string 遇小数点即丢精度） -------
    floats: list[str] = []
    find_floats(raw, "", floats)
    if floats:
        add("PR-013", SEV_ERROR, "E_FLOAT_IN_CONTENT",
            "卡片内出现浮点字面量：" + "、".join(floats[:6]) +
            ("…" if len(floats) > 6 else "") + "。11 号文件 §3 禁止小数点与指数记号。")

    # --- PR-007 / PR-006 valid_range 与 value -----------------------------
    vr = raw.get("valid_range")
    vr_ok = (isinstance(vr, list) and len(vr) == 2 and is_int(vr[0]) and is_int(vr[1]))
    if "valid_range" in raw and not vr_ok:
        add("PR-007", SEV_ERROR, "E_PARAM_RANGE",
            f"`valid_range` 必须是 [min, max] 两个整数，实得 {vr!r}。")
    elif vr_ok and vr[0] > vr[1]:
        add("PR-007", SEV_ERROR, "E_PARAM_RANGE", f"`valid_range` 的 min > max：{vr!r}。")
        vr_ok = False

    val = raw.get("value")
    val_items: list[int] = []
    if "value" in raw:
        if is_int(val):
            val_items = [val]
        elif isinstance(val, list) and val and all(is_int(x) for x in val):
            val_items = list(val)
        else:
            add("PR-006", SEV_ERROR, "E_PARAM_CARD",
                f"`value` 必须是整数或非空整数数组（禁止 float / bool / null / 字符串），实得 {type(val).__name__}。")

    for x in val_items:
        if abs(x) > INT_SAFE_MAX:
            add("PR-014", SEV_ERROR, "E_INT_RANGE",
                f"`value` 分量 {x} 的绝对值超出 2^53 互操作安全区（11 号文件 §3）。")

    if vr_ok and val_items:
        lo, hi = vr[0], vr[1]
        bad = [x for x in val_items if not (lo <= x <= hi)]
        if bad:
            add("PR-006", SEV_ERROR, "E_PARAM_RANGE",
                f"`value` 分量 {bad} 越出 valid_range [{lo}, {hi}]（契约 V-PC-02）。")

    # --- PR-008 单位拼写 ---------------------------------------------------
    unit = raw.get("unit")
    verdict = unit_verdict(unit) if "unit" in raw else None
    if verdict == "not_a_string":
        add("PR-008", SEV_ERROR, "E_UNIT_MISMATCH", f"`unit` 不是字符串：{unit!r}。")
    elif verdict == "unknown":
        add("PR-008", SEV_ERROR, "E_UNIT_MISMATCH",
            f"`unit` = {unit!r} 不在允许集合内（10 号文件 §0.1 核心符号 + 11 号文件 §5.15 沿用写法 + μQ_<部门> 族）。")
    elif verdict == "contract_extra":
        add("PR-018", SEV_WARN, "E_UNIT_MISMATCH",
            f"`unit` = {unit!r} 只出现在 11 号文件 §5.15 的表里，未进 10 号文件 §0.1 的唯一单位定义。"
            "两处拼写不统一时，单位一致性无法被机器完全证明。")

    # --- PR-017 字段后缀 ↔ 单位（10 号文件 §0.2） ---------------------------
    if isinstance(pid_raw, str) and isinstance(unit, str):
        tail = pid_raw.rsplit(".", 1)[-1]
        u = unicodedata.normalize("NFC", unit).strip()
        for pattern, expect, ok in SUFFIX_UNIT_RULES:
            m = pattern.search(tail)
            if not m:
                continue
            if not ok(u):
                add("PR-017", SEV_WARN, "E_UNIT_MISMATCH",
                    f"ID 后缀 `{m.group(0)}` 按 10 号文件 §0.2 应配 {expect}，实得 {unit!r}。"
                    "名字与单位不一致时，两处迟早有一处是错的。")
            break

    # --- PR-010 / PR-016 reference_year ------------------------------------
    ry = raw.get("reference_year")
    if "reference_year" in raw and not is_int(ry):
        add("PR-010", SEV_ERROR, "E_PARAM_CARD", f"`reference_year` 必须是整数，实得 {ry!r}。")
    elif is_int(ry):
        if st in ("observed", "literature"):
            if ry <= 0:
                add("PR-010", SEV_ERROR, "E_FAKE_OBSERVED",
                    f"`source_type` = {st} 必须填真实年份，`reference_year` = {ry} 不是真实年份。"
                    "契约明写「不得把缺失当零年份」，0 是虚构基年的专用标记。")
        elif st == "design_assumption" and ry != 0:
            add("PR-016", SEV_WARN, "E_PARAM_CARD",
                f"虚构剧本的 design_assumption 按契约应填 `reference_year` = 0，实得 {ry}。")

    # --- PR-010 observed / literature 的可核验出处（V-PC-03） --------------
    if st in ("observed", "literature"):
        sref = raw.get("source_ref")
        if blank(sref):
            add("PR-010", SEV_ERROR, "E_FAKE_OBSERVED",
                f"`source_type` = {st} 但 `source_ref` 为空。计划书 §14 明令禁止无出处的观测／文献。")
        elif not RE_DOWNLOAD_DATE.search(sref):
            add("PR-010", SEV_ERROR, "E_FAKE_OBSERVED",
                f"`source_type` = {st} 的 `source_ref` 中找不到数据集名 + 下载日期（契约 V-PC-03）。"
                "计划书 §19：本计划尚未导入数据，此刻出现观测只可能是伪造。")

    # --- PR-012 derived 必须给 derivation_expr（V-PC-05） ------------------
    if st == "derived":
        if blank(raw.get("derivation_expr")):
            add("PR-012", SEV_ERROR, "E_PARAM_DERIVE",
                "`source_type` = derived 必须给出非空 `derivation_expr` 并被复算验证（契约 V-PC-05）。")
    elif "derivation_expr" in raw and st_ok:
        add("PR-012", SEV_WARN, "E_PARAM_DERIVE",
            f"`derivation_expr` 只对 derived 有意义，本卡 `source_type` = {st}。")

    # --- PR-015 未声明的多余键（11 号文件 §3 additionalProperties:false） ---
    known = set(REQUIRED_FIELDS) | set(OPTIONAL_FIELDS)
    extra = sorted(k for k in raw
                   if k not in known and not (isinstance(k, str) and k.startswith("_note_")))
    if extra:
        add("PR-015", SEV_WARN, "E_UNKNOWN_FIELD",
            "卡片含 §5.15 未声明的键：" + "、".join(extra) +
            "。契约 additionalProperties:false 下这些键会使内容包被拒绝加载。")


def check_near_misses(near: list[Card], findings: list[Finding]) -> None:
    """PR-024：长得像身份证、却没有 parameter_id 的对象。

    两种真实来源，工具**不替作者区分意图**，只如实报告：
      (a) 政策的 `player_params` —— 玩家杠杆，本就不属 `param.*`，卡片字段是额外注释；
      (b) `content_value_cards` 一类自创命名空间 —— 契约 §5.15 明说内容数据不建卡，
          出现它意味着内容作者与契约对「什么该建卡」的理解不一致，应先改契约再改数据。
    """
    for c in sorted(near, key=lambda x: (x.file_rel, x.pointer)):
        holder = c.pointer.strip("/").split("/")[0] if c.pointer.strip("/") else "<根>"
        findings.append(Finding(
            "PR-024", SEV_WARN, "E_PARAM_CARD", "-", c.location,
            f"该对象带有身份证字段却无 `parameter_id`（{alt_identity(c.raw)}，容器 `{holder}`），"
            "未进登记表。若它本应是 param.* 参数，请补 `parameter_id`；"
            "若它是内容数据或玩家杠杆，请确认契约 §5.15「内容数据不建卡」的分界线仍然成立。"))


def check_global(cards: list[Card], findings: list[Finding]) -> None:
    # --- PR-004 parameter_id 全局唯一 --------------------------------------
    by_id: dict[str, list[Card]] = {}
    for c in cards:
        if isinstance(c.raw.get("parameter_id"), str):
            by_id.setdefault(c.raw["parameter_id"], []).append(c)
    for pid in sorted(by_id):
        group = by_id[pid]
        if len(group) > 1:
            locs = "；".join(c.location for c in group)
            findings.append(Finding(
                "PR-004", SEV_ERROR, "E_DUP_ID", pid, locs,
                f"`{pid}` 在 {len(group)} 处重复登记。11 号文件 §4 规则 4：重复 ID 直接拒绝加载。"
                "同一参数被两份文件各写一张卡时，两处数值迟早分叉。"))

    # --- PR-025 语料层面的单位约定分歧 --------------------------------------
    # 「每季金额」的两种写法（`μU` vs `μU/季`）都在用。哪种为准是契约问题，不是逐卡缺陷；
    # 但两种并存会让「同一量纲的两个参数看起来不同量纲」，量纲一致性因此无法被机器证明。
    rate_like = [c for c in cards
                 if isinstance(c.raw.get("parameter_id"), str)
                 and re.search(r"_per_(q|seat_q|kperson_q|capita_q)$", c.raw["parameter_id"])
                 and isinstance(c.raw.get("unit"), str)]
    with_slash = [c for c in rate_like if c.raw["unit"].strip().endswith(("/季", "/q"))]
    without = [c for c in rate_like if c not in with_slash]
    if with_slash and without:
        minority = without if len(without) <= len(with_slash) else with_slash
        findings.append(Finding(
            "PR-025", SEV_WARN, "E_UNIT_MISMATCH", "-",
            "；".join(c.location for c in minority[:6]) +
            ("…" if len(minority) > 6 else ""),
            f"ID 以 `_per_q` 结尾的 {len(rate_like)} 张卡中，{len(with_slash)} 张把单位写成带 `/季` 的形式、"
            f"{len(without)} 张写成不带的形式（少数派 {len(minority)} 张，位置见左）。"
            "两份契约都没有裁定「每季金额」的单位拼法；在裁定之前，"
            "同量纲参数看起来像不同量纲，量纲一致性无法被机器证明。"))

    # --- PR-011 首版 observed 条目数必须为 0（V-PC-04） ---------------------
    observed = [c for c in cards if c.raw.get("source_type") == "observed"]
    if observed:
        findings.append(Finding(
            "PR-011", SEV_ERROR, "E_FAKE_OBSERVED", "-",
            "；".join(c.location for c in observed[:8]),
            f"首版内容包中 observed 卡片数为 {len(observed)}，契约 V-PC-04 要求必须为 0。"
            "计划书 §19 明写「本计划尚未导入数据」。"))


def check_coverage(cards: list[Card], contract_ids: list[str],
                   findings: list[Finding]) -> list[str]:
    """对照 11 号文件 §5.15「首版必备参数最小集」，报缺卡。返回缺失 ID 列表。"""
    if not contract_ids:
        return []
    have = {c.raw["parameter_id"] for c in cards
            if isinstance(c.raw.get("parameter_id"), str)}
    missing = sorted(set(contract_ids) - have)
    for pid in missing:
        findings.append(Finding(
            "PR-019", SEV_WARN, "E_PARAM_COVERAGE", pid,
            "docs/11_data_contract.md §5.15 首版必备参数最小集",
            "契约列为首版必备，但内容包中尚无对应身份证。"))
    return missing


# ---------------------------------------------------------------------------
# 5  从契约文档解析「首版必备参数最小集」
#     —— 不把清单硬编码进本工具，避免制造第二处事实来源。
# ---------------------------------------------------------------------------

RE_MINSET_HEAD = re.compile(r"首版必备参数最小集")
RE_PARAM_IN_DOC = re.compile(r"`(param\.[a-z][a-z0-9_]*)(?:\[\d+\])?`")


def parse_contract_min_set(contract_path: str, findings: list[Finding]) -> list[str]:
    try:
        with open(contract_path, "r", encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError as exc:
        findings.append(Finding(
            "PR-022", SEV_WARN, "E_FILE_FORMAT", "-", contract_path,
            f"读不到数据协议文档，已跳过「首版必备参数最小集」覆盖检查：{exc}"))
        return []

    start = -1
    for i, ln in enumerate(lines):
        if RE_MINSET_HEAD.search(ln):
            start = i
            break
    if start < 0:
        findings.append(Finding(
            "PR-022", SEV_WARN, "E_FILE_FORMAT", "-", contract_path,
            "在数据协议文档中找不到「首版必备参数最小集」小节，已跳过覆盖检查。"))
        return []

    ids: list[str] = []
    seen_table = False
    for ln in lines[start + 1:]:
        if ln.startswith("## ") or ln.startswith("### "):
            break
        if ln.lstrip().startswith("|"):
            seen_table = True
            ids.extend(RE_PARAM_IN_DOC.findall(ln))
        elif seen_table and ln.strip() == "":
            # 表结束后允许一个空行，再遇非表行即停
            continue
        elif seen_table and not ln.lstrip().startswith("|"):
            break
    # 表头行里的「parameter_id」字面不会命中正则，无需另行剔除
    return sorted(set(ids))


# ---------------------------------------------------------------------------
# 6  统计
# ---------------------------------------------------------------------------

def build_stats(cards: list[Card]) -> "OrderedDict[str, Any]":
    total = len(cards)

    def dist(key: str, domain: tuple[str, ...]) -> list["OrderedDict[str, Any]"]:
        counter: Counter = Counter()
        for c in cards:
            v = c.raw.get(key)
            counter[v if isinstance(v, str) and v in domain else "<非法或缺失>"] += 1
        labels = [k for k in domain if counter.get(k)] + \
                 ([k for k in counter if k not in domain])
        labels = list(dict.fromkeys(labels))
        shares = split_largest_remainder(1_000_000, [counter[k] for k in labels]) if total else []
        rows: list[OrderedDict[str, Any]] = []
        for i, k in enumerate(labels):
            row: OrderedDict[str, Any] = OrderedDict()
            row["key"] = k
            row["count"] = counter[k]
            row["share_ppm"] = shares[i] if shares else 0
            rows.append(row)
        return rows

    st: OrderedDict[str, Any] = OrderedDict()
    st["card_count"] = total
    st["by_source_type"] = dist("source_type", SOURCE_TYPES)
    st["by_confidence"] = dist("confidence", CONFIDENCE_LEVELS)

    per_file: Counter = Counter(c.file_rel for c in cards)
    st["by_file"] = [OrderedDict((("file", f), ("count", per_file[f])))
                     for f in sorted(per_file)]
    return st


# ---------------------------------------------------------------------------
# 7  输出
# ---------------------------------------------------------------------------

def write_text(path: str, text: str) -> None:
    """UTF-8 无 BOM、LF、末尾单换行（11 号文件 §3 文件格式规则）。"""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if not text.endswith("\n"):
        text += "\n"
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def card_record(c: Card) -> "OrderedDict[str, Any]":
    r: OrderedDict[str, Any] = OrderedDict()
    r["parameter_id"] = c.parameter_id
    for f in ("value", "unit", "source_type", "source_ref", "reference_year",
              "definition", "valid_range", "confidence", "calibration_note"):
        if f in c.raw:
            r[f] = c.raw[f]
    if "derivation_expr" in c.raw:
        r["derivation_expr"] = c.raw["derivation_expr"]
    r["_origin_file"] = c.file_rel
    r["_origin_pointer"] = c.pointer or "/"
    return r


def build_registry_json(cards: list[Card], near: list[Card], findings: list[Finding],
                        stats: "OrderedDict[str, Any]", scanned: list[str],
                        skipped: list[str], missing: list[str],
                        contract_ids: list[str]) -> "OrderedDict[str, Any]":
    err = sum(1 for f in findings if f.severity == SEV_ERROR)
    warn = sum(1 for f in findings if f.severity == SEV_WARN)

    doc: OrderedDict[str, Any] = OrderedDict()
    doc["schema_kind"] = SCHEMA_KIND
    doc["schema_version"] = SCHEMA_VERSION
    doc["generated"] = 1
    doc["_note_generated"] = (
        "本文件由 tools/build_param_registry.py 生成，是 content/ 下全部参数身份证的只读索引，"
        "不是任何参数的事实来源，也不应进入 content_hash 或被加载器当作 parameter_set 读取。"
        "改参数请改各自的来源文件后重新生成本文件。")
    doc["tool"] = "tools/build_param_registry.py"
    doc["tool_version"] = TOOL_VERSION
    doc["summary"] = OrderedDict((
        ("files_scanned", len(scanned)),
        ("files_skipped", len(skipped)),
        ("card_count", len(cards)),
        ("near_miss_count", len(near)),
        ("error_count", err),
        ("warn_count", warn),
        ("contract_min_set_size", len(contract_ids)),
        ("contract_min_set_missing", len(missing)),
    ))
    doc["stats"] = stats
    doc["files_scanned"] = scanned
    doc["files_skipped"] = skipped
    doc["contract_min_set_missing"] = missing
    doc["near_miss_cards"] = [
        OrderedDict((("location", c.location), ("alt_identity", alt_identity(c.raw))))
        for c in sorted(near, key=lambda x: (x.file_rel, x.pointer))]
    doc["findings"] = [f.as_dict() for f in sorted(findings, key=lambda x: x.sort_key())]
    doc["cards"] = [card_record(c) for c in
                    sorted(cards, key=lambda c: (c.parameter_id, c.location))]
    return doc


def bar(ppm: int, width: int = 24) -> str:
    filled = ppm * width // 1_000_000   # rounding: floor, reason=展示条，宁短勿长
    return "█" * filled + "·" * (width - filled)


def md_escape(s: Any) -> str:
    t = "" if s is None else str(s)
    return t.replace("|", "\\|").replace("\n", " ").replace("\r", " ")


def clip(s: Any, n: int) -> str:
    t = md_escape(s)
    return t if len(t) <= n else t[: n - 1] + "…"


def build_markdown(cards: list[Card], near: list[Card], findings: list[Finding],
                   stats: "OrderedDict[str, Any]", scanned: list[str],
                   skipped: list[str], missing: list[str],
                   contract_ids: list[str], content_root_rel: str) -> str:
    err = [f for f in findings if f.severity == SEV_ERROR]
    warn = [f for f in findings if f.severity == SEV_WARN]
    total = len(cards)
    L: list[str] = []
    A = L.append

    A("# 14 参数登记表（生成物，勿手改）")
    A("")
    A("> 本文件由 `tools/build_param_registry.py` 扫描 `" + content_root_rel +
      "` 下全部 JSON 生成，对应计划书 §14「每个参数都带一张身份证」与"
      "`docs/11_data_contract.md` §5.15 `ParameterCard`。")
    A("> 任何手工修改都会在下次生成时被覆盖：**改参数请改来源文件**。")
    A("> 工具只报告、不修正；它不含任何模拟逻辑（计划书 §12「Python 只用于离线分析」）。")
    A("")

    # --- 证据状态仪表盘 ---------------------------------------------------
    A("## 0 证据状态仪表盘")
    A("")
    A("计划书 §14「本版本的证据状态」：**尚未完成数据下载与现实样本拟合**。"
      "下表是这句话的机器版本——它诚实地显示这个模型此刻建立在多少作者假设之上。")
    A("")
    A("| source_type | 含义 | 卡片数 | 占比 | |")
    A("|---|---|---:|---:|---|")
    meaning = {
        "observed": "实测数据（首版必须为 0）",
        "literature": "文献取值（需出处 + 下载日期）",
        "design_assumption": "设计假设（作者拍板，待校准）",
        "derived": "派生计算（须给 derivation_expr）",
    }
    for row in stats["by_source_type"]:
        k = row["key"]
        A("| `%s` | %s | %d | %s | `%s` |" % (
            md_escape(k), meaning.get(k, "—"), row["count"],
            ppm_to_pct_text(row["share_ppm"]), bar(row["share_ppm"])))
    if not stats["by_source_type"]:
        A("| — | 内容包中尚无参数身份证 | 0 | — | |")
    A("")

    obs = next((r["count"] for r in stats["by_source_type"] if r["key"] == "observed"), 0)
    lit = next((r["count"] for r in stats["by_source_type"] if r["key"] == "literature"), 0)
    A("**V-PC-04 闸门（首版 `observed` 必须为 0）**：" +
      ("✅ 通过，observed = 0。" if obs == 0 else
       f"❌ 失败，observed = {obs}。计划书 §19 明写数据尚未导入，此刻的 observed 只可能是伪造。"))
    A("")
    if total:
        assumption = total - obs - lit
        share = assumption * 1_000_000 // total   # rounding: floor, reason=展示占比
        A(f"**一句话读数**：{total} 张身份证中有 {assumption} 张"
          f"（{ppm_to_pct_text(share)}）没有任何外部证据支撑，只有作者假设与由假设派生的计算。"
          "这不是缺陷，是首版的**真实状态**；它决定了本版结论只能用于机制验证，不能用于现实预测。")
    else:
        A("**一句话读数**：内容包中尚未登记任何参数身份证。")
    A("")

    A("### 置信度分布")
    A("")
    A("| confidence | 卡片数 | 占比 | |")
    A("|---|---:|---:|---|")
    for row in stats["by_confidence"]:
        A("| `%s` | %d | %s | `%s` |" % (
            md_escape(row["key"]), row["count"],
            ppm_to_pct_text(row["share_ppm"]), bar(row["share_ppm"])))
    if not stats["by_confidence"]:
        A("| — | 0 | — | |")
    A("")

    # --- 校验结果 ---------------------------------------------------------
    A("## 1 校验结果")
    A("")
    A(f"- 扫描文件：{len(scanned)}（跳过 {len(skipped)}）")
    A(f"- 参数身份证：{total}")
    A(f"- 近似卡（带卡片字段但无 `parameter_id`，未进登记表）：{len(near)}")
    A(f"- **ERROR：{len(err)}**（按契约应拒绝加载）")
    A(f"- WARN：{len(warn)}（不阻断加载，但应在 G0 关闭前清掉）")
    A("")
    if not findings:
        A("✅ 全部检查通过。")
        A("")
    else:
        counter: Counter = Counter((f.code, f.severity) for f in findings)
        A("### 1.1 问题汇总")
        A("")
        A("| 检查码 | 级别 | 契约错误码 | 条目数 | 检查内容 |")
        A("|---|---|---|---:|---|")
        for (code, sev), n in sorted(counter.items(),
                                     key=lambda kv: (SEVERITY_ORDER[kv[0][1]], kv[0][0])):
            A("| %s | %s | `%s` | %d | %s |" % (
                code, sev, CHECK_ERROR_CODE.get(code, "—"), n,
                CHECK_TITLE.get(code, "—")))
        A("")
        A("### 1.2 逐条明细")
        A("")
        A("| 级别 | 检查码 | parameter_id | 位置 | 说明 |")
        A("|---|---|---|---|---|")
        for f in sorted(findings, key=lambda x: x.sort_key()):
            A("| %s | %s | `%s` | `%s` | %s |" % (
                f.severity, f.code, md_escape(f.parameter_id),
                clip(f.location, 80), clip(f.message, 220)))
        A("")

    # --- 契约最小集覆盖 ---------------------------------------------------
    A("## 2 契约「首版必备参数最小集」覆盖")
    A("")
    if not contract_ids:
        A("未能从 `docs/11_data_contract.md` §5.15 解析出最小集，本节跳过。")
    else:
        have = len(contract_ids) - len(missing)
        A(f"契约点名的首版必备参数 {len(contract_ids)} 项，已建卡 {have} 项，"
          f"**未建卡 {len(missing)} 项**。")
        A("")
        if missing:
            A("未建卡清单（每项都是 SimCore 迟早要用、届时只能凭空写死的数字）：")
            A("")
            for pid in missing:
                A(f"- `{pid}`")
            A("")
        else:
            A("✅ 最小集已全部建卡。")
            A("")

    # --- 全表 -------------------------------------------------------------
    A("## 3 参数登记全表")
    A("")
    A("按 `parameter_id` 升序。`value` 为整数或整数数组；单位见 `10_variable_dictionary.md` §0.1。")
    A("")
    A("| parameter_id | value | unit | source_type | conf. | valid_range | 定义 | 来源文件 |")
    A("|---|---:|---|---|---|---|---|---|")
    for c in sorted(cards, key=lambda c: (c.parameter_id, c.location)):
        raw = c.raw
        v = raw.get("value")
        vtxt = md_escape(json.dumps(v, ensure_ascii=False)) if v is not None else "—"
        vr = raw.get("valid_range")
        vrtxt = (f"[{vr[0]}, {vr[1]}]" if isinstance(vr, list) and len(vr) == 2
                 else md_escape(json.dumps(vr, ensure_ascii=False)) if vr is not None else "—")
        A("| `%s` | %s | %s | %s | %s | %s | %s | `%s` |" % (
            md_escape(c.parameter_id), clip(vtxt, 28), md_escape(raw.get("unit", "—")),
            md_escape(raw.get("source_type", "—")), md_escape(raw.get("confidence", "—")),
            md_escape(vrtxt), clip(raw.get("definition", "—"), 60), md_escape(c.file_rel)))
    if not cards:
        A("| — | — | — | — | — | — | 内容包中尚无参数身份证 | — |")
    A("")

    # --- 逐文件 -----------------------------------------------------------
    A("## 4 卡片分布与扫描范围")
    A("")
    A("| 来源文件 | 卡片数 |")
    A("|---|---:|")
    for row in stats["by_file"]:
        A("| `%s` | %d |" % (md_escape(row["file"]), row["count"]))
    if not stats["by_file"]:
        A("| — | 0 |")
    A("")
    A("<details><summary>已扫描文件（%d）</summary>" % len(scanned))
    A("")
    for f in scanned:
        A(f"- `{f}`")
    A("")
    A("</details>")
    A("")
    if skipped:
        A("**已跳过**：")
        for f in skipped:
            A(f"- `{f}`")
        A("")

    A("---")
    A("")
    A("*本文件为生成物。校准纪律见计划书 §14，待决问题见 `docs/13_open_questions.md`。*")
    return "\n".join(L)


CHECK_TITLE: dict[str, str] = {
    "PR-001": "身份证九字段齐全（V-PC-01）",
    "PR-002": "必填字符串非空且言之有物",
    "PR-003": "parameter_id 匹配 §4 正则",
    "PR-004": "parameter_id 全局唯一",
    "PR-005": "source_type 在四值枚举内",
    "PR-006": "value 落在 valid_range 内（V-PC-02）",
    "PR-007": "valid_range 形态为 [min, max] 且 min ≤ max",
    "PR-008": "unit 拼写在允许集合内",
    "PR-009": "confidence 在 low/medium/high 内",
    "PR-010": "observed / literature 必须有可核验出处与年份（V-PC-03）",
    "PR-011": "首版 observed 条目数必须为 0（V-PC-04）",
    "PR-012": "derived 必须给 derivation_expr（V-PC-05）",
    "PR-013": "卡片内不得出现浮点字面量",
    "PR-014": "整数落在 2^53 互操作安全区内",
    "PR-015": "无 §5.15 未声明的多余键",
    "PR-016": "虚构剧本的 design_assumption 应填 reference_year = 0",
    "PR-017": "ID 后缀与单位一致（§0.2）",
    "PR-018": "单位拼写在两份契约间统一",
    "PR-019": "契约最小集覆盖（V-PC-06 的前哨）",
    "PR-020": "文件可读且为合法 JSON",
    "PR-021": "文件格式为 UTF-8 无 BOM、LF",
    "PR-022": "契约文档可解析",
    "PR-023": "工具自身未在该卡上异常",
    "PR-024": "近似卡：有卡片字段但无 parameter_id",
    "PR-025": "语料内单位约定是否统一",
}

CHECK_ERROR_CODE: dict[str, str] = {
    "PR-001": "E_PARAM_CARD", "PR-002": "E_PARAM_CARD", "PR-003": "E_ID_FORMAT",
    "PR-004": "E_DUP_ID", "PR-005": "E_PARAM_CARD", "PR-006": "E_PARAM_RANGE",
    "PR-007": "E_PARAM_RANGE", "PR-008": "E_UNIT_MISMATCH", "PR-009": "E_PARAM_CARD",
    "PR-010": "E_FAKE_OBSERVED", "PR-011": "E_FAKE_OBSERVED", "PR-012": "E_PARAM_DERIVE",
    "PR-013": "E_FLOAT_IN_CONTENT", "PR-014": "E_INT_RANGE", "PR-015": "E_UNKNOWN_FIELD",
    "PR-016": "E_PARAM_CARD", "PR-017": "E_UNIT_MISMATCH", "PR-018": "E_UNIT_MISMATCH",
    "PR-019": "E_PARAM_COVERAGE", "PR-020": "E_FILE_FORMAT", "PR-021": "E_FILE_FORMAT",
    "PR-022": "E_FILE_FORMAT", "PR-023": "E_PARAM_CARD", "PR-024": "E_PARAM_CARD",
    "PR-025": "E_UNIT_MISMATCH",
}


# ---------------------------------------------------------------------------
# 8  主流程
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    project = os.path.dirname(here)

    ap = argparse.ArgumentParser(
        description="扫描 content/ 下的参数身份证，生成登记表与证据状态仪表盘。")
    ap.add_argument("--project", default=project, help="项目根目录（默认：本脚本的上一级）")
    ap.add_argument("--content", default=None, help="内容目录（默认：<project>/content）")
    ap.add_argument("--out-json", default=None,
                    help="机读输出（默认：<content>/parameters/registry.json）")
    ap.add_argument("--out-md", default=None,
                    help="人读输出（默认：<project>/docs/14_parameter_registry.md）")
    ap.add_argument("--contract", default=None,
                    help="数据协议文档（默认：<project>/docs/11_data_contract.md）")
    ap.add_argument("--warn-as-error", action="store_true", help="WARN 也计入非零退出码")
    ap.add_argument("--check", action="store_true", help="只检查不写文件（CI 用）")
    ap.add_argument("--quiet", action="store_true", help="只输出结论行")
    args = ap.parse_args(argv)

    proj = os.path.abspath(args.project)
    content_root = os.path.abspath(args.content or os.path.join(proj, "content"))
    out_json = os.path.abspath(args.out_json or
                               os.path.join(content_root, "parameters", "registry.json"))
    out_md = os.path.abspath(args.out_md or
                             os.path.join(proj, "docs", "14_parameter_registry.md"))
    contract = os.path.abspath(args.contract or
                               os.path.join(proj, "docs", "11_data_contract.md"))

    findings: list[Finding] = []
    near: list[Card] = []
    cards, scanned, skipped = scan_files(content_root, out_json, findings, near)

    for c in cards:
        try:
            check_card(c, findings)
        except Exception as exc:                      # noqa: BLE001 — 单卡异常不得拖垮全表
            findings.append(Finding("PR-023", SEV_ERROR, "E_PARAM_CARD",
                                    c.parameter_id, c.location,
                                    f"校验该卡时工具内部异常，请报缺陷：{exc!r}"))
    check_near_misses(near, findings)
    check_global(cards, findings)
    contract_ids = parse_contract_min_set(contract, findings)
    missing = check_coverage(cards, contract_ids, findings)

    stats = build_stats(cards)
    content_rel = os.path.relpath(content_root, proj).replace(os.sep, "/")

    if not args.check:
        registry = build_registry_json(cards, near, findings, stats, scanned, skipped,
                                       missing, contract_ids)
        try:
            write_text(out_json, json.dumps(registry, ensure_ascii=False, indent=2))
            write_text(out_md, build_markdown(cards, near, findings, stats, scanned,
                                              skipped, missing, contract_ids, content_rel))
        except OSError as exc:
            print(f"[build_param_registry] 写出失败：{exc}", file=sys.stderr)
            return 2

    n_err = sum(1 for f in findings if f.severity == SEV_ERROR)
    n_warn = sum(1 for f in findings if f.severity == SEV_WARN)

    if not args.quiet:
        # PR-019（最小集未建卡）在控制台折叠成一行：它是**尚未开始的工作**，
        # 不是既有卡片的缺陷，逐条刷屏会把真正的 ERROR 顶出屏幕。完整清单在两份输出里。
        bulk = sum(1 for f in findings if f.code == "PR-019")
        for f in sorted(findings, key=lambda x: x.sort_key()):
            if f.code == "PR-019":
                continue
            print(f"[{f.severity}] {f.code} {f.parameter_id} @ {f.location}: {f.message}")
        if bulk:
            print(f"[WARN] PR-019 × {bulk}：契约最小集中尚未建卡的参数，清单见输出文件 §2。")
        if not args.check:
            print(f"[build_param_registry] 已写出 {out_json}")
            print(f"[build_param_registry] 已写出 {out_md}")
    obs = next((r["count"] for r in stats["by_source_type"]
                if r["key"] == "observed"), 0)
    print(f"[build_param_registry] 文件 {len(scanned)} / 卡片 {len(cards)} / "
          f"ERROR {n_err} / WARN {n_warn} / observed {obs} / 最小集缺 {len(missing)}")

    if n_err:
        return 1
    if args.warn_as_error and n_warn:
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
