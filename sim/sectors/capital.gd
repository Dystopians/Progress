## 全部「能力存量」的唯一持有者：cell 产能与资本、pubserv 容量与可用率、
## 地区设施（电网 / 港口 / 灌溉 / 住房 / 施工槽位）、排放与环境存量。
##
## 放在一个文件里的理由是纪律性的：docs/12 §01.4 要求一切「完工后才生效的能力」
## 都必须经 *_pending_* 缓冲且只在 S01 转入（INV-054/091）。这条规则只有在
## 「全部 pending → active 的转移写在同一个函数里」时才可被静态检查。
##
## 骨架依据：docs/17_api_skeleton.md §4.13。依赖秩 4，只允许引用秩 ≤3。
class_name JWCapital
extends RefCounted

## §1.6 状态块协议：本块各数组所属子系统（与 STATE_ARRAY_IDS 等长）。
## cell_* 归 SUBSYS_CELL、pub_* 归 SUBSYS_PUBSERV、其余归 SUBSYS_REGION；
## content.region.area_index 是内容包数据，归 SUBSYS_META（不进 state_hash）。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_PUBSERV, JWUnits.SUBSYS_PUBSERV, JWUnits.SUBSYS_PUBSERV,
	JWUnits.SUBSYS_PUBSERV, JWUnits.SUBSYS_PUBSERV, JWUnits.SUBSYS_PUBSERV,
	JWUnits.SUBSYS_REGION, JWUnits.SUBSYS_REGION, JWUnits.SUBSYS_REGION,
	JWUnits.SUBSYS_REGION, JWUnits.SUBSYS_REGION, JWUnits.SUBSYS_REGION,
	JWUnits.SUBSYS_REGION, JWUnits.SUBSYS_REGION, JWUnits.SUBSYS_REGION,
	JWUnits.SUBSYS_REGION, JWUnits.SUBSYS_REGION, JWUnits.SUBSYS_REGION,
	JWUnits.SUBSYS_META,
]

## 稳定 ID 注册表：下标 == 数组序号；顺序是 schema 的一部分，重排即破坏性变更（INV-136）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.cell.capacity_active_uqs_per_q",
	"state.cell.capacity_pending_uqs_per_q",
	"state.cell.capital_value_uu",
	"state.cell.wip_uu",
	"state.cell.maintenance_backlog_ppm",
	"state.pubserv.capacity_active_uqs_per_q",
	"state.pubserv.capacity_pending_uqs_per_q",
	"state.pubserv.capital_value_uu",
	"state.pubserv.availability_ppm",
	"state.pubserv.teachers_persons",
	"state.pubserv.health_staff_persons",
	"state.region.grid_capacity_uqs_per_q",
	"state.region.grid_capacity_pending_uqs_per_q",
	"state.region.housing_capacity_units",
	"state.region.housing_stock_units",
	"state.region.housing_pending_units",
	"state.region.irrigation_index_ppm",
	"state.region.irrigation_index_pending_ppm",
	"state.region.port_capacity_uqs_per_q",
	"state.region.port_capacity_pending_uqs_per_q",
	"state.region.construction_slots_total",
	"state.region.emissions_stock_uqe",
	"state.region.env_exposure_ppm",
	"content.region.area_index",
]
const STATE_SCALAR_IDS: PackedStringArray = []
const FLOW_ARRAY_IDS: PackedStringArray = [
	"flow.cell.depreciation_uu",
	"flow.cell.depreciation_uqs_per_q",
	"flow.cell.investment_uu",
	"flow.pubserv.funding_ratio_ppm",
	"flow.pubserv.depreciation_uu",
	"flow.pubserv.output_uu",
	"flow.region.emissions_uqe",
]
const FLOW_SCALAR_IDS: PackedStringArray = []

# ── 契约常量（docs/12 §01.4 / §7.9 的区间上界；只在本文件内使用） ───────────

## state.region.irrigation_index_ppm 的上界（docs/10 §7：0..2 000 000）
const IRRIGATION_MAX_PPM: int = 2_000_000
## state.region.env_exposure_ppm 的上界（docs/10 §7：0..3 000 000）
const ENV_EXPOSURE_MAX_PPM: int = 3_000_000
## STATE_ARRAY_IDS 中最后一个 cell 数组的下标（0..4 长度 CELL），set_state_array 的长度分段用
const LAST_CELL_STATE: int = 4
## STATE_ARRAY_IDS 中最后一个 pubserv 数组的下标（5..10 长度 PUBSERV）
const LAST_PUBSERV_STATE: int = 10

