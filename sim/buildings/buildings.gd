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
	# R-METHOD-01：改造期间冻结的产能份额（ppm）。改造完成即清零。
	"state.building.frozen_ppm",
	# ── 内容表：建筑类型（下标 0 == 既有设施，内容卡从 1 起） ──
	"content.building.sector",
	"content.building.family",
	"content.building.unit_capacity_uqs",
	"content.building.cost_uu",
	"content.building.quarters",
	"content.building.opex_uu",
	"content.building.owners_mask",
	# ── 内容表：生产方式（下标 0 == 既有方式，倍率恒为 1e6） ──
	"content.method.building",
	"content.method.output_ppm",
	"content.method.elec_ppm",
	"content.method.material_ppm",
	"content.method.labor_ppm",
	"content.method.retrofit_cost_uu",
	"content.method.retrofit_quarters",
	"content.method.retrofit_frozen_ppm",
]
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	# 内容表（R-METHOD-01）：不进哈希与存档，随内容包载入。建筑类型 7 项、生产方式 8 项。
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
]
const STATE_SCALAR_IDS: PackedStringArray = [
	"state.building.count",
	"content.building.type_count",
	"content.method.count",
]
const STATE_SCALAR_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
]
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
## 生产方式 0：既有方式（系数即剧本投入产出表，倍率恒为 1 000 000）。
const METHOD_LEGACY: int = 0

## 建筑类型表与生产方式表的容量（M3 的十二家族 × 三变体留余量）。
const TYPE_CAP0: int = 64
const METHOD_CAP0: int = 128

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

# ── 内容表（content.*，不进哈希与存档） ───────────────────────────────────

var type_count: int = 1
var method_count: int = 1
var t_sector: PackedInt64Array = PackedInt64Array()
var t_family: PackedInt64Array = PackedInt64Array()
var t_unit_capacity: PackedInt64Array = PackedInt64Array()
var t_cost: PackedInt64Array = PackedInt64Array()
var t_quarters: PackedInt64Array = PackedInt64Array()
var t_opex: PackedInt64Array = PackedInt64Array()
var t_owners_mask: PackedInt64Array = PackedInt64Array()
var m_building: PackedInt64Array = PackedInt64Array()
var m_output_ppm: PackedInt64Array = PackedInt64Array()
var m_elec_ppm: PackedInt64Array = PackedInt64Array()
var m_material_ppm: PackedInt64Array = PackedInt64Array()
## 长 METHOD_CAP0 × K：method * K + skill。
var m_labor_ppm: PackedInt64Array = PackedInt64Array()
var m_retrofit_cost: PackedInt64Array = PackedInt64Array()
var m_retrofit_quarters: PackedInt64Array = PackedInt64Array()
var m_retrofit_frozen: PackedInt64Array = PackedInt64Array()
## state.building.frozen_ppm —— 改造期间冻结的产能份额。写入者 S02（开工）、S07（完工清零）
var frozen_ppm: PackedInt64Array = PackedInt64Array()


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
	type_count = 1
	method_count = 1
	t_sector = _zeros(TYPE_CAP0)
	t_family = _zeros(TYPE_CAP0)
	t_unit_capacity = _zeros(TYPE_CAP0)
	t_cost = _zeros(TYPE_CAP0)
	t_quarters = _zeros(TYPE_CAP0)
	t_opex = _zeros(TYPE_CAP0)
	t_owners_mask = _zeros(TYPE_CAP0)
	m_building = _zeros(METHOD_CAP0)
	m_output_ppm = _ppm_filled(METHOD_CAP0)
	m_elec_ppm = _ppm_filled(METHOD_CAP0)
	m_material_ppm = _ppm_filled(METHOD_CAP0)
	m_labor_ppm = _ppm_filled(METHOD_CAP0 * JWUnits.K)
	m_retrofit_cost = _zeros(METHOD_CAP0)
	m_retrofit_quarters = _zeros(METHOD_CAP0)
	m_retrofit_frozen = _zeros(METHOD_CAP0)
	frozen_ppm = _zeros(CAP0)


