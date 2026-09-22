## 稳定 ID 字符串 ↔ 稠密整数下标的双向映射（只在 LOAD 期可用），
## 以及 docs/17 §2.2–§2.4 的全部索引函数（运行期只用这些）。
##
## freeze() 之后 SimCore 进入「零字符串」状态：再调 resolve() 即 Fault.PHASE_VIOLATION。
## 依赖秩 1：只允许引用 JWUnits 与 JWResult。
class_name JWIds
extends RefCounted

## 稳定 ID 的种类。下标即 _index_to_id 的第一维。
enum IdKind { REGION = 0, SECTOR = 1, CELL = 2, PUBSERV = 3, GROUP = 4, POLICY = 5, EVENT = 6,
		SHOCK = 7, BOND = 8, PROJECT = 9, BLOC = 10, AGENT = 11, ACCOUNT = 12, PARAM = 13,
		MECHANISM = 14 }
const ID_KIND_N: int = 15

## 稳定 ID 的正则，逐字取自 docs/10 §0.4：全小写 ASCII 起头，段间 `.`，段内 `_`；
## 第二段起允许大写，以容纳政策／事件／冲击编号段（P04、E11、S02）。
const ID_PATTERN: String = "^[a-z][a-z0-9_]*(\\.[a-zA-Z0-9_]+)*$"

## idx_policy_param 的行宽。== JWUnits.POLICY_PARAM_N / JWUnits.POLICY_N，
## 但索引函数里不许出现除法，故写成常量；一致性由 T-U-IDS 的静态关系断言守住。
const POLICY_PARAM_STRIDE: int = 4

# ── 主体（agent）下标布局（docs/17 §2.3）—— 60 个，加载期枚举，运行期不新建 ──
#
#  0            agent.gov
#  1 .. 16      agent.cell.<region>.<sector>        == 1 + idx_cell(r, s)
# 17 .. 20      agent.pubserv.<region>              == 17 + r
# 21 .. 56      agent.group.<region>.<age>.<skill>  == 21 + idx_group(r, a, k)
# 57            agent.invpool
# 58            agent.row
# 59            agent.opening

const AGENT_GOV: int = 0

## R-SCENARIO-02：主体布局随地区数变化（上面的编号表是 4 区时的取值）。
## 调用顺序：JWUnits.set_regions(n) → JWIds.apply_dims()，两者都在分配状态之前。
static func apply_dims() -> void:
	AGENT_PUBSERV_BASE = AGENT_CELL_BASE + JWUnits.CELL
	AGENT_GROUP_BASE = AGENT_PUBSERV_BASE + JWUnits.PUBSERV
	AGENT_INVPOOL = AGENT_GROUP_BASE + JWUnits.GROUP
	AGENT_ROW = AGENT_INVPOOL + 1
	AGENT_OPENING = AGENT_ROW + 1
	AGENT_CASH_ACCOUNTS = JWUnits.AGENT_N - JWUnits.PUBSERV
	AGENT_CASH_ACTIVE = AGENT_CASH_ACCOUNTS - 1
	# 反解表按嵌套循环重建（本类不许出现裸 `/`，见下方反解表的说明）。
	REGION_OF_CELL = PackedInt64Array()
	SECTOR_OF_CELL = PackedInt64Array()
	for r: int in JWUnits.R:
		for sec: int in JWUnits.S:
			REGION_OF_CELL.append(r)
			SECTOR_OF_CELL.append(sec)
	REGION_OF_GROUP = PackedInt64Array()
	AGE_OF_GROUP = PackedInt64Array()
	SKILL_OF_GROUP = PackedInt64Array()
	for r2: int in JWUnits.R:
		for a: int in JWUnits.A:
			for k: int in JWUnits.K:
				REGION_OF_GROUP.append(r2)
				AGE_OF_GROUP.append(a)
				SKILL_OF_GROUP.append(k)