## state.cell.capacity_active_uqs_per_q[] —— 长度 16，初值剧本，μQ_s/季。类 S，写入者 **S01（转入）, S06（折旧）**。
## 两者不互相放大：S01 只做 active += pending（唯一增量写入点），S06 只做 active -= 折旧（唯一减量写入点）。
var cell_capacity_active: PackedInt64Array = PackedInt64Array()
## state.cell.capacity_pending_uqs_per_q[] —— 长度 16，初值 0，μQ_s/季。类 S，写入者 S07（完工写入）, S01（清零）。
var cell_capacity_pending: PackedInt64Array = PackedInt64Array()
## state.cell.capital_value_uu[] —— 长度 16，初值剧本，μU。类 S，写入者 S06（折旧）, S07（投运）。
var cell_capital_value: PackedInt64Array = PackedInt64Array()
## state.cell.wip_uu[] —— 长度 16，初值 0，μU。类 S，写入者 S05, S07。
var cell_wip: PackedInt64Array = PackedInt64Array()
## state.cell.maintenance_backlog_ppm[] —— 长度 16，初值 0，ppm。类 S，写入者 S07。
var cell_maint_backlog: PackedInt64Array = PackedInt64Array()
## flow.cell.depreciation_uu[] —— 长度 16，初值 0，μU。类 F，写入者 S06。
var f_cell_dep_uu: PackedInt64Array = PackedInt64Array()
## flow.cell.depreciation_uqs_per_q[] —— 长度 16，初值 0，μQ_s/季。类 F，写入者 S06。
var f_cell_dep_uqs: PackedInt64Array = PackedInt64Array()
## flow.cell.investment_uu[] —— 长度 16，初值 0，μU。类 F，写入者 S05。
var f_cell_investment: PackedInt64Array = PackedInt64Array()
## state.pubserv.capacity_active_uqs_per_q[] —— 长度 4，初值剧本，μQ_services/季。类 S，写入者 S01, S06。
var pub_capacity_active: PackedInt64Array = PackedInt64Array()
## state.pubserv.capacity_pending_uqs_per_q[] —— 长度 4，初值 0。类 S，写入者 S07, S01。
var pub_capacity_pending: PackedInt64Array = PackedInt64Array()
## state.pubserv.capital_value_uu[] —— 长度 4，初值剧本，μU。类 S，写入者 S06, S07。
var pub_capital_value: PackedInt64Array = PackedInt64Array()
## state.pubserv.availability_ppm[] —— 长度 4，初值 1 000 000，ppm。类 S，写入者 S07。
var pub_availability: PackedInt64Array = PackedInt64Array()
## state.pubserv.teachers_persons[] —— 长度 4，初值剧本，人。类 S，写入者 S03, S07。
var pub_teachers: PackedInt64Array = PackedInt64Array()
## state.pubserv.health_staff_persons[] —— 长度 4，初值剧本，人。类 S，写入者 S03, S07。
var pub_health_staff: PackedInt64Array = PackedInt64Array()
## flow.pubserv.funding_ratio_ppm[] —— 长度 4，初值 0，ppm。类 F，写入者 S04。
var f_pub_funding_ratio: PackedInt64Array = PackedInt64Array()
## flow.pubserv.depreciation_uu[] —— 长度 4，初值 0，μU。类 F，写入者 S06。
var f_pub_dep_uu: PackedInt64Array = PackedInt64Array()
## flow.pubserv.output_uu[] —— 长度 4，初值 0，μU。类 F，写入者 S06。
var f_pub_output: PackedInt64Array = PackedInt64Array()
## state.region.grid_capacity_uqs_per_q[] —— 长度 4，初值剧本，μQ_energy/季。类 S，写入者 S01, S06。
var grid_capacity: PackedInt64Array = PackedInt64Array()
## state.region.grid_capacity_pending_uqs_per_q[] —— 长度 4，初值 0。类 S，写入者 S07, S01。
var grid_pending: PackedInt64Array = PackedInt64Array()
## state.region.housing_capacity_units[] —— 长度 4，初值剧本，套。类 S，写入者 S01, S07。
var housing_capacity: PackedInt64Array = PackedInt64Array()
## state.region.housing_stock_units[] —— 长度 4，初值剧本，套。类 S，写入者 S01, S07。
var housing_stock: PackedInt64Array = PackedInt64Array()
## state.region.housing_pending_units[] —— 长度 4，初值 0，套。类 S，写入者 S07, S01。
var housing_pending: PackedInt64Array = PackedInt64Array()
## state.region.irrigation_index_ppm[] —— 长度 4，初值剧本，ppm。类 S，写入者 **S01（转入）**。
var irrigation_index: PackedInt64Array = PackedInt64Array()
## state.region.irrigation_index_pending_ppm[] —— 长度 4，初值 0，ppm。类 S，写入者 S07, S01。
var irrigation_pending: PackedInt64Array = PackedInt64Array()
## state.region.port_capacity_uqs_per_q[] —— 长度 4，初值剧本，μQ/季。类 S，写入者 S01, S06。
var port_capacity: PackedInt64Array = PackedInt64Array()
## state.region.port_capacity_pending_uqs_per_q[] —— 长度 4，初值 0。类 S，写入者 S07, S01。
var port_pending: PackedInt64Array = PackedInt64Array()
## state.region.construction_slots_total[] —— 长度 4，初值剧本 1..8，槽。类 S，写入者 S07。
var construction_slots: PackedInt64Array = PackedInt64Array()
## state.region.emissions_stock_uqe[] —— 长度 4，初值剧本，μQ_e。类 S，写入者 S07。
var emissions_stock: PackedInt64Array = PackedInt64Array()
## state.region.env_exposure_ppm[] —— 长度 4，初值剧本，ppm。类 S，写入者 S07。
var env_exposure: PackedInt64Array = PackedInt64Array()
## flow.region.emissions_uqe[] —— 长度 4，初值 0，μQ_e。类 F，写入者 S05。
var f_emissions: PackedInt64Array = PackedInt64Array()
## content.region.area_index[] —— 长度 4，初值剧本，指数。类 C，写入者 LOAD。
var area_index: PackedInt64Array = PackedInt64Array()

## R-BUILDING-01：建筑堆表（由 JWSimState.allocate_all 注入）。堆表非空时，cell 的在用 / 待投运产能与资本价值
## 是它按 cell 的求和，一切增减先落到堆上再由 sync_cells_from_buildings() 汇总；堆表为空（单独构造本块的
## 单元测试夹具）时退回逐 cell 的旧算术。
var buildings: JWBuildings = null


func _use_stacks() -> bool:
	return buildings != null and buildings.count > 0


## 从堆表汇总 cell 的三列（唯一写入点）。
func sync_cells_from_buildings() -> void:
	if _use_stacks():
		buildings.sum_by_cell(cell_capacity_active, cell_capacity_pending, cell_capital_value)


## 某 cell 的缺省堆；没有即故障（堆表非空时每个 cell 都应有既有设施堆）。
func _stack_of(cell: int) -> int:
	var b: int = buildings.default_stack(cell)
	if b < 0:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, buildings.count)
	return b


## R-METHOD-01：把一笔完工产能落到指定的建筑堆（没有就新建一堆）。只写待投运，S01 才转在用（INV-091）。
## 步骤：S07（投运）
## 前置：delta >= 0；cell 合法
## 后置：该堆的待投运产能增加、等级 +1；cell 三列由堆表重新汇总
func add_building_pending(cell: int, type_i: int, owner_i: int, method_i: int, delta: int,
		q: int, entity_seq: int) -> int:
	if not _use_stacks():
		return add_pending(4, cell, delta)
	if delta < 0:
		return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, type_i, delta)
	var b: int = buildings.find_stack(cell, type_i, owner_i, method_i)
	if b < 0:
		b = buildings.add_stack(cell, type_i, owner_i, method_i, 0, 0, 0, q, entity_seq)
		if b < 0:
			return JWResult.pending_code()
	buildings.capacity_pending[b] = JWMath.check_qty(buildings.capacity_pending[b] + delta)
	buildings.level[b] = buildings.level[b] + 1
	sync_cells_from_buildings()
	return JWResult.OK


## R-METHOD-01：改造完工——把某个堆切到新的生产方式并解冻产能。
func switch_stack_method(stack_entity: int, method_i: int) -> int:
	if not _use_stacks():
		return JWResult.OK
	var b: int = buildings.stack_of_entity(stack_entity)
	if b < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, stack_entity, buildings.count)
	buildings.method[b] = method_i
	buildings.frozen_ppm[b] = 0
	sync_cells_from_buildings()
	return JWResult.OK


## INV-B01（R-BUILDING-01）：cell 三列 == 堆表按 cell 求和。
func check_buildings_consistency() -> int:
	if not _use_stacks():
		return JWResult.OK
	var a: PackedInt64Array = PackedInt64Array()
	var p: PackedInt64Array = PackedInt64Array()
	var v: PackedInt64Array = PackedInt64Array()
	a.resize(JWUnits.CELL)
	p.resize(JWUnits.CELL)
	v.resize(JWUnits.CELL)
	buildings.sum_by_cell(a, p, v)
	for c: int in JWUnits.CELL:
		if a[c] != cell_capacity_active[c] or p[c] != cell_capacity_pending[c] or v[c] != cell_capital_value[c]:
			return JWResult.raise_fault(JWResult.Fault.STOCK_IDENTITY, c, a[c] - cell_capacity_active[c])
	return JWResult.OK


## capitalize_wip 的两腿结转缓冲（科目下标 / 有符号额）。不是状态、不进哈希；
## 声明处定长，热路径不新建数组（docs/17 §1.4）。
var _reclass_acc: PackedInt64Array = PackedInt64Array([0, 0])
var _reclass_delta: PackedInt64Array = PackedInt64Array([0, 0])