static func _ppm_filled(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(JWUnits.PPM)
	return a


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


## 按稳定实体号找堆；没有返回 −1。
func stack_of_entity(e: int) -> int:
	var b: int = 0
	while b < count:
		if entity[b] == e:
			return b
		b += 1
	return -1


## 找到匹配的堆（同一 cell、类型、所有者、方式）；没有返回 −1。
func find_stack(c: int, type_i: int, owner_i: int, method_i: int) -> int:
	var b: int = 0
	while b < count:
		if cell[b] == c and type[b] == type_i and owner[b] == owner_i and method[b] == method_i:
			return b
		b += 1
	return -1


## 载入期迁移（R-BUILDING-01）：每个 cell 建一个既有设施堆，吸收剧本给出的在用产能与资本价值。
## 前置：本表为空；cap / value 长 CELL
## 后置：count == CELL，第 c 行对应 cell c
func seed_legacy(cap: PackedInt64Array, value: PackedInt64Array) -> int:
	if cap.size() != JWUnits.CELL or value.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cap.size(), JWUnits.CELL)
	# 只清状态行，**不碰内容表**：建筑类型卡与方式卡在本函数之前已经载入（allocate() 会把它们一起抹掉）。
	count = 0
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
	frozen_ppm = _zeros(CAP0)
	for c: int in JWUnits.CELL:
		# 开局设施的实体号取 −(cell+1)，与运行期从 0 起的 entity_seq 不相交（同 R-CAP-01 的开局存量债）。
		if add_stack(c, TYPE_LEGACY, OWNER_PRIVATE, METHOD_LEGACY, 1, cap[c], value[c], -1, -(c + 1)) < 0:
			return JWResult.pending_code()
	return JWResult.OK


## R-OWNER-01：某生产单元里政府所有的有效产能份额（ppm）。没有产能时返回 0。
func gov_share_ppm(c: int) -> int:
	var total: int = 0
	var gov: int = 0
	var b: int = 0
	while b < count:
		if cell[b] == c:
			var w: int = effective_capacity(b)
			total += w
			if owner[b] == OWNER_GOV:
				gov += w
		b += 1
	if total <= 0:
		return 0
	# rounding: floor, reason=份额只取整一次，少划给政府优于多划
	return JWMath.mul_div_floor(gov, JWUnits.PPM, total)


## 按 cell 求和：在用产能、待投运产能、资本价值。写进调用方给的三个长 CELL 数组（先清零）。
func sum_by_cell(out_active: PackedInt64Array, out_pending: PackedInt64Array,
		out_value: PackedInt64Array) -> void:
	out_active.fill(0)
	out_pending.fill(0)
	out_value.fill(0)
	var b: int = 0
	while b < count:
		var c: int = cell[b]
		# R-METHOD-01：生产方式的产出倍率折进有效产能（既有方式恒为 1e6，旧剧本逐位不变）。
		out_active[c] += effective_capacity(b)
		out_pending[c] += JWMath.mul_ppm(capacity_pending[b], output_ppm_of(b))
		out_value[c] += capital_value[b]
		b += 1


## 某堆的产出倍率（越界或既有方式为 1e6）。
func output_ppm_of(b: int) -> int:
	var m: int = method[b]
	if m <= 0 or m >= m_output_ppm.size():
		return JWUnits.PPM
	return m_output_ppm[m]


## 某堆的有效在用产能（已按产出倍率折算）。
func effective_capacity(b: int) -> int:
	var cap: int = JWMath.mul_ppm(capacity_active[b], output_ppm_of(b))
	var fr: int = frozen_ppm[b] if b < frozen_ppm.size() else 0
	if fr > 0:
		# 改造期间冻结一部分产能（R-METHOD-01）：资产不减，只是本季用不上。
		cap = JWMath.mul_ppm(cap, maxi(0, JWUnits.PPM - fr))
	return cap


