## 建筑堆：生产单元产能与资本的唯一来源（docs/18 R-BUILDING-01；docs/53 M1-5）。
##
## 一行 == 一个「堆」：地区 × 建筑类型 × 所有者 × 生产方式，记等级、在用 / 待投运产能、资本价值、状况与首建季。
## `JWCapital` 的 cell 数组（在用产能、待投运产能、资本价值）从 R-BUILDING-01 起是本表按 cell 求和的结果，
## 只由 `JWCapital.sync_cells_from_buildings()` 写；产能与资本的一切增减都先落到某个堆上。
##
## M1 只有「既有设施」一种类型：载入时每个 cell 一个堆，吸收剧本给出的全部产能与资本；
## 企业购置、项目完工、折旧、在建转资本都作用在该 cell 的缺省堆上。单堆时的算术与此前逐 cell 的算术逐位相同。
## M2 起加入建筑类型、生产方式与所有者，一个 cell 可以有多个堆。
##
## 依赖秩与其他状态块相同：只依赖 JWUnits / JWMath / JWResult / JWIds。
class_name JWBuildings
extends RefCounted

# ── §1.6 状态块协议 ─────────────────────────────────────────────────────────

const STATE_ARRAY_IDS: PackedStringArray = [
	"state.building.cell",
	"state.building.type",
	"state.building.owner",
	"state.building.method",
	"state.building.level",
	"state.building.capacity_active_uqs_per_q",
	"state.building.capacity_pending_uqs_per_q",
	"state.building.capital_value_uu",
	"state.building.condition_ppm",
	"state.building.first_built_q",
	"state.building.entity",
]
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
]
const STATE_SCALAR_IDS: PackedStringArray = ["state.building.count"]
const STATE_SCALAR_SUBSYS: PackedInt64Array = [JWUnits.SUBSYS_CELL]
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_ARRAY_SUBSYS: PackedInt64Array = []
const FLOW_SCALAR_IDS: PackedStringArray = []
const FLOW_SCALAR_SUBSYS: PackedInt64Array = []

## 堆表容量。
const CAP0: int = 256

## 建筑类型 0：既有设施（载入期从剧本的 cell 产能与资本迁移而来）。
const TYPE_LEGACY: int = 0
## 所有者：0 == 该 cell 的企业（私人），1 == 政府。M1 只有 0。
const OWNER_PRIVATE: int = 0
const OWNER_GOV: int = 1
## 生产方式 0：既有方式（系数即剧本投入产出表）。
const METHOD_LEGACY: int = 0

# ── 状态 ───────────────────────────────────────────────────────────────────

var count: int = 0
var cell: PackedInt64Array = PackedInt64Array()
var type: PackedInt64Array = PackedInt64Array()
var owner: PackedInt64Array = PackedInt64Array()
var method: PackedInt64Array = PackedInt64Array()
var level: PackedInt64Array = PackedInt64Array()
var capacity_active: PackedInt64Array = PackedInt64Array()
var capacity_pending: PackedInt64Array = PackedInt64Array()
var capital_value: PackedInt64Array = PackedInt64Array()
var condition_ppm: PackedInt64Array = PackedInt64Array()
var first_built_q: PackedInt64Array = PackedInt64Array()
var entity: PackedInt64Array = PackedInt64Array()


func allocate() -> void:
	count = 0
	# 逐个成员 resize：Packed 数组放进 Array 再改只改到副本（值语义），不能用循环代劳。
	cell = _zeros(CAP0)
	type = _zeros(CAP0)
	owner = _zeros(CAP0)
	method = _zeros(CAP0)
	level = _zeros(CAP0)
	capacity_active = _zeros(CAP0)
	capacity_pending = _zeros(CAP0)
	capital_value = _zeros(CAP0)
	condition_ppm = _zeros(CAP0)
	first_built_q = _zeros(CAP0)
	entity = _zeros(CAP0)
	entity.fill(-1)