## R-INVEST-01：企业从市场购入的资本品入账。
## 步骤：S05 §5.6（市场成交之后）
## 前置：该笔已由 JWInventory 以四腿分录过账（买方现金 −V、买方资本 +V、卖方现金 +V、卖方净值）
## 后置：cell_capital_value += V；新增产能写入 cell_capacity_pending，**下季**经 commit_pending 转入在用
## 不变量：INV-054（产能增量只经 pending→active）、INV-091（当季形成的能力下一季才可用）
## 失败：越界 / 负额 → Fault
func add_purchased_capital(cell: int, value_uu: int, io: JWIoTable) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
	if value_uu < 0 or io == null:
		return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, cell, value_uu)
	if value_uu == 0:
		return JWResult.OK
	if _use_stacks():
		var b: int = _stack_of(cell)
		if b < 0:
			return JWResult.pending_code()
		buildings.capital_value[b] = JWMath.check_amount(buildings.capital_value[b] + value_uu)
		sync_cells_from_buildings()
	else:
		cell_capital_value[cell] = JWMath.check_amount(cell_capital_value[cell] + value_uu)
	# flow.cell.investment_uu 的唯一写入点（R-SUBSIDY-01）。原先只入资本、不记流量，该流量恒为 0，
	# P09 的「上季确有已付款的实际投资」前置因此永不成立，补助一分都发不出去。
	f_cell_investment[cell] = JWMath.check_amount(f_cell_investment[cell] + value_uu)
	# rounding: floor, reason=与 V-CELL-03 同一条换算，少给产能优于凭空多给
	var add_cap: int = JWMath.mul_ppm(value_uu, io.capacity_per_capital(JWIds.sector_of_cell(cell)))
	if add_cap > 0:
		return add_pending(4, cell, add_cap)
	return JWResult.OK


## S01 §01.4：把全部待投运能力转入在用能力。**这是 capacity_active 的唯一增量写入点**。
## 步骤：S01 §01.4
## 前置：phase == S01；本季尚未做任何生产
## 后置：全部 *_active += *_pending 且全部 *_pending == 0；
##       irrigation_index 在 [0, 2_000_000] 内 clamp 并写 log.clamp
## 不变量：INV-054（增量写入点全局唯一）、INV-091（完工写 pending、下季转 active）
## 失败：转入后 Σ pending != 0 → Fault.STOCK_IDENTITY
func commit_pending() -> int:
	if cell_capacity_active.size() != JWUnits.CELL or grid_capacity.size() != JWUnits.R \
			or pub_capacity_active.size() != JWUnits.PUBSERV:
		# allocate() 没跑过。继续下去只会在数组下标上炸，现场比这里差得多。
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				cell_capacity_active.size(), JWUnits.CELL)

	if _use_stacks():
		var b: int = 0
		while b < buildings.count:
			buildings.capacity_active[b] = JWMath.check_qty(buildings.capacity_active[b]
					+ buildings.capacity_pending[b])
			buildings.capacity_pending[b] = 0
			b += 1
		sync_cells_from_buildings()
	else:
		for i: int in JWUnits.CELL:
			cell_capacity_active[i] = JWMath.check_qty(cell_capacity_active[i] + cell_capacity_pending[i])
			cell_capacity_pending[i] = 0

	for r: int in JWUnits.R:
		pub_capacity_active[r] = JWMath.check_qty(pub_capacity_active[r] + pub_capacity_pending[r])
		pub_capacity_pending[r] = 0
		grid_capacity[r] = JWMath.check_qty(grid_capacity[r] + grid_pending[r])
		grid_pending[r] = 0
		housing_stock[r] = housing_stock[r] + housing_pending[r]
		housing_pending[r] = 0
		port_capacity[r] = JWMath.check_qty(port_capacity[r] + port_pending[r])
		port_pending[r] = 0
		# 灌溉是指数不是存量：转入后夹逼到契约区间。夹逼是「有界平滑」的登记点，
		# 但本函数拿不到 JWPricing（签名不含），log.clamp 由 S01 的调用方按返回值补记。
		irrigation_index[r] = JWMath.clamp_i(irrigation_index[r] + irrigation_pending[r],
				0, IRRIGATION_MAX_PPM)
		irrigation_pending[r] = 0

	# 步末断言（docs/12 §01.4）：全部 pending 必须精确归零。非零只有一种解释 ——
	# 有人在 S01 之后、S07 之前写了 pending，或者上面漏了一条转移。不许就地抹平。
	var residual: int = JWMath.sum_abs(cell_capacity_pending)
	residual += JWMath.sum_abs(pub_capacity_pending)
	residual += JWMath.sum_abs(grid_pending)
	residual += JWMath.sum_abs(housing_pending)
	residual += JWMath.sum_abs(port_pending)
	residual += JWMath.sum_abs(irrigation_pending)
	if residual != 0:
		return JWResult.raise_fault(JWResult.Fault.STOCK_IDENTITY, residual, 0)
	return JWResult.OK


## S07：把一笔完工能力写入 pending（**禁止写 active**，V-PD-11 在加载期已拦截直写 active 的政策）。
## 步骤：S07 §7.1
## 前置：target_code ∈ JWPolicyDef.EFFECT_TARGETS 的 *_pending_* 子集；delta >= 0
## 后置：对应 *_pending 增加 delta；本季生产完全不受影响
## 不变量：INV-091、INV-054
## 失败：target 不在白名单 → Fault.WRITE_OUT_OF_SCOPE
func add_pending(target_code: int, slot: int, delta: int) -> int:
	# delta < 0 等于借完工路径偷一次减量写入。减量写入点只有 S06 折旧一个（INV-054），
	# 所以这与「落点不在白名单」同罪，不是数值问题。
	if delta < 0:
		return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, target_code, delta)

	# 白名单即 JWPolicyDef.EFFECT_TARGETS 里的 *_pending_* 子集，下标 0..5；
	# 6/7（teachers / health_staff）不是待投运缓冲，由 JWLaborMarket 在 S03/S07 写。
	if target_code == 4:
		if slot < 0 or slot >= JWUnits.CELL:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, slot, JWUnits.CELL)
		if _use_stacks():
			var b: int = _stack_of(slot)
			if b < 0:
				return JWResult.pending_code()
			buildings.capacity_pending[b] = JWMath.check_qty(buildings.capacity_pending[b] + delta)
			sync_cells_from_buildings()
		else:
			cell_capacity_pending[slot] = JWMath.check_qty(cell_capacity_pending[slot] + delta)
		return JWResult.OK

	if target_code < 0 or target_code > 5:
		return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, target_code, slot)
	if slot < 0 or slot >= JWUnits.R:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, slot, JWUnits.R)

	if target_code == 0:
		grid_pending[slot] = JWMath.check_qty(grid_pending[slot] + delta)
	elif target_code == 1:
		housing_pending[slot] = housing_pending[slot] + delta
	elif target_code == 2:
		irrigation_pending[slot] = irrigation_pending[slot] + delta
	elif target_code == 3:
		port_pending[slot] = JWMath.check_qty(port_pending[slot] + delta)
	else:
		pub_capacity_pending[slot] = JWMath.check_qty(pub_capacity_pending[slot] + delta)
	return JWResult.OK


