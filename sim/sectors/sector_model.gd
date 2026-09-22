## 生产单元（cell）的**计划 → 五项约束 → 实际产量 → 经营结果**。
##
## Q_actual = min(Q_plan, Q_capacity, Q_labor, Q_energy, Q_materials)，**系数为零跳过该约束**。
## 同时持有 cell 的 S06 经营结果流量（增加值、利润），因为它们是同一个实体的两面。
##
## 骨架依据：docs/17_api_skeleton.md §4.18。依赖秩 7，只允许引用秩 ≤6。
## 全部公式抄自 docs/12 §3.1 / §3.5 / §3.6 / §5.2 / §5.3 / §5.4 / §6.2 / §6.6 / §6.7，
## 一切「先乘后除」走 JWMath.mul_div_floor（裁定 R-SCALE-01），整除走 floor_div / ceil_div。
class_name JWSectorModel
extends RefCounted

## §1.6 状态块协议：本块各数组所属子系统（与 STATE_ARRAY_IDS 等长）。子系统 SUBSYS_CELL。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
]

## 稳定 ID 注册表：下标 == 数组序号；顺序是 schema 的一部分，重排即破坏性变更（INV-136）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.cell.demand_expect_uqs",
	"state.cell.loss_carryforward_uu",
]
const STATE_SCALAR_IDS: PackedStringArray = []

## 流量注册表。末两项 `_internal.*` 在 docs/10 中尚无稳定 ID（docs/17 §4.18 的表里写作「—」），
## 按内部流量登记，仍须每季 S01 清零。电力两项归 SUBSYS_REGION，其余归 SUBSYS_CELL。
const FLOW_ARRAY_IDS: PackedStringArray = [
	"flow.cell.output_plan_uqs",
	"flow.cell.bound_plan_uqs",
	"flow.cell.bound_capacity_uqs",
	"flow.cell.bound_labor_uqs",
	"flow.cell.bound_energy_uqs",
	"flow.cell.bound_materials_uqs",
	"flow.cell.binding_code",
	"flow.cell.output_actual_uqs",
	"flow.cell.energy_allocated_uqs",
	"flow.cell.energy_unused_uqs",
	"flow.region.electricity_demand_uqs",
	"flow.region.electricity_supply_uqs",
	"flow.cell.invest_intent_uu",
	"flow.cell.gross_output_uu",
	"flow.cell.intermediate_uu",
	"flow.cell.value_added_uu",
	"flow.cell.value_added_real_uu",
	"flow.cell.operating_surplus_uu",
	"flow.cell.profit_pretax_uu",
	"flow.cell.tax_profit_paid_uu",
	"flow.cell.distributed_uu",
	"flow.cell.subsidy_received_uu",
	"_internal.cell.sales_revenue_uu",
	"_internal.cell.sold_qty_uqs",
	# R-GRID-01 补遗：能源 cell 本季经电网的实际交付（自用 + 本地 + 跨区输出）与各地区未满足的生产用电。
	"flow.cell.elec_delivered_uqs",
	"flow.region.elec_unmet_uqs",
]

## 与 FLOW_ARRAY_IDS 等长的子系统表（本文件头注释所规定的归属）。
## 缺这张表时 JWSimState._reg_add_group 会把全部条目算进块默认子系统（SUBSYS_CELL），
## 电力两项的 subsystem_hash 归属就会错，所以必须显式登记。
const FLOW_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_REGION, JWUnits.SUBSYS_REGION,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_REGION,
]
const FLOW_SCALAR_IDS: PackedStringArray = []

## 五项约束的项数（== JWUnits.Binding 的枚举数，docs/12 §5.3 的固定序 plan/capacity/labor/energy/materials）
const BOUND_N: int = 5

## state.cell.demand_expect_uqs[] —— 长度 16，初值剧本，μQ_s。类 S，写入者 S03（跨季存量，存档必含）。
var demand_expect: PackedInt64Array = PackedInt64Array()
## flow.cell.output_plan_uqs[] —— 长度 16，初值 0，μQ_s。类 F，写入者 S03。
var f_output_plan: PackedInt64Array = PackedInt64Array()
## flow.cell.bound_plan_uqs[] —— 长度 16，初值 0，μQ_s。类 F，写入者 S05。
var f_bound_plan: PackedInt64Array = PackedInt64Array()
## flow.cell.bound_capacity_uqs[] —— 长度 16，初值 0，μQ_s。类 F，写入者 S05。
var f_bound_capacity: PackedInt64Array = PackedInt64Array()
## flow.cell.bound_labor_uqs[] —— 长度 16，初值 0，μQ_s 或 SENTINEL（该约束不适用）。类 F，写入者 S05。
var f_bound_labor: PackedInt64Array = PackedInt64Array()
## flow.cell.bound_energy_uqs[] —— 长度 16，初值 0，μQ_s 或 SENTINEL。类 F，写入者 S05。
var f_bound_energy: PackedInt64Array = PackedInt64Array()
## flow.cell.bound_materials_uqs[] —— 长度 16，初值 0，μQ_s 或 SENTINEL。类 F，写入者 S05。
var f_bound_materials: PackedInt64Array = PackedInt64Array()
## flow.cell.binding_code[] —— 长度 16，初值 0，枚举 JWUnits.Binding。类 F，写入者 S05。
## 报告「限制因素」的唯一数据源（INV-045）。
var f_binding_code: PackedInt64Array = PackedInt64Array()
## flow.cell.output_actual_uqs[] —— 长度 16，初值 0，μQ_s。类 F，写入者 S05。
var f_output_actual: PackedInt64Array = PackedInt64Array()
## flow.cell.energy_allocated_uqs[] —— 长度 16，初值 0，μQ_energy。类 F，写入者 S05。
var f_energy_allocated: PackedInt64Array = PackedInt64Array()
## flow.cell.energy_unused_uqs[] —— 长度 16，初值 0，μQ_energy。类 F，写入者 S05。
var f_energy_unused: PackedInt64Array = PackedInt64Array()
## flow.cell.elec_delivered_uqs[] —— 16（只有能源 cell 非零），μQ_energy。本季经电网实际交付 = 自用 + 本地配给 + 跨区输出。
## 下季 S01 取作该能源 cell 的已实现需求（R-GRID-01 补遗）：原先取「本地区总用电需求」，
## 跨区输电之后对输出地区系统性低估、对输入地区系统性高估。
var f_elec_delivered: PackedInt64Array = PackedInt64Array()
## flow.region.elec_unmet_uqs[] —— 4，μQ_energy。本地区生产用电在本地配给与跨区输电之后仍未满足的量。
var f_elec_unmet: PackedInt64Array = PackedInt64Array()
## flow.region.electricity_demand_uqs[] —— 长度 4，初值 0，μQ_energy。类 F，写入者 S03。
var f_elec_demand: PackedInt64Array = PackedInt64Array()
## flow.region.electricity_supply_uqs[] —— 长度 4，初值 0，μQ_energy。类 F，写入者 S05。
var f_elec_supply: PackedInt64Array = PackedInt64Array()
## flow.cell.invest_intent_uu[] —— 长度 16，初值 0，μU。类 F，写入者 S03。
var f_invest_intent: PackedInt64Array = PackedInt64Array()
## flow.cell.gross_output_uu[] —— 长度 16，初值 0，μU。类 F，写入者 S06。
var f_gross_output: PackedInt64Array = PackedInt64Array()
## flow.cell.intermediate_uu[] —— 长度 16，初值 0，μU。类 F，写入者 S06。
var f_intermediate: PackedInt64Array = PackedInt64Array()
## flow.cell.value_added_uu[] —— 长度 16，初值 0，μU（可为负）。类 F，写入者 S06。
var f_value_added: PackedInt64Array = PackedInt64Array()
## flow.cell.value_added_real_uu[] —— 长度 16，初值 0，μU（基年价）。类 F，写入者 S06。
var f_value_added_real: PackedInt64Array = PackedInt64Array()
## flow.cell.operating_surplus_uu[] —— 长度 16，初值 0，μU（可为负）。类 F，写入者 S06。
var f_operating_surplus: PackedInt64Array = PackedInt64Array()
## flow.cell.profit_pretax_uu[] —— 长度 16，初值 0，μU（可为负）。类 F，写入者 S06。
var f_profit_pretax: PackedInt64Array = PackedInt64Array()
## flow.cell.tax_profit_paid_uu[] —— 长度 16，初值 0，μU。类 F，写入者 S06。
var f_tax_profit_paid: PackedInt64Array = PackedInt64Array()
## flow.cell.distributed_uu[] —— 长度 16，初值 0，μU。类 F，写入者 S06。
var f_distributed: PackedInt64Array = PackedInt64Array()
## flow.cell.subsidy_received_uu[] —— 长度 16，初值 0，μU。类 F，写入者 S04。
var f_subsidy_received: PackedInt64Array = PackedInt64Array()
## state.cell.loss_carryforward_uu[] —— 长度 16，初值 0，μU。类 S，写入者 S06。
var loss_carryforward: PackedInt64Array = PackedInt64Array()
## log.constraint_diag.* —— 逐 cell 的约束诊断（cell 号 / 五项候选 / 生效约束 / 松弛量）。类 L，写入者 S05。
## 布局：d_cell 与 d_binding 逐 cell（长度 CELL）；d_cands 与 d_slack 逐 (cell, 约束)（长度 CELL × BOUND_N，
## 行内下标 == JWUnits.Binding 的值）。
var d_cell: PackedInt64Array = PackedInt64Array()
var d_cands: PackedInt64Array = PackedInt64Array()
var d_binding: PackedInt64Array = PackedInt64Array()
var d_slack: PackedInt64Array = PackedInt64Array()
## 内部流量：S05 累计的销售额（长度 16，μU）。docs/10 尚无稳定 ID。
var _sales_rev: PackedInt64Array = PackedInt64Array()
## R-POWER-01：本季经电网购入的电力（μQ_energy），按 cell 记。S05 写、S06 计入中间消耗；与 _sales_rev 同寿命。
## 只在同一季内使用（S06 已把结果落进 f_value_added），故不进状态块协议、不进存档。
var _elec_bought_qty: PackedInt64Array = PackedInt64Array()
## 内部流量：S05 累计的销售量（长度 16，μQ_s，基年价口径）。docs/10 尚无稳定 ID。
var _sold_qty: PackedInt64Array = PackedInt64Array()

