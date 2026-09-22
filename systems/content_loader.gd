## 加载并校验 `content/*.json`，**缺字段即拒绝启动**；构建初始账本（开账分录）；
## 计算 `content_hash`；把 ID 解析成下标后冻结 `JWIds`。
##
## 骨架依据：docs/17_api_skeleton.md §4.31（秩 A1；可引用秩 ≤10 与 A0）。
##
## 三条贯穿本文件的纪律：
## 1. **全部收集完再报**：任何一条校验失败都登记进 `errors` 并继续往下走，最后返回第一条。
##    这样一次运行就能看到内容包的全部问题，而不是修一条跑一次。
## 2. **不静默改账**：读不进去的值（某个块的 `set_state_*` 没写成功）一律登记错误，
##    绝不假装写成功 —— 与 `JWSimState.from_dict` 的「写完读回来比一次」同一条纪律。
## 3. **不发明契约**：契约没写死的东西（如开局 `level_principal` 批次已摊还几期）
##    只用「能被内容自身交叉验证」的方式重建，重建结果与内容登记值不符即报错。
class_name JWContentLoader
extends RefCounted


## 逐条校验失败记录（**全部收集完再报，不在第一条就退出**）。
var errors: Array[JWResult] = []

## 各内容文件按相对路径升序、逐文件先规范化再拼接的 sha256。
var content_hash: String = ""

## 单独列出，便于定位是剧本改了还是政策改了。
var scenario_hash: String = ""

## 参数包版本。
var param_set_version: int = 0

# ── 私有成员（骨架的成员表只规定上面四项；以下全部是实现细节，加 `_` 前缀） ──

## 与 `errors` 等长的「精确位置」：`<相对路径>#<JSON 指针>`。
var _where: PackedStringArray = PackedStringArray()

## 内容根目录（`load_all` 的入参，形如 `res://content`）。
var _root: String = ""

## 已收录的内容文件相对路径，升序；不含生成产物 `parameters/registry.json`。
var _paths: PackedStringArray = PackedStringArray()

## 与 `_paths` 等长的已解析文档。
var _docs: Array[Dictionary] = []

## 与 `_paths` 等长的 `schema_kind`。
var _kinds: PackedStringArray = PackedStringArray()

## ID ↔ 下标映射表，`load_all` 末尾冻结。
var _ids: JWIds = null

## R-ACCESS-01 的载入期派生常量 `content.pop.base_service_access_ppm[3]`。
## 三个种类的人口加权可及率；SimCore 里目前没有块持有它（已登记接口变更请求）。
var _base_service_access_ppm: PackedInt64Array = PackedInt64Array()

## 反算出的开局失业率（ppm），供 `assert.unemployment` 复核。
var _unemployment_ppm: int = 0

## 逐批次复算出的基年四季票息合计（μU），供 V-FIN-05 与 `assert.interest_in_spend` 复核。
var _bond_coupon_year_uu: int = 0

## 剧本登记的全经济现金总量（μU），开账后用于 INV-018。
var _total_cash_uu: int = 0

# ── 内容包布局（docs/11 §2；新增文件必须先改 §2） ───────────────────────────

## 默认剧本名（R-SCENARIO-01）：`load_all` 的根路径不带 `#剧本名` 后缀时用它。
const DEFAULT_SCENARIO: String = "chengwan"

## 剧本目录的父目录。每个剧本占一个子目录 `scenarios/<name>/`，文件集合相同（§2）。
const SCENARIOS_ROOT: String = "scenarios"

## 本次载入的剧本目录（`scenarios/<name>`）。R-SCENARIO-01 之前是常量。
var _scenario_dir: String = SCENARIOS_ROOT + "/" + DEFAULT_SCENARIO

## 调用方传入的原始根路径（可能带 `#剧本名`），`root_path()` 原样返回，重放与复制据此重载同一剧本。
var _root_spec: String = ""

## 剧本模式（R-SCENARIO-01）：单届（旧 40 季现代版）与战役（四百年）。
const MODE_NAMES: PackedStringArray = ["term", "campaign"]

## 剧本目录下必须齐全的九份文件（§2）。顺序即加载顺序的依据。
const SCENARIO_FILES: PackedStringArray = [
	"scenario.json", "io_table.json", "regions.json", "population_init.json",
	"cells_init.json", "pubserv_init.json", "government_init.json",
	"politics_init.json", "assertions.json",
]

## 与 SCENARIO_FILES 等长的 `schema_kind`。
const SCENARIO_KINDS: PackedStringArray = [
	"scenario", "io_table", "regions", "population_init",
	"cells_init", "pubserv_init", "government_init",
	"politics_init", "assertions",
]

## 手写参数卡集合（§5.15，事实来源）。
const PARAMS_CORE: String = "parameters/params_core.json"

## 生成产物：不进加载器、不进 content_hash（§5.16 V-PR-04）。
const PARAMS_REGISTRY: String = "parameters/registry.json"

## 可选文件（存在即按其 schema_kind 校验，不存在不算缺）。
const OPTIONAL_FILES: PackedStringArray = ["id_aliases.json", "tombstones.json"]

## 允许的 `schema_kind` 闭集合（§5 表 + R-SCHEMA-01）。
const SCHEMA_KINDS: PackedStringArray = [
	"scenario", "io_table", "regions", "population_init", "cells_init", "pubserv_init",
	"government_init", "politics_init", "assertions", "policy_definition", "event_template",
	"shock_definition", "parameter_set", "parameter_registry",
	# R-RESEARCH-01（M2）：科技卡。
	"technology",
]

## 科技目录与文件前缀（R-RESEARCH-01）。目录可以不存在（旧剧本没有科技）。
const TECH_DIR: String = "technologies"
const TECH_PREFIX: String = "tech_"

# ── 枚举名 → 稠密下标（docs/10 §0.5 的枚举表，顺序不得改） ──────────────────

## 参考剧本的地区名（4 区，chengwan 的顺序）。R-SCENARIO-02 之后地区名取自本剧本 regions.json 的顺序，
## 这里只作缺省值。
const REGION_NAMES_DEFAULT: PackedStringArray = ["beiyuan", "zhongzhou", "haijia", "xiling"]
## 本次载入剧本的地区名（regions.json 的 region_id 去掉 `region.` 前缀，按文件顺序）。
var _region_names: PackedStringArray = REGION_NAMES_DEFAULT
## 计划书 §05 的锁定值只约束参考剧本 chengwan；其他剧本以自己的 assertions.json 为准（R-SCENARIO-02）。
var _plan_locks: bool = true
## 本次载入的科技卡文件（升序）。R-RESEARCH-01。
var _tech_files: PackedStringArray = PackedStringArray()
## 科技 ID → 下标（载入期解析前置与解锁引用用）。
var _tech_index: Dictionary = {}
const SECTOR_NAMES: PackedStringArray = ["agri", "manu", "energy", "services"]
const AGE_NAMES: PackedStringArray = ["minor", "working", "elder"]
const SKILL_NAMES: PackedStringArray = ["low", "mid", "high"]
const SERVICE_KIND_NAMES: PackedStringArray = ["health", "education", "utility"]
const BLOC_NAMES: PackedStringArray = ["agri_coop", "business", "labor_public"]

## 改革域位序，逐字取自 `sim/politics/interest_groups.gd` 的 `veto_domain_mask` 注释。
const REFORM_DOMAINS: PackedStringArray = [
	"tax_law", "social_program", "capital_project", "land_reform", "public_employment",
]

## 八档支出优先级（docs/11 §5.9；顺序 == JWUnits.PayLine）。
const PAY_LINE_NAMES: PackedStringArray = [
	"debt_service", "public_wages", "statutory_transfers", "service_opex",
	"project_contracts", "procurement", "subsidies", "discretionary",
]

## 政策 kind（§5.12；顺序 == JWPolicyDef.POLICY_KIND_*）。
const POLICY_KIND_NAMES: PackedStringArray = [
	"rate", "transfer", "subsidy", "project", "capacity", "admin",
]

## 项目支出三条线（顺序 == JWProjectQueue.LINE_*）。
const SPEND_LINE_NAMES: PackedStringArray = [
	"import_equipment", "domestic_material", "construction_service",
]

## 事件比较算子闭集合（V-EV-03）。
const EVENT_OPS: PackedStringArray = ["lt", "le", "eq", "ne", "ge", "gt"]

## 事件可写白名单（§5.13，唯一）。
const EVENT_TARGETS: PackedStringArray = [
	"state.group.expectation_ppm", "state.group.trust_ppm", "state.group.support_ppm",
	"state.bloc.org_power_ppm", "state.bloc.stance_ppm", "state.politics.admin_capacity_ppm",
]

## 冲击通道（V-SH-01，三者各一）。
const SHOCK_CHANNELS: PackedStringArray = ["export_demand", "import_price", "external_credit"]

const ONSET_PROFILES: PackedStringArray = ["step", "ramp_2q"]
const DECAY_PROFILES: PackedStringArray = ["none", "linear"]

## 冲击日志必备字段（V-SH-05）。
const SHOCK_LOG_REQUIRED: PackedStringArray = ["draw_index", "raw_u64", "mapped_value"]

const AMORT_NAMES: PackedStringArray = ["bullet", "level_principal"]
const HOLDER_NAMES: PackedStringArray = ["invpool", "row"]

## 事件 metric 允许的命名空间（V-EV-02 的可判定部分，见 `_validate_event` 的说明）。
const METRIC_PREFIXES: PackedStringArray = ["state.", "flow.", "derived.", "content.", "scenario."]

## 政策 `effect.kind` 的闭集合。**本表是加载器的临时归属**：
## 契约给了 `content.policy.effect_kind[]` 这个字段却没给取值表，
## 而 `JWPolicyDef` 已经为 `effect_target` / `mechanism_ids` 各备了一张白名单常量。
## 本表按同一形态列出内容包实际使用的全部取值；已登记接口变更请求，
## 请求把它移进 `JWPolicyDef.EFFECT_KINDS`（下标即码，重排即破坏性变更）。
const EFFECT_KINDS: PackedStringArray = [
	"capacity_delta", "housing_delta", "facility_index_delta", "cohort_enrollment",
	"policy_param_set", "rate_set", "subsidy_rate", "tax_schedule",
	"tax_capacity_delta", "admin_capacity_delta",
]

## `effect` 里承载量纲的键名（按 `effect.kind` 解释；缺省即 0）。
const EFFECT_MAGNITUDE_KEYS: PackedStringArray = [
	"capacity_delta_uqs_per_q", "housing_delta_units", "index_delta_ppm", "delta_ppm_full",
]

## JSON 互操作安全区（§3：整数绝对值 ≤ 2^53）。
const JSON_INT_ABS_MAX: int = 1 << 53

## 剧本硬约束的锁定值（计划书 §05 + R-SCALE-01）。
const LOCK_POPULATION_PERSONS: int = 24_000_000
const LOCK_REGION_POPULATION: PackedInt64Array = [9_000_000, 7_000_000, 5_000_000, 3_000_000]
const LOCK_GOV_CASH_UU: int = 2_000_000_000
const LOCK_DEBT_TOTAL_UU: int = 50_000_000_000
const LOCK_ANNUAL_RECEIPTS_UU: int = 20_000_000_000
const LOCK_ANNUAL_EXPENDITURE_UU: int = 22_000_000_000
const LOCK_ANNUAL_DEFICIT_UU: int = 2_000_000_000
const LOCK_UNEMPLOYMENT_PPM: int = 80_000
## 唯一允许的非零容差（§5.11）。
const UNEMPLOYMENT_TOLERANCE_PPM: int = 500

## 票息上界（V-FIN-07）。
const COUPON_PPM_MAX: int = 100_000

## 债券分期表的期数上界（== JWBondBook.HORIZON_MAX，写成常量以免跨块取私有常量）。
const BOND_HORIZON_MAX: int = 64

# ── 错误登记 ───────────────────────────────────────────────────────────────

## 登记一条校验失败并返回它。**不中断流程**：调用方继续往下校验。
## 步骤：LOAD
## 前置：code != 0
## 后置：errors 与 _where 各加一条
## 不变量：docs/17 §4.31「全部收集完再报」
## 失败：本身不失败
func _fail(code: int, where: String, a: int = 0, b: int = 0) -> JWResult:
	var r: JWResult = JWResult.make_err(code, a, b, errors.size())
	errors.append(r)
	_where.append(where)
	return r


## 第 i 条错误的精确位置（`<相对路径>#<JSON 指针>`）。
## 步骤：LOAD 后的诊断
## 前置：0 <= i < errors.size()
## 后置：不改状态
## 不变量：docs/11 §7「报出精确位置」
## 失败：越界返回空串
func error_where(i: int) -> String:
	if i < 0 or i >= _where.size():
		return ""
	return _where[i]


## ID 映射表（`load_all` 之后可用；已冻结，只能反查）。
## 步骤：LOAD 后（JWCommands.load_jsonl 需要它）
## 前置：load_all 已跑过
## 后置：不改状态
## 不变量：docs/10 §0.6
## 失败：无
func ids() -> JWIds:
	return _ids


## 上一次 `load_all` 用的内容根目录（骨架之外新增的只读口，签名只增不改）。
##
## 为什么必须有：JWReplay 的权威重放要「从 q=0 重新装配一份独立的 JWSimState」，
## 而它只拿得到一个已经载入过的 JWContentLoader。没有根路径，重放就只能把内容根写死成常量，
## 那等于让重放与主线读两份**可能不同**的内容包 —— INV-133 的前提当场失效。
## 步骤：LOAD 后
## 前置：load_all 已跑过（未跑过时为空串）
## 后置：不改状态
## 不变量：INV-134（内容包身份由 content_hash 把关，本函数只给出它的来源路径）
## 失败：无
func root_path() -> String:
	return _root_spec


## R-ACCESS-01 登记的 `content.pop.base_service_access_ppm[3]`（载入期算一次，之后只读）。
## 步骤：LOAD 后
## 前置：population_init 已校验
## 后置：不改状态
## 不变量：INV-149（服务指数按它归一化，基年恒为 1 000 000）
## 失败：无
func base_service_access_ppm() -> PackedInt64Array:
	return _base_service_access_ppm


## 返回第一条错误；没有错误则返回成功。
func _first_error() -> JWResult:
	if errors.is_empty():
		return JWResult.make_ok()
	return errors[0]

# ── 方言限制（docs/11 §3） ─────────────────────────────────────────────────

## 方言限制：比标准 JSON 更严（docs/11 §3）。
## 步骤：LOAD
## 前置：已解析成 Variant
## 后置：不改状态
## 不变量：INV-001（内容包里出现浮点即 E_FLOAT_IN_CONTENT）
## 失败：Load.FLOAT_IN_CONTENT / NULL_NOT_ALLOWED / UNKNOWN_FIELD / KEY_NAMING / INT_RANGE
##
## 本函数管「与 schema 无关」的四条：浮点、null、整数范围、键名。
## 第五条 `additionalProperties: false`（UNKNOWN_FIELD）需要知道节点属于哪张 schema，
## 而本函数的签名只有 `node` 与 `path`，因此未知键由 `_check_keys()` 在各 `_validate_*` 内判定
## —— 同一个错误码，两个判定点，分工写在这里以免下一个人以为漏了。
func check_dialect(node: Variant, path: String) -> JWResult:
	var before: int = errors.size()
	_dialect_walk(node, path, false)
	if errors.size() == before:
		return JWResult.make_ok()
	return errors[before]


## 递归实现。键名规则见 `_key_is_legal`。
##
## `in_note` 为真表示当前位于某个 `_note_*` 子树内：§5.15.1 规定注释键是自由文本或自由对象、
## **schema 不校验其内部形状**，所以那里面不判键名（那是「形状」），
## 但仍然判浮点、null 与整数范围（那是内容包的绝对纪律，与形状无关）。
func _dialect_walk(node: Variant, path: String, in_note: bool) -> void:
	var t: int = typeof(node)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = node
		for k: Variant in d.keys():
			if typeof(k) != TYPE_STRING and typeof(k) != TYPE_STRING_NAME:
				_fail(JWResult.Load.KEY_NAMING, path, typeof(k), 0)
				continue
			var ks: String = String(k)
			var child: String = path + "/" + ks
			var child_note: bool = in_note or ks.begins_with("_note_")
			if not in_note and not _key_is_legal(ks):
				_fail(JWResult.Load.KEY_NAMING, child, ks.length(), 0)
			_dialect_walk(d[k], child, child_note)
		return
	if t == TYPE_ARRAY:
		var a: Array = node
		for i: int in a.size():
			_dialect_walk(a[i], path + "/" + str(i), in_note)
		return
	if t == TYPE_NIL:
		_fail(JWResult.Load.NULL_NOT_ALLOWED, path, 0, 0)
		return
	if t == TYPE_INT or t == TYPE_FLOAT:
		# Godot 4.7 的 JSON 解析器**把每一个数都读成 double**（实测：`{"a":1}` 的 a 是 float）。
		# 因此「是不是浮点」不能靠 typeof 判：
		# ① 字面量层面的浮点（`1.5` / `1e3` / `.5` / `-0`）由 `_scan_number_literals` 在原文上判，
		#    那是唯一能分辨 `1` 与 `1.0` 的地方；
		# ② 值层面在这里判：有小数部分即 FLOAT_IN_CONTENT，超过 2^53 即 INT_RANGE
		#    （§3 的整数上界正是为了让 double 无损承载整数而设的）。
		if not _num_is_integral(node):
			_fail(JWResult.Load.FLOAT_IN_CONTENT, path, 0, 0)
			return
		if not _num_in_json_range(node):
			_fail(JWResult.Load.INT_RANGE, path, 0, JSON_INT_ABS_MAX)
		return
	if t == TYPE_BOOL or t == TYPE_STRING or t == TYPE_STRING_NAME:
		return
	# JSON 解析器只可能产出上面这些类型；出现别的说明调用方塞了非 JSON 数据进来。
	_fail(JWResult.Load.SCHEMA_HEADER, path, t, 0)


## 一个 JSON 数值是否代表整数（无小数部分）。
## Godot 的解析器把整数也读成 double，所以「整数性」只能在值上判，不能在类型上判。
func _num_is_integral(v: Variant) -> bool:
	var t: int = typeof(v)
	if t == TYPE_INT:
		return true
	if t != TYPE_FLOAT:
		return false
	var f: float = v
	return f == floor(f)


## 是否落在 JSON 互操作安全区（|v| ≤ 2^53，§3）。超出即 double 已经无法逐位承载。
func _num_in_json_range(v: Variant) -> bool:
	var limit: float = JSON_INT_ABS_MAX
	var t: int = typeof(v)
	if t == TYPE_INT:
		return JWMath.absi(int(v)) <= JSON_INT_ABS_MAX
	if t != TYPE_FLOAT:
		return false
	var f: float = v
	return f <= limit and f >= -limit


## 一个 Variant 是否是可以当整数用的 JSON 数值。
func _is_num(v: Variant) -> bool:
	return _num_is_integral(v) and _num_in_json_range(v)


## 取整数值。调用前必须先用 `_is_num` 判过。
func _num(v: Variant) -> int:
	return int(v)


## 原文层面的浮点字面量扫描（§3 的四种写法：`1.5` / `1e3` / `.5` / `-0`）。
##
## 值层面判不出 `1e3`（它等于整数 1000）与 `-0`（它等于 0），而这两种写法同样是
## 「内容包里出现浮点」。唯一能分辨的地方是原文，所以这里逐字符扫一遍数值 token。
## 字符串内部整段跳过（键名里的 `-` 与小数点不是数值）。
func _scan_number_literals(text: String, rel: String) -> void:
	var n: int = text.length()
	var i: int = 0
	var in_string: bool = false
	var escaped: bool = false
	while i < n:
		var c: int = text.unicode_at(i)
		if in_string:
			if escaped:
				escaped = false
			elif c == 92:
				escaped = true
			elif c == 34:
				in_string = false
			i += 1
			continue
		if c == 34:
			in_string = true
			i += 1
			continue
		var is_digit: bool = c >= 48 and c <= 57
		if not is_digit and c != 45 and c != 46:
			i += 1
			continue
		var j: int = i
		var has_dot: bool = false
		var has_exp: bool = false
		while j < n:
			var d: int = text.unicode_at(j)
			if d >= 48 and d <= 57 or d == 45 or d == 43:
				j += 1
				continue
			if d == 46:
				has_dot = true
				j += 1
				continue
			if d == 101 or d == 69:
				has_exp = true
				j += 1
				continue
			break
		var token: String = text.substr(i, j - i)
		if has_dot or has_exp or token == "-0":
			_fail(JWResult.Load.FLOAT_IN_CONTENT, rel + "#literal:" + token, 0, 0)
		i = j


## 键名合法性：英文 snake_case，或 docs/11 §4 的 ID 形态（段间 `.`，第二段起允许大写），
## 或注释键（`_` 开头的 snake_case，§5.15.1 明文允许且 schema 不校验其内部形状），
## 或投入产出表的默认键 `*`（§5.5 的覆盖语法）。
func _key_is_legal(k: String) -> bool:
	if k == "*":
		return true
	var body: String = k
	if body.begins_with("_"):
		body = body.substr(1)
	if body.is_empty():
		return false
	var segs: PackedStringArray = body.split(".")
	for i: int in segs.size():
		var s: String = segs[i]
		if s.is_empty():
			return false
		for j: int in s.length():
			var c: int = s.unicode_at(j)
			var is_lower: bool = c >= 97 and c <= 122
			var is_upper: bool = c >= 65 and c <= 90
			var is_digit: bool = c >= 48 and c <= 57
			var is_us: bool = c == 95
			if is_lower or is_digit or is_us:
				continue
			# 第二段起才允许大写（容纳 P04 / E11 / S02 的编号段）。
			if is_upper and i > 0:
				continue
			return false
		# 首段首字符必须是小写字母。
		if i == 0:
			var c0: int = s.unicode_at(0)
			if c0 < 97 or c0 > 122:
				return false
	return true


## `additionalProperties: false` 的落点：obj 的每个键都必须在 allowed 内。
## `_` 开头的注释键永远允许（§5.15.1）。
func _check_keys(obj: Dictionary, allowed: PackedStringArray, where: String) -> void:
	for k: Variant in obj.keys():
		var ks: String = String(k)
		if ks.begins_with("_"):
			continue
		if not allowed.has(ks):
			_fail(JWResult.Load.UNKNOWN_FIELD, where + "/" + ks, 0, 0)


## 必填键存在性检查；返回是否齐全。
func _require(obj: Dictionary, keys: PackedStringArray, where: String, code: int) -> bool:
	var ok: bool = true
	for i: int in keys.size():
		if not obj.has(keys[i]):
			_fail(code, where + "/" + keys[i], 0, 0)
			ok = false
	return ok

# ── 取值助手（类型不对即登记错误并返回缺省，绝不猜） ────────────────────────

func _get_int(obj: Dictionary, key: String, where: String, code: int) -> int:
	if not obj.has(key):
		_fail(code, where + "/" + key, 0, 0)
		return 0
	var v: Variant = obj[key]
	if not _is_num(v):
		_fail(JWResult.Load.SCHEMA_HEADER, where + "/" + key, typeof(v), TYPE_INT)
		return 0
	return _num(v)


func _get_str(obj: Dictionary, key: String, where: String, code: int) -> String:
	if not obj.has(key):
		_fail(code, where + "/" + key, 0, 0)
		return ""
	var v: Variant = obj[key]
	if typeof(v) != TYPE_STRING and typeof(v) != TYPE_STRING_NAME:
		_fail(JWResult.Load.SCHEMA_HEADER, where + "/" + key, typeof(v), TYPE_STRING)
		return ""
	return String(v)


func _get_dict(obj: Dictionary, key: String, where: String, code: int) -> Dictionary:
	if not obj.has(key):
		_fail(code, where + "/" + key, 0, 0)
		return {}
	var v: Variant = obj[key]
	if typeof(v) != TYPE_DICTIONARY:
		_fail(JWResult.Load.SCHEMA_HEADER, where + "/" + key, typeof(v), TYPE_DICTIONARY)
		return {}
	return v


func _get_array(obj: Dictionary, key: String, where: String, code: int) -> Array:
	if not obj.has(key):
		_fail(code, where + "/" + key, 0, 0)
		return []
	var v: Variant = obj[key]
	if typeof(v) != TYPE_ARRAY:
		_fail(JWResult.Load.SCHEMA_HEADER, where + "/" + key, typeof(v), TYPE_ARRAY)
		return []
	return v


## 定长整数数组；长度不符即登记并补零（后续检查不会因越界而报无关的错）。
func _get_int_array(obj: Dictionary, key: String, n: int, where: String, code: int) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(n)
	out.fill(0)
	var a: Array = _get_array(obj, key, where, code)
	if a.size() != n:
		if obj.has(key):
			_fail(code, where + "/" + key, a.size(), n)
		return out
	for i: int in n:
		if not _is_num(a[i]):
			_fail(JWResult.Load.SCHEMA_HEADER, where + "/" + key + "/" + str(i),
					typeof(a[i]), TYPE_INT)
			continue
		out[i] = _num(a[i])
	return out


## 布尔字段 → 0/1。
func _get_flag(obj: Dictionary, key: String, where: String, code: int) -> int:
	if not obj.has(key):
		_fail(code, where + "/" + key, 0, 0)
		return 0
	var v: Variant = obj[key]
	if typeof(v) == TYPE_BOOL:
		return 1 if bool(v) else 0
	if _is_num(v) and (_num(v) == 0 or _num(v) == 1):
		return _num(v)
	_fail(JWResult.Load.SCHEMA_HEADER, where + "/" + key, typeof(v), TYPE_BOOL)
	return 0


## 名字 → 下标；不在表内返回 −1（调用方转具体错误码）。
func _name_index(names: PackedStringArray, s: String) -> int:
	for i: int in names.size():
		if names[i] == s:
			return i
	return -1


## `region.<name>` → 0..3
func _region_index(id: String) -> int:
	if not id.begins_with("region."):
		return -1
	return _name_index(_region_names, id.substr(7))


## `sector.<name>` → 0..3
func _sector_index(id: String) -> int:
	if not id.begins_with("sector."):
		return -1
	return _name_index(SECTOR_NAMES, id.substr(7))


## `cell.<region>.<sector>` → 0..15
func _cell_index(id: String) -> int:
	var segs: PackedStringArray = id.split(".")
	if segs.size() != 3 or segs[0] != "cell":
		return -1
	var r: int = _name_index(_region_names, segs[1])
	var s: int = _name_index(SECTOR_NAMES, segs[2])
	if r < 0 or s < 0:
		return -1
	return JWIds.idx_cell(r, s)


## `pubserv.<region>` → 0..3
func _pubserv_index(id: String) -> int:
	if not id.begins_with("pubserv."):
		return -1
	return _name_index(_region_names, id.substr(8))


## `group.<region>.<age>.<skill>` → 0..35
func _group_index(id: String) -> int:
	var segs: PackedStringArray = id.split(".")
	if segs.size() != 4 or segs[0] != "group":
		return -1
	var r: int = _name_index(_region_names, segs[1])
	var a: int = _name_index(AGE_NAMES, segs[2])
	var k: int = _name_index(SKILL_NAMES, segs[3])
	if r < 0 or a < 0 or k < 0:
		return -1
	return JWIds.idx_group(r, a, k)


## `bloc.<name>` → 0..2
func _bloc_index(id: String) -> int:
	if not id.begins_with("bloc."):
		return -1
	return _name_index(BLOC_NAMES, id.substr(5))


## `policy.P01`.. → 0..11
func _policy_index(id: String) -> int:
	if not id.begins_with("policy.P"):
		return -1
	var n: int = id.substr(8).to_int()
	if n < 1 or n > JWUnits.POLICY_N:
		return -1
	return n - 1


## `event.E01`.. → 0..11
func _event_index(id: String) -> int:
	if not id.begins_with("event.E"):
		return -1
	var n: int = id.substr(7).to_int()
	if n < 1 or n > JWUnits.EVENT_N:
		return -1
	return n - 1


## `shock.S01`.. → 0..2
func _shock_index(id: String) -> int:
	if not id.begins_with("shock.S"):
		return -1
	var n: int = id.substr(7).to_int()
	if n < 1 or n > JWUnits.SHOCK_N:
		return -1
	return n - 1

# ── 状态块写入（写完读回来比一次，写不进去就登记，绝不假装成功） ────────────

## `verify` 为假表示这个槽位是**只写的内容表**（C 类）：
## 它有 `set_state_array` 通路，但不在该块的 `STATE_ARRAY_IDS` 里，`state_array()` 读不回来
## （例如 JWPopulation 的 `content.demography.*`）。这时跳过读回比对，而不是把「读不回来」
## 误报成「没写进去」。
func _set_arr(block: RefCounted, slot: int, v: PackedInt64Array, where: String,
		verify: bool = true) -> void:
	var rc: int = block.set_state_array(slot, v)
	if rc != JWResult.OK:
		_fail(rc, where, slot, v.size())
		return
	if not verify:
		return
	var got: PackedInt64Array = block.state_array(slot)
	if got != v:
		# 写入通道存在但没有落地（某个块的 set_state_array 还是空实现）。
		# 这不是内容错误，是装配错误；照样拒绝启动，不带着半截状态往下跑。
		_fail(JWResult.Load.SCHEMA_HEADER, where, slot, got.size())


func _set_scalar(block: RefCounted, slot: int, v: int, where: String) -> void:
	var rc: int = block.set_state_scalar(slot, v)
	if rc != JWResult.OK:
		_fail(rc, where, slot, v)
		return
	var got: int = block.state_scalar(slot)
	if got != v:
		_fail(JWResult.Load.SCHEMA_HEADER, where, slot, got)

# ── 文件枚举、格式与解析（docs/11 §7 的前三段） ────────────────────────────

## 把 content/ 下的全部 *.json 枚举成相对路径（升序），含子目录。
func _scan(dir_rel: String, out: PackedStringArray) -> void:
	var abs: String = _root if dir_rel.is_empty() else _root + "/" + dir_rel
	var files: PackedStringArray = DirAccess.get_files_at(abs)
	for i: int in files.size():
		var f: String = files[i]
		if not f.ends_with(".json"):
			continue
		out.append(f if dir_rel.is_empty() else dir_rel + "/" + f)
	var subs: PackedStringArray = DirAccess.get_directories_at(abs)
	for i: int in subs.size():
		_scan(_join(dir_rel, subs[i]), out)


## 拼接相对路径（根目录时不加前导斜杠）。
func _join(a: String, b: String) -> String:
	return b if a.is_empty() else a + "/" + b


## 相对路径是否落在 §2 的固定布局内。
func _in_layout(rel: String) -> bool:
	if OPTIONAL_FILES.has(rel):
		return true
	if rel == PARAMS_CORE or rel == PARAMS_REGISTRY:
		return true
	if rel.begins_with("schemas/") and rel.ends_with(".schema.json"):
		return true
	if rel.begins_with("policies/policy_P") and rel.ends_with(".json"):
		return _policy_index("policy." + rel.substr(16, rel.length() - 21)) >= 0
	if rel.begins_with("events/event_E") and rel.ends_with(".json"):
		return _event_index("event." + rel.substr(13, rel.length() - 18)) >= 0
	if rel.begins_with("shocks/shock_S") and rel.ends_with(".json"):
		return _shock_index("shock." + rel.substr(13, rel.length() - 18)) >= 0
	if rel.begins_with(TECH_DIR + "/" + TECH_PREFIX) and rel.ends_with(".json"):
		return true
	if rel.begins_with(SCENARIOS_ROOT + "/"):
		var parts: PackedStringArray = rel.split("/")
		return parts.size() == 3 and _scenario_name_ok(parts[1]) and SCENARIO_FILES.has(parts[2])
	return false


## 预读本剧本 regions.json 的地区名（R-SCENARIO-02）。读不到或格式不对返回空表，由调用方报错；
## 正式的逐字段校验仍在 `_validate_regions`。
func _peek_region_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var f: FileAccess = FileAccess.open(_root + "/" + _scenario_dir + "/regions.json", FileAccess.READ)
	if f == null:
		return out
	var v: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (v is Dictionary) or not (v as Dictionary).has("regions"):
		return out
	for e: Variant in (v as Dictionary)["regions"]:
		if not (e is Dictionary):
			return PackedStringArray()
		var rid: String = String((e as Dictionary).get("region_id", ""))
		var nm: String = rid.substr(7)
		if not rid.begins_with("region.") or not _scenario_name_ok(nm) or out.has(nm):
			return PackedStringArray()
		out.append(nm)
	return out