const AGENT_CELL_BASE: int = 1
static var AGENT_PUBSERV_BASE: int = 17
static var AGENT_GROUP_BASE: int = 21
static var AGENT_INVPOOL: int = 57
static var AGENT_ROW: int = 58
static var AGENT_OPENING: int = 59

## 现金主体口径（docs/10 §2.1 与 OQ-217 的合并）。
## 全部主体减去 4 个 pubserv（pubserv 无自有现金，其支付由 gov 执行）。
## INV-018（Σ cash == scenario.total_cash_uu）对这 56 个 cash 科目求和。
static var AGENT_CASH_ACCOUNTS: int = 56
## docs/10 §2.1 的「持有现金的主体共 55 个」口径：不含 agent.opening ——
## 其 cash 科目存在但开账后恒为 0（OQ-217）。agent.opening.cash 恒为 0 不影响 INV-018 求和，
## 但必须参与求和 —— 否则「恒为 0」这件事就没人检查了（T-U-OPENING-BALANCE）。
static var AGENT_CASH_ACTIVE: int = 55

# ── 科目（account code）下标布局（docs/17 §2.4）—— 15 个 ───────────────────
#
#  0 cash            1 inv.agri        2 inv.manu       3 inv.energy     4 inv.services
#  5 wip             6 capital         7 housing        8 recv           9 bondhold
# 10 deposit_claim  11 pay            12 debt          13 deposit_liab  14 nw
#
# 方向约定：资产科目（0..10）余额为正表示资产，负债科目（11..13）余额为正表示负债；
# nw 是平衡项，由 JWLedger 在每次 post() 内同步维护，不是独立可写字段（docs/10 §2.2）。

const ACC_CASH: int = 0
## ACC_INV_BASE + sector
const ACC_INV_BASE: int = 1
const ACC_WIP: int = 5
const ACC_CAPITAL: int = 6
const ACC_HOUSING: int = 7
const ACC_RECV: int = 8
const ACC_BONDHOLD: int = 9
const ACC_DEPOSIT_CLAIM: int = 10
const ACC_PAY: int = 11
const ACC_DEBT: int = 12
const ACC_DEPOSIT_LIAB: int = 13
const ACC_NW: int = 14

# ── 反解查找表（docs/10 §0.5 的下标布局取逆） ──────────────────────────────
#
# 用查表而不是除法：JWIds 的依赖秩与 JWMath 相同，不得互相引用（docs/17 §3.2），
# 因此这里既不能调 JWMath.floor_div，也不许出现裸 `/`（INV-002）。
# 表是布局的机器化冗余：一旦有人改了 idx_cell / idx_group，T-U-IDS 的往返测试立刻红。

## cell → region，长度 JWUnits.CELL
static var REGION_OF_CELL: PackedInt64Array = [
	0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
]
## cell → sector，长度 JWUnits.CELL
static var SECTOR_OF_CELL: PackedInt64Array = [
	0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3,
]
## group → region，长度 JWUnits.GROUP
static var REGION_OF_GROUP: PackedInt64Array = [
	0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1,
	1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2,
	2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3,
]
## group → age，长度 JWUnits.GROUP
static var AGE_OF_GROUP: PackedInt64Array = [
	0, 0, 0, 1, 1, 1, 2, 2, 2, 0, 0, 0,
	1, 1, 1, 2, 2, 2, 0, 0, 0, 1, 1, 1,
	2, 2, 2, 0, 0, 0, 1, 1, 1, 2, 2, 2,
]
## group → skill，长度 JWUnits.GROUP
static var SKILL_OF_GROUP: PackedInt64Array = [
	0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2,
	0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2,
	0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2,
]

# ── 成员变量 ───────────────────────────────────────────────────────────────

## "<kind>:<id>" → int，加载期专用。freeze() 之后不得再查。写入者：LOAD
var _id_to_index: Dictionary = {}
## 反查，用于写故障包与报告。按 kind 预分配。写入者：LOAD
var _index_to_id: Array[PackedStringArray] = []
## freeze() 后禁止再解析字符串。写入者：LOAD
var _frozen: bool = false
## 每个 kind 的实际登记条数，长度 ID_KIND_N。写入者：LOAD
##
## 不用 _index_to_id[kind].size() 代替：那是「最大下标 + 1」，中间留空洞时会把
## 「只登记了 1 个」误判成「登记满了」，freeze() 的齐全性检查就成了摆设。
var _count: PackedInt64Array = PackedInt64Array()