# ── 私有缓冲与跨季快照（不进注册表、不进哈希；热路径不新建对象，docs/17 §1.4） ──

## 长度 16：由 f_output_plan 反算的本季生产用电需求（μQ_energy），S03 与 S05 各算一次，结果相同。
var _need_energy: PackedInt64Array = PackedInt64Array()
## 长度 4：逐地区拆分用的权重 / 决胜键 / 结果缓冲（一个地区恰有 S 个 cell）。
var _split_w: PackedInt64Array = PackedInt64Array()
var _split_tb: PackedInt64Array = PackedInt64Array()
var _split_out: PackedInt64Array = PackedInt64Array()
## 长度 4：逐地区能源 cell 的可交付电力（μQ_energy），作废量按它拆回各能源 cell。
var _deliver: PackedInt64Array = PackedInt64Array()
## 长度 4：本地区各 cell 配给量中的进口部分（R-IMPORT-01 电网进口）。
var _imp_part: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
## R-GRID-01 跨区输电的季内缓冲（长度 R 或 CELL，构造期定长，热路径不新建对象）。
var _gen_r: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var _dom_used_r: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var _surplus_r: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var _headroom_r: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var _gap_r: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var _in_r: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var _out_r: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var _left_r: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var _tb_r: PackedInt64Array = PackedInt64Array([0, 1, 2, 3])
var _want_cell: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var _gap_cell: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
## 长度 5：五项约束候选值缓冲（下标 == JWUnits.Binding）。
var _cands: PackedInt64Array = PackedInt64Array()
## 长度 16：上季实际产量 / 上季生效约束 / 上季税前利润。
## 全部流量在 S01 §01.3 被整表清零，而 §3.6 的三项输入都是**上季已实现的量**，
## 所以快照只能在 reset_flows() 清零之前取（那是它们最后一次可见的时刻）。
var _prev_output_actual: PackedInt64Array = PackedInt64Array()
var _prev_binding: PackedInt64Array = PackedInt64Array()
var _prev_profit: PackedInt64Array = PackedInt64Array()


## S03 §3.1：滞后需求预期与计划产量（**不含本季信息**）。
## 步骤：S03 §3.1
## 前置：sold_prev 与 unmet_prev 是上季的实际值（用「成交 + 未满足」而不是产量）
## 后置：demand_expect 更新（跨季存量，存档必含）；output_plan >= 0；同时写 inventory 目标
## 不变量：INV-043（output_actual <= output_plan）
## 失败：无
func plan_output(sold_prev_uqs: PackedInt64Array, unmet_prev_uqs: PackedInt64Array,
		inventory: JWInventory, io: JWIoTable, params: PackedInt64Array) -> int:
	if sold_prev_uqs.size() != JWUnits.CELL or unmet_prev_uqs.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				sold_prev_uqs.size(), JWUnits.CELL)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	var smooth_ppm: int = params[JWUnits.Param.DEMAND_SMOOTH_PPM]
	var inv_target_ppm: int = params[JWUnits.Param.INVENTORY_TARGET_PPM]
	var r: int = 0
	while r < JWUnits.R:
		var s: int = 0
		while s < JWUnits.S:
			var cell: int = JWIds.idx_cell(r, s)
			# D_prev = 成交 + 未满足：用「卖得掉的量」而不是产量，避免卖不掉也照产。
			var d_prev: int = sold_prev_uqs[cell] + unmet_prev_uqs[cell]
			var e_prev: int = demand_expect[cell]
			# E = E_prev + mul_ppm(D_prev − E_prev, demand_smooth_ppm)：差额平滑，单次取整。
			var e: int = e_prev + JWMath.mul_ppm(d_prev - e_prev, smooth_ppm)
			demand_expect[cell] = JWMath.check_qty(e)
			# 不可库存部门（energy / services）的目标库存恒为 0（INV-049）。
			var target: int = 0
			if io.is_storable(s):
				target = JWMath.mul_ppm(e, inv_target_ppm)
			inventory.set_inventory_target(cell, target)
			# inv_gap 可负（库存高于目标时压低计划产量），plan 用 max(0, ·) 兜底。
			var inv_gap: int = target - inventory.inv_output[cell]
			var plan: int = e + inv_gap
			if plan < 0:
				plan = 0
			f_output_plan[cell] = JWMath.check_qty(plan)
			# R-ORDER-01：投入品目标存量按「下季预期产量」反算，而不是按本季实耗。
			# 本季 S05 买进的投入品供下季生产（INV-050），按本季实耗补货在计划回升时必然缺料，
			# 缺料 → 产量低于计划 → 未满足需求抬高预期 → 计划再抬高，形成材料约束的连锁收缩。
			# 下季产量的代理取 max(本季计划, 本季预期)：两者都是 S03 已知量，不含本季成交信息。
			var base_next: int = maxi(plan, e)
			var j: int = 0
			while j < JWUnits.S:
				var a: int = io.input_of(cell, j)
				var tgt: int = 0
				# 能源经电网当期配给、不入投入品库存（INV-051），不登记目标。
				if a > 0 and j != JWUnits.Sector.ENERGY:
					# rounding: ceil, reason=投入品目标不得少算（少一颗即被材料约束卡住）
					var need_next: int = JWMath.ceil_div(JWMath.mul(base_next, a), JWUnits.PPM)
					tgt = need_next + JWMath.mul_ppm(need_next, inv_target_ppm)
				inventory.set_input_target(JWIds.idx_inv(cell, j), tgt)
				j += 1
			s += 1
		r += 1
	return JWResult.OK


## S03 §3.5：投入订单与电力需求（只登记订单，本步不分配任何资源）。
## 步骤：S03 §3.5
## 前置：output_plan 已算出；energy_coeff 与 io_coeff 的能源行在加载期已交叉校验（V-IO-08）
## 后置：flow.region.electricity_demand_uqs 写入（含居民用电）
## 不变量：INV-044（系数为 0 跳过）；材料与电力**不在 S03/S04 分配**（§4.2）
## 失败：无
func order_inputs(io: JWIoTable, pop: JWPopulation, params: PackedInt64Array) -> int:
	# 材料订单没有对应的流量数组：docs/11 里 S03 唯一的材料侧产物是 flow.market.inventory_target_uqs
	# （已在 §3.1 经 inventory.set_inventory_target 登记），§5.6 的「企业投入与补库」需求就按它形成。
	# 因此本函数只需把电力需求登记到地区，不得在这里分配任何实物（§4.2）。
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	var rc: int = _recompute_energy_need(io)
	if rc != JWResult.OK:
		return rc
	var r: int = 0
	while r < JWUnits.R:
		var total: int = 0
		var s: int = 0
		while s < JWUnits.S:
			total += _need_energy[JWIds.idx_cell(r, s)]
			s += 1
		# 居民用电需求：首版内容包没有任何「人均用电」系数（regions.json / population_init.json
		# 都没有该字段），故本项恒为 0。它不是被省略，而是内容层尚未定义——见返回的 open_questions。
		# pop 形参保留在签名里，等该系数进内容包后在此处接上。
		var residential: int = 0
		f_elec_demand[r] = JWMath.check_qty(total + residential)
		r += 1
	return JWResult.OK


