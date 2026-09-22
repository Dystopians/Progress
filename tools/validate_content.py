#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""经纬 / 内容层校验器（G0 验收闸门）

权威依据（按优先级）：
  docs/11_data_contract.md   —— schema、错误码、V-* 校验表（本文件的主依据）
  docs/10_variable_dictionary.md —— 稳定 ID 全集、INV-141..152 剧本硬约束
  docs/12_simulation_contract.md —— 债券票息与摊还口径（V-FIN-05 复算依据）
  docs/ref/plan_v1.0.txt     —— §05 剧本硬数字、§09/§10 政策规格

纪律：
  * 本工具只读。绝不修改 content/ 下任何文件（唯一写动作是 --json 指定的报告文件）。
  * 不放宽检查。契约本身有硬伤时，按契约执行并在下面登记，不私自改判。
  * 分级 ERROR / WARN / INFO；有 ERROR 则退出码非 0。

本工具在实现过程中发现、但**没有自行裁定**的契约缺口（按契约现状执行，请裁定后回来收紧）：
  OQ-V01  MechanismRegistry 不存在。11 号 §5.12 的 V-PD-08 要求 `mechanism_ids` 中每个 ID
          「在 MechanismRegistry 中已注册」，但全仓库没有这张表：21 号文件有 8 个报告域
          （mech.employment/power/housing/finance/service/supply/external/politics），
          11 号文件示例用的是 mech.grid_capacity/project_queue/service_capacity，两套互不相交。
          本工具据此只报 WARN，等注册表落地后应升为 ERROR。
  OQ-V02  测试注册表 tests/tools/test_registry.gd 尚未存在。V-PD-06/07 的「test_id 真实存在」
          暂以 docs/30_quality_gates.md + 31_adversarial_tests.md 的测试矩阵为准（仍报 ERROR）。
  OQ-V03  **已按文档优先级处理（2026-09-12）**：11 号 §5.12 的 PolicyDefinition schema 里没有
          effect_chain 字段，但计划书 §09（优先级第 1 位）要求「每项至少 1 条完整反馈链」，
          验收口径 >= 4 环。本工具同时执行两条时，additionalProperties:false 会让**任何**正确的
          政策文件都无法通过——一条谁都满足不了的规则不是严格，是判据本身坏了。
          按「计划书 > docs/18 > 12 > 11 > 10」，缺字段的一侧是 §5.12，因此已把 effect_chain
          正式登记进 SCHEMAS["policy_definition"]（必填、array）。两侧方向一致后矛盾消失。
          注意这不是两头放水：effect_chain 仍是必填、仍要求 >= 4 环且逐环写清 settlement_step，
          additionalProperties:false 对其余任何未声明键的约束一字未动。
          **遗留**：docs/11 §5.12 的字段表与 docs/18 的裁定记录需同步补上该字段，
          在那之前本工具的 schema 表与 §5.12 正文不一致，差异只有这一个字段。
  OQ-V04  player_params 的枚举写法自相矛盾：§5.12 的 P04 示例用字符串 default 且不给 valid_range，
          而 V-PD-09 要求「每项有 valid_range 与 default，且 default ∈ valid_range」。
          本工具接受「取值本身」与「下标 + [0, n-1]」两种写法，等契约统一后收紧成一种。
  OQ-V05  exit_rule 的 delivered_assets / unfinished_work / compensation_rule 没有取值集合，
          内容层自创了哨兵值 "none"。本工具只报 WARN；契约补上枚举后应升为 ERROR。
  OQ-V06  投入产出「行合计 == 列合计」是关于**水平表**的恒等式；content/ 里只有系数矩阵。
          在 cells_init.json 补齐前，这条无法执行（本工具明确报为「无法核对」，不是「通过」）。
  OQ-V07  事件的「逐条后果说明」没有合法的书写位置。计划书 §13 要求每条变化附带实体 ID、
          来源操作、金额／数量、时间与约束，本工具据此要求事件给出逐条后果；但 11 号文件 §5.13
          的 EventTemplate 只声明 9 个键、不含 consequences，§3 的 additionalProperties:false
          又禁止未声明的顶层键——写了必报 E_UNKNOWN_FIELD，不写必报 E_EVENT_EVIDENCE。
          本工具按 §3 自己给出的出路裁剪：`_note_consequences` 与 `consequences` 都认，
          逐条断言（explain_keys）两处一视同仁。请在 §5.13 正式声明该字段后回来只认正式键。

用法：
  python tools/validate_content.py [--root <项目根>] [--json <输出文件>] [--quiet]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from typing import Any, Iterable

# --------------------------------------------------------------------------
# 0 常量：全部来自计划书 §05 与三份契约，禁止在别处重复定义
# --------------------------------------------------------------------------

MICRO = 1_000_000                    # 1 Q_s = 1e6 μQ_s；ppm 刻度
# 裁定 R-SCALE-01（docs/18）：1 U = 1e9 μU，货币刻度与数量刻度/ppm 刻度**不再相同**。
# MICRO 原本同时兼任这三者，R-SCALE-01 之后只保留「数量与 ppm」两个身份；
# 凡是「μQ_s → μU」的换算必须走 BASE_PRICE_UU_PER_UQS，不能再用 MICRO 蒙混过关。
U_SCALE = 1_000_000_000                  # jw_units.gd U_SCALE
BASE_PRICE_UU_PER_QS = 1_000_000_000     # jw_units.gd BASE_PRICE（INV-148）
BASE_PRICE_UU_PER_UQS = BASE_PRICE_UU_PER_QS // MICRO   # == 1000 μU / μQ_s
BASE_YEAR_GDP_UU = 100_000_000_000       # 计划书 §05：基年全年名义 GDP = 100 U
GOV_DEBT_UU = 50_000_000_000             # 计划书 §05：政府债务 50 U
GOV_CASH_UU = 2_000_000_000              # 计划书 §05：国库现金 2 U
ANNUAL_RECEIPTS_UU = 20_000_000_000      # 计划书 §05：全年收入 20 U
ANNUAL_EXPEND_UU = 22_000_000_000        # 计划书 §05：全年支出 22 U（含利息、不含还本）
ANNUAL_DEFICIT_UU = 2_000_000_000        # 计划书 §05：赤字 2 U
TOTAL_POP = 24_000_000               # 计划书 §05：总人口 2400 万
REGION_POP = {                       # 计划书 §05：四地区人口
    "region.beiyuan": 9_000_000,
    "region.zhongzhou": 7_000_000,
    "region.haijia": 5_000_000,
    "region.xiling": 3_000_000,
}
WAGE_STEP_MAX_PPM = 20_000           # param.wage_step_max_ppm：工资单季调整上限 ±2%
UNEMP_TARGET_PPM = 80_000            # 计划书 §05：失业率 8%（分母为劳动力）
UNEMP_TOL_PPM = 500                  # 11 号文件 §5.11：唯一允许的非零容差
INDEX_BASE_PPM = 1_000_000           # 计划书 §05：民生基线指数 = 100
AMOUNT_MAX = 4_000_000_000_000_000       # 11 号文件 §5.2
QTY_MAX = 1_000_000_000_000
JSON_SAFE_INT = 2 ** 53              # 11 号文件 §3

REGIONS = ["region.beiyuan", "region.zhongzhou", "region.haijia", "region.xiling"]
SECTORS = ["sector.agri", "sector.manu", "sector.energy", "sector.services"]
AGES = ["minor", "working", "elder"]
SKILLS = ["low", "mid", "high"]
BLOCS = ["bloc.agri_coop", "bloc.business", "bloc.labor_public"]
POLICY_IDS = [f"policy.P{i:02d}" for i in range(1, 13)]
EVENT_IDS = [f"event.E{i:02d}" for i in range(1, 13)]
SHOCK_IDS = [f"shock.S{i:02d}" for i in range(1, 4)]
CELL_IDS = [f"cell.{r.split('.')[1]}.{s.split('.')[1]}" for r in REGIONS for s in SECTORS]
PUBSERV_IDS = [f"pubserv.{r.split('.')[1]}" for r in REGIONS]
GROUP_IDS = [
    f"group.{r.split('.')[1]}.{a}.{k}" for r in REGIONS for a in AGES for k in SKILLS
]

PAYMENT_LINES = [
    "debt_service", "public_wages", "statutory_transfers", "service_opex",
    "project_contracts", "procurement", "subsidies", "discretionary",
]
EXPENDITURE_LINES = [
    "public_wages", "statutory_transfers", "procurement", "project_contracts",
    "service_opex", "subsidies", "discretionary", "interest",
]
RECEIPT_LINES = ["income_tax", "profit_tax", "other"]

# 11 号文件 §5.12 效果落点白名单
EFFECT_TARGET_WHITELIST = {
    "state.region.grid_capacity_pending_uqs_per_q",
    "state.region.housing_pending_units",
    "state.region.irrigation_index_pending_ppm",
    "state.region.port_capacity_pending_uqs_per_q",
    "state.cell.capacity_pending_uqs_per_q",
    "state.pubserv.capacity_pending_uqs_per_q",
    "state.pubserv.teachers_persons",
    "state.pubserv.health_staff_persons",
    "state.policy.params_ppm",
    "state.policy.params_uu",
    "state.gov.tax_capacity_ppm",
    "state.politics.admin_capacity_ppm",
    "state.group.education_cohort_persons",
}
# 11 号文件 §5.13 事件可写白名单
EVENT_TARGET_WHITELIST = {
    "state.group.expectation_ppm",
    "state.group.trust_ppm",
    "state.group.support_ppm",
    "state.bloc.org_power_ppm",
    "state.bloc.stance_ppm",
    "state.politics.admin_capacity_ppm",
}
# 11 号文件 §5.14 冲击可写白名单
SHOCK_TARGET_WHITELIST = {
    "state.world.export_demand_ppm",
    "state.world.import_price_ppm",
    "state.world.credit_limit_uu",
    "state.world.sovereign_rate_ppm_per_q",
    "state.world.delivery_capacity_uqs",
}
SHOCK_CHANNELS = ["export_demand", "import_price", "external_credit"]
COMPARE_OPS = {"lt", "le", "eq", "ne", "ge", "gt"}
SOURCE_TYPES = {"observed", "literature", "design_assumption", "derived"}
CONFIDENCES = {"low", "medium", "high"}

# 计划书 §10 P04 的逐项数值（测试夹具，必须精确对上）
P04_SPEC = {
    # 裁定 R-SCALE-01：1 U = 1e9 μU，故 4 U = 4_000_000_000 μU。
    # 数量（μQ）与季度数不随货币刻度变化。
    "one_off_uu": 4_000_000_000,
    "per_quarter_uu": 500_000_000,
    "planned_quarters": 8,
    "spend_lines_uu_per_q": {
        "import_equipment": 200_000_000,
        "domestic_material": 100_000_000,
        "construction_service": 200_000_000,
    },
    "opex_per_q_uu": 20_000_000,
    "capacity_delta_uqs_per_q": 10_000_000,   # 10 单位电力服务 = 10 Q_energy/季
}

# 11 号文件 §2 规定的内容包布局（相对 content/）
REQUIRED_FILES = [
    "scenarios/chengwan/scenario.json",
    "scenarios/chengwan/io_table.json",
    "scenarios/chengwan/regions.json",
    "scenarios/chengwan/population_init.json",
    "scenarios/chengwan/cells_init.json",
    "scenarios/chengwan/pubserv_init.json",
    "scenarios/chengwan/government_init.json",
    "scenarios/chengwan/politics_init.json",
    "scenarios/chengwan/assertions.json",
    "parameters/params_core.json",
    "parameters/registry.json",          # §5.16 生成产物；§2 布局把它列为固定文件
]
REQUIRED_FILES += [f"policies/policy_P{i:02d}.json" for i in range(1, 13)]
REQUIRED_FILES += [f"events/event_E{i:02d}.json" for i in range(1, 13)]
REQUIRED_FILES += [f"shocks/shock_S{i:02d}.json" for i in range(1, 4)]

ID_PATTERNS = {
    "region_id": re.compile(r"^region\.(beiyuan|zhongzhou|haijia|xiling)$"),
    "sector_id": re.compile(r"^sector\.(agri|manu|energy|services)$"),
    "cell_id": re.compile(r"^cell\.(beiyuan|zhongzhou|haijia|xiling)\.(agri|manu|energy|services)$"),
    "pubserv_id": re.compile(r"^pubserv\.(beiyuan|zhongzhou|haijia|xiling)$"),
    "group_id": re.compile(r"^group\.(beiyuan|zhongzhou|haijia|xiling)\.(minor|working|elder)\.(low|mid|high)$"),
    "policy_id": re.compile(r"^policy\.P(0[1-9]|1[0-2])$"),
    "event_id": re.compile(r"^event\.E(0[1-9]|1[0-2])$"),
    "shock_id": re.compile(r"^shock\.S0[1-3]$"),
    "param_id": re.compile(r"^param\.[a-z][a-z0-9_]*$"),
    "bloc_id": re.compile(r"^bloc\.(agri_coop|business|labor_public)$"),
    "bond_id": re.compile(r"^bond\.q(-?[0-9]{1,3})_[0-9]{2}$"),
    "scenario_id": re.compile(r"^scenario\.[a-z][a-z0-9_]*$"),
    "paramset_id": re.compile(r"^paramset\.[a-z][a-z0-9_]*$"),
}
KEY_NAME_RE = re.compile(r"^[a-z][a-z0-9_]*$")
ANY_ID_RE = re.compile(r"^[a-z][a-z0-9_]*(\.[a-zA-Z0-9_]+)*$")

# 字段后缀 → 必须是整数（10 号文件 §0.2）
INT_SUFFIXES = (
    "_uu", "_uqs", "_ppm", "_persons", "_units", "_q", "_count", "_mask",
    "_uu_per_qs", "_uqs_per_q", "_uqs_per_qs", "_persons_per_qs", "_uqe",
    "_ppmuu", "_uu_per_person_q", "_uu_per_unit_q", "_ppm_per_q",
)

SEVERITY_ORDER = {"ERROR": 0, "WARN": 1, "INFO": 2}


# --------------------------------------------------------------------------
# 1 发现记录
# --------------------------------------------------------------------------

@dataclass
class Finding:
    severity: str
    code: str
    file: str
    pointer: str
    message: str
    expected: str = ""
    actual: str = ""
    fix: str = ""

    def render(self) -> str:
        head = f"[{self.severity}] {self.code}  {self.file}{'  ' + self.pointer if self.pointer else ''}"
        lines = [head, f"    {self.message}"]
        if self.expected or self.actual:
            lines.append(f"    期望: {self.expected or '-'}")
            lines.append(f"    实际: {self.actual or '-'}")
        if self.fix:
            lines.append(f"    修复: {self.fix}")
        return "\n".join(lines)


class Report:
    def __init__(self) -> None:
        self.findings: list[Finding] = []

    def add(self, severity: str, code: str, file: str, pointer: str, message: str,
            expected: Any = "", actual: Any = "", fix: str = "") -> None:
        # 路径统一成仓库相对形式，方便直接点开
        if not file.startswith(("content/", "docs/", "tests/", "tools/")):
            file = "content/" + file
        self.findings.append(Finding(
            severity, code, file, pointer, message,
            "" if expected == "" else str(expected),
            "" if actual == "" else str(actual),
            fix,
        ))

    def err(self, *a: Any, **kw: Any) -> None:
        self.add("ERROR", *a, **kw)

    def warn(self, *a: Any, **kw: Any) -> None:
        self.add("WARN", *a, **kw)

    def info(self, *a: Any, **kw: Any) -> None:
        self.add("INFO", *a, **kw)

    def count(self, severity: str) -> int:
        return sum(1 for f in self.findings if f.severity == severity)


# --------------------------------------------------------------------------
# 2 JSON 方言层：浮点 / null / 重复键 / 大整数 / 行尾 / BOM
# --------------------------------------------------------------------------

class FloatLiteral:
    """json.loads 的 parse_float 钩子产物；一旦出现在树里即违反 int64 定点纪律。"""

    def __init__(self, raw: str) -> None:
        self.raw = raw

    def __repr__(self) -> str:
        return f"<float {self.raw}>"


class DupDict(dict):
    """记录同一对象内的重复键（标准 json 会静默丢弃先出现的那一个）。"""
    __slots__ = ("dup_keys",)


def _pairs_hook(pairs: list[tuple[str, Any]]) -> DupDict:
    d = DupDict()
    dups: list[str] = []
    for k, v in pairs:
        if k in d:
            dups.append(k)
        d[k] = v
    d.dup_keys = dups          # type: ignore[attr-defined]
    return d


def ptr_escape(token: str) -> str:
    return token.replace("~", "~0").replace("/", "~1")


def scan_raw_text(text: str) -> dict[str, list[tuple[int, str]]]:
    """在字符串之外扫描原始字面量：浮点、-0、下划线数字、超安全区整数。

    返回 {类别: [(行号, 片段)]}。行号比 JSON 指针更贴近「这一行怎么写错了」。
    """
    out: dict[str, list[tuple[int, str]]] = {
        "float": [], "negzero": [], "underscore": [], "bigint": [],
    }
    i, n = 0, len(text)
    line = 1
    in_str = False
    esc = False
    while i < n:
        ch = text[i]
        if ch == "\n":
            line += 1
            i += 1
            continue
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
            i += 1
            continue
        if ch == "-" or ch.isdigit():
            j = i
            if text[j] == "-":
                j += 1
            start = i
            has_dot = has_exp = has_us = False
            while j < n:
                c = text[j]
                if c.isdigit():
                    j += 1
                elif c == "." and not has_dot and not has_exp:
                    has_dot = True
                    j += 1
                elif c in "eE" and not has_exp:
                    has_exp = True
                    j += 1
                    if j < n and text[j] in "+-":
                        j += 1
                elif c == "_":
                    has_us = True
                    j += 1
                else:
                    break
            tok = text[start:j]
            if has_us:
                out["underscore"].append((line, tok))
            elif has_dot or has_exp:
                out["float"].append((line, tok))
            else:
                if tok == "-0":
                    out["negzero"].append((line, tok))
                try:
                    if abs(int(tok)) > JSON_SAFE_INT:
                        out["bigint"].append((line, tok))
                except ValueError:
                    pass
            i = j
            continue
        i += 1
    return out


# --------------------------------------------------------------------------
# 3 加载
# --------------------------------------------------------------------------

@dataclass
class ContentFile:
    rel: str                      # 相对 content/ 的路径，正斜杠
    abspath: str
    data: Any = None
    ok: bool = False
    text: str = ""
    schema_kind: str = ""
    ids_declared: dict[str, str] = field(default_factory=dict)   # id -> pointer


def load_files(content_dir: str, rep: Report) -> list[ContentFile]:
    files: list[ContentFile] = []
    for dirpath, _dirnames, filenames in os.walk(content_dir):
        for fn in sorted(filenames):
            if not fn.endswith(".json"):
                continue
            ap = os.path.join(dirpath, fn)
            rel = os.path.relpath(ap, content_dir).replace("\\", "/")
            cf = ContentFile(rel=rel, abspath=ap)
            files.append(cf)
            with open(ap, "rb") as fh:
                raw = fh.read()
            if raw.startswith(b"\xef\xbb\xbf"):
                rep.err("E_FILE_FORMAT", rel, "", "文件带 UTF-8 BOM。",
                        "UTF-8 无 BOM（11 号文件 §3）", "开头有 EF BB BF",
                        "以 UTF-8 无 BOM 重存；BOM 会让 content_hash 与逐字节对比失真。")
                raw = raw[3:]
            if b"\r\n" in raw:
                rep.err("E_FILE_FORMAT", rel, "", "文件含 CRLF 换行。",
                        "LF 换行（11 号文件 §3）", f"出现 {raw.count(b'\r\n')} 处 CRLF",
                        "统一转成 LF；否则同一内容在不同平台哈希不同。")
            if not raw.endswith(b"\n"):
                rep.err("E_FILE_FORMAT", rel, "", "文件末尾缺少换行。",
                        "末尾单个 LF", "无换行结尾", "在文件末尾补一个 \\n。")
            elif raw.endswith(b"\n\n"):
                rep.err("E_FILE_FORMAT", rel, "", "文件末尾有多个空行。",
                        "末尾单个 LF", "末尾 >= 2 个换行", "只保留一个结尾换行。")
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError as exc:
                rep.err("E_FILE_FORMAT", rel, "", f"不是合法 UTF-8：{exc}",
                        "UTF-8", "解码失败", "以 UTF-8 重存。")
                continue
            cf.text = text

            scans = scan_raw_text(text)
            for line, tok in scans["float"]:
                rep.err("E_FLOAT_IN_CONTENT", rel, f"line {line}",
                        "出现浮点字面量，违反 int64 定点纪律。",
                        "整数字面量", tok,
                        "改写成整数：金额用 μU、数量用 μQ_s、比率用 ppm。")
            for line, tok in scans["negzero"]:
                rep.err("E_FLOAT_IN_CONTENT", rel, f"line {line}",
                        "出现负零字面量 -0。", "0", tok, "写成 0。")
            for line, tok in scans["underscore"]:
                rep.err("E_FILE_FORMAT", rel, f"line {line}",
                        "数值里出现下划线分隔符，JSON 不支持。",
                        "纯数字（可读性用同级 _note_<field> 注释键）", tok,
                        "去掉下划线，并在同级加 \"_note_<field>\": \"N U\"。")
            for line, tok in scans["bigint"]:
                rep.err("E_INT_RANGE", rel, f"line {line}",
                        "整数绝对值超过 2^53 的 JSON 互操作安全区。",
                        f"|v| <= {JSON_SAFE_INT}", tok,
                        "拆分量纲或复核单位；裁定 R-SCALE-01 后 AMOUNT_MAX = 4e15，距 2^53 只剩约 2.25 倍裕度，撞上 2^53 说明单位写错了一个刻度。")

            try:
                cf.data = json.loads(text, parse_float=FloatLiteral,
                                     parse_constant=FloatLiteral,
                                     object_pairs_hook=_pairs_hook)
                cf.ok = True
            except json.JSONDecodeError as exc:
                rep.err("E_FILE_FORMAT", rel, f"line {exc.lineno} col {exc.colno}",
                        f"JSON 解析失败：{exc.msg}", "合法 JSON", "解析中止",
                        "修好语法后重跑；解析失败的文件不参与后续任何校验。")
    return files


# --------------------------------------------------------------------------
# 4 树遍历检查：null / 浮点残留 / 重复键 / 键名 / 后缀类型
# --------------------------------------------------------------------------

def walk(node: Any, pointer: str = "", skip_notes: bool = False) -> Iterable[tuple[str, Any]]:
    yield pointer, node
    if isinstance(node, dict):
        for k, v in node.items():
            if skip_notes and k.startswith("_note"):
                continue          # 注释键整棵子树不参与语义校验（11 号文件 §3）
            yield from walk(v, f"{pointer}/{ptr_escape(k)}", skip_notes)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk(v, f"{pointer}/{i}", skip_notes)