## R-METHOD-01：按 cell 汇总生产方式倍率（以各堆有效产能加权）。
## out_labor 长 EMP_N、out_input 长 INV_N；没有堆或全是既有方式的 cell 留在 1 000 000。
## 步骤：S01（产能转入之后）
func cell_multipliers_into(out_labor: PackedInt64Array, out_input: PackedInt64Array) -> void:
	out_labor.fill(JWUnits.PPM)
	out_input.fill(JWUnits.PPM)
	if method_count <= 1 or count == 0:
		return
	for c: int in JWUnits.CELL:
		var wsum: int = 0
		var b: int = 0
		while b < count:
			if cell[b] == c:
				wsum += effective_capacity(b)
			b += 1
		if wsum <= 0:
			continue
		for k: int in JWUnits.K:
			var acc_l: int = 0
			var b2: int = 0
			while b2 < count:
				if cell[b2] == c:
					var w: int = effective_capacity(b2)
					if w > 0:
						acc_l += JWMath.mul_div_floor(w, _labor_ppm_of(b2, k), wsum)
				b2 += 1
			out_labor[JWIds.idx_emp(c, k)] = maxi(1, acc_l)
		for j: int in JWUnits.S:
			var acc_i: int = 0
			var b3: int = 0
			while b3 < count:
				if cell[b3] == c:
					var w2: int = effective_capacity(b3)
					if w2 > 0:
						acc_i += JWMath.mul_div_floor(w2, _input_ppm_of(b3, j), wsum)
				b3 += 1
			out_input[JWIds.idx_inv(c, j)] = maxi(1, acc_i)


func _labor_ppm_of(b: int, k: int) -> int:
	var m: int = method[b]
	if m <= 0:
		return JWUnits.PPM
	var i: int = m * JWUnits.K + k
	if i >= m_labor_ppm.size():
		return JWUnits.PPM
	return m_labor_ppm[i]


func _input_ppm_of(b: int, j: int) -> int:
	var m: int = method[b]
	if m <= 0:
		return JWUnits.PPM
	if j == JWUnits.Sector.ENERGY:
		return m_elec_ppm[m] if m < m_elec_ppm.size() else JWUnits.PPM
	return m_material_ppm[m] if m < m_material_ppm.size() else JWUnits.PPM


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
		11: return frozen_ppm
		12: return t_sector
		13: return t_family
		14: return t_unit_capacity
		15: return t_cost
		16: return t_quarters
		17: return t_opex
		18: return t_owners_mask
		19: return m_building
		20: return m_output_ppm
		21: return m_elec_ppm
		22: return m_material_ppm
		23: return m_labor_ppm
		24: return m_retrofit_cost
		25: return m_retrofit_quarters
		26: return m_retrofit_frozen
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	var want: int = CAP0
	if i >= 12 and i <= 18:
		want = TYPE_CAP0
	elif i == 23:
		want = METHOD_CAP0 * JWUnits.K
	elif i >= 19:
		want = METHOD_CAP0
	if v.size() != want:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), want)
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
		11: frozen_ppm = d
		12: t_sector = d
		13: t_family = d
		14: t_unit_capacity = d
		15: t_cost = d
		16: t_quarters = d
		17: t_opex = d
		18: t_owners_mask = d
		19: m_building = d
		20: m_output_ppm = d
		21: m_elec_ppm = d
		22: m_material_ppm = d
		23: m_labor_ppm = d
		24: m_retrofit_cost = d
		25: m_retrofit_quarters = d
		26: m_retrofit_frozen = d
	return JWResult.OK


func state_scalar(i: int) -> int:
	if i == 0:
		return count
	if i == 1:
		return type_count
	if i == 2:
		return method_count
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


func set_state_scalar(i: int, v: int) -> int:
	if i == 0:
		count = v
	elif i == 1:
		type_count = v
	elif i == 2:
		method_count = v
	else:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
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