## S03 §3.6：扩产意愿（部门行为规则，不是 AI）。
## 步骤：S03 §3.6
## 前置：三项输入全部是**已实现的量**（上季瓶颈、上季利润、产能利用率）
## 后置：invest_intent >= 0；无任何外生加成项
## 不变量：静态检查——投资函数不得引用 expectation_ppm / trust_ppm / support_ppm
## 失败：capacity == 0 → util 记 0，不除零
func compute_invest_intent(capital: JWCapital, params: PackedInt64Array,
		io: JWIoTable = null) -> int:
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	var propensity_ppm: int = params[JWUnits.Param.INVEST_PROPENSITY_PPM]
	var r: int = 0
	while r < JWUnits.R:
		var s: int = 0
		while s < JWUnits.S:
			var cell: int = JWIds.idx_cell(r, s)
			var cap: int = capital.cell_capacity(cell)
			# 产能为 0 时利用率记 0（不除零，也不用 max(cap, 1) 造一个假的巨大利用率）。
			var util_ppm: int = 0
			if cap > 0:
				util_ppm = JWMath.clamp_i(
						JWMath.mul_div_floor(_prev_output_actual[cell], JWUnits.PPM, cap),
						0, JWUnits.PPM)
			var profit_prev: int = _prev_profit[cell]
			var intent: int = 0
			# 只有「上季被产能卡住」且「上季有利润」才扩产；两项都是已实现的量，无外生加成。
			if _prev_binding[cell] == JWUnits.Binding.CAPACITY and profit_prev > 0:
				intent = JWMath.mul_ppm_2(profit_prev, propensity_ppm, util_ppm)
			# R-INVEST-01：更新投资——补偿本季将发生的折旧，维持资本存量。
			# 输入是已实现的存量（资本价值）与内容常量（折旧率），不是「信心 +10」式的外生加成；
			# 基年资本形成 22 U/年 中有 13.15 U 正是折旧补偿，缺它则资本逐季萎缩、最终需求凭空少 13%。
			if io != null:
				intent += JWMath.mul_ppm(capital.cell_capital_value[cell], io.depreciation(s))
			f_invest_intent[cell] = JWMath.check_amount(intent)
			s += 1
		r += 1
	return JWResult.OK