## S06 §6.1：折旧（非现金分录，资产↓净值↓），产能轨与价值轨用同一折旧率。
## 步骤：S06 §6.1
## 前置：io.depreciation_ppm 已加载；本季生产已完成
## 后置：capital_value 与 capacity_active 同步减少；flow.cell.depreciation_* 写入；
##       调用方已 post_noncash(kind=DEPRECIATION)
## 不变量：INV-055（折旧减资产与产能；维护欠账不减资产）、INV-056（同一折旧率）、INV-020
## 失败：资产被折成负数 → Fault.BALANCE_SHEET_BROKEN
func depreciate(io: JWIoTable, ledger: JWLedger, accounts: JWAccount) -> int:
	if io == null or ledger == null or accounts == null:
		# 装配缺件。折旧改账而不落分录会直接破坏 INV-020，宁可在这里停。
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, -1, 0)
	if cell_capital_value.size() != JWUnits.CELL or pub_capital_value.size() != JWUnits.PUBSERV:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				cell_capital_value.size(), JWUnits.CELL)

	if _use_stacks():
		# R-BUILDING-01：逐堆折旧（同一折旧率、各自取整），cell 的折旧额是本 cell 各堆之和；
		# 单堆 cell 的算术与下面的逐 cell 旧算术逐位相同。
		f_cell_dep_uu.fill(0)
		f_cell_dep_uqs.fill(0)
		var b: int = 0
		while b < buildings.count:
			var cb: int = buildings.cell[b]
			var rate_b: int = io.depreciation(JWIds.SECTOR_OF_CELL[cb])
			var val_b: int = buildings.capital_value[b]
			var cap_b: int = buildings.capacity_active[b]
			if val_b < 0 or cap_b < 0:
				return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, cb, val_b)
			var d_uu: int = JWMath.mul_ppm(val_b, rate_b)
			var d_uqs: int = JWMath.mul_ppm(cap_b, rate_b)
			buildings.capital_value[b] = val_b - d_uu
			buildings.capacity_active[b] = cap_b - d_uqs
			f_cell_dep_uu[cb] += d_uu
			# 产能轨按有效产能记（R-METHOD-01：cell 的在用产能是各堆按产出倍率折算后的和）。
			f_cell_dep_uqs[cb] += JWMath.mul_ppm(d_uqs, buildings.output_ppm_of(b))
			b += 1
		sync_cells_from_buildings()
		for i2: int in JWUnits.CELL:
			var dep2: int = f_cell_dep_uu[i2]
			if dep2 != 0:
				var agent2: int = JWIds.agent_of_cell(i2)
				var rc2: int = ledger.post_noncash(JWUnits.Kind.DEPRECIATION, agent2,
						JWIds.ACC_CAPITAL, -dep2, 0, i2)
				if rc2 != JWResult.OK:
					return rc2
				if accounts.get_balance(JWIds.idx_account(agent2, JWIds.ACC_CAPITAL)) < 0:
					return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, agent2, dep2)

	for i: int in (0 if _use_stacks() else JWUnits.CELL):
		var s: int = JWIds.SECTOR_OF_CELL[i]
		var rate: int = io.depreciation(s)
		var value: int = cell_capital_value[i]
		var cap: int = cell_capacity_active[i]
		if value < 0 or cap < 0:
			return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, i, value)
		# rounding: floor（mul_ppm 内部走 mul_div_floor）——docs/12 §6.1 明写 floor
		var dep_uu: int = JWMath.mul_ppm(value, rate)
		var dep_uqs: int = JWMath.mul_ppm(cap, rate)
		if dep_uu > value or dep_uqs > cap:
			# 折旧率 > 1e6 才可能发生（加载期 V-IO 已挡）。发生即内容包与代码脱节。
			return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, dep_uu, value)
		cell_capital_value[i] = value - dep_uu
		cell_capacity_active[i] = cap - dep_uqs
		f_cell_dep_uu[i] = dep_uu
		f_cell_dep_uqs[i] = dep_uqs
		if dep_uu != 0:
			var agent: int = JWIds.agent_of_cell(i)
			var rc: int = ledger.post_noncash(JWUnits.Kind.DEPRECIATION, agent,
					JWIds.ACC_CAPITAL, -dep_uu, 0, i)
			if rc != JWResult.OK:
				return rc
			if accounts.get_balance(JWIds.idx_account(agent, JWIds.ACC_CAPITAL)) < 0:
				return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, agent, dep_uu)

	# pubserv 是 sector.services 的非市场子账户（docs/10 §5）：折旧率取服务业的那一档。
	var rate_srv: int = io.depreciation(JWUnits.Sector.SERVICES)
	# 电网是能源基础设施，港口按服务业计（两者只有产能轨，无资本价值轨，故不落分录）。
	var rate_eng: int = io.depreciation(JWUnits.Sector.ENERGY)

	for r: int in JWUnits.PUBSERV:
		var pv: int = pub_capital_value[r]
		var pc: int = pub_capacity_active[r]
		if pv < 0 or pc < 0:
			return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, r, pv)
		var pdep_uu: int = JWMath.mul_ppm(pv, rate_srv)
		var pdep_uqs: int = JWMath.mul_ppm(pc, rate_srv)
		if pdep_uu > pv or pdep_uqs > pc:
			return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, pdep_uu, pv)
		pub_capital_value[r] = pv - pdep_uu
		pub_capacity_active[r] = pc - pdep_uqs
		f_pub_dep_uu[r] = pdep_uu
		if pdep_uu != 0:
			var pagent: int = JWIds.agent_of_pubserv(r)
			var prc: int = ledger.post_noncash(JWUnits.Kind.DEPRECIATION, pagent,
					JWIds.ACC_CAPITAL, -pdep_uu, 0, r)
			if prc != JWResult.OK:
				return prc
			if accounts.get_balance(JWIds.idx_account(pagent, JWIds.ACC_CAPITAL)) < 0:
				return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, pagent, pdep_uu)

		var g: int = grid_capacity[r]
		var p: int = port_capacity[r]
		if g < 0 or p < 0:
			return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, r, g)
		var gdep: int = JWMath.mul_ppm(g, rate_eng)
		var pdep: int = JWMath.mul_ppm(p, rate_srv)
		if gdep > g or pdep > p:
			return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, gdep, g)
		grid_capacity[r] = g - gdep
		port_capacity[r] = p - pdep
	return JWResult.OK