## ID 正则，编译一次复用。只在 LOAD 期被调用。
static var _id_re: RegEx = null


func _init() -> void:
	_index_to_id.resize(ID_KIND_N)
	for k: int in ID_KIND_N:
		_index_to_id[k] = PackedStringArray()
	_count.resize(ID_KIND_N)


## 惰性编译 ID 正则。加载期一次，此后命中缓存。
static func _re() -> RegEx:
	if _id_re == null:
		_id_re = RegEx.create_from_string(ID_PATTERN)
	return _id_re


## 映射表的键。kind 进键是为了让同名 id 能在不同 kind 下共存（例如 sector.agri 与 cell 的段名）。
static func _key(kind: int, id: String) -> String:
	return "%d:%s" % [kind, id]

# ── 映射表方法（只在 LOAD 期可用） ─────────────────────────────────────────

## 登记一个稳定 ID 与它的稠密下标。
## 步骤：LOAD
## 前置：!_frozen；id 匹配 docs/10 §0.4 的正则；同 kind 内 id 不重复
## 后置：resolve(kind, id) == index 且 id_of(kind, index) == id
## 不变量：INV-010（运行期 ID 只来自单调计数器，本函数不生成 ID，只登记）
## 失败：重复 → Load.DUP_ID；格式不符 → Load.ID_FORMAT；已冻结 → Fault.PHASE_VIOLATION
func register(kind: int, id: String, index: int) -> JWResult:
	if _frozen:
		JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, kind, index)
		return JWResult.make_err(JWResult.Fault.PHASE_VIOLATION, kind, index)
	if kind < 0 or kind >= ID_KIND_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, kind, ID_KIND_N)
		return JWResult.make_err(JWResult.Fault.INDEX_OUT_OF_RANGE, kind, ID_KIND_N)
	if index < 0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, index, 0)
		return JWResult.make_err(JWResult.Fault.INDEX_OUT_OF_RANGE, index, 0)
	if _re().search(id) == null:
		return JWResult.make_err(JWResult.Load.ID_FORMAT, kind, index)

	var key: String = _key(kind, id)
	if _id_to_index.has(key):
		return JWResult.make_err(JWResult.Load.DUP_ID, kind, index)

	var arr: PackedStringArray = _index_to_id[kind]
	# 同一 kind 的同一下标被两个 ID 占用会打破双射，与 ID 重复同罪。
	if index < arr.size() and arr[index] != "":
		return JWResult.make_err(JWResult.Load.DUP_ID, kind, index)
	if index >= arr.size():
		arr.resize(index + 1)
	arr[index] = id
	_index_to_id[kind] = arr
	_id_to_index[key] = index
	_count[kind] = _count[kind] + 1
	return JWResult.make_ok()


## 字符串 ID → 稠密下标。结算期调用即故障。
## 步骤：LOAD
## 前置：!_frozen
## 后置：不改状态
## 不变量：docs/10 §0.6（运行期不使用 Dictionary 键查找）
## 失败：未登记 → 返回 -1；已冻结 → raise_fault(PHASE_VIOLATION) 返回 -1
func resolve(kind: int, id: String) -> int:
	if _frozen:
		JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, kind, 0)
		return -1
	if kind < 0 or kind >= ID_KIND_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, kind, ID_KIND_N)
		return -1
	# 未登记返回 -1 而不是故障：加载期「这个 ID 在不在表里」是正常的询问。
	return int(_id_to_index.get(_key(kind, id), -1))