## S05 §5.2：能源 cell 先结算，净出自用量，形成各地区可交付电力并配给。
## 步骤：S05 §5.1 第 1–2 步
## 前置：a(energy→energy) < 1_000_000（加载期已保证，INV-052）
## 后置：本地区用户获配 ≤ grid(r)（电网容量约束的是**交付给本地区用户**的电量，R-GRID-01）；
##       两级配给（生命线 → 生产用电），同档内按 split_lr；本地发电余量经全国输电补给他区缺口；
##       进口电力按份额先用（R-IMPORT-01）
## 不变量：INV-051（电力当期使用、不入库存）、INV-052、INV-060（本地配给与跨区输电两段各自精确）
## 失败：电力被写入库存 → Fault.ENERGY_STORED；配给和不等 → Fault.SPLIT_MISMATCH
##
## R-GRID-01（跨区输电）：原实现把每个地区的电网当作孤岛，且用本地区电网容量截断**本地区发电**。
## 结果是西岭（剧本设定的能源与资源供给区）的发电除本地少量用电外只能进全国零售市场或作废，
## 而用电大区的生产被电力卡住。改为：
##   第一段：各地区本地发电先供本地区用户，交付量受本地区电网容量约束；
##   第二段：各地区未被本地用掉的发电进入全国输电池，按各地区剩余缺口（以其电网余量封顶）配给，
##           缺口与余量两侧都按最大余数法拆分，付款按当季电价由用电 cell 付给发电地区的能源 cell；
##   第三段：仍未用掉的发电进入当季零售市场（居民与出口），季末未售部分才作废。
func settle_energy(capital: JWCapital, inventory: JWInventory, io: JWIoTable,
		labor: JWLaborMarket, params: PackedInt64Array, ledger: JWLedger = null,
		accounts: JWAccount = null, pricing: JWPricing = null,
		world: JWWorldMarket = null) -> int:
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	# 电力不可库存是内容层的硬约束（INV-049/INV-150）；被改成可库存即失去「当期使用」的前提。
	if io.is_storable(JWUnits.Sector.ENERGY):
		return JWResult.raise_fault(JWResult.Fault.ENERGY_STORED, JWUnits.Sector.ENERGY, 1)
	var rc: int = _recompute_energy_need(io)
	if rc != JWResult.OK:
		return rc
	var a_ee: int = io.io(JWUnits.Sector.ENERGY, JWUnits.Sector.ENERGY)
	# R-POWER-01：电力随配给按当季电价结算。三件结算对象缺一即不结算（旧调用方与单元测试夹具），
	# 此时退化为纯实物配给。
	var settle: bool = ledger != null and accounts != null and pricing != null
	var p_e: int = pricing.price_of(JWUnits.Sector.ENERGY) if settle else 0
	# R-IMPORT-01（电网进口）：生产用电中按进口份额由外部供电，经电网交付，按进口价付给 agent.row。
	# 没有 world（旧调用方与单元测试夹具）即不进口。
	var imp_share: int = 0
	var p_imp: int = 0
	if settle and world != null and world.import_share_ppm.size() == JWUnits.S:
		imp_share = world.import_share_ppm[JWUnits.Sector.ENERGY]
		# rounding: floor, reason=进口价 = 基价 × 进口价格乘数，与市场进口同一口径
		p_imp = JWMath.mul_ppm(JWUnits.BASE_PRICE, world.import_price(JWUnits.Sector.ENERGY))
	var p_afford: int = maxi(p_e, p_imp)

	# ── 第一段：逐地区发电、本地配给、进口 ──────────────────────────────────
	var r: int = 0
	while r < JWUnits.R:
		var e_cell: int = JWIds.idx_cell(r, JWUnits.Sector.ENERGY)
		var s: int = 0
		while s < JWUnits.S:
			_split_tb[s] = JWIds.idx_cell(r, s)
			s += 1
		rc = solve_output(e_cell, capital, labor, inventory, io)
		if rc != JWResult.OK:
			return rc
		var q_e: int = f_output_actual[e_cell]
		rc = inventory.consume_inputs(e_cell, q_e, io)
		if rc != JWResult.OK:
			return rc
		# 全部产量登记进当期供给账（JWInventory.store_output 的约定：能源 cell 也传入全部产量），
		# 否则 INV-047 的逐 cell 恒等式在能源 cell 上恒差一个 q_e。自用与交付在本函数内净出，
		# 不经市场，也就不进 f_sold。
		rc = inventory.store_output(e_cell, q_e, io)
		if rc != JWResult.OK:
			return rc
		# self_use = ceil(Q_e × a(energy→energy) / 1e6)：不得少算自用。
		var self_use: int = _ceil_mul_div(q_e, a_ee, JWUnits.PPM)
		if self_use > q_e:
			# a(energy→energy) < 1e6 时数学上不可能；出现即内容层违反 INV-052。
			return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, e_cell, self_use)
		# 能源 cell 的「获配电力」就是它自供的那部分，其余可交付。
		f_energy_allocated[e_cell] = self_use
		var deliver_total: int = q_e - self_use
		_gen_r[r] = deliver_total

		# 需求：生命线档（pubserv 与居民用电）= 地区需求 − 全部 cell 的生产用电需求；生产用电按现金可负担量封顶。
		var prod_all: int = 0
		var prod_grid: int = 0
		s = 0
		while s < JWUnits.S:
			var c2: int = JWIds.idx_cell(r, s)
			prod_all += _need_energy[c2]
			var w: int = 0
			if s != JWUnits.Sector.ENERGY:
				w = _need_energy[c2]
				# R-POWER-01：用电需求以现金可负担量为上限（不能花没有的钱；配给后即付款，不留应付）。
				if settle and p_afford > 0:
					var afford: int = JWMath.mul_div_floor(
							accounts.cash_of(JWIds.agent_of_cell(c2)), JWUnits.Q_SCALE, p_afford)
					if afford < w:
						w = afford
				prod_grid += w
			_split_w[s] = w
			_split_out[s] = 0
			_want_cell[c2] = w
			s += 1
		var lifeline: int = f_elec_demand[r] - prod_all
		if lifeline < 0:
			lifeline = 0
		var grid: int = capital.grid(r)
		if grid < 0:
			grid = 0
		# R-IMPORT-01：本地区生产用电的进口量 = 份额 × 参与配给的生产用电需求，
		# 受本季交付能力余额与电网容量（进口电力同样经电网交付）封顶。
		var imp_r: int = 0
		if imp_share > 0 and prod_grid > 0 and p_imp > 0:
			# rounding: floor, reason=进口量只取整一次，少进口优于凭空多进口
			imp_r = JWMath.mul_ppm(prod_grid, imp_share)
			imp_r = mini(imp_r, world.delivery_remaining(JWUnits.Sector.ENERGY))
			imp_r = mini(imp_r, grid)
			if imp_r < 0:
				imp_r = 0
		# 本地可交付给本地区用户的电量 = min(本地发电 + 进口, 电网容量)。
		var supply: int = mini(deliver_total + imp_r, grid)
		var alloc_lifeline: int = mini(lifeline, supply)
		var rest: int = supply - alloc_lifeline
		if rest >= prod_grid:
			# 供大于求：全额满足，不走拆分（拆分只在配给时才有意义）。
			s = 0
			while s < JWUnits.S:
				_split_out[s] = _split_w[s]
				s += 1
		else:
			var split_rc: int = JWMath.split_lr_into(rest, _split_w, _split_tb, _split_out)
			if split_rc != 0:
				return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, r, split_rc)
		var alloc_prod: int = 0
		s = 0
		while s < JWUnits.S:
			if s != JWUnits.Sector.ENERGY:
				f_energy_allocated[JWIds.idx_cell(r, s)] = _split_out[s]
				alloc_prod += _split_out[s]
			s += 1
		# INV-060（本地段）：Σ 配给 == min(本地可交付, 参与配给的需求)，精确相等。
		var alloc_sum: int = alloc_lifeline + alloc_prod
		if alloc_sum != mini(supply, lifeline + prod_grid):
			return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, supply, alloc_sum)
		# 进口电力先用（固定份额口径）：实际用掉的进口量 = min(进口量, 生产用电配给量)，
		# 按各 cell 配给量最大余数拆分，其余由本地区能源 cell 供给。
		var imp_used: int = mini(imp_r, alloc_prod)
		var imp_value: int = 0
		s = 0
		while s < JWUnits.S:
			_imp_part[s] = 0
			s += 1
		if imp_used > 0:
			var imp_rc: int = JWMath.split_lr_into(imp_used, _split_out, _split_tb, _imp_part)
			if imp_rc != 0:
				return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, r, imp_rc)
		s = 0
		while s < JWUnits.S:
			if s != JWUnits.Sector.ENERGY and settle and _split_out[s] > 0:
				var c_b: int = JWIds.idx_cell(r, s)
				var q_imp: int = _imp_part[s]
				var q_dom: int = _split_out[s] - q_imp
				if q_imp > 0:
					var v_imp: int = _pay_electricity_import(c_b, q_imp, p_imp, ledger, accounts, inventory)
					if v_imp < 0:
						return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, c_b, q_imp)
					imp_value += v_imp
				if q_dom > 0:
					var rc_pay: int = _pay_electricity(c_b, e_cell, q_dom, p_e, ledger, accounts,
							inventory)
					if rc_pay != JWResult.OK:
						return rc_pay
			s += 1
		if imp_used > 0:
			var rc_imp: int = world.record_import(JWUnits.Sector.ENERGY, imp_used, imp_value)
			if rc_imp != JWResult.OK:
				return rc_imp
		# 本地发电被本地用掉的量（生命线档由本地发电承担，进口只供生产用电）。
		var dom_used: int = alloc_sum - imp_used
		_dom_used_r[r] = dom_used
		_surplus_r[r] = maxi(0, deliver_total - dom_used)
		_headroom_r[r] = maxi(0, grid - alloc_sum)
		# 地区可供电力（报告的供需比分子）：本地可交付给本地区用户的量；跨区输入在第二段再加。
		f_elec_supply[r] = JWMath.check_qty(supply)
		r += 1

	# ── 第二段：全国输电（R-GRID-01）──────────────────────────────────────────
	# 缺口 = 各生产 cell 未获配的可负担需求；地区缺口以该地区电网余量封顶。
	var tot_sur: int = 0
	var tot_gap: int = 0
	r = 0
	while r < JWUnits.R:
		tot_sur += _surplus_r[r]
		var gap_r: int = 0
		var s3: int = 0
		while s3 < JWUnits.S:
			var c3: int = JWIds.idx_cell(r, s3)
			var g3: int = 0
			if s3 != JWUnits.Sector.ENERGY:
				g3 = maxi(0, _want_cell[c3] - f_energy_allocated[c3])
			_gap_cell[c3] = g3
			gap_r += g3
			s3 += 1
		_gap_r[r] = mini(gap_r, _headroom_r[r])
		tot_gap += _gap_r[r]
		r += 1
	var moved: int = mini(tot_sur, tot_gap)
	if moved > 0:
		# 汇入侧：先按地区缺口拆到地区，再按 cell 缺口拆到 cell；汇出侧：按各地区余量拆。
		var rc_in: int = JWMath.split_lr_into(moved, _gap_r, _tb_r, _in_r)
		if JWMath._split_last_fault != 0 or rc_in != 0:
			return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, moved, rc_in)
		var rc_out: int = JWMath.split_lr_into(moved, _surplus_r, _tb_r, _out_r)
		if JWMath._split_last_fault != 0 or rc_out != 0:
			return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, moved, rc_out)
		# 汇出余量逐地区扣减（西北角法：汇入 cell 按下标升序、汇出地区按下标升序配对，完全确定）。
		r = 0
		while r < JWUnits.R:
			_left_r[r] = _out_r[r]
			r += 1
		var src: int = 0
		r = 0
		while r < JWUnits.R:
			if _in_r[r] > 0:
				var s4: int = 0
				while s4 < JWUnits.S:
					_split_w[s4] = _gap_cell[JWIds.idx_cell(r, s4)]
					_split_tb[s4] = JWIds.idx_cell(r, s4)
					_split_out[s4] = 0
					s4 += 1
				var rc_c: int = JWMath.split_lr_into(_in_r[r], _split_w, _split_tb, _split_out)
				if JWMath._split_last_fault != 0 or rc_c != 0:
					return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, r, rc_c)
				s4 = 0
				while s4 < JWUnits.S:
					var need_q: int = _split_out[s4]
					var c_b2: int = JWIds.idx_cell(r, s4)
					if need_q > 0:
						f_energy_allocated[c_b2] = f_energy_allocated[c_b2] + need_q
					while need_q > 0:
						while src < JWUnits.R and _left_r[src] <= 0:
							src += 1
						if src >= JWUnits.R:
							# 汇出总量 == 汇入总量 == moved，走到这里即拆分口径不一致。
							return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, c_b2, need_q)
						var q_t: int = mini(need_q, _left_r[src])
						if settle:
							var rc_t: int = _pay_electricity(c_b2,
									JWIds.idx_cell(src, JWUnits.Sector.ENERGY), q_t, p_e, ledger,
									accounts, inventory)
							if rc_t != JWResult.OK:
								return rc_t
						_left_r[src] -= q_t
						_dom_used_r[src] += q_t
						need_q -= q_t
					s4 += 1
				f_elec_supply[r] = JWMath.check_qty(f_elec_supply[r] + _in_r[r])
			r += 1

	# ── 第三段：未被任何生产用户用掉的本地发电进入零售市场；作废量记回能源 cell ──
	r = 0
	while r < JWUnits.R:
		var e_cell2: int = JWIds.idx_cell(r, JWUnits.Sector.ENERGY)
		# 实际交付 = 自用（f_energy_allocated[能源 cell]）+ 本地配给与跨区输出（_dom_used_r）。
		f_elec_delivered[e_cell2] = JWMath.check_qty(f_energy_allocated[e_cell2] + _dom_used_r[r])
		var unmet_r: int = 0
		var s5: int = 0
		while s5 < JWUnits.S:
			if s5 != JWUnits.Sector.ENERGY:
				var c5: int = JWIds.idx_cell(r, s5)
				unmet_r += maxi(0, _want_cell[c5] - f_energy_allocated[c5])
			s5 += 1
		f_elec_unmet[r] = JWMath.check_qty(unmet_r)
		var left_gen: int = maxi(0, _gen_r[r] - _dom_used_r[r])
		inventory.set_energy_market_avail(e_cell2, left_gen)
		if left_gen > 0:
			f_energy_unused[e_cell2] = left_gen
		r += 1
	return JWResult.OK