## S04：登记本季运行费拨款到位率（决定 S07 的可用率）。
## 步骤：S04 §4.2 的 service_opex 档
## 前置：due > 0 时 ratio = floor_div(paid * 1e6, due)；due == 0 时 ratio = 1_000_000
## 后置：flow.pubserv.funding_ratio_ppm[r] ∈ [0, 1_000_000]
## 不变量：INV-102（拨款不足只降可用率）
## 失败：无
func set_funding_ratio(r: int, paid_uu: int, due_uu: int) -> int:
	if r < 0 or r >= JWUnits.PUBSERV or f_pub_funding_ratio.size() != JWUnits.PUBSERV:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.PUBSERV)
	if due_uu <= 0:
		# 没有应付额就没有欠拨：到位率满格（docs/12 §4.2）。
		f_pub_funding_ratio[r] = JWUnits.PPM
		return JWResult.OK
	if paid_uu <= 0:
		f_pub_funding_ratio[r] = 0
		return JWResult.OK
	if paid_uu >= due_uu:
		# 足额（或超额）到位。先判再除有两个理由：结果本来就要夹到 1e6，
		# 而且这样 mul_div_floor 只会在 paid < due 的分支被调用，商恒为 0，余数恒为 paid。
		f_pub_funding_ratio[r] = JWUnits.PPM
		return JWResult.OK
	# mul_div_floor 的中间量是 (paid mod due) × 1e6，在 paid < due 时就是 paid × 1e6。
	# 它只在分母小于 INT64_MAX/1e6 时才不溢出——本季应付运行费离这个量级差好几个数量级
	# （9.2×10¹² μU 相当于九十多年的全国 GDP），越过即是上游算错了，显式登记，不静默返回 0。
	if due_uu > JWMath.floor_div(JWUnits.INT64_MAX, JWUnits.PPM):
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, due_uu, JWUnits.PPM)
	# rounding: floor —— 先乘后除一律走 mul_div_floor（R-SCALE-01）
	var ratio: int = JWMath.mul_div_floor(paid_uu, JWUnits.PPM, due_uu)
	f_pub_funding_ratio[r] = JWMath.clamp_i(ratio, 0, JWUnits.PPM)
	return JWResult.OK


## S07 §7.2：维护欠账与公共服务可用率。
## 步骤：S07 §7.2
## 前置：本季 funding_ratio 已写
## 后置：availability_ppm ∈ [0, 1_000_000]；maintenance_backlog ∈ [0, max]
## 不变量：INV-055、INV-102（**capacity_active、grid_capacity、housing_stock 在本路径下不得被写**，
##          不得用写 0 表达停运）
## 失败：本函数若触碰上述三个字段 → Fault.WRITE_OUT_OF_SCOPE（WriteGuard 会抓住）
func update_maintenance_and_availability(params: PackedInt64Array) -> int:
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	if cell_maint_backlog.size() != JWUnits.CELL or pub_availability.size() != JWUnits.PUBSERV:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				cell_maint_backlog.size(), JWUnits.CELL)

	var gain: int = params[JWUnits.Param.MAINTENANCE_BACKLOG_GAIN_PPM]
	var recover: int = params[JWUnits.Param.MAINTENANCE_BACKLOG_RECOVER_PPM]
	var backlog_max: int = params[JWUnits.Param.MAINTENANCE_BACKLOG_MAX_PPM]
	var starve: int = params[JWUnits.Param.OPEX_STARVE_DECAY_PPM]
	var recover_avail: int = params[JWUnits.Param.OPEX_RECOVER_PPM]

	# 维护欠账逐 cell 记账，欠拨口径逐地区（运行费是按地区拨的），故取本 cell 所在地区的缺口。
	for i: int in JWUnits.CELL:
		var r: int = JWIds.REGION_OF_CELL[i]
		var shortfall: int = JWMath.clamp_i(JWUnits.PPM - f_pub_funding_ratio[r], 0, JWUnits.PPM)
		var backlog: int = cell_maint_backlog[i]
		# rounding: floor ×2 —— 累积项与恢复项各自只对 ppm 取整一次（M1）
		var next_backlog: int = backlog + JWMath.mul_ppm(shortfall, gain) \
				- JWMath.mul_ppm(backlog, recover)
		cell_maint_backlog[i] = JWMath.clamp_i(next_backlog, 0, backlog_max)

	# 可用率：欠拨只降可用率，不减资产也不减容量（INV-055 / INV-102）。
	for r2: int in JWUnits.PUBSERV:
		var ratio: int = f_pub_funding_ratio[r2]
		if ratio < JWUnits.PPM:
			var shortfall2: int = JWMath.clamp_i(JWUnits.PPM - ratio, 0, JWUnits.PPM)
			var decay: int = JWMath.mul_ppm(starve, shortfall2)
			pub_availability[r2] = JWMath.clamp_i(pub_availability[r2] - decay, 0, JWUnits.PPM)
		else:
			pub_availability[r2] = JWMath.clamp_i(pub_availability[r2] + recover_avail,
					0, JWUnits.PPM)
	return JWResult.OK


## S06 §6.3：公共非市场产出（按成本计价 = 工资 + 中间消耗 + 折旧）。
## 工资来自 JWLaborMarket、中间消耗来自 JWInventory，均以**数组形参**传入（避免反向依赖）。
## 步骤：S06 §6.3
## 前置：本季 pubserv 的工资与中间消耗已确定；折旧已由 depreciate() 算出
## 后置：flow.pubserv.output_uu = wage + intermediate + depreciation；其增加值 = wage + depreciation；
##       全额计入政府最终消费
## 不变量：INV-101（**不走市场销售，不重复计算**）、INV-112
## 失败：无
func compute_nonmarket_output(pub_wage_bill_uu: PackedInt64Array,
		pub_intermediate_uu: PackedInt64Array) -> int:
	if pub_wage_bill_uu.size() != JWUnits.PUBSERV or pub_intermediate_uu.size() != JWUnits.PUBSERV \
			or f_pub_output.size() != JWUnits.PUBSERV:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pub_wage_bill_uu.size(), JWUnits.PUBSERV)
	for r: int in JWUnits.PUBSERV:
		# 成本计价：三项直接相加，不做任何加成，也不进市场（INV-101）。
		var out_uu: int = pub_wage_bill_uu[r] + pub_intermediate_uu[r] + f_pub_dep_uu[r]
		f_pub_output[r] = JWMath.check_amount(out_uu)
	return JWResult.OK


## S05 §5.8：按实际产量累计本季排放流量。
## 步骤：S05 §5.8
## 前置：output_actual 已定
## 后置：flow.region.emissions_uqe 写入
## 不变量：INV-057（排放只累积，首版不反馈到生产约束——静态检查生产函数不引用 emissions）
## 失败：无
func accumulate_emissions(output_actual_uqs: PackedInt64Array, io: JWIoTable) -> int:
	if io == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, -1, 0)
	if output_actual_uqs.size() != JWUnits.CELL or f_emissions.size() != JWUnits.R:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				output_actual_uqs.size(), JWUnits.CELL)
	for i: int in JWUnits.CELL:
		var s: int = JWIds.SECTOR_OF_CELL[i]
		var coeff: int = io.emission(s)
		if coeff == 0:
			continue
		var r: int = JWIds.REGION_OF_CELL[i]
		# rounding: floor —— 单位产量排放系数是 ppm，对产量只取整一次（M1）
		f_emissions[r] = JWMath.check_qty(f_emissions[r] + JWMath.mul_ppm(output_actual_uqs[i], coeff))
	return JWResult.OK