def check_tree_dialect(cf: ContentFile, rep: Report, unknown_prefixes: list[str]) -> None:
    def under_unknown(ptr: str) -> bool:
        return any(ptr == p or ptr.startswith(p + "/") for p in unknown_prefixes)

    # 第一遍：null / 浮点 / 重复键 —— 注释子树也要查（方言规则对全文件生效）
    for ptr, node in walk(cf.data):
        if isinstance(node, FloatLiteral):
            rep.err("E_FLOAT_IN_CONTENT", cf.rel, ptr or "/",
                    "该位置的值被解析成浮点数。", "整数", node.raw,
                    "改成整数表示（μU / μQ_s / ppm）。")
        elif node is None:
            rep.err("E_NULL_NOT_ALLOWED", cf.rel, ptr or "/",
                    "用 null 表示「未填」。", "显式给值，或整键省略", "null",
                    "null 与 0 的混淆是最常见的账目缺陷；删键或给真值。")
        if isinstance(node, dict):
            for dk in getattr(node, "dup_keys", []) or []:
                rep.err("E_FILE_FORMAT", cf.rel, f"{ptr}/{ptr_escape(dk)}",
                        "同一对象内出现重复键，标准 JSON 会静默丢弃先出现的值。",
                        "键唯一", f"重复键 {dk!r}", "删掉重复项，确认保留的是哪一个值。")

    # 第二遍：键名与后缀语义 —— 注释子树是自由文本，不参与
    for ptr, node in walk(cf.data, skip_notes=True):
        if isinstance(node, dict):
            for k in node:
                kptr = f"{ptr}/{ptr_escape(k)}"
                if under_unknown(kptr):
                    continue
                if k.startswith("_note"):
                    continue
                if k in GENERATED_ORIGIN_KEYS and cf.schema_kind in GENERATED_KINDS:
                    # 11 号文件 §5.16 的示例结构里，卡片的出处就写作 `_origin_file` /
                    # `_origin_pointer`。§3 的 snake_case 规则与 §5.16 的字段名在此相撞，
                    # 按「专条优先于通则」取 §5.16：这两个键是契约钦定的，且只在生成产物里合法。
                    continue
                if KEY_NAME_RE.match(k):
                    continue
                if k == "*" or ANY_ID_RE.match(k):
                    continue
                rep.err("E_KEY_NAMING", cf.rel, kptr,
                        "键名既不是英文 snake_case，也不是合法稳定 ID。",
                        "^[a-z][a-z0-9_]*$ 或稳定 ID", repr(k),
                        "改成 snake_case；展示文案放在值里，不放在键名里。")
        # 后缀 → 整数
        if isinstance(node, dict):
            for k, v in node.items():
                if k.startswith("_note"):
                    continue
                if not k.endswith(INT_SUFFIXES):
                    continue
                kptr = f"{ptr}/{ptr_escape(k)}"
                if under_unknown(kptr):
                    continue
                bad = None
                if isinstance(v, bool):
                    bad = "bool"
                elif isinstance(v, int):
                    pass
                elif isinstance(v, list):
                    if any(isinstance(x, bool) or not isinstance(x, int) for x in v):
                        bad = "数组含非整数元素"
                elif isinstance(v, dict):
                    for kk, vv in v.items():
                        if kk.startswith("_note"):
                            continue
                        if isinstance(vv, bool) or (not isinstance(vv, int)
                                                    and not isinstance(vv, (dict, list))):
                            bad = f"映射项 {kk} 非整数"
                            break
                else:
                    bad = type(v).__name__
                if bad:
                    rep.err("E_FLOAT_IN_CONTENT", cf.rel, kptr,
                            f"字段后缀声明它是整数量（{k.rsplit('_', 1)[-1]}），但值不是整数。",
                            "int64 整数", bad,
                            "按 10 号文件 §0.2 的后缀语义改成整数。")


# --------------------------------------------------------------------------
# 5 schema 定义（11 号文件 §5）
# --------------------------------------------------------------------------

# 每个 schema：{字段: (必填?, 类型串)}；类型串仅用于报错文案。
SCHEMAS: dict[str, dict[str, tuple[bool, str]]] = {
    "scenario": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "scenario_id": (True, "str"), "label_zh": (True, "str"),
        "reference_year": (True, "int"), "unit_declaration": (True, "object"),
        "horizon_q": (True, "int"), "param_set_ref": (True, "str"),
        "param_set_version": (True, "int"), "root_seed": (True, "int"),
        "includes": (True, "object"), "enabled_policies": (True, "array"),
        "baseline_policies": (True, "array"),   # R-BASELINE-01：开局现行制度
        "enabled_events": (True, "array"), "enabled_shocks": (True, "array"),
        "season_factor_ppm": (True, "object"), "prices_init": (True, "object"),
        "world_init": (True, "object"), "mandate_goals": (True, "array"),
        "total_cash_uu": (True, "int"), "notes_zh": (True, "str"),
    },
    "io_table": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "sectors": (True, "array"), "io_coeff_uqs_per_qs": (True, "object"),
        "labor_coeff_persons_per_qs": (True, "object"),
        "energy_coeff_uqs_per_qs": (True, "array"), "spoilage_ppm": (True, "array"),
        "depreciation_ppm_per_q": (True, "array"),
        "capacity_per_capital_uu_ppm": (True, "array"),
        "emission_ppm": (True, "array"), "storable": (True, "array"),
        "capital_goods_split_ppm": (True, "array"),   # R-INVEST-01
    },
    "regions": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "regions": (True, "array"),
    },
    "population_init": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "groups": (True, "array"), "demography_rates": (True, "object"),
    },
    "cells_init": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "cells": (True, "array"),
    },
    "pubserv_init": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "units": (True, "array"),
    },
    "government_init": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "gov": (True, "object"), "annual_plan": (True, "object"),
        "payment_priority": (True, "array"), "bonds": (True, "array"),
        "invpool": (True, "object"),
    },
    "politics_init": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "seats_total": (True, "int"), "seats_gov": (True, "int"),
        "next_election_q": (True, "int"), "next_budget_review_q": (True, "int"),
        "admin_capacity_ppm": (True, "int"), "legal_authority_mask": (True, "int"),
        "blocs": (True, "array"), "stance_ppm": (True, "object"),
    },
    "assertions": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "checks": (True, "array"),
    },
    "policy_definition": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "policy_id": (True, "str"), "label_zh": (True, "str"),
        "problem_statement_zh": (True, "str"), "kind": (True, "str"),
        "legal_authority": (True, "object"), "player_params": (True, "array"),
        "cost": (True, "object"), "preconditions": (True, "array"),
        "lag": (True, "object"), "effect": (True, "object"),
        # effect_chain：11 号 §5.12 的字段表里没有它，但计划书 §09（文档优先级第 1 位）
        # 要求「每项至少 1 条完整反馈链」，本工具下方也据此把「缺 effect_chain」判为 ERROR。
        # 两者并存时 additionalProperties:false 会让任何正确文件都无法通过（原 OQ-V03）。
        # 按优先级「计划书 > docs/18 > 12 > 11 > 10」，缺字段的一侧是 §5.12，故在此正式登记。
        # 这不是放水：字段仍为必填、仍要求 >= 4 环，additionalProperties:false 对其余键不变。
        "effect_chain": (True, "array"),
        "exit_rule": (True, "object"), "political_reaction": (True, "object"),
        "failure_paths": (True, "array"), "acceptance_tests": (True, "array"),
        "mechanism_ids": (True, "array"), "cooldown_q": (True, "int"),
        "toggle_cost_uu": (True, "int"), "ui_text_keys": (True, "object"),
    },
    "event_template": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "event_id": (True, "str"), "label_zh": (True, "str"),
        "trigger": (True, "object"), "effects": (True, "array"),
        "evidence_refs": (True, "array"), "report_template_id": (True, "str"),
        "kind": (True, "str"),
        # check_event 下方「每条后果必须有对手方或会计解释」（计划书 §13）无条件要求顶层
        # consequences 存在，缺失即 E_EVENT_EVIDENCE。本表原先不声明它，于是同一个工具
        # 一边强制要求该字段、一边用 additionalProperties:false 判它为 E_UNKNOWN_FIELD，
        # 两条规则不可能同时满足。这是校验器自身的不一致（要求先于 schema 登记而落下），
        # 不是内容层的缺陷：修法是让 schema 表承认这个被要求的字段，而不是撤回要求。
        # 声明为**可选**，使「缺失」仍由 check_event 报 E_EVENT_EVIDENCE（口径不变、不降级）。
        # 契约侧待办：11 号文件 §5.13 的 EventTemplate 键集合应同步补入 consequences。
        "consequences": (False, "array"),
    },
    "shock_definition": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "shock_id": (True, "str"), "label_zh": (True, "str"),
        "channel": (True, "str"), "targets": (True, "array"),
        "target_weights_ppm": (True, "array"), "arrival": (True, "object"),
        "magnitude_ppm": (True, "object"), "duration_q": (True, "object"),
        "onset_profile": (True, "str"), "decay_profile": (True, "str"),
        "rng_stream": (True, "str"), "log_fields": (True, "array"),
    },
    "parameter_set": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "param_set_id": (True, "str"), "param_set_version": (True, "int"),
        "cards": (True, "array"),
    },
    # 11 号文件 §5.16（裁定 R-SCHEMA-01）：生成产物，由 tools/build_param_registry.py 写出。
    # 它在 §5 的 schema_kind 闭集合表里（该表第 14 行），也在 §2 的文件布局里——
    # 契约原文：「`parameter_registry` 既要进本表（否则 E_SCHEMA_HEADER），
    # 也要进 §2 的文件布局（否则 E_CONTENT_LAYOUT）。只补一处的话文件仍然进不来。」
    "parameter_registry": {
        "schema_kind": (True, "str"), "schema_version": (True, "int"),
        "generated": (True, "int"), "tool": (True, "str"),
        "tool_version": (True, "int"), "summary": (True, "object"),
        "stats": (True, "object"), "files_scanned": (True, "array"),
        "files_skipped": (True, "array"),
        "contract_min_set_missing": (True, "array"),
        "near_miss_cards": (True, "array"), "findings": (True, "array"),
        "cards": (True, "array"),
    },
}

# §5.16：生成产物。校验它「是否与源文件一致」，不对它的内容做第二套语义校验
# （否则同一份数据有两套真理）。这个集合是所有「按源文件校验、不按内容校验」的开关。
GENERATED_KINDS = {"parameter_registry"}

# §5.16 示例结构钦定的两个下划线前缀键（只在生成产物内合法，见 check_tree_dialect）
GENERATED_ORIGIN_KEYS = {"_origin_file", "_origin_pointer"}

# 子对象的字段表（用于 additionalProperties:false 的第二层）
SUB_SCHEMAS: dict[str, list[str]] = {
    "regions.item": [
        "region_id", "label_zh", "population_persons", "adjacency",
        "logistics_cost_ppm", "migration_cost_uu", "housing_capacity_units",
        "housing_stock_units", "grid_capacity_uqs_per_q", "port_capacity_uqs_per_q",
        "irrigation_index_ppm", "construction_slots_total", "area_index",
        "emissions_stock_uqe", "env_exposure_ppm",
    ],
    "population.group": [
        "group_id", "population_persons", "participation_ppm", "employed_persons",
        "cash_uu", "deposit_uu", "housing_units_occupied", "support_out_weight_ppm",
        "service_access_ppm", "consumption_index_ppm", "living_index_ppm",
        "base_per_capita_real_income_uu", "expectation_ppm", "trust_ppm",
        "support_ppm", "bloc_affiliation_ppm",
        "base_real_consumption_uqs", "base_delivered_service_uqs",
    ],
    "gov": [
        "cash_uu", "arrears_uu", "tax_receivable_uu", "wip_uu", "capital_uu",
        "housing_uu", "tax_capacity_ppm", "credit_limit_domestic_uu",
        "service_opex_committed_uu",
    ],
    "annual_plan": [
        "receipts_uu", "expenditure_incl_interest_uu", "deficit_uu",
        "receipt_lines_uu", "expenditure_lines_uu",
    ],
    "bond": [
        "bond_id", "issue_q", "principal_initial_uu", "principal_outstanding_uu",
        "coupon_ppm_per_q", "maturity_q", "amortization", "holder",
    ],
    "parameter_card": [
        "parameter_id", "value", "unit", "source_type", "source_ref",
        "reference_year", "definition", "valid_range", "confidence",
        "calibration_note", "derivation_expr",
    ],
}

PARAM_CARD_REQUIRED = [
    "parameter_id", "value", "unit", "source_type", "source_ref",
    "reference_year", "definition", "valid_range", "confidence", "calibration_note",
]


def check_schema_shell(cf: ContentFile, rep: Report) -> list[str]:
    """顶层 schema 校验，返回「未知字段」的指针前缀列表。"""
    unknown_ptrs: list[str] = []
    d = cf.data
    if not isinstance(d, dict):
        rep.err("E_SCHEMA_HEADER", cf.rel, "/", "顶层不是 JSON 对象。",
                "object", type(d).__name__, "内容包每个文件顶层必须是对象。")
        return unknown_ptrs
    kind = d.get("schema_kind")
    ver = d.get("schema_version")
    if not isinstance(kind, str) or not kind:
        rep.err("E_SCHEMA_HEADER", cf.rel, "/schema_kind", "缺少顶层 schema_kind。",
                "已声明的 schema_kind 常量", repr(kind),
                "加上 schema_kind；它是迁移链的唯一依据。")
        return unknown_ptrs
    cf.schema_kind = kind
    if not isinstance(ver, int) or isinstance(ver, bool) or ver < 1:
        rep.err("E_SCHEMA_HEADER", cf.rel, "/schema_version",
                "schema_version 缺失或不是 >= 1 的整数。", "int >= 1", repr(ver),
                "补一个整数版本号，不要用语义化版本字符串。")
    if kind not in SCHEMAS:
        rep.err("E_SCHEMA_HEADER", cf.rel, "/schema_kind",
                "schema_kind 不在 11 号文件 §5 定义的类型集合内。",
                " / ".join(sorted(SCHEMAS)), repr(kind),
                "改成契约已定义的类型；新增类型必须先改契约并登记错误码。")
        return unknown_ptrs
    spec = SCHEMAS[kind]
    for fname, (req, typ) in spec.items():
        if req and fname not in d:
            rep.err("E_SCHEMA_HEADER", cf.rel, f"/{fname}",
                    f"缺少必填字段 {fname}。", typ, "缺失",
                    f"按 11 号文件 §5 的 {kind} schema 补齐。")
            continue
        if fname in d:
            v = d[fname]
            ok = {
                "int": lambda x: isinstance(x, int) and not isinstance(x, bool),
                "str": lambda x: isinstance(x, str),
                "object": lambda x: isinstance(x, dict),
                "array": lambda x: isinstance(x, list),
            }[typ](v)
            if not ok:
                rep.err("E_SCHEMA_HEADER", cf.rel, f"/{fname}",
                        f"字段 {fname} 类型不符。", typ, type(v).__name__,
                        "按 schema 改类型。")
    extra = [k for k in d if k not in spec and not k.startswith("_note")]
    if extra:
        for k in extra:
            unknown_ptrs.append(f"/{ptr_escape(k)}")
        rep.err("E_UNKNOWN_FIELD", cf.rel, "/",
                f"顶层出现 {len(extra)} 个 schema 未声明的键（additionalProperties: false）。",
                f"仅 {kind} schema 声明的键 + _note_* 注释键",
                ", ".join(sorted(extra)),
                "扩展字段要么改进契约后正式登记，要么改名为 _note_<field> 注释键；"
                "未声明的键会让「拼错字段名」被静默忽略（11 号文件 §3）。")
    return unknown_ptrs


def check_sub_object(cf: ContentFile, rep: Report, obj: Any, ptr: str,
                     allowed: list[str], label: str) -> None:
    if not isinstance(obj, dict):
        return
    extra = [k for k in obj if k not in allowed and not k.startswith("_note")]
    if extra:
        rep.err("E_UNKNOWN_FIELD", cf.rel, ptr,
                f"{label} 出现 {len(extra)} 个 schema 未声明的键。",
                "仅契约声明的键 + _note_*", ", ".join(sorted(extra)),
                "删除或改成 _note_<field>；schema 是第一道测试。")


# --------------------------------------------------------------------------
# 6 工具函数
# --------------------------------------------------------------------------

def as_int(v: Any) -> int | None:
    return v if isinstance(v, int) and not isinstance(v, bool) else None


def int_list(v: Any) -> list[int] | None:
    if isinstance(v, list) and v and all(isinstance(x, int) and not isinstance(x, bool) for x in v):
        return v
    return None


def get(d: Any, *path: str) -> Any:
    cur = d
    for p in path:
        if not isinstance(cur, dict) or p not in cur:
            return None
        cur = cur[p]
    return cur