## S05 §5.3：五项约束的整数换算与取最小（**本季 argmin 是报告「限制因素」的唯一数据源**）。
## 步骤：S05 §5.3
## 前置：能源 cell 跳过 bound_energy；系数为 0 的约束不产生候选值（continue / SENTINEL）
## 后置：output_actual == min(激活候选)；binding_code 为并列时序号最小者；
##       slack[binding] == 0，其余 slack >= 0；逐 cell 写 log.constraint_diag
## 不变量：INV-043, INV-044（禁止除零、禁止 max(c,1)）, INV-045（并列决胜固定序）
## 失败：五项全为 SENTINEL（理论不可能）→ Fault.UNBOUNDED_PRODUCTION
func solve_output(cell: int, capital: JWCapital, labor: JWLaborMarket,
		inventory: JWInventory, io: JWIoTable) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
	var s: int = JWIds.sector_of_cell(cell)

	# 1) 计划
	var bound_plan: int = f_output_plan[cell]

	# 2) 产能（维护欠账只降本季可用产能，不减资产，INV-055）
	var bound_capacity: int = capital.cell_capacity(cell)
	var backlog_ppm: int = capital.cell_maint_backlog[cell]
	if backlog_ppm > 0:
		bound_capacity = JWMath.mul_ppm(bound_capacity, JWUnits.PPM - backlog_ppm)

	# 「该约束是否适用」只能由**有没有非零系数**判定，不能由「值 == SENTINEL」反推：
	# SENTINEL 恒等于合法上界 QTY_MAX（JWUnits，docs/17 §4.1），于是「不适用」与
	# 「候选值恰好取到合法上界」在编码上是同一个数（ADV-J01 的哨兵碰撞）。
	# 这里用位掩码显式记住哪几项真的产生了候选值，取 min 时只在这些项里取
	# （INV-043「min(激活的候选约束)」、INV-044「系数为 0 的约束不产生候选值」）。
	# 计划与产能永远适用（docs/12 §5.3：两者永远有限），故掩码恒含 PLAN 与 CAPACITY。
	var active_mask: int = (1 << JWUnits.Binding.PLAN) | (1 << JWUnits.Binding.CAPACITY)

	# 3) 劳动（逐技能档取最紧；系数为 0 的档跳过，既不除零也不用 max(c, 1)）
	var bound_labor: int = JWUnits.SENTINEL
	var k: int = 0
	while k < JWUnits.K:
		var c: int = io.labor_of(cell, k)
		if c == 0:
			k += 1
			continue
		active_mask |= 1 << JWUnits.Binding.LABOR
		var avail: int = labor.employment(cell, k)
		var cand_k: int = JWMath.mul_div_floor(avail, JWUnits.PPM, c)
		if cand_k < bound_labor:
			bound_labor = cand_k
		k += 1

	# 4) 能源（能源 cell 自供，跳过此项，见 §5.2）
	var a_e: int = io.input_of(cell, JWUnits.Sector.ENERGY)
	var bound_energy: int = JWUnits.SENTINEL
	if a_e != 0 and s != JWUnits.Sector.ENERGY:
		active_mask |= 1 << JWUnits.Binding.ENERGY
		bound_energy = JWMath.mul_div_floor(f_energy_allocated[cell], JWUnits.PPM, a_e)

	# 5) 材料（逐投入部门取最紧；能源行不在此列，已由第 4 项表达）
	var bound_materials: int = JWUnits.SENTINEL
	var j: int = 0
	while j < JWUnits.S:
		if j == JWUnits.Sector.ENERGY:
			j += 1
			continue
		var a: int = io.input_of(cell, j)
		if a == 0:
			j += 1
			continue
		active_mask |= 1 << JWUnits.Binding.MATERIALS
		# 只看上季末持有的投入品库存：本季购入补的是下季可用量（INV-050）。
		var avail_j: int = inventory.inv_input[JWIds.idx_inv(cell, j)]
		var cand_j: int = JWMath.mul_div_floor(avail_j, JWUnits.PPM, a)
		if cand_j < bound_materials:
			bound_materials = cand_j
		j += 1

	_cands[JWUnits.Binding.PLAN] = bound_plan
	_cands[JWUnits.Binding.CAPACITY] = bound_capacity
	_cands[JWUnits.Binding.LABOR] = bound_labor
	_cands[JWUnits.Binding.ENERGY] = bound_energy
	_cands[JWUnits.Binding.MATERIALS] = bound_materials
	f_bound_plan[cell] = bound_plan
	f_bound_capacity[cell] = bound_capacity
	f_bound_labor[cell] = bound_labor
	f_bound_energy[cell] = bound_energy
	f_bound_materials[cell] = bound_materials

	# 取最小：固定序 plan(0) < capacity(1) < labor(2) < energy(3) < materials(4)，
	# **严格小于**才替换 ⇒ 并列时取序号最小者（INV-045 的决胜规则）。
	# 只在 active_mask 里取 min：不适用的一项根本**没有候选值**（INV-044），
	# 它槽里的 SENTINEL 只是占位，不得参与比较——否则当激活项恰好取到合法上界
	# QTY_MAX 时，一个不适用的约束会冒充 argmin（ADV-J01 的哨兵碰撞）。
	var q_actual: int = 0
	var binding: int = -1
	var n: int = 0
	while n < BOUND_N:
		if (active_mask & (1 << n)) != 0 and (binding < 0 or _cands[n] < q_actual):
			q_actual = _cands[n]
			binding = n
		n += 1
	if binding < 0:
		# 五项全不适用。计划与产能永远适用（docs/12 §5.3），理论上到不了这里。
		return JWResult.raise_fault(JWResult.Fault.UNBOUNDED_PRODUCTION, cell, active_mask)
	if q_actual < 0:
		q_actual = 0
	f_output_actual[cell] = JWMath.check_qty(q_actual)
	f_binding_code[cell] = binding

	# log.constraint_diag：逐 cell 的五项候选与松弛量，binding 项的 slack 恒为 0。
	d_cell[cell] = cell
	d_binding[cell] = binding
	var base: int = cell * BOUND_N
	n = 0
	while n < BOUND_N:
		d_cands[base + n] = _cands[n]
		d_slack[base + n] = _cands[n] - q_actual
		n += 1
	return JWResult.OK


## S05 §5.1 第 3 步：12 个 agri/manu/services cell 的生产（互不使用对方本季产出）。
## 步骤：S05 §5.1
## 前置：能源已结算；本季购入补的是**下季**可用库存
## 后置：逐 cell 调 solve_output → inventory.consume_inputs → inventory.store_output
## 不变量：INV-050（同季不得使用本季产出，T-U-NO-SAME-QUARTER-CHAIN）、INV-046、INV-047
## 失败：透支库存 → Fault.NEGATIVE_INVENTORY
func settle_production(capital: JWCapital, labor: JWLaborMarket, inventory: JWInventory,
		io: JWIoTable) -> int:
	# 固定顺序：地区升序 × 部门升序（== cell 下标升序），能源 cell 已在 §5.2 结算完毕。
	var r: int = 0
	while r < JWUnits.R:
		var s: int = 0
		while s < JWUnits.S:
			if s == JWUnits.Sector.ENERGY:
				s += 1
				continue
			var cell: int = JWIds.idx_cell(r, s)
			var rc: int = solve_output(cell, capital, labor, inventory, io)
			if rc != JWResult.OK:
				return rc
			var q_actual: int = f_output_actual[cell]
			# 投入品：从 q_actual 用 ceil 反算并扣减（不透支由 §5.4 的整数引理保证）。
			rc = inventory.consume_inputs(cell, q_actual, io)
			if rc != JWResult.OK:
				return rc
			# 电力：当季用掉多少由 q_actual 反算，配而未用的部分当季作废（不入库存）。
			var a_e: int = io.input_of(cell, JWUnits.Sector.ENERGY)
			var energy_use: int = 0
			if a_e != 0:
				energy_use = _ceil_mul_div(q_actual, a_e, JWUnits.PPM)
			var allocated: int = f_energy_allocated[cell]
			if energy_use > allocated:
				# bound_energy 的 floor 换算 + 这里的 ceil 反算保证不会发生（T-U-CEIL-SAFE）；
				# 真发生即 q_actual 推导有误，按透支处理，保留现场。
				return JWResult.raise_fault(JWResult.Fault.NEGATIVE_INVENTORY, cell,
						energy_use - allocated)
			f_energy_unused[cell] = allocated - energy_use
			# 成品：storable == 1 入库；storable == 0（services）直接进当期供给（INV-049）。
			rc = inventory.store_output(cell, q_actual, io)
			if rc != JWResult.OK:
				return rc
			s += 1
		r += 1
	return JWResult.OK