## S07 §7.9：排放存量衰减与环境暴露指数。
## 步骤：S07 §7.9
## 前置：region_population 由 JWPopulation 传入
## 后置：emissions_stock >= 0；env_exposure ∈ [0, 3_000_000]
## 不变量：INV-057
## 失败：area_index == 0 → 用 max(area,1)，不除零
func update_environment(region_population: PackedInt64Array, params: PackedInt64Array) -> int:
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	if region_population.size() != JWUnits.R or emissions_stock.size() != JWUnits.R:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				region_population.size(), JWUnits.R)

	var decay_ppm: int = JWMath.clamp_i(params[JWUnits.Param.EMISSION_DECAY_PPM], 0, JWUnits.PPM)
	var exposure_gain: int = params[JWUnits.Param.ENV_EXPOSURE_GAIN_PPM]

	for r: int in JWUnits.R:
		var stock: int = JWMath.check_qty(emissions_stock[r] + f_emissions[r])
		if stock < 0:
			# 存量只会由非负流量累积，负值说明上游写错了；不静默抹平。
			return JWResult.raise_fault(JWResult.Fault.STOCK_IDENTITY, r, stock)
		# rounding: floor —— 自然消纳按季衰减，少消纳优于多消纳
		stock = JWMath.mul_ppm(stock, JWUnits.PPM - decay_ppm)
		emissions_stock[r] = stock
		# area_index == 0 时取 1：不除零，也不跳过这个地区（跳过等于把暴露记成 0）。
		var area: int = area_index[r]
		if area < 1:
			area = 1
		# rounding: floor —— 人口密度指数，先乘后除走 mul_div_floor
		var density_ppm: int = JWMath.mul_div_floor(region_population[r], JWUnits.PPM, area)
		# M2：两个 ppm 先合成再对存量取整一次，禁止 mul_ppm(mul_ppm(x, p1), p2)
		var exposure: int = JWMath.mul_ppm_2(stock, exposure_gain, density_ppm)
		env_exposure[r] = JWMath.clamp_i(exposure, 0, ENV_EXPOSURE_MAX_PPM)
	return JWResult.OK


## S07：项目完工时把 wip 转成目标主体的 capital（由 JWAssetCommissioning 调用）。
## 步骤：S07 §7.1
## 前置：wip_part <= 该主体当前 wip
## 后置：capital_value += wip_part；wip -= wip_part。
##       政府主体（AGENT_GOV）由本函数过一笔 ASSET_RECLASS 分录（R-ASSET-01）：政府 wip −V、政府资本 +V
## 不变量：INV-092（付款只增 wip 与承包方现金）、INV-020、INV-021（结转不改净值）
## 失败：wip 不足 → Fault.BALANCE_SHEET_BROKEN；其余主体越权 → Fault.WRITE_OUT_OF_SCOPE
##
## entity_ref：写进分录行的实体引用（投运调用方传项目下标），缺省 −1。
func capitalize_wip(target_agent: int, wip_part_uu: int, ledger: JWLedger, accounts: JWAccount,
		entity_ref: int = -1) -> int:
	# 本函数只做「同一主体内两个资产科目之间的结转」：wip ↓ 与 capital ↑ 金额相等，净值不变。
	# JWLedger.post_noncash 只能表达「一条资产腿 + 一条净值腿」，表达不了两条资产腿；
	# 政府主体的结转因此走 post_multi 的两腿分录，类型是 docs/18 R-ASSET-01 新增的 ASSET_RECLASS
	# （三口径全 none：结转既不是生产、也不是支出，投资已在付款时按 PROJECT_PAYMENT 计过一次）。
	if ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, -1, 0)
	if wip_part_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, target_agent, wip_part_uu)
	if wip_part_uu == 0:
		return JWResult.OK

	if target_agent == JWIds.AGENT_GOV:
		# R-ASSET-01：政府项目的在建工程（S04 付款的第三腿，R-PROJECT-01）与投运后的资产同属政府，
		# 结转是政府主体内部的事（docs/10 §3.1：state.gov.wip_uu / capital_uu 的写入者都含 S07）。
		# 原实现把 AGENT_GOV 判成越权，投运路径上任何一笔付过款的项目都会撞 WRITE_OUT_OF_SCOPE。
		var gov_wip_acc: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_WIP)
		var gov_wip: int = accounts.get_balance(gov_wip_acc)
		if gov_wip < wip_part_uu:
			# wip 装不下本项目的已付额 ⇒ 付款时的 wip 腿缺了（INV-092 在上游破了）。不截断、不结转。
			return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, gov_wip, wip_part_uu)
		if _reclass_acc.size() != 2 or _reclass_delta.size() != 2:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, _reclass_acc.size(), 2)
		# 第 0 腿承载分类码（全 none），取资产增加的那条腿，与其它分录「分类落在正腿」的习惯一致。
		_reclass_acc[0] = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CAPITAL)
		_reclass_delta[0] = wip_part_uu
		_reclass_acc[1] = gov_wip_acc
		_reclass_delta[1] = -wip_part_uu
		return ledger.post_multi(JWUnits.Kind.ASSET_RECLASS, _reclass_acc, _reclass_delta, 0, -1,
				JWUnits.Kind.ASSET_RECLASS, entity_ref)

	var cell: int = JWIds.cell_of_agent(target_agent)
	if cell >= 0:
		if cell_wip.size() != JWUnits.CELL:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					cell_wip.size(), JWUnits.CELL)
		if cell_wip[cell] < wip_part_uu:
			return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN,
					cell_wip[cell], wip_part_uu)
		cell_wip[cell] = cell_wip[cell] - wip_part_uu
		if _use_stacks():
			var bw: int = _stack_of(cell)
			if bw < 0:
				return JWResult.pending_code()
			buildings.capital_value[bw] = JWMath.check_amount(buildings.capital_value[bw] + wip_part_uu)
			sync_cells_from_buildings()
		else:
			cell_capital_value[cell] = JWMath.check_amount(cell_capital_value[cell] + wip_part_uu)
		if accounts.get_balance(JWIds.idx_account(target_agent, JWIds.ACC_CAPITAL)) < 0:
			return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, target_agent, 0)
		return JWResult.OK

	if target_agent >= JWIds.AGENT_PUBSERV_BASE and target_agent < JWIds.AGENT_GROUP_BASE:
		var r: int = target_agent - JWIds.AGENT_PUBSERV_BASE
		if pub_capital_value.size() != JWUnits.PUBSERV:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					pub_capital_value.size(), JWUnits.PUBSERV)
		# pubserv 没有自己的在建工程：政府项目的 wip 记在 state.gov.wip_uu（JWTreasury），
		# 扣减由调用方在同一步做（docs/12 §7.1「gov.wip_uu -= 该部分」）。
		# 这里只能核对政府的 wip 够不够，核对不通过就不结转。
		if accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_WIP)) < wip_part_uu:
			return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN,
					JWIds.AGENT_GOV, wip_part_uu)
		pub_capital_value[r] = JWMath.check_amount(pub_capital_value[r] + wip_part_uu)
		return JWResult.OK

	# 投资池、居民与外部没有资本科目，也不持有政府项目的在建工程。
	return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, target_agent, wip_part_uu)


## 只读访问器：cell 在用产能（μQ_s/季）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-043（产能约束是 solve_output 的候选之一）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func cell_capacity(cell: int) -> int:
	if cell < 0 or cell >= cell_capacity_active.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	return cell_capacity_active[cell]


## 只读访问器：地区公共服务在用容量（μQ_services/季）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-103
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func pubserv_capacity(r: int) -> int:
	if r < 0 or r >= pub_capacity_active.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.PUBSERV)
		return 0
	return pub_capacity_active[r]


## 只读访问器：地区公共服务可用率（ppm）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-102
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func availability(r: int) -> int:
	if r < 0 or r >= pub_availability.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.PUBSERV)
		return 0
	return pub_availability[r]