static func _zeros(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(0)
	return a


# ── 规则 ───────────────────────────────────────────────────────────────────

## 新建一个堆。返回行号；表满返回 −1 并登记故障。
func add_stack(c: int, type_i: int, owner_i: int, method_i: int, level_i: int, cap_active: int,
		capital_uu: int, q: int, entity_i: int) -> int:
	if c < 0 or c >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, c, JWUnits.CELL)
		return -1
	if count >= CAP0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, count, CAP0)
		return -1
	var b: int = count
	cell[b] = c
	type[b] = type_i
	owner[b] = owner_i
	method[b] = method_i
	level[b] = level_i
	capacity_active[b] = cap_active
	capacity_pending[b] = 0
	capital_value[b] = capital_uu
	condition_ppm[b] = JWUnits.PPM
	first_built_q[b] = q
	entity[b] = entity_i
	count += 1
	return b


## 某 cell 的缺省堆（私人所有的第一个堆）；没有返回 −1。
## M1 每个 cell 恰有一个既有设施堆，所以企业购置、项目完工、折旧都落在它上面。
func default_stack(c: int) -> int:
	var b: int = 0
	while b < count:
		if cell[b] == c and owner[b] == OWNER_PRIVATE:
			return b
		b += 1
	return -1


## 载入期迁移（R-BUILDING-01）：每个 cell 建一个既有设施堆，吸收剧本给出的在用产能与资本价值。
## 前置：本表为空；cap / value 长 CELL
## 后置：count == CELL，第 c 行对应 cell c
func seed_legacy(cap: PackedInt64Array, value: PackedInt64Array) -> int:
	if cap.size() != JWUnits.CELL or value.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cap.size(), JWUnits.CELL)
	allocate()
	for c: int in JWUnits.CELL:
		# 开局设施的实体号取 −(cell+1)，与运行期从 0 起的 entity_seq 不相交（同 R-CAP-01 的开局存量债）。
		if add_stack(c, TYPE_LEGACY, OWNER_PRIVATE, METHOD_LEGACY, 1, cap[c], value[c], -1, -(c + 1)) < 0:
			return JWResult.pending_code()
	return JWResult.OK


## 按 cell 求和：在用产能、待投运产能、资本价值。写进调用方给的三个长 CELL 数组（先清零）。
func sum_by_cell(out_active: PackedInt64Array, out_pending: PackedInt64Array,
		out_value: PackedInt64Array) -> void:
	out_active.fill(0)
	out_pending.fill(0)
	out_value.fill(0)
	var b: int = 0
	while b < count:
		var c: int = cell[b]
		out_active[c] += capacity_active[b]
		out_pending[c] += capacity_pending[b]
		out_value[c] += capital_value[b]
		b += 1


# ── §1.6 状态块协议 ─────────────────────────────────────────────────────────

func state_array(i: int) -> PackedInt64Array:
	match i:
		0: return cell
		1: return type
		2: return owner
		3: return method
		4: return level
		5: return capacity_active
		6: return capacity_pending
		7: return capital_value
		8: return condition_ppm
		9: return first_built_q
		10: return entity
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	if v.size() != CAP0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), CAP0)
	var d: PackedInt64Array = v.duplicate()
	match i:
		0: cell = d
		1: type = d
		2: owner = d
		3: method = d
		4: level = d
		5: capacity_active = d
		6: capacity_pending = d
		7: capital_value = d
		8: condition_ppm = d
		9: first_built_q = d
		10: entity = d
	return JWResult.OK


func state_scalar(i: int) -> int:
	if i == 0:
		return count
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


func set_state_scalar(i: int, v: int) -> int:
	if i != 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	count = v
	return JWResult.OK


func flow_array(i: int) -> PackedInt64Array:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)
	return PackedInt64Array()


func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, 0)
	return 0


func reset_flows() -> void:
	pass


func flow_abs_sum() -> int:
	return 0