## S05：登记一笔销售（由 JWInventory 在成交后回调），用于 S06 的总产出。
## 步骤：S05 §5.6
## 前置：value_uu 与 qty_uqs 同时 >= 0
## 后置：_sales_rev 与 _sold_qty 累加
## 不变量：INV-112（**禁止用 Σ 销售额直接当 GDP**；这里只是增加值公式的一个输入项）
## 失败：无
func record_sale(cell: int, value_uu: int, qty_uqs: int) -> void:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return
	_sales_rev[cell] = JWMath.check_amount(_sales_rev[cell] + value_uu)
	_sold_qty[cell] = JWMath.check_qty(_sold_qty[cell] + qty_uqs)


## R-POWER-01：电网配电的价款结算（docs/18）。
## 步骤：S05 §5.2（配给落定之后、其余 cell 生产之前）
## 前置：qty 已按买方现金可负担量截断；seller 是买方所在地区的能源 cell
## 后置：买方现金 → 能源 cell 现金（kind = INTERMEDIATE_PURCHASE，与市场购投入同一分类；
##       S06 前由账本归集成能源 cell 的销售收入）；买方把 at_base(qty) 记入本季中间消耗，差价记入价差项（INV-119）
## 不变量：INV-115（全国：能源增加值 +value、买方增加值 −at_base、价差 +(at_base − value)，净变动恰为 0）
## 失败：透传 ledger.post 的错误码（可负担截断保证不会因现金不足而失败）
func _pay_electricity(buyer: int, seller: int, qty: int, p_e: int, ledger: JWLedger,
		accounts: JWAccount, inventory: JWInventory) -> int:
	# rounding: floor, reason=M1，价款按成交量×单价只取整一次，少收优于凭空多收
	var value: int = JWMath.mul_div_floor(qty, p_e, JWUnits.Q_SCALE)
	if value > 0:
		var rc: int = ledger.post(JWUnits.Kind.INTERMEDIATE_PURCHASE,
				JWIds.idx_account(JWIds.agent_of_cell(buyer), JWIds.ACC_CASH),
				JWIds.idx_account(JWIds.agent_of_cell(seller), JWIds.ACC_CASH),
				value, qty, JWUnits.Sector.ENERGY, 0, buyer)
		if rc != JWResult.OK:
			return rc
		# 不在这里 record_sale：JWTurnRunner._collect_sales_from_ledger 在 S06 前从账本逐行归集
		# 全部 INTERMEDIATE_PURCHASE 收款腿作为卖方销售额——账本是唯一事实来源，手记即重复计入。
	_elec_bought_qty[buyer] = JWMath.check_qty(_elec_bought_qty[buyer] + qty)
	inventory.add_price_variance(buyer, _at_base(qty) - value)
	return JWResult.OK


## R-IMPORT-01：进口电力付款（买方 cell → agent.row），返回付款额；过账被拒返回 −1。
## 买方侧记账与国内电力相同：_elec_bought_qty 计入中间消耗，价差 = at_base(qty) − 实付。
func _pay_electricity_import(buyer: int, qty: int, p_imp: int, ledger: JWLedger,
		accounts: JWAccount, inventory: JWInventory) -> int:
	# rounding: floor, reason=M1，价款按成交量×单价只取整一次
	var value: int = JWMath.mul_div_floor(qty, p_imp, JWUnits.Q_SCALE)
	if value > 0:
		var rc: int = ledger.post(JWUnits.Kind.INTERMEDIATE_PURCHASE,
				JWIds.idx_account(JWIds.agent_of_cell(buyer), JWIds.ACC_CASH),
				JWIds.idx_account(JWIds.AGENT_ROW, JWIds.ACC_CASH),
				value, qty, JWUnits.Sector.ENERGY, 0, buyer)
		if rc != JWResult.OK:
			return -1
	_elec_bought_qty[buyer] = JWMath.check_qty(_elec_bought_qty[buyer] + qty)
	inventory.add_price_variance(buyer, _at_base(qty) - value)
	return value


## S06 §6.2：总产出、中间投入、增加值（名义与基年价两轨）。
## 步骤：S06 §6.2
## 前置：S05 已完成；损耗计入中间消耗（INV-053）
## 后置：value_added == gross_output − intermediate 逐 cell 成立；
##       value_added_real 全部用数量口径重算
## 不变量：INV-111、INV-053、INV-117（**禁止用名义值除以任何价格指数**，
##          静态检查本函数不引用 consumer_index_ppm）
## 失败：无（单个 cell 增加值允许为负，OQ-219）
func compute_value_added(inventory: JWInventory, io: JWIoTable) -> int:
	# docs/12 §6.2：库存变动、损耗与耗用量都是**数量口径**（μQ_s），必须经 at_base 换成 μU
	# 才能与 sales_rev（现价 μU）相加。R-SCALE-01 之前 BASE_PRICE / Q_SCALE == 1，
	# 两者碰巧是同一个整数，本函数曾直接拿数量当金额用；现在这个系数是 1000，不换算会让
	# §6.4 的 `expenditure == production + price_variance`（INV-115）差三个数量级。
	# at_base 对加减法精确线性且无余数（§6.2 的旁注），所以逐项换算与先求差再换算同值。
	var r: int = 0
	while r < JWUnits.R:
		var s: int = 0
		while s < JWUnits.S:
			var cell: int = JWIds.idx_cell(r, s)
			var sales_rev: int = _sales_rev[cell]
			var d_inv_out: int = _at_base(inventory.d_inventory_output(cell))
			var spoil_out: int = _at_base(inventory.spoilage_out(cell))
			var spoil_in: int = _at_base(inventory.spoilage_in_total(cell))
			var used: int = _at_base(inventory.used_total(cell))
			var gross: int = sales_rev + d_inv_out + spoil_out
			# R-POWER-01：经电网购入的电力是中间消耗，按基年价计值（现价差额已进价差项）。
			var elec: int = _at_base(_elec_bought_qty[cell])
			var inter: int = used + spoil_out + spoil_in + elec
			f_gross_output[cell] = JWMath.check_amount(gross)
			f_intermediate[cell] = JWMath.check_amount(inter)
			f_value_added[cell] = JWMath.check_amount(gross - inter)
			# 实际值走数量口径：成交量按基年价计值替换成交额，其余项本来就已按基年价计值。
			f_value_added_real[cell] = JWMath.check_amount(
					_at_base(_sold_qty[cell]) + d_inv_out - used - spoil_in - elec)
			s += 1
		r += 1
	return JWResult.OK


## 数量（μQ_s）按基年价计值成 μU（docs/12 §0.3.3 的 at_base）。
## 步骤：S06 §6.2
## 前置：无
## 后置：返回 floor(qty × BASE_PRICE / Q_SCALE)；系数为整数 1000，故无余数
## 不变量：R-SCALE-01 连带要求 1（先乘后除一律走 mul_div_floor）
## 失败：无
static func _at_base(qty_uqs: int) -> int:
	return JWMath.mul_div_floor(qty_uqs, JWUnits.BASE_PRICE, JWUnits.Q_SCALE)


## S06 §6.6：税前利润与结转亏损（价差进经营结果）。
## 步骤：S06 §6.6
## 前置：折旧已由 JWCapital 算出并落账；价差来自 JWInventory
## 后置：operating_surplus = value_added − wage_bill（**按残差定义**，INV-116 因此是定义式）；
##       profit_pretax = value_added − wage_bill − depreciation + price_variance；
##       loss_carryforward 按 §6.6 的公式更新；out_taxable 供 JWTreasury 用
## 不变量：INV-116、INV-113（补助不进 gross_output、不进任何 GDP 口径）
## 失败：无
func compute_profit(labor: JWLaborMarket, capital: JWCapital, inventory: JWInventory,
		out_taxable_by_cell: PackedInt64Array, params: PackedInt64Array) -> int:
	if out_taxable_by_cell.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				out_taxable_by_cell.size(), JWUnits.CELL)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	var r: int = 0
	while r < JWUnits.R:
		var s: int = 0
		while s < JWUnits.S:
			var cell: int = JWIds.idx_cell(r, s)
			var va: int = f_value_added[cell]
			var wage: int = labor.f_wage_bill[cell]
			var dep: int = capital.f_cell_dep_uu[cell]
			var pv: int = inventory.price_variance(cell)
			# 营业盈余按残差定义（含固定资本消耗），所以 INV-116 是定义式而不是待验证的等式。
			# 补助不进这里：它既不进 gross_output 也不进任何 GDP 口径（INV-113）。
			f_operating_surplus[cell] = JWMath.check_amount(va - wage)
			var profit: int = va - wage - dep + pv
			f_profit_pretax[cell] = JWMath.check_amount(profit)
			# 先用**本季之前**的结转亏损抵扣，再更新结转亏损，顺序不可交换。
			var carry: int = loss_carryforward[cell]
			var taxable: int = profit - carry
			if taxable < 0:
				taxable = 0
			var profit_pos: int = profit
			if profit_pos < 0:
				profit_pos = 0
			var loss_new: int = carry - profit_pos
			if loss_new < 0:
				loss_new = 0
			if profit < 0:
				loss_new += -profit
			loss_carryforward[cell] = JWMath.check_amount(loss_new)
			out_taxable_by_cell[cell] = taxable
			s += 1
		r += 1
	return JWResult.OK