## 只读访问器：地区电网容量（μQ_energy/季）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-051（Σ 配给 ≤ min(可交付, 电网)）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func grid(r: int) -> int:
	if r < 0 or r >= grid_capacity.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.R)
		return 0
	return grid_capacity[r]


## 只读访问器：地区住房存量（套）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-083（Σ occupied <= housing_stock <= housing_capacity，由调用方在 S07 断言）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func housing_stock_of(r: int) -> int:
	if r < 0 or r >= housing_stock.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.R)
		return 0
	return housing_stock[r]


## 只读访问器：地区住房容量（套）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-083
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func housing_capacity_of(r: int) -> int:
	if r < 0 or r >= housing_capacity.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.R)
		return 0
	return housing_capacity[r]


## 只读访问器：地区施工槽位总数（槽）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-093（在建项目数不超过槽位数）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func slots_total(r: int) -> int:
	if r < 0 or r >= construction_slots.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.R)
		return 0
	return construction_slots[r]


## 只读访问器：地区灌溉指数（ppm）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-054
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func irrigation(r: int) -> int:
	if r < 0 or r >= irrigation_index.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.R)
		return 0
	return irrigation_index[r]


## 只读访问器：地区港口能力（μQ/季）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-063（出口受交付能力约束）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func port(r: int) -> int:
	if r < 0 or r >= port_capacity.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, r, JWUnits.R)
		return 0
	return port_capacity[r]


## 载入期与投运瞬间的产能／资本一致性检查（允许此后漂移，OQ-206）。
## 步骤：LOAD、S07 投运瞬间
## 前置：io.capacity_per_capital_ppm > 0
## 后置：不改状态
## 不变量：INV-056（|capacity − capital × coeff / 1e6| <= 1 μQ_s）
## 失败：Load.CAPACITY_INCONSISTENT（载入期）；S07 投运时不符 → Fault.STOCK_IDENTITY
func check_capacity_value_consistency(io: JWIoTable) -> int:
	# 返回码统一取 Load.CAPACITY_INCONSISTENT（不 raise_fault）：载入期它是一条拒绝码，
	# 而 S07 投运瞬间的同一条不符要登记成 Fault.STOCK_IDENTITY —— 本函数看不见 phase，
	# 由 S07 的调用方拿到非 OK 返回后自行 raise_fault(STOCK_IDENTITY)。
	if io == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, -1, 0)
	if cell_capacity_active.size() != JWUnits.CELL or cell_capital_value.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				cell_capacity_active.size(), JWUnits.CELL)
	for i: int in JWUnits.CELL:
		var s: int = JWIds.SECTOR_OF_CELL[i]
		var coeff: int = io.capacity_per_capital(s)
		if coeff <= 0:
			# 前置条件破裂：系数是内容包必填项且必须 > 0（docs/10 §4.5、V-IO-07）。
			return JWResult.Load.IO_CAPACITY_COEFF
		# rounding: floor —— 系数单位是 μQ_s/季 每 μU，按 ppm 缩放一次
		var expect: int = JWMath.mul_ppm(cell_capital_value[i], coeff)
		var diff: int = JWMath.absi(cell_capacity_active[i] - expect)
		if diff > 1:
			return JWResult.Load.CAPACITY_INCONSISTENT
	return JWResult.OK


## 漂移诊断（只报警不改数，OQ-206）。
## 步骤：S06 末（诊断用）
## 前置：无
## 后置：不改状态
## 不变量：—（这是诊断指标 derived.cell.capacity_value_drift_ppm 的来源）
## 失败：无
func capacity_value_drift_ppm(cell: int, io: JWIoTable) -> int:
	if io == null:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, -1, 0)
		return 0
	if cell < 0 or cell >= cell_capacity_active.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	var s: int = JWIds.SECTOR_OF_CELL[cell]
	var coeff: int = io.capacity_per_capital(s)
	# rounding: floor —— 与一致性检查用同一条换算，保证两者永远指向同一个「应有产能」
	var expect: int = JWMath.mul_ppm(cell_capital_value[cell], coeff)
	var cap: int = cell_capacity_active[cell]
	# 分母取产能本身；产能为 0 时取 1，不除零（诊断量不允许因为 0 而中断结算）。
	var denom: int = cap
	if denom < 1:
		denom = 1
	# rounding: floor —— 相对偏离，负值向 −∞ 取整是确定性偏置，不改成向零截断
	return JWMath.mul_div_floor(cap - expect, JWUnits.PPM, denom)


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：尚未 allocate
## 后置：cell_* 与 f_cell_* 长度 CELL，pub_* 与 f_pub_* 长度 PUBSERV，region 相关长度 R
## 不变量：INV-136
## 失败：无
func allocate() -> void:
	cell_capacity_active.resize(JWUnits.CELL)
	cell_capacity_active.fill(0)
	cell_capacity_pending.resize(JWUnits.CELL)
	cell_capacity_pending.fill(0)
	cell_capital_value.resize(JWUnits.CELL)
	cell_capital_value.fill(0)
	cell_wip.resize(JWUnits.CELL)
	cell_wip.fill(0)
	cell_maint_backlog.resize(JWUnits.CELL)
	cell_maint_backlog.fill(0)
	f_cell_dep_uu.resize(JWUnits.CELL)
	f_cell_dep_uu.fill(0)
	f_cell_dep_uqs.resize(JWUnits.CELL)
	f_cell_dep_uqs.fill(0)
	f_cell_investment.resize(JWUnits.CELL)
	f_cell_investment.fill(0)

	pub_capacity_active.resize(JWUnits.PUBSERV)
	pub_capacity_active.fill(0)
	pub_capacity_pending.resize(JWUnits.PUBSERV)
	pub_capacity_pending.fill(0)
	pub_capital_value.resize(JWUnits.PUBSERV)
	pub_capital_value.fill(0)
	pub_availability.resize(JWUnits.PUBSERV)
	pub_availability.fill(0)
	pub_teachers.resize(JWUnits.PUBSERV)
	pub_teachers.fill(0)
	pub_health_staff.resize(JWUnits.PUBSERV)
	pub_health_staff.fill(0)
	f_pub_funding_ratio.resize(JWUnits.PUBSERV)
	f_pub_funding_ratio.fill(0)
	f_pub_dep_uu.resize(JWUnits.PUBSERV)
	f_pub_dep_uu.fill(0)
	f_pub_output.resize(JWUnits.PUBSERV)
	f_pub_output.fill(0)

	grid_capacity.resize(JWUnits.R)
	grid_capacity.fill(0)
	grid_pending.resize(JWUnits.R)
	grid_pending.fill(0)
	housing_capacity.resize(JWUnits.R)
	housing_capacity.fill(0)
	housing_stock.resize(JWUnits.R)
	housing_stock.fill(0)
	housing_pending.resize(JWUnits.R)
	housing_pending.fill(0)
	irrigation_index.resize(JWUnits.R)
	irrigation_index.fill(0)
	irrigation_pending.resize(JWUnits.R)
	irrigation_pending.fill(0)
	port_capacity.resize(JWUnits.R)
	port_capacity.fill(0)
	port_pending.resize(JWUnits.R)
	port_pending.fill(0)
	construction_slots.resize(JWUnits.R)
	construction_slots.fill(0)
	emissions_stock.resize(JWUnits.R)
	emissions_stock.fill(0)
	env_exposure.resize(JWUnits.R)
	env_exposure.fill(0)
	f_emissions.resize(JWUnits.R)
	f_emissions.fill(0)
	area_index.resize(JWUnits.R)
	area_index.fill(0)


