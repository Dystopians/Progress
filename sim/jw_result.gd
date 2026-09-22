## 全系统唯一的错误码定义与故障登记点。禁止任何别的文件自定义错误码。
##
## 它不依赖任何文件（连 JWUnits 都不依赖），因为 JWMath 要在溢出时调它（依赖秩 0）。
## 冷路径用对象形态 {ok, code, detail_a, detail_b, detail_key}；
## 热路径用静态故障登记，不分配对象（docs/17 §1.3）。
class_name JWResult
extends RefCounted

const OK: int = 0

## 故障码，逐字对应 docs/12 §9 的 Fault 枚举，数值不得改（进故障包与测试断言）
enum Fault {
	OK = 0, RUN_ENDED = 1,
	FLOW_NOT_RESET = 10, WRITE_OUT_OF_SCOPE = 11, PHASE_VIOLATION = 12, RNG_LOG_MISMATCH = 13,
	NEGATIVE_CASH = 20, BOND_MISMATCH = 21, LEDGER_IMBALANCE = 22, SPLIT_MISMATCH = 23,
	CASH_TOTAL_CHANGED = 24, BALANCE_SHEET_BROKEN = 25,
	NEGATIVE_INVENTORY = 30, UNBOUNDED_PRODUCTION = 31, ENERGY_STORED = 32,
	DOUBLE_ALLOCATION = 33, STOCK_IDENTITY = 34,
	POPULATION_NOT_CONSERVED = 40, MIGRATION_UNPAIRED = 41, EMPLOYMENT_OVERFLOW = 42,
	HOUSING_OVERFLOW = 43, WAGE_UNFUNDED = 44,
	GDP_CLASS_MISSING = 50, GDP_CLASS_DUPLICATE = 51, LEDGER_KIND_UNCLASSIFIED = 52,
	GDP_IDENTITY = 53,
	SUPPORT_UNEXPLAINED = 60, METRIC_UNKNOWN = 61,
	INT_OVERFLOW = 90, DIV_ZERO = 91, INDEX_OUT_OF_RANGE = 92, FLOAT_IN_STATE = 93,
}

## 命令拒绝码，逐字对应 docs/11 §7 的 E_* 表，值不得改
enum Reject {
	NONE = 0,
	RUN_TERMINATED = 1000, PHASE_BUSY = 1001, UNKNOWN_POLICY = 1002, POLICY_COOLDOWN = 1003,
	AUTHORITY = 1004, SEATS_SHORT = 1005, BLOC_VETO = 1006, BUDGET_INSUFFICIENT = 1007,
	NO_FUNDING = 1008, CREDIT_LIMIT = 1009, NO_SLOT = 1010, PRECONDITION = 1011,
	ALREADY_ENACTED = 1012, NOT_FOUND = 1013, DIRECT_STATE_WRITE = 1014,
	PARAM_RANGE = 1015, PRIORITY_INCOMPLETE = 1016, OVERPAY = 1017, COMMAND_ORDER = 1018,
}

## 加载期拒绝码，逐字对应 docs/11 §7 的 E_* 表，值不得改
enum Load {
	NONE = 0,
	FILE_FORMAT = 2000, SCHEMA_HEADER = 2001, FLOAT_IN_CONTENT = 2002, INT_RANGE = 2003,
	NULL_NOT_ALLOWED = 2004, UNKNOWN_FIELD = 2005, KEY_NAMING = 2006, DUP_ID = 2007,
	ID_FORMAT = 2008, ALIAS_IN_CONTENT = 2009, UNIT_MISMATCH = 2010,
	POP_TOTAL = 2100, POP_REGION = 2101, GROUP_SET = 2102, POP_AGE_ROLE = 2103, POP_EMP = 2104,
	POP_UNEMP = 2105, EMPLOY_MISMATCH = 2106, HOUSE_CAP = 2107, HOUSE_OVER = 2108,
	INDEX_BASE = 2109,
	CASH_INIT = 2200, DEBT_TOTAL = 2201, FIN_YEARPLAN = 2202, FIN_LINES = 2203,
	FIN_INTEREST = 2204, BOND_FIELD = 2205, INVPOOL_TOO_SMALL = 2206, DEPOSIT_MISMATCH = 2207,
	GDP_INIT = 2208, BALANCE_INIT = 2209, CASH_TOTAL = 2210, ASSERT_TOLERANCE = 2211,
	REGION_SET = 2300, REGION_ADJ = 2301, REGION_SLOTS = 2302, CELL_SET = 2303,
	ENERGY_INVENTORY = 2304, CAPACITY_INCONSISTENT = 2305, EQUITY_SHARE = 2306,
	SERVICE_SPLIT = 2307, RANGE = 2308,
	IO_COLSUM = 2400, IO_STORABLE = 2401, IO_ENERGY_SELF = 2402, IO_NEGATIVE = 2403,
	IO_NOT_CONVERGENT = 2404, IO_ENERGY_COEFF = 2405, IO_LABOR = 2406, IO_CAPACITY_COEFF = 2407,
	POLICY_COUNT = 2500, POLICY_FIELDS = 2501, POLICY_COST = 2502, COMMISSION_LAG = 2503,
	POLICY_TEST_MISSING = 2504, MECH_UNKNOWN = 2505, EFFECT_TARGET = 2506,
	EVENT_COUNT = 2600, METRIC_UNKNOWN = 2601, EVENT_OP = 2602, EVENT_STREAM = 2603,
	EVENT_TARGET = 2604, EVENT_LEDGER = 2605, EVENT_FIELD = 2606, EVENT_EVIDENCE = 2607,
	SHOCK_COUNT = 2700, SHOCK_STREAM = 2701, SHOCK_WEIGHTS = 2702, SHOCK_SCOPE = 2703,
	SHOCK_LOG = 2704, SHOCK_RANGE = 2705,
	PARAM_CARD = 2800, FAKE_OBSERVED = 2801, PARAM_DERIVE = 2802, PARAM_COVERAGE = 2803,
	PARAM_STALE = 2804,
	SAVE_CORRUPT = 2900, SAVE_VERSION_TOO_NEW = 2901, MIGRATION_MISSING = 2902,
}