## 稠密下标 → 字符串 ID。只用于故障包、存档 SoA 的 ids[]、报告模板取键。
## 步骤：LOAD / 存档 / 故障包（不在热路径）
## 前置：index 在该 kind 的范围内
## 后置：不改状态
## 不变量：INV-010
## 失败：越界返回空串并登记 INDEX_OUT_OF_RANGE
func id_of(kind: int, index: int) -> String:
	# 不看 _frozen：故障包与存档恰恰是在冻结之后才写的，反查必须一直可用。
	if kind < 0 or kind >= ID_KIND_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, kind, ID_KIND_N)
		return ""
	var arr: PackedStringArray = _index_to_id[kind]
	if index < 0 or index >= arr.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, index, arr.size())
		return ""
	return arr[index]


## 某个 kind 已登记的条数（加载流水线自检与 freeze 用）。
## 步骤：LOAD
## 前置：kind ∈ [0, ID_KIND_N)
## 后置：不改状态
## 不变量：INV-142
## 失败：kind 越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回 0
func count_of(kind: int) -> int:
	if kind < 0 or kind >= ID_KIND_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, kind, ID_KIND_N)
		return 0
	return _count[kind]


## 是否已冻结。
## 步骤：LOAD / 测试
## 前置：无
## 后置：不改状态
## 不变量：docs/10 §0.6
## 失败：无
func is_frozen() -> bool:
	return _frozen


## 冻结映射表。加载流水线的最后一步调用；此后 SimCore 进入「零字符串」状态。
## 步骤：LOAD 末
## 前置：全部 kind 的登记数量等于 docs/17 §2.1 的维度常量（CELL==16、GROUP==36…）
## 后置：_frozen == true
## 不变量：INV-142（群组齐全）、docs/10 §0.6
## 失败：数量不符 → Load.GROUP_SET / Load.CELL_SET / Load.REGION_SET
##
## 只核对契约点名了错误码的三个 kind（REGION / CELL / GROUP）。其余 kind 的基数
## 由 systems/content_loader 按 docs/11 §7 各自的 E_* 码校验，此处不重复一套口径；
## BOND 与 PROJECT 本就是运行期增长的 SoA，没有固定基数可核。
func freeze() -> JWResult:
	if _frozen:
		# 重复冻结是加载流水线的顺序错误，不是可以吞掉的幂等操作。
		JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, ID_KIND_N, 0)
		return JWResult.make_err(JWResult.Fault.PHASE_VIOLATION, ID_KIND_N, 0)
	var n_region: int = _count[IdKind.REGION]
	if n_region != JWUnits.R:
		return JWResult.make_err(JWResult.Load.REGION_SET, JWUnits.R, n_region)
	var n_cell: int = _count[IdKind.CELL]
	if n_cell != JWUnits.CELL:
		return JWResult.make_err(JWResult.Load.CELL_SET, JWUnits.CELL, n_cell)
	var n_group: int = _count[IdKind.GROUP]
	if n_group != JWUnits.GROUP:
		return JWResult.make_err(JWResult.Load.GROUP_SET, JWUnits.GROUP, n_group)
	_frozen = true
	return JWResult.make_ok()

# ── 索引函数（docs/17 §2.2，全部 static、O(1)、无分支、无除法） ─────────────
#
# 步骤：全部
# 前置：各参数在其维度范围内
# 后置：返回稠密下标
# 不变量：docs/10 §0.5（下标布局是契约的一部分）
# 失败：debug 构建断言范围；release 构建越界由数组访问自身报 INDEX_OUT_OF_RANGE

## r * 4 + s，值域 0..15
static func idx_cell(r: int, s: int) -> int:
	return r * JWUnits.S + s


## r * 9 + a * 3 + k，值域 0..35
static func idx_group(r: int, a: int, k: int) -> int:
	return r * (JWUnits.A * JWUnits.K) + a * JWUnits.K + k


## s_from * 4 + s_to，值域 0..15
static func idx_io(s_from: int, s_to: int) -> int:
	return s_from * JWUnits.S + s_to


## cell * 4 + s_in，值域 0..63
static func idx_inv(cell: int, s_in: int) -> int:
	return cell * JWUnits.S + s_in