## §1.6 状态块协议：只读取用（返回引用，调用方不得写）。
## 步骤：LOAD / 哈希 / 存档
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
		return PackedInt64Array()
	if i == 0:
		return cell_capacity_active
	if i == 1:
		return cell_capacity_pending
	if i == 2:
		return cell_capital_value
	if i == 3:
		return cell_wip
	if i == 4:
		return cell_maint_backlog
	if i == 5:
		return pub_capacity_active
	if i == 6:
		return pub_capacity_pending
	if i == 7:
		return pub_capital_value
	if i == 8:
		return pub_availability
	if i == 9:
		return pub_teachers
	if i == 10:
		return pub_health_staff
	if i == 11:
		return grid_capacity
	if i == 12:
		return grid_pending
	if i == 13:
		return housing_capacity
	if i == 14:
		return housing_stock
	if i == 15:
		return housing_pending
	if i == 16:
		return irrigation_index
	if i == 17:
		return irrigation_pending
	if i == 18:
		return port_capacity
	if i == 19:
		return port_pending
	if i == 20:
		return construction_slots
	if i == 21:
		return emissions_stock
	if i == 22:
		return env_exposure
	return area_index


## §1.6 状态块协议：仅 LOAD / MIG（静态检查：调用点必须在 systems/content_loader.gd 或 systems/saves.gd）。
## 步骤：LOAD / MIG
## 前置：allocate() 已调用；v 长度与契约一致
## 后置：对应数组逐位等于 v
## 不变量：INV-136
## 失败：越界或长度不符 → INDEX_OUT_OF_RANGE / Load.SCHEMA_HEADER
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	# 长度是 schema 的一部分：0..4 是 cell 数组，5..10 是 pubserv 数组，其余是地区数组。
	var want: int = JWUnits.R
	if i <= LAST_CELL_STATE:
		want = JWUnits.CELL
	elif i <= LAST_PUBSERV_STATE:
		want = JWUnits.PUBSERV
	if v.size() != want:
		return JWResult.Load.SCHEMA_HEADER

	if i == 0:
		cell_capacity_active = v
	elif i == 1:
		cell_capacity_pending = v
	elif i == 2:
		cell_capital_value = v
	elif i == 3:
		cell_wip = v
	elif i == 4:
		cell_maint_backlog = v
	elif i == 5:
		pub_capacity_active = v
	elif i == 6:
		pub_capacity_pending = v
	elif i == 7:
		pub_capital_value = v
	elif i == 8:
		pub_availability = v
	elif i == 9:
		pub_teachers = v
	elif i == 10:
		pub_health_staff = v
	elif i == 11:
		grid_capacity = v
	elif i == 12:
		grid_pending = v
	elif i == 13:
		housing_capacity = v
	elif i == 14:
		housing_stock = v
	elif i == 15:
		housing_pending = v
	elif i == 16:
		irrigation_index = v
	elif i == 17:
		irrigation_pending = v
	elif i == 18:
		port_capacity = v
	elif i == 19:
		port_pending = v
	elif i == 20:
		construction_slots = v
	elif i == 21:
		emissions_stock = v
	elif i == 22:
		env_exposure = v
	else:
		area_index = v
	return JWResult.OK


## §1.6 状态块协议：本类无标量状态，恒返回 0。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：INV-136
## 失败：无
func state_scalar(i: int) -> int:
	return 0


## §1.6 状态块协议：本类无标量状态，恒返回 OK 且不做任何事。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：INV-136
## 失败：无
func set_state_scalar(i: int, v: int) -> int:
	return JWResult.OK


## §1.6 状态块协议：读流量数组（只读取用）。
## 步骤：诊断 / 报告
## 前置：i ∈ [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-010
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func flow_array(i: int) -> PackedInt64Array:
	if i < 0 or i >= FLOW_ARRAY_IDS.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
		return PackedInt64Array()
	if i == 0:
		return f_cell_dep_uu
	if i == 1:
		return f_cell_dep_uqs
	if i == 2:
		return f_cell_investment
	if i == 3:
		return f_pub_funding_ratio
	if i == 4:
		return f_pub_dep_uu
	if i == 5:
		return f_pub_output
	if i == 6:
		return f_emissions
	return PackedInt64Array()


## §1.6 状态块协议：本类无标量流量，恒返回 0。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：INV-010
## 失败：无
func flow_scalar(i: int) -> int:
	return 0


## §1.6 状态块协议：仅 S01；全部 FLOW_* 归零。
## 步骤：S01 §01.3
## 前置：phase == S01
## 后置：七个流量数组全 0
## 不变量：INV-010
## 失败：无
func reset_flows() -> void:
	f_cell_dep_uu.fill(0)
	f_cell_dep_uqs.fill(0)
	f_cell_investment.fill(0)
	f_pub_funding_ratio.fill(0)
	f_pub_dep_uu.fill(0)
	f_pub_output.fill(0)
	f_emissions.fill(0)


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 已调用
## 后置：不改状态
## 不变量：INV-010
## 失败：无
func flow_abs_sum() -> int:
	var acc: int = JWMath.sum_abs(f_cell_dep_uu)
	acc += JWMath.sum_abs(f_cell_dep_uqs)
	acc += JWMath.sum_abs(f_cell_investment)
	acc += JWMath.sum_abs(f_pub_funding_ratio)
	acc += JWMath.sum_abs(f_pub_dep_uu)
	acc += JWMath.sum_abs(f_pub_output)
	acc += JWMath.sum_abs(f_emissions)
	return acc


## §1.6 状态块协议：读档时写回流量数组（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_array 逐项对称生成）。
## 步骤：LOAD（JWSaves 经 JWSimState 调用）
## 前置：v 的长度与本块当前分配的长度一致（长度是 schema 的一部分，INV-136）
## 后置：对应成员被整体替换
## 不变量：INV-133（读档后与原进程逐位相同）
## 失败：下标越界或长度不符 → INDEX_OUT_OF_RANGE
func set_flow_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != f_cell_dep_uu.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_cell_dep_uu = v.duplicate()
		return JWResult.OK
	if i == 1:
		if v.size() != f_cell_dep_uqs.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_cell_dep_uqs = v.duplicate()
		return JWResult.OK
	if i == 2:
		if v.size() != f_cell_investment.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_cell_investment = v.duplicate()
		return JWResult.OK
	if i == 3:
		if v.size() != f_pub_funding_ratio.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_pub_funding_ratio = v.duplicate()
		return JWResult.OK
	if i == 4:
		if v.size() != f_pub_dep_uu.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_pub_dep_uu = v.duplicate()
		return JWResult.OK
	if i == 5:
		if v.size() != f_pub_output.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_pub_output = v.duplicate()
		return JWResult.OK
	if i == 6:
		if v.size() != f_emissions.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_emissions = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