## 剧本目录名：小写字母、数字、下划线，1—32 字符（R-SCENARIO-01）。
static func _scenario_name_ok(name: String) -> bool:
	if name.is_empty() or name.length() > 32:
		return false
	for i: int in name.length():
		var c: int = name.unicode_at(i)
		var ok: bool = (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
		if not ok:
			return false
	return true


## 拆分 `load_all` 的根路径参数：`res://content#campaign_1600` → [目录, 剧本名]。
## 不带 `#` 时剧本名取 DEFAULT_SCENARIO。
static func split_root_spec(spec: String) -> PackedStringArray:
	var root: String = spec
	var name: String = DEFAULT_SCENARIO
	var h: int = spec.rfind("#")
	if h >= 0:
		root = spec.substr(0, h)
		name = spec.substr(h + 1)
	return PackedStringArray([root.trim_suffix("/"), name])


## 读一个文件：格式（UTF-8 无 BOM / LF / 末尾单换行） → JSON 解析 → 方言 → 头部。
## 成功返回解析后的 Dictionary 并把它登记进 _paths/_docs/_kinds；失败登记错误并返回 false。
func _read_one(rel: String) -> bool:
	var abs: String = _root + "/" + rel
	if not FileAccess.file_exists(abs):
		# Load 枚举里没有「文件缺失」与「不在布局内」两个码（docs/11 §7 的 E_CONTENT_LAYOUT
		# 与 E_NOT_FOUND 尚未进 sim/jw_result.gd，已登记接口变更请求）。
		# 在补上之前一律用同组的 FILE_FORMAT，位置串里写明是缺文件还是越布局。
		_fail(JWResult.Load.FILE_FORMAT, rel + "#missing-file", 0, 0)
		return false
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(abs)
	if raw.is_empty():
		_fail(JWResult.Load.FILE_FORMAT, rel + "#empty", 0, 0)
		return false
	if raw.size() >= 3 and raw[0] == 0xEF and raw[1] == 0xBB and raw[2] == 0xBF:
		_fail(JWResult.Load.FILE_FORMAT, rel + "#bom", 0, 0)
	if raw.has(0x0D):
		_fail(JWResult.Load.FILE_FORMAT, rel + "#crlf", 0, 0)
	if raw[raw.size() - 1] != 0x0A:
		_fail(JWResult.Load.FILE_FORMAT, rel + "#no-final-lf", 0, 0)
	elif raw.size() >= 2 and raw[raw.size() - 2] == 0x0A:
		_fail(JWResult.Load.FILE_FORMAT, rel + "#extra-final-lf", 0, 0)

	var text: String = raw.get_string_from_utf8()
	_scan_number_literals(text, rel)
	var parser: JSON = JSON.new()
	var perr: int = parser.parse(text)
	if perr != OK:
		_fail(JWResult.Load.FILE_FORMAT, rel + "#line" + str(parser.get_error_line()), perr, 0)
		return false
	var data: Variant = parser.data
	if typeof(data) != TYPE_DICTIONARY:
		_fail(JWResult.Load.SCHEMA_HEADER, rel + "#root", typeof(data), TYPE_DICTIONARY)
		return false

	check_dialect(data, rel + "#")
	var doc: Dictionary = data

	# §3 最后一条：顶层必须有 schema_kind（闭集合）与 schema_version（整数 ≥ 1）。
	var kind: String = _get_str(doc, "schema_kind", rel + "#", JWResult.Load.SCHEMA_HEADER)
	if not SCHEMA_KINDS.has(kind):
		_fail(JWResult.Load.SCHEMA_HEADER, rel + "#/schema_kind", kind.length(), 0)
	var ver: int = _get_int(doc, "schema_version", rel + "#", JWResult.Load.SCHEMA_HEADER)
	if ver < 1:
		_fail(JWResult.Load.SCHEMA_HEADER, rel + "#/schema_version", ver, 1)

	_paths.append(rel)
	_docs.append(doc)
	_kinds.append(kind)
	return true


## 按相对路径升序取回某个已读文件的下标；不存在返回 −1。
func _doc_index(rel: String) -> int:
	for i: int in _paths.size():
		if _paths[i] == rel:
			return i
	return -1


## 取某个剧本文件的文档（缺失返回空字典；缺失本身已在 _read_one 登记）。
func _scenario_doc(name: String) -> Dictionary:
	var i: int = _doc_index(_scenario_dir + "/" + name)
	if i < 0:
		return {}
	return _docs[i]

# ── ID 登记（docs/11 §4；下标顺序由 docs/10 §0.5 的枚举表决定） ─────────────

## 把全部固定枚举的稳定 ID 登记进 JWIds。
## 剧本文件里出现的 ID 之后只做「解析得到下标」，不再新增登记 —— 集合是契约定死的，
## 内容包多一个少一个都由各自的 V-*-01 报错，而不是靠登记表默默扩张。
func _register_ids() -> void:
	for r: int in JWUnits.R:
		_reg(JWIds.IdKind.REGION, "region." + _region_names[r], r)
	for s: int in JWUnits.S:
		_reg(JWIds.IdKind.SECTOR, "sector." + SECTOR_NAMES[s], s)
	for r: int in JWUnits.R:
		for s: int in JWUnits.S:
			_reg(JWIds.IdKind.CELL, "cell." + _region_names[r] + "." + SECTOR_NAMES[s],
					JWIds.idx_cell(r, s))
		_reg(JWIds.IdKind.PUBSERV, "pubserv." + _region_names[r], r)
		for a: int in JWUnits.A:
			for k: int in JWUnits.K:
				_reg(JWIds.IdKind.GROUP,
						"group." + _region_names[r] + "." + AGE_NAMES[a] + "." + SKILL_NAMES[k],
						JWIds.idx_group(r, a, k))
	for p: int in JWUnits.POLICY_N:
		_reg(JWIds.IdKind.POLICY, "policy.P" + _pad2(p + 1), p)
	for e: int in JWUnits.EVENT_N:
		_reg(JWIds.IdKind.EVENT, "event.E" + _pad2(e + 1), e)
	for k: int in JWUnits.SHOCK_N:
		_reg(JWIds.IdKind.SHOCK, "shock.S" + _pad2(k + 1), k)
	for b: int in JWUnits.BLOC_N:
		_reg(JWIds.IdKind.BLOC, "bloc." + BLOC_NAMES[b], b)
	for i: int in JWPolicyDef.MECHANISM_IDS.size():
		_reg(JWIds.IdKind.MECHANISM, JWPolicyDef.MECHANISM_IDS[i], i)
	for i: int in PARAM_IDS.size():
		_reg(JWIds.IdKind.PARAM, PARAM_IDS[i], i)
	_register_agent_ids()


## 60 个主体 ID（docs/17 §2.3 的下标布局）。
func _register_agent_ids() -> void:
	_reg(JWIds.IdKind.AGENT, "agent.gov", JWIds.AGENT_GOV)
	for r: int in JWUnits.R:
		for s: int in JWUnits.S:
			_reg(JWIds.IdKind.AGENT,
					"agent.cell." + _region_names[r] + "." + SECTOR_NAMES[s],
					JWIds.agent_of_cell(JWIds.idx_cell(r, s)))
		_reg(JWIds.IdKind.AGENT, "agent.pubserv." + _region_names[r], JWIds.agent_of_pubserv(r))
		for a: int in JWUnits.A:
			for k: int in JWUnits.K:
				_reg(JWIds.IdKind.AGENT,
						"agent.group." + _region_names[r] + "." + AGE_NAMES[a] + "."
								+ SKILL_NAMES[k],
						JWIds.agent_of_group(JWIds.idx_group(r, a, k)))
	_reg(JWIds.IdKind.AGENT, "agent.invpool", JWIds.AGENT_INVPOOL)
	_reg(JWIds.IdKind.AGENT, "agent.row", JWIds.AGENT_ROW)
	_reg(JWIds.IdKind.AGENT, "agent.opening", JWIds.AGENT_OPENING)


func _reg(kind: int, id: String, index: int) -> void:
	var r: JWResult = _ids.register(kind, id, index)
	if not r.ok:
		_fail(r.code, "ids#" + id, kind, index)


func _pad2(v: int) -> String:
	var s: String = str(v)
	if s.length() < 2:
		return "0" + s
	return s

## `param.*` 的稠密下标表：下标 == `JWUnits.Param` 的枚举值，内容是参数卡 ID。
## 数组型参数卡（`engel_weight_ppm[4]`、`support_weight_ppm[3]`）按元素展开成连续槽位，
## 与 `JWUnits.Param` 的 `_0.._3` 命名逐字对应。长度必须 == JWUnits.PARAM_N。
const PARAM_IDS: PackedStringArray = [
	"param.amount_max_uu", "param.bloc_care_gain_ppm", "param.bloc_org_inertia_ppm",
	"param.bloc_resource_ref_uu", "param.bloc_w_resource_ppm", "param.bloc_w_size_ppm",
	"param.bond_batch_cap", "param.commitment_horizon_q", "param.construction_share_cap_ppm",
	"param.coupon_max_ppm", "param.coupon_min_ppm", "param.default_grace_q",
	"param.demand_smooth_ppm", "param.dissave_ppm", "param.edu_pipeline_slots",
	"param.emission_decay_ppm", "param.engel_weight_ppm.0", "param.engel_weight_ppm.1",
	"param.engel_weight_ppm.2", "param.engel_weight_ppm.3", "param.env_exposure_gain_ppm",
	"param.expectation_inertia_ppm", "param.firing_friction_ppm", "param.gap_cap_ppm",
	"param.hiring_friction_ppm", "param.household_bond_appetite_ppm", "param.inventory_target_ppm",
	"param.invest_propensity_ppm", "param.living_weight_house_ppm",
	"param.living_weight_service_ppm", "param.log_capacity_rows",
	"param.maintenance_backlog_gain_ppm", "param.maintenance_backlog_max_ppm",
	"param.maintenance_backlog_recover_ppm", "param.market_rate_base_ppm",
	"param.market_rate_slope_ppm", "param.migration_max_share_ppm",
	"param.migration_threshold_ppm", "param.migration_w_env_ppm", "param.migration_w_house_ppm",
	"param.migration_w_job_ppm", "param.migration_w_service_ppm", "param.migration_w_wage_ppm",
	"param.mpc_ppm", "param.no_confidence_q", "param.opex_recover_ppm",
	"param.opex_starve_decay_ppm", "param.payout_ratio_ppm", "param.persons_per_housing_unit",
	"param.policy_toggle_cost_uu", "param.price_ceil_ppm", "param.price_clamp_budget_count",
	"param.price_cover_gain_ppm", "param.price_floor_ppm", "param.price_gap_gain_ppm",
	"param.price_step_max_ppm", "param.qty_max_uqs", "param.rate_sensitivity_ppm",
	"param.student_teacher_ratio", "param.support_weight_ppm.0", "param.support_weight_ppm.1",
	"param.support_weight_ppm.2", "param.tax_base_rate_ppm", "param.tax_evasion_slope_ppm",
	"param.tax_recovery_ppm", "param.training_lag_q", "param.trust_drop_ppm",
	"param.trust_recover_ppm", "param.trust_streak_cap_q", "param.uu_to_construction_uqs_ppm",
	"param.wage_cash_share_ppm", "param.wage_ceil_uu", "param.wage_floor_uu",
	"param.wage_gain_ppm", "param.wage_step_max_ppm", "param.write_guard_sample_q",
	"param.pubserv_fee_ppm", "param.pension_uu_per_elder_q", "param.rule_issue_tenor_q",
	"param.p09_eligible_sector_mask",
	"param.p11_staff_gain_full_ppm", "param.p11_system_gain_full_ppm",
	"param.p11_tax_capacity_ceiling_ppm",
	"param.p11_region_base_share_ppm.0", "param.p11_region_base_share_ppm.1",
	"param.p11_region_base_share_ppm.2", "param.p11_region_base_share_ppm.3",
	"param.procurement_disclosure_ref_uu", "param.proc_transparency_gain_ppm",
	"param.proc_transparency_load_ppm", "param.proc_transparency_appeal_load_ppm",
	"param.proc_transparency_ramp_q", "param.proc_review_uu_per_opex_ppm",
	"param.proc_transparency_step_max_ppm",
	"param.max_defer_count", "param.max_defer_quarters", "param.defer_fee_ppm_per_q",
	"param.p11_capacity_floor_ppm", "param.p11_capacity_decay_ppm", "param.p11_capacity_recover_ppm",
	"param.proc_transparency_decay_ppm", "param.proc_transparency_decay_q",
]

# ── 开账分录缓冲（各 `_validate_*` 边校验边登记，build_opening_ledger 统一过账） ──

var _op_agent: PackedInt64Array = PackedInt64Array()
var _op_code: PackedInt64Array = PackedInt64Array()
var _op_amount: PackedInt64Array = PackedInt64Array()


## 登记一条开账分录。金额为 0 的科目不登记（INV-015 要求每行 amount != 0）。
func _add_open(agent: int, code: int, amount_uu: int) -> void:
	if amount_uu == 0:
		return
	_op_agent.append(agent)
	_op_code.append(code)
	_op_amount.append(amount_uu)

# ── 加载流水线 ─────────────────────────────────────────────────────────────

## 加载流水线（顺序固定，docs/11 §7）。
## 步骤：LOAD
## 前置：内容目录存在
## 后置：文件格式 → JSON 解析 → 方言限制（无浮点/无 null/无未知键） → schema 校验 →
##       ID 唯一性与正则 → 单文件语义校验 → 跨文件引用解析 → 剧本硬约束与会计对账 →
##       构建初始账本 → 跑一遍 P0 不变量 → 就绪
## 不变量：INV-141..152 全部；INV-023（初值经 q = −1 的开账分录生成）
## 失败：返回第一条错误的 JWResult，`errors` 里是完整清单；**任何一条失败都拒绝启动**
func load_all(root_path: String, st: JWSimState) -> JWResult:
	_reset()
	_root_spec = root_path
	var spec: PackedStringArray = split_root_spec(root_path)
	_root = spec[0]
	if not _scenario_name_ok(spec[1]):
		return _fail(JWResult.Load.FILE_FORMAT, root_path + "#bad-scenario-name", 0, 0)
	_scenario_dir = SCENARIOS_ROOT + "/" + spec[1]
	_plan_locks = spec[1] == DEFAULT_SCENARIO

	# R-SCENARIO-02：地区数与地区名取自本剧本 regions.json，先定维度再分配状态。
	var names: PackedStringArray = _peek_region_names()
	if names.is_empty() or not JWUnits.set_regions(names.size()):
		return _fail(JWResult.Load.REGION_SET, _scenario_dir + "/regions.json#count", names.size(), JWUnits.R_MAX)
	JWIds.apply_dims()
	_region_names = names
	if st.registry_size() == 0 or st.dims_r != JWUnits.R:
		st.allocate_all()
	if st == null:
		return _fail(JWResult.Load.SCHEMA_HEADER, "#state-null", 0, 0)
	_ids = JWIds.new()
	_register_ids()

	# ① 枚举 content/ 下全部 *.json，与 §2 布局比对；剔除生成产物。
	var found: PackedStringArray = PackedStringArray()
	_scan("", found)
	found.sort()
	for i: int in found.size():
		var rel: String = found[i]
		if rel == PARAMS_REGISTRY:
			# §5.16 V-PR-04：加载器不得读取生成产物；它的时效性由 tools/ 负责。
			continue
		if not _in_layout(rel):
			_fail(JWResult.Load.FILE_FORMAT, rel + "#not-in-layout", 0, 0)

	# ② 读取 → 格式 → 解析 → 方言 → 头部。必备文件缺一即错。
	for i: int in SCENARIO_FILES.size():
		_read_one(_scenario_dir + "/" + SCENARIO_FILES[i])
	for p: int in JWUnits.POLICY_N:
		_read_one("policies/policy_P" + _pad2(p + 1) + ".json")
	for e: int in JWUnits.EVENT_N:
		_read_one("events/event_E" + _pad2(e + 1) + ".json")
	for k: int in JWUnits.SHOCK_N:
		_read_one("shocks/shock_S" + _pad2(k + 1) + ".json")
	_read_one(PARAMS_CORE)
	# R-RESEARCH-01：科技卡按文件名升序读入，下标即顺序（前置引用必须指向更靠前的科技，见 _validate_technologies）。
	_tech_files = PackedStringArray()
	for i2: int in found.size():
		if found[i2].begins_with(TECH_DIR + "/" + TECH_PREFIX) and found[i2].ends_with(".json"):
			_tech_files.append(found[i2])
	for i3: int in _tech_files.size():
		_read_one(_tech_files[i3])
	for i: int in OPTIONAL_FILES.size():
		if FileAccess.file_exists(_root + "/" + OPTIONAL_FILES[i]):
			_read_one(OPTIONAL_FILES[i])

	# ③ 文件位置与 schema_kind 必须对得上（放错目录的文件不能靠内容蒙混过关）。
	for i: int in SCENARIO_FILES.size():
		var idx: int = _doc_index(_scenario_dir + "/" + SCENARIO_FILES[i])
		if idx >= 0 and _kinds[idx] != SCENARIO_KINDS[i]:
			_fail(JWResult.Load.SCHEMA_HEADER,
					_paths[idx] + "#/schema_kind", i, 0)
	_expect_kind_of_dir("policies/", "policy_definition")
	_expect_kind_of_dir("events/", "event_template")
	_expect_kind_of_dir("shocks/", "shock_definition")

	# ④ 单文件语义校验，同时把已校验的值写进 JWSimState（顺序有依赖：io → cells）。
	_validate_scenario(st)
	_validate_io(st)
	_validate_regions(st)
	_validate_population(st)
	_validate_cells(st)
	_validate_pubserv(st)
	_validate_government(st)
	_validate_politics(st)
	_validate_policies(st)
	_derive_policy_domains(st)
	_derive_wage_anchor(st)
	_validate_technologies(st)
	_validate_events()
	_validate_shocks(st)

	# ⑤ 跨文件引用与冗余交叉校验（悬空引用即失败）。
	_resolve_cross_refs(st)

	# ⑥ 剧本硬约束与会计对账（INV-141..151）。
	check_scenario_assertions(st)

	# ⑦ 参数包（INV-152）。
	validate_params(st)

	# ⑦′ R-BUILDING-01：把剧本给出的 cell 产能与资本迁移成「既有设施」建筑堆（每个 cell 一堆）；
	#     此后 cell 三列是堆表的求和。
	var rs: int = st.buildings.seed_legacy(st.capital.cell_capacity_active, st.capital.cell_capital_value)
	if rs != JWResult.OK:
		_fail(rs, "buildings#seed_legacy", 0, 0)
	st.capital.sync_cells_from_buildings()

	# ⑧ 构建初始账本：全部初值写成 q = −1 的开账分录（INV-023）。
	build_opening_ledger(st)

	# ⑨ content_hash / scenario_hash。
	content_hash = compute_content_hash(_root)
	st.content_hash = content_hash

	# ⑩ 冻结 ID 表：此后 SimCore 进入「零字符串」状态。
	var fr: JWResult = _ids.freeze()
	if not fr.ok:
		_fail(fr.code, "ids#freeze", fr.detail_a, fr.detail_b)

	# ⑪ 载入后立即跑一遍 P0 不变量（docs/11 §6.6 的同一条纪律）。
	#    先重建私有的上季基准，否则开局没有「上一季」可对账（finalize_load 幂等）。
	var fl: int = st.finalize_load()
	if fl != JWResult.OK:
		_fail(fl, "state#finalize_load", 0, 0)
	var p0: int = st.check_all_p0()
	if p0 != JWResult.OK:
		_fail(p0, "state#check_all_p0", 0, 0)

	return _first_error()


## 每次 load_all 都从零开始：加载器可以被重复使用，但不能带着上一次的残留结论。
func _reset() -> void:
	# 开新的一局：清掉上一局遗留的故障登记（JWResult.clear_pending 的两个合法调用点之一）。
	# 放在最前面，这样本次载入登记的故障一定是本次产生的。
	JWResult.clear_pending()
	JWResult.set_step(JWUnits.Phase.IDLE)
	errors.clear()
	_where = PackedStringArray()
	_paths = PackedStringArray()
	_docs = []
	_kinds = PackedStringArray()
	_docs.clear()
	content_hash = ""
	scenario_hash = ""
	param_set_version = 0
	_seen_io_table_card = false
	_base_service_access_ppm = PackedInt64Array()
	_base_service_access_ppm.resize(JWUnits.SERVICE_KIND)
	_base_service_access_ppm.fill(0)
	_unemployment_ppm = 0
	_bond_coupon_year_uu = 0
	_total_cash_uu = 0
	_tech_files = PackedStringArray()
	_tech_index = {}
	_op_agent = PackedInt64Array()
	_op_code = PackedInt64Array()
	_op_amount = PackedInt64Array()


func _expect_kind_of_dir(prefix: String, kind: String) -> void:
	for i: int in _paths.size():
		if _paths[i].begins_with(prefix) and _kinds[i] != kind:
			_fail(JWResult.Load.SCHEMA_HEADER, _paths[i] + "#/schema_kind", 0, 0)

## 剧本根文件（docs/11 §5.4）。
const SCENARIO_ALLOWED: PackedStringArray = [
	"schema_kind", "schema_version", "scenario_id", "label_zh", "reference_year",
	"unit_declaration", "horizon_q", "param_set_ref", "param_set_version", "root_seed",
	"includes", "enabled_policies", "baseline_policies", "enabled_events", "enabled_shocks", "season_factor_ppm",
	"prices_init", "world_init", "mandate_goals", "total_cash_uu", "notes_zh",
	"mode", "start_year", "money_rule", "research_rule",
]

## R-RESEARCH-01：剧本 research_rule 的字段（只允许战役模式）。下标 == JWResearch 内容标量槽位 5、6。
const RESEARCH_RULE_KEYS: PackedStringArray = [
	"points_per_edu_ppm", "points_per_high_skill_ppm",
]

## R-MONEY-01 / R-PRICE-LONG-01：剧本 money_rule 的字段（只允许战役模式）。下标 == JWMoney 的内容标量槽位。
const MONEY_RULE_KEYS: PackedStringArray = [
	"base_real_gdp_q_uu", "target_inflation_ppm_per_year", "adjust_ppm", "issue_cap_ppm",
	"band_floor_ppm", "band_ceil_ppm", "abs_floor_ppm", "abs_ceil_ppm", "wage_ceil_mult_ppm",
	"row_cash_floor_ppm", "firm_excess_buffer_ppm", "firm_excess_payout_ppm",
]
const MONEY_RULE_SLOTS: PackedInt64Array = [5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 17]
const MANDATE_GOAL_NAMES: PackedStringArray = ["industry", "livelihood", "fiscal"]
const SEASON_KEYS: PackedStringArray = ["gov_receipts", "gov_primary", "agri_output"]
const INCLUDE_KEYS: PackedStringArray = [
	"io_table", "regions", "population_init", "cells_init", "pubserv_init",
	"government_init", "politics_init", "assertions",
]


func _validate_scenario(st: JWSimState) -> void:
	var w: String = _scenario_dir + "/scenario.json#"
	var doc: Dictionary = _scenario_doc("scenario.json")
	if doc.is_empty():
		return
	_check_keys(doc, SCENARIO_ALLOWED, w)

	st.scenario_id = _get_str(doc, "scenario_id", w, JWResult.Load.SCHEMA_HEADER)
	if not st.scenario_id.begins_with("scenario."):
		_fail(JWResult.Load.ID_FORMAT, w + "/scenario_id", 0, 0)

	# 单位声明：四个常量逐个比对（R-SCALE-01 之后四者不再同值）。
	var ud: Dictionary = _get_dict(doc, "unit_declaration", w, JWResult.Load.SCHEMA_HEADER)
	var uw: String = w + "/unit_declaration"
	_expect_int(ud, "money_micro_per_unit", JWUnits.U_SCALE, uw, JWResult.Load.UNIT_MISMATCH)
	_expect_int(ud, "quantity_micro_per_qs", JWUnits.Q_SCALE, uw, JWResult.Load.UNIT_MISMATCH)
	_expect_int(ud, "ppm_scale", JWUnits.PPM, uw, JWResult.Load.UNIT_MISMATCH)
	_expect_int(ud, "base_price_uu_per_qs", JWUnits.BASE_PRICE, uw, JWResult.Load.UNIT_MISMATCH)

	# R-SCENARIO-01：mode 缺省为单届（旧剧本不写这个键）；start_year 缺省 0 = 不显示公历年份。
	var mode: int = JWUnits.Mode.TERM
	if doc.has("mode"):
		mode = _name_index(MODE_NAMES, _get_str(doc, "mode", w, JWResult.Load.SCHEMA_HEADER))
		if mode < 0:
			_fail(JWResult.Load.SCHEMA_HEADER, w + "/mode", 0, 0)
			mode = JWUnits.Mode.TERM
	st.mode = mode
	var start_year: int = 0
	if doc.has("start_year"):
		start_year = _get_int(doc, "start_year", w, JWResult.Load.SCHEMA_HEADER)
		if start_year < 1 or start_year > 9999:
			_fail(JWResult.Load.RANGE, w + "/start_year", start_year, 9999)
			start_year = 0
	st.start_year = start_year

	# R-CLOCK-01：单届只认 40 / 120；战役为 4 的倍数，4—1600 季（最长四百年）。
	var horizon: int = _get_int(doc, "horizon_q", w, JWResult.Load.SCHEMA_HEADER)
	var horizon_ok: bool = horizon == 40 or horizon == 120
	if mode == JWUnits.Mode.CAMPAIGN:
		horizon_ok = horizon >= 4 and horizon <= JWUnits.HORIZON_Q_MAX and horizon % 4 == 0
	if not horizon_ok:
		_fail(JWResult.Load.SCHEMA_HEADER, w + "/horizon_q", horizon, 40)
	else:
		st.horizon_q = horizon

	param_set_version = _get_int(doc, "param_set_version", w, JWResult.Load.SCHEMA_HEADER)
	st.param_set_version = param_set_version
	var pset: String = _get_str(doc, "param_set_ref", w, JWResult.Load.SCHEMA_HEADER)
	if not pset.begins_with("paramset."):
		_fail(JWResult.Load.ID_FORMAT, w + "/param_set_ref", 0, 0)

	# root_seed：int64 全域；0 表示运行时注入。
	var seed: int = _get_int(doc, "root_seed", w, JWResult.Load.SCHEMA_HEADER)
	_set_scalar(st.rng, 0, seed, w + "/root_seed")

	# includes：八项齐全且被引用的文件必须真实存在（悬空引用即失败）。
	var inc: Dictionary = _get_dict(doc, "includes", w, JWResult.Load.SCHEMA_HEADER)
	_check_keys(inc, INCLUDE_KEYS, w + "/includes")
	for i: int in INCLUDE_KEYS.size():
		var fname: String = _get_str(inc, INCLUDE_KEYS[i], w + "/includes",
				JWResult.Load.SCHEMA_HEADER)
		if fname.is_empty():
			continue
		if _doc_index(_scenario_dir + "/" + fname) < 0:
			_fail(JWResult.Load.FILE_FORMAT,
					w + "/includes/" + INCLUDE_KEYS[i] + "#dangling", 0, 0)

	_expect_id_list(doc, "enabled_policies", JWUnits.POLICY_N, "policy.P", w)
	_expect_id_list(doc, "enabled_events", JWUnits.EVENT_N, "event.E", w)
	_expect_id_list(doc, "enabled_shocks", JWUnits.SHOCK_N, "shock.S", w)

	# 季节系数：每条 4 项且 Σ == 1e6（INV-042）。
	# **没有任何状态块持有它**（已登记接口变更请求）：这里只校验，不假装写进去。
	var season: Dictionary = _get_dict(doc, "season_factor_ppm", w, JWResult.Load.SCHEMA_HEADER)
	_check_keys(season, SEASON_KEYS, w + "/season_factor_ppm")
	for i: int in SEASON_KEYS.size():
		var arr: PackedInt64Array = _get_int_array(season, SEASON_KEYS[i], 4,
				w + "/season_factor_ppm", JWResult.Load.SCHEMA_HEADER)
		var s: int = JWMath.sum(arr)
		if s != JWUnits.PPM:
			_fail(JWResult.Load.SCHEMA_HEADER,
					w + "/season_factor_ppm/" + SEASON_KEYS[i], s, JWUnits.PPM)

	_validate_prices(st, doc, w)
	_validate_world(st, doc, w)

	# mandate_goals：三项，取自闭集合。开局目标由 q == 0 的 select_mandate_goal 命令选定，
	# 因此这里只校验候选集合，不预先写 state.politics.mandate_goal。
	var goals: Array = _get_array(doc, "mandate_goals", w, JWResult.Load.SCHEMA_HEADER)
	if goals.size() != MANDATE_GOAL_NAMES.size():
		_fail(JWResult.Load.SCHEMA_HEADER, w + "/mandate_goals", goals.size(),
				MANDATE_GOAL_NAMES.size())
	for i: int in goals.size():
		if _name_index(MANDATE_GOAL_NAMES, String(goals[i])) < 0:
			_fail(JWResult.Load.SCHEMA_HEADER, w + "/mandate_goals/" + str(i), 0, 0)

	_total_cash_uu = _get_int(doc, "total_cash_uu", w, JWResult.Load.SCHEMA_HEADER)
	if _total_cash_uu < 0 or _total_cash_uu > JWUnits.AMOUNT_MAX:
		_fail(JWResult.Load.RANGE, w + "/total_cash_uu", _total_cash_uu, JWUnits.AMOUNT_MAX)
	st.total_cash_uu = _total_cash_uu

	if doc.has("money_rule"):
		_validate_money_rule(st, doc, w)
	if doc.has("research_rule"):
		_validate_research_rule(st, doc, w)


## R-RESEARCH-01：剧本的研究规则（只允许战役模式）。
func _validate_research_rule(st: JWSimState, doc: Dictionary, w: String) -> void:
	var rw: String = w + "/research_rule"
	if st.mode != JWUnits.Mode.CAMPAIGN:
		_fail(JWResult.Load.SCHEMA_HEADER, rw + "#term-mode", st.mode, JWUnits.Mode.CAMPAIGN)
		return
	var rr: Dictionary = _get_dict(doc, "research_rule", w, JWResult.Load.SCHEMA_HEADER)
	_check_keys(rr, RESEARCH_RULE_KEYS, rw)
	for i: int in RESEARCH_RULE_KEYS.size():
		var v: int = _get_int(rr, RESEARCH_RULE_KEYS[i], rw, JWResult.Load.SCHEMA_HEADER)
		if v < 0:
			_fail(JWResult.Load.RANGE, rw + "/" + RESEARCH_RULE_KEYS[i], v, 0)
		_set_scalar(st.research, 5 + i, v, rw + "/" + RESEARCH_RULE_KEYS[i])
	_set_scalar(st.research, 4, 1, rw + "#enabled")


## R-MONEY-01 / R-PRICE-LONG-01：战役模式的货币发行与长期上下限。
## 约束：只在战役模式；比率 ≥ 0；带宽下限 ≤ 1e6 ≤ 带宽上限；绝对下限 ≤ 1e6 ≤ 绝对上限；
## 篮子权重长 S、非负、合计 1e6；基期实际产出 > 0。基期货币量取剧本现金总量。
func _validate_money_rule(st: JWSimState, doc: Dictionary, w: String) -> void:
	var mw: String = w + "/money_rule"
	if st.mode != JWUnits.Mode.CAMPAIGN:
		_fail(JWResult.Load.SCHEMA_HEADER, mw + "#term-mode", st.mode, JWUnits.Mode.CAMPAIGN)
		return
	var mr: Dictionary = _get_dict(doc, "money_rule", w, JWResult.Load.SCHEMA_HEADER)
	var allowed: PackedStringArray = MONEY_RULE_KEYS.duplicate()
	allowed.append("level_weight_ppm")
	_check_keys(mr, allowed, mw)
	var vals: PackedInt64Array = PackedInt64Array()
	for i: int in MONEY_RULE_KEYS.size():
		var v: int = _get_int(mr, MONEY_RULE_KEYS[i], mw, JWResult.Load.SCHEMA_HEADER)
		if v < 0:
			_fail(JWResult.Load.RANGE, mw + "/" + MONEY_RULE_KEYS[i], v, 0)
		vals.append(v)
		_set_scalar(st.money, MONEY_RULE_SLOTS[i], v, mw + "/" + MONEY_RULE_KEYS[i])
	if vals[0] <= 0:
		_fail(JWResult.Load.RANGE, mw + "/base_real_gdp_q_uu", vals[0], 1)
	if vals[4] > JWUnits.PPM or vals[5] < JWUnits.PPM:
		_fail(JWResult.Load.RANGE, mw + "/band", vals[4], vals[5])
	if vals[6] > JWUnits.PPM or vals[7] < JWUnits.PPM:
		_fail(JWResult.Load.RANGE, mw + "/abs", vals[6], vals[7])
	var wts: PackedInt64Array = _get_int_array(mr, "level_weight_ppm", JWUnits.S, mw,
			JWResult.Load.SCHEMA_HEADER)
	var wsum: int = 0
	for s: int in wts.size():
		if wts[s] < 0:
			_fail(JWResult.Load.RANGE, mw + "/level_weight_ppm/" + str(s), wts[s], 0)
		wsum += wts[s]
	if wts.size() == JWUnits.S and wsum != JWUnits.PPM:
		_fail(JWResult.Load.SCHEMA_HEADER, mw + "/level_weight_ppm", wsum, JWUnits.PPM)
	_set_arr(st.money, 1, wts, mw + "/level_weight_ppm")
	_set_scalar(st.money, 4, _total_cash_uu, mw + "#base_money")
	# R-CLOSURE-01：开局外部现金取自 world_init.cash_uu（本函数在 _validate_world 之后运行）。
	var wi: Dictionary = doc.get("world_init", {})
	_set_scalar(st.money, 14, int(wi.get("cash_uu", 0)), mw + "#base_row_cash")
	_set_scalar(st.money, 3, 1, mw + "#enabled")


func _validate_prices(st: JWSimState, doc: Dictionary, w: String) -> void:
	var pi: Dictionary = _get_dict(doc, "prices_init", w, JWResult.Load.SCHEMA_HEADER)
	var pw: String = w + "/prices_init"
	_check_keys(pi, PackedStringArray(["sector_uu_per_qs", "base_uu_per_qs",
			"wage_uu_per_person_q", "housing_rent_uu_per_unit_q"]), pw)

	var sector: PackedInt64Array = _get_int_array(pi, "sector_uu_per_qs", JWUnits.S, pw,
			JWResult.Load.SCHEMA_HEADER)
	var base: PackedInt64Array = _get_int_array(pi, "base_uu_per_qs", JWUnits.S, pw,
			JWResult.Load.SCHEMA_HEADER)
	# INV-148：基年价的两条数组每项都必须 == BASE_PRICE，不是「约等于」。
	for s: int in JWUnits.S:
		if sector[s] != JWUnits.BASE_PRICE:
			_fail(JWResult.Load.UNIT_MISMATCH, pw + "/sector_uu_per_qs/" + str(s),
					sector[s], JWUnits.BASE_PRICE)
		if base[s] != JWUnits.BASE_PRICE:
			_fail(JWResult.Load.UNIT_MISMATCH, pw + "/base_uu_per_qs/" + str(s),
					base[s], JWUnits.BASE_PRICE)
	_set_arr(st.pricing, 0, sector, pw + "/sector_uu_per_qs")
	_set_arr(st.pricing, 1, sector, pw + "/sector_uu_per_qs#pending")
	# base_price 是内容常量，不在 JWPricing 的 STATE_ARRAY_IDS 里，只能整体赋值。
	st.pricing.base_price = base.duplicate()

	var wage: PackedInt64Array = _get_int_array(pi, "wage_uu_per_person_q", JWUnits.K, pw,
			JWResult.Load.SCHEMA_HEADER)
	for k: int in JWUnits.K:
		if wage[k] <= 0:
			_fail(JWResult.Load.RANGE, pw + "/wage_uu_per_person_q/" + str(k), wage[k], 1)
	_set_arr(st.pricing, 2, wage, pw + "/wage_uu_per_person_q")
	_set_arr(st.pricing, 3, wage, pw + "/wage_uu_per_person_q#pending")

	var rent: PackedInt64Array = _get_int_array(pi, "housing_rent_uu_per_unit_q", JWUnits.R, pw,
			JWResult.Load.SCHEMA_HEADER)
	for r: int in JWUnits.R:
		if rent[r] < 0:
			_fail(JWResult.Load.RANGE, pw + "/housing_rent_uu_per_unit_q/" + str(r), rent[r], 0)
	_set_arr(st.pricing, 4, rent, pw + "/housing_rent_uu_per_unit_q")


func _validate_world(st: JWSimState, doc: Dictionary, w: String) -> void:
	var wi: Dictionary = _get_dict(doc, "world_init", w, JWResult.Load.SCHEMA_HEADER)
	var ww: String = w + "/world_init"
	_check_keys(wi, PackedStringArray(["fx_rate_ppm", "export_demand_ppm", "import_price_ppm",
			"delivery_capacity_uqs", "credit_limit_uu", "sovereign_rate_ppm_per_q", "cash_uu",
			"base_export_uqs", "import_share_ppm"]), ww)

	# INV-105：汇率恒定，任何别的取值都会让「以基年价计的对外账」失去意义。
	_expect_int(wi, "fx_rate_ppm", JWUnits.FX_RATE_PPM, ww, JWResult.Load.UNIT_MISMATCH)

	var exp_d: PackedInt64Array = _get_int_array(wi, "export_demand_ppm", JWUnits.S, ww,
			JWResult.Load.SCHEMA_HEADER)
	var imp_p: PackedInt64Array = _get_int_array(wi, "import_price_ppm", JWUnits.S, ww,
			JWResult.Load.SCHEMA_HEADER)
	var deliv: PackedInt64Array = _get_int_array(wi, "delivery_capacity_uqs", JWUnits.S, ww,
			JWResult.Load.SCHEMA_HEADER)
	for s: int in JWUnits.S:
		if exp_d[s] < JWWorldMarket.EXPORT_DEMAND_MIN_PPM \
				or exp_d[s] > JWWorldMarket.EXPORT_DEMAND_MAX_PPM:
			_fail(JWResult.Load.RANGE, ww + "/export_demand_ppm/" + str(s), exp_d[s], 0)
		if imp_p[s] < JWWorldMarket.IMPORT_PRICE_MIN_PPM \
				or imp_p[s] > JWWorldMarket.IMPORT_PRICE_MAX_PPM:
			_fail(JWResult.Load.RANGE, ww + "/import_price_ppm/" + str(s), imp_p[s], 0)
		if deliv[s] < 0 or deliv[s] > JWUnits.QTY_MAX:
			_fail(JWResult.Load.RANGE, ww + "/delivery_capacity_uqs/" + str(s), deliv[s], 0)
	_set_arr(st.world, 0, exp_d, ww + "/export_demand_ppm")
	_set_arr(st.world, 1, imp_p, ww + "/import_price_ppm")
	_set_arr(st.world, 2, deliv, ww + "/delivery_capacity_uqs")
	# 基准副本是内容常量（冲击按它折算），不在 STATE_ARRAY_IDS 里。
	st.world.base_export_ppm = exp_d.duplicate()
	# R-EXPORT-01：基年季度出口量（content.world.base_export_uqs）。出口上限 = base × export_demand_ppm；
	# 缺它则出口恒为 0，基年最终需求凭空少掉 2.75 U/季。
	var base_exp: PackedInt64Array = _get_int_array(wi, "base_export_uqs", JWUnits.S, ww,
			JWResult.Load.SCHEMA_HEADER)
	for s2: int in JWUnits.S:
		if base_exp[s2] < 0 or base_exp[s2] > JWUnits.QTY_MAX:
			_fail(JWResult.Load.RANGE, ww + "/base_export_uqs/" + str(s2), base_exp[s2], 0)
	st.world.base_export_uqs = base_exp.duplicate()
	# R-IMPORT-01：进口份额（ppm，每项 ∈ [0, 1e6)）。
	var imp_sh: PackedInt64Array = _get_int_array(wi, "import_share_ppm", JWUnits.S, ww,
			JWResult.Load.SCHEMA_HEADER)
	for s3: int in JWUnits.S:
		if imp_sh[s3] < 0 or imp_sh[s3] >= JWUnits.PPM:
			_fail(JWResult.Load.RANGE, ww + "/import_share_ppm/" + str(s3), imp_sh[s3], JWUnits.PPM)
	st.world.import_share_ppm = imp_sh.duplicate()
	st.world.base_import_ppm = imp_p.duplicate()

	var credit: int = _get_int(wi, "credit_limit_uu", ww, JWResult.Load.SCHEMA_HEADER)
	if credit < 0 or credit > JWUnits.AMOUNT_MAX:
		_fail(JWResult.Load.RANGE, ww + "/credit_limit_uu", credit, JWUnits.AMOUNT_MAX)
	_set_scalar(st.world, 0, credit, ww + "/credit_limit_uu")
	st.world.base_credit_limit = credit
	# R-CREDIT-01：额度只约束**新增**外部借款，存量外债不占用 ⇒ credit_used 初值为 0。
	_set_scalar(st.world, 1, 0, ww + "#credit_used")

	var rate: int = _get_int(wi, "sovereign_rate_ppm_per_q", ww, JWResult.Load.SCHEMA_HEADER)
	if rate < JWWorldMarket.SOVEREIGN_RATE_MIN_PPM or rate > JWWorldMarket.SOVEREIGN_RATE_MAX_PPM:
		_fail(JWResult.Load.RANGE, ww + "/sovereign_rate_ppm_per_q", rate, 0)
	_set_scalar(st.world, 2, rate, ww + "/sovereign_rate_ppm_per_q")
	_set_scalar(st.world, 3, 0, ww + "#current_account")

	var row_cash: int = _get_int(wi, "cash_uu", ww, JWResult.Load.SCHEMA_HEADER)
	if row_cash < 0 or row_cash > JWUnits.AMOUNT_MAX:
		_fail(JWResult.Load.RANGE, ww + "/cash_uu", row_cash, JWUnits.AMOUNT_MAX)
	_add_open(JWIds.AGENT_ROW, JWIds.ACC_CASH, row_cash)


func _expect_int(obj: Dictionary, key: String, want: int, w: String, code: int) -> void:
	var got: int = _get_int(obj, key, w, code)
	if got != want:
		_fail(code, w + "/" + key, got, want)


## `enabled_*` 列表：条数齐全、ID 连续、无重复。
func _expect_id_list(doc: Dictionary, key: String, n: int, prefix: String, w: String) -> void:
	var a: Array = _get_array(doc, key, w, JWResult.Load.SCHEMA_HEADER)
	if a.size() != n:
		_fail(JWResult.Load.SCHEMA_HEADER, w + "/" + key, a.size(), n)
		return
	for i: int in n:
		var want: String = prefix + _pad2(i + 1)
		if String(a[i]) != want:
			_fail(JWResult.Load.ID_FORMAT, w + "/" + key + "/" + str(i), i, 0)

const IO_ALLOWED: PackedStringArray = [
	"schema_kind", "schema_version", "sectors", "io_coeff_uqs_per_qs",
	"labor_coeff_persons_per_qs", "energy_coeff_uqs_per_qs", "spoilage_ppm",
	"depreciation_ppm_per_q", "capacity_per_capital_uu_ppm", "emission_ppm", "storable",
	"capital_goods_split_ppm",
]


func _validate_io(st: JWSimState) -> void:
	var w: String = _scenario_dir + "/io_table.json#"
	var doc: Dictionary = _scenario_doc("io_table.json")
	if doc.is_empty():
		return
	_check_keys(doc, IO_ALLOWED, w)

	# 部门顺序是契约的一部分（docs/10 §0.5），不随文件里的写法变化。
	var sectors: Array = _get_array(doc, "sectors", w, JWResult.Load.SCHEMA_HEADER)
	if sectors.size() != JWUnits.S:
		_fail(JWResult.Load.SCHEMA_HEADER, w + "/sectors", sectors.size(), JWUnits.S)
	else:
		for s: int in JWUnits.S:
			if _sector_index(String(sectors[s])) != s:
				_fail(JWResult.Load.ID_FORMAT, w + "/sectors/" + str(s), s, 0)

	# io_coeff[row = 投入方 s_from][col = 消耗方 s_to]
	var io_coeff: PackedInt64Array = PackedInt64Array()
	io_coeff.resize(JWUnits.IO_N)
	io_coeff.fill(0)
	var rows: Dictionary = _get_dict(doc, "io_coeff_uqs_per_qs", w, JWResult.Load.SCHEMA_HEADER)
	for s_from: int in JWUnits.S:
		var rk: String = "sector." + SECTOR_NAMES[s_from]
		var rw: String = w + "/io_coeff_uqs_per_qs/" + rk
		var row: Dictionary = _get_dict(rows, rk, w + "/io_coeff_uqs_per_qs",
				JWResult.Load.SCHEMA_HEADER)
		for s_to: int in JWUnits.S:
			io_coeff[JWIds.idx_io(s_from, s_to)] = _get_int(row, "sector." + SECTOR_NAMES[s_to],
					rw, JWResult.Load.SCHEMA_HEADER)
	_set_arr(st.io, 0, io_coeff, w + "/io_coeff_uqs_per_qs")

	_set_arr(st.io, 1, _expand_labor_coeff(doc, w), w + "/labor_coeff_persons_per_qs")

	# energy_coeff 的契约形态是「每部门一项」，运行期形态是「每格一项」；
	# 展开是纯查表，V-IO-08 随后在 JWIoTable.validate() 里做冗余交叉校验。
	var energy_s: PackedInt64Array = _get_int_array(doc, "energy_coeff_uqs_per_qs", JWUnits.S, w,
			JWResult.Load.SCHEMA_HEADER)
	var energy_cell: PackedInt64Array = PackedInt64Array()
	energy_cell.resize(JWUnits.CELL)
	for cell: int in JWUnits.CELL:
		energy_cell[cell] = energy_s[JWIds.SECTOR_OF_CELL[cell]]
	_set_arr(st.io, 2, energy_cell, w + "/energy_coeff_uqs_per_qs")

	_set_arr(st.io, 3, _get_int_array(doc, "spoilage_ppm", JWUnits.S, w,
			JWResult.Load.SCHEMA_HEADER), w + "/spoilage_ppm")
	_set_arr(st.io, 4, _get_int_array(doc, "depreciation_ppm_per_q", JWUnits.S, w,
			JWResult.Load.SCHEMA_HEADER), w + "/depreciation_ppm_per_q")
	_set_arr(st.io, 5, _get_int_array(doc, "capacity_per_capital_uu_ppm", JWUnits.S, w,
			JWResult.Load.SCHEMA_HEADER), w + "/capacity_per_capital_uu_ppm")
	_set_arr(st.io, 6, _get_int_array(doc, "emission_ppm", JWUnits.S, w,
			JWResult.Load.SCHEMA_HEADER), w + "/emission_ppm")
	# R-INVEST-01：资本品构成（内容常量，Σ == 1e6，直接写成员，不进状态块协议）。
	var cg: PackedInt64Array = _get_int_array(doc, "capital_goods_split_ppm", JWUnits.S, w,
			JWResult.Load.SCHEMA_HEADER)
	if JWMath.sum(cg) != JWUnits.PPM:
		_fail(JWResult.Load.RANGE, w + "/capital_goods_split_ppm", JWMath.sum(cg), JWUnits.PPM)
	st.io.capital_goods_split_ppm = cg.duplicate()
	_set_arr(st.io, 7, _get_int_array(doc, "storable", JWUnits.S, w,
			JWResult.Load.SCHEMA_HEADER), w + "/storable")

	# V-IO-01..08 全部由 JWIoTable.validate() 落地（它是这些系数的所有者）。
	var r: JWResult = st.io.validate()
	if not r.ok:
		_fail(r.code, w + "#V-IO", r.detail_a, r.detail_b)


## `labor_coeff_persons_per_qs` 的覆盖语法：`"*"` 是按部门的默认值，
## `"cell.<region>.<sector>"` 覆盖单格。加载期展开成定长 EMP_N 数组，运行期不再有 map。
func _expand_labor_coeff(doc: Dictionary, w: String) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(JWUnits.EMP_N)
	out.fill(0)
	var lw: String = w + "/labor_coeff_persons_per_qs"
	var root: Dictionary = _get_dict(doc, "labor_coeff_persons_per_qs", w,
			JWResult.Load.SCHEMA_HEADER)
	var defaults: Dictionary = _get_dict(root, "*", lw, JWResult.Load.SCHEMA_HEADER)
	for cell: int in JWUnits.CELL:
		var s: int = JWIds.SECTOR_OF_CELL[cell]
		var by_skill: Dictionary = _get_dict(defaults, "sector." + SECTOR_NAMES[s],
				lw + "/*", JWResult.Load.IO_LABOR)
		for k: int in JWUnits.K:
			out[JWIds.idx_emp(cell, k)] = _get_int(by_skill, SKILL_NAMES[k],
					lw + "/*/sector." + SECTOR_NAMES[s], JWResult.Load.IO_LABOR)
	for key: Variant in root.keys():
		var ks: String = String(key)
		if ks == "*" or ks.begins_with("_"):
			continue
		var cell_idx: int = _cell_index(ks)
		if cell_idx < 0:
			_fail(JWResult.Load.ID_FORMAT, lw + "/" + ks, 0, 0)
			continue
		var ov: Dictionary = _get_dict(root, ks, lw, JWResult.Load.IO_LABOR)
		for k: int in JWUnits.K:
			out[JWIds.idx_emp(cell_idx, k)] = _get_int(ov, SKILL_NAMES[k], lw + "/" + ks,
					JWResult.Load.IO_LABOR)
	return out


const REGION_ALLOWED: PackedStringArray = [
	"region_id", "label_zh", "population_persons", "adjacency", "logistics_cost_ppm",
	"migration_cost_uu", "housing_capacity_units", "housing_stock_units",
	"grid_capacity_uqs_per_q", "port_capacity_uqs_per_q", "irrigation_index_ppm",
	"construction_slots_total", "area_index", "emissions_stock_uqe", "env_exposure_ppm",
]

## 冗余登记的地区人口（V-REG-05 与群组求和交叉校验）。
var _region_population_decl: PackedInt64Array = PackedInt64Array()


func _validate_regions(st: JWSimState) -> void:
	var w: String = _scenario_dir + "/regions.json#"
	var doc: Dictionary = _scenario_doc("regions.json")
	if doc.is_empty():
		return
	_check_keys(doc, PackedStringArray(["schema_kind", "schema_version", "regions"]), w)
	var list: Array = _get_array(doc, "regions", w, JWResult.Load.REGION_SET)
	if list.size() != JWUnits.R:
		_fail(JWResult.Load.REGION_SET, w + "/regions", list.size(), JWUnits.R)

	var seen: PackedInt64Array = PackedInt64Array()
	seen.resize(JWUnits.R)
	seen.fill(0)
	_region_population_decl = PackedInt64Array()
	_region_population_decl.resize(JWUnits.R)
	_region_population_decl.fill(0)

	var grid: PackedInt64Array = _zeros(JWUnits.R)
	var house_cap: PackedInt64Array = _zeros(JWUnits.R)
	var house_stock: PackedInt64Array = _zeros(JWUnits.R)
	var irrigation: PackedInt64Array = _zeros(JWUnits.R)
	var port: PackedInt64Array = _zeros(JWUnits.R)
	var slots: PackedInt64Array = _zeros(JWUnits.R)
	var emissions: PackedInt64Array = _zeros(JWUnits.R)
	var exposure: PackedInt64Array = _zeros(JWUnits.R)
	var area: PackedInt64Array = _zeros(JWUnits.R)
	var adjacency: PackedInt64Array = _zeros(JWUnits.OD_N)
	var logistics: PackedInt64Array = _zeros(JWUnits.OD_N)
	var migration_cost: PackedInt64Array = _zeros(JWUnits.OD_N)

	for i: int in list.size():
		var rw: String = w + "/regions/" + str(i)
		if typeof(list[i]) != TYPE_DICTIONARY:
			_fail(JWResult.Load.SCHEMA_HEADER, rw, typeof(list[i]), TYPE_DICTIONARY)
			continue
		var e: Dictionary = list[i]
		_check_keys(e, REGION_ALLOWED, rw)
		var rid: String = _get_str(e, "region_id", rw, JWResult.Load.REGION_SET)
		var r: int = _region_index(rid)
		if r < 0:
			_fail(JWResult.Load.ID_FORMAT, rw + "/region_id", 0, 0)
			continue
		if seen[r] != 0:
			_fail(JWResult.Load.DUP_ID, rw + "/region_id", r, 0)
			continue
		seen[r] = 1

		_region_population_decl[r] = _get_int(e, "population_persons", rw,
				JWResult.Load.POP_REGION)
		house_cap[r] = _get_int(e, "housing_capacity_units", rw, JWResult.Load.HOUSE_CAP)
		house_stock[r] = _get_int(e, "housing_stock_units", rw, JWResult.Load.HOUSE_CAP)
		# V-REG-03：存量不得超过容量。
		if house_stock[r] > house_cap[r]:
			_fail(JWResult.Load.HOUSE_CAP, rw + "/housing_stock_units",
					house_stock[r], house_cap[r])
		grid[r] = _get_int(e, "grid_capacity_uqs_per_q", rw, JWResult.Load.SCHEMA_HEADER)
		port[r] = _get_int(e, "port_capacity_uqs_per_q", rw, JWResult.Load.SCHEMA_HEADER)
		irrigation[r] = _get_int(e, "irrigation_index_ppm", rw, JWResult.Load.SCHEMA_HEADER)
		emissions[r] = _get_int(e, "emissions_stock_uqe", rw, JWResult.Load.SCHEMA_HEADER)
		exposure[r] = _get_int(e, "env_exposure_ppm", rw, JWResult.Load.SCHEMA_HEADER)
		area[r] = _get_int(e, "area_index", rw, JWResult.Load.SCHEMA_HEADER)
		if area[r] <= 0:
			# 面积指数是人口密度折算的除数，0 会让密度无定义。
			_fail(JWResult.Load.RANGE, rw + "/area_index", area[r], 1)
		slots[r] = _get_int(e, "construction_slots_total", rw, JWResult.Load.REGION_SLOTS)
		# V-REG-04：1..8（施工拥堵的失败路径可测的前提）。
		if slots[r] < 1 or slots[r] > 8:
			_fail(JWResult.Load.REGION_SLOTS, rw + "/construction_slots_total", slots[r], 8)

		var adj: Array = _get_array(e, "adjacency", rw, JWResult.Load.REGION_ADJ)
		for j: int in adj.size():
			var r2: int = _region_index(String(adj[j]))
			if r2 < 0:
				_fail(JWResult.Load.ID_FORMAT, rw + "/adjacency/" + str(j), 0, 0)
				continue
			if r2 == r:
				# V-REG-02：不允许自环。
				_fail(JWResult.Load.REGION_ADJ, rw + "/adjacency/" + str(j), r, r)
				continue
			adjacency[JWIds.idx_od(r, r2)] = 1
		_read_od_map(e, "logistics_cost_ppm", r, logistics, rw, JWResult.Load.REGION_ADJ)
		_read_od_map(e, "migration_cost_uu", r, migration_cost, rw, JWResult.Load.REGION_ADJ)

	for r: int in JWUnits.R:
		if seen[r] == 0:
			_fail(JWResult.Load.REGION_SET, w + "/regions#missing-" + _region_names[r], r, 0)
		for r2: int in JWUnits.R:
			# V-REG-02：邻接必须对称。
			if adjacency[JWIds.idx_od(r, r2)] != adjacency[JWIds.idx_od(r2, r)]:
				_fail(JWResult.Load.REGION_ADJ, w + "/regions#adjacency-asymmetric",
						JWIds.idx_od(r, r2), 0)

	_set_arr(st.capital, 11, grid, w + "#grid_capacity")
	_set_arr(st.capital, 12, _zeros(JWUnits.R), w + "#grid_pending")
	_set_arr(st.capital, 13, house_cap, w + "#housing_capacity")
	_set_arr(st.capital, 14, house_stock, w + "#housing_stock")
	_set_arr(st.capital, 15, _zeros(JWUnits.R), w + "#housing_pending")
	_set_arr(st.capital, 16, irrigation, w + "#irrigation_index")
	_set_arr(st.capital, 17, _zeros(JWUnits.R), w + "#irrigation_pending")
	_set_arr(st.capital, 18, port, w + "#port_capacity")
	_set_arr(st.capital, 19, _zeros(JWUnits.R), w + "#port_pending")
	_set_arr(st.capital, 20, slots, w + "#construction_slots")
	_set_arr(st.capital, 21, emissions, w + "#emissions_stock")
	_set_arr(st.capital, 22, exposure, w + "#env_exposure")
	_set_arr(st.capital, 23, area, w + "#area_index")
	# content.region.logistics_cost_ppm 由 JWInventory 持有（物流成本进交易定价）。
	_set_arr(st.inventory, 3, logistics, w + "#logistics_cost_ppm")
	# JWMigration 的两张内容表不在 STATE_ARRAY_IDS 里（该表按契约为空），整体赋值。
	st.migration.adjacency = adjacency.duplicate()
	st.migration.migration_cost = migration_cost.duplicate()


## 读一行 OD 映射（对其它 3 区完备、自身为 0）。
func _read_od_map(e: Dictionary, key: String, r: int, out: PackedInt64Array,
		rw: String, code: int) -> void:
	var m: Dictionary = _get_dict(e, key, rw, code)
	for r2: int in JWUnits.R:
		var v: int = _get_int(m, "region." + _region_names[r2], rw + "/" + key, code)
		if r2 == r and v != 0:
			_fail(code, rw + "/" + key + "/region." + _region_names[r2], v, 0)
		if v < 0:
			_fail(JWResult.Load.RANGE, rw + "/" + key + "/region." + _region_names[r2], v, 0)
		out[JWIds.idx_od(r, r2)] = v


func _zeros(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(0)
	return a

const GROUP_ALLOWED: PackedStringArray = [
	"group_id", "population_persons", "participation_ppm", "employed_persons", "cash_uu",
	"deposit_uu", "housing_units_occupied", "support_out_weight_ppm", "service_access_ppm",
	"consumption_index_ppm", "living_index_ppm", "base_per_capita_real_income_uu",
	"expectation_ppm", "trust_ppm", "support_ppm", "bloc_affiliation_ppm",
	# R-LIVING-01：生活与服务指数的基年基准（tools/refit_living.py 生成）。
	"base_real_consumption_uqs", "base_delivered_service_uqs",
]

## 群组人口（V-REG-05 / V-POP-02 / V-POP-08 的交叉校验用）。
var _group_population: PackedInt64Array = PackedInt64Array()
## 群组就业（180 = GROUP × 5，slot 4 为 pubserv），V-POP-08 用。
var _group_employed: PackedInt64Array = PackedInt64Array()
## 群组占用住房（V-POP-06 用）。
var _group_housing: PackedInt64Array = PackedInt64Array()
## 群组存款合计（V-FIN-09 用）。
var _group_deposit_total: int = 0


func _validate_population(st: JWSimState) -> void:
	var w: String = _scenario_dir + "/population_init.json#"
	var doc: Dictionary = _scenario_doc("population_init.json")
	if doc.is_empty():
		return
	_check_keys(doc, PackedStringArray(["schema_kind", "schema_version", "groups",
			"demography_rates"]), w)

	_group_population = _zeros(JWUnits.GROUP)
	_group_employed = _zeros(JWUnits.GROUP_EMP_N)
	_group_housing = _zeros(JWUnits.GROUP)
	_group_deposit_total = 0

	var participation: PackedInt64Array = _zeros(JWUnits.GROUP)
	var service_access: PackedInt64Array = _zeros(JWUnits.GROUP_SVC_N)
	var consumption_index: PackedInt64Array = _zeros(JWUnits.GROUP)
	var living_index: PackedInt64Array = _zeros(JWUnits.GROUP)
	var expectation: PackedInt64Array = _zeros(JWUnits.GROUP)
	var trust: PackedInt64Array = _zeros(JWUnits.GROUP)
	var support: PackedInt64Array = _zeros(JWUnits.GROUP)
	var base_income: PackedInt64Array = _zeros(JWUnits.GROUP)
	var base_cons: PackedInt64Array = _zeros(JWUnits.GROUP)
	var base_svc: PackedInt64Array = _zeros(JWUnits.GROUP_SVC_N)
	var support_out: PackedInt64Array = _zeros(JWUnits.GROUP)
	var affiliation: PackedInt64Array = _zeros(JWUnits.AFFIL_N)
	var seen: PackedInt64Array = _zeros(JWUnits.GROUP)

	var list: Array = _get_array(doc, "groups", w, JWResult.Load.GROUP_SET)
	# V-POP-01：恰好 36 条，4×3×3 全组合且无重复。
	if list.size() != JWUnits.GROUP:
		_fail(JWResult.Load.GROUP_SET, w + "/groups", list.size(), JWUnits.GROUP)

	var labor_force_total: int = 0
	var unemployed_total: int = 0

	for i: int in list.size():
		var gw: String = w + "/groups/" + str(i)
		if typeof(list[i]) != TYPE_DICTIONARY:
			_fail(JWResult.Load.SCHEMA_HEADER, gw, typeof(list[i]), TYPE_DICTIONARY)
			continue
		var e: Dictionary = list[i]
		_check_keys(e, GROUP_ALLOWED, gw)
		var gid: String = _get_str(e, "group_id", gw, JWResult.Load.GROUP_SET)
		var g: int = _group_index(gid)
		if g < 0:
			_fail(JWResult.Load.ID_FORMAT, gw + "/group_id", 0, 0)
			continue
		if seen[g] != 0:
			_fail(JWResult.Load.DUP_ID, gw + "/group_id", g, 0)
			continue
		seen[g] = 1
		var age: int = JWIds.AGE_OF_GROUP[g]

		_group_population[g] = _get_int(e, "population_persons", gw, JWResult.Load.POP_TOTAL)
		if _group_population[g] < 0:
			_fail(JWResult.Load.RANGE, gw + "/population_persons", _group_population[g], 0)
		participation[g] = _get_int(e, "participation_ppm", gw, JWResult.Load.POP_AGE_ROLE)
		_ppm_range(participation[g], gw + "/participation_ppm")
		support_out[g] = _get_int(e, "support_out_weight_ppm", gw, JWResult.Load.POP_AGE_ROLE)
		_ppm_range(support_out[g], gw + "/support_out_weight_ppm")
		_group_housing[g] = _get_int(e, "housing_units_occupied", gw, JWResult.Load.HOUSE_OVER)
		base_income[g] = _get_int(e, "base_per_capita_real_income_uu", gw,
				JWResult.Load.SCHEMA_HEADER)
		if base_income[g] <= 0:
			# 它是人均实际收入指数的分母（docs/11 §5.7「> 0，之后只读」）。
			_fail(JWResult.Load.RANGE, gw + "/base_per_capita_real_income_uu", base_income[g], 1)

		consumption_index[g] = _get_int(e, "consumption_index_ppm", gw, JWResult.Load.INDEX_BASE)
		living_index[g] = _get_int(e, "living_index_ppm", gw, JWResult.Load.INDEX_BASE)
		expectation[g] = _get_int(e, "expectation_ppm", gw, JWResult.Load.SCHEMA_HEADER)
		trust[g] = _get_int(e, "trust_ppm", gw, JWResult.Load.SCHEMA_HEADER)
		_ppm_range(trust[g], gw + "/trust_ppm")
		support[g] = _get_int(e, "support_ppm", gw, JWResult.Load.SCHEMA_HEADER)
		_ppm_range(support[g], gw + "/support_ppm")

		# V-POP-07b：逐组逐种类 ∈ [0, 1e6]。
		var sa: Dictionary = _get_dict(e, "service_access_ppm", gw, JWResult.Load.INDEX_BASE)
		_check_keys(sa, SERVICE_KIND_NAMES, gw + "/service_access_ppm")
		for kind: int in JWUnits.SERVICE_KIND:
			var v: int = _get_int(sa, SERVICE_KIND_NAMES[kind], gw + "/service_access_ppm",
					JWResult.Load.INDEX_BASE)
			if v < 0 or v > JWUnits.PPM:
				_fail(JWResult.Load.INDEX_BASE,
						gw + "/service_access_ppm/" + SERVICE_KIND_NAMES[kind], v, JWUnits.PPM)
			service_access[JWIds.idx_group_svc(g, kind)] = v

		# R-LIVING-01：消费与服务指数的基年基准（非负；服务基准按三类服务逐项）。
		base_cons[g] = _get_int(e, "base_real_consumption_uqs", gw, JWResult.Load.INDEX_BASE)
		if base_cons[g] < 0 or base_cons[g] > JWUnits.QTY_MAX:
			_fail(JWResult.Load.RANGE, gw + "/base_real_consumption_uqs", base_cons[g], 0)
		var bs: Dictionary = _get_dict(e, "base_delivered_service_uqs", gw, JWResult.Load.INDEX_BASE)
		_check_keys(bs, SERVICE_KIND_NAMES, gw + "/base_delivered_service_uqs")
		for kind2: int in JWUnits.SERVICE_KIND:
			var v2: int = _get_int(bs, SERVICE_KIND_NAMES[kind2], gw + "/base_delivered_service_uqs",
					JWResult.Load.INDEX_BASE)
			if v2 < 0 or v2 > JWUnits.QTY_MAX:
				_fail(JWResult.Load.RANGE,
						gw + "/base_delivered_service_uqs/" + SERVICE_KIND_NAMES[kind2], v2, 0)
			base_svc[JWIds.idx_group_svc(g, kind2)] = v2

		var aff: PackedInt64Array = _get_int_array(e, "bloc_affiliation_ppm", JWUnits.BLOC_N, gw,
				JWResult.Load.SCHEMA_HEADER)
		for b: int in JWUnits.BLOC_N:
			# 允许 Σ > 1e6（成员可同属多个网络），但每一项仍是比率。
			_ppm_range(aff[b], gw + "/bloc_affiliation_ppm/" + str(b))
			affiliation[JWIds.idx_affil(g, b)] = aff[b]

		var employed_g: int = _read_employment(e, g, gw)

		# V-POP-03：非 working 组不参与劳动（INV-074）。
		if age != JWUnits.Age.WORKING:
			if participation[g] != 0 or employed_g != 0 or support_out[g] != 0:
				_fail(JWResult.Load.POP_AGE_ROLE, gw, g, employed_g)
		else:
			# 失业率反算链（docs/11 §5.7，不可绕过）。
			var lf: int = JWMath.mul_div_floor(_group_population[g], participation[g], JWUnits.PPM)
			# V-POP-04：逐组 employed <= labor_force。
			if employed_g > lf:
				_fail(JWResult.Load.POP_EMP, gw + "/employed_persons", employed_g, lf)
			labor_force_total += lf
			unemployed_total += lf - employed_g

		var cash: int = _get_int(e, "cash_uu", gw, JWResult.Load.RANGE)
		var deposit: int = _get_int(e, "deposit_uu", gw, JWResult.Load.RANGE)
		if cash < 0 or deposit < 0:
			_fail(JWResult.Load.RANGE, gw + "/cash_uu", cash, deposit)
		_group_deposit_total += deposit
		var agent: int = JWIds.agent_of_group(g)
		_add_open(agent, JWIds.ACC_CASH, cash)
		_add_open(agent, JWIds.ACC_DEPOSIT_CLAIM, deposit)

	for g: int in JWUnits.GROUP:
		if seen[g] == 0:
			_fail(JWResult.Load.GROUP_SET, w + "/groups#missing-" + str(g), g, 0)

	# V-POP-05 / INV-143：**反算**失业率，schema 里不存在失业率输入字段。
	if labor_force_total > 0:
		_unemployment_ppm = JWMath.mul_div_floor(unemployed_total, JWUnits.PPM, labor_force_total)
	else:
		_fail(JWResult.Load.POP_UNEMP, w + "#labor-force-zero", 0, 0)
	if _plan_locks and _unemployment_ppm < LOCK_UNEMPLOYMENT_PPM - UNEMPLOYMENT_TOLERANCE_PPM \
			or _plan_locks and _unemployment_ppm > LOCK_UNEMPLOYMENT_PPM + UNEMPLOYMENT_TOLERANCE_PPM:
		_fail(JWResult.Load.POP_UNEMP, w + "#unemployment", _unemployment_ppm,
				LOCK_UNEMPLOYMENT_PPM)

	_check_index_bases(w, consumption_index, living_index, service_access)
	_validate_demography(st, doc, w)

	_set_arr(st.pop, 0, _group_population, w + "#population")
	_set_arr(st.pop, 1, participation, w + "#participation")
	_set_arr(st.pop, 2, _group_employed, w + "#employed")
	_set_arr(st.pop, 3, _zeros(JWUnits.EDU_N), w + "#education_cohort")
	_set_arr(st.pop, 4, _group_housing, w + "#housing_occupied")
	_set_arr(st.pop, 5, service_access, w + "#service_access")
	_set_arr(st.pop, 6, consumption_index, w + "#consumption_index")
	# R-CONS-01：上季可支配收入与上季非劳动净收入，开局没有上季，写 0。
	_set_arr(st.pop, 7, _zeros(JWUnits.GROUP), w + "#disposable_prev")
	_set_arr(st.pop, 8, _zeros(JWUnits.GROUP), w + "#nonlabor_net_prev")
	_set_arr(st.pop, 12, support_out, w + "#support_out_weight", false)
	_set_arr(st.pop, 13, base_income, w + "#base_per_capita_real_income", false)
	# R-LIVING-01：两项基年基准由 population_init 的群组字段给出（tools/refit_living.py 生成）。
	_set_arr(st.pop, 14, base_cons, w + "#base_real_consumption_uqs", false)
	_set_arr(st.pop, 15, base_svc, w + "#base_delivered_service_uqs", false)

	# 主观指标归 JWPolitics（它同时在首次写入时截下 base_* 基年副本）。
	_set_arr(st.politics, 0, living_index, w + "#living_index")
	_set_arr(st.politics, 1, expectation, w + "#expectation")
	_set_arr(st.politics, 2, trust, w + "#trust")
	_set_arr(st.politics, 3, support, w + "#support")
	_set_arr(st.politics, 4, _zeros(JWUnits.GROUP), w + "#keep_streak")
	# content.bloc_affiliation_ppm 归 JWInterestGroups，不在它的 STATE_ARRAY_IDS 里。
	st.blocs.affiliation_ppm = affiliation.duplicate()


## 读一个群组的就业分布，返回本组在岗合计。
func _read_employment(e: Dictionary, g: int, gw: String) -> int:
	var total: int = 0
	var m: Dictionary = _get_dict(e, "employed_persons", gw, JWResult.Load.POP_EMP)
	var allowed: PackedStringArray = PackedStringArray()
	for s: int in JWUnits.S:
		allowed.append("sector." + SECTOR_NAMES[s])
	allowed.append("pubserv")
	_check_keys(m, allowed, gw + "/employed_persons")
	for slot: int in allowed.size():
		var key: String = allowed[slot]
		if not m.has(key):
			continue
		var v: int = _get_int(m, key, gw + "/employed_persons", JWResult.Load.POP_EMP)
		if v < 0:
			_fail(JWResult.Load.RANGE, gw + "/employed_persons/" + key, v, 0)
			continue
		_group_employed[JWIds.idx_group_emp(g, slot)] = v
		total += v
	return total


## V-POP-07：人口加权的消费指数与生活指数均 == 1 000 000（**不含服务可及性**，R-ACCESS-01）。
## V-POP-07b：服务可及性只登记不断言，逐种类必须 > 0（它是后续季度的归一化分母）。
func _check_index_bases(w: String, consumption: PackedInt64Array, living: PackedInt64Array,
		service: PackedInt64Array) -> void:
	var pop_total: int = JWMath.sum(_group_population)
	if pop_total <= 0:
		_fail(JWResult.Load.POP_TOTAL, w + "#population-zero", pop_total, 0)
		return
	var acc_c: int = 0
	var acc_l: int = 0
	for g: int in JWUnits.GROUP:
		acc_c += JWMath.mul(_group_population[g], consumption[g])
		acc_l += JWMath.mul(_group_population[g], living[g])
	# rounding: floor, reason=V-POP-07 是恒等式断言，取整方向不影响判定（等号两边都是整数）
	var wc: int = JWMath.floor_div(acc_c, pop_total)
	var wl: int = JWMath.floor_div(acc_l, pop_total)
	if wc != JWUnits.PPM:
		_fail(JWResult.Load.INDEX_BASE, w + "#consumption_index_weighted", wc, JWUnits.PPM)
	if wl != JWUnits.PPM:
		_fail(JWResult.Load.INDEX_BASE, w + "#living_index_weighted", wl, JWUnits.PPM)

	for kind: int in JWUnits.SERVICE_KIND:
		var acc: int = 0
		for g: int in JWUnits.GROUP:
			acc += JWMath.mul(_group_population[g], service[JWIds.idx_group_svc(g, kind)])
		# rounding: floor, reason=R-ACCESS-01 的登记式逐字如此（分母取 max(Σpop, 1) 只为防崩）
		var v: int = JWMath.floor_div(acc, pop_total)
		_base_service_access_ppm[kind] = v
		if v <= 0:
			_fail(JWResult.Load.INDEX_BASE,
					w + "#base_service_access/" + SERVICE_KIND_NAMES[kind], v, 1)


func _validate_demography(st: JWSimState, doc: Dictionary, w: String) -> void:
	var dw: String = w + "/demography_rates"
	var d: Dictionary = _get_dict(doc, "demography_rates", w, JWResult.Load.SCHEMA_HEADER)
	_check_keys(d, PackedStringArray(["birth_ppm_per_q", "death_ppm_per_q", "age_out_ppm_per_q",
			"birth_target_skill"]), dw)

	var birth: PackedInt64Array = _zeros(JWUnits.R)
	var bm: Dictionary = _get_dict(d, "birth_ppm_per_q", dw, JWResult.Load.SCHEMA_HEADER)
	for r: int in JWUnits.R:
		birth[r] = _get_int(bm, "region." + _region_names[r], dw + "/birth_ppm_per_q",
				JWResult.Load.SCHEMA_HEADER)
		_ppm_range(birth[r], dw + "/birth_ppm_per_q/region." + _region_names[r])

	# 契约按年龄段给出死亡率，运行期数组按群组展开（长度 GROUP）。
	var death_by_age: PackedInt64Array = _zeros(JWUnits.A)
	var dm: Dictionary = _get_dict(d, "death_ppm_per_q", dw, JWResult.Load.SCHEMA_HEADER)
	for a: int in JWUnits.A:
		death_by_age[a] = _get_int(dm, AGE_NAMES[a], dw + "/death_ppm_per_q",
				JWResult.Load.SCHEMA_HEADER)
		_ppm_range(death_by_age[a], dw + "/death_ppm_per_q/" + AGE_NAMES[a])
	var death: PackedInt64Array = _zeros(JWUnits.GROUP)
	for g: int in JWUnits.GROUP:
		death[g] = death_by_age[JWIds.AGE_OF_GROUP[g]]

	# 老年组没有「升组」去向，契约因此只给 minor 与 working 两档；elder 恒为 0。
	var age_out: PackedInt64Array = _zeros(JWUnits.A)
	var am: Dictionary = _get_dict(d, "age_out_ppm_per_q", dw, JWResult.Load.SCHEMA_HEADER)
	_check_keys(am, PackedStringArray([AGE_NAMES[JWUnits.Age.MINOR],
			AGE_NAMES[JWUnits.Age.WORKING]]), dw + "/age_out_ppm_per_q")
	for a: int in JWUnits.A:
		if a == JWUnits.Age.ELDER:
			continue
		age_out[a] = _get_int(am, AGE_NAMES[a], dw + "/age_out_ppm_per_q",
				JWResult.Load.SCHEMA_HEADER)
		_ppm_range(age_out[a], dw + "/age_out_ppm_per_q/" + AGE_NAMES[a])

	var target: String = _get_str(d, "birth_target_skill", dw, JWResult.Load.SCHEMA_HEADER)
	# 新生儿落入 group.<r>.minor.low（§5.7）；别的取值 JWPopulation 无法执行。
	if target != SKILL_NAMES[JWUnits.Skill.LOW]:
		_fail(JWResult.Load.SCHEMA_HEADER, dw + "/birth_target_skill", 0, 0)

	_set_arr(st.pop, 9, birth, dw + "#birth_ppm", false)
	_set_arr(st.pop, 10, death, dw + "#death_ppm", false)
	_set_arr(st.pop, 11, age_out, dw + "#age_out_ppm", false)


func _ppm_range(v: int, where: String) -> void:
	if v < 0 or v > JWUnits.PPM:
		_fail(JWResult.Load.RANGE, where, v, JWUnits.PPM)

const CELL_ALLOWED: PackedStringArray = [
	"cell_id", "cash_uu", "capacity_active_uqs_per_q", "capital_value_uu",
	"inventory_output_uqs", "inventory_input_uqs", "employment_persons",
	"loss_carryforward_uu", "equity_share_ppm", "demand_expect_uqs",
]

## 生产单元在岗人数（V-POP-08 的另一侧）。
var _cell_employment: PackedInt64Array = PackedInt64Array()
## 公共服务单元在岗人数（V-POP-08 的另一侧）。
var _pubserv_employment: PackedInt64Array = PackedInt64Array()


func _validate_cells(st: JWSimState) -> void:
	var w: String = _scenario_dir + "/cells_init.json#"
	var doc: Dictionary = _scenario_doc("cells_init.json")
	if doc.is_empty():
		return
	_check_keys(doc, PackedStringArray(["schema_kind", "schema_version", "cells"]), w)

	var capacity: PackedInt64Array = _zeros(JWUnits.CELL)
	var capital: PackedInt64Array = _zeros(JWUnits.CELL)
	var inv_output: PackedInt64Array = _zeros(JWUnits.CELL)
	var inv_input: PackedInt64Array = _zeros(JWUnits.INV_N)
	var loss: PackedInt64Array = _zeros(JWUnits.CELL)
	var demand_expect: PackedInt64Array = _zeros(JWUnits.CELL)
	var equity: PackedInt64Array = _zeros(JWUnits.CELL * JWUnits.GROUP)
	_cell_employment = _zeros(JWUnits.EMP_N)
	var seen: PackedInt64Array = _zeros(JWUnits.CELL)

	var list: Array = _get_array(doc, "cells", w, JWResult.Load.CELL_SET)
	# V-CELL-01：恰好 16 条，ID 齐全无重复。
	if list.size() != JWUnits.CELL:
		_fail(JWResult.Load.CELL_SET, w + "/cells", list.size(), JWUnits.CELL)

	for i: int in list.size():
		var cw: String = w + "/cells/" + str(i)
		if typeof(list[i]) != TYPE_DICTIONARY:
			_fail(JWResult.Load.SCHEMA_HEADER, cw, typeof(list[i]), TYPE_DICTIONARY)
			continue
		var e: Dictionary = list[i]
		_check_keys(e, CELL_ALLOWED, cw)
		var cid: String = _get_str(e, "cell_id", cw, JWResult.Load.CELL_SET)
		var cell: int = _cell_index(cid)
		if cell < 0:
			_fail(JWResult.Load.ID_FORMAT, cw + "/cell_id", 0, 0)
			continue
		if seen[cell] != 0:
			_fail(JWResult.Load.DUP_ID, cw + "/cell_id", cell, 0)
			continue
		seen[cell] = 1
		var sector: int = JWIds.SECTOR_OF_CELL[cell]

		var cash: int = _get_int(e, "cash_uu", cw, JWResult.Load.RANGE)
		# R-EXPECT-01：开局需求预期（= 基年季度产量）。缺它则 S03 计划产量恒为 0，基年经济无法起步。
		demand_expect[cell] = _get_int(e, "demand_expect_uqs", cw, JWResult.Load.CELL_SET)
		if demand_expect[cell] < 0:
			_fail(JWResult.Load.RANGE, cw + "/demand_expect_uqs", demand_expect[cell], 0)
		capacity[cell] = _get_int(e, "capacity_active_uqs_per_q", cw,
				JWResult.Load.CAPACITY_INCONSISTENT)
		capital[cell] = _get_int(e, "capital_value_uu", cw, JWResult.Load.RANGE)
		inv_output[cell] = _get_int(e, "inventory_output_uqs", cw, JWResult.Load.RANGE)
		loss[cell] = _get_int(e, "loss_carryforward_uu", cw, JWResult.Load.RANGE)

		# V-CELL-06：现金非负、数量 ≤ QTY_MAX、金额 ≤ AMOUNT_MAX。
		if cash < 0 or cash > JWUnits.AMOUNT_MAX:
			_fail(JWResult.Load.RANGE, cw + "/cash_uu", cash, JWUnits.AMOUNT_MAX)
		if capital[cell] < 0 or capital[cell] > JWUnits.AMOUNT_MAX:
			_fail(JWResult.Load.RANGE, cw + "/capital_value_uu", capital[cell],
					JWUnits.AMOUNT_MAX)
		if capacity[cell] < 0 or capacity[cell] > JWUnits.QTY_MAX:
			_fail(JWResult.Load.RANGE, cw + "/capacity_active_uqs_per_q", capacity[cell],
					JWUnits.QTY_MAX)
		if inv_output[cell] < 0 or inv_output[cell] > JWUnits.QTY_MAX:
			_fail(JWResult.Load.RANGE, cw + "/inventory_output_uqs", inv_output[cell],
					JWUnits.QTY_MAX)
		if loss[cell] < 0:
			_fail(JWResult.Load.RANGE, cw + "/loss_carryforward_uu", loss[cell], 0)
		# INV-049：不可库存部门的产出库存必须为 0（电力当期使用，不跨季储存）。
		if not st.io.is_storable(sector) and inv_output[cell] != 0:
			_fail(JWResult.Load.ENERGY_INVENTORY, cw + "/inventory_output_uqs",
					inv_output[cell], 0)

		# V-CELL-03：产能与资本一致（防止「凭空产能」）。系数方向见 R-SCALE-01 连带要求 2。
		var want_cap: int = JWMath.mul_ppm(capital[cell], st.io.capacity_per_capital(sector))
		if JWMath.absi(capacity[cell] - want_cap) > 1:
			_fail(JWResult.Load.CAPACITY_INCONSISTENT, cw + "/capacity_active_uqs_per_q",
					capacity[cell], want_cap)

		_read_cell_inventory(e, cell, cw, inv_input, st)
		_read_cell_employment(e, cell, cw)
		_read_equity(e, cell, cw, equity)

		var agent: int = JWIds.agent_of_cell(cell)
		_add_open(agent, JWIds.ACC_CASH, cash)
		_add_open(agent, JWIds.ACC_CAPITAL, capital[cell])
		# 库存的开账金额按基年价折算（docs/12 §0：存货以基年价入账）。
		for s: int in JWUnits.S:
			var qty: int = inv_input[JWIds.idx_inv(cell, s)]
			if s == sector:
				qty += inv_output[cell]
			if qty == 0:
				continue
			# rounding: floor, reason=换算类（数量 × 基年价），少给优于凭空多给
			var value: int = JWMath.mul_div_floor(qty, st.pricing.base_price_of(s),
					JWUnits.Q_SCALE)
			_add_open(agent, JWIds.ACC_INV_BASE + s, value)

	for cell: int in JWUnits.CELL:
		if seen[cell] == 0:
			_fail(JWResult.Load.CELL_SET, w + "/cells#missing-" + str(cell), cell, 0)

	_set_arr(st.capital, 0, capacity, w + "#capacity_active")
	_set_arr(st.capital, 1, _zeros(JWUnits.CELL), w + "#capacity_pending")
	_set_arr(st.capital, 2, capital, w + "#capital_value")
	_set_arr(st.capital, 3, _zeros(JWUnits.CELL), w + "#wip")
	_set_arr(st.capital, 4, _zeros(JWUnits.CELL), w + "#maintenance_backlog")
	_set_arr(st.inventory, 0, inv_output, w + "#inventory_output")
	_set_arr(st.inventory, 1, inv_input, w + "#inventory_input")
	_set_arr(st.labor, 0, _cell_employment, w + "#cell_employment")
	# R-EXPECT-01：demand_expect_uqs 已升为 CellInit 一等字段（原先只登记在 `_note_` 里，读不到）。
	_set_arr(st.sectors, 0, demand_expect, w + "#demand_expect")
	_set_arr(st.sectors, 1, loss, w + "#loss_carryforward")
	_set_arr(st.pop, 16, equity, w + "#equity_share_ppm", false)


func _read_cell_inventory(e: Dictionary, cell: int, cw: String, inv_input: PackedInt64Array,
		st: JWSimState) -> void:
	var m: Dictionary = _get_dict(e, "inventory_input_uqs", cw, JWResult.Load.RANGE)
	for key: Variant in m.keys():
		var ks: String = String(key)
		if ks.begins_with("_"):
			continue
		var s: int = _sector_index(ks)
		if s < 0:
			_fail(JWResult.Load.UNKNOWN_FIELD, cw + "/inventory_input_uqs/" + ks, 0, 0)
			continue
		# V-CELL-02（R-SERVICES-01 收窄）：只有**电力**不得出现在投入库存里——它按 §5.2 逐季配给、不跨季储存。
		# 服务虽不可库存（生产方成品库存恒为 0，INV-049），但使用方上季采购的中间服务按 §5.1 的离散化
		# 正是本季的投入存量，§5.3 的材料约束也逐项读取它；在此禁止服务等于让全部 cell 的材料约束恒为 0。
		if s == JWUnits.Sector.ENERGY:
			_fail(JWResult.Load.ENERGY_INVENTORY, cw + "/inventory_input_uqs/" + ks, s, 0)
			continue
		var v: int = _get_int(m, ks, cw + "/inventory_input_uqs", JWResult.Load.RANGE)
		if v < 0 or v > JWUnits.QTY_MAX:
			_fail(JWResult.Load.RANGE, cw + "/inventory_input_uqs/" + ks, v, JWUnits.QTY_MAX)
			continue
		inv_input[JWIds.idx_inv(cell, s)] = v


func _read_cell_employment(e: Dictionary, cell: int, cw: String) -> void:
	var m: Dictionary = _get_dict(e, "employment_persons", cw, JWResult.Load.EMPLOY_MISMATCH)
	_check_keys(m, SKILL_NAMES, cw + "/employment_persons")
	for k: int in JWUnits.K:
		var v: int = _get_int(m, SKILL_NAMES[k], cw + "/employment_persons",
				JWResult.Load.EMPLOY_MISMATCH)
		if v < 0:
			_fail(JWResult.Load.RANGE, cw + "/employment_persons/" + SKILL_NAMES[k], v, 0)
			continue
		_cell_employment[JWIds.idx_emp(cell, k)] = v


## V-CELL-04：`equity_share_ppm` 各项和 == 1 000 000，且键必须是真实群组。
func _read_equity(e: Dictionary, cell: int, cw: String, equity: PackedInt64Array) -> void:
	var m: Dictionary = _get_dict(e, "equity_share_ppm", cw, JWResult.Load.EQUITY_SHARE)
	var total: int = 0
	for key: Variant in m.keys():
		var ks: String = String(key)
		if ks.begins_with("_"):
			continue
		var g: int = _group_index(ks)
		if g < 0:
			_fail(JWResult.Load.EQUITY_SHARE, cw + "/equity_share_ppm/" + ks, 0, 0)
			continue
		var v: int = _get_int(m, ks, cw + "/equity_share_ppm", JWResult.Load.EQUITY_SHARE)
		_ppm_range(v, cw + "/equity_share_ppm/" + ks)
		equity[JWMath.mul(cell, JWUnits.GROUP) + g] = v
		total += v
	if total != JWUnits.PPM:
		_fail(JWResult.Load.EQUITY_SHARE, cw + "/equity_share_ppm", total, JWUnits.PPM)


const PUBSERV_ALLOWED: PackedStringArray = [
	"pubserv_id", "capacity_active_uqs_per_q", "capital_value_uu", "availability_ppm",
	"employment_persons", "teachers_persons", "health_staff_persons",
	"service_capacity_split_ppm",
]


func _validate_pubserv(st: JWSimState) -> void:
	var w: String = _scenario_dir + "/pubserv_init.json#"
	var doc: Dictionary = _scenario_doc("pubserv_init.json")
	if doc.is_empty():
		return
	_check_keys(doc, PackedStringArray(["schema_kind", "schema_version", "units"]), w)

	var capacity: PackedInt64Array = _zeros(JWUnits.PUBSERV)
	var capital: PackedInt64Array = _zeros(JWUnits.PUBSERV)
	var availability: PackedInt64Array = _zeros(JWUnits.PUBSERV)
	var teachers: PackedInt64Array = _zeros(JWUnits.PUBSERV)
	var staff: PackedInt64Array = _zeros(JWUnits.PUBSERV)
	_pubserv_employment = _zeros(JWUnits.PUBSERV_EMP_N)
	var seen: PackedInt64Array = _zeros(JWUnits.PUBSERV)

	var list: Array = _get_array(doc, "units", w, JWResult.Load.CELL_SET)
	# V-CELL-01 的另一半：恰好 4 条。
	if list.size() != JWUnits.PUBSERV:
		_fail(JWResult.Load.CELL_SET, w + "/units", list.size(), JWUnits.PUBSERV)

	for i: int in list.size():
		var uw: String = w + "/units/" + str(i)
		if typeof(list[i]) != TYPE_DICTIONARY:
			_fail(JWResult.Load.SCHEMA_HEADER, uw, typeof(list[i]), TYPE_DICTIONARY)
			continue
		var e: Dictionary = list[i]
		_check_keys(e, PUBSERV_ALLOWED, uw)
		var r: int = _pubserv_index(_get_str(e, "pubserv_id", uw, JWResult.Load.CELL_SET))
		if r < 0:
			_fail(JWResult.Load.ID_FORMAT, uw + "/pubserv_id", 0, 0)
			continue
		if seen[r] != 0:
			_fail(JWResult.Load.DUP_ID, uw + "/pubserv_id", r, 0)
			continue
		seen[r] = 1

		capacity[r] = _get_int(e, "capacity_active_uqs_per_q", uw, JWResult.Load.RANGE)
		capital[r] = _get_int(e, "capital_value_uu", uw, JWResult.Load.RANGE)
		availability[r] = _get_int(e, "availability_ppm", uw, JWResult.Load.RANGE)
		_ppm_range(availability[r], uw + "/availability_ppm")
		teachers[r] = _get_int(e, "teachers_persons", uw, JWResult.Load.RANGE)
		staff[r] = _get_int(e, "health_staff_persons", uw, JWResult.Load.RANGE)
		if capacity[r] < 0 or capacity[r] > JWUnits.QTY_MAX:
			_fail(JWResult.Load.RANGE, uw + "/capacity_active_uqs_per_q", capacity[r],
					JWUnits.QTY_MAX)
		if capital[r] < 0 or capital[r] > JWUnits.AMOUNT_MAX:
			_fail(JWResult.Load.RANGE, uw + "/capital_value_uu", capital[r], JWUnits.AMOUNT_MAX)
		if teachers[r] < 0 or staff[r] < 0:
			_fail(JWResult.Load.RANGE, uw + "/teachers_persons", teachers[r], staff[r])

		var em: Dictionary = _get_dict(e, "employment_persons", uw, JWResult.Load.EMPLOY_MISMATCH)
		_check_keys(em, SKILL_NAMES, uw + "/employment_persons")
		var emp_total: int = 0
		for k: int in JWUnits.K:
			var v: int = _get_int(em, SKILL_NAMES[k], uw + "/employment_persons",
					JWResult.Load.EMPLOY_MISMATCH)
			if v < 0:
				_fail(JWResult.Load.RANGE, uw + "/employment_persons/" + SKILL_NAMES[k], v, 0)
				continue
			_pubserv_employment[JWIds.idx_pubserv_emp(r, k)] = v
			emp_total += v
		# 教师与医护是在岗人数的子集：两者之和超过在岗总数即口径打架。
		if teachers[r] + staff[r] > emp_total:
			_fail(JWResult.Load.EMPLOY_MISMATCH, uw + "/teachers_persons",
					teachers[r] + staff[r], emp_total)

		# V-CELL-05：三种类拆分之和 == 1e6。**没有状态块持有它**（已登记接口变更请求），
		# 因此这里只校验，不假装写进去。
		var sp: Dictionary = _get_dict(e, "service_capacity_split_ppm", uw,
				JWResult.Load.SERVICE_SPLIT)
		_check_keys(sp, SERVICE_KIND_NAMES, uw + "/service_capacity_split_ppm")
		var split_total: int = 0
		for kind: int in JWUnits.SERVICE_KIND:
			var v2: int = _get_int(sp, SERVICE_KIND_NAMES[kind],
					uw + "/service_capacity_split_ppm", JWResult.Load.SERVICE_SPLIT)
			_ppm_range(v2, uw + "/service_capacity_split_ppm/" + SERVICE_KIND_NAMES[kind])
			split_total += v2
		if split_total != JWUnits.PPM:
			_fail(JWResult.Load.SERVICE_SPLIT, uw + "/service_capacity_split_ppm",
					split_total, JWUnits.PPM)

		# pubserv 无自有现金（docs/10 §2.1），只有资本。
		_add_open(JWIds.agent_of_pubserv(r), JWIds.ACC_CAPITAL, capital[r])

	for r: int in JWUnits.PUBSERV:
		if seen[r] == 0:
			_fail(JWResult.Load.CELL_SET, w + "/units#missing-" + _region_names[r], r, 0)

	_set_arr(st.capital, 5, capacity, w + "#pub_capacity_active")
	_set_arr(st.capital, 6, _zeros(JWUnits.PUBSERV), w + "#pub_capacity_pending")
	_set_arr(st.capital, 7, capital, w + "#pub_capital_value")
	_set_arr(st.capital, 8, availability, w + "#pub_availability")
	_set_arr(st.capital, 9, teachers, w + "#pub_teachers")
	_set_arr(st.capital, 10, staff, w + "#pub_health_staff")
	_set_arr(st.labor, 1, _pubserv_employment, w + "#pubserv_employment")
	# R-PUBSTAFF-01：公共部门编制开局即剧本在岗人数。
	_set_arr(st.labor, 2, _pubserv_employment.duplicate(), w + "#pubserv_establishment")

const GOV_ALLOWED: PackedStringArray = [
	"cash_uu", "arrears_uu", "tax_receivable_uu", "wip_uu", "capital_uu", "housing_uu",
	"tax_capacity_ppm", "credit_limit_domestic_uu", "service_opex_committed_uu",
]
const RECEIPT_LINES: PackedStringArray = ["income_tax", "profit_tax", "other"]
const EXPENDITURE_LINES: PackedStringArray = [
	"public_wages", "statutory_transfers", "procurement", "project_contracts",
	"service_opex", "subsidies", "discretionary", "interest",
]
const BOND_ALLOWED: PackedStringArray = [
	"bond_id", "issue_q", "principal_initial_uu", "principal_outstanding_uu",
	"coupon_ppm_per_q", "maturity_q", "amortization", "holder",
]

## 投资池初始现金（V-FIN-08 / V-FIN-09 用）。
var _invpool_cash_uu: int = 0
## 投资池持有的债券本金合计（V-FIN-09 用）。
var _invpool_bondhold_uu: int = 0
## 年度赤字（V-FIN-08 用）。
var _annual_deficit_uu: int = 0
## 年度计划收入合计（μU），开局写入 state.gov.receipts_annualized_uu（R-DSR-01）。
var _annual_receipts_uu: int = 0
## 年度计划的政府采购档（μU/年），开局折成 treasury.procurement_budget_q_uu（R-PROCURE-01）。
var _annual_procurement_uu: int = 0


func _validate_government(st: JWSimState) -> void:
	var w: String = _scenario_dir + "/government_init.json#"
	var doc: Dictionary = _scenario_doc("government_init.json")
	if doc.is_empty():
		return
	_check_keys(doc, PackedStringArray(["schema_kind", "schema_version", "gov", "annual_plan",
			"payment_priority", "bonds", "invpool"]), w)

	# ── gov ───────────────────────────────────────────────────────────────
	var gw: String = w + "/gov"
	var gov: Dictionary = _get_dict(doc, "gov", w, JWResult.Load.CASH_INIT)
	_check_keys(gov, GOV_ALLOWED, gw)
	var gov_cash: int = _get_int(gov, "cash_uu", gw, JWResult.Load.CASH_INIT)
	# V-FIN-01 / INV-145：计划书 §05 的锁定值，容差 0。
	if _plan_locks and gov_cash != LOCK_GOV_CASH_UU:
		_fail(JWResult.Load.CASH_INIT, gw + "/cash_uu", gov_cash, LOCK_GOV_CASH_UU)
	var arrears: int = _get_int(gov, "arrears_uu", gw, JWResult.Load.FIN_LINES)
	var receivable: int = _get_int(gov, "tax_receivable_uu", gw, JWResult.Load.FIN_LINES)
	var wip: int = _get_int(gov, "wip_uu", gw, JWResult.Load.RANGE)
	var gcapital: int = _get_int(gov, "capital_uu", gw, JWResult.Load.RANGE)
	var housing: int = _get_int(gov, "housing_uu", gw, JWResult.Load.RANGE)
	var tax_cap: int = _get_int(gov, "tax_capacity_ppm", gw, JWResult.Load.RANGE)
	_ppm_range(tax_cap, gw + "/tax_capacity_ppm")
	var dom_credit: int = _get_int(gov, "credit_limit_domestic_uu", gw, JWResult.Load.RANGE)
	var opex_committed: int = _get_int(gov, "service_opex_committed_uu", gw, JWResult.Load.RANGE)
	for pair: Array in [[arrears, "arrears_uu"], [receivable, "tax_receivable_uu"],
			[wip, "wip_uu"], [gcapital, "capital_uu"], [housing, "housing_uu"],
			[dom_credit, "credit_limit_domestic_uu"],
			[opex_committed, "service_opex_committed_uu"]]:
		if int(pair[0]) < 0 or int(pair[0]) > JWUnits.AMOUNT_MAX:
			_fail(JWResult.Load.RANGE, gw + "/" + String(pair[1]), int(pair[0]),
					JWUnits.AMOUNT_MAX)

	_set_scalar(st.treasury, 0, arrears, gw + "/arrears_uu")
	_set_scalar(st.treasury, 1, receivable, gw + "/tax_receivable_uu")
	_set_scalar(st.treasury, 2, 0, gw + "#committed_memo")
	_set_scalar(st.treasury, 3, 0, gw + "#reserved_memo")
	_set_scalar(st.treasury, 4, dom_credit, gw + "/credit_limit_domestic_uu")
	_set_scalar(st.treasury, 5, opex_committed, gw + "/service_opex_committed_uu")
	_set_scalar(st.treasury, 6, tax_cap, gw + "/tax_capacity_ppm")
	# R-P11-02：建成水平（回升上限）开局 == 基年征收能力。
	_set_scalar(st.treasury, 9, tax_cap, gw + "/tax_capacity_ppm#built")
	_set_scalar(st.treasury, 7, 0, gw + "#rounding_residual")
	_set_arr(st.treasury, 0, _zeros(JWUnits.AGENT_N), gw + "#arrears_by_payee")
	_set_arr(st.treasury, 2, _zeros(JWUnits.PAY_LINE_N), gw + "#deferral_flag")

	_add_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, gov_cash)
	_add_open(JWIds.AGENT_GOV, JWIds.ACC_WIP, wip)
	_add_open(JWIds.AGENT_GOV, JWIds.ACC_CAPITAL, gcapital)
	_add_open(JWIds.AGENT_GOV, JWIds.ACC_HOUSING, housing)
	_add_open(JWIds.AGENT_GOV, JWIds.ACC_RECV, receivable)
	_add_open(JWIds.AGENT_GOV, JWIds.ACC_PAY, arrears)

	# ── payment_priority（V-FIN-06：8 类支出的全排列） ─────────────────────
	var order: Array = _get_array(doc, "payment_priority", w, JWResult.Reject.PRIORITY_INCOMPLETE)
	var prio: PackedInt64Array = _zeros(JWUnits.PAY_LINE_N)
	if order.size() != JWUnits.PAY_LINE_N:
		_fail(JWResult.Reject.PRIORITY_INCOMPLETE, w + "/payment_priority", order.size(),
				JWUnits.PAY_LINE_N)
	else:
		for i: int in order.size():
			var line: int = _name_index(PAY_LINE_NAMES, String(order[i]))
			if line < 0:
				_fail(JWResult.Reject.PRIORITY_INCOMPLETE, w + "/payment_priority/" + str(i), 0, 0)
				continue
			prio[i] = line
		_set_arr(st.treasury, 1, prio, w + "/payment_priority")

	_validate_bonds(st, doc, w)
	_validate_annual_plan(doc, w)
	# R-DSR-01：第 0 季 §2.6 的 dsr 分母取年度计划收入（此前为 1，开局每笔新债都按票息上限定价）。
	_set_scalar(st.treasury, 8, _annual_receipts_uu, w + "/annual_plan/receipts_uu")
	# R-PROCURE-01：采购档每季预算（内容常量，不进状态块；读档时随内容包重新载入）。
	st.treasury.procurement_budget_q_uu = JWMath.floor_div(maxi(0, _annual_procurement_uu), 4)

	# ── invpool ───────────────────────────────────────────────────────────
	var pool: Dictionary = _get_dict(doc, "invpool", w, JWResult.Load.INVPOOL_TOO_SMALL)
	_check_keys(pool, PackedStringArray(["cash_uu"]), w + "/invpool")
	_invpool_cash_uu = _get_int(pool, "cash_uu", w + "/invpool", JWResult.Load.INVPOOL_TOO_SMALL)
	if _invpool_cash_uu < 0 or _invpool_cash_uu > JWUnits.AMOUNT_MAX:
		_fail(JWResult.Load.RANGE, w + "/invpool/cash_uu", _invpool_cash_uu, JWUnits.AMOUNT_MAX)
	# V-FIN-08：基线年赤字必须有对手方买得起（OQ-201）。
	if _invpool_cash_uu < _annual_deficit_uu:
		_fail(JWResult.Load.INVPOOL_TOO_SMALL, w + "/invpool/cash_uu", _invpool_cash_uu,
				_annual_deficit_uu)
	_add_open(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH, _invpool_cash_uu)
	_add_open(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD, _invpool_bondhold_uu)
	# 居民存款的对手方负债在投资池（V-FIN-09 的会计表达）。
	_add_open(JWIds.AGENT_INVPOOL, JWIds.ACC_DEPOSIT_LIAB, _group_deposit_total)


func _validate_bonds(st: JWSimState, doc: Dictionary, w: String) -> void:
	var list: Array = _get_array(doc, "bonds", w, JWResult.Load.DEBT_TOTAL)
	var n: int = list.size()
	if n > JWUnits.BOND_CAP0:
		_fail(JWResult.Load.BOND_FIELD, w + "/bonds", n, JWUnits.BOND_CAP0)
		return

	var issue_q: PackedInt64Array = _zeros(JWUnits.BOND_CAP0)
	var initial: PackedInt64Array = _zeros(JWUnits.BOND_CAP0)
	var outstanding: PackedInt64Array = _zeros(JWUnits.BOND_CAP0)
	var coupon: PackedInt64Array = _zeros(JWUnits.BOND_CAP0)
	var maturity: PackedInt64Array = _zeros(JWUnits.BOND_CAP0)
	var amort: PackedInt64Array = _zeros(JWUnits.BOND_CAP0)
	var holder: PackedInt64Array = _zeros(JWUnits.BOND_CAP0)
	var status: PackedInt64Array = _zeros(JWUnits.BOND_CAP0)
	var schedule: PackedInt64Array = _zeros(JWMath.mul(JWUnits.BOND_CAP0, BOND_HORIZON_MAX))
	var ids: PackedStringArray = PackedStringArray()
	ids.resize(JWUnits.BOND_CAP0)

	var debt_total: int = 0
	var row_hold: int = 0
	_invpool_bondhold_uu = 0
	_bond_coupon_year_uu = 0

	for b: int in n:
		var bw: String = w + "/bonds/" + str(b)
		if typeof(list[b]) != TYPE_DICTIONARY:
			_fail(JWResult.Load.SCHEMA_HEADER, bw, typeof(list[b]), TYPE_DICTIONARY)
			continue
		var e: Dictionary = list[b]
		_check_keys(e, BOND_ALLOWED, bw)
		var bid: String = _get_str(e, "bond_id", bw, JWResult.Load.BOND_FIELD)
		for j: int in b:
			if ids[j] == bid:
				_fail(JWResult.Load.DUP_ID, bw + "/bond_id", j, b)
		ids[b] = bid
		# 债券 ID 只留在 SoA 的 `ids[]` 里，不进 JWIds：
		# ① 债券批次是运行期增长的 SoA，JWIds.freeze() 本来也不核它的基数；
		# ② docs/11 §4 的 `bond_id` 正则允许 `q-20` 这样的负季度段，而 JWIds.ID_PATTERN
		#    的段内字符集不含 `-`，登记开局批次必然报 ID_FORMAT。
		#    两条正则的分歧已登记为待决问题，在裁定之前不拿一个必然失败的登记去污染错误清单。

		issue_q[b] = _get_int(e, "issue_q", bw, JWResult.Load.BOND_FIELD)
		maturity[b] = _get_int(e, "maturity_q", bw, JWResult.Load.BOND_FIELD)
		initial[b] = _get_int(e, "principal_initial_uu", bw, JWResult.Load.BOND_FIELD)
		outstanding[b] = _get_int(e, "principal_outstanding_uu", bw, JWResult.Load.BOND_FIELD)
		coupon[b] = _get_int(e, "coupon_ppm_per_q", bw, JWResult.Load.BOND_FIELD)
		status[b] = JWUnits.BondStatus.ACTIVE
		var am: String = _get_str(e, "amortization", bw, JWResult.Load.BOND_FIELD)
		amort[b] = _name_index(AMORT_NAMES, am)
		var hd: String = _get_str(e, "holder", bw, JWResult.Load.BOND_FIELD)
		holder[b] = _name_index(HOLDER_NAMES, hd)

		# V-FIN-07：期限、票息与债权人。
		if maturity[b] <= issue_q[b]:
			_fail(JWResult.Load.BOND_FIELD, bw + "/maturity_q", maturity[b], issue_q[b])
		if maturity[b] - issue_q[b] >= BOND_HORIZON_MAX:
			_fail(JWResult.Load.BOND_FIELD, bw + "/maturity_q", maturity[b] - issue_q[b],
					BOND_HORIZON_MAX)
		if coupon[b] < 0 or coupon[b] > COUPON_PPM_MAX:
			_fail(JWResult.Load.BOND_FIELD, bw + "/coupon_ppm_per_q", coupon[b], COUPON_PPM_MAX)
		if amort[b] < 0:
			_fail(JWResult.Load.BOND_FIELD, bw + "/amortization", 0, 0)
			amort[b] = JWUnits.Amortization.BULLET
		if holder[b] < 0:
			_fail(JWResult.Load.BOND_FIELD, bw + "/holder", 0, 0)
			holder[b] = JWUnits.Holder.INVPOOL
		if outstanding[b] < 0 or outstanding[b] > initial[b]:
			_fail(JWResult.Load.BOND_FIELD, bw + "/principal_outstanding_uu", outstanding[b],
					initial[b])
		# 开局存量批次的 issue_q 必须为负（q=0 之前发行）。
		if issue_q[b] >= 0:
			_fail(JWResult.Load.BOND_FIELD, bw + "/issue_q", issue_q[b], 0)

		_fill_amort(schedule, b, issue_q[b], maturity[b], initial[b], outstanding[b],
				amort[b], bw)
		_bond_coupon_year_uu += _base_year_coupon(schedule, b, issue_q[b], maturity[b],
				outstanding[b], coupon[b])

		debt_total += outstanding[b]
		if holder[b] == JWUnits.Holder.INVPOOL:
			_invpool_bondhold_uu += outstanding[b]
		else:
			row_hold += outstanding[b]

	# V-FIN-02 / INV-144：合计 50 U，容差 0。
	if _plan_locks and debt_total != LOCK_DEBT_TOTAL_UU:
		_fail(JWResult.Load.DEBT_TOTAL, w + "/bonds#total", debt_total, LOCK_DEBT_TOTAL_UU)

	_set_arr(st.bonds, 0, issue_q, w + "/bonds#issue_q")
	_set_arr(st.bonds, 1, initial, w + "/bonds#principal_initial")
	_set_arr(st.bonds, 2, outstanding, w + "/bonds#principal_outstanding")
	_set_arr(st.bonds, 3, coupon, w + "/bonds#coupon_ppm")
	_set_arr(st.bonds, 4, maturity, w + "/bonds#maturity_q")
	_set_arr(st.bonds, 5, amort, w + "/bonds#amortization")
	_set_arr(st.bonds, 6, holder, w + "/bonds#holder")
	_set_arr(st.bonds, 7, status, w + "/bonds#status")
	_set_arr(st.bonds, 8, _zeros(JWUnits.BOND_CAP0), w + "/bonds#accrued_unpaid")
	_set_arr(st.bonds, 9, _zeros(JWUnits.BOND_CAP0), w + "/bonds#interest_remainder")
	_set_arr(st.bonds, 10, _zeros(JWUnits.BOND_CAP0), w + "/bonds#writeoff")
	_set_arr(st.bonds, 11, schedule, w + "/bonds#amort_schedule")
	# R-CAP-01：开局存量债的稳定实体号取 −(序号+1)，与运行期从 0 起的 entity_seq 不相交。
	var ent: PackedInt64Array = _zeros(JWUnits.BOND_CAP0)
	for j: int in n:
		ent[j] = -(j + 1)
	_set_arr(st.bonds, 12, ent, w + "/bonds#entity")
	_set_scalar(st.bonds, 0, n, w + "/bonds#count")
	st.bonds.id = ids

	# 债务是政府的负债，债权在两个持有人手上（INV-028 的开账表达）。
	_add_open(JWIds.AGENT_GOV, JWIds.ACC_DEBT, debt_total)
	_add_open(JWIds.AGENT_ROW, JWIds.ACC_BONDHOLD, row_hold)


## 重建一笔开局批次的分期表。
##
## 契约（docs/11 §5.9）明说「issue_q 到 q=0 之间已摊还几期」没有写死，留给 T03 与 12 号文件。
## 因此这里**不发明约定**，而是用唯一能被内容自身证伪的办法重建：
## 按 02.4 的「等权重预生成」在整个存续期 k ∈ [1, tenor] 上摊完 `principal_initial`，
## 再把 q < 0 的期（k < −issue_q）视作已付清零，最后断言剩余之和**逐位等于**
## 内容登记的 `principal_outstanding`。对不上就报 E_BOND_FIELD —— 说明内容用的是另一套约定，
## 那时该改的是契约，不是这里的重建式。
func _fill_amort(schedule: PackedInt64Array, b: int, issue: int, maturity: int,
		initial: int, outstanding: int, amort: int, bw: String) -> void:
	if amort != JWUnits.Amortization.LEVEL_PRINCIPAL:
		# bullet：分期表全 0，本金在到期日一次还清（JWBondBook.schedule_principal 负责）。
		if outstanding != initial:
			_fail(JWResult.Load.BOND_FIELD, bw + "/principal_outstanding_uu#bullet",
					outstanding, initial)
		return
	var tenor: int = maturity - issue
	if tenor <= 0 or tenor >= BOND_HORIZON_MAX:
		return
	var weights: PackedInt64Array = PackedInt64Array()
	var tiebreak: PackedInt64Array = PackedInt64Array()
	weights.resize(tenor)
	tiebreak.resize(tenor)
	for i: int in tenor:
		weights[i] = 1
		tiebreak[i] = i
	var parts: PackedInt64Array = JWMath.split_lr(initial, weights, tiebreak)
	if parts.size() != tenor:
		_fail(JWResult.Load.BOND_FIELD, bw + "#amort-split", parts.size(), tenor)
		return
	var base: int = JWMath.mul(b, BOND_HORIZON_MAX)
	var paid_before_q0: int = -issue
	var remaining: int = 0
	for i: int in tenor:
		var k: int = i + 1
		if k < paid_before_q0:
			continue
		schedule[base + k] = parts[i]
		remaining += parts[i]
	if remaining != outstanding:
		_fail(JWResult.Load.BOND_FIELD, bw + "/principal_outstanding_uu#schedule",
				remaining, outstanding)


## 基年四季（q = 0..3）的票息合计，逐季按**当季期初**未偿本金计提（docs/12 §2 的 02.3）。
## 02.3 先计息再还本，所以第 q 季的计息基数是扣除前 q 季还本之后的余额。
func _base_year_coupon(schedule: PackedInt64Array, b: int, issue: int, maturity: int,
		outstanding: int, coupon_ppm: int) -> int:
	var base: int = JWMath.mul(b, BOND_HORIZON_MAX)
	var remaining: int = outstanding
	var acc: int = 0
	for q: int in 4:
		if remaining <= 0:
			break
		# rounding: floor, reason=换算类（存量 × 票息率），docs/12 §2 的 02.3 逐字如此
		acc += JWMath.mul_ppm(remaining, coupon_ppm)
		if q == maturity:
			remaining = 0
			continue
		var k: int = q - issue
		if k >= 1 and k < BOND_HORIZON_MAX:
			remaining -= schedule[base + k]
	return acc


func _validate_annual_plan(doc: Dictionary, w: String) -> void:
	var aw: String = w + "/annual_plan"
	var plan: Dictionary = _get_dict(doc, "annual_plan", w, JWResult.Load.FIN_YEARPLAN)
	_check_keys(plan, PackedStringArray(["receipts_uu", "expenditure_incl_interest_uu",
			"deficit_uu", "receipt_lines_uu", "expenditure_lines_uu"]), aw)
	var receipts: int = _get_int(plan, "receipts_uu", aw, JWResult.Load.FIN_YEARPLAN)
	var spend: int = _get_int(plan, "expenditure_incl_interest_uu", aw,
			JWResult.Load.FIN_YEARPLAN)
	_annual_deficit_uu = _get_int(plan, "deficit_uu", aw, JWResult.Load.FIN_YEARPLAN)
	_annual_receipts_uu = receipts
	var el0: Dictionary = plan.get("expenditure_lines_uu", {})
	_annual_procurement_uu = int(el0.get("procurement", 0)) if el0 is Dictionary else 0

	# V-FIN-03 / INV-146：支出 − 收入 == 赤字 == 2 U，且两端都是计划书锁定值。
	if spend - receipts != _annual_deficit_uu:
		_fail(JWResult.Load.FIN_YEARPLAN, aw + "/deficit_uu", spend - receipts,
				_annual_deficit_uu)
	if _plan_locks and _annual_deficit_uu != LOCK_ANNUAL_DEFICIT_UU:
		_fail(JWResult.Load.FIN_YEARPLAN, aw + "/deficit_uu#locked", _annual_deficit_uu,
				LOCK_ANNUAL_DEFICIT_UU)
	if _plan_locks and receipts != LOCK_ANNUAL_RECEIPTS_UU:
		_fail(JWResult.Load.FIN_YEARPLAN, aw + "/receipts_uu#locked", receipts,
				LOCK_ANNUAL_RECEIPTS_UU)
	if _plan_locks and spend != LOCK_ANNUAL_EXPENDITURE_UU:
		_fail(JWResult.Load.FIN_YEARPLAN, aw + "/expenditure_incl_interest_uu#locked", spend,
				LOCK_ANNUAL_EXPENDITURE_UU)

	# V-FIN-04：两张明细表各自与合计逐位相等（不做归一化补偿）。
	var rl: Dictionary = _get_dict(plan, "receipt_lines_uu", aw, JWResult.Load.FIN_LINES)
	_check_keys(rl, RECEIPT_LINES, aw + "/receipt_lines_uu")
	var racc: int = 0
	for i: int in RECEIPT_LINES.size():
		racc += _get_int(rl, RECEIPT_LINES[i], aw + "/receipt_lines_uu", JWResult.Load.FIN_LINES)
	if racc != receipts:
		_fail(JWResult.Load.FIN_LINES, aw + "/receipt_lines_uu", racc, receipts)

	var el: Dictionary = _get_dict(plan, "expenditure_lines_uu", aw, JWResult.Load.FIN_LINES)
	_check_keys(el, EXPENDITURE_LINES, aw + "/expenditure_lines_uu")
	var eacc: int = 0
	for i: int in EXPENDITURE_LINES.size():
		eacc += _get_int(el, EXPENDITURE_LINES[i], aw + "/expenditure_lines_uu",
				JWResult.Load.FIN_LINES)
	if eacc != spend:
		_fail(JWResult.Load.FIN_LINES, aw + "/expenditure_lines_uu", eacc, spend)

	# V-FIN-05 / INV-147：利息行必须等于逐批次复算出的基年四季票息（防止债务与利息各写各的）。
	var declared: int = _get_int(el, "interest", aw + "/expenditure_lines_uu",
			JWResult.Load.FIN_INTEREST)
	if declared != _bond_coupon_year_uu:
		_fail(JWResult.Load.FIN_INTEREST, aw + "/expenditure_lines_uu/interest", declared,
				_bond_coupon_year_uu)

const POLITICS_ALLOWED: PackedStringArray = [
	"schema_kind", "schema_version", "seats_total", "seats_gov", "next_election_q",
	"next_budget_review_q", "admin_capacity_ppm", "legal_authority_mask", "blocs", "stance_ppm",
	"crisis_rule",
]
## R-REGIME-01 / R-CRISIS-01：politics_init.crisis_rule 的字段（只允许战役模式）；下标 == JWCrisis 内容标量槽位 3..7。
const CRISIS_RULE_KEYS: PackedStringArray = [
	"election_period_q", "final_window_q", "legit_warn_ppm", "legit_crisis_ppm", "legit_final_ppm",
]
func _validate_crisis_rule(st: JWSimState, doc: Dictionary, w: String) -> void:
	var cw: String = w + "/crisis_rule"
	if st.mode != JWUnits.Mode.CAMPAIGN:
		_fail(JWResult.Load.SCHEMA_HEADER, cw + "#term-mode", st.mode, JWUnits.Mode.CAMPAIGN)
		return
	var cr: Dictionary = _get_dict(doc, "crisis_rule", w, JWResult.Load.SCHEMA_HEADER)
	_check_keys(cr, CRISIS_RULE_KEYS, cw)
	var v: PackedInt64Array = PackedInt64Array()
	for i: int in CRISIS_RULE_KEYS.size():
		var x: int = _get_int(cr, CRISIS_RULE_KEYS[i], cw, JWResult.Load.SCHEMA_HEADER)
		v.append(x)
		_set_scalar(st.crisis, 3 + i, x, cw + "/" + CRISIS_RULE_KEYS[i])
	if v[0] < 4 or v[1] < 1:
		_fail(JWResult.Load.RANGE, cw + "/election_period_q", v[0], 4)
	# 三档门槛须单调：最后窗口 < 危机 < 预警，且都在 [0, 1e6]。
	if not (0 <= v[4] and v[4] < v[3] and v[3] < v[2] and v[2] <= JWUnits.PPM):
		_fail(JWResult.Load.RANGE, cw + "/legit_*_ppm", v[4], v[2])
	_set_scalar(st.crisis, 2, 1, cw + "#enabled")


const BLOC_ALLOWED: PackedStringArray = [
	"bloc_id", "label_zh", "org_power_ppm", "resource_uu", "veto_domains",
]


func _validate_politics(st: JWSimState) -> void:
	var w: String = _scenario_dir + "/politics_init.json#"
	var doc: Dictionary = _scenario_doc("politics_init.json")
	if doc.is_empty():
		return
	_check_keys(doc, POLITICS_ALLOWED, w)

	var seats_total: int = _get_int(doc, "seats_total", w, JWResult.Load.SCHEMA_HEADER)
	var seats_gov: int = _get_int(doc, "seats_gov", w, JWResult.Load.SCHEMA_HEADER)
	# V-POL-02：奇数席位（避免平票无解），且执政席位落在 [0, total]。
	var half: int = JWMath.floor_div(seats_total, 2)
	if seats_total - JWMath.mul(half, 2) != 1:
		_fail(JWResult.Load.SCHEMA_HEADER, w + "/seats_total", seats_total, 0)
	if seats_gov < 0 or seats_gov > seats_total:
		_fail(JWResult.Load.SCHEMA_HEADER, w + "/seats_gov", seats_gov, seats_total)

	var election: int = _get_int(doc, "next_election_q", w, JWResult.Load.SCHEMA_HEADER)
	# INV-127 的 {15, 31} 只约束单届剧本；战役剧本的选举日历由 crisis_rule 的周期决定（R-REGIME-01）。
	if st.mode == JWUnits.Mode.CAMPAIGN:
		if election < 0:
			_fail(JWResult.Load.SCHEMA_HEADER, w + "/next_election_q", election, 0)
	elif election != 15 and election != 31:
		_fail(JWResult.Load.SCHEMA_HEADER, w + "/next_election_q", election, 15)
	if doc.has("crisis_rule"):
		_validate_crisis_rule(st, doc, w)
	var review: int = _get_int(doc, "next_budget_review_q", w, JWResult.Load.SCHEMA_HEADER)
	# V-POL-03 / INV-127：预算审查季恒为 q ≡ 3 (mod 4)。
	if review - JWMath.mul(JWMath.floor_div(review, 4), 4) != 3:
		_fail(JWResult.Load.SCHEMA_HEADER, w + "/next_budget_review_q", review, 3)

	var admin: int = _get_int(doc, "admin_capacity_ppm", w, JWResult.Load.SCHEMA_HEADER)
	_ppm_range(admin, w + "/admin_capacity_ppm")
	var mask: int = _get_int(doc, "legal_authority_mask", w, JWResult.Load.SCHEMA_HEADER)
	if mask < 0:
		_fail(JWResult.Load.RANGE, w + "/legal_authority_mask", mask, 0)

	_set_scalar(st.politics, 0, seats_total, w + "/seats_total")
	_set_scalar(st.politics, 1, seats_gov, w + "/seats_gov")
	_set_scalar(st.politics, 2, 0, w + "#term_index")
	_set_scalar(st.politics, 3, election, w + "/next_election_q")
	_set_scalar(st.politics, 4, review, w + "/next_budget_review_q")
	_set_scalar(st.politics, 5, JWUnits.MandateGoal.INDUSTRY, w + "#mandate_goal")
	_set_scalar(st.politics, 6, JWUnits.MandateStatus.OK, w + "#mandate_status")
	_set_scalar(st.politics, 7, admin, w + "/admin_capacity_ppm")
	_set_scalar(st.politics, 8, mask, w + "/legal_authority_mask")
	_set_scalar(st.politics, 9, 0, w + "#run_terminated")
	_set_scalar(st.politics, 10, JWUnits.Termination.NONE, w + "#termination_reason")
	for slot: int in range(11, 16):
		_set_scalar(st.politics, slot, 0, w + "#politics-scalar-" + str(slot))

	# ── 三个集团（V-POL-01） ───────────────────────────────────────────────
	var org: PackedInt64Array = _zeros(JWUnits.BLOC_N)
	var resource: PackedInt64Array = _zeros(JWUnits.BLOC_N)
	var veto: PackedInt64Array = _zeros(JWUnits.BLOC_N)
	var seen: PackedInt64Array = _zeros(JWUnits.BLOC_N)
	var blocs: Array = _get_array(doc, "blocs", w, JWResult.Load.SCHEMA_HEADER)
	if blocs.size() != JWUnits.BLOC_N:
		_fail(JWResult.Load.SCHEMA_HEADER, w + "/blocs", blocs.size(), JWUnits.BLOC_N)
	for i: int in blocs.size():
		var bw: String = w + "/blocs/" + str(i)
		if typeof(blocs[i]) != TYPE_DICTIONARY:
			_fail(JWResult.Load.SCHEMA_HEADER, bw, typeof(blocs[i]), TYPE_DICTIONARY)
			continue
		var e: Dictionary = blocs[i]
		_check_keys(e, BLOC_ALLOWED, bw)
		var b: int = _bloc_index(_get_str(e, "bloc_id", bw, JWResult.Load.SCHEMA_HEADER))
		if b < 0:
			_fail(JWResult.Load.ID_FORMAT, bw + "/bloc_id", 0, 0)
			continue
		if seen[b] != 0:
			_fail(JWResult.Load.DUP_ID, bw + "/bloc_id", b, 0)
			continue
		seen[b] = 1
		org[b] = _get_int(e, "org_power_ppm", bw, JWResult.Load.SCHEMA_HEADER)
		_ppm_range(org[b], bw + "/org_power_ppm")
		resource[b] = _get_int(e, "resource_uu", bw, JWResult.Load.RANGE)
		if resource[b] < 0 or resource[b] > JWUnits.AMOUNT_MAX:
			_fail(JWResult.Load.RANGE, bw + "/resource_uu", resource[b], JWUnits.AMOUNT_MAX)
		var domains: Array = _get_array(e, "veto_domains", bw, JWResult.Load.SCHEMA_HEADER)
		for j: int in domains.size():
			var d: int = _name_index(REFORM_DOMAINS, String(domains[j]))
			if d < 0:
				_fail(JWResult.Load.SCHEMA_HEADER, bw + "/veto_domains/" + str(j), 0, 0)
				continue
			veto[b] = veto[b] | (1 << d)
	for b: int in JWUnits.BLOC_N:
		if seen[b] == 0:
			_fail(JWResult.Load.SCHEMA_HEADER, w + "/blocs#missing-" + BLOC_NAMES[b], b, 0)

	# ── 立场矩阵（3 × 12） ────────────────────────────────────────────────
	var stance: PackedInt64Array = _zeros(JWUnits.STANCE_N)
	var sm: Dictionary = _get_dict(doc, "stance_ppm", w, JWResult.Load.SCHEMA_HEADER)
	for b: int in JWUnits.BLOC_N:
		var key: String = "bloc." + BLOC_NAMES[b]
		var row: Dictionary = _get_dict(sm, key, w + "/stance_ppm", JWResult.Load.SCHEMA_HEADER)
		for p: int in JWUnits.POLICY_N:
			var pk: String = "policy.P" + _pad2(p + 1)
			var v: int = _get_int(row, pk, w + "/stance_ppm/" + key,
					JWResult.Load.SCHEMA_HEADER)
			if v < JWInterestGroups.STANCE_MIN_PPM or v > JWInterestGroups.STANCE_MAX_PPM:
				_fail(JWResult.Load.RANGE, w + "/stance_ppm/" + key + "/" + pk, v,
						JWInterestGroups.STANCE_MAX_PPM)
			stance[JWIds.idx_stance(b, p)] = v

	_set_arr(st.blocs, 0, org, w + "#org_power")
	_set_arr(st.blocs, 1, stance, w + "#stance")
	_set_arr(st.blocs, 2, resource, w + "#resource")
	_set_arr(st.blocs, 3, _zeros(JWUnits.BLOC_N), w + "#care_prev")
	st.blocs.veto_domain_mask = veto.duplicate()
	# content.policy_domain（政策 → 改革域）不单列字段：由政策的授权位推出（_derive_policy_domains，
	# R-AUTHORITY-01）。


## R-EVENT-01：把 12 张事件卡装进事件引擎（原先只校验、从不装载，事件在游戏里一次都不会发生）。
## 条件的 metric 解析成状态注册表下标或 JWEventEngine.DERIVED_BASE + k；scope 解析成引擎的范围码；
## 效应落点与范围同理；证据引用解析不了的记 EVIDENCE_NONE（只用于报告回看）。装完跑引擎自检。
## 步骤：LOAD（load_all 之后、第一次推进之前；读档不重装——计数在政治块里随存档走）
## 前置：load_all 已成功；engine.allocate() 已跑
## 后置：engine 的内容数组按卡片填满
## 不变量：INV-130、V-EV-01..07
## 失败：解析失败 → Load.METRIC_UNKNOWN / EVENT_OP / EVENT_TARGET；引擎自检失败原样返回
func load_events_into(engine: JWEventEngine, st: JWSimState) -> JWResult:
	if engine == null or st == null:
		return JWResult.make_err(JWResult.Load.EVENT_COUNT, 0, 0)
	var reg: Dictionary = {}
	for e0: int in st.registry_size():
		reg[st.registry_id(e0)] = e0
	var ops: Dictionary = {"lt": JWEventEngine.OP_LT, "le": JWEventEngine.OP_LE,
			"eq": JWEventEngine.OP_EQ, "ne": JWEventEngine.OP_NE,
			"ge": JWEventEngine.OP_GE, "gt": JWEventEngine.OP_GT}
	var targets: Dictionary = {
		"state.group.expectation_ppm": JWEventEngine.TARGET_EXPECTATION_PPM,
		"state.group.trust_ppm": JWEventEngine.TARGET_TRUST_PPM,
		"state.group.support_ppm": JWEventEngine.TARGET_SUPPORT_PPM,
		"state.bloc.org_power_ppm": JWEventEngine.TARGET_ORG_POWER_PPM,
		"state.bloc.stance_ppm": JWEventEngine.TARGET_STANCE_PPM,
		"state.politics.admin_capacity_ppm": JWEventEngine.TARGET_ADMIN_CAPACITY_PPM,
	}
	for e: int in JWUnits.EVENT_N:
		var rel: String = "events/event_E" + _pad2(e + 1) + ".json"
		var di: int = _doc_index(rel)
		if di < 0:
			return JWResult.make_err(JWResult.Load.EVENT_COUNT, e, 0)
		var doc: Dictionary = _docs[di]
		var trig: Dictionary = doc.get("trigger", {})
		engine.probability_ppm[e] = int(trig.get("probability_ppm", 0))
		engine.cooldown_q[e] = int(trig.get("cooldown_q", 0))
		engine.max_occurrences[e] = int(trig.get("max_occurrences", 0))
		engine.rng_stream[e] = JWUnits.RngStream.EVENT
		engine.ledger_effect_count[e] = 0
		var base: int = e * JWEventEngine.SLOT_N
		var conds: Array = trig.get("all_of", [])
		for i: int in mini(conds.size(), JWEventEngine.SLOT_N):
			var c: Dictionary = conds[i]
			var mid: String = String(c.get("metric", ""))
			var code: int = _event_metric_code(mid, reg)
			if code < 0:
				return JWResult.make_err(JWResult.Load.METRIC_UNKNOWN, e, i)
			engine.trigger_metric[base + i] = code
			var sc: int = _event_scope_code(String(c.get("scope", "")), mid)
			if sc == -2:
				return JWResult.make_err(JWResult.Load.METRIC_UNKNOWN, e, 100 + i)
			engine.trigger_scope[base + i] = sc
			var op: String = String(c.get("op", ""))
			if not ops.has(op):
				return JWResult.make_err(JWResult.Load.EVENT_OP, e, i)
			engine.trigger_op[base + i] = int(ops[op])
			engine.trigger_value[base + i] = int(c.get("value", 0))
		var effs: Array = doc.get("effects", [])
		for j: int in mini(effs.size(), JWEventEngine.SLOT_N):
			var f: Dictionary = effs[j]
			var tid: String = String(f.get("target", ""))
			if not targets.has(tid):
				return JWResult.make_err(JWResult.Load.EVENT_TARGET, e, j)
			engine.effect_target[base + j] = int(targets[tid])
			var esc: int = _event_scope_code(String(f.get("scope", "")), "")
			if esc == -2:
				return JWResult.make_err(JWResult.Load.EVENT_TARGET, e, 100 + j)
			engine.effect_scope[base + j] = esc
			engine.effect_delta_ppm[base + j] = int(f.get("delta_ppm", 0))
		var evs: Array = doc.get("evidence_refs", [])
		for k: int in mini(evs.size(), JWEventEngine.SLOT_N):
			var ev: Variant = evs[k]
			var eid: String = String(ev) if typeof(ev) == TYPE_STRING else String((ev as Dictionary).get("metric", ""))
			var ec: int = _event_metric_code(eid, reg)
			engine.evidence_ref[base + k] = ec if ec >= 0 else JWEventEngine.EVIDENCE_NONE
	return engine.validate()


## 事件卡的中文标题（界面报告用；读内容包原文，不是结算输入）。
func event_label(e: int) -> String:
	var di: int = _doc_index("events/event_E" + _pad2(e + 1) + ".json")
	if di < 0:
		return ""
	return String((_docs[di] as Dictionary).get("label_zh", ""))


## 事件 metric 稳定 ID → 引擎码（注册表下标，或 DERIVED_BASE + k）；解析不了返回 −1。
func _event_metric_code(mid: String, reg: Dictionary) -> int:
	if reg.has(mid):
		return int(reg[mid])
	var k: int = _name_index(JWEventEngine.DERIVED_IDS, mid)
	if k >= 0:
		return JWEventEngine.DERIVED_BASE + k
	return -1


## 事件 scope 字符串 → 引擎范围码；空串 == SCOPE_NONE；解析不了返回 −2。
## metric_id 非空且是按群组的数组（state.group.* / flow.group.*）时，region 范围编成「该地区群组之和」。
func _event_scope_code(scope: String, metric_id: String) -> int:
	if scope == "":
		return JWEventEngine.SCOPE_NONE
	var segs: PackedStringArray = scope.split(".")
	var kind: int = -1
	var idx: int = -1
	match segs[0]:
		"region":
			idx = _region_index(scope)
			kind = JWEventEngine.SCOPE_KIND_REGION
			if metric_id.begins_with("state.group.") or metric_id.begins_with("flow.group."):
				kind = JWEventEngine.SCOPE_KIND_REGION_GROUPS
		"sector":
			idx = _sector_index(scope)
			kind = JWEventEngine.SCOPE_KIND_SECTOR
		"cell":
			idx = _cell_index(scope)
			kind = JWEventEngine.SCOPE_KIND_CELL
		"pubserv":
			idx = _pubserv_index(scope)
			kind = JWEventEngine.SCOPE_KIND_PUBSERV
		"group":
			idx = _group_index(scope)
			kind = JWEventEngine.SCOPE_KIND_GROUP
		"policy":
			idx = _policy_index(scope)
			kind = JWEventEngine.SCOPE_KIND_POLICY
		"bloc":
			if segs.size() == 4 and segs[2] == "policy":
				var b: int = _name_index(BLOC_NAMES, segs[1])
				var p: int = _policy_index("policy." + segs[3])
				if b >= 0 and p >= 0:
					idx = JWIds.idx_stance(b, p)
				kind = JWEventEngine.SCOPE_KIND_STANCE
			else:
				idx = _bloc_index(scope)
				kind = JWEventEngine.SCOPE_KIND_BLOC
	if kind < 0 or idx < 0:
		return -2
	return JWEventEngine.scope_code(kind, idx)


## R-NAIRU-01：工资调整的基年松紧度锚点 = (基年空缺 0 − 基年失业) / 基年劳动力。
## 基年失业 = Σ 劳动力 − Σ（cell 在岗 + 公共部门在岗），全部取自剧本初值（加载期、开账之前），
## 与存档所处的季无关——读档重算得到同一个值，因此它不是状态，不进存档与哈希。
func _derive_wage_anchor(st: JWSimState) -> void:
	var lf: int = 0
	for g: int in JWUnits.GROUP:
		lf += st.pop.labor_force(g)
	var emp: int = JWMath.sum(st.labor.cell_employment) + JWMath.sum(st.labor.pub_employment)
	if lf <= 0:
		st.pricing.wage_anchor_tightness_ppm = 0
		return
	var unemployed: int = maxi(0, lf - emp)
	# rounding: floor（松紧度为负，floor 使锚点偏紧 1 ppm 以内，可忽略）
	st.pricing.wage_anchor_tightness_ppm = -JWMath.mul_div_floor(unemployed, JWUnits.PPM, lf)


## R-AUTHORITY-01：政策 → 改革域（JWInterestGroups.policy_domain，has_veto 的输入；关闭 OQ-252）。
## 授权位 0/1/2 与改革域 tax_law / social_program / capital_project 一一对应（politics_init
## `_note_authority_bits` 与 `_note_reform_domains` 的 required_authority_bit 同表）；位 3（重大改革权）
## 覆盖 land_reform 与 public_employment 两个域，单凭位推不出是哪一个，首版没有政策落在位 3，记为未映射。
## 集团在「非授权域」上的否决（如劳动与公共服务联盟对 P05/P10/P12 的公共岗位扩编）
## 由各政策的 requires_bloc_support 显式声明，两条来源在 S02 资格链里取并集。
func _derive_policy_domains(st: JWSimState) -> void:
	if st.policy_defs.authority_bit.size() != JWUnits.POLICY_N:
		return
	for p: int in JWUnits.POLICY_N:
		var bit: int = st.policy_defs.authority_bit[p]
		if bit >= 0 and bit <= JWInterestGroups.DOMAIN_CAPITAL_PROJECT:
			st.blocs.policy_domain[p] = bit
		else:
			st.blocs.policy_domain[p] = JWInterestGroups.DOMAIN_UNMAPPED


const POLICY_ALLOWED: PackedStringArray = [
	"schema_kind", "schema_version", "policy_id", "label_zh", "problem_statement_zh", "kind",
	"legal_authority", "player_params", "cost", "preconditions", "lag", "effect", "exit_rule",
	"political_reaction", "failure_paths", "acceptance_tests", "mechanism_ids", "cooldown_q",
	"toggle_cost_uu", "ui_text_keys",
	# effect_chain：docs/11 §5.12 的字段表里没有它，但计划书 §03 的范围契约（文档优先级第 1 位）
	# 写死「12 项政策；每项至少 1 条完整反馈链」。§5.12 是缺字段的一侧，不是内容多写的一侧，
	# 所以这里登记它 —— 但**不是只登记不看**：`_read_policy_chain` 按同一条依据判非空与环数下界，
	# 与 tools/validate_content.py 的判定逐条一致（两个检查器独立同判，不是放行）。
	# 契约侧待办已在 open_questions 上报：§5.12 的键集合应同步补入 effect_chain。
	"effect_chain",
]
## 九项必填（计划书 §09 的机器版本，V-PD-02）。
const POLICY_REQUIRED: PackedStringArray = [
	"problem_statement_zh", "legal_authority", "cost", "preconditions", "lag", "effect",
	"exit_rule", "political_reaction", "failure_paths",
]


func _validate_policies(st: JWSimState) -> void:
	var n: int = JWUnits.POLICY_N
	var kind: PackedInt64Array = _zeros(n)
	var authority_bit: PackedInt64Array = _zeros(n)
	var min_seats: PackedInt64Array = _zeros(n)
	var bloc_mask: PackedInt64Array = _zeros(n)
	var needs_review: PackedInt64Array = _zeros(n)
	var one_off: PackedInt64Array = _zeros(n)
	var per_q: PackedInt64Array = _zeros(n)
	var quarters: PackedInt64Array = _zeros(n)
	var spend: PackedInt64Array = _zeros(JWMath.mul(n, JWPolicyDef.SPEND_LINE_N))
	var opex: PackedInt64Array = _zeros(n)
	var req_constr: PackedInt64Array = _zeros(n)
	var req_equip: PackedInt64Array = _zeros(n)
	var lag: PackedInt64Array = _zeros(n)
	var commission: PackedInt64Array = _zeros(n)
	var eff_kind: PackedInt64Array = _zeros(n)
	var eff_target: PackedInt64Array = _zeros(n)
	var eff_mag: PackedInt64Array = _zeros(n)
	var pmin: PackedInt64Array = _zeros(JWUnits.POLICY_PARAM_N)
	var pmax: PackedInt64Array = _zeros(JWUnits.POLICY_PARAM_N)
	var pdef: PackedInt64Array = _zeros(JWUnits.POLICY_PARAM_N)
	var cooldown: PackedInt64Array = _zeros(n)
	var toggle: PackedInt64Array = _zeros(n)
	var exit_comp: PackedInt64Array = _zeros(n)
	var reaction: PackedInt64Array = _zeros(JWMath.mul(n, JWUnits.BLOC_N))
	var mech_mask: PackedInt64Array = _zeros(n)

	for p: int in n:
		var rel: String = "policies/policy_P" + _pad2(p + 1) + ".json"
		var idx: int = _doc_index(rel)
		if idx < 0:
			# V-PD-01：12 个政策文件齐全，ID 连续 P01..P12。
			_fail(JWResult.Load.POLICY_COUNT, rel + "#missing", p, 0)
			continue
		var w: String = rel + "#"
		var doc: Dictionary = _docs[idx]
		_check_keys(doc, POLICY_ALLOWED, w)
		_require(doc, POLICY_REQUIRED, w, JWResult.Load.POLICY_FIELDS)
		if _policy_index(_get_str(doc, "policy_id", w, JWResult.Load.POLICY_COUNT)) != p:
			_fail(JWResult.Load.POLICY_COUNT, w + "/policy_id", p, 0)
		if _get_str(doc, "problem_statement_zh", w, JWResult.Load.POLICY_FIELDS).is_empty():
			_fail(JWResult.Load.POLICY_FIELDS, w + "/problem_statement_zh", 0, 0)

		kind[p] = _name_index(POLICY_KIND_NAMES,
				_get_str(doc, "kind", w, JWResult.Load.POLICY_FIELDS))
		if kind[p] < 0:
			_fail(JWResult.Load.POLICY_FIELDS, w + "/kind", 0, 0)
			kind[p] = 0

		_read_policy_authority(doc, p, w, authority_bit, min_seats, bloc_mask, needs_review)
		_read_policy_cost(doc, p, w, one_off, per_q, quarters, spend, opex, req_constr, req_equip)
		_read_policy_lag(doc, p, w, lag, commission)
		_read_policy_effect(doc, p, w, eff_kind, eff_target, eff_mag)
		_read_policy_exit(doc, p, w, exit_comp)
		_read_policy_reaction(doc, p, w, reaction)
		_read_policy_params(doc, p, w, pmin, pmax, pdef)
		_read_policy_slots(doc, p, kind[p], st.policy_defs)
		mech_mask[p] = _read_mechanisms(doc, w)
		_read_policy_tests(doc, w)
		_read_policy_chain(doc, w)

		cooldown[p] = _get_int(doc, "cooldown_q", w, JWResult.Load.POLICY_FIELDS)
		toggle[p] = _get_int(doc, "toggle_cost_uu", w, JWResult.Load.POLICY_FIELDS)

	# JWPolicyDef.state_array() 按契约恒返回空数组（内容包不进 state_hash），
	# 因此这 25 张内容表只写不读回 —— 传 verify = false。
	_set_arr(st.policy_defs, 0, kind, "policies#kind", false)
	_set_arr(st.policy_defs, 1, authority_bit, "policies#authority_bit", false)
	_set_arr(st.policy_defs, 2, min_seats, "policies#min_seats_ppm", false)
	_set_arr(st.policy_defs, 3, bloc_mask, "policies#requires_bloc_mask", false)
	_set_arr(st.policy_defs, 4, needs_review, "policies#requires_budget_review", false)
	_set_arr(st.policy_defs, 5, one_off, "policies#cost_one_off_uu", false)
	_set_arr(st.policy_defs, 6, per_q, "policies#cost_per_quarter_uu", false)
	_set_arr(st.policy_defs, 7, quarters, "policies#planned_quarters", false)
	_set_arr(st.policy_defs, 8, spend, "policies#spend_line_uu", false)
	_set_arr(st.policy_defs, 9, opex, "policies#opex_per_q_uu", false)
	_set_arr(st.policy_defs, 10, req_constr, "policies#required_construction_uqs", false)
	_set_arr(st.policy_defs, 11, req_equip, "policies#required_equipment_uqs", false)
	_set_arr(st.policy_defs, 12, lag, "policies#lag_enact_to_effect_q", false)
	_set_arr(st.policy_defs, 13, commission, "policies#commission_delay_q", false)
	_set_arr(st.policy_defs, 14, eff_kind, "policies#effect_kind", false)
	_set_arr(st.policy_defs, 15, eff_target, "policies#effect_target", false)
	_set_arr(st.policy_defs, 16, eff_mag, "policies#effect_magnitude", false)
	_set_arr(st.policy_defs, 17, pmin, "policies#param_min_ppm", false)
	_set_arr(st.policy_defs, 18, pmax, "policies#param_max_ppm", false)
	_set_arr(st.policy_defs, 19, pdef, "policies#param_default", false)
	_set_arr(st.policy_defs, 20, cooldown, "policies#cooldown_q", false)
	_set_arr(st.policy_defs, 21, toggle, "policies#toggle_cost_uu", false)
	_set_arr(st.policy_defs, 22, exit_comp, "policies#exit_compensation_ppm", false)
	_set_arr(st.policy_defs, 23, reaction, "policies#political_reaction", false)
	_set_arr(st.policy_defs, 24, mech_mask, "policies#mechanism_mask", false)

	# V-PD-01..04、08..11 的 SoA 可判定部分由所有者落地。
	var r: JWResult = st.policy_defs.validate()
	if not r.ok:
		_fail(r.code, "policies#V-PD", r.detail_a, r.detail_b)

	# 政策参数槽的开局值 = 模板默认值（JWPolicyEngine.allocate 的注释指定由本加载器装填）。
	# 未启用的政策也装填：是否生效由 is_effective 单点把关（INV-095），
	# 装填只保证玩家首次启用而不改参数时取模板默认值，而不是 0。
	_set_arr(st.policy, 3, pdef, "policies#params_ppm_default")
	_apply_baseline_policies(st)
	# R-PSLOT-01：region_mask 由参数槽同步（开局取模板默认值；此后随参数落定而同步）。
	st.policy.sync_all_region_masks(st.policy_defs)


## R-BASELINE-01：剧本声明的开局现行制度（docs/18）。
## 步骤：LOAD
## 前置：政策模板已解析，params_ppm 已装填默认值
## 后置：列入 baseline_policies 的政策 enabled = 1、enacted_q = ENACTED_BEFORE_START、
##       effective_from_q = 0；其余政策保持 allocate() 的「未通过」初值
## 不变量：INV-095（开局即生效，时滞视为开局前已走完）
## 失败：缺字段 / ID 不存在 / 重复 → 拒绝启动
##
## 计划书 §05 的基年财政（全年收入 20 U、支出 22 U 含法定转移）来自开局就在执行的制度；
## 若它们不在 q=0 生效，基年第一季的税收恒为 0，国库在第 0 季即被掏空。
func _apply_baseline_policies(st: JWSimState) -> void:
	var w: String = _scenario_dir + "/scenario.json#/baseline_policies"
	var doc: Dictionary = _scenario_doc("scenario.json")
	var list: Array = _get_array(doc, "baseline_policies", w, JWResult.Load.SCHEMA_HEADER)
	var en: PackedInt64Array = _zeros(JWUnits.POLICY_N)
	var enacted: PackedInt64Array = _zeros(JWUnits.POLICY_N)
	var eff: PackedInt64Array = _zeros(JWUnits.POLICY_N)
	enacted.fill(-1)
	eff.fill(-1)
	for i: int in list.size():
		var p: int = _policy_index(String(list[i]))
		if p < 0:
			_fail(JWResult.Load.ID_FORMAT, w + "/" + str(i), 0, 0)
			continue
		if en[p] == 1:
			_fail(JWResult.Load.ID_FORMAT, w + "/" + str(i) + "#duplicate", p, 0)
			continue
		en[p] = 1
		enacted[p] = JWPolicyEngine.ENACTED_BEFORE_START
		eff[p] = 0
	_set_arr(st.policy, 0, en, w + "#enabled")
	_set_arr(st.policy, 1, enacted, w + "#enacted_q")
	_set_arr(st.policy, 2, eff, w + "#effective_from_q")


func _read_policy_authority(doc: Dictionary, p: int, w: String, bit: PackedInt64Array,
		seats: PackedInt64Array, mask: PackedInt64Array, review: PackedInt64Array) -> void:
	var aw: String = w + "/legal_authority"
	var la: Dictionary = _get_dict(doc, "legal_authority", w, JWResult.Load.POLICY_FIELDS)
	_check_keys(la, PackedStringArray(["authority_bit", "requires_budget_review",
			"requires_bloc_support", "min_seats_ppm"]), aw)
	bit[p] = _get_int(la, "authority_bit", aw, JWResult.Load.POLICY_FIELDS)
	if bit[p] < 0 or bit[p] >= 63:
		_fail(JWResult.Load.POLICY_FIELDS, aw + "/authority_bit", bit[p], 63)
		bit[p] = 0
	seats[p] = _get_int(la, "min_seats_ppm", aw, JWResult.Load.POLICY_FIELDS)
	_ppm_range(seats[p], aw + "/min_seats_ppm")
	review[p] = _get_flag(la, "requires_budget_review", aw, JWResult.Load.POLICY_FIELDS)
	var need: Array = _get_array(la, "requires_bloc_support", aw, JWResult.Load.POLICY_FIELDS)
	for i: int in need.size():
		var b: int = _bloc_index(String(need[i]))
		if b < 0:
			_fail(JWResult.Load.ID_FORMAT, aw + "/requires_bloc_support/" + str(i), 0, 0)
			continue
		mask[p] = mask[p] | (1 << b)


func _read_policy_cost(doc: Dictionary, p: int, w: String, one_off: PackedInt64Array,
		per_q: PackedInt64Array, quarters: PackedInt64Array, spend: PackedInt64Array,
		opex: PackedInt64Array, constr: PackedInt64Array, equip: PackedInt64Array) -> void:
	var cw: String = w + "/cost"
	var c: Dictionary = _get_dict(doc, "cost", w, JWResult.Load.POLICY_COST)
	_check_keys(c, PackedStringArray(["one_off_uu", "per_quarter_uu", "planned_quarters",
			"spend_lines_uu_per_q", "opex_per_q_uu", "required_construction_uqs",
			"required_equipment_uqs"]), cw)
	one_off[p] = _get_int(c, "one_off_uu", cw, JWResult.Load.POLICY_COST)
	per_q[p] = _get_int(c, "per_quarter_uu", cw, JWResult.Load.POLICY_COST)
	quarters[p] = _get_int(c, "planned_quarters", cw, JWResult.Load.POLICY_COST)
	opex[p] = _get_int(c, "opex_per_q_uu", cw, JWResult.Load.POLICY_COST)
	constr[p] = _get_int(c, "required_construction_uqs", cw, JWResult.Load.POLICY_COST)
	equip[p] = _get_int(c, "required_equipment_uqs", cw, JWResult.Load.POLICY_COST)

	# ── 支出落点：槽位是定死的三个，名字只在项目口径上是定死的 ──────────────
	# `content.policy.spend_line_uu` 是 12×3 的**定位**表（docs/17 §4.8）。
	# docs/12 §04.4 只为「项目付款」写了按名字查的收款方映射：
	#     import_equipment → agent.row（同时进 flow.world.imports_*）
	#     domestic_material → cell.<r>.manu
	#     construction_service → cell.<r>.services
	# 所以这三个名字对**能进项目队列的政策**是契约定死的，改名就等于改收款方。
	# 而 `JWProjectQueue.enqueue` 对 `required_construction_uqs <= 0` 直接拒绝入队，
	# 于是 `required_construction_uqs == 0` 的政策永远走不到那张映射表：
	# 它的三个槽位是这条政策自己的支出标签（税务行政工资、法定转移、补助核查…），
	# 契约里没有、也不可能有一张全局的线名表 —— 把税务行政工资硬塞进「进口设备」才是改账。
	#
	# 两种口径都不放水：
	#   · 项目口径：三条线逐字齐全，缺一条即 E_POLICY_COST（不靠 V-PD-03 事后兜底）；
	#   · 政策口径：键名须是合法 snake_case、互不重名、条数 ≤ 3，金额按声明次序落槽，
	#     一分钱都不丢。V-PD-03「Σ spend_lines == per_quarter_uu」的精确相等
	#     由 `JWPolicyDef.validate()` 逐政策钉死，拼错线名会立刻把这条和打破。
	# 槽序只对项目口径有意义（收款方按名字定），政策口径的槽序不进任何结算式。
	var lw: String = cw + "/spend_lines_uu_per_q"
	var lines: Dictionary = _get_dict(c, "spend_lines_uu_per_q", cw, JWResult.Load.POLICY_COST)
	var base: int = JWMath.mul(p, JWPolicyDef.SPEND_LINE_N)
	if constr[p] > 0:
		_check_keys(lines, SPEND_LINE_NAMES, lw)
		for line: int in JWPolicyDef.SPEND_LINE_N:
			spend[base + line] = _get_int(lines, SPEND_LINE_NAMES[line], lw,
					JWResult.Load.POLICY_COST)
		return
	var slot: int = 0
	var seen: PackedStringArray = PackedStringArray()
	for k: Variant in lines.keys():
		var ks: String = String(k)
		if ks.begins_with("_"):
			continue
		if not _key_is_legal(ks):
			_fail(JWResult.Load.KEY_NAMING, lw + "/" + ks, 0, 0)
			continue
		if seen.has(ks):
			_fail(JWResult.Load.DUP_ID, lw + "/" + ks, 0, 0)
			continue
		seen.append(ks)
		if slot >= JWPolicyDef.SPEND_LINE_N:
			# 槽位只有三个：多出来的线没有地方放，报错而不是悄悄丢掉它的金额。
			_fail(JWResult.Load.POLICY_COST, lw + "/" + ks, slot, JWPolicyDef.SPEND_LINE_N)
			continue
		spend[base + slot] = _get_int(lines, ks, lw, JWResult.Load.POLICY_COST)
		slot += 1
	if slot == 0:
		_fail(JWResult.Load.POLICY_COST, lw, 0, 1)


func _read_policy_lag(doc: Dictionary, p: int, w: String, lag: PackedInt64Array,
		commission: PackedInt64Array) -> void:
	var lw: String = w + "/lag"
	var l: Dictionary = _get_dict(doc, "lag", w, JWResult.Load.POLICY_FIELDS)
	_check_keys(l, PackedStringArray(["enact_to_effect_q", "min_feedback_q", "max_feedback_q",
			"commission_delay_q"]), lw)
	lag[p] = _get_int(l, "enact_to_effect_q", lw, JWResult.Load.POLICY_FIELDS)
	commission[p] = _get_int(l, "commission_delay_q", lw, JWResult.Load.COMMISSION_LAG)
	var fmin: int = _get_int(l, "min_feedback_q", lw, JWResult.Load.POLICY_FIELDS)
	var fmax: int = _get_int(l, "max_feedback_q", lw, JWResult.Load.POLICY_FIELDS)
	if fmin < 0 or fmax < fmin:
		_fail(JWResult.Load.POLICY_FIELDS, lw + "/max_feedback_q", fmax, fmin)


func _read_policy_effect(doc: Dictionary, p: int, w: String, ekind: PackedInt64Array,
		target: PackedInt64Array, magnitude: PackedInt64Array) -> void:
	var ew: String = w + "/effect"
	var e: Dictionary = _get_dict(doc, "effect", w, JWResult.Load.EFFECT_TARGET)
	var ks: String = _get_str(e, "kind", ew, JWResult.Load.EFFECT_TARGET)
	ekind[p] = _name_index(EFFECT_KINDS, ks)
	if ekind[p] < 0:
		_fail(JWResult.Load.EFFECT_TARGET, ew + "/kind", 0, 0)
		ekind[p] = 0
	# V-PD-10 / V-PD-11：落点白名单由 JWPolicyDef 持有；表里只有 *_pending_* 形态，
	# 落在 *_active_* 上的字符串根本查不到。
	target[p] = JWPolicyDef.effect_target_code(_get_str(e, "target", ew,
			JWResult.Load.EFFECT_TARGET))
	if target[p] < 0:
		_fail(JWResult.Load.EFFECT_TARGET, ew + "/target", p, 0)
		target[p] = 0
	for i: int in EFFECT_MAGNITUDE_KEYS.size():
		if e.has(EFFECT_MAGNITUDE_KEYS[i]):
			magnitude[p] = _get_int(e, EFFECT_MAGNITUDE_KEYS[i], ew,
					JWResult.Load.EFFECT_TARGET)
			break
	# V-PD-05：capacity_unit_ref 必须指向真实部门（只有产能类效果才有这个字段）。
	if e.has("capacity_unit_ref"):
		if _sector_index(_get_str(e, "capacity_unit_ref", ew, JWResult.Load.UNIT_MISMATCH)) < 0:
			_fail(JWResult.Load.UNIT_MISMATCH, ew + "/capacity_unit_ref", p, 0)


func _read_policy_exit(doc: Dictionary, p: int, w: String, comp: PackedInt64Array) -> void:
	var xw: String = w + "/exit_rule"
	var x: Dictionary = _get_dict(doc, "exit_rule", w, JWResult.Load.POLICY_FIELDS)
	_require(x, PackedStringArray(["delivered_assets", "unfinished_work", "compensation_rule",
			"compensation_ppm"]), xw, JWResult.Load.POLICY_FIELDS)
	comp[p] = _get_int(x, "compensation_ppm", xw, JWResult.Load.POLICY_FIELDS)
	_ppm_range(comp[p], xw + "/compensation_ppm")


func _read_policy_reaction(doc: Dictionary, p: int, w: String, out: PackedInt64Array) -> void:
	var rw: String = w + "/political_reaction"
	var m: Dictionary = _get_dict(doc, "political_reaction", w, JWResult.Load.POLICY_FIELDS)
	for key: Variant in m.keys():
		var ks: String = String(key)
		if ks.begins_with("_"):
			continue
		var b: int = _bloc_index(ks)
		if b < 0:
			_fail(JWResult.Load.ID_FORMAT, rw + "/" + ks, 0, 0)
			continue
		out[JWMath.mul(p, JWUnits.BLOC_N) + b] = _get_int(m, ks, rw,
				JWResult.Load.POLICY_FIELDS)


## `funding_source` 的键名：它是唯一一个**有自己的命令槽**、因而不占政策参数槽的玩家参数。
const FUNDING_SOURCE_KEY: String = "funding_source"


## V-PD-09：每个 player_params 项有 valid_range 与 default，且 default ∈ valid_range。
## 枚举型（§5.12 示例的 funding_source）以 `values` 的下标为取值域。
func _read_policy_params(doc: Dictionary, p: int, w: String, pmin: PackedInt64Array,
		pmax: PackedInt64Array, pdef: PackedInt64Array) -> void:
	var list: Array = _get_array(doc, "player_params", w, JWResult.Reject.PARAM_RANGE)
	# `funding_source` 是玩家参数，但它**不占政策参数槽**：`JWCommands` 给它单开了一个
	# `SLOT_ENACT_FUNDING`（policy_enact）/ `SLOT_LAUNCH_FUNDING`（project_launch），
	# 并按 `FUNDING_SOURCE_N` 自行判界，而四个 `SLOT_PARAM_BASE + j` 才走 `defs.param_range(p, j)`。
	# docs/11 §5.12 的 P04 示例把它和另外两个旋钮并列写在 player_params 里，也正是这个意思。
	# 所以槽位预算只算「非 funding_source」项：把它算进去，等于凭空吃掉一个真旋钮的位置。
	var budget: int = 0
	for i: int in list.size():
		if typeof(list[i]) == TYPE_DICTIONARY and String((list[i] as Dictionary).get(
				"key", "")) == FUNDING_SOURCE_KEY:
			continue
		budget += 1
	if budget > JWIds.POLICY_PARAM_STRIDE:
		# SoA 与命令行宽都只有 4 个参数槽位（docs/17 §4.8、JWIds.POLICY_PARAM_STRIDE），
		# 第 5 个旋钮无处安放：它既写不进状态，也没有命令槽能递交它 —— 报错，不静默丢弃。
		_fail(JWResult.Reject.PARAM_RANGE, w + "/player_params", budget,
				JWIds.POLICY_PARAM_STRIDE)
	var j: int = -1
	for i: int in list.size():
		var jw: String = w + "/player_params/" + str(i)
		if typeof(list[i]) != TYPE_DICTIONARY:
			_fail(JWResult.Load.SCHEMA_HEADER, jw, typeof(list[i]), TYPE_DICTIONARY)
			continue
		var e: Dictionary = list[i]
		# funding_source 仍按 V-PD-09 逐项判（valid_range / values 与 default ∈ 取值域），
		# 只是判完不落槽 —— 不判等于把命令层的 FUNDING_SOURCE_N 判界建在没人核过的内容上。
		var is_funding: bool = String(e.get("key", "")) == FUNDING_SOURCE_KEY
		if not is_funding:
			j += 1
		var store: bool = (not is_funding) and j < JWIds.POLICY_PARAM_STRIDE
		# 枚举型（§5.12 示例的 funding_source）以 `values` 的下标为取值域。内容包里两种写法都有：
		# 有的枚举项额外写了 `valid_range` [0, n−1]，有的没有。规则因此是：
		# **有 valid_range 就以它为准**（此时 default 是下标整数），没有才用 values 的下标映射；
		# 两者同时存在时必须一致，不一致说明有一处是手改的。
		var values: Array = []
		if e.has("values"):
			values = _get_array(e, "values", jw, JWResult.Reject.PARAM_RANGE)
			if values.is_empty():
				_fail(JWResult.Reject.PARAM_RANGE, jw + "/values", 0, 1)
				continue
		var lo: int = 0
		var hi: int = 0
		if e.has("valid_range"):
			var vr: PackedInt64Array = _get_int_array(e, "valid_range", 2, jw,
					JWResult.Reject.PARAM_RANGE)
			lo = vr[0]
			hi = vr[1]
			if not values.is_empty() and (vr[0] != 0 or vr[1] != values.size() - 1):
				_fail(JWResult.Reject.PARAM_RANGE, jw + "/valid_range", vr[1],
						values.size() - 1)
		elif not values.is_empty():
			hi = values.size() - 1
		else:
			# V-PD-09：既没有 valid_range 也没有 values，取值域无从谈起。
			_fail(JWResult.Reject.PARAM_RANGE, jw + "/valid_range", 0, 0)
			continue
		var dflt: int = _read_param_default(e, values, jw)
		if not store:
			continue
		var slot: int = JWIds.idx_policy_param(p, j)
		pmin[slot] = lo
		pmax[slot] = hi
		pdef[slot] = dflt


## R-PSLOT-01：按键与类型解析玩家参数的槽位（与 _read_policy_params 同一套 j 计数：funding_source 不占槽）。
func _read_policy_slots(doc: Dictionary, p: int, kind_p: int, defs: JWPolicyDef) -> void:
	var list: Variant = doc.get("player_params", [])
	if typeof(list) != TYPE_ARRAY:
		return
	var key_slot: Dictionary = {}
	var j: int = -1
	for e: Variant in list:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var key: String = String(d.get("key", ""))
		if key == FUNDING_SOURCE_KEY:
			continue
		j += 1
		if j >= JWIds.POLICY_PARAM_STRIDE:
			break
		key_slot[key] = j
		if String(d.get("type", "")) == "mask" or key == "region_mask":
			defs.mask_slot[p] = j
	if key_slot.has("cap_per_cell_per_q_uu"):
		defs.cap_slot[p] = int(key_slot["cap_per_cell_per_q_uu"])
	if key_slot.has("min_investment_ratio_ppm"):
		defs.min_ratio_slot[p] = int(key_slot["min_investment_ratio_ppm"])
	if key_slot.has("seats_per_q_units"):
		defs.qty_slot[p] = int(key_slot["seats_per_q_units"])
	if key_slot.has("track"):
		defs.track_slot[p] = int(key_slot["track"])
	# R-P11-01 / R-P12-01：
	if key_slot.has("staffing_scale_ppm"):
		defs.staff_slot[p] = int(key_slot["staffing_scale_ppm"])
	if key_slot.has("system_scale_ppm"):
		defs.system_slot[p] = int(key_slot["system_scale_ppm"])
	if key_slot.has("disclosure_threshold_ppm"):
		defs.disclosure_slot[p] = int(key_slot["disclosure_threshold_ppm"])
	if key_slot.has("audit_sample_ppm"):
		defs.audit_slot[p] = int(key_slot["audit_sample_ppm"])
	if key_slot.has("appeal_scope_ppm"):
		defs.appeal_slot[p] = int(key_slot["appeal_scope_ppm"])
	# R-P10-01：
	if key_slot.has("grant_per_q_uu"):
		defs.grant_slot[p] = int(key_slot["grant_per_q_uu"])
	var eff: Variant = doc.get("effect", {})
	var rate_ref: String = ""
	if typeof(eff) == TYPE_DICTIONARY:
		rate_ref = String((eff as Dictionary).get("rate_ref", ""))
	if rate_ref.begins_with("player_params:"):
		var rk: String = rate_ref.substr("player_params:".length())
		if key_slot.has(rk):
			defs.rate_slot[p] = int(key_slot[rk])
		else:
			_fail(JWResult.Load.EFFECT_TARGET, "policy_P" + _pad2(p + 1) + ".json#/effect/rate_ref", p, 0)
	elif kind_p == JWPolicyDef.POLICY_KIND_RATE or kind_p == JWPolicyDef.POLICY_KIND_TRANSFER:
		defs.rate_slot[p] = JWPolicyDef.PARAM_SLOT_PRIMARY


## `default` 的两种写法：下标整数，或枚举项的字符串值（此时按 `values` 的下标映射）。
## SoA 里只有整数，因此字符串一律映射成下标；映射不到即 V-PD-09 失败。
func _read_param_default(e: Dictionary, values: Array, jw: String) -> int:
	if not e.has("default"):
		_fail(JWResult.Reject.PARAM_RANGE, jw + "/default", 0, 0)
		return 0
	var d: Variant = e["default"]
	if _is_num(d):
		return _num(d)
	if values.is_empty():
		_fail(JWResult.Reject.PARAM_RANGE, jw + "/default", typeof(d), TYPE_INT)
		return 0
	var s: String = String(d)
	for k: int in values.size():
		if String(values[k]) == s:
			return k
	_fail(JWResult.Reject.PARAM_RANGE, jw + "/default", 0, values.size())
	return 0


## V-PD-08：mechanism_ids 非空，且每个 ID 都在 MechanismRegistry 里。
func _read_mechanisms(doc: Dictionary, w: String) -> int:
	var mask: int = 0
	var list: Array = _get_array(doc, "mechanism_ids", w, JWResult.Load.MECH_UNKNOWN)
	if list.is_empty():
		_fail(JWResult.Load.MECH_UNKNOWN, w + "/mechanism_ids", 0, 0)
		return 0
	for i: int in list.size():
		var idx: int = JWPolicyDef.mechanism_index(String(list[i]))
		if idx < 0:
			# 政策只能引用已实现的机制并给参数，不能自带逻辑（计划书 §09 的「伪深度」防线）。
			_fail(JWResult.Load.MECH_UNKNOWN, w + "/mechanism_ids/" + str(i), i, 0)
			continue
		mask = mask | (1 << idx)
	return mask


## V-PD-06 / V-PD-07：failure_paths 与 acceptance_tests 非空，且每个 test_id 真实存在。
##
## 「真实存在」这一半**做不到**：SimCore 里没有测试注册表，`tests/` 下是 GDScript 文件而不是
## 可查询的 ID 表。这里只判可判定的部分（非空、字段齐全、ID 形态），
## 并把「测试注册表」登记为接口变更请求 —— 不做「大概齐」的替代判断，也不假装已经查过。
func _read_policy_tests(doc: Dictionary, w: String) -> void:
	var fp: Array = _get_array(doc, "failure_paths", w, JWResult.Load.POLICY_TEST_MISSING)
	if fp.is_empty():
		_fail(JWResult.Load.POLICY_TEST_MISSING, w + "/failure_paths", 0, 0)
	for i: int in fp.size():
		var iw: String = w + "/failure_paths/" + str(i)
		if typeof(fp[i]) != TYPE_DICTIONARY:
			_fail(JWResult.Load.SCHEMA_HEADER, iw, typeof(fp[i]), TYPE_DICTIONARY)
			continue
		var e: Dictionary = fp[i]
		if String(_get_str(e, "code", iw, JWResult.Load.POLICY_TEST_MISSING)).is_empty():
			_fail(JWResult.Load.POLICY_TEST_MISSING, iw + "/code", 0, 0)
		if not _is_test_id(_get_str(e, "test_id", iw, JWResult.Load.POLICY_TEST_MISSING)):
			_fail(JWResult.Load.POLICY_TEST_MISSING, iw + "/test_id", 0, 0)
	var at: Array = _get_array(doc, "acceptance_tests", w, JWResult.Load.POLICY_TEST_MISSING)
	if at.is_empty():
		_fail(JWResult.Load.POLICY_TEST_MISSING, w + "/acceptance_tests", 0, 0)
	for i: int in at.size():
		if not _is_test_id(String(at[i])):
			_fail(JWResult.Load.POLICY_TEST_MISSING, w + "/acceptance_tests/" + str(i), i, 0)


func _is_test_id(s: String) -> bool:
	return s.begins_with("T-") and s.length() > 2


## 反馈链（计划书 §03 范围契约：「12 项政策；每项至少 1 条完整反馈链」）。
##
## 这条要求来自文档优先级第 1 位的计划书，而 docs/11 §5.12 的键集合里没有 `effect_chain`，
## 所以缺字段的一侧是 §5.12 —— 键留在顶层，不降级成注释键（注释键按 §5.15.1 永远不是事实来源，
## 「至少 1 条完整反馈链」就成了没人能核验的口号）。
##
## **只判可判定的部分**：链是数组、环数 ≥ 4、每一环是对象。
## 环内的字段形状**故意不判**：12 个政策文件里它现在有五套互不相同的写法
## （settlement_step / sim_step / link / ring；from 与 from_state；rule 与 rule_zh），
## 而契约里根本没有这个键的形状定义 —— 此处凭实现口味钉死任何一套，都是拿被检查方当依据。
## 形状统一须先在 docs/11 §5.12 立契约，已在 open_questions 上报。
func _read_policy_chain(doc: Dictionary, w: String) -> void:
	var chain: Array = _get_array(doc, "effect_chain", w, JWResult.Load.POLICY_FIELDS)
	if chain.size() < CHAIN_MIN_LINKS:
		_fail(JWResult.Load.POLICY_FIELDS, w + "/effect_chain", chain.size(), CHAIN_MIN_LINKS)
	for i: int in chain.size():
		if typeof(chain[i]) != TYPE_DICTIONARY:
			_fail(JWResult.Load.POLICY_FIELDS, w + "/effect_chain/" + str(i),
					typeof(chain[i]), TYPE_DICTIONARY)


## 反馈链的环数下界（计划书 §10 的「命令 → … → 部门响应」六环，验收口径取 4 环为硬下界）。
const CHAIN_MIN_LINKS: int = 4

const EVENT_ALLOWED: PackedStringArray = [
	"schema_kind", "schema_version", "event_id", "label_zh", "kind", "trigger", "effects",
	"evidence_refs", "report_template_id",
]


func _validate_events() -> void:
	for e: int in JWUnits.EVENT_N:
		var rel: String = "events/event_E" + _pad2(e + 1) + ".json"
		var idx: int = _doc_index(rel)
		if idx < 0:
			# V-EV-01：12 个事件文件齐全。
			_fail(JWResult.Load.EVENT_COUNT, rel + "#missing", e, 0)
			continue
		var w: String = rel + "#"
		var doc: Dictionary = _docs[idx]
		_check_keys(doc, EVENT_ALLOWED, w)
		# V-EV-06：首版不存在 ledger_effects 字段；出现即失败（事件不得有账本效应）。
		if doc.has("ledger_effects"):
			_fail(JWResult.Load.EVENT_LEDGER, w + "/ledger_effects", 0, 0)
		if _event_index(_get_str(doc, "event_id", w, JWResult.Load.EVENT_COUNT)) != e:
			_fail(JWResult.Load.EVENT_COUNT, w + "/event_id", e, 0)

		var tw: String = w + "/trigger"
		var trig: Dictionary = _get_dict(doc, "trigger", w, JWResult.Load.EVENT_FIELD)
		_check_keys(trig, PackedStringArray(["all_of", "probability_ppm", "rng_stream",
				"cooldown_q", "max_occurrences"]), tw)
		# V-EV-04：不得借用 rng.shock —— 多写一个事件模板不能改变经济抽样（INV-009）。
		if _get_str(trig, "rng_stream", tw, JWResult.Load.EVENT_STREAM) != "rng.event":
			_fail(JWResult.Load.EVENT_STREAM, tw + "/rng_stream", 0, 0)
		# V-EV-07：三个字段的界。
		var prob: int = _get_int(trig, "probability_ppm", tw, JWResult.Load.EVENT_FIELD)
		_ppm_range(prob, tw + "/probability_ppm")
		var cooldown: int = _get_int(trig, "cooldown_q", tw, JWResult.Load.EVENT_FIELD)
		if cooldown < 0:
			_fail(JWResult.Load.EVENT_FIELD, tw + "/cooldown_q", cooldown, 0)
		var max_occ: int = _get_int(trig, "max_occurrences", tw, JWResult.Load.EVENT_FIELD)
		if max_occ < 1:
			_fail(JWResult.Load.EVENT_FIELD, tw + "/max_occurrences", max_occ, 1)

		var conds: Array = _get_array(trig, "all_of", tw, JWResult.Load.EVENT_FIELD)
		if conds.is_empty():
			_fail(JWResult.Load.EVENT_FIELD, tw + "/all_of", 0, 1)
		for i: int in conds.size():
			_validate_event_condition(conds[i], tw + "/all_of/" + str(i))

		var effects: Array = _get_array(doc, "effects", w, JWResult.Load.EVENT_TARGET)
		if effects.is_empty():
			_fail(JWResult.Load.EVENT_TARGET, w + "/effects", 0, 1)
		for i: int in effects.size():
			_validate_event_effect(effects[i], w + "/effects/" + str(i))

		# V-EV-08：证据引用非空（计划书 §13「每条变化附带实体 ID」）。
		var ev: Array = _get_array(doc, "evidence_refs", w, JWResult.Load.EVENT_EVIDENCE)
		if ev.is_empty():
			_fail(JWResult.Load.EVENT_EVIDENCE, w + "/evidence_refs", 0, 1)
		for i: int in ev.size():
			if not _is_metric_ref(String(ev[i])):
				_fail(JWResult.Load.EVENT_EVIDENCE, w + "/evidence_refs/" + str(i), i, 0)


## V-EV-02 / V-EV-03：metric 必须是真实存在的稳定 ID，op 只有六种比较。
##
## 「真实存在」这一半目前只能判到命名空间：**metric 的整数码表还不存在**
## （`JWSimState.read_metric` 自己也登记着同一条待决项），没有可查询的稳定 ID 全集。
## 因此这里判「是不是一个 docs/10 命名空间下的合法 ID」，并把码表登记为接口变更请求；
## 码表落地之前不猜、也不放行一个看起来像的字符串。
func _validate_event_condition(node: Variant, cw: String) -> void:
	if typeof(node) != TYPE_DICTIONARY:
		_fail(JWResult.Load.EVENT_FIELD, cw, typeof(node), TYPE_DICTIONARY)
		return
	var c: Dictionary = node
	_check_keys(c, PackedStringArray(["metric", "scope", "op", "value"]), cw)
	if not _is_metric_ref(_get_str(c, "metric", cw, JWResult.Load.METRIC_UNKNOWN)):
		_fail(JWResult.Load.METRIC_UNKNOWN, cw + "/metric", 0, 0)
	if _name_index(EVENT_OPS, _get_str(c, "op", cw, JWResult.Load.EVENT_OP)) < 0:
		_fail(JWResult.Load.EVENT_OP, cw + "/op", 0, 0)
	if not c.has("value"):
		_fail(JWResult.Load.EVENT_FIELD, cw + "/value", 0, 0)
	elif not _is_num(c["value"]):
		# 没有表达式求值器：右值只能是整数字面量。
		_fail(JWResult.Load.EVENT_FIELD, cw + "/value", typeof(c["value"]), TYPE_INT)
	if c.has("scope") and _resolve_scope(String(c["scope"])) < 0:
		_fail(JWResult.Load.ID_FORMAT, cw + "/scope", 0, 0)


## V-EV-05：effects[].target ∈ 事件可写白名单，且只能是 delta_ppm。
func _validate_event_effect(node: Variant, ew: String) -> void:
	if typeof(node) != TYPE_DICTIONARY:
		_fail(JWResult.Load.EVENT_TARGET, ew, typeof(node), TYPE_DICTIONARY)
		return
	var e: Dictionary = node
	_check_keys(e, PackedStringArray(["target", "scope", "delta_ppm"]), ew)
	if _name_index(EVENT_TARGETS, _get_str(e, "target", ew, JWResult.Load.EVENT_TARGET)) < 0:
		# 事件不得直接写现金、库存、产能、人口、GDP（INV-130）。
		_fail(JWResult.Load.EVENT_TARGET, ew + "/target", 0, 0)
	if not e.has("delta_ppm"):
		_fail(JWResult.Load.EVENT_TARGET, ew + "/delta_ppm", 0, 0)
	elif not _is_num(e["delta_ppm"]):
		_fail(JWResult.Load.EVENT_TARGET, ew + "/delta_ppm", typeof(e["delta_ppm"]), TYPE_INT)
	if e.has("scope") and _resolve_scope(String(e["scope"])) < 0:
		_fail(JWResult.Load.ID_FORMAT, ew + "/scope", 0, 0)


## 作用域字符串 → 下标（只用于加载期判「引用是否悬空」，不产出运行期数据）。
## 返回 −1 表示解析不出来。
func _resolve_scope(s: String) -> int:
	if s == "national":
		return 0
	var candidates: PackedInt64Array = PackedInt64Array([
		_region_index(s), _sector_index(s), _cell_index(s), _pubserv_index(s),
		_group_index(s), _bloc_index(s), _policy_index(s),
	])
	for i: int in candidates.size():
		if candidates[i] >= 0:
			return candidates[i]
	# `bloc.<name>.policy.PNN` 形态（立场是二维的，作用域要同时给出两个下标）。
	var cut: int = s.find(".policy.")
	if cut > 0:
		var b: int = _bloc_index(s.substr(0, cut))
		var p: int = _policy_index(s.substr(cut + 1))
		if b >= 0 and p >= 0:
			return JWIds.idx_stance(b, p)
	return -1


func _is_metric_ref(s: String) -> bool:
	if s.is_empty():
		return false
	for i: int in METRIC_PREFIXES.size():
		if s.begins_with(METRIC_PREFIXES[i]):
			return true
	return false


const SHOCK_ALLOWED: PackedStringArray = [
	"schema_kind", "schema_version", "shock_id", "label_zh", "channel", "targets",
	"target_weights_ppm", "arrival", "magnitude_ppm", "duration_q", "onset_profile",
	"decay_profile", "rng_stream", "log_fields",
]


func _validate_shocks(st: JWSimState) -> void:
	# JWShocks.allocate() 只分配了 state.* 五张表；内容表（通道、权重、到达过程、幅度、时长、
	# 形态）没有被 allocate 覆盖，也不在它的 STATE_ARRAY_IDS 里 —— 这里一次性定长化后整体赋值。
	# 已登记接口变更请求：这几张内容表应当由 JWShocks.allocate() 自己负责。
	var channel: PackedInt64Array = _zeros(JWUnits.SHOCK_N)
	var weights: PackedInt64Array = _zeros(JWMath.mul(JWUnits.SHOCK_N, JWUnits.S))
	var hazard: PackedInt64Array = _zeros(JWUnits.SHOCK_N)
	var earliest: PackedInt64Array = _zeros(JWUnits.SHOCK_N)
	var min_gap: PackedInt64Array = _zeros(JWUnits.SHOCK_N)
	var max_active: PackedInt64Array = _zeros(JWUnits.SHOCK_N)
	var mag_min: PackedInt64Array = _zeros(JWUnits.SHOCK_N)
	var mag_max: PackedInt64Array = _zeros(JWUnits.SHOCK_N)
	var dur_min: PackedInt64Array = _zeros(JWUnits.SHOCK_N)
	var dur_max: PackedInt64Array = _zeros(JWUnits.SHOCK_N)
	var onset: PackedInt64Array = _zeros(JWUnits.SHOCK_N)
	var decay: PackedInt64Array = _zeros(JWUnits.SHOCK_N)
	var channel_seen: PackedInt64Array = _zeros(SHOCK_CHANNELS.size())

	for k: int in JWUnits.SHOCK_N:
		var rel: String = "shocks/shock_S" + _pad2(k + 1) + ".json"
		var idx: int = _doc_index(rel)
		if idx < 0:
			# V-SH-01：3 个冲击文件齐全。
			_fail(JWResult.Load.SHOCK_COUNT, rel + "#missing", k, 0)
			continue
		var w: String = rel + "#"
		var doc: Dictionary = _docs[idx]
		_check_keys(doc, SHOCK_ALLOWED, w)
		if _shock_index(_get_str(doc, "shock_id", w, JWResult.Load.SHOCK_COUNT)) != k:
			_fail(JWResult.Load.SHOCK_COUNT, w + "/shock_id", k, 0)

		channel[k] = _name_index(SHOCK_CHANNELS, _get_str(doc, "channel", w,
				JWResult.Load.SHOCK_SCOPE))
		if channel[k] < 0:
			# V-SH-04：冲击只能写 state.world.* 白名单字段，通道就是那张白名单的入口。
			_fail(JWResult.Load.SHOCK_SCOPE, w + "/channel", 0, 0)
			channel[k] = 0
		elif channel_seen[channel[k]] != 0:
			_fail(JWResult.Load.SHOCK_COUNT, w + "/channel#duplicate", channel[k], 0)
		else:
			channel_seen[channel[k]] = 1

		# V-SH-02：不得借用 rng.event。
		if _get_str(doc, "rng_stream", w, JWResult.Load.SHOCK_STREAM) != "rng.shock":
			_fail(JWResult.Load.SHOCK_STREAM, w + "/rng_stream", 0, 0)

		var targets: Array = _get_array(doc, "targets", w, JWResult.Load.SHOCK_WEIGHTS)
		if targets.size() != JWUnits.S:
			_fail(JWResult.Load.SHOCK_WEIGHTS, w + "/targets", targets.size(), JWUnits.S)
		for i: int in targets.size():
			if _sector_index(String(targets[i])) != i:
				_fail(JWResult.Load.ID_FORMAT, w + "/targets/" + str(i), i, 0)
		var tw: PackedInt64Array = _get_int_array(doc, "target_weights_ppm", JWUnits.S, w,
				JWResult.Load.SHOCK_WEIGHTS)
		var wsum: int = 0
		for i: int in JWUnits.S:
			_ppm_range(tw[i], w + "/target_weights_ppm/" + str(i))
			weights[JWMath.mul(k, JWUnits.S) + i] = tw[i]
			wsum += tw[i]
		# V-SH-03：Σ == 1e6。
		if wsum != JWUnits.PPM:
			_fail(JWResult.Load.SHOCK_WEIGHTS, w + "/target_weights_ppm", wsum, JWUnits.PPM)

		var aw: String = w + "/arrival"
		var arrival: Dictionary = _get_dict(doc, "arrival", w, JWResult.Load.SHOCK_RANGE)
		_check_keys(arrival, PackedStringArray(["hazard_ppm_per_q", "earliest_q", "min_gap_q",
				"max_active"]), aw)
		hazard[k] = _get_int(arrival, "hazard_ppm_per_q", aw, JWResult.Load.SHOCK_RANGE)
		_ppm_range(hazard[k], aw + "/hazard_ppm_per_q")
		earliest[k] = _get_int(arrival, "earliest_q", aw, JWResult.Load.SHOCK_RANGE)
		min_gap[k] = _get_int(arrival, "min_gap_q", aw, JWResult.Load.SHOCK_RANGE)
		max_active[k] = _get_int(arrival, "max_active", aw, JWResult.Load.SHOCK_RANGE)
		if earliest[k] < 0 or min_gap[k] < 0 or max_active[k] < 1:
			_fail(JWResult.Load.SHOCK_RANGE, aw, earliest[k], max_active[k])

		var mw: String = w + "/magnitude_ppm"
		var mag: Dictionary = _get_dict(doc, "magnitude_ppm", w, JWResult.Load.SHOCK_RANGE)
		_check_keys(mag, PackedStringArray(["min", "max"]), mw)
		mag_min[k] = _get_int(mag, "min", mw, JWResult.Load.SHOCK_RANGE)
		mag_max[k] = _get_int(mag, "max", mw, JWResult.Load.SHOCK_RANGE)
		var dw: String = w + "/duration_q"
		var dur: Dictionary = _get_dict(doc, "duration_q", w, JWResult.Load.SHOCK_RANGE)
		_check_keys(dur, PackedStringArray(["min", "max"]), dw)
		dur_min[k] = _get_int(dur, "min", dw, JWResult.Load.SHOCK_RANGE)
		dur_max[k] = _get_int(dur, "max", dw, JWResult.Load.SHOCK_RANGE)
		# V-SH-06：幅度区间不倒挂；时长下界 ≥ 1。
		if mag_min[k] > mag_max[k]:
			_fail(JWResult.Load.SHOCK_RANGE, mw, mag_min[k], mag_max[k])
		if dur_min[k] < 1 or dur_max[k] < dur_min[k]:
			_fail(JWResult.Load.SHOCK_RANGE, dw, dur_min[k], dur_max[k])

		onset[k] = _name_index(ONSET_PROFILES, _get_str(doc, "onset_profile", w,
				JWResult.Load.SHOCK_RANGE))
		decay[k] = _name_index(DECAY_PROFILES, _get_str(doc, "decay_profile", w,
				JWResult.Load.SHOCK_RANGE))
		if onset[k] < 0:
			_fail(JWResult.Load.SHOCK_RANGE, w + "/onset_profile", 0, 0)
			onset[k] = 0
		if decay[k] < 0:
			_fail(JWResult.Load.SHOCK_RANGE, w + "/decay_profile", 0, 0)
			decay[k] = 0

		# V-SH-05：抽样日志必须可复核（计划书 §07「每次抽样写入日志」）。
		var logs: Array = _get_array(doc, "log_fields", w, JWResult.Load.SHOCK_LOG)
		for i: int in SHOCK_LOG_REQUIRED.size():
			var found: bool = false
			for j: int in logs.size():
				if String(logs[j]) == SHOCK_LOG_REQUIRED[i]:
					found = true
					break
			if not found:
				_fail(JWResult.Load.SHOCK_LOG, w + "/log_fields#" + SHOCK_LOG_REQUIRED[i], i, 0)

	st.shocks.channel = channel
	st.shocks.target_weights_ppm = weights
	st.shocks.hazard_ppm = hazard
	st.shocks.earliest_q = earliest
	st.shocks.min_gap_q = min_gap
	st.shocks.max_active = max_active
	st.shocks.mag_min = mag_min
	st.shocks.mag_max = mag_max
	st.shocks.dur_min = dur_min
	st.shocks.dur_max = dur_max
	st.shocks.onset_profile = onset
	st.shocks.decay_profile = decay

## 跨文件引用解析与冗余交叉校验（docs/11 §7 的第七段）。
## 这些检查**故意冗余**：同一个数在两份文件里各写一遍，对不上就说明有一份是手改的。
func _resolve_cross_refs(st: JWSimState) -> void:
	var w: String = _scenario_dir + "#cross"
	if _group_population.size() != JWUnits.GROUP:
		return

	# V-REG-05 / INV-141：地区人口 == 群组按地区求和。
	var by_region: PackedInt64Array = _zeros(JWUnits.R)
	var occupied: PackedInt64Array = _zeros(JWUnits.R)
	for g: int in JWUnits.GROUP:
		var r: int = JWIds.REGION_OF_GROUP[g]
		by_region[r] += _group_population[g]
		occupied[r] += _group_housing[g]
	for r: int in JWUnits.R:
		if _region_population_decl.size() == JWUnits.R \
				and _region_population_decl[r] != by_region[r]:
			_fail(JWResult.Load.POP_REGION, w + "/population/" + _region_names[r],
					_region_population_decl[r], by_region[r])
		# V-POP-06：逐地区 Σ 占用 ≤ 住房存量。
		var stock: int = st.capital.housing_stock_of(r)
		if occupied[r] > stock:
			_fail(JWResult.Load.HOUSE_OVER, w + "/housing/" + _region_names[r], occupied[r],
					stock)

	# V-POP-08 / INV-151：群组侧就业按 (地区, 部门/pubserv, 技能) 汇总 == 单元侧在岗人数。
	if _cell_employment.size() == JWUnits.EMP_N \
			and _pubserv_employment.size() == JWUnits.PUBSERV_EMP_N:
		for r: int in JWUnits.R:
			for k: int in JWUnits.K:
				for s: int in JWUnits.S:
					var gside: int = 0
					for a: int in JWUnits.A:
						gside += _group_employed[JWIds.idx_group_emp(
								JWIds.idx_group(r, a, k), s)]
					var cside: int = _cell_employment[JWIds.idx_emp(JWIds.idx_cell(r, s), k)]
					if gside != cside:
						_fail(JWResult.Load.EMPLOY_MISMATCH,
								w + "/employment/" + _region_names[r] + "." + SECTOR_NAMES[s]
										+ "." + SKILL_NAMES[k], gside, cside)
				var gpub: int = 0
				for a2: int in JWUnits.A:
					gpub += _group_employed[JWIds.idx_group_emp(JWIds.idx_group(r, a2, k),
							JWUnits.S)]
				var cpub: int = _pubserv_employment[JWIds.idx_pubserv_emp(r, k)]
				if gpub != cpub:
					_fail(JWResult.Load.EMPLOY_MISMATCH,
							w + "/employment/pubserv." + _region_names[r] + "." + SKILL_NAMES[k],
							gpub, cpub)

	# V-FIN-09 / INV-024：居民存款 == 投资池现金 + 投资池持有的债券本金。
	var claim: int = _invpool_cash_uu + _invpool_bondhold_uu
	if _group_deposit_total != claim:
		_fail(JWResult.Load.DEPOSIT_MISMATCH, w + "/deposits", _group_deposit_total, claim)

# ── 剧本硬约束 ─────────────────────────────────────────────────────────────

## 剧本硬约束（容差一律 0，唯一例外是失业率的 500 ppm 带）。
## 步骤：LOAD
## 前置：各 Init 文件已解析
## 后置：不改状态
## 不变量：INV-141（Σ 人口 == 24 000 000，四地区 9/7/5/3 百万）、INV-142、INV-143（反算失业率
##          ∈ [79 500, 80 500] 且 schema 中不存在失业率输入字段）、INV-144（Σ 债券本金 == 50 000 000）、
##          INV-145（gov.cash == 2 000 000）、INV-146、INV-147、INV-148、INV-149、INV-150、INV-151
## 失败：对应的 Load.* 码
##
## 逐项的判定写在各 `_validate_*` 里（那里才有文件位置可报）；本函数做两件事：
## ① 把「只有汇总之后才能判」的锁定值再算一遍（人口总量与分地区）；
## ② 跑 `assertions.json` 的冗余断言 —— 它是内容作者独立写下的第二份期望值，
##    与 ① 的判定互为交叉验证（对不上说明有一侧是手改的）。
func check_scenario_assertions(st: JWSimState) -> JWResult:
	var before: int = errors.size()
	var w: String = _scenario_dir + "#assertions"

	# INV-141：Σ 人口 == 24 000 000，四地区 9/7/5/3 百万。
	if _plan_locks and _group_population.size() == JWUnits.GROUP:
		var total: int = JWMath.sum(_group_population)
		if total != LOCK_POPULATION_PERSONS:
			_fail(JWResult.Load.POP_TOTAL, w + "/total_population", total,
					LOCK_POPULATION_PERSONS)
		var by_region: PackedInt64Array = _zeros(JWUnits.R)
		for g: int in JWUnits.GROUP:
			by_region[JWIds.REGION_OF_GROUP[g]] += _group_population[g]
		for r: int in JWUnits.R:
			if by_region[r] != LOCK_REGION_POPULATION[r]:
				_fail(JWResult.Load.POP_REGION, w + "/region_population/" + _region_names[r],
						by_region[r], LOCK_REGION_POPULATION[r])

	# INV-142：群组集合齐全（36 条）——由 JWIds 的登记数兜底再看一次。
	if _ids != null and _ids.count_of(JWIds.IdKind.GROUP) != JWUnits.GROUP:
		_fail(JWResult.Load.GROUP_SET, w + "/group_count",
				_ids.count_of(JWIds.IdKind.GROUP), JWUnits.GROUP)

	_run_assertion_file(st)

	if errors.size() == before:
		return JWResult.make_ok()
	return errors[before]


## R-RESEARCH-01：科技卡校验与装载。下标 == 文件名升序；前置只能指向更靠前的科技（保证无环）。
## 解锁的建筑类型与生产方式在 M2-2 的建筑表落地后解析，本轮只校验它们是字符串并登记为 0 掩码。
const TECH_ALLOWED: PackedStringArray = [
	"schema_kind", "schema_version", "tech_id", "label_zh", "desc_zh", "era_hint",
	"research_cost", "prereqs", "unlocks", "requires", "placeholder",
]
const TECH_UNLOCK_KEYS: PackedStringArray = ["building_types", "methods"]


func _validate_technologies(st: JWSimState) -> void:
	var n: int = _tech_files.size()
	if n == 0:
		return
	if n > JWResearch.CAP0:
		_fail(JWResult.Load.SCHEMA_HEADER, TECH_DIR + "#count", n, JWResearch.CAP0)
		return
	var cost: PackedInt64Array = _zeros(JWResearch.CAP0)
	var era: PackedInt64Array = _zeros(JWResearch.CAP0)
	var prereq: PackedInt64Array = _zeros(JWResearch.CAP0)
	_tech_index = {}
	for t: int in n:
		var rel: String = _tech_files[t]
		var idx: int = _doc_index(rel)
		if idx < 0:
			continue
		var doc: Dictionary = _docs[idx]
		var w: String = rel + "#"
		_check_keys(doc, TECH_ALLOWED, w)
		var tid: String = _get_str(doc, "tech_id", w, JWResult.Load.SCHEMA_HEADER)
		if not tid.begins_with("tech."):
			_fail(JWResult.Load.ID_FORMAT, w + "/tech_id", 0, 0)
		if _tech_index.has(tid):
			_fail(JWResult.Load.DUP_ID, w + "/tech_id", t, int(_tech_index[tid]))
		_tech_index[tid] = t
		era[t] = _get_int(doc, "era_hint", w, JWResult.Load.SCHEMA_HEADER)
		cost[t] = _get_int(doc, "research_cost", w, JWResult.Load.SCHEMA_HEADER)
		if cost[t] <= 0:
			_fail(JWResult.Load.RANGE, w + "/research_cost", cost[t], 1)
		var pre: Array = _get_array(doc, "prereqs", w, JWResult.Load.SCHEMA_HEADER)
		var mask: int = 0
		for j: int in pre.size():
			var pid: String = String(pre[j])
			if not _tech_index.has(pid):
				# 前置必须指向更靠前的科技：既保证无环，也让「下标即拓扑序」成立。
				_fail(JWResult.Load.SCHEMA_HEADER, w + "/prereqs/" + str(j), t, -1)
				continue
			mask = mask | (1 << int(_tech_index[pid]))
		prereq[t] = mask
		var unl: Dictionary = _get_dict(doc, "unlocks", w, JWResult.Load.SCHEMA_HEADER)
		_check_keys(unl, TECH_UNLOCK_KEYS, w + "/unlocks")
		for k: int in TECH_UNLOCK_KEYS.size():
			var lst: Array = _get_array(unl, TECH_UNLOCK_KEYS[k], w + "/unlocks",
					JWResult.Load.SCHEMA_HEADER)
			for m: int in lst.size():
				if typeof(lst[m]) != TYPE_STRING:
					_fail(JWResult.Load.ID_FORMAT, w + "/unlocks/" + TECH_UNLOCK_KEYS[k], m, 0)
	_set_arr(st.research, 2, cost, TECH_DIR + "#cost")
	_set_arr(st.research, 3, era, TECH_DIR + "#era_hint")
	_set_arr(st.research, 4, prereq, TECH_DIR + "#prereq_mask")
	_set_scalar(st.research, 3, n, TECH_DIR + "#count")
	# 载入即刷新可研究状态（前置为空的科技一开始就可研究）。
	st.research.advance_research(0)


## 跑 `assertions.json`（§5.11）。`at == "load"` 的当场判；`q_end:<n>` 的只校验形态，
## 由季末的诊断层去判 —— 载入期判不了还没跑出来的量，硬判就是自欺。
func _run_assertion_file(st: JWSimState) -> void:
	var w: String = _scenario_dir + "/assertions.json#"
	var doc: Dictionary = _scenario_doc("assertions.json")
	if doc.is_empty():
		return
	_check_keys(doc, PackedStringArray(["schema_kind", "schema_version", "checks"]), w)
	var checks: Array = _get_array(doc, "checks", w, JWResult.Load.SCHEMA_HEADER)
	for i: int in checks.size():
		var cw: String = w + "/checks/" + str(i)
		if typeof(checks[i]) != TYPE_DICTIONARY:
			_fail(JWResult.Load.SCHEMA_HEADER, cw, typeof(checks[i]), TYPE_DICTIONARY)
			continue
		var c: Dictionary = checks[i]
		_check_keys(c, PackedStringArray(["id", "at", "expr", "expect", "tolerance"]), cw)
		var id: String = _get_str(c, "id", cw, JWResult.Load.SCHEMA_HEADER)
		var at: String = _get_str(c, "at", cw, JWResult.Load.SCHEMA_HEADER)
		var tol: int = _get_int(c, "tolerance", cw, JWResult.Load.ASSERT_TOLERANCE)

		# §5.11：tolerance 只允许为 0，唯一例外是失业率的 500 ppm。
		# 「出现第二个非零容差」本身就是一个校验错误 —— 放宽必须改协议，不能偷偷改数据。
		if tol != 0:
			if id != "assert.unemployment" or tol != UNEMPLOYMENT_TOLERANCE_PPM:
				_fail(JWResult.Load.ASSERT_TOLERANCE, cw + "/tolerance", tol, 0)
				tol = 0
		if at != "load" and not at.begins_with("q_end:"):
			_fail(JWResult.Load.SCHEMA_HEADER, cw + "/at", 0, 0)
			continue
		if at != "load":
			continue

		var expr: String = _get_str(c, "expr", cw, JWResult.Load.SCHEMA_HEADER)
		var actual: PackedInt64Array = PackedInt64Array()
		if not _eval_expr(expr, st, actual):
			# 断言引用了本加载器不认识的量：宁可报「未知字段」也不放行一条没跑过的断言。
			_fail(JWResult.Load.UNKNOWN_FIELD, cw + "/expr", 0, 0)
			continue
		_compare_expect(c, actual, tol, st, cw)


## 把 `expect`（整数 / 整数数组 / 另一条表达式）与实算值逐位比对。
func _compare_expect(c: Dictionary, actual: PackedInt64Array, tol: int, st: JWSimState,
		cw: String) -> void:
	if not c.has("expect"):
		_fail(JWResult.Load.SCHEMA_HEADER, cw + "/expect", 0, 0)
		return
	var want: PackedInt64Array = PackedInt64Array()
	var e: Variant = c["expect"]
	var t: int = typeof(e)
	if _is_num(e):
		want.append(_num(e))
	elif t == TYPE_ARRAY:
		var arr: Array = e
		for i: int in arr.size():
			if not _is_num(arr[i]):
				_fail(JWResult.Load.SCHEMA_HEADER, cw + "/expect/" + str(i), typeof(arr[i]),
						TYPE_INT)
				return
			want.append(_num(arr[i]))
	elif t == TYPE_STRING or t == TYPE_STRING_NAME:
		if not _eval_expr(String(e), st, want):
			_fail(JWResult.Load.UNKNOWN_FIELD, cw + "/expect", 0, 0)
			return
	else:
		_fail(JWResult.Load.SCHEMA_HEADER, cw + "/expect", t, TYPE_INT)
		return

	if want.size() != actual.size():
		_fail(JWResult.Load.SCHEMA_HEADER, cw + "/expect#shape", actual.size(), want.size())
		return
	for i: int in want.size():
		if JWMath.absi(actual[i] - want[i]) > tol:
			_fail(JWResult.Load.SCHEMA_HEADER, cw + "/expect/" + str(i), actual[i], want[i])


## §5.11 的极小只读表达式语言。**闭集合**：认识的表达式逐条列在这里，
## 不认识的一律返回 false（由调用方报 E_UNKNOWN_FIELD），绝不「大致猜一个量」。
func _eval_expr(expr: String, st: JWSimState, out: PackedInt64Array) -> bool:
	out.resize(0)
	if expr == "sum(group.*.population_persons)":
		out.append(JWMath.sum(_group_population))
		return true
	if expr == "sum_by_region(group.*.population_persons)":
		var by_region: PackedInt64Array = _zeros(JWUnits.R)
		for g: int in JWUnits.GROUP:
			by_region[JWIds.REGION_OF_GROUP[g]] += _group_population[g]
		out.append_array(by_region)
		return true
	if expr == "derived.labor.unemployment_ppm":
		out.append(_unemployment_ppm)
		return true
	if expr == "derived.gov.debt_uu":
		out.append(_opening_sum(JWIds.AGENT_GOV, JWIds.ACC_DEBT))
		return true
	if expr == "state.gov.cash_uu":
		out.append(_opening_sum(JWIds.AGENT_GOV, JWIds.ACC_CASH))
		return true
	if expr == "annual_plan.expenditure_incl_interest_uu - annual_plan.receipts_uu":
		out.append(_annual_deficit_uu)
		return true
	if expr == "annual_plan.expenditure_lines_uu.interest":
		out.append(_declared_interest_uu())
		return true
	if expr == "sum_q(0..3, bond_coupon_total_uu)":
		out.append(_bond_coupon_year_uu)
		return true
	if expr == "state.price.sector_uu_per_qs":
		out.append_array(st.pricing.state_array(0))
		return true
	if expr == "derived.living.consumption_index_ppm":
		out.append(_weighted_index(st.pop.state_array(6)))
		return true
	if expr == "derived.living.living_index_ppm":
		out.append(_weighted_index(st.politics.state_array(0)))
		return true
	if expr == "content.pop.base_service_access_ppm":
		out.append_array(_base_service_access_ppm)
		return true
	if expr == "sum(all_agents.cash_uu)":
		out.append(_opening_sum(-1, JWIds.ACC_CASH))
		return true
	if expr == "scenario.total_cash_uu":
		out.append(_total_cash_uu)
		return true
	return false


## 开账缓冲里某个（主体, 科目）的合计；agent == −1 表示全部主体。
func _opening_sum(agent: int, code: int) -> int:
	var acc: int = 0
	for i: int in _op_agent.size():
		if _op_code[i] != code:
			continue
		if agent >= 0 and _op_agent[i] != agent:
			continue
		acc += _op_amount[i]
	return acc


## 人口加权指数（分母为 Σ 人口）。
func _weighted_index(values: PackedInt64Array) -> int:
	if values.size() != JWUnits.GROUP or _group_population.size() != JWUnits.GROUP:
		return 0
	var pop_total: int = JWMath.sum(_group_population)
	if pop_total <= 0:
		return 0
	var acc: int = 0
	for g: int in JWUnits.GROUP:
		acc += JWMath.mul(_group_population[g], values[g])
	# rounding: floor, reason=与 V-POP-07 的加权口径逐字一致
	return JWMath.floor_div(acc, pop_total)


## 年度计划里登记的利息行（`assert.interest_in_spend` 要跟逐批次复算值比对）。
func _declared_interest_uu() -> int:
	var doc: Dictionary = _scenario_doc("government_init.json")
	if doc.is_empty() or not doc.has("annual_plan"):
		return 0
	var plan: Dictionary = doc["annual_plan"]
	if not plan.has("expenditure_lines_uu"):
		return 0
	var lines: Dictionary = plan["expenditure_lines_uu"]
	if not lines.has("interest") or not _is_num(lines["interest"]):
		return 0
	return _num(lines["interest"])

## 参数卡的九个必填字段（V-PC-01）。
const PARAM_CARD_REQUIRED: PackedStringArray = [
	"parameter_id", "value", "unit", "source_type", "source_ref", "reference_year",
	"definition", "valid_range", "confidence", "calibration_note",
]
const PARAM_SOURCE_TYPES: PackedStringArray = [
	"observed", "literature", "design_assumption", "derived",
]
const PARAM_CONFIDENCE: PackedStringArray = ["low", "medium", "high"]

## 6 条随机流的盐值（不进 params 数组，由 JWRngStreams 持有）。
const PARAM_RNG_SALT: String = "param.rng_salt"

## IOTable 的**集合级**参数卡（docs/11 §5.15「一个例外」）。
##
## 它不是一个运行期参数：IO 系数是内容数据，逐个不建卡，整表共用这一张卡，
## `value` 记该表规范化哈希的前缀，只为让「改了系数却忘了更新校准说明」当场暴露（V-PC-07）。
## 因此它**没有稠密下标**，也就不该按 `PARAM_COVERAGE` 去找槽位 ——
## 找不到槽位就报「缺一张卡」，是把契约明写的例外当成了错误。
## 本卡仍走九字段校验（V-PC-01/03/04/05），并在下面判「必须在册」。
##
## **未实现的那一半**：V-PC-07 要求 `value` 与 IOTable 规范化哈希的前 16 位十进制截断相符，
## 而「规范化」与「十进制截断」的确切规则在 docs/11 §6.4 之外没有任何一处定义，
## 也没有任何工具实现过它（tools/validate_content.py 只判卡在不在）。
## 此处**不猜**一套哈希规则：猜出来的规则只会与写卡的人各算各的，
## 或者反过来照着卡里的数字凑，两种都会得到一条恒真的检查。已在 open_questions 登记。
const PARAM_IO_TABLE_SET: String = "param.io_table_set"

## 本次载入是否见到集合级 IO 卡（V-PC-07 的「在册」那一半）。
var _seen_io_table_card: bool = false


## 参数包加载与交叉校验（docs/14 的参数卡 → JWSimState.params 稠密数组）。
## 步骤：LOAD
## 前置：每个数值参数有一张九字段齐全的身份证卡
## 后置：params 数组填满；`sim/**` 内无魔数
## 不变量：INV-152（`observed` 却无对应数据文件即失败，首版 `observed` 必须为 0）、
##          INV-122（trust_recover < trust_drop）、三项 support 权重之和 == 1e6
## 失败：Load.PARAM_CARD / FAKE_OBSERVED / PARAM_DERIVE / PARAM_COVERAGE / PARAM_STALE
func validate_params(st: JWSimState) -> JWResult:
	var before: int = errors.size()
	var values: PackedInt64Array = _zeros(JWUnits.PARAM_N)
	var filled: PackedInt64Array = _zeros(JWUnits.PARAM_N)

	var idx: int = -1
	for i: int in _kinds.size():
		if _kinds[i] == "parameter_set":
			idx = i
			break
	if idx >= 0:
		_read_param_cards(_docs[idx], _paths[idx] + "#", values, filled, st)

	# V-PC-06 / INV-152：覆盖率。缺一张卡就少一个下标，运行期只能靠裸数字顶上 —— 拒绝启动。
	for i: int in JWUnits.PARAM_N:
		if filled[i] == 0:
			_fail(JWResult.Load.PARAM_COVERAGE, PARAMS_CORE + "#" + PARAM_IDS[i], i, 0)
	st.params = values

	_cross_check_params(values, filled, st)

	if errors.size() == before:
		return JWResult.make_ok()
	return errors[before]


func _read_param_cards(doc: Dictionary, w: String, values: PackedInt64Array,
		filled: PackedInt64Array, st: JWSimState) -> void:
	_check_keys(doc, PackedStringArray(["schema_kind", "schema_version", "param_set_id",
			"param_set_version", "cards"]), w)
	var version: int = _get_int(doc, "param_set_version", w, JWResult.Load.PARAM_CARD)
	# 参数包版本是重放与只读检视的判据之一（docs/11 §6.7 M-9），两处必须一致。
	if version != param_set_version:
		_fail(JWResult.Load.PARAM_STALE, w + "/param_set_version", version, param_set_version)

	var observed: int = 0
	var cards: Array = _get_array(doc, "cards", w, JWResult.Load.PARAM_CARD)
	for i: int in cards.size():
		var cw: String = w + "/cards/" + str(i)
		if typeof(cards[i]) != TYPE_DICTIONARY:
			_fail(JWResult.Load.PARAM_CARD, cw, typeof(cards[i]), TYPE_DICTIONARY)
			continue
		var c: Dictionary = cards[i]
		# V-PC-01：九字段齐全，缺一即失败。
		_require(c, PARAM_CARD_REQUIRED, cw, JWResult.Load.PARAM_CARD)
		var pid: String = _get_str(c, "parameter_id", cw, JWResult.Load.PARAM_CARD)
		var source: String = _get_str(c, "source_type", cw, JWResult.Load.PARAM_CARD)
		if _name_index(PARAM_SOURCE_TYPES, source) < 0:
			_fail(JWResult.Load.PARAM_CARD, cw + "/source_type", 0, 0)
		if _name_index(PARAM_CONFIDENCE,
				_get_str(c, "confidence", cw, JWResult.Load.PARAM_CARD)) < 0:
			_fail(JWResult.Load.PARAM_CARD, cw + "/confidence", 0, 0)
		if _get_str(c, "definition", cw, JWResult.Load.PARAM_CARD).is_empty():
			_fail(JWResult.Load.PARAM_CARD, cw + "/definition", 0, 0)
		if _get_str(c, "calibration_note", cw, JWResult.Load.PARAM_CARD).is_empty():
			_fail(JWResult.Load.PARAM_CARD, cw + "/calibration_note", 0, 0)
		if _get_str(c, "source_ref", cw, JWResult.Load.PARAM_CARD).is_empty():
			_fail(JWResult.Load.PARAM_CARD, cw + "/source_ref", 0, 0)
		# V-PC-03 / V-PC-04：首版内容包中 observed 条目数必须为 0（计划书 §19：数据尚未导入）。
		if source == "observed":
			observed += 1
			_fail(JWResult.Load.FAKE_OBSERVED, cw + "/source_type", observed, 0)
		# V-PC-05：derived 类必须给 derivation_expr 并被复算验证。
		# 复算器不在本加载器的职责内（它要一个表达式求值器，而契约只给了断言用的那个极小集合）；
		# 这里判「有没有给」，并把复算登记为接口变更请求。
		if source == "derived" and not c.has("derivation_expr"):
			_fail(JWResult.Load.PARAM_DERIVE, cw + "/derivation_expr", 0, 0)

		var vr: PackedInt64Array = _get_int_array(c, "valid_range", 2, cw,
				JWResult.Load.PARAM_CARD)
		if vr[0] > vr[1]:
			_fail(JWResult.Reject.PARAM_RANGE, cw + "/valid_range", vr[0], vr[1])

		if pid == PARAM_RNG_SALT:
			_read_rng_salt(c, cw, st)
			continue
		if pid == PARAM_IO_TABLE_SET:
			_seen_io_table_card = true
			continue
		_store_card_value(c, pid, cw, vr, values, filled)

	# V-PC-07：IO 整表的集合级卡必须在册（§5.15 的唯一例外条款）。
	# 没有它，「改了技术系数却忘了更新校准说明」不会被任何检查发现。
	if not _seen_io_table_card:
		_fail(JWResult.Load.PARAM_STALE, w + "#" + PARAM_IO_TABLE_SET, 0, 0)


## 把一张卡的 `value` 写进稠密数组。数组型卡按元素展开成连续槽位（`<id>.<i>`）。
func _store_card_value(c: Dictionary, pid: String, cw: String, vr: PackedInt64Array,
		values: PackedInt64Array, filled: PackedInt64Array) -> void:
	if not c.has("value"):
		return
	var v: Variant = c["value"]
	if _is_num(v):
		var slot: int = _name_index(PARAM_IDS, pid)
		if slot < 0:
			# 卡在册但下标表里没有它：要么 ID 写错，要么 JWUnits.Param 该追加一项。
			_fail(JWResult.Load.PARAM_COVERAGE, cw + "/parameter_id", 0, 0)
			return
		if filled[slot] != 0:
			_fail(JWResult.Load.DUP_ID, cw + "/parameter_id", slot, 0)
			return
		# V-PC-02：value ∈ valid_range。
		if _num(v) < vr[0] or _num(v) > vr[1]:
			_fail(JWResult.Reject.PARAM_RANGE, cw + "/value", _num(v), vr[0])
		values[slot] = _num(v)
		filled[slot] = 1
		return
	if typeof(v) != TYPE_ARRAY:
		_fail(JWResult.Load.PARAM_CARD, cw + "/value", typeof(v), TYPE_INT)
		return
	var arr: Array = v
	for i: int in arr.size():
		var slot2: int = _name_index(PARAM_IDS, pid + "." + str(i))
		if slot2 < 0:
			_fail(JWResult.Load.PARAM_COVERAGE, cw + "/value/" + str(i), i, 0)
			continue
		if not _is_num(arr[i]):
			_fail(JWResult.Load.PARAM_CARD, cw + "/value/" + str(i), typeof(arr[i]), TYPE_INT)
			continue
		if _num(arr[i]) < vr[0] or _num(arr[i]) > vr[1]:
			_fail(JWResult.Reject.PARAM_RANGE, cw + "/value/" + str(i), _num(arr[i]), vr[0])
		values[slot2] = _num(arr[i])
		filled[slot2] = 1


## `param.rng_salt[6]`：不进 params 数组，直接交给 JWRngStreams（它是 content.rng.salt 的所有者）。
##
## 三道校验，缺一道就会有一种「盐表坏了但加载器说没事」的情形：
##   1. 取值域：每个盐必须 > 0 且 ≤ 2^53（docs/11 §1.2 的 JSON 互操作安全区）。
##      0 是最危险的取值——它让该流的盐项在异或里完全消失。
##   2. 两两不同（INV-009）：盐值是流隔离的唯一来源，两条流同盐就会在同一 (q, index)
##      给出同一个数，「多写一句新闻也改变经济抽样」的风险变成现实。
##   3. 与 JWRngStreams.DEFAULT_SALT 逐位相同：salt「属 schema，发布后不得更改」
##      （docs/11 §5.15.2、INV-136），改一位就让全部已发布存档的重放失效。
##      与本文件对 `amount_max_uu` / `qty_max_uqs` 的处置同形：故意冗余的重复登记，
##      防止参数包与代码各说各的。
## 任一道不过就不写 st.rng.salt：宁可让引擎守着已登记的 schema 常量跑，
## 也不能把一张坏盐表装进权威状态。
func _read_rng_salt(c: Dictionary, cw: String, st: JWSimState) -> void:
	var salt: PackedInt64Array = _get_int_array(c, "value", JWUnits.RNG_STREAM_N, cw,
			JWResult.Load.PARAM_CARD)
	var before: int = errors.size()
	for i: int in JWUnits.RNG_STREAM_N:
		if salt[i] <= 0 or salt[i] > JSON_INT_ABS_MAX:
			_fail(JWResult.Reject.PARAM_RANGE, cw + "/value/" + str(i), salt[i], 0)
		for j: int in range(i + 1, JWUnits.RNG_STREAM_N):
			if salt[i] == salt[j]:
				_fail(JWResult.Load.DUP_ID, cw + "/value/" + str(j), j, i)
		if salt[i] != JWRngStreams.DEFAULT_SALT[i]:
			_fail(JWResult.Load.UNIT_MISMATCH, cw + "/value/" + str(i),
					salt[i], JWRngStreams.DEFAULT_SALT[i])
	if errors.size() != before:
		return
	st.rng.salt = salt.duplicate()


## 参数之间的交叉校验（docs/17 §2.6 的清单）。缺卡的项跳过 —— 缺卡本身已经报过一次，
## 拿 0 去比会再报一条假的「权重和不对」，把真正的原因埋掉。
func _cross_check_params(v: PackedInt64Array, filled: PackedInt64Array, st: JWSimState) -> void:
	var w: String = PARAMS_CORE + "#cross"
	# 与代码常量的重复登记：故意冗余，防止参数包与代码各说各的。
	if filled[JWUnits.Param.AMOUNT_MAX_UU] == 1 \
			and v[JWUnits.Param.AMOUNT_MAX_UU] != JWUnits.AMOUNT_MAX:
		_fail(JWResult.Load.UNIT_MISMATCH, w + "/amount_max_uu",
				v[JWUnits.Param.AMOUNT_MAX_UU], JWUnits.AMOUNT_MAX)
	if filled[JWUnits.Param.QTY_MAX_UQS] == 1 \
			and v[JWUnits.Param.QTY_MAX_UQS] != JWUnits.QTY_MAX:
		_fail(JWResult.Load.UNIT_MISMATCH, w + "/qty_max_uqs",
				v[JWUnits.Param.QTY_MAX_UQS], JWUnits.QTY_MAX)
	# §5.15.2 第 3 条：价格上下限的 ppm 口径与绝对界是同一约束的两种写法，必须同时成立。
	if filled[JWUnits.Param.PRICE_FLOOR_PPM] == 1 \
			and JWMath.mul_ppm(JWUnits.BASE_PRICE, v[JWUnits.Param.PRICE_FLOOR_PPM]) \
					!= JWUnits.PRICE_MIN:
		_fail(JWResult.Load.UNIT_MISMATCH, w + "/price_floor_ppm",
				v[JWUnits.Param.PRICE_FLOOR_PPM], JWUnits.PRICE_MIN)
	if filled[JWUnits.Param.PRICE_CEIL_PPM] == 1 \
			and JWMath.mul_ppm(JWUnits.BASE_PRICE, v[JWUnits.Param.PRICE_CEIL_PPM]) \
					!= JWUnits.PRICE_MAX:
		_fail(JWResult.Load.UNIT_MISMATCH, w + "/price_ceil_ppm",
				v[JWUnits.Param.PRICE_CEIL_PPM], JWUnits.PRICE_MAX)
	# INV-122：信任恢复必须慢于下降。
	if filled[JWUnits.Param.TRUST_RECOVER_PPM] == 1 and filled[JWUnits.Param.TRUST_DROP_PPM] == 1 \
			and v[JWUnits.Param.TRUST_RECOVER_PPM] >= v[JWUnits.Param.TRUST_DROP_PPM]:
		_fail(JWResult.Reject.PARAM_RANGE, w + "/trust_recover_ppm",
				v[JWUnits.Param.TRUST_RECOVER_PPM], v[JWUnits.Param.TRUST_DROP_PPM])
	# R-P11-02：征收能力恢复必须慢于下降；地板必须逐位等于剧本基年征收能力（policy_P11.json 交接记录）。
	if filled[JWUnits.Param.P11_CAPACITY_RECOVER_PPM] == 1 and filled[JWUnits.Param.P11_CAPACITY_DECAY_PPM] == 1 \
			and v[JWUnits.Param.P11_CAPACITY_RECOVER_PPM] >= v[JWUnits.Param.P11_CAPACITY_DECAY_PPM]:
		_fail(JWResult.Reject.PARAM_RANGE, w + "/p11_capacity_recover_ppm",
				v[JWUnits.Param.P11_CAPACITY_RECOVER_PPM], v[JWUnits.Param.P11_CAPACITY_DECAY_PPM])
	if filled[JWUnits.Param.P11_CAPACITY_FLOOR_PPM] == 1 and st.treasury != null \
			and v[JWUnits.Param.P11_CAPACITY_FLOOR_PPM] != st.treasury.tax_capacity_ppm:
		_fail(JWResult.Load.UNIT_MISMATCH, w + "/p11_capacity_floor_ppm",
				v[JWUnits.Param.P11_CAPACITY_FLOOR_PPM], st.treasury.tax_capacity_ppm)

	_sum_must_be_ppm(v, filled, PackedInt64Array([JWUnits.Param.SUPPORT_WEIGHT_PPM_0,
			JWUnits.Param.SUPPORT_WEIGHT_PPM_1, JWUnits.Param.SUPPORT_WEIGHT_PPM_2]),
			w + "/support_weight_ppm")
	_sum_must_be_ppm(v, filled, PackedInt64Array([JWUnits.Param.ENGEL_WEIGHT_PPM_0,
			JWUnits.Param.ENGEL_WEIGHT_PPM_1, JWUnits.Param.ENGEL_WEIGHT_PPM_2,
			JWUnits.Param.ENGEL_WEIGHT_PPM_3]), w + "/engel_weight_ppm")
	_sum_must_be_ppm(v, filled, PackedInt64Array([JWUnits.Param.MIGRATION_W_WAGE_PPM,
			JWUnits.Param.MIGRATION_W_JOB_PPM, JWUnits.Param.MIGRATION_W_SERVICE_PPM]),
			w + "/migration_pull_weights")
	_sum_must_be_ppm(v, filled, PackedInt64Array([JWUnits.Param.MIGRATION_W_HOUSE_PPM,
			JWUnits.Param.MIGRATION_W_ENV_PPM]), w + "/migration_push_weights")
	_sum_must_be_ppm(v, filled, PackedInt64Array([JWUnits.Param.BLOC_ORG_INERTIA_PPM,
			JWUnits.Param.BLOC_W_SIZE_PPM, JWUnits.Param.BLOC_W_RESOURCE_PPM]),
			w + "/bloc_org_weights")
	# 生活指数：住房 + 服务 + 收入 == 1e6，收入权重是余项，故两项之和不得达到 1e6。
	if filled[JWUnits.Param.LIVING_WEIGHT_HOUSE_PPM] == 1 \
			and filled[JWUnits.Param.LIVING_WEIGHT_SERVICE_PPM] == 1:
		var two: int = v[JWUnits.Param.LIVING_WEIGHT_HOUSE_PPM] \
				+ v[JWUnits.Param.LIVING_WEIGHT_SERVICE_PPM]
		if two >= JWUnits.PPM:
			_fail(JWResult.Reject.PARAM_RANGE, w + "/living_weights", two, JWUnits.PPM)

	# §5.4 的说明：world_init.sovereign_rate_ppm_per_q 不是自由参数，
	# 它必须等于 param.market_rate_base_ppm，否则读档瞬间与第一季的利率之间会有一次无法解释的跳变。
	if filled[JWUnits.Param.MARKET_RATE_BASE_PPM] == 1 \
			and st.world.sovereign_rate() != v[JWUnits.Param.MARKET_RATE_BASE_PPM]:
		_fail(JWResult.Load.UNIT_MISMATCH, w + "/market_rate_base_ppm",
				st.world.sovereign_rate(), v[JWUnits.Param.MARKET_RATE_BASE_PPM])
	# 票息上下限不得倒挂。
	if filled[JWUnits.Param.COUPON_MIN_PPM] == 1 and filled[JWUnits.Param.COUPON_MAX_PPM] == 1 \
			and v[JWUnits.Param.COUPON_MIN_PPM] > v[JWUnits.Param.COUPON_MAX_PPM]:
		_fail(JWResult.Reject.PARAM_RANGE, w + "/coupon_bounds", v[JWUnits.Param.COUPON_MIN_PPM],
				v[JWUnits.Param.COUPON_MAX_PPM])


func _sum_must_be_ppm(v: PackedInt64Array, filled: PackedInt64Array, slots: PackedInt64Array,
		w: String) -> void:
	var acc: int = 0
	for i: int in slots.size():
		if filled[slots[i]] == 0:
			return
		acc += v[slots[i]]
	if acc != JWUnits.PPM:
		_fail(JWResult.Reject.PARAM_RANGE, w, acc, JWUnits.PPM)

# ── 初始账本 ───────────────────────────────────────────────────────────────

## 构建初始账本：把全部初值写成 q = −1 的开账分录。
## 步骤：LOAD
## 前置：全部 Init 已校验通过
## 后置：开账完成后 `agent.opening.cash == 0`（OQ-217：现金腿与各主体自身 nw 配平，
##       不经 opening 的现金科目）；`Σ all cash == scenario.total_cash_uu`
## 不变量：INV-023（初始化不是恒等式的例外）、INV-015、INV-018、INV-020
## 失败：Load.BALANCE_INIT / CASH_TOTAL
##
## 分录本身在各 `_validate_*` 里边校验边登记（`_add_open`），本函数只负责**按稳定顺序过账**
## 与过账后的三条对账。顺序 = 登记顺序 = 文件顺序 = 下标顺序，因此是确定的（INV-008）。
func build_opening_ledger(st: JWSimState) -> JWResult:
	var before: int = errors.size()
	var w: String = "opening#"
	for i: int in _op_agent.size():
		var rc: int = st.ledger.post_opening(_op_agent[i], _op_code[i], _op_amount[i])
		if rc != JWResult.OK:
			_fail(rc, w + str(_op_agent[i]) + "/" + str(_op_code[i]), _op_agent[i],
					_op_amount[i])
			# 第一条开账分录过不去，后面 100 多条是同一个原因的复述。
			# 继续写只会把错误清单灌满同一条现场，反而盖住真正的第一现场（docs/12 §9）。
			break

	# INV-018：全经济现金总量恒等于剧本登记值。
	var cash: int = st.accounts.total_cash()
	if cash != _total_cash_uu:
		_fail(JWResult.Load.CASH_TOTAL, w + "total_cash", cash, _total_cash_uu)
	# OQ-217：agent.opening 只作对手方标记，余额恒为 0。
	var opening_cash: int = st.accounts.cash_of(JWIds.AGENT_OPENING)
	if opening_cash != 0:
		_fail(JWResult.Load.BALANCE_INIT, w + "agent.opening/cash", opening_cash, 0)
	if st.accounts.net_worth_of(JWIds.AGENT_OPENING) != 0:
		_fail(JWResult.Load.BALANCE_INIT, w + "agent.opening/nw",
				st.accounts.net_worth_of(JWIds.AGENT_OPENING), 0)
	# INV-020：逐主体资产负债恒等式；INV-019：Σ recv == Σ pay。
	var rc_bs: int = st.accounts.check_balance_sheet()
	if rc_bs != JWResult.OK:
		_fail(JWResult.Load.BALANCE_INIT, w + "balance_sheet", rc_bs, 0)
	var rc_rp: int = st.accounts.check_receivable_payable()
	if rc_rp != JWResult.OK:
		_fail(JWResult.Load.BALANCE_INIT, w + "receivable_payable", rc_rp, 0)

	if errors.size() == before:
		return JWResult.make_ok()
	return errors[before]

# ── content_hash ───────────────────────────────────────────────────────────

## `content_hash` 的排除集合（docs/11 §6.4 第 5 条）：展示文案不进哈希，
## 改一句中文不会让老存档失效。`_note_*` / `_origin_*` 等注释键同理（前缀 `_`）。
const HASH_EXCLUDED_KEYS: PackedStringArray = ["label_zh", "desc_zh", "report_template_id"]


## content_hash：按相对路径升序，每个文件**先解析后做规范化**再拼接（不哈希原始字节）。
## 步骤：LOAD
## 前置：全部文件已解析
## 后置：格式化改动不影响哈希
## 不变量：INV-134（不符即进入只读检视模式）
## 失败：无
##
## 同时算出 `scenario_hash`（只含剧本目录），便于定位到底是剧本改了还是政策改了。
## **生成产物整份排除**（§6.4 第 6 条的例外，目前只有 `parameters/registry.json`）：
## 它由同一批源文件算出，算进哈希等于把同一份数据数两遍，而且重跑一次生成器
## 会平白让全部老存档进只读检视模式。
func compute_content_hash(root_path: String) -> String:
	var root: String = root_path.trim_suffix("/")
	var files: PackedStringArray = PackedStringArray()
	var saved_root: String = _root
	_root = root
	_scan("", files)
	_root = saved_root
	files.sort()

	var all_buf: PackedByteArray = PackedByteArray()
	var scenario_buf: PackedByteArray = PackedByteArray()
	for i: int in files.size():
		var rel: String = files[i]
		if rel == PARAMS_REGISTRY or not _in_layout(rel):
			continue
		# R-SCENARIO-01：别的剧本目录不进本剧本的内容指纹，改战役内容不会让旧剧本存档进只读。
		if rel.begins_with(SCENARIOS_ROOT + "/") and not rel.begins_with(_scenario_dir + "/"):
			continue
		var parser: JSON = JSON.new()
		if parser.parse(FileAccess.get_file_as_bytes(root + "/" + rel)
				.get_string_from_utf8()) != OK:
			continue
		_canon_node(all_buf, rel, parser.data)
		if rel.begins_with(_scenario_dir + "/"):
			_canon_node(scenario_buf, rel, parser.data)
	# 空缓冲不做 sha256：HashingContext.update 对零长度输入会报错，而「一个文件都没读到」
	# 本身已经是加载流水线里报过的错（布局与必备文件那两段）。此时返回空串，
	# 让 INV-134 的比对必然不符 —— 进只读检视模式，而不是拿一个假的哈希冒充「内容一致」。
	scenario_hash = "" if scenario_buf.is_empty() else JWSimState.sha256_hex(scenario_buf)
	if all_buf.is_empty():
		return ""
	return JWSimState.sha256_hex(all_buf)


## 规范化一个已解析的 JSON 子树。条目 ID 是「相对路径 + JSON 指针」，
## 字典键按字节序升序 —— 拼接顺序因此与文件里的书写顺序无关（这正是「先解析后规范化」的意思）。
func _canon_node(buf: PackedByteArray, id: String, node: Variant) -> void:
	var t: int = typeof(node)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = node
		var keys: PackedStringArray = PackedStringArray()
		for k: Variant in d.keys():
			var ks: String = String(k)
			if ks.begins_with("_") or HASH_EXCLUDED_KEYS.has(ks):
				continue
			keys.append(ks)
		keys.sort()
		for i: int in keys.size():
			_canon_node(buf, id + "/" + keys[i], d[keys[i]])
		return
	if t == TYPE_ARRAY:
		var a: Array = node
		for i: int in a.size():
			_canon_node(buf, id + "/" + str(i), a[i])
		return
	if _is_num(node):
		# 解析器把整数读成 double；规范化编码只认 int64，这里统一收窄
		# （超界与非整数已在方言检查里被拒，走到这里的一定是可无损收窄的整数）。
		JWSimState.canon_scalar(buf, id.to_utf8_buffer(), _num(node))
		return
	if t == TYPE_BOOL:
		# 契约的规范化编码只有整数 / 整数数组 / 字符串三种标签；布尔按 0/1 归到整数标签。
		JWSimState.canon_scalar(buf, id.to_utf8_buffer(), 1 if bool(node) else 0)
		return
	if t == TYPE_STRING or t == TYPE_STRING_NAME:
		JWSimState.canon_string(buf, id.to_utf8_buffer(), String(node))
		return
	# 浮点与 null 在方言检查里已被拒；走到这里说明有一条路径绕过了检查。
	JWResult.raise_fault(JWResult.Fault.FLOAT_IN_STATE, t, 0)