## cell * 3 + k，值域 0..47
static func idx_emp(cell: int, k: int) -> int:
	return cell * JWUnits.K + k


## r_from * 4 + r_to，值域 0..15
static func idx_od(r_from: int, r_to: int) -> int:
	return r_from * JWUnits.R + r_to


## g * 5 + slot，值域 0..179（slot == 4 为 pubserv）
static func idx_group_emp(g: int, slot: int) -> int:
	return g * (JWUnits.S + 1) + slot


## g * 3 + kind，值域 0..107
static func idx_group_svc(g: int, kind: int) -> int:
	return g * JWUnits.SERVICE_KIND + kind


## g * 4 + s，值域 0..143
static func idx_group_prod(g: int, s: int) -> int:
	return g * JWUnits.S + s


## g * 8 + slot，值域 0..287
static func idx_edu(g: int, slot: int) -> int:
	return g * JWUnits.EDU_SLOT + slot


## r * 3 + k，值域 0..11
static func idx_pubserv_emp(r: int, k: int) -> int:
	return r * JWUnits.K + k


## r * 3 + kind，值域 0..11
static func idx_pubserv_queue(r: int, kind: int) -> int:
	return r * JWUnits.SERVICE_KIND + kind


## s * 5 + buyer，值域 0..19
static func idx_market(s: int, buyer: int) -> int:
	return s * JWUnits.BUYER_CLASS_N + buyer


## p * 4 + j，值域 0..47
static func idx_policy_param(p: int, j: int) -> int:
	return p * POLICY_PARAM_STRIDE + j


## b * 12 + p，值域 0..35
static func idx_stance(b: int, p: int) -> int:
	return b * JWUnits.POLICY_N + p


## g * 3 + b，值域 0..107
static func idx_affil(g: int, b: int) -> int:
	return g * JWUnits.BLOC_N + b


## r * 3 + kind，值域 0..11
static func idx_opex(r: int, kind: int) -> int:
	return r * JWUnits.SERVICE_KIND + kind


## agent * 15 + code，值域 0..899
static func idx_account(agent: int, code: int) -> int:
	return agent * JWUnits.ACCOUNT_CODE_N + code

# ── 反解（报告与写日志时用；结算算式里不用） ───────────────────────────────

## cell → region
static func region_of_cell(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	return REGION_OF_CELL[cell]


## cell → sector
static func sector_of_cell(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	return SECTOR_OF_CELL[cell]


## group → region
static func region_of_group(g: int) -> int:
	if g < 0 or g >= JWUnits.GROUP:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, g, JWUnits.GROUP)
		return 0
	return REGION_OF_GROUP[g]


## group → age
static func age_of_group(g: int) -> int:
	if g < 0 or g >= JWUnits.GROUP:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, g, JWUnits.GROUP)
		return 0
	return AGE_OF_GROUP[g]


## group → skill
static func skill_of_group(g: int) -> int:
	if g < 0 or g >= JWUnits.GROUP:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, g, JWUnits.GROUP)
		return 0
	return SKILL_OF_GROUP[g]

# ── 主体下标换算（docs/17 §2.3） ───────────────────────────────────────────

## AGENT_CELL_BASE + cell
static func agent_of_cell(cell: int) -> int:
	return AGENT_CELL_BASE + cell


## AGENT_PUBSERV_BASE + r
static func agent_of_pubserv(r: int) -> int:
	return AGENT_PUBSERV_BASE + r


## AGENT_GROUP_BASE + g
static func agent_of_group(g: int) -> int:
	return AGENT_GROUP_BASE + g


## 非 cell 主体返回 -1
static func cell_of_agent(a: int) -> int:
	if a < AGENT_CELL_BASE or a >= AGENT_PUBSERV_BASE:
		return -1
	return a - AGENT_CELL_BASE


## 非 group 主体返回 -1
static func group_of_agent(a: int) -> int:
	if a < AGENT_GROUP_BASE or a >= AGENT_INVPOOL:
		return -1
	return a - AGENT_GROUP_BASE