## S06 §6.7：可分配利润（扣税后按 payout_ratio），交给 JWPopulation 分回各组。
## 步骤：S06 §6.7
## 前置：compute_profit 与 collect_profit_tax 已完成
## 后置：out_distributable 被填满；f_distributed 写入
## 不变量：INV-086（财产收入是可支配收入的一项）
## 失败：无
func compute_distributable(out_distributable: PackedInt64Array, params: PackedInt64Array) -> int:
	if out_distributable.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				out_distributable.size(), JWUnits.CELL)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	var payout_ppm: int = params[JWUnits.Param.PAYOUT_RATIO_PPM]
	var r: int = 0
	while r < JWUnits.R:
		var s: int = 0
		while s < JWUnits.S:
			var cell: int = JWIds.idx_cell(r, s)
			# 已缴利润税由 JWTreasury 写进 flow.cell.tax_profit_paid_uu（本类只读它）。
			var distributable: int = f_profit_pretax[cell] - f_tax_profit_paid[cell]
			if distributable < 0:
				distributable = 0
			var payout: int = JWMath.mul_ppm(distributable, payout_ppm)
			f_distributed[cell] = JWMath.check_amount(payout)
			out_distributable[cell] = payout
			s += 1
		r += 1
	return JWResult.OK


## 只读访问器：本季实际产量（μQ_s）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-043
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func output_actual(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	return f_output_actual[cell]


## 只读访问器：本季生效的限制因素（枚举 JWUnits.Binding）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-045（binding_code 是报告的唯一数据源）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func binding_code(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	return f_binding_code[cell]


## 只读访问器：某一项约束的候选产量（which ∈ JWUnits.Binding；不适用时为 SENTINEL）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-044、INV-045
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func bound_value(cell: int, which: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	if which == JWUnits.Binding.PLAN:
		return f_bound_plan[cell]
	if which == JWUnits.Binding.CAPACITY:
		return f_bound_capacity[cell]
	if which == JWUnits.Binding.LABOR:
		return f_bound_labor[cell]
	if which == JWUnits.Binding.ENERGY:
		return f_bound_energy[cell]
	if which == JWUnits.Binding.MATERIALS:
		return f_bound_materials[cell]
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, which, BOUND_N)
	return 0


## 只读访问器：名义增加值（μU，可为负）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-111
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func value_added(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	return f_value_added[cell]


## 只读访问器：基年价增加值（μU）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-117
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func value_added_real(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	return f_value_added_real[cell]


## 只读访问器：税前利润（μU，可为负）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-116
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func profit_pretax(cell: int) -> int:
	if cell < 0 or cell >= JWUnits.CELL:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, cell, JWUnits.CELL)
		return 0
	return f_profit_pretax[cell]


## 只读访问器：本季实际产量整表，供 JWProjectQueue 折施工能力（数组形参，不反向依赖）。
## 步骤：S05 §5.5
## 前置：S05 生产已完成
## 后置：不改状态
## 不变量：INV-043
## 失败：无
func output_actual_array() -> PackedInt64Array:
	return f_output_actual


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：尚未 allocate
## 后置：cell 相关数组长度 CELL，电力两项长度 R，log.constraint_diag 按诊断布局
## 不变量：INV-136
## 失败：无
func allocate() -> void:
	var n: int = JWUnits.CELL
	demand_expect.resize(n)
	demand_expect.fill(0)
	loss_carryforward.resize(n)
	loss_carryforward.fill(0)
	f_output_plan.resize(n)
	f_output_plan.fill(0)
	f_bound_plan.resize(n)
	f_bound_plan.fill(0)
	f_bound_capacity.resize(n)
	f_bound_capacity.fill(0)
	f_bound_labor.resize(n)
	f_bound_labor.fill(0)
	f_bound_energy.resize(n)
	f_bound_energy.fill(0)
	f_bound_materials.resize(n)
	f_bound_materials.fill(0)
	f_binding_code.resize(n)
	f_binding_code.fill(0)
	f_output_actual.resize(n)
	f_output_actual.fill(0)
	f_energy_allocated.resize(n)
	f_energy_allocated.fill(0)
	f_energy_unused.resize(n)
	f_energy_unused.fill(0)
	f_elec_delivered.resize(n)
	f_elec_delivered.fill(0)
	f_elec_unmet.resize(JWUnits.R)
	f_elec_unmet.fill(0)
	f_invest_intent.resize(n)
	f_invest_intent.fill(0)
	f_gross_output.resize(n)
	f_gross_output.fill(0)
	f_intermediate.resize(n)
	f_intermediate.fill(0)
	f_value_added.resize(n)
	f_value_added.fill(0)
	f_value_added_real.resize(n)
	f_value_added_real.fill(0)
	f_operating_surplus.resize(n)
	f_operating_surplus.fill(0)
	f_profit_pretax.resize(n)
	f_profit_pretax.fill(0)
	f_tax_profit_paid.resize(n)
	f_tax_profit_paid.fill(0)
	f_distributed.resize(n)
	f_distributed.fill(0)
	f_subsidy_received.resize(n)
	f_subsidy_received.fill(0)
	_sales_rev.resize(n)
	_sales_rev.fill(0)
	_elec_bought_qty.resize(n)
	_elec_bought_qty.fill(0)
	_sold_qty.resize(n)
	_sold_qty.fill(0)
	f_elec_demand.resize(JWUnits.R)
	f_elec_demand.fill(0)
	f_elec_supply.resize(JWUnits.R)
	f_elec_supply.fill(0)
	d_cell.resize(n)
	d_cell.fill(0)
	d_binding.resize(n)
	d_binding.fill(0)
	d_cands.resize(n * BOUND_N)
	d_cands.fill(0)
	d_slack.resize(n * BOUND_N)
	d_slack.fill(0)
	_need_energy.resize(n)
	_need_energy.fill(0)
	_prev_output_actual.resize(n)
	_prev_output_actual.fill(0)
	_prev_binding.resize(n)
	_prev_binding.fill(0)
	_prev_profit.resize(n)
	_prev_profit.fill(0)
	_split_w.resize(JWUnits.S)
	_split_w.fill(0)
	_split_tb.resize(JWUnits.S)
	_split_tb.fill(0)
	_split_out.resize(JWUnits.S)
	_split_out.fill(0)
	_deliver.resize(JWUnits.R)
	_deliver.fill(0)
	# R-SCENARIO-02：按地区排列的季内缓冲随地区数定长（此前是 4 格字面量）。
	_gen_r = _zeros_n(JWUnits.R)
	_dom_used_r = _zeros_n(JWUnits.R)
	_surplus_r = _zeros_n(JWUnits.R)
	_headroom_r = _zeros_n(JWUnits.R)
	_gap_r = _zeros_n(JWUnits.R)
	_in_r = _zeros_n(JWUnits.R)
	_out_r = _zeros_n(JWUnits.R)
	_left_r = _zeros_n(JWUnits.R)
	_tb_r = PackedInt64Array()
	for r: int in JWUnits.R:
		_tb_r.append(r)
	_want_cell = _zeros_n(JWUnits.CELL)
	_gap_cell = _zeros_n(JWUnits.CELL)
	_cands.resize(BOUND_N)
	_cands.fill(0)


static func _zeros_n(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(0)
	return a


## §1.6 状态块协议：只读取用（返回引用，调用方不得写）。
## 步骤：LOAD / 哈希 / 存档
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return demand_expect
	if i == 1:
		return loss_carryforward
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：仅 LOAD / MIG（静态检查：调用点必须在 systems/content_loader.gd 或 systems/saves.gd）。
## 步骤：LOAD / MIG
## 前置：allocate() 已调用；v 长度与契约一致
## 后置：对应数组逐位等于 v
## 不变量：INV-136
## 失败：越界或长度不符 → INDEX_OUT_OF_RANGE / Load.SCHEMA_HEADER
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i,
				STATE_ARRAY_IDS.size())
	if v.size() != JWUnits.CELL:
		# 长度不符是 schema 问题（读档或内容包与本构建不一致），不是运行期故障。
		return JWResult.Load.SCHEMA_HEADER
	if i == 0:
		demand_expect = v
	else:
		loss_carryforward = v
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
	if i == 0:
		return f_output_plan
	if i == 1:
		return f_bound_plan
	if i == 2:
		return f_bound_capacity
	if i == 3:
		return f_bound_labor
	if i == 4:
		return f_bound_energy
	if i == 5:
		return f_bound_materials
	if i == 6:
		return f_binding_code
	if i == 7:
		return f_output_actual
	if i == 8:
		return f_energy_allocated
	if i == 9:
		return f_energy_unused
	if i == 10:
		return f_elec_demand
	if i == 11:
		return f_elec_supply
	if i == 12:
		return f_invest_intent
	if i == 13:
		return f_gross_output
	if i == 14:
		return f_intermediate
	if i == 15:
		return f_value_added
	if i == 16:
		return f_value_added_real
	if i == 17:
		return f_operating_surplus
	if i == 18:
		return f_profit_pretax
	if i == 19:
		return f_tax_profit_paid
	if i == 20:
		return f_distributed
	if i == 21:
		return f_subsidy_received
	if i == 22:
		return _sales_rev
	if i == 23:
		return _sold_qty
	if i == 24:
		return f_elec_delivered
	if i == 25:
		return f_elec_unmet
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
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
## 后置：二十四个流量数组全 0
## 不变量：INV-010
## 失败：无
func reset_flows() -> void:
	# 清零之前先留下 §3.6 要用的三项「上季已实现的量」：
	# 本步是它们最后一次可见的时刻（S01 之后整季都读不到上季流量）。
	var i: int = 0
	while i < JWUnits.CELL:
		_prev_output_actual[i] = f_output_actual[i]
		_prev_binding[i] = f_binding_code[i]
		_prev_profit[i] = f_profit_pretax[i]
		i += 1
	# 逐个显式清零（不经 flow_array 的返回值写，避免依赖 Packed 数组的引用语义）。
	f_output_plan.fill(0)
	f_bound_plan.fill(0)
	f_bound_capacity.fill(0)
	f_bound_labor.fill(0)
	f_bound_energy.fill(0)
	f_bound_materials.fill(0)
	f_binding_code.fill(0)
	f_output_actual.fill(0)
	f_energy_allocated.fill(0)
	f_energy_unused.fill(0)
	f_elec_delivered.fill(0)
	f_elec_unmet.fill(0)
	f_elec_demand.fill(0)
	f_elec_supply.fill(0)
	f_invest_intent.fill(0)
	f_gross_output.fill(0)
	f_intermediate.fill(0)
	f_value_added.fill(0)
	f_value_added_real.fill(0)
	f_operating_surplus.fill(0)
	f_profit_pretax.fill(0)
	f_tax_profit_paid.fill(0)
	f_distributed.fill(0)
	f_subsidy_received.fill(0)
	_sales_rev.fill(0)
	_sold_qty.fill(0)
	_elec_bought_qty.fill(0)


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 已调用
## 后置：不改状态
## 不变量：INV-010
## 失败：无
func flow_abs_sum() -> int:
	var acc: int = 0
	var k: int = 0
	while k < FLOW_ARRAY_IDS.size():
		acc += JWMath.sum_abs(flow_array(k))
		k += 1
	return acc


# ── 私有工具 ───────────────────────────────────────────────────────────────

## 由 f_output_plan 与 IO 表能源行反算逐 cell 的生产用电需求（μQ_energy）。
## 步骤：S03 §3.5、S05 §5.2
## 前置：f_output_plan 已写
## 后置：_need_energy 逐位等于 ceil(output_plan × a_e / 1e6)；系数为 0 的 cell 记 0
## 不变量：INV-044（系数为 0 跳过，不除零）
## 失败：无
func _recompute_energy_need(io: JWIoTable) -> int:
	var r: int = 0
	while r < JWUnits.R:
		var s: int = 0
		while s < JWUnits.S:
			var cell: int = JWIds.idx_cell(r, s)
			var a_e: int = io.input_of(cell, JWUnits.Sector.ENERGY)
			if a_e == 0:
				_need_energy[cell] = 0
			else:
				_need_energy[cell] = _ceil_mul_div(f_output_plan[cell], a_e, JWUnits.PPM)
			s += 1
		r += 1
	return JWResult.OK


## 无溢出的 ceil(a × b / c)，c > 0，a >= 0。
## 步骤：一切「产量 → 投入消耗 / 用工 / 自用电」的反算（docs/10 §0.10 规定必须 ceil）
## 前置：a >= 0，b >= 0，c > 0
## 后置：精确等于 ceil(a × b / c) 的数学真值，中间量不溢出
## 不变量：INV-046（不得少算投入）、R-SCALE-01（先乘后除只能走 mul_div_floor）
## 失败：同 JWMath.mul_div_floor
##
## ceil(x) == −floor(−x)，于是 ceil(a·b/c) == −floor((−a)·b/c) == −mul_div_floor(−a, b, c)。
## 这样仍然只用 mul_div_floor 这一个入口，不出现任何裸的 a × b。
static func _ceil_mul_div(a: int, b: int, c: int) -> int:
	if a == 0 or b == 0:
		return 0
	return -JWMath.mul_div_floor(-a, b, c)


## §1.6 状态块协议：读档时写回流量数组（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_array 逐项对称生成）。
## 步骤：LOAD（JWSaves 经 JWSimState 调用）
## 前置：v 的长度与本块当前分配的长度一致（长度是 schema 的一部分，INV-136）
## 后置：对应成员被整体替换
## 不变量：INV-133（读档后与原进程逐位相同）
## 失败：下标越界或长度不符 → INDEX_OUT_OF_RANGE
func set_flow_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != f_output_plan.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_output_plan = v.duplicate()
		return JWResult.OK
	if i == 1:
		if v.size() != f_bound_plan.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_bound_plan = v.duplicate()
		return JWResult.OK
	if i == 2:
		if v.size() != f_bound_capacity.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_bound_capacity = v.duplicate()
		return JWResult.OK
	if i == 3:
		if v.size() != f_bound_labor.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_bound_labor = v.duplicate()
		return JWResult.OK
	if i == 4:
		if v.size() != f_bound_energy.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_bound_energy = v.duplicate()
		return JWResult.OK
	if i == 5:
		if v.size() != f_bound_materials.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_bound_materials = v.duplicate()
		return JWResult.OK
	if i == 6:
		if v.size() != f_binding_code.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_binding_code = v.duplicate()
		return JWResult.OK
	if i == 7:
		if v.size() != f_output_actual.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_output_actual = v.duplicate()
		return JWResult.OK
	if i == 8:
		if v.size() != f_energy_allocated.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_energy_allocated = v.duplicate()
		return JWResult.OK
	if i == 9:
		if v.size() != f_energy_unused.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_energy_unused = v.duplicate()
		return JWResult.OK
	if i == 10:
		if v.size() != f_elec_demand.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_elec_demand = v.duplicate()
		return JWResult.OK
	if i == 11:
		if v.size() != f_elec_supply.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_elec_supply = v.duplicate()
		return JWResult.OK
	if i == 12:
		if v.size() != f_invest_intent.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_invest_intent = v.duplicate()
		return JWResult.OK
	if i == 13:
		if v.size() != f_gross_output.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_gross_output = v.duplicate()
		return JWResult.OK
	if i == 14:
		if v.size() != f_intermediate.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_intermediate = v.duplicate()
		return JWResult.OK
	if i == 15:
		if v.size() != f_value_added.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_value_added = v.duplicate()
		return JWResult.OK
	if i == 16:
		if v.size() != f_value_added_real.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_value_added_real = v.duplicate()
		return JWResult.OK
	if i == 17:
		if v.size() != f_operating_surplus.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_operating_surplus = v.duplicate()
		return JWResult.OK
	if i == 18:
		if v.size() != f_profit_pretax.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_profit_pretax = v.duplicate()
		return JWResult.OK
	if i == 19:
		if v.size() != f_tax_profit_paid.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_tax_profit_paid = v.duplicate()
		return JWResult.OK
	if i == 20:
		if v.size() != f_distributed.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_distributed = v.duplicate()
		return JWResult.OK
	if i == 21:
		if v.size() != f_subsidy_received.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_subsidy_received = v.duplicate()
		return JWResult.OK
	if i == 22:
		if v.size() != _sales_rev.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		_sales_rev = v.duplicate()
		return JWResult.OK
	if i == 23:
		if v.size() != _sold_qty.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		_sold_qty = v.duplicate()
		return JWResult.OK
	if i == 24:
		if v.size() != f_elec_delivered.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_elec_delivered = v.duplicate()
		return JWResult.OK
	if i == 25:
		if v.size() != f_elec_unmet.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_elec_unmet = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