# ── 成员变量（冷路径对象形态） ─────────────────────────────────────────────

## 是否成功
var ok: bool = true
## Fault / Reject / Load 之一
var code: int = 0
## 上下文整数 1（实体下标、期望值）
var detail_a: int = 0
## 上下文整数 2（实际值、残差）
var detail_b: int = 0
## 本地化文案键的整数码（不存字符串，由 Presentation 查表）
var detail_key: int = 0

# ── 静态故障登记（热路径用，无对象分配） ───────────────────────────────────

## 本季第一次故障的码；后续故障不覆盖它
static var _pending_code: int = 0
## 故障发生的步骤（JWUnits.Phase）
static var _pending_step: int = 0
## 现场整数 1
static var _pending_a: int = 0
## 现场整数 2
static var _pending_b: int = 0
## 由 JWTurnRunner 每步入口设置，供 raise_fault 自动带上步骤
static var _current_step: int = 0

# ── 方法 ───────────────────────────────────────────────────────────────────

## 登记一次故障并返回故障码，供调用方直接 `return JWResult.raise_fault(...)`。
## 步骤：任意（热路径）
## 前置：code != 0
## 后置：_pending_* 被写（仅第一次），返回值 == code
## 不变量：INV-006, INV-007（溢出与越界经由本函数落地）；docs/12 §9 的「不回滚到看起来正常的状态」
## 失败：本身不失败；它就是失败的登记点
static func raise_fault(code: int, detail_a: int = 0, detail_b: int = 0) -> int:
	# code == 0 不是故障：直接放行，避免调用方误把 OK 登记成故障而掩盖真正的第一现场。
	if code == 0:
		return 0
	# 只登记本季第一次故障。后续故障往往是第一次故障的下游后果，
	# 覆盖它会让故障包指向错误的现场（docs/12 §9「不回滚到看起来正常的状态」）。
	if _pending_code == 0:
		_pending_code = code
		_pending_step = _current_step
		_pending_a = detail_a
		_pending_b = detail_b
		if trace_faults:
			_print_fault_site(code, detail_a, detail_b)
	return code


## 诊断开关：打开后，本季第一次故障登记时打印故障码与 GDScript 调用栈。
## 默认关闭；只由 tools/ 下的诊断脚本打开，不进状态、不进哈希、不影响任何结算结果。
static var trace_faults: bool = false


static func _print_fault_site(code: int, detail_a: int, detail_b: int) -> void:
	print("[fault] code=%d step=%d a=%d b=%d" % [code, _current_step, detail_a, detail_b])
	var frames: Array = get_stack()
	for i: int in frames.size():
		if i == 0:
			continue
		var f: Dictionary = frames[i]
		print("    at %s:%d  %s()" % [String(f.get("source", "?")), int(f.get("line", 0)), String(f.get("function", "?"))])


## 查询本季是否已有未处理故障（WriteGuard 与 TurnRunner 用）。
## 步骤：每步末
## 前置：无
## 后置：不改状态
## 不变量：INV-012（有故障即中止推进）
## 失败：无
static func has_pending() -> bool:
	return _pending_code != 0


## 返回本季已登记的故障码，无故障时为 0。
## 步骤：每步末
## 前置：无
## 后置：不改状态
## 不变量：INV-012
## 失败：无
static func pending_code() -> int:
	return _pending_code


## 返回故障发生的步骤号（JWUnits.Phase），无故障时为 0。
## 步骤：每步末
## 前置：无
## 后置：不改状态
## 不变量：INV-012
## 失败：无
static func pending_step() -> int:
	return _pending_step


## 清空故障登记，只允许在开始新的一局或导出故障包之后调用。
## 步骤：LOAD / 故障包导出后
## 前置：调用方已经把故障包写盘
## 后置：_pending_* 归零
## 不变量：docs/12 §9「不得自动修正」——本函数不修状态，只清登记
## 失败：无
static func clear_pending() -> void:
	_pending_code = 0
	_pending_step = 0
	_pending_a = 0
	_pending_b = 0


## 设置当前步骤号，使 raise_fault 自动带上步骤（避免每个调用点手写步骤）。
## 步骤：S01..S08 入口
## 前置：step ∈ JWUnits.Phase
## 后置：_current_step == step
## 不变量：INV-012
## 失败：无
static func set_step(step: int) -> void:
	_current_step = step


## 冷路径构造器：成功结果。
## 步骤：加载 / 命令 / 存档
## 前置：无
## 后置：返回一个新对象；禁止在结算期调用
## 不变量：docs/17 §1.4 热路径不分配
## 失败：无
static func make_ok() -> JWResult:
	var r: JWResult = JWResult.new()
	r.ok = true
	r.code = 0
	return r


## 冷路径构造器：失败结果。
## 步骤：加载 / 命令 / 存档
## 前置：无
## 后置：返回一个新对象；禁止在结算期调用
## 不变量：docs/17 §1.4 热路径不分配
## 失败：无
static func make_err(code: int, a: int = 0, b: int = 0, key: int = 0) -> JWResult:
	var r: JWResult = JWResult.new()
	r.ok = false
	r.code = code
	r.detail_a = a
	r.detail_b = b
	r.detail_key = key
	return r