def deep_find(node: Any, pred, ptr: str = "") -> Iterable[tuple[str, Any]]:
    if pred(node):
        yield ptr, node
    if isinstance(node, dict):
        for k, v in node.items():
            yield from deep_find(v, pred, f"{ptr}/{ptr_escape(k)}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from deep_find(v, pred, f"{ptr}/{i}")


def load_doc_ids(docs_dir: str, rep: Report) -> tuple[set[str], set[str]]:
    """从权威文档提取 (稳定变量 ID 全集, 测试 ID 全集)。"""
    var_ids: set[str] = set()
    vpath = os.path.join(docs_dir, "10_variable_dictionary.md")
    if os.path.isfile(vpath):
        txt = open(vpath, encoding="utf-8").read()
        for m in re.findall(r"`((?:state|flow|derived|log|content)\.[A-Za-z0-9_.]+)(?:\[\])?`", txt):
            var_ids.add(m.rstrip("."))
    else:
        rep.err("E_METRIC_UNKNOWN", "docs/10_variable_dictionary.md", "",
                "找不到变量字典，无法执行 V-EV-02（事件 metric 必须真实存在）。",
                "存在该文件", "缺失", "恢复文档后重跑；缺它则事件触发器无法被校验。")
    test_ids: set[str] = set()
    for name in ("30_quality_gates.md", "31_adversarial_tests.md"):
        p = os.path.join(docs_dir, name)
        if os.path.isfile(p):
            txt = open(p, encoding="utf-8").read()
            for m in re.findall(r"\bT-[A-Z]-[A-Z0-9][A-Z0-9\-]*", txt):
                test_ids.add(m.rstrip("-"))
    return var_ids, test_ids


def split_largest_remainder(total: int, weights: list[int]) -> list[int]:
    W = sum(weights)
    if W == 0:
        return [0] * len(weights)
    base = [(total * w) // W for w in weights]
    rem = [total * w - b * W for w, b in zip(weights, base)]
    r = total - sum(base)
    order = sorted(range(len(weights)), key=lambda i: (-rem[i], i))
    for i in order[:r]:
        base[i] += 1
    return base


# --------------------------------------------------------------------------
# 7 V-SCEN：Scenario 根文件（11 号文件 §5.4）
# --------------------------------------------------------------------------

def check_scenario(cf: ContentFile, rep: Report, index: dict) -> None:
    d = cf.data
    sid = d.get("scenario_id")
    if isinstance(sid, str) and not ID_PATTERNS["scenario_id"].match(sid):
        rep.err("E_ID_FORMAT", cf.rel, "/scenario_id", "scenario_id 不符合命名规则。",
                ID_PATTERNS["scenario_id"].pattern, sid, "改成 scenario.<snake_name>。")

    ud = d.get("unit_declaration")
    # R-SCALE-01（docs/18）之后这四个常量**不再同值**：1e9 / 1e6 / 1e6 / 1e9。
    # 11 号文件 §5.4 的字段表已因此由一行拆成三行，逐个对着 jw_units.gd 的常量比。
    expect_ud = {"money_micro_per_unit": U_SCALE, "quantity_micro_per_qs": MICRO,
                 "ppm_scale": MICRO, "base_price_uu_per_qs": BASE_PRICE_UU_PER_QS}
    if isinstance(ud, dict):
        for k, ev in expect_ud.items():
            av = ud.get(k)
            if av != ev:
                rep.err("E_UNIT_MISMATCH", cf.rel, "/unit_declaration/" + k,
                        "单位声明与引擎常量不等，剧本必须在载入期就死掉。",
                        ev, repr(av), "改成 " + str(ev)
                        + "；这四个常量存在的唯一目的就是拦住换算错的剧本，"
                        "R-SCALE-01 之后它们不再同值（1e9 / 1e6 / 1e6 / 1e9）。")
        check_sub_object(cf, rep, ud, "/unit_declaration", list(expect_ud), "unit_declaration")

    hz = as_int(d.get("horizon_q"))
    if hz not in (40, 120):
        rep.err("E_SCHEMA_HEADER", cf.rel, "/horizon_q", "horizon_q 取值非法。",
                "40 或 120", repr(d.get("horizon_q")),
                "首版 40 季；压测 120 季由 --horizon 覆盖，不改本文件（OQ-210）。")

    sf = d.get("season_factor_ppm")
    if isinstance(sf, dict):
        for k, v in sf.items():
            if k.startswith("_note"):
                continue
            arr = int_list(v)
            if arr is None or len(arr) != 4:
                rep.err("E_SCHEMA_HEADER", cf.rel, "/season_factor_ppm/" + k,
                        "季节系数必须是 4 个整数。", "int[4]", repr(v),
                        "按四个季度给出 ppm 份额。")
                continue
            s = sum(arr)
            if s != MICRO:
                rep.err("E_SCHEMA_HEADER", cf.rel, "/season_factor_ppm/" + k,
                        "季节系数四季合计不等于 1 000 000（INV-042）。",
                        MICRO, str(s) + "（差 " + str(s - MICRO) + "）",
                        "调整某一季使合计精确为 1000000；年度额按最大余数法拆季后必须精确等于年计划。")
            else:
                index.setdefault("season", {})[k] = arr

    pi = d.get("prices_init")
    if isinstance(pi, dict):
        for key in ("sector_uu_per_qs", "base_uu_per_qs"):
            arr = int_list(pi.get(key))
            if arr is None or len(arr) != 4:
                rep.err("E_SCHEMA_HEADER", cf.rel, "/prices_init/" + key,
                        "价格数组必须是 4 个整数（按部门下标 0..3）。", "int[4]",
                        repr(pi.get(key)), "补齐四个部门的价格。")
            else:
                # INV-148 的目标值随 R-SCALE-01 由 1e6 改为 1e9（docs/10 §14.12、
                # docs/11 §5.4 与 §7.1）。价格的基数是 BASE_PRICE，不是 ppm 基数 MICRO。
                for i, v in enumerate(arr):
                    if v != BASE_PRICE_UU_PER_QS:
                        rep.err("E_UNIT_MISMATCH", cf.rel,
                                "/prices_init/" + key + "/" + str(i),
                                "基年 " + SECTORS[i] + " 价格不等于 "
                                + str(BASE_PRICE_UU_PER_QS) + "（INV-148）。",
                                BASE_PRICE_UU_PER_QS, v,
                                "基年名义必须等于实际，四部门价格一律 "
                                + str(BASE_PRICE_UU_PER_QS) + "。")
        wage = int_list(pi.get("wage_uu_per_person_q"))
        if wage is None or len(wage) != 3:
            rep.err("E_SCHEMA_HEADER", cf.rel, "/prices_init/wage_uu_per_person_q",
                    "工资率必须是 3 个整数（按技能档 low/mid/high）。", "int[3]",
                    repr(pi.get("wage_uu_per_person_q")), "补齐三档。")
        else:
            for i, v in enumerate(wage):
                if v <= 0:
                    rep.err("E_RANGE", cf.rel,
                            "/prices_init/wage_uu_per_person_q/" + str(i),
                            "工资率必须 > 0。", "> 0", v, "由剧本作者给出正值。")
            # 这条检查的谓词是「±2% 的有界平滑恒为 0」，不是某个写死的数字。
            # mul_ppm(w, param.wage_step_max_ppm == 20000) == idiv_floor(w, 50)，
            # 故它恒为 0 当且仅当 max(wage) < 50。原先写的 `<= 3` 是旧刻度下对同一谓词的
            # 粗略代用值（R-SCALE-01 把工资量级抬高了 1000 倍），照抄会让检查失去意义。
            if max(wage) * WAGE_STEP_MAX_PPM // MICRO == 0:
                rep.warn("E_RANGE", cf.rel, "/prices_init/wage_uu_per_person_q",
                         "工资率撞上记账单位分辨率下限，INV-067 的有界平滑（±"
                         + str(WAGE_STEP_MAX_PPM) + " ppm）对这组取值永远算出 0。",
                         "每档 >= " + str(MICRO // WAGE_STEP_MAX_PPM) + " μU/人/季", wage,
                         "这是单位定义问题而非填错；须在契约层决定是否细化货币最小单位，"
                         "不要在剧本里私自改口径。")
        rent = int_list(pi.get("housing_rent_uu_per_unit_q"))
        if rent is None or len(rent) != 4:
            rep.err("E_SCHEMA_HEADER", cf.rel, "/prices_init/housing_rent_uu_per_unit_q",
                    "住房租金必须是 4 个整数（按地区下标）。", "int[4]",
                    repr(pi.get("housing_rent_uu_per_unit_q")), "补齐四个地区。")
        check_sub_object(cf, rep, pi, "/prices_init",
                         ["sector_uu_per_qs", "base_uu_per_qs",
                          "wage_uu_per_person_q", "housing_rent_uu_per_unit_q"],
                         "prices_init")

    wi = d.get("world_init")
    if isinstance(wi, dict):
        fx = as_int(wi.get("fx_rate_ppm"))
        if fx != MICRO:
            rep.err("E_UNIT_MISMATCH", cf.rel, "/world_init/fx_rate_ppm",
                    "首版固定汇率必须恒为 1 000 000（INV-105）。", MICRO,
                    repr(wi.get("fx_rate_ppm")),
                    "改回 1000000；玩家不能直接操纵汇率（计划书 §03）。")
        for key in ("export_demand_ppm", "import_price_ppm", "delivery_capacity_uqs"):
            arr = int_list(wi.get(key))
            if arr is None or len(arr) != 4:
                if not (isinstance(wi.get(key), list) and len(wi.get(key)) == 4):
                    rep.err("E_SCHEMA_HEADER", cf.rel, "/world_init/" + key,
                            "必须是 4 个整数（按部门下标）。", "int[4]", repr(wi.get(key)),
                            "补齐四部门。")
        index["world_cash_uu"] = as_int(wi.get("cash_uu"))
        check_sub_object(cf, rep, wi, "/world_init",
                         ["fx_rate_ppm", "export_demand_ppm", "import_price_ppm",
                          "delivery_capacity_uqs", "credit_limit_uu",
                          "sovereign_rate_ppm_per_q", "cash_uu", "base_export_uqs",
                          "import_share_ppm"], "world_init")

    for key, full, code in (("enabled_policies", POLICY_IDS, "E_POLICY_COUNT"),
                            ("enabled_events", EVENT_IDS, "E_EVENT_COUNT"),
                            ("enabled_shocks", SHOCK_IDS, "E_SHOCK_COUNT")):
        v = d.get(key)
        if not isinstance(v, list):
            continue
        missing = [x for x in full if x not in v]
        unknown = [x for x in v if x not in full]
        if missing:
            rep.err(code, cf.rel, "/" + key, "首版必须全列，缺项即内容不齐。",
                    str(len(full)) + " 项全集", "缺 " + ", ".join(missing),
                    "补齐；计划书 §03 明确首版 12 政策 / 12 事件 / 3 冲击缺一不可。")
        if unknown:
            rep.err("E_ID_FORMAT", cf.rel, "/" + key, "出现不在全集内的 ID。",
                    full[0] + " .. " + full[-1], ", ".join(str(u) for u in unknown), "删除或改正。")

    inc = d.get("includes")
    if isinstance(inc, dict):
        base = os.path.dirname(cf.rel)
        for k, v in inc.items():
            if k.startswith("_note") or not isinstance(v, str):
                continue
            target = (base + "/" + v) if base else v
            if target not in index["by_rel"]:
                rep.err("E_NOT_FOUND", cf.rel, "/includes/" + k,
                        "includes 指向的剧本文件不存在（悬空引用）。", target, "文件缺失",
                        "补齐该文件或修正 includes；载入器按 includes 逐个读，缺一个即整份剧本无法加载。")
            else:
                index.setdefault("included", set()).add(target)

    index["total_cash_declared"] = as_int(d.get("total_cash_uu"))
    psr = d.get("param_set_ref")
    if isinstance(psr, str) and not ID_PATTERNS["paramset_id"].match(psr):
        rep.err("E_ID_FORMAT", cf.rel, "/param_set_ref", "param_set_ref 不符合命名规则。",
                ID_PATTERNS["paramset_id"].pattern, psr, "改成 paramset.<snake_name>。")
    index["param_set_ref"] = psr
    index["param_set_version"] = as_int(d.get("param_set_version"))


# --------------------------------------------------------------------------
# 8 V-IO：投入产出表（11 号文件 §5.5）
# --------------------------------------------------------------------------

def check_io_table(cf: ContentFile, rep: Report, index: dict) -> None:
    d = cf.data
    if d.get("sectors") != SECTORS:
        rep.err("E_SCHEMA_HEADER", cf.rel, "/sectors",
                "部门顺序是契约的一部分，不得重排（10 号文件 §0.5）。",
                SECTORS, d.get("sectors"), "改回 agri / manu / energy / services 的固定顺序。")

    io = d.get("io_coeff_uqs_per_qs")
    coeff: dict = {}
    if isinstance(io, dict):
        for r in SECTORS:
            row = io.get(r)
            if not isinstance(row, dict):
                rep.err("E_IO_NEGATIVE", cf.rel, "/io_coeff_uqs_per_qs/" + r,
                        "缺少行部门或不是对象。", "对四个列部门给出系数", repr(row),
                        "补齐 4x4 技术系数矩阵。")
                continue
            for c in SECTORS:
                v = as_int(row.get(c))
                if v is None:
                    rep.err("E_IO_NEGATIVE", cf.rel, "/io_coeff_uqs_per_qs/" + r + "/" + c,
                            "系数缺失或不是整数。", "int >= 0", repr(row.get(c)),
                            "0 是合法值（表示跳过该约束），但必须显式写出来。")
                    continue
                if v < 0:
                    rep.err("E_IO_NEGATIVE", cf.rel, "/io_coeff_uqs_per_qs/" + r + "/" + c,
                            "技术系数为负。", ">= 0", v, "投入系数不能为负。")
                coeff[(r, c)] = v
            check_sub_object(cf, rep, row, "/io_coeff_uqs_per_qs/" + r, SECTORS, "io_coeff 行")
        check_sub_object(cf, rep, io, "/io_coeff_uqs_per_qs", SECTORS, "io_coeff")

    if len(coeff) == 16:
        index["io_coeff"] = coeff
        for c in SECTORS:
            colsum = sum(coeff[(r, c)] for r in SECTORS)
            if colsum >= MICRO:
                rep.err("E_IO_COLSUM", cf.rel, "/io_coeff_uqs_per_qs (列 " + c + ")",
                        "中间投入吃光总产出，该列增加值必为负。", "< 1 000 000", colsum,
                        "降低该列的中间投入系数；否则基年 GDP 无法为正。")
            else:
                rep.info("V-IO-01", cf.rel, "/io_coeff_uqs_per_qs (列 " + c + ")",
                         "列和检查通过，增加值为正。", "< 1 000 000", colsum)
        e = coeff[("sector.energy", "sector.energy")]
        if e >= MICRO:
            rep.err("E_IO_ENERGY_SELF", cf.rel,
                    "/io_coeff_uqs_per_qs/sector.energy/sector.energy",
                    "能源自用系数 >= 1，自指无法在整数下闭合（R-19）。", "< 1 000 000", e,
                    "降到 1e6 以下。")
        need = dict((c, 0) for c in SECTORS)
        cur = dict((c, MICRO) for c in SECTORS)
        diverged = False
        for _ in range(30):
            nxt = dict((c, 0) for c in SECTORS)
            for c in SECTORS:
                if cur[c] == 0:
                    continue
                for r in SECTORS:
                    nxt[r] += (cur[c] * coeff[(r, c)]) // MICRO
            for c in SECTORS:
                need[c] += nxt[c]
            if sum(nxt.values()) > 10 ** 15:
                diverged = True
                break
            cur = nxt
            if sum(cur.values()) == 0:
                break
        tail = sum(cur.values())
        if diverged or tail >= 1:
            rep.err("E_IO_NOT_CONVERGENT", cf.rel, "/io_coeff_uqs_per_qs",
                    "30 轮整数幂和后累计投入增量未收敛到 < 1 μQ。", "< 1 μQ", tail,
                    "降低系数；本检查只拦「投入比产出还多」的明显错配，不宣称数学严谨。")
        else:
            rep.info("V-IO-05", cf.rel, "/io_coeff_uqs_per_qs",
                     "Leontief 整数可行性近似收敛。", "< 1 μQ", tail)

    ec = int_list(d.get("energy_coeff_uqs_per_qs"))
    if ec is not None and len(ec) == 4 and len(coeff) == 16:
        for i, s in enumerate(SECTORS):
            want = coeff[("sector.energy", s)]
            if ec[i] != want:
                rep.err("E_IO_ENERGY_COEFF", cf.rel, "/energy_coeff_uqs_per_qs/" + str(i),
                        "用电系数与 IO 表能源行不一致（故意冗余，用于交叉校验）。",
                        str(want) + "（= io_coeff[sector.energy][" + s + "]）", ec[i],
                        "两处必须逐字相等；冗余项写错说明有人只改了一处。")
        rep.info("V-IO-08", cf.rel, "/energy_coeff_uqs_per_qs",
                 "用电系数与 IO 能源行冗余交叉校验通过。", ec, ec)
    elif ec is None or len(ec) != 4:
        rep.err("E_IO_ENERGY_COEFF", cf.rel, "/energy_coeff_uqs_per_qs",
                "用电系数缺失或不是 4 个整数。", "int[4]",
                repr(d.get("energy_coeff_uqs_per_qs")), "补齐。")

    st = int_list(d.get("storable"))
    if st is None:
        st = d.get("storable") if isinstance(d.get("storable"), list) else None
    if isinstance(st, list) and len(st) == 4:
        for i in (2, 3):
            if st[i] != 0:
                rep.err("E_IO_STORABLE", cf.rel, "/storable/" + str(i),
                        SECTORS[i] + " 被标为可库存，违反「电力当期使用，不跨季储存」（计划书 §06）。",
                        0, st[i], "energy 与 services 必须为 0。")
        for i in (0, 1):
            if st[i] not in (0, 1):
                rep.err("E_IO_STORABLE", cf.rel, "/storable/" + str(i),
                        "storable 只能是 0 或 1。", "0 / 1", st[i], "改成 0 或 1。")
    else:
        rep.err("E_IO_STORABLE", cf.rel, "/storable", "storable 缺失或不是 4 个整数。",
                "int[4]", repr(d.get("storable")), "补齐。")

    cap = int_list(d.get("capacity_per_capital_uu_ppm"))
    if cap is not None and len(cap) == 4:
        for i, v in enumerate(cap):
            if v <= 0:
                rep.err("E_IO_CAPACITY_COEFF", cf.rel,
                        "/capacity_per_capital_uu_ppm/" + str(i),
                        "产能/资本系数必须 > 0，否则资本无法形成产能。", "> 0", v, "给正值。")
        index["capacity_per_capital_uu_ppm"] = cap
    else:
        rep.err("E_IO_CAPACITY_COEFF", cf.rel, "/capacity_per_capital_uu_ppm",
                "缺失或不是 4 个整数。", "int[4]",
                repr(d.get("capacity_per_capital_uu_ppm")), "补齐。")

    for key in ("spoilage_ppm", "depreciation_ppm_per_q", "emission_ppm"):
        arr = d.get(key)
        if not (isinstance(arr, list) and len(arr) == 4
                and all(isinstance(x, int) and not isinstance(x, bool) for x in arr)):
            rep.err("E_RANGE", cf.rel, "/" + key, "缺失或不是 4 个整数。", "int[4]",
                    repr(arr), "补齐。")
        else:
            for i, v in enumerate(arr):
                if v < 0:
                    rep.err("E_RANGE", cf.rel, "/" + key + "/" + str(i), "不能为负。",
                            ">= 0", v, "改成非负。")

    lab = d.get("labor_coeff_persons_per_qs")
    if isinstance(lab, dict):
        default = lab.get("*")
        if not isinstance(default, dict):
            rep.err("E_IO_LABOR", cf.rel, "/labor_coeff_persons_per_qs/*",
                    "缺少默认档 \"*\"。", "四部门 × 三技能的默认系数", repr(default),
                    "补上 \"*\" 默认值；单格覆盖用 cell.<region>.<sector> 键。")
        expanded = {}
        for cell in CELL_IDS:
            sect = "sector." + cell.split(".")[2]
            row = lab.get(cell) if isinstance(lab.get(cell), dict) else (
                default.get(sect) if isinstance(default, dict) else None)
            if not isinstance(row, dict):
                rep.err("E_IO_LABOR", cf.rel, "/labor_coeff_persons_per_qs",
                        cell + " 展开后没有用工系数。", "每个 (cell, skill) 有值", "缺失",
                        "补默认档或单格覆盖。")
                continue
            vals = {}
            for k in SKILLS:
                v = as_int(row.get(k))
                loc = "/labor_coeff_persons_per_qs (展开 " + cell + "/" + k + ")"
                if v is None:
                    rep.err("E_IO_LABOR", cf.rel, loc, "用工系数缺失或不是整数。",
                            "int >= 0", repr(row.get(k)), "补齐三档。")
                    v = 0
                elif v < 0:
                    rep.err("E_IO_LABOR", cf.rel, loc, "用工系数为负。", ">= 0", v, "改成非负。")
                vals[k] = v
            if all(v == 0 for v in vals.values()):
                rep.err("E_IO_LABOR", cf.rel,
                        "/labor_coeff_persons_per_qs (展开 " + cell + ")",
                        "三个技能档全为 0，该 cell 完全不受劳动约束。", "至少一档 > 0",
                        "low=mid=high=0", "给至少一档正系数，否则就业对这个 cell 没有任何意义。")
            expanded[cell] = vals
        index["labor_coeff"] = expanded
    index["io_present"] = True


# --------------------------------------------------------------------------
# 9 V-REG：地区（11 号文件 §5.6）
# --------------------------------------------------------------------------

def check_regions(cf: ContentFile, rep: Report, index: dict) -> None:
    regs = cf.data.get("regions")
    if not isinstance(regs, list):
        return
    seen = {}
    for i, r in enumerate(regs):
        ptr = "/regions/" + str(i)
        if not isinstance(r, dict):
            rep.err("E_REGION_SET", cf.rel, ptr, "地区条目不是对象。", "object",
                    type(r).__name__, "改成对象。")
            continue
        check_sub_object(cf, rep, r, ptr, SUB_SCHEMAS["regions.item"], "region 条目")
        rid = r.get("region_id")
        if not isinstance(rid, str) or not ID_PATTERNS["region_id"].match(rid):
            rep.err("E_ID_FORMAT", cf.rel, ptr + "/region_id", "region_id 非法。",
                    ID_PATTERNS["region_id"].pattern, repr(rid), "改成四个合法地区 ID 之一。")
            continue
        if rid in seen:
            rep.err("E_DUP_ID", cf.rel, ptr + "/region_id", "地区 ID 重复。", "唯一", rid,
                    "删除重复条目。")
        seen[rid] = r
    missing = [x for x in REGIONS if x not in seen]
    if missing or len(regs) != 4:
        rep.err("E_REGION_SET", cf.rel, "/regions", "地区集合不是恰好 4 条且齐全。",
                "4 条：" + ", ".join(REGIONS),
                str(len(regs)) + " 条；缺 " + (", ".join(missing) if missing else "无"),
                "补齐四个地区。")

    # V-REG-05：地区人口冗余值必须等于计划书 §05 的锁定值
    for rid, r in seen.items():
        want = REGION_POP[rid]
        got = as_int(r.get("population_persons"))
        if got != want:
            rep.err("E_POP_REGION", cf.rel, "/regions (" + rid + ")/population_persons",
                    "地区人口与计划书 §05 锁定值不符（INV-141）。", want, repr(got),
                    "改回锁定值；北原 900 万 / 中州 700 万 / 海岬 500 万 / 西岭 300 万。")
    index["region_init"] = seen

    # V-REG-02 邻接对称、无自环；成本矩阵完备且对角为 0
    for rid, r in seen.items():
        adj = r.get("adjacency")
        if not isinstance(adj, list):
            rep.err("E_REGION_ADJ", cf.rel, "/regions (" + rid + ")/adjacency",
                    "邻接表缺失或不是数组。", "array of region_id", repr(adj), "补齐。")
            continue
        if rid in adj:
            rep.err("E_REGION_ADJ", cf.rel, "/regions (" + rid + ")/adjacency",
                    "邻接表含自环。", "不含自身", rid, "删掉自身。")
        for other in adj:
            if other not in seen:
                rep.err("E_REGION_ADJ", cf.rel, "/regions (" + rid + ")/adjacency",
                        "邻接指向不存在的地区。", "四个合法地区之一", repr(other), "改正。")
                continue
            back = seen[other].get("adjacency")
            if not isinstance(back, list) or rid not in back:
                rep.err("E_REGION_ADJ", cf.rel, "/regions (" + rid + ")/adjacency",
                        "邻接矩阵不对称（INV-150）。",
                        other + " 的邻接表应含 " + rid, "不含",
                        "邻接必须双向登记，否则物流与迁移的方向性会静默不一致。")
        for key, code in (("logistics_cost_ppm", "E_REGION_ADJ"),
                          ("migration_cost_uu", "E_REGION_ADJ")):
            m = r.get(key)
            if not isinstance(m, dict):
                rep.err(code, cf.rel, "/regions (" + rid + ")/" + key, "缺失或不是映射。",
                        "对全部 4 个地区给出值", repr(m), "补齐。")
                continue
            for o in REGIONS:
                if o not in m:
                    rep.err(code, cf.rel, "/regions (" + rid + ")/" + key,
                            "对其它地区的项不完备。", "含 " + o, "缺失", "补齐四项。")
                elif o == rid and as_int(m.get(o)) != 0:
                    rep.err(code, cf.rel, "/regions (" + rid + ")/" + key + "/" + o,
                            "自身项必须为 0（对角为 0）。", 0, repr(m.get(o)), "改成 0。")
                elif as_int(m.get(o)) is not None and as_int(m.get(o)) < 0:
                    rep.err("E_RANGE", cf.rel, "/regions (" + rid + ")/" + key + "/" + o,
                            "成本不能为负。", ">= 0", m.get(o), "改成非负。")

    # V-REG-03 / V-REG-04
    for rid, r in seen.items():
        cap = as_int(r.get("housing_capacity_units"))
        stock = as_int(r.get("housing_stock_units"))
        if cap is not None and stock is not None and stock > cap:
            rep.err("E_HOUSE_CAP", cf.rel, "/regions (" + rid + ")/housing_stock_units",
                    "住房存量超过住房容量。", "<= " + str(cap), stock, "降存量或提容量。")
        slots = as_int(r.get("construction_slots_total"))
        if slots is None or not (1 <= slots <= 8):
            rep.err("E_REGION_SLOTS", cf.rel,
                    "/regions (" + rid + ")/construction_slots_total",
                    "施工槽位不在 1..8（施工拥堵失败路径可测的前提）。", "1..8", repr(slots),
                    "给 1..8 的整数。")
        area = as_int(r.get("area_index"))
        if area is None or area <= 0:
            rep.err("E_RANGE", cf.rel, "/regions (" + rid + ")/area_index",
                    "面积指数必须 > 0。", "> 0", repr(area), "给正值。")
        port = as_int(r.get("port_capacity_uqs_per_q"))
        if port is not None and port > 0 and rid in ("region.beiyuan", "region.zhongzhou",
                                                     "region.xiling"):
            rep.warn("E_RANGE", cf.rel, "/regions (" + rid + ")/port_capacity_uqs_per_q",
                     "内陆地区有港口通行能力。", "0（计划书 §05 只有海岬是港口区位）", port,
                     "确认是否有意为之；若无，改成 0。")


# --------------------------------------------------------------------------
# 10 V-POP：人口（11 号文件 §5.7）
# --------------------------------------------------------------------------

def check_population(cf: ContentFile, rep: Report, index: dict) -> None:
    d = cf.data
    groups = d.get("groups")
    if not isinstance(groups, list):
        return
    if "unemployment_ppm" in d or any(isinstance(g, dict) and "unemployment_ppm" in g
                                      for g in groups):
        rep.err("E_POP_UNEMP", cf.rel, "/", "剧本里出现失业率输入字段（INV-143）。",
                "schema 中不存在该字段，8% 只能反算", "出现 unemployment_ppm",
                "删除；手写失业率必须在语法层面不可能。")

    seen = {}
    for i, g in enumerate(groups):
        ptr = "/groups/" + str(i)
        if not isinstance(g, dict):
            rep.err("E_GROUP_SET", cf.rel, ptr, "群组条目不是对象。", "object",
                    type(g).__name__, "改成对象。")
            continue
        check_sub_object(cf, rep, g, ptr, SUB_SCHEMAS["population.group"], "group 条目")
        gid = g.get("group_id")
        if not isinstance(gid, str) or not ID_PATTERNS["group_id"].match(gid):
            rep.err("E_ID_FORMAT", cf.rel, ptr + "/group_id", "group_id 非法。",
                    ID_PATTERNS["group_id"].pattern, repr(gid),
                    "改成 group.<region>.<age>.<skill>。")
            continue
        if gid in seen:
            rep.err("E_DUP_ID", cf.rel, ptr + "/group_id", "群组 ID 重复。", "唯一", gid,
                    "删除重复条目。")
        seen[gid] = g

    missing = [x for x in GROUP_IDS if x not in seen]
    if missing or len(groups) != 36:
        rep.err("E_GROUP_SET", cf.rel, "/groups",
                "群组集合不是恰好 36 条且覆盖 4×3×3 全组合（INV-142）。", "36 条全组合",
                str(len(groups)) + " 条；缺 " + str(len(missing)) + " 个"
                + ("：" + ", ".join(missing[:6]) + (" …" if len(missing) > 6 else "")
                   if missing else ""),
                "补齐；允许 population_persons == 0 的空组，但 36 条必须齐全。")
    index["groups"] = seen

    # V-POP-02 人口合计
    total = 0
    by_region = dict((r, 0) for r in REGIONS)
    for gid, g in seen.items():
        p = as_int(g.get("population_persons"))
        if p is None or p < 0:
            rep.err("E_POP_TOTAL", cf.rel, "/groups (" + gid + ")/population_persons",
                    "人口缺失或为负。", "int >= 0", repr(g.get("population_persons")),
                    "给非负整数人。")
            continue
        total += p
        by_region["region." + gid.split(".")[1]] += p
    if len(seen) == 36:
        if total != TOTAL_POP:
            rep.err("E_POP_TOTAL", cf.rel, "/groups",
                    "全国人口合计不等于 2400 万（计划书 §05，INV-141）。", TOTAL_POP,
                    str(total) + "（差 " + str(total - TOTAL_POP) + "）",
                    "调整群组人口使合计精确等于 24000000。")
        else:
            rep.info("V-POP-02", cf.rel, "/groups", "全国人口合计正确。", TOTAL_POP, total)
        for r in REGIONS:
            if by_region[r] != REGION_POP[r]:
                rep.err("E_POP_REGION", cf.rel, "/groups (" + r + ")",
                        "地区人口合计与计划书 §05 不符（INV-141）。", REGION_POP[r],
                        str(by_region[r]) + "（差 " + str(by_region[r] - REGION_POP[r]) + "）",
                        "调整该地区群组人口。")
            else:
                rep.info("V-POP-02", cf.rel, "/groups (" + r + ")", "地区人口合计正确。",
                         REGION_POP[r], by_region[r])
        ri = index.get("region_init") or {}
        for r in REGIONS:
            decl = as_int((ri.get(r) or {}).get("population_persons"))
            if decl is not None and decl != by_region[r]:
                rep.err("E_POP_REGION", cf.rel, "/groups (" + r + ")",
                        "regions.json 的地区人口冗余值与群组求和不一致（故意冗余，交叉校验）。",
                        str(decl) + "（regions.json）", by_region[r],
                        "两处必须逐字相等；冗余项不一致说明只改了一处。")

    # V-POP-03 / V-POP-04 / V-POP-05
    labor_force = 0
    unemployed = 0
    emp_by_region_skill = {}
    emp_by_cell = {}
    emp_pubserv = {}
    for gid, g in seen.items():
        parts = gid.split(".")
        region = "region." + parts[1]
        age, skill = parts[2], parts[3]
        ptr = "/groups (" + gid + ")"
        pop = as_int(g.get("population_persons")) or 0
        part = as_int(g.get("participation_ppm"))
        emp = g.get("employed_persons")
        sow = as_int(g.get("support_out_weight_ppm"))
        if part is None or not (0 <= part <= MICRO):
            rep.err("E_RANGE", cf.rel, ptr + "/participation_ppm",
                    "劳动参与率缺失或超出 0..1 000 000。", "0..1000000", repr(g.get("participation_ppm")),
                    "给 ppm 整数。")
            part = 0
        emp_sum = 0
        if isinstance(emp, dict):
            allowed = SECTORS + ["pubserv"]
            check_sub_object(cf, rep, emp, ptr + "/employed_persons", allowed, "employed_persons")
            for k in allowed:
                v = as_int(emp.get(k))
                if v is None:
                    rep.err("E_POP_EMP", cf.rel, ptr + "/employed_persons/" + k,
                            "就业分项缺失或不是整数。", "int >= 0", repr(emp.get(k)),
                            "显式写 0，不要省略。")
                    v = 0
                elif v < 0:
                    rep.err("E_POP_EMP", cf.rel, ptr + "/employed_persons/" + k,
                            "就业人数为负。", ">= 0", v, "改成非负。")
                    v = 0
                emp_sum += v
                if v:
                    if k == "pubserv":
                        emp_pubserv.setdefault("pubserv." + parts[1], {}).setdefault(skill, 0)
                        emp_pubserv["pubserv." + parts[1]][skill] += v
                    else:
                        cid = "cell." + parts[1] + "." + k.split(".")[1]
                        emp_by_cell.setdefault(cid, {}).setdefault(skill, 0)
                        emp_by_cell[cid][skill] += v
                    emp_by_region_skill.setdefault((region, skill), 0)
                    emp_by_region_skill[(region, skill)] += v
        else:
            rep.err("E_POP_EMP", cf.rel, ptr + "/employed_persons",
                    "缺少就业分配表。", "五个去向（4 部门 + pubserv）的整数", repr(emp),
                    "补齐；失业率必须由这里反算得出（INV-143）。")

        if age != "working":
            if part != 0 or emp_sum != 0 or (sow or 0) != 0:
                rep.err("E_POP_AGE_ROLE", cf.rel, ptr,
                        "非劳动年龄组出现参与率 / 就业 / 赡养转出（INV-074）。",
                        "participation_ppm == 0 且就业全 0 且 support_out_weight_ppm == 0",
                        "participation=" + str(part) + " 就业=" + str(emp_sum)
                        + " 赡养转出=" + str(sow),
                        "儿童档位代表教育准备程度，不代表劳动技能；老年组不就业。")
        else:
            lf = (pop * part) // MICRO
            if emp_sum > lf:
                rep.err("E_POP_EMP", cf.rel, ptr + "/employed_persons",
                        "就业人数超过本组劳动力（计划书 §17「就业人数不超过同口径劳动力」）。",
                        "<= " + str(lf), emp_sum, "降低就业或提高参与率。")
            labor_force += lf
            unemployed += max(0, lf - emp_sum)

        for key, lo, hi in (("consumption_index_ppm", 0, 3 * MICRO),
                            ("living_index_ppm", 0, 3 * MICRO),
                            ("expectation_ppm", 0, 3 * MICRO),
                            ("trust_ppm", 0, MICRO),
                            ("support_ppm", 0, MICRO)):
            v = as_int(g.get(key))
            if v is None or not (lo <= v <= hi):
                rep.err("E_RANGE", cf.rel, ptr + "/" + key, "缺失或超出区间。",
                        str(lo) + ".." + str(hi), repr(g.get(key)), "给区间内的 ppm 整数。")
        for key in ("cash_uu", "deposit_uu", "housing_units_occupied",
                    "base_per_capita_real_income_uu", "base_real_consumption_uqs"):
            v = as_int(g.get(key))
            if v is None or v < 0:
                rep.err("E_RANGE", cf.rel, ptr + "/" + key, "缺失或为负。", ">= 0",
                        repr(g.get(key)), "给非负整数。")
        sa = g.get("service_access_ppm")
        if isinstance(sa, dict):
            check_sub_object(cf, rep, sa, ptr + "/service_access_ppm",
                             ["health", "education", "utility"], "service_access_ppm")
            for k in ("health", "education", "utility"):
                v = as_int(sa.get(k))
                if v is None or not (0 <= v <= MICRO):
                    rep.err("E_RANGE", cf.rel, ptr + "/service_access_ppm/" + k,
                            "服务可及性缺失或超出 0..1 000 000。", "0..1000000",
                            repr(sa.get(k)), "给 ppm 整数。")
        else:
            rep.err("E_INDEX_BASE", cf.rel, ptr + "/service_access_ppm", "缺少服务可及性。",
                    "health / education / utility 三项", repr(sa), "补齐。")
        bds = g.get("base_delivered_service_uqs")
        if isinstance(bds, dict):
            check_sub_object(cf, rep, bds, ptr + "/base_delivered_service_uqs",
                             ["health", "education", "utility"], "base_delivered_service_uqs")
            for k in ("health", "education", "utility"):
                v = as_int(bds.get(k))
                if v is None or v < 0:
                    rep.err("E_RANGE", cf.rel, ptr + "/base_delivered_service_uqs/" + k,
                            "服务基准缺失或为负。", ">= 0", repr(bds.get(k)),
                            "运行 tools/refit_living.py --apply 重新生成。")
        else:
            rep.err("E_INDEX_BASE", cf.rel, ptr + "/base_delivered_service_uqs", "缺少服务基准（R-LIVING-01）。",
                    "health / education / utility 三项", repr(bds), "运行 tools/refit_living.py --apply。")
        ba = g.get("bloc_affiliation_ppm")
        if not (isinstance(ba, list) and len(ba) == 3
                and all(isinstance(x, int) and not isinstance(x, bool) and x >= 0 for x in ba)):
            rep.err("E_RANGE", cf.rel, ptr + "/bloc_affiliation_ppm",
                    "集团归属权重必须是 3 个非负整数（按 bloc 下标）。", "int[3] >= 0",
                    repr(ba), "补齐；允许合计 > 1e6（成员可同属多个网络）。")

    index["labor_force"] = labor_force
    index["unemployed"] = unemployed
    index["emp_by_cell"] = emp_by_cell
    index["emp_pubserv"] = emp_pubserv

    if labor_force > 0:
        ppm = (unemployed * MICRO) // labor_force
        lo, hi = UNEMP_TARGET_PPM - UNEMP_TOL_PPM, UNEMP_TARGET_PPM + UNEMP_TOL_PPM
        detail = ("分子 未就业=" + str(unemployed) + " 人；分母 劳动力="
                  + str(labor_force) + " 人；反算 " + str(ppm) + " ppm")
        if not (lo <= ppm <= hi):
            rep.err("E_POP_UNEMP", cf.rel, "/groups",
                    "由就业分配反算的失业率不在 8% ± 500 ppm（计划书 §05，INV-143）。",
                    str(lo) + ".." + str(hi) + " ppm", detail,
                    "调整 working 组的 participation_ppm 或 employed_persons；"
                    "不要新增失业率字段。")
        else:
            rep.info("V-POP-05", cf.rel, "/groups", "反算失业率落在目标带内。",
                     "80000 ± 500 ppm", detail)
    else:
        rep.err("E_POP_UNEMP", cf.rel, "/groups", "劳动力合计为 0，失业率无法反算。",
                "> 0", 0, "给 working 组正的 participation_ppm。")

    # V-POP-07 基期人口加权指数 == 1 000 000
    for key in ("consumption_index_ppm", "living_index_ppm"):
        num = 0
        den = 0
        for gid, g in seen.items():
            p = as_int(g.get("population_persons")) or 0
            v = as_int(g.get(key))
            if v is None:
                continue
            num += p * v
            den += p
        if den:
            w = num // den
            if w != INDEX_BASE_PPM:
                rep.err("E_INDEX_BASE", cf.rel, "/groups (" + key + ")",
                        "基期人口加权指数不等于 1 000 000（民生基线 = 100，INV-149）。",
                        INDEX_BASE_PPM, w, "把基期全部群组的该指数设为 1000000。")
            else:
                rep.info("V-POP-07", cf.rel, "/groups (" + key + ")",
                         "基期人口加权指数正确。", INDEX_BASE_PPM, w)
    for svc in ("health", "education", "utility"):
        num = 0
        den = 0
        for gid, g in seen.items():
            p = as_int(g.get("population_persons")) or 0
            v = as_int(get(g, "service_access_ppm", svc))
            if v is None:
                continue
            num += p * v
            den += p
        if den:
            w = num // den
            if w != INDEX_BASE_PPM:
                rep.err("E_INDEX_BASE", cf.rel,
                        "/groups (service_access_ppm/" + svc + ")",
                        "基期人口加权服务可及性不等于 1 000 000（INV-149）。",
                        INDEX_BASE_PPM, w, "基期设为 1000000。")

    # V-POP-06 分地区住房占用 <= 存量
    ri = index.get("region_init") or {}
    occ = dict((r, 0) for r in REGIONS)
    for gid, g in seen.items():
        occ["region." + gid.split(".")[1]] += as_int(g.get("housing_units_occupied")) or 0
    for r in REGIONS:
        stock = as_int((ri.get(r) or {}).get("housing_stock_units"))
        if stock is not None and occ[r] > stock:
            rep.err("E_HOUSE_OVER", cf.rel, "/groups (" + r + ")",
                    "群组已占用住房超过该地区住房存量（INV-083）。", "<= " + str(stock),
                    occ[r], "降低占用或提高存量；不能让所有人迁到同一区还享受无限住房。")
        elif stock is not None:
            rep.info("V-POP-06", cf.rel, "/groups (" + r + ")", "住房占用未超存量。",
                     "<= " + str(stock), occ[r])

    dr = d.get("demography_rates")
    if isinstance(dr, dict):
        check_sub_object(cf, rep, dr, "/demography_rates",
                         ["birth_ppm_per_q", "death_ppm_per_q", "age_out_ppm_per_q",
                          "birth_target_skill"], "demography_rates")
        b = dr.get("birth_ppm_per_q")
        if isinstance(b, dict):
            for r in REGIONS:
                if as_int(b.get(r)) is None:
                    rep.err("E_RANGE", cf.rel, "/demography_rates/birth_ppm_per_q/" + r,
                            "缺少该地区出生率。", "int ppm", repr(b.get(r)), "补齐四地区。")
        dd = dr.get("death_ppm_per_q")
        if isinstance(dd, dict):
            for a in AGES:
                if as_int(dd.get(a)) is None:
                    rep.err("E_RANGE", cf.rel, "/demography_rates/death_ppm_per_q/" + a,
                            "缺少该年龄层死亡率。", "int ppm", repr(dd.get(a)), "补齐三档。")
        ao = dr.get("age_out_ppm_per_q")
        if isinstance(ao, dict):
            for a in ("minor", "working"):
                if as_int(ao.get(a)) is None:
                    rep.err("E_RANGE", cf.rel, "/demography_rates/age_out_ppm_per_q/" + a,
                            "缺少该年龄层成年/退休率。", "int ppm", repr(ao.get(a)), "补齐。")
        if dr.get("birth_target_skill") not in SKILLS:
            rep.err("E_RANGE", cf.rel, "/demography_rates/birth_target_skill",
                    "新生儿技能落点非法。", " / ".join(SKILLS), repr(dr.get("birth_target_skill")),
                    "首版应为 low。")


# --------------------------------------------------------------------------
# 11 V-FIN：政府与债券（11 号文件 §5.9）
# --------------------------------------------------------------------------

def amort_schedule(b: dict) -> dict:
    """按 12 号文件 §2.4 生成 {q: 本金还款额}。

    level_principal：发行时用 split_largest_remainder(principal_initial, 等权重) 预生成，
    各期之和精确等于面值（INV-037）；还款期为 issue_q+1 .. maturity_q。
    bullet：到期一次还清。
    """
    iq = as_int(b.get("issue_q"))
    mq = as_int(b.get("maturity_q"))
    p0 = as_int(b.get("principal_initial_uu"))
    amo = b.get("amortization")
    if iq is None or mq is None or p0 is None or mq <= iq:
        return {}
    if amo == "bullet":
        return {mq: p0}
    if amo == "level_principal":
        n = mq - iq
        parts = split_largest_remainder(p0, [1] * n)
        return dict((iq + 1 + i, parts[i]) for i in range(n))
    return {}


def check_government(cf: ContentFile, rep: Report, index: dict) -> None:
    d = cf.data
    gov = d.get("gov")
    if isinstance(gov, dict):
        check_sub_object(cf, rep, gov, "/gov", SUB_SCHEMAS["gov"], "gov")
        cash = as_int(gov.get("cash_uu"))
        if cash != GOV_CASH_UU:
            rep.err("E_CASH_INIT", cf.rel, "/gov/cash_uu",
                    "国库现金不等于 2 U（计划书 §05，INV-145）。", GOV_CASH_UU, repr(cash),
                    "改回 2000000 μU。")
        else:
            rep.info("V-FIN-01", cf.rel, "/gov/cash_uu", "国库现金正确。", GOV_CASH_UU, cash)
        index["gov_cash_uu"] = cash
        for k in SUB_SCHEMAS["gov"]:
            v = as_int(gov.get(k))
            if v is None:
                rep.err("E_RANGE", cf.rel, "/gov/" + k, "字段缺失或不是整数。", "int",
                        repr(gov.get(k)), "补齐。")
            elif v < 0:
                rep.err("E_RANGE", cf.rel, "/gov/" + k, "不能为负。", ">= 0", v, "改成非负。")
            elif k.endswith("_uu") and v > AMOUNT_MAX:
                rep.err("E_RANGE", cf.rel, "/gov/" + k, "超过 AMOUNT_MAX。",
                        "<= " + str(AMOUNT_MAX), v, "复核单位。")
        tc = as_int(gov.get("tax_capacity_ppm"))
        if tc is not None and not (0 <= tc <= MICRO):
            rep.err("E_RANGE", cf.rel, "/gov/tax_capacity_ppm", "征收能力超出 0..1e6。",
                    "0..1000000", tc, "给 ppm 整数。")

    # 债券
    bonds = d.get("bonds")
    total_out = 0
    total_init = 0
    invpool_hold = 0
    if isinstance(bonds, list):
        seen_bid = set()
        if not bonds:
            rep.err("E_DEBT_TOTAL", cf.rel, "/bonds",
                    "债券批次为空，50 U 债务未拆分期限与债权人（计划书 §05）。",
                    ">= 2 个批次", "0", "按期限与债权人拆分。")
        for i, b in enumerate(bonds):
            ptr = "/bonds/" + str(i)
            if not isinstance(b, dict):
                rep.err("E_BOND_FIELD", cf.rel, ptr, "债券条目不是对象。", "object",
                        type(b).__name__, "改成对象。")
                continue
            check_sub_object(cf, rep, b, ptr, SUB_SCHEMAS["bond"], "bond 条目")
            bid = b.get("bond_id")
            if not isinstance(bid, str) or not ID_PATTERNS["bond_id"].match(bid):
                rep.err("E_ID_FORMAT", cf.rel, ptr + "/bond_id", "bond_id 非法。",
                        ID_PATTERNS["bond_id"].pattern, repr(bid),
                        "开局存量批次的 issue_q 为负，形如 bond.q-12_01。")
            elif bid in seen_bid:
                rep.err("E_DUP_ID", cf.rel, ptr + "/bond_id", "债券 ID 重复。", "唯一", bid,
                        "ID 永不复用。")
            else:
                seen_bid.add(bid)
            iq = as_int(b.get("issue_q"))
            mq = as_int(b.get("maturity_q"))
            if iq is None or mq is None or mq <= iq:
                rep.err("E_BOND_FIELD", cf.rel, ptr, "必须 maturity_q > issue_q。",
                        "maturity_q > issue_q", "issue_q=" + str(iq) + " maturity_q=" + str(mq),
                        "改正期限。")
            cp = as_int(b.get("coupon_ppm_per_q"))
            if cp is None or not (0 <= cp <= 100_000):
                rep.err("E_BOND_FIELD", cf.rel, ptr + "/coupon_ppm_per_q",
                        "季度票息率超出 0..100 000 ppm。", "0..100000", repr(cp), "改正。")
            holder = b.get("holder")
            if holder not in ("invpool", "row"):
                rep.err("E_BOND_FIELD", cf.rel, ptr + "/holder",
                        "债权人非法（融资必须有对手方，计划书 §07）。", "invpool / row",
                        repr(holder), "改成 invpool 或 row。")
            amo = b.get("amortization")
            if amo not in ("bullet", "level_principal"):
                rep.err("E_BOND_FIELD", cf.rel, ptr + "/amortization", "摊还方式非法。",
                        "bullet / level_principal", repr(amo), "改正。")
            p0 = as_int(b.get("principal_initial_uu"))
            po = as_int(b.get("principal_outstanding_uu"))
            if p0 is None or p0 <= 0:
                rep.err("E_BOND_FIELD", cf.rel, ptr + "/principal_initial_uu",
                        "面值缺失或非正。", "> 0", repr(p0), "给正整数。")
            if po is None or po < 0:
                rep.err("E_BOND_FIELD", cf.rel, ptr + "/principal_outstanding_uu",
                        "余额缺失或为负。", ">= 0", repr(po), "给非负整数。")
            if p0 is not None and po is not None:
                total_init += p0
                total_out += po
                if po > p0:
                    rep.err("E_BOND_FIELD", cf.rel, ptr + "/principal_outstanding_uu",
                            "余额大于面值。", "<= " + str(p0), po, "改正。")
                sched = amort_schedule(b)
                if sched:
                    paid_before_q0 = sum(v for q, v in sched.items() if q < 0)
                    want = p0 - paid_before_q0
                    if want != po:
                        rep.warn("E_BOND_FIELD", cf.rel, ptr + "/principal_outstanding_uu",
                                 "余额与摊还表推算值不一致（12 号文件 §2.4 的 amort_schedule）。",
                                 str(want) + "（面值 " + str(p0) + " 减 q<0 已还 "
                                 + str(paid_before_q0) + "）", po,
                                 "两者必须同源；否则 V-FIN-05 的票息复算与债务存量各说各话。")
                if holder == "invpool" and po is not None:
                    invpool_hold += po
    if total_out != GOV_DEBT_UU:
        rep.err("E_DEBT_TOTAL", cf.rel, "/bonds",
                "债券批次面值合计不等于 50 U（计划书 §05，INV-144）。", GOV_DEBT_UU,
                str(total_out) + "（差 " + str(total_out - GOV_DEBT_UU) + "）",
                "调整批次余额使合计精确为 50000000 μU。")
    else:
        rep.info("V-FIN-02", cf.rel, "/bonds", "债务存量合计正确。", GOV_DEBT_UU, total_out)

    # 年度计划
    ap = d.get("annual_plan")
    if isinstance(ap, dict):
        check_sub_object(cf, rep, ap, "/annual_plan", SUB_SCHEMAS["annual_plan"], "annual_plan")
        rc = as_int(ap.get("receipts_uu"))
        ex = as_int(ap.get("expenditure_incl_interest_uu"))
        df = as_int(ap.get("deficit_uu"))
        if rc != ANNUAL_RECEIPTS_UU:
            rep.err("E_FIN_YEARPLAN", cf.rel, "/annual_plan/receipts_uu",
                    "全年收入不等于 20 U（计划书 §05，INV-146）。", ANNUAL_RECEIPTS_UU,
                    repr(rc), "改回 20000000 μU。")
        if ex != ANNUAL_EXPEND_UU:
            rep.err("E_FIN_YEARPLAN", cf.rel, "/annual_plan/expenditure_incl_interest_uu",
                    "全年支出不等于 22 U（含利息、不含还本；计划书 §05，INV-146）。",
                    ANNUAL_EXPEND_UU, repr(ex), "改回 22000000 μU。")
        if df != ANNUAL_DEFICIT_UU:
            rep.err("E_FIN_YEARPLAN", cf.rel, "/annual_plan/deficit_uu",
                    "赤字不等于 2 U（计划书 §05，INV-146）。", ANNUAL_DEFICIT_UU, repr(df),
                    "改回 2000000 μU。")
        if rc is not None and ex is not None and df is not None and ex - rc != df:
            rep.err("E_FIN_YEARPLAN", cf.rel, "/annual_plan",
                    "支出 − 收入 ≠ 赤字。", "expenditure − receipts == deficit",
                    str(ex) + " − " + str(rc) + " = " + str(ex - rc) + " ≠ " + str(df),
                    "三个数必须自洽。")
        elif rc == ANNUAL_RECEIPTS_UU and ex == ANNUAL_EXPEND_UU and df == ANNUAL_DEFICIT_UU:
            rep.info("V-FIN-03", cf.rel, "/annual_plan", "年计划三项与计划书 §05 一致。",
                     "20 U / 22 U / 2 U", "20 U / 22 U / 2 U")

        rl = ap.get("receipt_lines_uu")
        if isinstance(rl, dict):
            check_sub_object(cf, rep, rl, "/annual_plan/receipt_lines_uu", RECEIPT_LINES,
                             "receipt_lines_uu")
            s = 0
            for k in RECEIPT_LINES:
                v = as_int(rl.get(k))
                if v is None:
                    rep.err("E_FIN_LINES", cf.rel, "/annual_plan/receipt_lines_uu/" + k,
                            "收入分项缺失或不是整数。", "int >= 0", repr(rl.get(k)), "补齐。")
                else:
                    s += v
            if rc is not None and s != rc:
                rep.err("E_FIN_LINES", cf.rel, "/annual_plan/receipt_lines_uu",
                        "收入分项合计 ≠ 全年收入。", rc,
                        str(s) + "（差 " + str(s - rc) + "）", "调整分项使合计精确相等。")
            else:
                rep.info("V-FIN-04", cf.rel, "/annual_plan/receipt_lines_uu",
                         "收入分项合计正确。", rc, s)
        el = ap.get("expenditure_lines_uu")
        interest_line = None
        if isinstance(el, dict):
            check_sub_object(cf, rep, el, "/annual_plan/expenditure_lines_uu",
                             EXPENDITURE_LINES, "expenditure_lines_uu")
            s = 0
            for k in EXPENDITURE_LINES:
                v = as_int(el.get(k))
                if v is None:
                    rep.err("E_FIN_LINES", cf.rel,
                            "/annual_plan/expenditure_lines_uu/" + k,
                            "支出分项缺失或不是整数。", "int >= 0", repr(el.get(k)),
                            "显式写 0，不要省略。")
                else:
                    s += v
            interest_line = as_int(el.get("interest"))
            if ex is not None and s != ex:
                rep.err("E_FIN_LINES", cf.rel, "/annual_plan/expenditure_lines_uu",
                        "支出分项合计 ≠ 全年支出。", ex,
                        str(s) + "（差 " + str(s - ex) + "）", "调整分项使合计精确相等。")
            else:
                rep.info("V-FIN-04", cf.rel, "/annual_plan/expenditure_lines_uu",
                         "支出分项合计正确。", ex, s)

        # V-FIN-05：利息项 == 基年四季逐批次票息之和
        if isinstance(bonds, list) and bonds:
            per_batch = []
            grand = 0
            for b in bonds:
                if not isinstance(b, dict):
                    continue
                p0 = as_int(b.get("principal_initial_uu"))
                po = as_int(b.get("principal_outstanding_uu"))
                cp = as_int(b.get("coupon_ppm_per_q"))
                if po is None or cp is None:
                    continue
                sched = amort_schedule(b)
                out = po
                acc = 0
                rem = 0
                for q in range(4):
                    raw = out * cp
                    it = raw // MICRO
                    rem += raw - it * MICRO
                    if rem >= MICRO:
                        it += 1
                        rem -= MICRO
                    acc += it
                    out -= sched.get(q, 0)
                    if out < 0:
                        out = 0
                per_batch.append((b.get("bond_id"), acc))
                grand += acc
            detail = "；".join(str(x[0]) + "=" + str(x[1]) for x in per_batch)
            if interest_line is not None and interest_line != grand:
                rep.err("E_FIN_INTEREST", cf.rel,
                        "/annual_plan/expenditure_lines_uu/interest",
                        "支出结构中的利息项 ≠ 基年四季逐批次票息之和（INV-147）。",
                        str(grand) + "（逐批次：" + detail + "）",
                        str(interest_line) + "（差 " + str(interest_line - grand) + "）",
                        "禁止先把债务求和再乘平均利率；利息必须逐债券批次计算（计划书 §07）。")
            elif interest_line is not None:
                rep.info("V-FIN-05", cf.rel,
                         "/annual_plan/expenditure_lines_uu/interest",
                         "利息项与逐批次票息复算一致。", grand, interest_line)

        # 四季拆分合计 == 年计划（最大余数法）
        season = index.get("season") or {}
        for line_key, amount, sk in (("receipts_uu", rc, "gov_receipts"),
                                     ("primary（支出 − 利息）",
                                      (ex - interest_line) if (ex is not None
                                                               and interest_line is not None)
                                      else None, "gov_primary")):
            w = season.get(sk)
            if w and amount is not None:
                parts = split_largest_remainder(amount, w)
                if sum(parts) != amount:
                    rep.err("E_FIN_YEARPLAN", cf.rel, "/annual_plan",
                            "年度额按季节系数拆四季后合计 ≠ 年计划。", amount, sum(parts),
                            "用最大余数法拆分，禁止静默丢失余数。")
                else:
                    rep.info("V-SEASON", cf.rel, "/annual_plan",
                             line_key + " 四季拆分合计等于年计划（最大余数法）。",
                             amount, str(parts) + " 合计 " + str(sum(parts)))

    # V-FIN-06 支付优先级全排列
    pp = d.get("payment_priority")
    if isinstance(pp, list):
        if sorted(pp) != sorted(PAYMENT_LINES):
            rep.err("E_PRIORITY_INCOMPLETE", cf.rel, "/payment_priority",
                    "支付优先级不是 8 类支出的全排列（缺项即行为未定义、不可测）。",
                    ", ".join(PAYMENT_LINES), ", ".join(str(x) for x in pp),
                    "补成 8 类的全排列。")
        else:
            rep.info("V-FIN-06", cf.rel, "/payment_priority", "支付优先级是 8 类全排列。",
                     "8 类全排列", "8 类全排列")

    # V-FIN-08 / V-FIN-09
    iv = d.get("invpool")
    invpool_cash = as_int(get(iv, "cash_uu")) if isinstance(iv, dict) else None
    if isinstance(iv, dict):
        check_sub_object(cf, rep, iv, "/invpool", ["cash_uu"], "invpool")
    if invpool_cash is None:
        rep.err("E_INVPOOL_TOO_SMALL", cf.rel, "/invpool/cash_uu",
                "居民投资池初始现金缺失。", "int >= 0", repr(iv), "补齐；融资必须有对手方。")
    else:
        index["invpool_cash_uu"] = invpool_cash
        if invpool_cash < ANNUAL_DEFICIT_UU:
            rep.err("E_INVPOOL_TOO_SMALL", cf.rel, "/invpool/cash_uu",
                    "投资池现金不足以承接基线年赤字（V-FIN-08 / OQ-201）。",
                    ">= " + str(ANNUAL_DEFICIT_UU), invpool_cash,
                    "现金总量恒定下，融资必须有买得起的对手方，否则基年即触发融资危机。")
        else:
            rep.info("V-FIN-08", cf.rel, "/invpool/cash_uu", "投资池可承接基线年赤字。",
                     ">= " + str(ANNUAL_DEFICIT_UU), invpool_cash)
    index["invpool_bond_holding_uu"] = invpool_hold

    groups = index.get("groups") or {}
    if groups and invpool_cash is not None:
        dep = sum((as_int(g.get("deposit_uu")) or 0) for g in groups.values())
        want = invpool_cash + invpool_hold
        if dep != want:
            rep.err("E_DEPOSIT_MISMATCH", cf.rel, "/invpool",
                    "居民存款合计 ≠ 投资池现金 + 投资池持有的债券余额（INV-024）。",
                    str(want) + "（= " + str(invpool_cash) + " + " + str(invpool_hold) + "）",
                    str(dep) + "（差 " + str(dep - want) + "）",
                    "投资池是居民存款的对手方；两侧不平意味着凭空多出或少掉一笔债权。")
        else:
            rep.info("V-FIN-09", cf.rel, "/invpool", "居民存款与投资池配平。", want, dep)


# --------------------------------------------------------------------------
# 12 V-CELL / V-POL
# --------------------------------------------------------------------------

def check_cells(cf: ContentFile, rep: Report, index: dict) -> None:
    cells = cf.data.get("cells")
    if not isinstance(cells, list):
        return
    seen = {}
    cap_coeff = index.get("capacity_per_capital_uu_ppm")
    groups = index.get("groups") or {}
    emp_from_pop = index.get("emp_by_cell") or {}
    for i, c in enumerate(cells):
        ptr = "/cells/" + str(i)
        if not isinstance(c, dict):
            continue
        cid = c.get("cell_id")
        if not isinstance(cid, str) or not ID_PATTERNS["cell_id"].match(cid):
            rep.err("E_ID_FORMAT", cf.rel, ptr + "/cell_id", "cell_id 非法。",
                    ID_PATTERNS["cell_id"].pattern, repr(cid), "改成 cell.<region>.<sector>。")
            continue
        if cid in seen:
            rep.err("E_DUP_ID", cf.rel, ptr + "/cell_id", "cell ID 重复。", "唯一", cid, "去重。")
        seen[cid] = c
        inv_in = c.get("inventory_input_uqs")
        if isinstance(inv_in, dict):
            # R-SERVICES-01：只禁电力。服务作为上季采购的中间投入可以持有（docs/12 §5.1 / §5.3）。
            for bad in ("sector.energy",):
                if bad in inv_in:
                    rep.err("E_ENERGY_INVENTORY", cf.rel,
                            ptr + "/inventory_input_uqs/" + bad,
                            "电力出现在投入库存里（计划书 §06：电力当期使用，不跨季储存）。",
                            "只允许 sector.agri / sector.manu / sector.services", bad, "删除该项。")
        capa = as_int(c.get("capacity_active_uqs_per_q"))
        capv = as_int(c.get("capital_value_uu"))
        if cap_coeff and capa is not None and capv is not None:
            s = SECTORS.index("sector." + cid.split(".")[2])
            want = (capv * cap_coeff[s]) // MICRO
            if abs(capa - want) > 1:
                rep.err("E_CAPACITY_INCONSISTENT", cf.rel,
                        ptr + "/capacity_active_uqs_per_q",
                        "产能与资本不一致（凭空产能，计划书 §16 人工评审要点）。",
                        str(want) + " ± 1（= capital_value × capacity_per_capital_uu_ppm）",
                        capa, "让两条轨同源。")
        eq = c.get("equity_share_ppm")
        if isinstance(eq, dict):
            s = 0
            for k, v in eq.items():
                if k.startswith("_note"):
                    continue
                if groups and k not in groups:
                    rep.err("E_EQUITY_SHARE", cf.rel, ptr + "/equity_share_ppm/" + k,
                            "持股键不是真实群组 ID。", "群组 ID", k, "改正。")
                iv = as_int(v)
                if iv is not None:
                    s += iv
            if s != MICRO:
                rep.err("E_EQUITY_SHARE", cf.rel, ptr + "/equity_share_ppm",
                        "持股比例合计 ≠ 1 000 000。", MICRO, s, "调整使合计精确为 1e6。")
        emp = c.get("employment_persons")
        if isinstance(emp, dict):
            want = emp_from_pop.get(cid, {})
            for k in SKILLS:
                a = as_int(emp.get(k)) or 0
                b = want.get(k, 0)
                if groups and a != b:
                    rep.err("E_EMPLOY_MISMATCH", cf.rel, ptr + "/employment_persons/" + k,
                            "cell 侧在岗人数与群组侧就业不一致（故意冗余，交叉校验，INV-151）。",
                            str(b) + "（population_init 侧）", a,
                            "两处必须逐字相等；不一致说明有人只改了一处。")
        for k in ("cash_uu", "capital_value_uu", "inventory_output_uqs", "loss_carryforward_uu"):
            v = as_int(c.get(k))
            if v is None:
                rep.err("E_RANGE", cf.rel, ptr + "/" + k, "缺失或不是整数。", "int", repr(c.get(k)), "补齐。")
            elif v < 0:
                rep.err("E_RANGE", cf.rel, ptr + "/" + k, "不能为负。", ">= 0", v, "改成非负。")
    missing = [x for x in CELL_IDS if x not in seen]
    if missing or len(cells) != 16:
        rep.err("E_CELL_SET", cf.rel, "/cells", "生产单元不是恰好 16 条且齐全。",
                "16 条", str(len(cells)) + " 条；缺 " + ", ".join(missing[:5]), "补齐。")
    index["cells"] = seen


def check_pubserv(cf: ContentFile, rep: Report, index: dict) -> None:
    units = cf.data.get("units")
    if not isinstance(units, list):
        return
    seen = {}
    emp_from_pop = index.get("emp_pubserv") or {}
    for i, u in enumerate(units):
        ptr = "/units/" + str(i)
        if not isinstance(u, dict):
            continue
        pid = u.get("pubserv_id")
        if not isinstance(pid, str) or not ID_PATTERNS["pubserv_id"].match(pid):
            rep.err("E_ID_FORMAT", cf.rel, ptr + "/pubserv_id", "pubserv_id 非法。",
                    ID_PATTERNS["pubserv_id"].pattern, repr(pid), "改成 pubserv.<region>。")
            continue
        seen[pid] = u
        sp = u.get("service_capacity_split_ppm")
        if isinstance(sp, dict):
            s = sum((as_int(v) or 0) for k, v in sp.items() if not k.startswith("_note"))
            if s != MICRO:
                rep.err("E_SERVICE_SPLIT", cf.rel, ptr + "/service_capacity_split_ppm",
                        "服务容量拆分合计 ≠ 1 000 000。", MICRO, s, "调整使合计精确为 1e6。")
        av = as_int(u.get("availability_ppm"))
        if av is None or not (0 <= av <= MICRO):
            rep.err("E_RANGE", cf.rel, ptr + "/availability_ppm", "可用率超出 0..1e6。",
                    "0..1000000", repr(u.get("availability_ppm")), "给 ppm 整数。")
        emp = u.get("employment_persons")
        if isinstance(emp, dict) and index.get("groups"):
            want = emp_from_pop.get(pid, {})
            for k in SKILLS:
                a = as_int(emp.get(k)) or 0
                b = want.get(k, 0)
                if a != b:
                    rep.err("E_EMPLOY_MISMATCH", cf.rel, ptr + "/employment_persons/" + k,
                            "pubserv 侧在岗人数与群组侧 pubserv 就业不一致（INV-151）。",
                            str(b) + "（population_init 侧）", a, "两处必须逐字相等。")
    missing = [x for x in PUBSERV_IDS if x not in seen]
    if missing or len(units) != 4:
        rep.err("E_CELL_SET", cf.rel, "/units", "公共服务单元不是恰好 4 条且齐全。", "4 条",
                str(len(units)) + " 条；缺 " + ", ".join(missing), "补齐。")
    index["pubserv"] = seen


def check_politics(cf: ContentFile, rep: Report, index: dict) -> None:
    d = cf.data
    st = as_int(d.get("seats_total"))
    sg = as_int(d.get("seats_gov"))
    if st is None or st % 2 == 0 or st <= 0:
        rep.err("E_RANGE", cf.rel, "/seats_total", "总席位必须是正奇数。", "奇数 > 0", repr(st),
                "奇数保证简化留任规则不出现平票未定义。")
    if sg is None or st is None or not (0 <= sg <= st):
        rep.err("E_RANGE", cf.rel, "/seats_gov", "执政席位超出 0..seats_total。",
                "0.." + str(st), repr(sg), "改正。")
    ne = as_int(d.get("next_election_q"))
    if ne not in (15, 31):
        rep.err("E_RANGE", cf.rel, "/next_election_q",
                "选举季度非法（q 从 0 起，第 16 / 32 季 = q 15 / 31，INV-127）。",
                "15 或 31", repr(ne), "改成 15。")
    nb = as_int(d.get("next_budget_review_q"))
    if nb is None or nb % 4 != 3:
        rep.err("E_RANGE", cf.rel, "/next_budget_review_q",
                "预算审查季度必须 ≡ 3 (mod 4)（每 4 季审查一次，INV-127）。", "q ≡ 3 (mod 4)",
                repr(nb), "改成 3 / 7 / 11 …")
    ac = as_int(d.get("admin_capacity_ppm"))
    if ac is None or not (0 <= ac <= MICRO):
        rep.err("E_RANGE", cf.rel, "/admin_capacity_ppm", "行政能力超出 0..1e6。",
                "0..1000000", repr(ac), "给 ppm 整数。")
    blocs = d.get("blocs")
    seen = set()
    if isinstance(blocs, list):
        for i, b in enumerate(blocs):
            ptr = "/blocs/" + str(i)
            if not isinstance(b, dict):
                continue
            bid = b.get("bloc_id")
            if not isinstance(bid, str) or not ID_PATTERNS["bloc_id"].match(bid):
                rep.err("E_ID_FORMAT", cf.rel, ptr + "/bloc_id", "bloc_id 非法。",
                        ID_PATTERNS["bloc_id"].pattern, repr(bid), "改成三个合法集团 ID 之一。")
                continue
            seen.add(bid)
            op = as_int(b.get("org_power_ppm"))
            if op is None or not (0 <= op <= MICRO):
                rep.err("E_RANGE", cf.rel, ptr + "/org_power_ppm", "组织力超出 0..1e6。",
                        "0..1000000", repr(op), "给 ppm 整数。")
            if as_int(b.get("resource_uu")) is None:
                rep.err("E_RANGE", cf.rel, ptr + "/resource_uu", "组织资源缺失或不是整数。",
                        "int >= 0", repr(b.get("resource_uu")), "补齐。")
            if not isinstance(b.get("veto_domains"), list):
                rep.err("E_RANGE", cf.rel, ptr + "/veto_domains", "否决域缺失或不是数组。",
                        "array", repr(b.get("veto_domains")), "补齐。")
        if sorted(seen) != sorted(BLOCS) or len(blocs) != 3:
            rep.err("E_RANGE", cf.rel, "/blocs", "利益集团不是恰好 3 个且齐全。",
                    ", ".join(BLOCS), str(len(blocs)) + " 个：" + ", ".join(sorted(seen)), "补齐。")
    sp = d.get("stance_ppm")
    if isinstance(sp, dict):
        for bid, m in sp.items():
            if bid.startswith("_note"):
                continue
            if bid not in BLOCS:
                rep.err("E_ID_FORMAT", cf.rel, "/stance_ppm/" + bid, "立场表键不是合法集团 ID。",
                        ", ".join(BLOCS), bid, "改正。")
                continue
            if not isinstance(m, dict):
                continue
            for pid, v in m.items():
                if pid.startswith("_note"):
                    continue
                if pid not in POLICY_IDS:
                    rep.err("E_ID_FORMAT", cf.rel, "/stance_ppm/" + bid + "/" + pid,
                            "立场表指向不存在的政策 ID。", "policy.P01..P12", pid, "改正。")
                iv = as_int(v)
                if iv is None or not (-MICRO <= iv <= MICRO):
                    rep.err("E_RANGE", cf.rel, "/stance_ppm/" + bid + "/" + pid,
                            "立场值缺失或超出 ±1e6。", "-1000000..1000000", repr(v), "改正。")
    index["politics_present"] = True


# --------------------------------------------------------------------------
# 13 V-PD：政策定义（11 号文件 §5.12 + 计划书 §09/§10）
# --------------------------------------------------------------------------

POLICY_NINE = ["problem_statement_zh", "legal_authority", "cost", "preconditions",
               "lag", "effect", "exit_rule", "political_reaction", "failure_paths"]
POLICY_KINDS = {"rate", "transfer", "subsidy", "project", "capacity", "admin"}


def check_policy(cf: ContentFile, rep: Report, index: dict) -> None:
    d = cf.data
    pid = d.get("policy_id")
    if not isinstance(pid, str) or not ID_PATTERNS["policy_id"].match(pid):
        rep.err("E_ID_FORMAT", cf.rel, "/policy_id", "policy_id 非法。",
                ID_PATTERNS["policy_id"].pattern, repr(pid), "改成 policy.P01..policy.P12。")
        return
    index.setdefault("policies", {})[pid] = cf

    if d.get("kind") not in POLICY_KINDS:
        rep.err("E_POLICY_FIELDS", cf.rel, "/kind", "政策类别非法。",
                " / ".join(sorted(POLICY_KINDS)), repr(d.get("kind")), "改成合法类别。")

    # V-PD-02 九项必填
    for f in POLICY_NINE:
        v = d.get(f)
        if v is None or (isinstance(v, (list, dict, str)) and len(v) == 0):
            rep.err("E_POLICY_FIELDS", cf.rel, "/" + f,
                    "政策九项必填字段缺失或为空（计划书 §09：没有这些字段的政策不进入可玩菜单）。",
                    "非空", repr(v), "补齐；九项 = " + "、".join(POLICY_NINE) + "。")

    la = d.get("legal_authority")
    if isinstance(la, dict):
        check_sub_object(cf, rep, la, "/legal_authority",
                         ["authority_bit", "requires_budget_review",
                          "requires_bloc_support", "min_seats_ppm"], "legal_authority")
        if as_int(la.get("authority_bit")) is None:
            rep.err("E_POLICY_FIELDS", cf.rel, "/legal_authority/authority_bit",
                    "缺少法定权限位。", "int", repr(la.get("authority_bit")), "补齐。")
        ms = as_int(la.get("min_seats_ppm"))
        if ms is None or not (0 <= ms <= MICRO):
            rep.err("E_RANGE", cf.rel, "/legal_authority/min_seats_ppm",
                    "最低席位门槛超出 0..1e6。", "0..1000000", repr(la.get("min_seats_ppm")), "改正。")
        for b in (la.get("requires_bloc_support") or []):
            if b not in BLOCS:
                rep.err("E_ID_FORMAT", cf.rel, "/legal_authority/requires_bloc_support",
                        "引用了不存在的集团 ID。", ", ".join(BLOCS), repr(b), "改正。")

    # V-PD-03 成本恒等式
    cost = d.get("cost")
    if isinstance(cost, dict):
        one = as_int(cost.get("one_off_uu"))
        per = as_int(cost.get("per_quarter_uu"))
        nq = as_int(cost.get("planned_quarters"))
        if one is not None and per is not None and nq is not None:
            if per * nq != one:
                rep.err("E_POLICY_COST", cf.rel, "/cost",
                        "per_quarter_uu × planned_quarters ≠ one_off_uu（INV-092，加载器不做归一化补偿）。",
                        one, str(per) + " × " + str(nq) + " = " + str(per * nq),
                        "分季计划合计必须精确等于合同总额。")
            else:
                rep.info("V-PD-03", cf.rel, "/cost", "分季计划合计等于合同总额。", one, per * nq)
        sl = cost.get("spend_lines_uu_per_q")
        if isinstance(sl, dict):
            s = sum((as_int(v) or 0) for k, v in sl.items() if not k.startswith("_note"))
            if per is not None and s != per:
                rep.err("E_POLICY_COST", cf.rel, "/cost/spend_lines_uu_per_q",
                        "支出落点分项合计 ≠ per_quarter_uu。", per,
                        str(s) + "（差 " + str(s - per) + "）",
                        "各项之和必须精确等于原额；每一笔都要有收款方（计划书 §10）。")
            else:
                rep.info("V-PD-03", cf.rel, "/cost/spend_lines_uu_per_q",
                         "支出落点分项合计等于每季成本。", per, s)
        elif d.get("kind") == "project":
            rep.err("E_POLICY_COST", cf.rel, "/cost/spend_lines_uu_per_q",
                    "工程类政策缺少支出落点拆分。", "至少一项，且各有收款方", "缺失",
                    "计划书 §10 要求每笔支出都有收款方。")
        for k in ("opex_per_q_uu",):
            if k in cost and as_int(cost.get(k)) is None:
                rep.err("E_POLICY_COST", cf.rel, "/cost/" + k, "不是整数。", "int",
                        repr(cost.get(k)), "改正。")

    # V-PD-04 投运时滞
    lag = d.get("lag")
    if isinstance(lag, dict):
        check_sub_object(cf, rep, lag, "/lag",
                         ["enact_to_effect_q", "min_feedback_q", "max_feedback_q",
                          "commission_delay_q"], "lag")
        cd = as_int(lag.get("commission_delay_q"))
        if cd is None or cd < 1:
            rep.err("E_COMMISSION_LAG", cf.rel, "/lag/commission_delay_q",
                    "投运时滞 < 1，会让完工当季就供能（INV-091）。", ">= 1", repr(cd),
                    "S07 只写 pending，S01 才转 active；投运时滞硬性 >= 1 季。")
        mn = as_int(lag.get("min_feedback_q"))
        mx = as_int(lag.get("max_feedback_q"))
        if mn is not None and mx is not None and mn > mx:
            rep.err("E_RANGE", cf.rel, "/lag", "min_feedback_q > max_feedback_q。",
                    "min <= max", str(mn) + " > " + str(mx), "改正。")

    # V-PD-10 / V-PD-11 效果落点
    eff = d.get("effect")
    if isinstance(eff, dict):
        tgt = eff.get("target")
        if tgt not in EFFECT_TARGET_WHITELIST:
            rep.err("E_EFFECT_TARGET", cf.rel, "/effect/target",
                    "效果落点不在白名单内（11 号文件 §5.12）。",
                    "白名单 " + str(len(EFFECT_TARGET_WHITELIST)) + " 项之一", repr(tgt),
                    "改到白名单内的字段；产能类效果只能落在 *_pending_* 上。")
        elif isinstance(tgt, str):
            if eff.get("kind") in ("capacity_delta", "capacity") and "_pending_" not in tgt:
                rep.err("E_EFFECT_TARGET", cf.rel, "/effect/target",
                        "产能／容量类效果没有落在 *_pending_* 字段上（INV-091 的加载期防线）。",
                        "含 _pending_ 的字段", tgt, "改到 pending 轨，由 S01 转 active。")
        ur = eff.get("capacity_unit_ref")
        if ur is not None and ur not in SECTORS:
            rep.err("E_UNIT_MISMATCH", cf.rel, "/effect/capacity_unit_ref",
                    "容量单位参照不是真实部门（V-PD-05）。", ", ".join(SECTORS), repr(ur),
                    "要么改成真实部门（单位须与 io_table 的用电系数同口径），"
                    "要么在非容量类效果上整键省略；"
                    "\"none\" 这类自创哨兵值让「单位一致」变成无法机器判定的口号。")

    # V-PD-09 玩家参数
    pps = d.get("player_params")
    if isinstance(pps, list):
        for i, p in enumerate(pps):
            ptr = "/player_params/" + str(i)
            if not isinstance(p, dict):
                continue
            vr = p.get("valid_range")
            dv = p.get("default")
            if p.get("type") == "enum":
                vals = p.get("values")
                if not isinstance(vals, list) or not vals:
                    rep.err("E_PARAM_RANGE", cf.rel, ptr + "/values", "枚举参数缺少取值集合。",
                            "非空数组", repr(vals), "补齐。")
                    continue
                # 两种合法写法：default 是取值本身（§5.12 的 P04 示例），
                # 或 default 是下标且 valid_range == [0, len-1]（V-PD-09 要求 default ∈ valid_range）。
                idx_ok = (isinstance(vr, list) and len(vr) == 2
                          and vr == [0, len(vals) - 1]
                          and isinstance(dv, int) and not isinstance(dv, bool)
                          and vr[0] <= dv <= vr[1])
                if not (dv in vals or idx_ok):
                    rep.err("E_PARAM_RANGE", cf.rel, ptr + "/default",
                            "枚举默认值既不是取值本身，也不是合法下标。",
                            str(vals) + " 或 [0, " + str(len(vals) - 1) + "] 内的下标", repr(dv),
                            "二选一并保持同一文件内一致；11 号文件 §5.12 的 P04 示例"
                            "（字符串 default、无 valid_range）与 V-PD-09 互相冲突，已登记为待决问题。")
                continue
            if not (isinstance(vr, list) and len(vr) == 2
                    and all(isinstance(x, int) and not isinstance(x, bool) for x in vr)):
                rep.err("E_PARAM_RANGE", cf.rel, ptr + "/valid_range",
                        "缺少 [min, max] 整数区间。", "int[2]", repr(vr), "补齐。")
                continue
            if as_int(dv) is None or not (vr[0] <= dv <= vr[1]):
                rep.err("E_PARAM_RANGE", cf.rel, ptr + "/default", "默认值不在 valid_range 内。",
                        str(vr), repr(dv), "改正。")

    # V-PD-06 / V-PD-07 测试注册表
    treg = index.get("test_ids") or set()
    fps = d.get("failure_paths")
    if isinstance(fps, list):
        if len(fps) < 4:
            rep.err("E_POLICY_FIELDS", cf.rel, "/failure_paths",
                    "可验证的失败路径少于 4 条。", ">= 4", len(fps),
                    "计划书 §09 要求每项政策都有可验证的失败路径；写不出失败测试的政策不进内容包。")
        for i, f in enumerate(fps):
            ptr = "/failure_paths/" + str(i)
            if isinstance(f, str):
                rep.err("E_POLICY_TEST_MISSING", cf.rel, ptr,
                        "失败路径只有代码没有 test_id。", "{code, test_id}", repr(f),
                        "每条失败路径必须绑定一个真实存在的测试用例（V-PD-06）。")
                continue
            if not isinstance(f, dict):
                continue
            tid = f.get("test_id")
            if not isinstance(tid, str) or not tid:
                rep.err("E_POLICY_TEST_MISSING", cf.rel, ptr + "/test_id", "缺少 test_id。",
                        "非空字符串", repr(tid), "绑定测试用例。")
            elif treg and tid not in treg:
                rep.err("E_POLICY_TEST_MISSING", cf.rel, ptr + "/test_id",
                        "失败路径引用的测试用例在测试注册表中不存在（V-PD-06）。",
                        "docs/30_quality_gates.md 测试矩阵中的 ID", tid,
                        "补进测试矩阵与 tests/tools/test_registry.gd，或改成已有 ID。")
    ats = d.get("acceptance_tests")
    if isinstance(ats, list):
        if len(ats) < 5:
            rep.err("E_POLICY_FIELDS", cf.rel, "/acceptance_tests", "验收测试少于 5 条。",
                    ">= 5", len(ats), "补齐；政策必须有可执行的验收判据。")
        for i, t in enumerate(ats):
            if not isinstance(t, str):
                continue
            if treg and t not in treg:
                rep.err("E_POLICY_TEST_MISSING", cf.rel, "/acceptance_tests/" + str(i),
                        "验收测试 ID 在测试注册表中不存在（V-PD-07）。",
                        "docs/30_quality_gates.md 测试矩阵中的 ID", t,
                        "补进测试矩阵，或改成已有 ID。")

    # V-PD-08 机制注册表
    mids = d.get("mechanism_ids")
    if isinstance(mids, list):
        if not mids:
            rep.err("E_MECH_UNKNOWN", cf.rel, "/mechanism_ids", "机制 ID 为空。", "非空",
                    "[]", "政策只能引用已注册机制并给参数，不能自带逻辑。")
        for i, m in enumerate(mids):
            if not isinstance(m, str) or not m.startswith("mech."):
                rep.err("E_MECH_UNKNOWN", cf.rel, "/mechanism_ids/" + str(i),
                        "机制 ID 格式非法。", "mech.<name>", repr(m), "改正。")
            elif m not in index.get("mech_ids", set()):
                rep.warn("E_MECH_UNKNOWN", cf.rel, "/mechanism_ids/" + str(i),
                         "机制 ID 未出现在任何已知机制清单中（MechanismRegistry 尚不存在，见 OQ）。",
                         "MechanismRegistry 已注册的 mech.*", m,
                         "先把 MechanismRegistry 落成代码或文档表，再让 V-PD-08 变成硬失败。")

    # 效果链（计划书 §10 的 PolicyCommand→…→SectorResponse 六环）
    chain = d.get("effect_chain")
    if not isinstance(chain, list):
        rep.err("E_POLICY_FIELDS", cf.rel, "/effect_chain",
                "缺少 effect_chain（计划书 §09「每项至少 1 条完整反馈链」）。",
                ">= 4 环的数组", repr(type(chain).__name__ if chain is not None else None),
                "补一条从命令到部门响应的完整链；注意 11 号文件 §5.12 的 schema 里"
                "没有这个字段，需同步修订契约。")
    elif len(chain) < 4:
        rep.err("E_POLICY_FIELDS", cf.rel, "/effect_chain", "反馈链少于 4 环。", ">= 4",
                len(chain), "补齐到至少 4 环，并逐环写清 settlement_step 与不变量。")

    # 退出规则与政治反应
    er = d.get("exit_rule")
    if isinstance(er, dict):
        for k in ("delivered_assets", "unfinished_work", "compensation_rule"):
            v = er.get(k)
            if not isinstance(v, str) or not v.strip():
                rep.err("E_POLICY_FIELDS", cf.rel, "/exit_rule/" + k,
                        "退出规则字段缺失或为空。", "非空字符串", repr(v),
                        "计划书 §09 要求每项政策写清退出规则。")
            elif v == "none":
                # 契约 §5.12 只给了 "retain" 这一个示例值，没有定义取值集合；
                # 「none」是内容层自创的哨兵值，无法被机器判定含义。
                rep.warn("E_POLICY_FIELDS", cf.rel, "/exit_rule/" + k,
                         "退出规则取值为自创哨兵 \"none\"，契约没有定义取值集合。",
                         "契约定义的枚举值（目前只有示例 retain / register_residual / "
                         "remaining_contract_ppm）", v,
                         "先在 11 号文件 §5.12 补上该字段的取值集合，再回来对齐；"
                         "在此之前 \"none\" 的语义不可测。")
        cp = as_int(er.get("compensation_ppm"))
        if cp is None:
            rep.err("E_POLICY_FIELDS", cf.rel, "/exit_rule/compensation_ppm",
                    "赔偿比例缺失或不是整数。", "int ppm", repr(er.get("compensation_ppm")),
                    "补齐；合同赔偿按剩余合同规则结算（计划书 §10）。")
        elif not (0 <= cp <= MICRO):
            rep.err("E_RANGE", cf.rel, "/exit_rule/compensation_ppm", "赔偿比例超出 0..1e6。",
                    "0..1000000", cp, "改正。")
    pr = d.get("political_reaction")
    if isinstance(pr, dict):
        for k, v in pr.items():
            if k.startswith("_note"):
                continue
            if k not in BLOCS:
                rep.err("E_UNKNOWN_FIELD", cf.rel, "/political_reaction/" + k,
                        "政治反应表里出现不是集团 ID 的键。",
                        "只允许 " + ", ".join(BLOCS), k,
                        "政治反应是「集团 → ppm 增量」的映射；说明性内容放到 _note_<field>。")
            elif as_int(v) is None:
                rep.err("E_RANGE", cf.rel, "/political_reaction/" + k, "不是整数 ppm。",
                        "int", repr(v), "改正。")

    # 前置条件
    pcs = d.get("preconditions")
    if isinstance(pcs, list):
        for i, p in enumerate(pcs):
            ptr = "/preconditions/" + str(i)
            if not isinstance(p, dict):
                continue
            if p.get("kind") == "metric_compare":
                if p.get("op") not in COMPARE_OPS:
                    rep.err("E_EVENT_OP", cf.rel, ptr + "/op", "比较运算符非法。",
                            " / ".join(sorted(COMPARE_OPS)), repr(p.get("op")), "改正。")
                m = p.get("metric")
                vids = index.get("var_ids") or set()
                if vids and isinstance(m, str) and m not in vids:
                    rep.err("E_METRIC_UNKNOWN", cf.rel, ptr + "/metric",
                            "前置条件引用的变量 ID 在变量字典中不存在。",
                            "10 号文件中的稳定 ID", m, "改成真实变量 ID。")

    # P04 逐项对上计划书 §10
    if pid == "policy.P04":
        cost = d.get("cost") or {}
        checks = [
            ("/cost/one_off_uu", as_int(cost.get("one_off_uu")), P04_SPEC["one_off_uu"], "总成本 4 U"),
            ("/cost/per_quarter_uu", as_int(cost.get("per_quarter_uu")),
             P04_SPEC["per_quarter_uu"], "每季 0.5 U"),
            ("/cost/planned_quarters", as_int(cost.get("planned_quarters")),
             P04_SPEC["planned_quarters"], "计划 8 季"),
            ("/cost/opex_per_q_uu", as_int(cost.get("opex_per_q_uu")),
             P04_SPEC["opex_per_q_uu"], "运行费 0.02 U/季"),
            ("/effect/capacity_delta_uqs_per_q",
             as_int(get(d, "effect", "capacity_delta_uqs_per_q")),
             P04_SPEC["capacity_delta_uqs_per_q"], "额外 10 单位可用电力服务"),
        ]
        for ptr, got, want, what in checks:
            if got != want:
                rep.err("E_POLICY_COST", cf.rel, ptr,
                        "P04 与计划书 §10 规格不一致（" + what + "）。", want, repr(got),
                        "P04 的数值是测试夹具，被 T-S-P04-CHAIN 逐季逐笔断言，不能改。")
            else:
                rep.info("V-P04", cf.rel, ptr, "P04 " + what + " 与计划书 §10 一致。", want, got)
        sl = cost.get("spend_lines_uu_per_q")
        if isinstance(sl, dict):
            for k, want in P04_SPEC["spend_lines_uu_per_q"].items():
                got = as_int(sl.get(k))
                if got != want:
                    rep.err("E_POLICY_COST", cf.rel, "/cost/spend_lines_uu_per_q/" + k,
                            "P04 支出落点与计划书 §10 不一致。", want, repr(got),
                            "测试拆分：每季 0.2 U 进口设备、0.1 U 国产材料、0.2 U 施工服务。")
            s = sum((as_int(v) or 0) for k, v in sl.items() if not k.startswith("_note"))
            if s != P04_SPEC["per_quarter_uu"]:
                rep.err("E_POLICY_COST", cf.rel, "/cost/spend_lines_uu_per_q",
                        "P04 支出落点合计 ≠ 每季 0.5 U。", P04_SPEC["per_quarter_uu"], s, "改正。")
            else:
                rep.info("V-P04", cf.rel, "/cost/spend_lines_uu_per_q",
                         "P04 三笔支出落点合计等于每季成本。", P04_SPEC["per_quarter_uu"], s)
        else:
            rep.err("E_POLICY_COST", cf.rel, "/cost/spend_lines_uu_per_q",
                    "P04 缺少支出落点拆分。", "三笔：进口设备/国产材料/施工服务", "缺失", "补齐。")


# --------------------------------------------------------------------------
# 14 V-EV：事件模板（11 号文件 §5.13）
# --------------------------------------------------------------------------

def check_event(cf: ContentFile, rep: Report, index: dict) -> None:
    d = cf.data
    eid = d.get("event_id")
    if not isinstance(eid, str) or not ID_PATTERNS["event_id"].match(eid):
        rep.err("E_ID_FORMAT", cf.rel, "/event_id", "event_id 非法。",
                ID_PATTERNS["event_id"].pattern, repr(eid), "改成 event.E01..event.E12。")
        return
    index.setdefault("events", {})[eid] = cf

    if "ledger_effects" in d:
        rep.err("E_EVENT_LEDGER", cf.rel, "/ledger_effects",
                "首版 schema 中不存在 ledger_effects（事件不得直接动钱）。", "不存在该字段",
                "出现", "花钱必须走政策或项目；这是计划书 §13「禁止后处理补丁」的结构性执行点。")

    vids = index.get("var_ids") or set()
    tr = d.get("trigger")
    if not isinstance(tr, dict):
        rep.err("E_EVENT_FIELD", cf.rel, "/trigger", "缺少触发器。",
                "{all_of, probability_ppm, rng_stream, cooldown_q, max_occurrences}",
                repr(tr), "补齐；触发必须是可求值的比较条件，不是随机弹窗。")
    else:
        conds = None
        for key in ("all_of", "any_of"):
            if isinstance(tr.get(key), list):
                conds = tr[key]
                break
        if not conds:
            rep.err("E_EVENT_FIELD", cf.rel, "/trigger", "触发器没有任何可求值条件。",
                    "all_of 至少 1 条比较", repr(list(tr.keys())),
                    "事件必须由状态条件触发，不能只靠概率弹出。")
        else:
            for i, c in enumerate(conds):
                ptr = "/trigger/all_of/" + str(i)
                if not isinstance(c, dict):
                    rep.err("E_EVENT_OP", cf.rel, ptr, "条件不是对象。", "{metric, op, value}",
                            repr(c), "改正。")
                    continue
                m = c.get("metric")
                if not isinstance(m, str):
                    rep.err("E_METRIC_UNKNOWN", cf.rel, ptr + "/metric", "缺少 metric。",
                            "稳定变量 ID", repr(m), "补齐。")
                elif vids and m not in vids:
                    rep.err("E_METRIC_UNKNOWN", cf.rel, ptr + "/metric",
                            "触发条件引用的变量 ID 在 10 号文件中不存在（V-EV-02）。",
                            "10 号文件中的稳定 ID", m,
                            "改成真实变量 ID；悬空 metric 意味着这条触发永远无法求值。")
                if c.get("op") not in COMPARE_OPS:
                    rep.err("E_EVENT_OP", cf.rel, ptr + "/op",
                            "比较运算符非法（没有表达式求值器，只有六种比较）。",
                            " / ".join(sorted(COMPARE_OPS)), repr(c.get("op")), "改正。")
                if as_int(c.get("value")) is None:
                    rep.err("E_EVENT_FIELD", cf.rel, ptr + "/value", "阈值缺失或不是整数。",
                            "int", repr(c.get("value")), "改正。")
                sc = c.get("scope")
                if sc is not None and isinstance(sc, str):
                    if not any(p.match(sc) for p in (
                            ID_PATTERNS["region_id"], ID_PATTERNS["sector_id"],
                            ID_PATTERNS["cell_id"], ID_PATTERNS["pubserv_id"],
                            ID_PATTERNS["group_id"], ID_PATTERNS["bloc_id"],
                            ID_PATTERNS["policy_id"])) and sc != "national":
                        rep.err("E_ID_FORMAT", cf.rel, ptr + "/scope",
                                "作用域不是合法稳定 ID。",
                                "region./sector./cell./pubserv./group./bloc./policy. 之一或 national",
                                sc, "改正。")
        if tr.get("rng_stream") != "rng.event":
            rep.err("E_EVENT_STREAM", cf.rel, "/trigger/rng_stream",
                    "事件必须用 rng.event 流，不得借用 rng.shock。", "rng.event",
                    repr(tr.get("rng_stream")),
                    "多写一句新闻不得改变经济抽样（计划书 §12）。")
        p = as_int(tr.get("probability_ppm"))
        if p is None or not (0 <= p <= MICRO):
            rep.err("E_EVENT_FIELD", cf.rel, "/trigger/probability_ppm", "概率超出 0..1e6。",
                    "0..1000000", repr(tr.get("probability_ppm")), "改正。")
        cd = as_int(tr.get("cooldown_q"))
        if cd is None or cd < 0:
            rep.err("E_EVENT_FIELD", cf.rel, "/trigger/cooldown_q", "冷却季数缺失或为负。",
                    ">= 0", repr(tr.get("cooldown_q")), "改正。")
        mo = as_int(tr.get("max_occurrences"))
        if mo is None or mo < 1:
            rep.err("E_EVENT_FIELD", cf.rel, "/trigger/max_occurrences",
                    "最大发生次数缺失或 < 1（事件刷屏上限）。", ">= 1",
                    repr(tr.get("max_occurrences")), "改正。")

    effs = d.get("effects")
    if isinstance(effs, list):
        if not effs:
            rep.err("E_EVENT_TARGET", cf.rel, "/effects", "事件没有任何效果。", "至少 1 条",
                    "[]", "补齐。")
        for i, e in enumerate(effs):
            ptr = "/effects/" + str(i)
            if not isinstance(e, dict):
                continue
            check_sub_object(cf, rep, e, ptr, ["target", "scope", "delta_ppm"], "event effect")
            t = e.get("target")
            if t not in EVENT_TARGET_WHITELIST:
                rep.err("E_EVENT_TARGET", cf.rel, ptr + "/target",
                        "事件效果落点不在白名单内（事件不得直接写现金、库存、产能、人口、GDP）。",
                        "、".join(sorted(EVENT_TARGET_WHITELIST)), repr(t),
                        "要花钱必须通过一条政策或项目（INV-130）。")
            if "delta_ppm" not in e:
                rep.err("E_EVENT_TARGET", cf.rel, ptr,
                        "事件效果只能是 delta_ppm 形式。", "delta_ppm",
                        ", ".join(k for k in e if k != "target"), "改正。")
            elif as_int(e.get("delta_ppm")) is None:
                rep.err("E_EVENT_TARGET", cf.rel, ptr + "/delta_ppm", "不是整数。", "int",
                        repr(e.get("delta_ppm")), "改正。")

    ev = d.get("evidence_refs")
    if not isinstance(ev, list) or not ev:
        rep.err("E_EVENT_EVIDENCE", cf.rel, "/evidence_refs",
                "缺少证据引用（计划书 §13「每条变化附带实体 ID」）。", "非空数组", repr(ev),
                "列出可追溯的变量 ID。")
    else:
        for i, v in enumerate(ev):
            if vids and isinstance(v, str) and v not in vids:
                rep.err("E_METRIC_UNKNOWN", cf.rel, "/evidence_refs/" + str(i),
                        "证据引用的变量 ID 在 10 号文件中不存在。", "稳定 ID", v, "改正。")

    if d.get("kind") not in ("inferred", "accounted", "scenario"):
        rep.err("E_EVENT_FIELD", cf.rel, "/kind", "事件类别非法。",
                "inferred / accounted / scenario", repr(d.get("kind")), "改正。")

    # 每条后果必须有对手方或会计解释（任务书 C）
    # OQ-V07（见文件头）：11 号文件 §5.13 的 EventTemplate 键集合里没有 consequences，而 §3 的
    # additionalProperties:false 又禁止未声明的顶层键出现——原实现只认顶层 consequences，
    # 于是「写了后果说明」必然换来 E_UNKNOWN_FIELD，两条规则不可能同时满足。
    # 按 11 号文件 §3 自己给出的出路（扩展字段改名为 _note_<field>），本工具把 _note_consequences
    # 认作合法的书写位置。**检查强度不变**：两处都逐条走同一套 explain_keys 断言，
    # 两处都没有才报错；这里放宽的只是「写在哪个键上」，不是「要不要写」。
    items = []
    cons_keys = [k for k in ("consequences", "_note_consequences") if d.get(k) is not None]
    for key in cons_keys:
        cons = d[key]
        if isinstance(cons, list):
            items += [("/" + key + "/" + str(i), c)
                      for i, c in enumerate(cons) if isinstance(c, dict)]
        elif isinstance(cons, dict):
            for k, v in cons.items():
                if isinstance(v, list):
                    items += [("/" + key + "/" + k + "/" + str(i), x)
                              for i, x in enumerate(v) if isinstance(x, dict)]
    if not cons_keys:
        rep.err("E_EVENT_EVIDENCE", cf.rel, "/consequences",
                "没有逐条后果说明。", "每条后果给出对手方或会计解释", "缺失",
                "计划书 §13 要求每条变化附带实体 ID、来源操作、金额／数量、时间与约束；"
                "契约未声明 consequences 顶层键时写成 _note_consequences（11 号文件 §3）。")
    # 「对手方」= payer/payee/counterparty/agent；「会计解释」= 落在哪个结算步、按哪条公式改哪个字段
    explain_keys = ("explanation_zh", "counterparty", "payer", "payee", "agent",
                    "applied_at", "change_expr", "formula", "formula_zh", "written_by",
                    "mechanism", "mechanism_ref", "accounting_zh", "settlement_step",
                    "duration_note_zh")
    for ptr, c in items:
        if not any(k in c for k in explain_keys):
            rep.err("E_EVENT_EVIDENCE", cf.rel, ptr,
                    "该条后果既没有对手方，也没有会计／机制解释。",
                    "含 " + " / ".join(explain_keys[:6]) + " 之一", ", ".join(sorted(c.keys()))[:120],
                    "补上「谁付给谁」或「落在哪个结算步、按哪条公式」。")


# --------------------------------------------------------------------------
# 15 V-SH：冲击定义（11 号文件 §5.14）
# --------------------------------------------------------------------------

def check_shock(cf: ContentFile, rep: Report, index: dict) -> None:
    d = cf.data
    sid = d.get("shock_id")
    if not isinstance(sid, str) or not ID_PATTERNS["shock_id"].match(sid):
        rep.err("E_ID_FORMAT", cf.rel, "/shock_id", "shock_id 非法。",
                ID_PATTERNS["shock_id"].pattern, repr(sid), "改成 shock.S01..shock.S03。")
        return
    index.setdefault("shocks", {})[sid] = cf
    ch = d.get("channel")
    if ch not in SHOCK_CHANNELS:
        rep.err("E_SHOCK_COUNT", cf.rel, "/channel", "冲击通道非法。",
                " / ".join(SHOCK_CHANNELS), repr(ch), "三类外生冲击各一（计划书 §07）。")
    else:
        index.setdefault("shock_channels", {}).setdefault(ch, []).append(sid)

    if d.get("rng_stream") != "rng.shock":
        rep.err("E_SHOCK_STREAM", cf.rel, "/rng_stream", "冲击必须用 rng.shock 流。",
                "rng.shock", repr(d.get("rng_stream")), "流之间必须结构性独立。")

    tw = d.get("target_weights_ppm")
    tg = d.get("targets")
    if isinstance(tw, list):
        s = sum(x for x in tw if isinstance(x, int) and not isinstance(x, bool))
        if s != MICRO:
            rep.err("E_SHOCK_WEIGHTS", cf.rel, "/target_weights_ppm",
                    "落点权重合计 ≠ 1 000 000。", MICRO, str(s) + "（差 " + str(s - MICRO) + "）",
                    "调整使合计精确为 1e6。")
        else:
            rep.info("V-SH-03", cf.rel, "/target_weights_ppm", "落点权重合计正确。", MICRO, s)
        if isinstance(tg, list) and len(tg) != len(tw):
            rep.err("E_SHOCK_WEIGHTS", cf.rel, "/target_weights_ppm",
                    "权重个数与 targets 个数不一致。", len(tg), len(tw), "一一对应。")
    if isinstance(tg, list):
        for i, t in enumerate(tg):
            if t not in SECTORS:
                rep.err("E_ID_FORMAT", cf.rel, "/targets/" + str(i), "落点不是合法部门 ID。",
                        ", ".join(SECTORS), repr(t), "改正。")

    lf = d.get("log_fields")
    if isinstance(lf, list):
        for need in ("draw_index", "raw_u64", "mapped_value"):
            if need not in lf:
                rep.err("E_SHOCK_LOG", cf.rel, "/log_fields",
                        "抽样日志字段不足以复核（计划书 §07「每次抽样写入日志」）。",
                        "含 " + need, ", ".join(str(x) for x in lf), "补齐三项。")
    else:
        rep.err("E_SHOCK_LOG", cf.rel, "/log_fields", "缺少日志字段声明。", "数组", repr(lf), "补齐。")

    mg = d.get("magnitude_ppm")
    if isinstance(mg, dict):
        lo, hi = as_int(mg.get("min")), as_int(mg.get("max"))
        if lo is None or hi is None:
            rep.err("E_SHOCK_RANGE", cf.rel, "/magnitude_ppm", "强度区间缺失或不是整数。",
                    "{min, max}", repr(mg), "补齐。")
        elif lo > hi:
            rep.err("E_SHOCK_RANGE", cf.rel, "/magnitude_ppm", "min > max。", "min <= max",
                    str(lo) + " > " + str(hi), "改正。")
    dq = d.get("duration_q")
    if isinstance(dq, dict):
        lo, hi = as_int(dq.get("min")), as_int(dq.get("max"))
        if lo is None or hi is None:
            rep.err("E_SHOCK_RANGE", cf.rel, "/duration_q", "持续期区间缺失或不是整数。",
                    "{min, max}", repr(dq), "补齐。")
        else:
            if lo < 1:
                rep.err("E_SHOCK_RANGE", cf.rel, "/duration_q/min", "持续期下界 < 1。", ">= 1",
                        lo, "改正。")
            if lo > hi:
                rep.err("E_SHOCK_RANGE", cf.rel, "/duration_q", "min > max。", "min <= max",
                        str(lo) + " > " + str(hi), "改正。")
    if d.get("onset_profile") not in ("step", "ramp_2q"):
        rep.err("E_SHOCK_RANGE", cf.rel, "/onset_profile", "起效曲线非法。", "step / ramp_2q",
                repr(d.get("onset_profile")), "改正。")
    if d.get("decay_profile") not in ("none", "linear"):
        rep.err("E_SHOCK_RANGE", cf.rel, "/decay_profile", "衰减曲线非法。", "none / linear",
                repr(d.get("decay_profile")), "改正。")
    ar = d.get("arrival")
    if isinstance(ar, dict):
        check_sub_object(cf, rep, ar, "/arrival",
                         ["hazard_ppm_per_q", "earliest_q", "min_gap_q", "max_active"], "arrival")
        hz = as_int(ar.get("hazard_ppm_per_q"))
        if hz is None or not (0 <= hz <= MICRO):
            rep.err("E_SHOCK_RANGE", cf.rel, "/arrival/hazard_ppm_per_q",
                    "到达风险率超出 0..1e6。", "0..1000000", repr(ar.get("hazard_ppm_per_q")), "改正。")

    # 概率档位合计必须 == 1 000 000（任务书 C）
    found_tiers = False
    for ptr, node in deep_find(d, lambda n: isinstance(n, list) and n and all(
            isinstance(x, dict) and "probability_ppm" in x for x in n)):
        found_tiers = True
        s = sum((as_int(x.get("probability_ppm")) or 0) for x in node)
        if s != MICRO:
            rep.err("E_SHOCK_WEIGHTS", cf.rel, ptr,
                    "概率档位合计 ≠ 1 000 000。", MICRO, str(s) + "（差 " + str(s - MICRO) + "）",
                    "档位是对同一均匀分布的等价读数，合计必须精确为 1e6。")
        else:
            rep.info("V-SH-TIER", cf.rel, ptr, "概率档位合计正确。", MICRO, s)
    if not found_tiers:
        rep.warn("E_SHOCK_RANGE", cf.rel, "/", "文件中没有任何概率档位表可供校验合计。",
                 "至少一组 probability_ppm 档位", "无",
                 "若采用纯区间均匀抽样，请显式登记等价档位表，否则「概率合计 1e6」这条无法被机器检查。")

    # V-SH-04 写入范围。只看「这条数据本身就是一个状态字段 ID」的位置：
    # 值必须整串等于一个 state.* ID，且不在中文说明键（*_zh / _note*）下。
    # 说明文字里提到 state.cell.* 是解释，不是写入；把散文当写入会淹掉真正的越界。
    for ptr, node in walk(d, skip_notes=True):
        if not isinstance(node, str) or not node.startswith("state."):
            continue
        last = ptr.rsplit("/", 1)[-1]
        if last.endswith("_zh") or last.endswith("_note") or not re.fullmatch(
                r"state\.[a-z0-9_.]+", node):
            continue
        if node.startswith("state.world."):
            if node not in SHOCK_TARGET_WHITELIST:
                rep.err("E_SHOCK_SCOPE", cf.rel, ptr,
                        "冲击引用的 state.world 字段不在可写白名单内。",
                        "、".join(sorted(SHOCK_TARGET_WHITELIST)), node, "改正。")
        else:
            rep.err("E_SHOCK_SCOPE", cf.rel, ptr,
                    "冲击以字段形式引用了非 state.world 的状态（冲击只能写 state.world.*）。",
                    "state.world.* 白名单", node,
                    "冲击不得直接写国内账户、产能、库存或人口（INV-108）。")


# --------------------------------------------------------------------------
# 16 V-PC：参数身份证（11 号文件 §5.15）
# --------------------------------------------------------------------------

def check_param_card(cf: ContentFile, rep: Report, card: Any, ptr: str, index: dict) -> None:
    if not isinstance(card, dict):
        return
    pid = card.get("parameter_id")
    for f in PARAM_CARD_REQUIRED:
        if f not in card:
            rep.err("E_PARAM_CARD", cf.rel, ptr + "/" + f,
                    "参数身份证缺字段（九字段缺一即失败，计划书 §14）。", "存在且非空", "缺失",
                    "九字段 = " + "、".join(PARAM_CARD_REQUIRED) + "。")
        elif isinstance(card[f], str) and not card[f].strip():
            rep.err("E_PARAM_CARD", cf.rel, ptr + "/" + f, "参数身份证字段为空串。",
                    "非空", "''", "补齐真实内容。")
    if isinstance(pid, str):
        if not ID_PATTERNS["param_id"].match(pid):
            rep.err("E_ID_FORMAT", cf.rel, ptr + "/parameter_id", "parameter_id 非法。",
                    ID_PATTERNS["param_id"].pattern, pid, "改成 param.<snake_name>。")
        prev = index.setdefault("param_cards", {})
        if pid in prev and prev[pid] != (cf.rel, ptr):
            rep.err("E_DUP_ID", cf.rel, ptr + "/parameter_id",
                    "同一 parameter_id 出现在多处。", "全集唯一",
                    pid + "（另一处：" + prev[pid][0] + prev[pid][1] + "）",
                    "参数卡必须只有一处事实来源。")
        else:
            prev[pid] = (cf.rel, ptr)

    stype = card.get("source_type")
    if stype not in SOURCE_TYPES:
        rep.err("E_PARAM_CARD", cf.rel, ptr + "/source_type", "source_type 非法。",
                " / ".join(sorted(SOURCE_TYPES)), repr(stype), "只能是四者之一。")
    elif stype == "observed":
        rep.err("E_FAKE_OBSERVED", cf.rel, ptr + "/source_type",
                "首版内容包中 observed 条目数必须为 0（计划书 §19：数据尚未导入）。",
                "0 条 observed", "observed",
                "此刻出现 observed 只可能是伪造；改成 design_assumption 并如实标注。")
    if card.get("confidence") not in CONFIDENCES:
        rep.err("E_PARAM_CARD", cf.rel, ptr + "/confidence", "confidence 非法。",
                " / ".join(sorted(CONFIDENCES)), repr(card.get("confidence")), "改正。")
    ry = card.get("reference_year")
    if as_int(ry) is None:
        rep.err("E_PARAM_CARD", cf.rel, ptr + "/reference_year", "reference_year 不是整数。",
                "int（虚构剧本的 design_assumption 填 0）", repr(ry), "改正。")
    val = card.get("value")
    vr = card.get("valid_range")
    vals = None
    if isinstance(val, int) and not isinstance(val, bool):
        vals = [val]
    elif isinstance(val, list) and val and all(
            isinstance(x, int) and not isinstance(x, bool) for x in val):
        vals = list(val)
    else:
        rep.err("E_PARAM_CARD", cf.rel, ptr + "/value", "value 必须是整数或非空整数数组。",
                "int 或 int[]", repr(val)[:80], "禁止 float / bool / null / 字符串。")
    if not (isinstance(vr, list) and len(vr) == 2
            and all(isinstance(x, int) and not isinstance(x, bool) for x in vr)):
        rep.err("E_PARAM_RANGE", cf.rel, ptr + "/valid_range",
                "valid_range 必须是 [min, max] 两个整数。", "int[2]", repr(vr)[:80], "改正。")
    elif vals is not None:
        for i, v in enumerate(vals):
            if not (vr[0] <= v <= vr[1]):
                rep.err("E_PARAM_RANGE", cf.rel, ptr + "/value",
                        "value 落在 valid_range 之外。", str(vr), v, "调整取值或区间。")
                break
        if vr[0] > vr[1]:
            rep.err("E_PARAM_RANGE", cf.rel, ptr + "/valid_range", "min > max。", "min <= max",
                    str(vr), "改正。")
    if stype == "derived" and not card.get("derivation_expr"):
        rep.err("E_PARAM_DERIVE", cf.rel, ptr + "/derivation_expr",
                "derived 类参数必须给出推导式并被复算验证（V-PC-05）。", "非空", "缺失",
                "写出 derivation_expr，或改成 design_assumption。")
    sr = card.get("source_ref")
    if stype in ("observed", "literature") and isinstance(sr, str):
        if not re.search(r"\d{4}", sr):
            rep.err("E_FAKE_OBSERVED", cf.rel, ptr + "/source_ref",
                    "observed / literature 的出处缺少可核验的年份或下载日期。",
                    "含数据集名 + 下载日期", sr[:80], "补齐出处。")


# --------------------------------------------------------------------------
# 17 布局、全局 ID 与跨文件引用
# --------------------------------------------------------------------------

def contract_path_for(cf: ContentFile) -> str:
    """这份文件按 11 号文件 §2 应该叫什么名字（据 schema_kind 与其内部 ID 判定）。"""
    k = cf.schema_kind
    d = cf.data if isinstance(cf.data, dict) else {}
    if k == "policy_definition" and isinstance(d.get("policy_id"), str):
        return "policies/policy_" + d["policy_id"].split(".")[-1] + ".json"
    if k == "event_template" and isinstance(d.get("event_id"), str):
        return "events/event_" + d["event_id"].split(".")[-1] + ".json"
    if k == "shock_definition" and isinstance(d.get("shock_id"), str):
        return "shocks/shock_" + d["shock_id"].split(".")[-1] + ".json"
    fixed = {
        "scenario": "scenarios/chengwan/scenario.json",
        "io_table": "scenarios/chengwan/io_table.json",
        "regions": "scenarios/chengwan/regions.json",
        "population_init": "scenarios/chengwan/population_init.json",
        "cells_init": "scenarios/chengwan/cells_init.json",
        "pubserv_init": "scenarios/chengwan/pubserv_init.json",
        "government_init": "scenarios/chengwan/government_init.json",
        "politics_init": "scenarios/chengwan/politics_init.json",
        "assertions": "scenarios/chengwan/assertions.json",
        "parameter_set": "parameters/params_core.json",
        "parameter_registry": "parameters/registry.json",
    }
    return fixed.get(k, "")


def check_layout(files: list, rep: Report, index: dict) -> None:
    have = set(index["by_rel"])
    claimed: dict = {}
    for cf in files:
        if not cf.ok:
            continue
        want = contract_path_for(cf)
        if not want:
            rep.err("E_CONTENT_LAYOUT", "content/" + cf.rel, "",
                    "内容包中出现 11 号文件 §2 未定义的文件（schema_kind 也不在契约类型集合内）。",
                    "§2 的固定布局", cf.rel + "（schema_kind=" + (cf.schema_kind or "?") + "）",
                    "改名到契约路径，或先修订契约再登记新文件；"
                    "未定义的文件不会被载入器读到，也不会进 content_hash 的既定顺序。")
            continue
        claimed.setdefault(want, []).append(cf.rel)
        if cf.rel != want:
            rep.err("E_CONTENT_LAYOUT", "content/" + cf.rel, "",
                    "文件路径不符合 11 号文件 §2 规定的内容包布局。", want, cf.rel,
                    "改名成契约路径；载入器按固定路径读（scenario.includes 也按这个名字引用），"
                    "改名等于这份内容不存在。")
    for req in REQUIRED_FILES:
        if req not in have and req not in claimed:
            rep.err("E_CONTENT_LAYOUT", "content/" + req, "",
                    "11 号文件 §2 规定的内容包文件缺失，且没有任何文件自称是它。", req, "不存在",
                    "补齐该文件；缺它意味着对应的载入期校验整条无法执行。")
    for want, lst in sorted(claimed.items()):
        if len(lst) > 1:
            rep.err("E_CONTENT_LAYOUT", "content/" + want, "",
                    "多个文件声称自己是同一份契约文件。", "唯一", ", ".join(sorted(lst)),
                    "只保留一份事实来源。")


# ID「声明点」：只有这些位置算声明，其余出现一律是引用（引用允许重复）
DECLARATION_SITES = {
    "scenario_id": ("scenario", ""),
    "region_id": ("regions", "/regions/"),
    "cell_id": ("cells_init", "/cells/"),
    "pubserv_id": ("pubserv_init", "/units/"),
    "group_id": ("population_init", "/groups/"),
    "policy_id": ("policy_definition", ""),
    "event_id": ("event_template", ""),
    "shock_id": ("shock_definition", ""),
    "bloc_id": ("politics_init", "/blocs/"),
    "bond_id": ("government_init", "/bonds/"),
}
ID_FIELDS = tuple(DECLARATION_SITES) + ("parameter_id",)


def collect_global_ids(files: list, rep: Report, index: dict) -> None:
    """稳定 ID 的格式与唯一性。

    唯一性只对**声明点**成立：`bloc.business` 出现在十个政策的 political_reaction 里是引用，
    不是重复声明。把引用当重复会淹掉真正的 ID 复用缺陷。
    """
    owners: dict = {}
    for cf in files:
        if not cf.ok or not isinstance(cf.data, dict) or cf.schema_kind not in SCHEMAS:
            continue
        if cf.schema_kind in GENERATED_KINDS:
            continue        # §5.16：登记表里的 parameter_id 是索引副本，不是声明点

        for ptr, node in walk(cf.data, skip_notes=True):
            if not isinstance(node, dict):
                continue
            for f in ID_FIELDS:
                v = node.get(f)
                if not isinstance(v, str):
                    continue
                fptr = ptr + "/" + f
                pat = ID_PATTERNS.get(f)
                if pat and not pat.match(v):
                    rep.err("E_ID_FORMAT", cf.rel, fptr, "稳定 ID 不符合命名规则。",
                            pat.pattern, v, "改正；ID 命名规则是机器可检查的契约。")
                if f == "parameter_id":
                    is_decl = True
                else:
                    kind, prefix = DECLARATION_SITES[f]
                    is_decl = cf.schema_kind == kind and ptr.startswith(prefix) and (
                        ptr.count("/") <= prefix.count("/") + 1)
                if not is_decl:
                    continue
                key = (f, v)
                if key in owners:
                    rep.err("E_DUP_ID", cf.rel, fptr,
                            "同一稳定 ID 被声明了两次。", "全局唯一",
                            v + "（另一处：" + owners[key][0] + owners[key][1] + "）",
                            "ID 一经进入存档即永不复用；改名必须新增 ID 并在 id_aliases.json 登记。")
                else:
                    owners[key] = (cf.rel, fptr)
    index["id_owners"] = owners


def check_cross_refs(rep: Report, index: dict) -> None:
    pol = index.get("policies") or {}
    ev = index.get("events") or {}
    sh = index.get("shocks") or {}
    if len(pol) != 12:
        rep.err("E_POLICY_COUNT", "content/policies/", "",
                "政策文件数不是 12（缺一不可）。", 12,
                str(len(pol)) + " 个：" + ", ".join(sorted(pol)),
                "补齐 policy.P01..policy.P12。")
    else:
        missing = [p for p in POLICY_IDS if p not in pol]
        if missing:
            rep.err("E_POLICY_COUNT", "content/policies/", "", "政策 ID 不连续。",
                    "P01..P12", "缺 " + ", ".join(missing), "补齐。")
        else:
            rep.info("V-PD-01", "content/policies/", "", "12 个政策齐全且 ID 连续。",
                     "policy.P01..P12", "12 个")
    if len(ev) != 12:
        rep.err("E_EVENT_COUNT", "content/events/", "", "事件文件数不是 12。", 12,
                str(len(ev)) + " 个", "补齐 event.E01..event.E12。")
    else:
        rep.info("V-EV-01", "content/events/", "", "12 个事件齐全。", "event.E01..E12", "12 个")
    if len(sh) != 3:
        rep.err("E_SHOCK_COUNT", "content/shocks/", "", "冲击文件数不是 3。", 3,
                str(len(sh)) + " 个", "补齐 shock.S01..shock.S03。")
    ch = index.get("shock_channels") or {}
    for c in SHOCK_CHANNELS:
        n = len(ch.get(c, []))
        if n != 1:
            rep.err("E_SHOCK_COUNT", "content/shocks/", "",
                    "冲击通道 " + c + " 不是恰好一个。", 1,
                    str(n) + "：" + ", ".join(ch.get(c, [])),
                    "三类外生冲击各一（计划书 §07）。")
    if all(len(ch.get(c, [])) == 1 for c in SHOCK_CHANNELS):
        rep.info("V-SH-01", "content/shocks/", "", "三类冲击通道各一。",
                 ", ".join(SHOCK_CHANNELS), "各 1 个")

    # 参数集合引用
    psr = index.get("param_set_ref")
    if psr and psr not in (index.get("param_set_ids") or set()):
        rep.err("E_NOT_FOUND", "content/scenarios/chengwan/scenario.json", "/param_set_ref",
                "剧本引用的参数集合不存在（没有任何 schema_kind == parameter_set 的文件声明它）。",
                psr, "未找到",
                "按 11 号文件 §5.15 建 content/parameters/params_core.json，"
                "顶层 param_set_id / param_set_version / cards。")

    # 契约要求的参数最小集
    have = set(index.get("param_cards") or {})
    want = index.get("param_min_set") or []
    miss = [p for p in want if p not in have]
    if miss:
        rep.err("E_PARAM_COVERAGE", "content/parameters/", "",
                "11 号文件 §5.15「首版必备参数最小集」未覆盖。",
                str(len(want)) + " 个必备参数", "缺 " + str(len(miss)) + " 个："
                + ", ".join(miss[:12]) + (" …" if len(miss) > 12 else ""),
                "逐个建九字段齐全的卡；SimCore 里每个裸数字都必须有对应卡（INV-152）。")

    # V-PC-07：IO 表整表共用的集合级参数卡
    if "param.io_table_set" not in have:
        rep.err("E_PARAM_STALE", "content/parameters/", "",
                "缺少 IO 表的集合级参数卡 param.io_table_set（11 号文件 §5.15 的唯一例外条款）。",
                "九字段齐全，value 记 IOTable 规范化哈希前 16 位十进制截断",
                "未找到有效卡",
                "补这张卡；没有它，「改了技术系数却忘了更新校准说明」不会被任何检查发现。")

    # 参数卡交叉约束
    cards = index.get("param_values") or {}
    def pv(name):
        v = cards.get(name)
        return v if isinstance(v, int) else None
    tr_rec, tr_drop = pv("param.trust_recover_ppm"), pv("param.trust_drop_ppm")
    if tr_rec is not None and tr_drop is not None and not (tr_rec < tr_drop):
        rep.err("E_PARAM_RANGE", "content/parameters/", "",
                "信任恢复必须慢于下降（INV-122）。",
                "trust_recover_ppm < trust_drop_ppm",
                str(tr_rec) + " >= " + str(tr_drop),
                "短期补贴不能自动修复长期失信（计划书 §08）。")
    for trio, label in (
            (("param.migration_w_wage_ppm", "param.migration_w_job_ppm",
              "param.migration_w_service_ppm"), "迁移拉力三项权重"),
            (("param.migration_w_house_ppm", "param.migration_w_env_ppm"), "迁移推力两项权重"),
            (("param.bloc_org_inertia_ppm", "param.bloc_w_size_ppm",
              "param.bloc_w_resource_ppm"), "组织力惯性与两项权重")):
        vs = [pv(x) for x in trio]
        if all(v is not None for v in vs):
            s = sum(vs)
            if s != MICRO:
                rep.err("E_PARAM_RANGE", "content/parameters/", "",
                        label + "合计 ≠ 1 000 000。", MICRO, s, "调整使合计精确为 1e6。")

    # 全经济现金恒定（INV-018）
    decl = index.get("total_cash_declared")
    if decl is not None:
        parts = {
            "agent.gov": index.get("gov_cash_uu"),
            "agent.invpool": index.get("invpool_cash_uu"),
            "agent.row": index.get("world_cash_uu"),
        }
        groups = index.get("groups") or {}
        parts["agent.group ×36"] = (sum((as_int(g.get("cash_uu")) or 0)
                                        for g in groups.values()) if groups else None)
        cells = index.get("cells") or {}
        parts["agent.cell ×16"] = (sum((as_int(c.get("cash_uu")) or 0)
                                       for c in cells.values()) if cells else None)
        unknown = [k for k, v in parts.items() if v is None]
        if unknown:
            rep.err("E_CASH_TOTAL", "content/scenarios/chengwan/scenario.json",
                    "/total_cash_uu",
                    "无法核对全经济现金总量（INV-018）：部分主体的初始现金没有数据来源。",
                    "gov + invpool + row + 36 群组 + 16 cell 的现金之和 == " + str(decl),
                    "缺少 " + ", ".join(unknown) + " 的初值文件",
                    "补齐缺失的 *_init 文件；现金总量恒定是「无来源资金」检验的前提（计划书 §15 G1 门槛）。")
        else:
            s = sum(parts.values())
            if s != decl:
                rep.err("E_CASH_TOTAL", "content/scenarios/chengwan/scenario.json",
                        "/total_cash_uu", "各主体现金初值之和 ≠ total_cash_uu（INV-018）。",
                        decl, str(s) + "（差 " + str(s - decl) + "）；明细 " + str(parts),
                        "两侧必须精确相等。")
            else:
                rep.info("INV-018", "content/scenarios/chengwan/scenario.json",
                         "/total_cash_uu", "全经济现金总量对账通过。", decl, s)

    # 基年 GDP == 100 U，以及投入产出表的行合计 == 列合计
    if not index.get("cells"):
        rep.err("E_GDP_INIT", "content/scenarios/chengwan/", "",
                "无法核对基年全年名义 GDP == 100 U（计划书 §05，assert.base_year_gdp）。",
                str(BASE_YEAR_GDP_UU) + " μU（生产法口径）",
                "缺少 cells_init.json：io_table 只有技术系数，没有生产水平，GDP 无从算起",
                "补齐 cells_init.json（16 个 cell 的产能、资本、库存、就业与现金），"
                "校验器才能用「总产出 − 中间投入」复算增加值并与 100 U 对账。")
        rep.err("E_GDP_INIT", "content/scenarios/chengwan/io_table.json", "",
                "无法核对投入产出表的行合计 == 列合计。",
                "每个部门：总产出 == 中间使用 + 最终使用；"
                "投入合计 == 中间投入 + 增加值",
                "content/ 里只有系数矩阵，没有基年水平的投入产出交易表",
                "行列平衡是一个关于**水平表**的恒等式，系数矩阵本身无法表达它。"
                "要么补 cells_init.json 让校验器自己生成水平表并配平，"
                "要么在契约里正式登记「首版不做行列平衡」并说明理由。")
    else:
        cells = index["cells"]
        coeff = index.get("io_coeff") or {}
        if coeff:
            gross = 0
            inter = 0
            for cid, c in cells.items():
                s = "sector." + cid.split(".")[2]
                q = as_int(c.get("capacity_active_uqs_per_q")) or 0
                gross += q
                for r in SECTORS:
                    inter += (q * coeff.get((r, s), 0)) // MICRO
            va_q_uqs = gross - inter                       # μQ_s/季
            # R-SCALE-01：增加值是 μQ_s，GDP 目标是 μU，两者差一个基年价。
            # 旧代码直接拿 μQ_s 与 100 U 比，等于隐含 1 μU == 1 μQ_s——那只在 1 U = 1e6 μU
            # 的旧刻度下成立，新刻度下它把任何正确的剧本都判成差 1000 倍。
            va_year = va_q_uqs * 4 * BASE_PRICE_UU_PER_UQS
            if va_year != BASE_YEAR_GDP_UU:
                rep.err("E_GDP_INIT", "content/scenarios/chengwan/cells_init.json", "",
                        "按基年价（" + str(BASE_PRICE_UU_PER_UQS)
                        + " μU/μQ_s）复算的基年全年增加值 ≠ 100 U。",
                        BASE_YEAR_GDP_UU,
                        str(va_year) + "（季度总产出 " + str(gross) + " − 中间投入 "
                        + str(inter) + " = " + str(va_q_uqs) + " μQ_s，×4 季 × 基年价）",
                        "调整 cells_init 的产能水平；GDP 是核算结果，不是直接写上去的数。")
            else:
                rep.info("V-GDP", "content/scenarios/chengwan/cells_init.json", "",
                         "基年全年名义 GDP 复算等于 100 U。", BASE_YEAR_GDP_UU, va_year)

    # 就业两侧交叉对账（V-POP-08 / INV-151）
    if index.get("groups") and not index.get("cells"):
        rep.err("E_EMPLOY_MISMATCH", "content/scenarios/chengwan/", "",
                "无法执行「群组侧就业 == cell / pubserv 侧在岗人数」的冗余交叉校验（V-POP-08，INV-151）。",
                "两侧逐 (地区, 部门, 技能) 相等",
                "缺少 cells_init.json 与 pubserv_init.json",
                "补齐这两个文件；这条冗余校验是「就业人数不超过同口径劳动力」"
                "（计划书 §17）唯一的机器执行点。")

    # assertions.json
    if not index.get("assertions_seen"):
        rep.err("E_CONTENT_LAYOUT", "content/scenarios/chengwan/assertions.json", "",
                "缺少载入期冗余断言文件（11 号文件 §5.11）。",
                "至少 11 条 checks，tolerance 一律 0（失业率 500 ppm 为唯一例外）", "文件不存在",
                "补齐；没有它，「账能对上」只能靠人工复核。")


def check_assertions(cf: ContentFile, rep: Report, index: dict) -> None:
    index["assertions_seen"] = True
    checks = cf.data.get("checks")
    if not isinstance(checks, list):
        return
    nonzero = 0
    for i, c in enumerate(checks):
        ptr = "/checks/" + str(i)
        if not isinstance(c, dict):
            continue
        check_sub_object(cf, rep, c, ptr, ["id", "at", "expr", "expect", "tolerance"],
                         "assertion")
        at = c.get("at")
        if not (at == "load" or (isinstance(at, str) and at.startswith("q_end:"))):
            rep.err("E_ASSERT_TOLERANCE", cf.rel, ptr + "/at", "at 取值非法。",
                    "load 或 q_end:<n>", repr(at), "改正。")
        tol = as_int(c.get("tolerance"))
        if tol is None:
            rep.err("E_ASSERT_TOLERANCE", cf.rel, ptr + "/tolerance", "容差缺失或不是整数。",
                    "int", repr(c.get("tolerance")), "补齐。")
        elif tol != 0:
            nonzero += 1
            if not (c.get("id") == "assert.unemployment" and tol == UNEMP_TOL_PPM):
                rep.err("E_ASSERT_TOLERANCE", cf.rel, ptr + "/tolerance",
                        "出现协议之外的非零容差。",
                        "0（唯一例外：assert.unemployment 的 500 ppm）", tol,
                        "放宽必须改协议，不能偷偷改数据。")
    ids = set(c.get("id") for c in checks if isinstance(c, dict))
    for need in ("assert.total_population", "assert.region_population",
                 "assert.unemployment", "assert.gov_debt", "assert.gov_cash",
                 "assert.annual_deficit", "assert.base_prices", "assert.living_index",
                 "assert.interest_in_spend", "assert.base_year_gdp", "assert.cash_total"):
        if need not in ids:
            rep.err("E_ASSERT_TOLERANCE", cf.rel, "/checks",
                    "缺少 11 号文件 §5.11 列出的冗余断言。", need, "缺失", "补齐该条断言。")


def check_parameter_set(cf: ContentFile, rep: Report, index: dict) -> None:
    d = cf.data
    psid = d.get("param_set_id")
    if isinstance(psid, str):
        index.setdefault("param_set_ids", set()).add(psid)
        if not ID_PATTERNS["paramset_id"].match(psid):
            rep.err("E_ID_FORMAT", cf.rel, "/param_set_id", "param_set_id 非法。",
                    ID_PATTERNS["paramset_id"].pattern, psid, "改成 paramset.<snake_name>。")
    cards = d.get("cards")
    if isinstance(cards, list):
        for i, c in enumerate(cards):
            check_param_card(cf, rep, c, "/cards/" + str(i), index)
            if isinstance(c, dict) and isinstance(c.get("parameter_id"), str):
                index.setdefault("param_values", {})[c["parameter_id"]] = c.get("value")


def scan_embedded_param_cards(files: list, rep: Report, index: dict) -> None:
    """参数卡散落在政策 / 事件 / 剧本文件里时，同样按九字段校验并登记覆盖情况。"""
    scattered: dict = {}
    for cf in files:
        if not cf.ok or cf.schema_kind == "parameter_set" or cf.schema_kind not in SCHEMAS:
            continue
        if cf.schema_kind in GENERATED_KINDS:
            continue        # §5.16：登记表里的卡是源文件的索引副本，不是第二处声明
        for ptr, node in walk(cf.data, skip_notes=True):
            if not (isinstance(node, dict) and "parameter_id" in node
                    and ("value" in node or "valid_range" in node)):
                continue
            check_param_card(cf, rep, node, ptr, index)
            pid = node.get("parameter_id")
            if isinstance(pid, str):
                index.setdefault("param_values", {}).setdefault(pid, node.get("value"))
                scattered.setdefault(cf.rel, []).append(pid)
    for rel, pids in sorted(scattered.items()):
        rep.warn("E_PARAM_CARD", rel, "/",
                 "本文件内嵌了 " + str(len(pids)) + " 张参数身份证，但它不是 parameter_set 文件。",
                 "全部 param.* 卡集中在 content/parameters/params_core.json",
                 ", ".join(pids[:8]) + (" …" if len(pids) > 8 else ""),
                 "参数集合有独立版本线 param_set_version（11 号文件 §6.7 M-9）；"
                 "卡片散落会让「改参数不改状态形状」的版本判断失效，"
                 "也让 param_set_ref 无从解析。")
    # 藏在 _note_* 注释子树里的参数卡：载入器按契约不读注释键，等于没有这张卡
    for cf in files:
        if not cf.ok or cf.schema_kind not in SCHEMAS:
            continue
        if cf.schema_kind in GENERATED_KINDS:
            continue        # §5.16：登记表整份不参与内容校验（V-PR-02 只比对源文件）
        deep = set(p for p, _ in walk(cf.data, skip_notes=True))
        for ptr, node in walk(cf.data):
            if (isinstance(node, dict) and "parameter_id" in node
                    and ("value" in node or "valid_range" in node) and ptr not in deep):
                rep.err("E_PARAM_CARD", cf.rel, ptr,
                        "参数身份证写在 _note_* 注释子树里，载入器不读注释键，等于这张卡不存在。",
                        "放在 parameter_set 的 cards[] 中",
                        str(node.get("parameter_id")),
                        "移到 content/parameters/params_core.json；"
                        "注释键不进逻辑、不进 content_hash（11 号文件 §1.5、§6.4）。")


def load_param_min_set(docs_dir: str) -> list:
    """从 11 号文件 §5.15「首版必备参数最小集」表里读 parameter_id。"""
    p = os.path.join(docs_dir, "11_data_contract.md")
    out: list = []
    if not os.path.isfile(p):
        return out
    txt = open(p, encoding="utf-8").read()
    # 原正则要求标题写成加粗的 `**首版必备参数最小集**`，而契约里它是小节标题
    # `#### 5.15.2 首版必备参数最小集`（11 号文件改版时下沉为 §5.15.2，编号变化未同步到这里）。
    # 于是 m 恒为 None、最小集恒为空表，V-PC-06 的覆盖检查**从未真正执行过**——
    # 对照证据：tools/build_param_registry.py 用另一套正则读到的是 72 项
    # （registry.json 的 summary.contract_min_set_size == 72）。
    # 改法：定位小节标题，取到下一个 markdown 标题为止，只认表格行（以 `|` 开头），
    # 这样「本表」= 契约里那张表，正文里的举例与 ⚠ 说明不会混进来。
    m = re.search(r"首版必备参数最小集[^\n]*\n(.*?)(?=\n#{1,6} |\Z)", txt, re.S)
    block = m.group(1) if m else ""
    for line in block.splitlines():
        if not line.lstrip().startswith("|"):
            continue
        for pid in re.findall(r"`(param\.[a-z][a-z0-9_]*)(?:\[\d+\])?`", line):
            if pid not in out:
                out.append(pid)
    return out


def load_mech_ids(docs_dir: str) -> set:
    out = set()
    for name in ("21_report_templates.md", "11_data_contract.md", "12_simulation_contract.md"):
        p = os.path.join(docs_dir, name)
        if os.path.isfile(p):
            txt = open(p, encoding="utf-8").read()
            for m in re.findall(r"`(mech\.[a-z][a-z0-9_]*)`", txt):
                out.add(m)
            for m in re.findall(r'"(mech\.[a-z][a-z0-9_]*)"', txt):
                out.add(m)
    return out


# --------------------------------------------------------------------------
# 17.5 ParameterRegistry（11 号文件 §5.16 / 裁定 R-SCHEMA-01）
# --------------------------------------------------------------------------

def check_parameter_registry(cf, rep: Report, index: dict) -> None:
    """V-PR-01..04。

    §5.16 的原文：「校验器检查它『是否与源文件一致』，而不是检查它的内容本身。」
    所以这里**不**逐卡校验九字段（那是 scan_embedded_param_cards 对源文件做的事），
    只做四件事：头部常量、与生成器输出逐字节相等、出处可解析、不被加载器读到。
    """
    d = cf.data if isinstance(cf.data, dict) else {}

    # ---- V-PR-01：schema_kind == "parameter_registry" 且 generated == 1 ----
    gen = d.get("generated")
    if gen != 1 or isinstance(gen, bool):
        rep.err("E_SCHEMA_HEADER", cf.rel, "/generated",
                "生成产物必须自报 generated == 1。", 1, repr(gen),
                "这是「本文件不是手写的」的唯一机读标记（§5.16 V-PR-01）；"
                "把它改成别的值等于声称这份数据是事实来源。")
    tool_rel = d.get("tool")
    if tool_rel != "tools/build_param_registry.py":
        rep.err("E_SCHEMA_HEADER", cf.rel, "/tool",
                "生成器路径与 §5.16 登记的不一致。",
                "tools/build_param_registry.py", repr(tool_rel),
                "登记表必须指名生成它的工具，否则 V-PR-02 无从重跑。")

    # ---- V-PR-02：与源文件一致（重跑生成器，逐字节比对）----
    root = index.get("root") or ""
    builder = os.path.join(root, "tools", "build_param_registry.py")
    if not os.path.isfile(builder):
        rep.err("E_PARAM_REGISTRY_STALE", cf.rel, "",
                "找不到生成器，无法执行 V-PR-02 的一致性比对。",
                "tools/build_param_registry.py 存在", "不存在",
                "生成产物没有可复现的来源，就退化成一份无人负责的手写数据。")
    else:
        tmpdir = tempfile.mkdtemp(prefix="jw_pr_")
        try:
            # 生成器按「输出文件的绝对路径」把自身产物排除在扫描之外（避免自指重复登记）。
            # 若只是把 --out-json 指到别处，content/parameters/registry.json 就会被当成
            # 普通内容文件扫进去，扫描集合与契约路径下的那次运行不同，比对结果没有意义。
            # 所以把 content/ 整棵复制到影子目录，让输出落在影子树的同一相对位置上——
            # 这样扫描集合逐文件相同，输出才可以**逐字节**比对（§5.16 V-PR-02）。
            shadow = os.path.join(tmpdir, "content")
            shutil.copytree(os.path.join(root, "content"), shadow)
            out_json = os.path.join(shadow, "parameters", "registry.json")
            out_md = os.path.join(tmpdir, "registry.md")
            env = dict(os.environ)
            env["PYTHONIOENCODING"] = "utf-8"
            proc = subprocess.run(
                [sys.executable, builder, "--project", root, "--quiet",
                 "--content", shadow, "--out-json", out_json, "--out-md", out_md,
                 "--contract", os.path.join(root, "docs", "11_data_contract.md")],
                capture_output=True, env=env)
            fresh = open(out_json, "rb").read() if os.path.isfile(out_json) else None
            on_disk = open(cf.abspath, "rb").read()
            if fresh is None:
                rep.err("E_PARAM_REGISTRY_STALE", cf.rel, "",
                        "重跑生成器没有产出文件，V-PR-02 无法判定。",
                        "生成器退出后 out-json 存在",
                        "退出码 " + str(proc.returncode) + "；stderr: "
                        + proc.stderr.decode("utf-8", "replace").strip()[:200],
                        "先修好生成器；在它能跑通之前，磁盘上这份登记表没有任何担保。")
            elif fresh != on_disk:
                rep.err("E_PARAM_REGISTRY_STALE", cf.rel, "",
                        "registry.json 与重新生成的输出不一致（源文件改过，登记表没跟上）。",
                        "与 tools/build_param_registry.py 的输出逐字节相等",
                        "磁盘 " + str(len(on_disk)) + " 字节 vs 重新生成 "
                        + str(len(fresh)) + " 字节，首个差异在第 "
                        + str(_first_diff(on_disk, fresh)) + " 字节",
                        "重跑 `python tools/build_param_registry.py`；"
                        "**不要手改这个文件**——手改是在给同一份数据写第二套真理"
                        "（§5.16）。")
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    # ---- V-PR-03：每张卡的出处指向真实存在的文件与位置 ----
    cards = d.get("cards")
    by_rel = index.get("by_rel") or {}
    if isinstance(cards, list):
        for i, card in enumerate(cards):
            if not isinstance(card, dict):
                rep.err("E_SCHEMA_HEADER", cf.rel, f"/cards/{i}",
                        "cards[] 的元素不是对象。", "object", type(card).__name__,
                        "重跑生成器。")
                continue
            of = card.get("_origin_file")
            op = card.get("_origin_pointer")
            if not isinstance(of, str) or of not in by_rel:
                rep.err("E_NOT_FOUND", cf.rel, f"/cards/{i}/_origin_file",
                        "卡片的出处文件在内容包里不存在。",
                        "content/ 下的一个真实文件", repr(of),
                        "重跑生成器；出处解析不了的索引，人工评审时无法回到事实来源"
                        "（§5.16 V-PR-03）。")
                continue
            if not isinstance(op, str) or _resolve_pointer(by_rel[of].data, op) is _PTR_MISS:
                rep.err("E_NOT_FOUND", cf.rel, f"/cards/{i}/_origin_pointer",
                        "卡片的出处指针在源文件里解析不到。",
                        of + " 中一个真实存在的 JSON 指针", repr(op),
                        "重跑生成器；指针漂移意味着索引指向了别的东西"
                        "（§5.16 V-PR-03）。")

    # ---- V-PR-04：加载器不得读它（不在 scenario.includes 里）----
    sc = by_rel.get("scenarios/chengwan/scenario.json")
    inc = sc.data.get("includes") if (sc is not None and isinstance(sc.data, dict)) else None
    if isinstance(inc, dict):
        hits = sorted(k for k, v in inc.items()
                      if isinstance(v, str) and v.replace("\\", "/").endswith("parameters/registry.json"))
        if hits:
            rep.err("E_SCHEMA_HEADER", "scenarios/chengwan/scenario.json",
                    "/includes/" + hits[0],
                    "剧本把生成产物登记进了 includes，等于让加载器去读它。",
                    "includes 不含 parameters/registry.json", ", ".join(hits),
                    "删掉这条引用：登记表不进 content_hash（§6.4），"
                    "把它读进加载器会让「重跑一次生成器」变成存档不兼容（§5.16 V-PR-04）。")


_PTR_MISS = object()


def _first_diff(a: bytes, b: bytes) -> int:
    """两份字节流的首个差异位置（1 基），便于人工定位重新生成后的改动点。"""
    n = min(len(a), len(b))
    for i in range(n):
        if a[i] != b[i]:
            return i + 1
    return n + 1


def _resolve_pointer(data, pointer: str):
    """RFC 6901 指针解析；解析不到返回 _PTR_MISS。"""
    if pointer == "":
        return data
    if not pointer.startswith("/"):
        return _PTR_MISS
    node = data
    for raw in pointer.split("/")[1:]:
        tok = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(node, dict):
            if tok not in node:
                return _PTR_MISS
            node = node[tok]
        elif isinstance(node, list):
            if not re.fullmatch(r"(0|[1-9][0-9]*)", tok) or int(tok) >= len(node):
                return _PTR_MISS
            node = node[int(tok)]
        else:
            return _PTR_MISS
    return node


# --------------------------------------------------------------------------
# 18 主流程
# --------------------------------------------------------------------------

DISPATCH = {
    "scenario": "check_scenario",
    "io_table": "check_io_table",
    "regions": "check_regions",
    "population_init": "check_population",
    "cells_init": "check_cells",
    "pubserv_init": "check_pubserv",
    "government_init": "check_government",
    "politics_init": "check_politics",
    "assertions": "check_assertions",
    "policy_definition": "check_policy",
    "event_template": "check_event",
    "shock_definition": "check_shock",
    "parameter_set": "check_parameter_set",
    "parameter_registry": "check_parameter_registry",
}

# 加载顺序：被依赖者在前（io_table 供 V-CELL-03，regions/population 供交叉对账）
KIND_ORDER = ["scenario", "io_table", "regions", "population_init", "cells_init",
              "pubserv_init", "government_init", "politics_init", "assertions",
              "parameter_set", "policy_definition", "event_template", "shock_definition",
              "parameter_registry"]


def main(argv: list) -> int:
    ap = argparse.ArgumentParser(description="经纬内容层校验器（G0 验收闸门）")
    ap.add_argument("--root", default=None, help="项目根目录（默认取本文件的上一级）")
    ap.add_argument("--json", default=None, help="把全部发现写成 JSON")
    ap.add_argument("--quiet", action="store_true", help="只打印 ERROR 与汇总")
    args = ap.parse_args(argv)

    # Windows 控制台默认 GBK，报告里有 −、μ、§ 等字符；不改编码会在打印时崩溃。
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    root = args.root or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    content_dir = os.path.join(root, "content")
    docs_dir = os.path.join(root, "docs")
    rep = Report()

    if not os.path.isdir(content_dir):
        print("FATAL: 找不到 content 目录: " + content_dir)
        return 2

    index: dict = {}
    index["root"] = root          # V-PR-02 需要重跑 tools/build_param_registry.py
    var_ids, test_ids = load_doc_ids(docs_dir, rep)
    index["var_ids"] = var_ids
    index["test_ids"] = test_ids
    index["mech_ids"] = load_mech_ids(docs_dir)
    index["param_min_set"] = load_param_min_set(docs_dir)

    if not os.path.isfile(os.path.join(root, "tests", "tools", "test_registry.gd")):
        rep.info("V-PD-06", "tests/tools/test_registry.gd", "",
                 "测试注册表尚未落成代码，改用 docs/30_quality_gates.md + 31_adversarial_tests.md "
                 "的测试矩阵做注册表（共 " + str(len(test_ids)) + " 个 ID）。",
                 "tests/tools/test_registry.gd", "不存在",
                 "G0 末必须建它；T-U-Z-02 要求矩阵与注册表互为子集。")
    if not index["mech_ids"]:
        rep.err("E_MECH_UNKNOWN", "docs/", "",
                "MechanismRegistry 在任何文档或代码中都不存在，V-PD-08 无法执行。",
                "一张 mech.* → SimCore 函数的注册表", "无",
                "先建注册表；否则「政策只能引用已有机制」这条防伪深度的规则形同虚设。")

    files = load_files(content_dir, rep)
    index["by_rel"] = dict((f.rel, f) for f in files)

    unknown_map: dict = {}
    for cf in files:
        if cf.ok:
            unknown_map[cf.rel] = check_schema_shell(cf, rep)
    check_layout(files, rep, index)
    for cf in files:
        if not cf.ok:
            continue
        if cf.schema_kind not in SCHEMAS:
            # schema_kind 不在契约类型集合内 → 已由 check_schema_shell 报过一次。
            # 这里只做方言层（浮点 / null / 重复键），不再逐字段深挖：
            # 对一个契约里根本不存在的类型做语义校验，只会产生一堆无人能修的派生错误。
            rep.err("E_SCHEMA_HEADER", cf.rel, "/",
                    "该文件的 schema_kind 不在契约类型集合内，其全部内容未参与语义校验。",
                    "11 号文件 §5 定义的类型之一",
                    (cf.schema_kind or "缺失") + "（文件大小 " + str(len(cf.text)) + " 字节）",
                    "先决定它属于哪个契约类型（或修订契约新增该类型并给出 V-* 校验表），"
                    "在此之前这份数据既进不了载入器，也没有任何检查能保证它是对的。")
            check_tree_dialect(cf, rep, [""])   # "" 前缀 = 整棵树都算未知字段区
            continue
        check_tree_dialect(cf, rep, unknown_map.get(cf.rel, []))

    collect_global_ids(files, rep, index)

    g = globals()
    for kind in KIND_ORDER:
        fn = g.get(DISPATCH[kind])
        for cf in files:
            if cf.ok and cf.schema_kind == kind and fn is not None:
                try:
                    fn(cf, rep, index)
                except Exception as exc:                       # 校验器自身崩溃必须显式报出
                    rep.err("E_VALIDATOR_FAULT", cf.rel, "",
                            "校验器在处理该文件时抛出异常：" + repr(exc),
                            "校验器不崩溃", type(exc).__name__,
                            "这是校验器缺陷，不是内容缺陷；请修校验器后重跑。")

    scan_embedded_param_cards(files, rep, index)
    check_cross_refs(rep, index)

    # ---- 输出 ----
    order = sorted(rep.findings,
                   key=lambda f: (SEVERITY_ORDER[f.severity], f.file, f.code, f.pointer))
    shown = [f for f in order if not (args.quiet and f.severity != "ERROR")]
    for f in shown:
        print(f.render())
        print()

    n_err = rep.count("ERROR")
    n_warn = rep.count("WARN")
    n_info = rep.count("INFO")

    by_file: dict = {}
    for f in rep.findings:
        if f.severity == "ERROR":
            by_file.setdefault(f.file, []).append(f)
    by_code: dict = {}
    for f in rep.findings:
        if f.severity == "ERROR":
            by_code[f.code] = by_code.get(f.code, 0) + 1

    print("=" * 78)
    print("经纬内容层校验汇总")
    print("=" * 78)
    print("扫描文件      : " + str(len(files)) + " 个 JSON（解析成功 "
          + str(sum(1 for f in files if f.ok)) + " 个）")
    print("ERROR / WARN / INFO : " + str(n_err) + " / " + str(n_warn) + " / " + str(n_info))
    if by_code:
        print()
        print("按错误码：")
        for code, n in sorted(by_code.items(), key=lambda kv: (-kv[1], kv[0])):
            print("  " + code.ljust(28) + str(n))
    if by_file:
        print()
        print("按文件（ERROR 数）：")
        for fn, lst in sorted(by_file.items(), key=lambda kv: (-len(kv[1]), kv[0])):
            print("  " + str(len(lst)).rjust(4) + "  " + fn)
    print()
    if n_err:
        print("结论：内容包未通过 G0 内容层闸门。共 " + str(n_err) + " 条 ERROR，必须清零后才能进 G1。")
    else:
        print("结论：内容层全部 ERROR 清零。")

    if args.json:
        with open(args.json, "w", encoding="utf-8", newline="\n") as fh:
            json.dump({
                "summary": {"files": len(files), "error": n_err, "warn": n_warn, "info": n_info},
                "by_code": by_code,
                "findings": [f.__dict__ for f in order],
            }, fh, ensure_ascii=False, indent=1)
            fh.write("\n")

    return 1 if n_err else 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception:
        import traceback
        traceback.print_exc()
        print("FATAL: 校验器自身崩溃。这不是内容通过的证据。")
        sys.exit(2)
