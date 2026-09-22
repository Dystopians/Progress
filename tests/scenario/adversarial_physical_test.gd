## 对抗性验收套件 B：物资守恒攻击（D 族）、人口守恒攻击（E 族）、数值边界攻击（J 族）。
##
## 依据（只依据契约，不参考任何模块实现）：
##   docs/18 裁定 —— R-SCALE-01（1 U = 1e9 μU；AMOUNT_MAX = 4e15；PRICE ∈ [4e8, 2.5e9]；
##                    「先乘后除」只允许 JWMath.mul_div_floor）
##   docs/12 §5（S05 生产与交易）、§7（S07 跨期变化）的整数公式
##   docs/10 §14 不变量总表 INV-002…INV-007、INV-043…INV-053、INV-071…INV-086
##   docs/31 §5 D 族 ADV-D01…D07、§6 E 族 ADV-E01…E06、§11 J 族 ADV-J01…J07
##   docs/17 §4.7/§4.13/§4.14/§4.15/§4.16/§4.17/§4.18/§4.19（成员与签名，签名不得改）
##
## 立场（docs/31 §0.2）：任何一条攻击的期望结局只有三种 —— REJECT / ARREARS / 期望永不发生的 FAULT。
## **第四类「静默改账」一律判失败**：负库存被抹成 0、被挡回的人被吞掉、除零被 max(c,1) 伪装成 0%、
## 溢出被饱和截断，都必须在这里变红。
##
## 每个断言的期望值都在消息里写明推导来源，失败时能一眼分辨「实现错」还是「契约变了」。
## 纪律：JWResult 的故障登记是静态的、跨测试方法残留，故每个方法前后都 clear_pending()。
extends JWTest

# ── 契约常量的本地别名（数值来自 JWUnits 与 docs/10，不在此处重新定义） ──────

const AGRI: int = JWUnits.Sector.AGRI
const MANU: int = JWUnits.Sector.MANU
const ENERGY: int = JWUnits.Sector.ENERGY
const SERVICES: int = JWUnits.Sector.SERVICES

const LOW: int = JWUnits.Skill.LOW
const MID: int = JWUnits.Skill.MID
const HIGH: int = JWUnits.Skill.HIGH

const MINOR: int = JWUnits.Age.MINOR
const WORKING: int = JWUnits.Age.WORKING
const ELDER: int = JWUnits.Age.ELDER

const B_PLAN: int = JWUnits.Binding.PLAN
const B_CAPACITY: int = JWUnits.Binding.CAPACITY
const B_LABOR: int = JWUnits.Binding.LABOR
const B_ENERGY: int = JWUnits.Binding.ENERGY
const B_MATERIALS: int = JWUnits.Binding.MATERIALS

const PPM: int = JWUnits.PPM
const Q_SCALE: int = JWUnits.Q_SCALE

## 迁移夹具：北原（低工资、劳动力过剩）→ 中州（高工资）
const R_FROM: int = 0
const R_TO: int = 1
## 迁移成本 μU/人（剧本 2 000…4 000 μU，已随 R-SCALE-01 ×1000，取中值）
const MIG_COST_UU: int = 3_000_000
## param.persons_per_housing_unit
const PERSONS_PER_UNIT: int = 3
## 三档季度工资率 μU/人/季（R-SCALE-01 后人均季度劳动报酬约 1 360 μU）
const WAGE_LOW: int = 1_000
const WAGE_MID: int = 1_360
const WAGE_HIGH: int = 2_000

# ── 夹具 ───────────────────────────────────────────────────────────────────

var io: JWIoTable = null
var cap: JWCapital = null
var lab: JWLaborMarket = null
var inv: JWInventory = null
var sec: JWSectorModel = null
var pop: JWPopulation = null
var mig: JWMigration = null
var pricing: JWPricing = null
var accounts: JWAccount = null
var ledger: JWLedger = null
var rng: JWRngStreams = null
var params: PackedInt64Array = PackedInt64Array()


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(JWUnits.Phase.S05)

	io = JWIoTable.new()
	io.allocate()
	io.io_coeff = _zeros(JWUnits.IO_N)
	io.labor_coeff = _zeros(JWUnits.EMP_N)
	io.energy_coeff = _zeros(JWUnits.CELL)
	io.spoilage_ppm = _zeros(JWUnits.S)
	io.depreciation_ppm = _zeros(JWUnits.S)
	io.capacity_per_capital_ppm = _zeros(JWUnits.S)
	io.emission_ppm = _zeros(JWUnits.S)
	# INV-049 / INV-150：energy 与 services 必须不可库存。
	io.storable = PackedInt64Array([1, 1, 0, 0])

	cap = JWCapital.new()
	cap.allocate()
	cap.cell_capacity_active = _zeros(JWUnits.CELL)
	cap.cell_capacity_pending = _zeros(JWUnits.CELL)
	cap.cell_capital_value = _zeros(JWUnits.CELL)
	cap.cell_wip = _zeros(JWUnits.CELL)
	cap.cell_maint_backlog = _zeros(JWUnits.CELL)
	cap.grid_capacity = _zeros(JWUnits.R)
	cap.housing_stock = _zeros(JWUnits.R)
	cap.housing_capacity = _zeros(JWUnits.R)
	cap.env_exposure = _zeros(JWUnits.R)
	cap.f_emissions = _zeros(JWUnits.R)

	lab = JWLaborMarket.new()
	lab.allocate()
	lab.cell_employment = _zeros(JWUnits.EMP_N)
	lab.pub_employment = _zeros(JWUnits.PUBSERV_EMP_N)
	lab.f_hires = _zeros(JWUnits.EMP_N)
	lab.f_separations = _zeros(JWUnits.EMP_N)

	inv = JWInventory.new()
	inv.allocate()
	inv.inv_output = _zeros(JWUnits.CELL)
	inv.inv_input = _zeros(JWUnits.INV_N)
	inv.f_consumed = _zeros(JWUnits.INV_N)
	inv.f_purchased = _zeros(JWUnits.INV_N)
	inv.f_sold = _zeros(JWUnits.CELL)
	inv.f_spoilage_out = _zeros(JWUnits.CELL)
	inv.f_spoilage_in = _zeros(JWUnits.INV_N)
	inv.f_unmet_demand = _zeros(JWUnits.CELL)
	inv.m_supply = _zeros(JWUnits.S)
	inv.m_demand = _zeros(JWUnits.MARKET_N)
	inv.m_traded = _zeros(JWUnits.MARKET_N)
	inv.m_unmet = _zeros(JWUnits.MARKET_N)
	inv.m_rule = _zeros(JWUnits.S)
	inv.m_inv_target = _zeros(JWUnits.CELL)

	sec = JWSectorModel.new()
	sec.allocate()
	sec.f_output_plan = _zeros(JWUnits.CELL)
	sec.f_bound_plan = _zeros(JWUnits.CELL)
	sec.f_bound_capacity = _zeros(JWUnits.CELL)
	sec.f_bound_labor = _zeros(JWUnits.CELL)
	sec.f_bound_energy = _zeros(JWUnits.CELL)
	sec.f_bound_materials = _zeros(JWUnits.CELL)
	sec.f_binding_code = _zeros(JWUnits.CELL)
	sec.f_output_actual = _zeros(JWUnits.CELL)
	sec.f_energy_allocated = _zeros(JWUnits.CELL)
	sec.f_energy_unused = _zeros(JWUnits.CELL)
	sec.f_elec_demand = _zeros(JWUnits.R)
	sec.f_elec_supply = _zeros(JWUnits.R)

	pop = JWPopulation.new()
	pop.allocate()
	pop.population = _zeros(JWUnits.GROUP)
	pop.participation_ppm = _zeros(JWUnits.GROUP)
	pop.employed = _zeros(JWUnits.GROUP_EMP_N)
	pop.education_cohort = _zeros(JWUnits.EDU_N)
	pop.housing_occupied = _zeros(JWUnits.GROUP)
	pop.service_access = _zeros(JWUnits.GROUP_SVC_N)
	pop.consumption_index = _zeros(JWUnits.GROUP)
	pop.birth_ppm = _zeros(JWUnits.R)
	pop.death_ppm = _zeros(JWUnits.GROUP)
	pop.age_out_ppm = _zeros(JWUnits.A)
	pop.support_out_weight_ppm = _zeros(JWUnits.GROUP)
	pop.base_real_cons = _zeros(JWUnits.GROUP)
	pop.base_real_income = _zeros(JWUnits.GROUP)
	pop.base_delivered_service = _zeros(JWUnits.GROUP_SVC_N)
	pop.f_migrate_rejected = _zeros(JWUnits.GROUP)

	mig = JWMigration.new()
	mig.allocate()
	mig.adjacency = _zeros(JWUnits.OD_N)
	mig.migration_cost = _zeros(JWUnits.OD_N)

	pricing = JWPricing.new()
	pricing.allocate()
	pricing.price = PackedInt64Array([JWUnits.BASE_PRICE, JWUnits.BASE_PRICE,
			JWUnits.BASE_PRICE, JWUnits.BASE_PRICE])
	pricing.price_pending = _zeros(JWUnits.S)
	pricing.base_price = PackedInt64Array([JWUnits.BASE_PRICE, JWUnits.BASE_PRICE,
			JWUnits.BASE_PRICE, JWUnits.BASE_PRICE])
	pricing.wage = PackedInt64Array([WAGE_LOW, WAGE_MID, WAGE_HIGH])
	pricing.gap_ppm = _zeros(JWUnits.S)

	accounts = JWAccount.new()
	accounts.allocate()
	accounts.balance = _zeros(JWUnits.ACCOUNT_N)
	ledger = JWLedger.new(accounts)
	ledger.allocate()
	ledger.set_context(0, JWUnits.Phase.S05)

	rng = JWRngStreams.new()
	rng.allocate()
	# 六条流的盐必须互不相同（content.rng.salt[6]）；全 0 的盐会让六条流退化成同一条，
	# 那样 INV-009 的流隔离就无从检验。
	rng.root_seed = 0x5EED_0001
	rng.salt = PackedInt64Array([0x11, 0x2222, 0x333333, 0x44444444, 0x5555555555, 0x66666666666])
	rng.begin_quarter(0)

	params = _zeros(JWUnits.PARAM_N)
	_default_params()


func after_each() -> void:
	JWResult.clear_pending()


# ── 夹具工具 ───────────────────────────────────────────────────────────────

func _zeros(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(0)
	return a


## 只设置本文件用到的参数；其余保持 0（0 在契约里都表示「该通道关闭」）。
func _default_params() -> void:
	params[JWUnits.Param.PERSONS_PER_HOUSING_UNIT] = PERSONS_PER_UNIT
	params[JWUnits.Param.STUDENT_TEACHER_RATIO] = 20
	params[JWUnits.Param.TRAINING_LAG_Q] = 4
	params[JWUnits.Param.EDU_PIPELINE_SLOTS] = JWUnits.EDU_SLOT
	# 价格（docs/12 §7.3 (e)：floor/ceil 必须与 JWUnits 的 PRICE_MIN / PRICE_MAX 同源）
	params[JWUnits.Param.PRICE_FLOOR_PPM] = 400_000
	params[JWUnits.Param.PRICE_CEIL_PPM] = 2_500_000
	params[JWUnits.Param.PRICE_STEP_MAX_PPM] = 20_000
	params[JWUnits.Param.PRICE_GAP_GAIN_PPM] = 100_000
	params[JWUnits.Param.PRICE_COVER_GAIN_PPM] = 50_000
	params[JWUnits.Param.GAP_CAP_PPM] = 200_000
	params[JWUnits.Param.PRICE_CLAMP_BUDGET_COUNT] = 200
	# 迁移（拉力只由工资差驱动，推力权重 0 —— 让三道硬闸成为唯一约束）
	params[JWUnits.Param.MIGRATION_W_WAGE_PPM] = 1_000_000
	params[JWUnits.Param.MIGRATION_THRESHOLD_PPM] = 1_000
	params[JWUnits.Param.MIGRATION_MAX_SHARE_PPM] = 100_000
	# 就业摩擦：允许一季翻倍，使「劳动力池」成为唯一上限
	params[JWUnits.Param.HIRING_FRICTION_PPM] = 1_000_000
	params[JWUnits.Param.FIRING_FRICTION_PPM] = 1_000_000
	params[JWUnits.Param.WAGE_CASH_SHARE_PPM] = 1_000_000
	params[JWUnits.Param.CONSTRUCTION_SHARE_CAP_PPM] = 200_000
	# 工资侧（S07 §7.3 同法）：swap_pending 要求本季 price 与 wage 的 pending 都写过
	params[JWUnits.Param.WAGE_GAIN_PPM] = 100_000
	params[JWUnits.Param.WAGE_STEP_MAX_PPM] = 20_000
	params[JWUnits.Param.WAGE_FLOOR_UU] = 500
	params[JWUnits.Param.WAGE_CEIL_UU] = 20_000_000_000


func _cell(r: int, s: int) -> int:
	return JWIds.idx_cell(r, s)


func _grp(r: int, a: int, k: int) -> int:
	return JWIds.idx_group(r, a, k)


func _cash_of_group(g: int) -> int:
	return accounts.balance[JWIds.idx_account(JWIds.agent_of_group(g), JWIds.ACC_CASH)]


func _set_cash_group(g: int, v: int) -> void:
	accounts.balance[JWIds.idx_account(JWIds.agent_of_group(g), JWIds.ACC_CASH)] = v


func _set_cash_cell(cell: int, v: int) -> void:
	accounts.balance[JWIds.idx_account(JWIds.agent_of_cell(cell), JWIds.ACC_CASH)] = v


func _sum(a: PackedInt64Array) -> int:
	var t: int = 0
	for v: int in a:
		t += v
	return t


func _nation_pop() -> int:
	var t: int = 0
	for g: int in JWUnits.GROUP:
		t += pop.population[g]
	return t


func _region_pop(r: int) -> int:
	var t: int = 0
	for g: int in JWUnits.GROUP:
		if JWIds.region_of_group(g) == r:
			t += pop.population[g]
	return t


func _region_occupied(r: int) -> int:
	var t: int = 0
	for g: int in JWUnits.GROUP:
		if JWIds.region_of_group(g) == r:
			t += pop.housing_occupied[g]
	return t


## S08 §8.7 的价格切换。swap_pending 要求本季 price 与 wage 的 pending 都写过（INV-065/070），
## 所以这里补一次工资更新再切换；返回值必须是 OK，否则说明 pending 双缓冲的契约被改了。
func _swap_prices(note: String) -> void:
	var rc_w: int = pricing.update_wages(0, 0, 0, params)
	eq_int(rc_w, JWResult.OK, "%s：工资 pending 写入不应失败" % note)
	var rc: int = pricing.swap_pending()
	eq_int(rc, JWResult.OK,
			"%s/INV-065：S08 的价格与工资切换必须成功（同季只切一次、S07 写过 pending）" % note)


## 邻接登记（对称无自环；对角线迁移成本恒为 0，docs/12 §7.5）。
func _link(a: int, b: int) -> void:
	mig.adjacency[JWIds.idx_od(a, b)] = 1
	mig.adjacency[JWIds.idx_od(b, a)] = 1
	mig.migration_cost[JWIds.idx_od(a, b)] = MIG_COST_UU
	mig.migration_cost[JWIds.idx_od(b, a)] = MIG_COST_UU


# ══════════════════════════════════════════════════════════════════════════
#  D 族：物资守恒攻击（docs/31 §5）
# ══════════════════════════════════════════════════════════════════════════

## ADV-D01 拆单造货（取整套利）。检验 INV-046（投入用 ceil 反算，不得少耗）、
## INV-047、INV-048、INV-062（付款额 == floor(量×价/1e6)）、INV-003。
##
## 攻击：把一笔 100 单位的投料拆成 100 笔 1 单位，每笔各向下取整一次 —— 若投入消耗用 floor，
## 拆单后总耗料变少而产出不变，等于凭空造货。契约要求 ceil，故拆单只会**多耗**，绝不少耗。
func test_adv_d01_split_orders_cannot_manufacture_materials() -> void:
	var cell: int = _cell(0, MANU)
	# a(agri→manu) = 1.5 μQ_agri / Q_manu：故意取非整千，让每笔的取整方向可见。
	io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 1_500_000
	inv.inv_input[JWIds.idx_inv(cell, AGRI)] = 1_000_000

	# 整单：一次消耗 100 μQ_manu ⇒ use = ceil(100 × 1 500 000 / 1e6) = 150
	inv.begin_production()
	var rc_whole: int = inv.consume_inputs(cell, 100, io)
	eq_int(rc_whole, JWResult.OK, "ADV-D01：整单消耗不应失败（库存 1e6 远大于所需 150）")
	var whole_used: int = inv.f_consumed[JWIds.idx_inv(cell, AGRI)]
	eq_int(whole_used, 150,
			"ADV-D01/INV-046：整单耗料期望 ceil(100×1 500 000/1e6) = 150 μQ_agri（docs/12 §5.4）")

	# 拆单：同样 100 μQ_manu，拆成 100 笔各 1 μQ_manu ⇒ 每笔 ceil(1.5) = 2，共 200
	before_each()
	cell = _cell(0, MANU)
	io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 1_500_000
	inv.inv_input[JWIds.idx_inv(cell, AGRI)] = 1_000_000
	inv.begin_production()
	var i: int = 0
	while i < 100:
		var rc: int = inv.consume_inputs(cell, 1, io)
		eq_int(rc, JWResult.OK, "ADV-D01：第 %d 笔拆单消耗不应失败" % i)
		i += 1
	var split_used: int = inv.f_consumed[JWIds.idx_inv(cell, AGRI)]
	eq_int(split_used, 200,
			"ADV-D01/INV-046：拆成 100 笔各 1 μQ_manu，每笔 ceil(1×1 500 000/1e6) = 2，期望共 200 μQ_agri")
	check(split_used >= whole_used,
			"ADV-D01：拆单耗料 %d 小于整单耗料 %d ⇒ 投入反算用了 floor，拆单即造货（INV-046 被破坏）"
			% [split_used, whole_used])
	ge_int(inv.inv_input[JWIds.idx_inv(cell, AGRI)], 0,
			"ADV-D01/INV-048：任何一笔消耗之后投入库存都不得为负")

	# 货币侧：同一季同买方同品种若逐笔计价，每笔各 floor 一次，买方少付的上界是「笔数 − 1」μU。
	# 病态价格 1 000 500 000 μU/Q_s（在 [PRICE_MIN, PRICE_MAX] 内）把偏差放到可观测量级。
	var price: int = 1_000_500_000
	eq_int(JWMath.check_price(price), price,
			"ADV-D01：夹具价格 1 000 500 000 必须落在 R-SCALE-01 的 [4e8, 2.5e9] 内")
	var whole_value: int = JWMath.mul_div_floor(100, price, Q_SCALE)
	var split_value: int = 0
	var j: int = 0
	while j < 100:
		split_value += JWMath.mul_div_floor(1, price, Q_SCALE)
		j += 1
	eq_int(whole_value, 100_050,
			"ADV-D01/INV-062：整单 100 μQ_s × 1 000 500 000 / 1e6 = 100 050 μU（合并后只取整一次）")
	eq_int(split_value, 100_000,
			"ADV-D01/INV-062：逐笔计价 100 × floor(1 000.5) = 100 000 μU —— 拆单少付 50 μU")
	le_int(whole_value - split_value, 99,
			"ADV-D01：拆单少付额的上界是「笔数 − 1」= 99 μU（docs/31 ADV-D01「取整残差上界」）；"
			+ "超过即说明逐笔计价放大了取整偏差，必须改为「同季同对手方同品种先合并再计价一次」")
	check(whole_value - split_value > 0,
			"ADV-D01：该夹具下拆单与整单计价必须存在可观测差额，否则这条测试什么也没测到")


## ADV-D02 制造负库存。检验 INV-043（取最小）、INV-045（slack[binding] == 0）、
## INV-046、INV-048（任何库存写入后 ≥ 0，不得无提示负库存）。
func test_adv_d02_overplan_cannot_create_negative_inventory() -> void:
	var cell: int = _cell(0, MANU)
	# a(agri→manu) = 0.5：库存 1 000 000 μQ_agri 只够 2 000 000 μQ_manu 的产出。
	io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 500_000
	inv.inv_input[JWIds.idx_inv(cell, AGRI)] = 1_000_000
	cap.cell_capacity_active[cell] = 10_000_000
	sec.f_output_plan[cell] = 10_000_000

	inv.begin_production()
	var rc: int = sec.solve_output(cell, cap, lab, inv, io)
	eq_int(rc, JWResult.OK, "ADV-D02：五项约束求解本身不应失败")
	eq_int(sec.output_actual(cell), 2_000_000,
			"ADV-D02/INV-043：bound_materials = floor(1 000 000 × 1e6 / 500 000) = 2 000 000 μQ_manu，"
			+ "它是五项中最小者，实际产量必须等于它")
	eq_int(sec.binding_code(cell), B_MATERIALS,
			"ADV-D02/INV-045：最紧约束必须是 materials（计划 1e7、产能 1e7 都更宽）")
	eq_int(sec.bound_value(cell, B_MATERIALS) - sec.output_actual(cell), 0,
			"ADV-D02/INV-045：binding 项的 slack 恒为 0")

	rc = inv.consume_inputs(cell, sec.output_actual(cell), io)
	eq_int(rc, JWResult.OK, "ADV-D02/INV-046：按 bound_materials 反算的耗料恰好用完库存，不应失败")
	eq_int(inv.inv_input[JWIds.idx_inv(cell, AGRI)], 0,
			"ADV-D02/INV-046：ceil(2 000 000 × 500 000 / 1e6) = 1 000 000，正好用尽，期末为 0")

	# 攻击本体：库存已空仍下单生产 —— 必须登记 NEGATIVE_INVENTORY，且库存不得变负、也不得被抹平。
	JWResult.clear_pending()
	var before: int = inv.inv_input[JWIds.idx_inv(cell, AGRI)]
	rc = inv.consume_inputs(cell, 1_000, io)
	ne_int(rc, JWResult.OK,
			"ADV-D02/INV-048：库存为 0 时再扣 ceil(1 000×0.5) = 500 μQ 必须失败，"
			+ "静默透支是 docs/31 §0.2 禁止的第四类「静默改账」")
	eq_int(JWResult.pending_code(), JWResult.Fault.NEGATIVE_INVENTORY,
			"ADV-D02：透支库存的故障码必须是 NEGATIVE_INVENTORY（docs/17 §4.17 consume_inputs 失败行）")
	ge_int(inv.inv_input[JWIds.idx_inv(cell, AGRI)], 0,
			"ADV-D02/INV-048：失败路径也不得留下负库存")
	eq_int(inv.inv_input[JWIds.idx_inv(cell, AGRI)], before,
			"ADV-D02：被拒的消耗不得改动库存（不得「先扣成负数再想办法」）")


## ADV-D03 用未完工资产供能：付款不制造进度。
## 检验 INV-087（construction_progress 与 paid_uu 无函数依赖）、INV-088、
## docs/30 T-S-P04-PAY-NO-PROGRESS、docs/12 §5.5。
func test_adv_d03_payment_does_not_create_construction_progress() -> void:
	var projects: JWProjectQueue = JWProjectQueue.new()
	projects.allocate()
	var world: JWWorldMarket = JWWorldMarket.new()
	world.allocate()
	world.delivery_capacity = _zeros(JWUnits.S)
	world.begin_quarter_delivery()

	# 两个完全相同的在建项目，区别只有「已付款额」：p0 付满，p1 一分未付。
	projects.count = 2
	var p: int = 0
	while p < 2:
		projects.status[p] = JWUnits.ProjectStatus.IN_PROGRESS
		projects.region_idx[p] = 0
		projects.planned_quarters[p] = 4
		projects.required_construction[p] = 4_000_000
		projects.required_equipment[p] = 0
		projects.construction_progress[p] = 0
		projects.delivery_progress[p] = 0
		p += 1
	projects.paid[0] = 4_000_000_000_000
	projects.paid[1] = 0

	# 施工能力为 0（服务部门本季产出为 0），这是「有钱、无施工能力」的验收场景。
	var svc_out: PackedInt64Array = _zeros(JWUnits.CELL)
	var rc: int = projects.compute_construction_capacity(svc_out, params)
	eq_int(rc, JWResult.OK, "ADV-D03：施工能力折算本身不应失败")
	eq_int(projects.f_construction_capacity[0], 0,
			"ADV-D03/INV-088：服务产出为 0 ⇒ 施工能力为 0（施工能力由实物产出折出，不由付款折出）")

	rc = projects.advance_progress(world, ledger, accounts)
	eq_int(rc, JWResult.OK, "ADV-D03：无施工能力不是故障，只是进度不增（docs/12 §5.5）")
	eq_int(projects.construction_progress[0], 0,
			"ADV-D03/INV-087：付满款的项目施工进度仍必须为 0（T-S-P04-PAY-NO-PROGRESS）")
	eq_int(projects.construction_progress[0], projects.construction_progress[1],
			"ADV-D03/INV-087：付款额不同的两个项目进度必须逐位相同 —— 进度不得对 paid_uu 有任何函数依赖")
	eq_int(projects.status_of(0), JWUnits.ProjectStatus.SUSPENDED,
			"ADV-D03/docs/12 §5.5：grant == 0 且 need > 0 ⇒ 项目转 suspended")
	eq_int(projects.suspension_reason[0], JWUnits.SuspendReason.CONGESTION,
			"ADV-D03：挂起原因必须是 congestion（施工能力被占满），玩家才能看懂「为什么钱付了却不动」")
	eq_int(projects.delivery_progress[0], 1_000_000,
			"ADV-D03/docs/12 §5.5：required_equipment == 0 的项目，交付维度立刻满格（1e6），"
			+ "而不是 DIV_ZERO —— 否则纯土建项目永远无法完工")
	eq_int(JWResult.pending_code(), 0,
			"ADV-D03：无施工能力、无设备需求的一季不得登记任何故障")

	# 对照：给足施工能力后，进度增量必须精确等于 floor(grant × 1e6 / required)。
	JWResult.clear_pending()
	svc_out[_cell(0, SERVICES)] = 5_000_000          # ⇒ capacity = 20% × 5e6 = 1 000 000 μQ
	rc = projects.compute_construction_capacity(svc_out, params)
	eq_int(rc, JWResult.OK, "ADV-D03：对照组施工能力折算不应失败")
	eq_int(projects.f_construction_capacity[0], 1_000_000,
			"ADV-D03：capacity = mul_ppm(5 000 000, construction_share_cap_ppm 200 000) = 1 000 000 μQ")
	projects.status[0] = JWUnits.ProjectStatus.IN_PROGRESS
	projects.status[1] = JWUnits.ProjectStatus.IN_PROGRESS
	rc = projects.advance_progress(world, ledger, accounts)
	eq_int(rc, JWResult.OK, "ADV-D03：对照组推进不应失败")
	# 两个项目各需 need = floor(4 000 000 / 4) = 1 000 000，能力 1 000 000 按需求等比拆 ⇒ 各 500 000。
	eq_int(projects.construction_progress[0], 125_000,
			"ADV-D03/INV-088：Δ = floor(500 000 × 1e6 / 4 000 000) = 125 000 ppm（施工能力两项目均分）")
	eq_int(projects.construction_progress[0], projects.construction_progress[1],
			"ADV-D03：付款额不同不得让两个项目分到不同的施工能力")


## ADV-D04 把电力存起来。检验 INV-049（storable == 0 的部门期末库存恒为 0）、
## INV-051（电力当期使用、未用作废、不入库存、Σ 配给 ≤ min(可交付, 电网)）、INV-052。
func test_adv_d04_electricity_cannot_be_stored() -> void:
	var e_cell: int = _cell(0, ENERGY)
	var s_cell: int = _cell(0, SERVICES)

	# 直接攻击入库路径：不可库存部门被写入产出，期末库存必须仍为 0。
	var rc: int = inv.store_output(e_cell, 500_000, io)
	eq_int(inv.inv_output[e_cell], 0,
			"ADV-D04/INV-049：energy 的 storable == 0，入库 500 000 μQ 之后期末库存必须仍为 0")
	rc = inv.store_output(s_cell, 500_000, io)
	eq_int(inv.inv_output[s_cell], 0,
			"ADV-D04/INV-049：services 的 storable == 0，期末库存必须恒为 0")

	# 电网封顶：可交付 900 000，电网只有 500 000 ⇒ 多出的部分作废，不得转成库存。
	JWResult.clear_pending()
	io.io_coeff[JWIds.idx_io(ENERGY, ENERGY)] = 100_000       # 自用 10%，INV-052 要求 < 1e6
	io.energy_coeff[e_cell] = 100_000
	cap.cell_capacity_active[e_cell] = 1_000_000
	sec.f_output_plan[e_cell] = 1_000_000
	cap.grid_capacity[0] = 500_000

	inv.begin_production()
	rc = sec.settle_energy(cap, inv, io, lab, params)
	eq_int(rc, JWResult.OK, "ADV-D04：能源结算本身不应失败")
	eq_int(sec.output_actual(e_cell), 1_000_000,
			"ADV-D04：能源 cell 的产量 = min(计划 1e6, 产能 1e6)，能源约束对自己不适用（INV-052）")
	eq_int(inv.inv_output[e_cell], 0,
			"ADV-D04/INV-049：能源 cell 生产完成之后成品库存必须仍为 0 —— 电不能囤")
	eq_int(sec.f_elec_supply[0], 500_000,
			"ADV-D04/INV-051：可交付 = 1 000 000 − ceil(1 000 000×0.1) = 900 000，"
			+ "电网 500 000 封顶 ⇒ 本地区可供电力 = min(900 000, 500 000) = 500 000")
	le_int(sec.f_elec_supply[0], cap.grid_capacity[0],
			"ADV-D04/INV-051：可供电力不得超过电网输配容量")
	var alloc_total: int = 0
	var c: int = 0
	while c < JWUnits.CELL:
		alloc_total += sec.f_energy_allocated[c]
		c += 1
	le_int(alloc_total, sec.f_elec_supply[0],
			"ADV-D04/INV-051：Σ 配给 ≤ min(可交付, 电网容量)；超出即凭空发电")


## ADV-D05 同季链条造货。检验 INV-050（可库存中间投入只来自期初库存）、
## INV-043、INV-045，对应 docs/30 的 T-U-NO-SAME-QUARTER-CHAIN。
func test_adv_d05_no_same_quarter_production_chain() -> void:
	var agri_cell: int = _cell(0, AGRI)
	var manu_cell: int = _cell(0, MANU)
	# 农业本季满产；制造业需要农产品但期初库存为 0。
	cap.cell_capacity_active[agri_cell] = 3_000_000
	sec.f_output_plan[agri_cell] = 3_000_000
	cap.cell_capacity_active[manu_cell] = 3_000_000
	sec.f_output_plan[manu_cell] = 3_000_000
	io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 1_000_000
	inv.inv_input[JWIds.idx_inv(manu_cell, AGRI)] = 0

	inv.begin_production()
	var rc: int = sec.settle_production(cap, lab, inv, io)
	eq_int(rc, JWResult.OK, "ADV-D05：生产结算本身不应失败")
	eq_int(sec.output_actual(agri_cell), 3_000_000,
			"ADV-D05：上游农业不受约束，产量 = min(计划, 产能) = 3 000 000 μQ_agri")
	eq_int(sec.output_actual(manu_cell), 0,
			"ADV-D05/INV-050：期初农产品库存为 0 ⇒ 制造业本季产量必须是 0，"
			+ "本季农业产出只能补下季库存（docs/12 §5.1 的显式离散化简化）")
	eq_int(sec.binding_code(manu_cell), B_MATERIALS,
			"ADV-D05/INV-045：制造业本季的最紧约束必须报告为 materials，否则玩家无法定位瓶颈")
	eq_int(inv.f_consumed[JWIds.idx_inv(manu_cell, AGRI)], 0,
			"ADV-D05：产量为 0 就不得有任何耗料，否则投入凭空消失")
	eq_int(inv.inv_output[agri_cell], 3_000_000,
			"ADV-D05/INV-047：农业产出全部入库（storable == 1），供下季使用")


## ADV-D06 用损耗掩盖盘点差异。检验 INV-047（库存恒等式，容差 0）、
## INV-048、INV-053（损耗显式登记，不得用「盘点差异」吸收）。
func test_adv_d06_spoilage_cannot_absorb_stock_gap() -> void:
	var cell: int = _cell(0, MANU)
	io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 500_000
	io.spoilage_ppm[MANU] = 200_000              # 损耗率取上限档：20%/季
	io.spoilage_ppm[AGRI] = 200_000
	inv.inv_input[JWIds.idx_inv(cell, AGRI)] = 1_000_000
	cap.cell_capacity_active[cell] = 2_000_000
	sec.f_output_plan[cell] = 2_000_000

	inv.begin_production()
	var rc: int = sec.solve_output(cell, cap, lab, inv, io)
	eq_int(rc, JWResult.OK, "ADV-D06：约束求解不应失败")
	var q_actual: int = sec.output_actual(cell)
	eq_int(q_actual, 2_000_000, "ADV-D06：产量 = min(计划 2e6, 产能 2e6, 材料 2e6) = 2 000 000 μQ_manu")
	rc = inv.consume_inputs(cell, q_actual, io)
	eq_int(rc, JWResult.OK, "ADV-D06：耗料不应失败")
	rc = inv.store_output(cell, q_actual, io)
	eq_int(rc, JWResult.OK, "ADV-D06：入库不应失败")
	rc = inv.apply_spoilage(io)
	eq_int(rc, JWResult.OK, "ADV-D06：损耗结转不应失败")

	eq_int(inv.f_spoilage_out[cell], 400_000,
			"ADV-D06/INV-053：损耗 = mul_ppm(2 000 000, 200 000) = 400 000 μQ_manu，"
			+ "必须是有名字、有数量的显式流量，而不是隐去的盘点差异")
	eq_int(inv.inv_output[cell], 1_600_000,
			"ADV-D06/INV-047：期末 = 0 期初 + 2 000 000 生产 − 400 000 损耗 = 1 600 000 μQ_manu")
	ge_int(inv.inv_output[cell], 0, "ADV-D06/INV-048：损耗后库存不得为负")

	rc = inv.check_stock_identity(sec.output_actual_array())
	eq_int(rc, JWResult.OK,
			"ADV-D06/INV-047：逐 cell 逐品种的库存恒等式必须以容差 0 成立；"
			+ "残差非 0 却不报错即说明存在「盘点差异」吸收路径（docs/31 §0.2 禁止的第四类）")
	eq_int(inv.used_total(cell), 1_000_000,
			"ADV-D06/INV-053：本季耗用合计 = ceil(2 000 000 × 0.5) = 1 000 000 μQ_agri，"
			+ "它与损耗一同进入中间消耗，增加值才不会被高估")


## ADV-D07 能源自举。检验 INV-052（a(energy→energy) < 1e6）、INV-150（IO 列和 < 1e6）、
## INV-044（能源 cell 不产生能源约束候选值）。
func test_adv_d07_energy_self_bootstrap_rejected_at_load() -> void:
	# 变体 1：a(energy→energy) == 1 000 000 —— 产 1 单位电要用 1 单位电，自举。
	io.io_coeff[JWIds.idx_io(ENERGY, ENERGY)] = 1_000_000
	io.energy_coeff[_cell(0, ENERGY)] = 1_000_000
	io.energy_coeff[_cell(1, ENERGY)] = 1_000_000
	io.energy_coeff[_cell(2, ENERGY)] = 1_000_000
	io.energy_coeff[_cell(3, ENERGY)] = 1_000_000
	var res: JWResult = io.validate()
	check_false(res.ok,
			"ADV-D07/INV-052：a(energy→energy) == 1e6 必须在载入期被拒，不得「先跑起来再说」")
	check(res.code == JWResult.Load.IO_ENERGY_SELF or res.code == JWResult.Load.IO_COLSUM
			or res.code == JWResult.Load.IO_NOT_CONVERGENT,
			"ADV-D07：docs/31 期望拒绝码为 E_IO_ENERGY_SELF（列和分支给 E_IO_COLSUM 亦可接受），实际 %d"
			% res.code)

	# 变体 2：a(energy→energy) == 1 000 001 —— 越界更明显，同样必须在载入期拒绝。
	before_each()
	io.io_coeff[JWIds.idx_io(ENERGY, ENERGY)] = 1_000_001
	var c2: int = 0
	while c2 < JWUnits.CELL:
		if JWIds.sector_of_cell(c2) == ENERGY:
			io.energy_coeff[c2] = 1_000_001
		c2 += 1
	res = io.validate()
	check_false(res.ok, "ADV-D07/INV-150：IO 系数 > 1e6 必须在载入期被拒（列和 < 1e6 是硬约束）")

	# 变体 3：合法取值下，能源 cell 必须**跳过**能源约束（INV-044：自指不产生候选值）。
	before_each()
	var e_cell: int = _cell(0, ENERGY)
	io.io_coeff[JWIds.idx_io(ENERGY, ENERGY)] = 100_000
	io.energy_coeff[e_cell] = 100_000
	cap.cell_capacity_active[e_cell] = 1_000_000
	sec.f_output_plan[e_cell] = 1_000_000
	sec.f_energy_allocated[e_cell] = 0
	var rc: int = sec.solve_output(e_cell, cap, lab, inv, io)
	eq_int(rc, JWResult.OK, "ADV-D07：合法自用系数下能源 cell 的求解不应失败")
	eq_int(sec.f_bound_energy[e_cell], JWUnits.SENTINEL,
			"ADV-D07/INV-044：能源 cell 的能源约束必须写 SENTINEL（不适用），"
			+ "否则它会因「自己没给自己配电」而永远产量为 0，形成同期迭代")
	ne_int(sec.binding_code(e_cell), B_ENERGY,
			"ADV-D07/INV-044：能源 cell 的最紧约束不得落在 energy 上")


# ══════════════════════════════════════════════════════════════════════════
#  E 族：人口守恒攻击（docs/31 §6）
# ══════════════════════════════════════════════════════════════════════════

## 两地区迁移夹具：北原低工资 → 中州高工资。stock_to 决定住房硬闸松紧。
func _migration_world(stock_to_units: int, occupied_to_units: int, cash_uu: int,
		vacancies: int) -> void:
	var g_from: int = _grp(R_FROM, WORKING, LOW)
	var g_to: int = _grp(R_TO, WORKING, HIGH)

	pop.population[g_from] = 1_000_000
	pop.participation_ppm[g_from] = 800_000
	pop.housing_occupied[g_from] = 300_000
	pop.employed[JWIds.idx_group_emp(g_from, SERVICES)] = 400_000

	pop.population[g_to] = 100_000
	pop.participation_ppm[g_to] = 800_000
	pop.housing_occupied[g_to] = occupied_to_units
	pop.employed[JWIds.idx_group_emp(g_to, SERVICES)] = 40_000

	lab.cell_employment[JWIds.idx_emp(_cell(R_FROM, SERVICES), LOW)] = 400_000
	lab.cell_employment[JWIds.idx_emp(_cell(R_TO, SERVICES), HIGH)] = 40_000
	lab.set("_vacancies_persons", vacancies)

	cap.housing_stock[R_FROM] = 1_000_000
	cap.housing_capacity[R_FROM] = 1_000_000
	cap.housing_stock[R_TO] = stock_to_units
	cap.housing_capacity[R_TO] = stock_to_units + 6_000

	_link(R_FROM, R_TO)
	_set_cash_group(g_from, cash_uu)
	_set_cash_group(g_to, cash_uu)


## ADV-E01 全员迁入一区仍享无限住房（≡ 计划书点名 ④）。
## 检验 INV-083（占用 ≤ 存量 ≤ 容量）、INV-084（被挡回必须登记，容量不得自动增长）、INV-071。
func test_adv_e01_housing_is_a_hard_cap_not_a_suggestion() -> void:
	# 住房存量 34 000 套 × 3 人/套 = 102 000 人上限，已住 100 000 人 ⇒ 只剩 2 000 个位置。
	_migration_world(34_000, 30_000, 4_000_000_000_000, 1_000_000)
	var stock_before: int = cap.housing_stock[R_TO]
	var capacity_before: int = cap.housing_capacity[R_TO]
	var nation_before: int = _nation_pop()

	var rc: int = mig.run(pop, lab, cap, pricing, ledger, accounts, rng, params)
	eq_int(rc, JWResult.OK, "ADV-E01：极端诱因下的迁移不应产生故障，只应被硬闸挡住")

	var moved: int = _sum(mig.in_by_group())
	eq_int(moved, 2_000,
			"ADV-E01/INV-083：cap_housing = max(0, 34 000 套 × 3 人/套 − 100 000 人) = 2 000 人，"
			+ "这是硬上限，实际迁入必须恰好被它卡住（docs/12 §7.5）")
	eq_int(cap.housing_stock[R_TO], stock_before,
			"ADV-E01/INV-084：住房存量不得因为「人来了」而自动增长；"
			+ "存量只能由 P06 公共住房建设经施工形成")
	eq_int(cap.housing_capacity[R_TO], capacity_before,
			"ADV-E01/INV-084：住房容量同样不得自动增长")
	check(_sum(pop.f_migrate_rejected) > 0,
			"ADV-E01/INV-084：被住房闸挡回的人必须写入 migrate_rejected_persons；"
			+ "为 0 说明迁移函数根本没有住房闸门，或被挡回的人被静默吞掉了")
	le_int(_region_occupied(R_TO), cap.housing_stock[R_TO],
			"ADV-E01/INV-083：Σ housing_occupied ≤ housing_stock 必须逐季成立")
	le_int(cap.housing_stock[R_TO], cap.housing_capacity[R_TO],
			"ADV-E01/INV-083：housing_stock ≤ housing_capacity 必须逐季成立")
	eq_int(_nation_pop(), nation_before,
			"ADV-E01/INV-071：迁移不生不死，全国人口必须逐位不变")
	eq_int(_sum(mig.in_by_group()), _sum(mig.out_by_group()),
			"ADV-E01/INV-073：Σ 迁入 == Σ 迁出")


## ADV-E02 同季互迁造人。检验 INV-073（迁移双边配对）、INV-071、INV-072，
## 并检验「迁移不是免费的」（kind=25 migration_cost 真的从迁出方现金扣走）。
func test_adv_e02_bidirectional_migration_conserves_population() -> void:
	_migration_world(1_000_000, 30_000, 4_000_000_000_000, 1_000_000)
	var g_from: int = _grp(R_FROM, WORKING, LOW)
	var nation_before: int = _nation_pop()
	var cash_before: int = _cash_of_group(g_from)

	var rc: int = mig.run(pop, lab, cap, pricing, ledger, accounts, rng, params)
	eq_int(rc, JWResult.OK, "ADV-E02：第一季迁移不应失败")
	var moved_q0: int = _sum(mig.out_by_group())
	check(moved_q0 > 0, "ADV-E02：夹具必须真的产生迁移，否则这条测试什么也没测到")
	eq_int(_sum(mig.in_by_group()), moved_q0, "ADV-E02/INV-073：Σ 迁入 == Σ 迁出（第一季）")
	eq_int(_nation_pop(), nation_before, "ADV-E02/INV-071：第一季迁移后全国人口不得变化")
	eq_int(cash_before - _cash_of_group(g_from), moved_q0 * MIG_COST_UU,
			"ADV-E02：迁移成本 = 迁出人数 × 3 000 000 μU/人，必须真的从迁出组现金扣走"
			+ "（docs/12 §7.5：迁移成本是真实支出）")

	# 逐对配对：稀疏流的每一行都必须同时进 in_by_group 与 out_by_group。
	var in_by: PackedInt64Array = mig.in_by_group()
	var out_by: PackedInt64Array = mig.out_by_group()
	var g: int = 0
	while g < JWUnits.GROUP:
		ge_int(in_by[g], 0, "ADV-E02/INV-073：组 %d 的迁入人数不得为负" % g)
		ge_int(out_by[g], 0, "ADV-E02/INV-073：组 %d 的迁出人数不得为负" % g)
		g += 1

	# 第二季把工资优势整体反转，制造反向流：两季合计人口仍必须一人不差。
	JWResult.clear_pending()
	mig.reset_flows()
	pop.reset_flows()
	rng.begin_quarter(1)
	lab.cell_employment = _zeros(JWUnits.EMP_N)
	lab.cell_employment[JWIds.idx_emp(_cell(R_FROM, SERVICES), HIGH)] = 400_000
	lab.cell_employment[JWIds.idx_emp(_cell(R_TO, SERVICES), LOW)] = 40_000
	var nation_mid: int = _nation_pop()
	rc = mig.run(pop, lab, cap, pricing, ledger, accounts, rng, params)
	eq_int(rc, JWResult.OK, "ADV-E02：第二季反向迁移不应失败")
	eq_int(_sum(mig.in_by_group()), _sum(mig.out_by_group()),
			"ADV-E02/INV-073：反向流同样必须双边配对")
	eq_int(_nation_pop(), nation_mid,
			"ADV-E02/INV-071：来回迁移两季之后全国人口必须仍然是 %d —— "
			% nation_before + "「先加迁入再减迁出」的两趟循环会在这里造出人来")


## ADV-E03 没有教师时培训照样完成（≡ 计划书点名 ③）。
## 检验 INV-081（新增席位 ≤ teachers × ratio − 在读；拨款当季不得产生任何 skill_in）、
## INV-082（技能升档只来自结业队列，等量配对，滞后 ≥ training_lag_q）。
func test_adv_e03_no_teachers_means_no_graduates() -> void:
	var teachers: PackedInt64Array = _zeros(JWUnits.R)
	var requested: PackedInt64Array = _zeros(JWUnits.GROUP)
	var g_low: int = _grp(0, WORKING, LOW)
	var g_mid: int = _grp(0, WORKING, MID)
	requested[g_low] = 10_000
	pop.population[g_low] = 1_000_000

	# 20 季：钱照拨（席位照申请），但教师为 0 ⇒ 一个人也不得升档。
	var q: int = 0
	while q < 20:
		pop.reset_flows()
		var rc: int = pop.update_education(teachers, requested, q, params)
		eq_int(rc, JWResult.OK, "ADV-E03：无教师不是故障，只是无效支出（q=%d）" % q)
		eq_int(_sum(pop.f_skill_in), 0,
				"ADV-E03/INV-081：teachers == 0 ⇒ 全程 skill_in == 0（q=%d）；"
				% q + "非 0 即「花钱就升级」，计划书 §08 的队列结业被架空")
		eq_int(_sum(pop.education_cohort), 0,
				"ADV-E03/INV-081：teachers == 0 ⇒ new_seats == 0，结业队列必须一直是空的（q=%d）" % q)
		q += 1

	# 恢复教师：席位上限 = 100 × 20 = 2 000，申请 10 000 必须被截到 2 000。
	teachers[0] = 100
	pop.reset_flows()
	var rc2: int = pop.update_education(teachers, requested, 20, params)
	eq_int(rc2, JWResult.OK, "ADV-E03：恢复教师后的招生不应失败")
	eq_int(_sum(pop.education_cohort), 2_000,
			"ADV-E03/INV-081：new_seats = min(申请 10 000, teachers 100 × ratio 20 − 在读 0) = 2 000")
	eq_int(_sum(pop.f_skill_in), 0,
			"ADV-E03/INV-081：招生当季不得产生任何 skill_in（拨款当季不许全民升级）")

	# 滞后 4 季后结业，且 skill_out 与 skill_in 等量配对、方向为低档 → 高一档。
	var lag: int = params[JWUnits.Param.TRAINING_LAG_Q]
	var empty_request: PackedInt64Array = _zeros(JWUnits.GROUP)
	var graduated_at: int = -1
	var step: int = 1
	while step <= lag:
		pop.reset_flows()
		var rc3: int = pop.update_education(teachers, empty_request, 20 + step, params)
		eq_int(rc3, JWResult.OK, "ADV-E03：第 %d 季的队列推进不应失败" % (20 + step))
		if _sum(pop.f_skill_in) > 0 and graduated_at < 0:
			graduated_at = step
		step += 1
	eq_int(graduated_at, lag,
			"ADV-E03/INV-082：结业必须恰好发生在入学后第 training_lag_q(=%d) 季，"
			% lag + "提前结业等于把滞后规则删掉")
	eq_int(_sum(pop.f_skill_in), 2_000,
			"ADV-E03/INV-082：结业人数必须等于当初入学的 2 000 人")
	eq_int(_sum(pop.f_skill_in), _sum(pop.f_skill_out),
			"ADV-E03/INV-082：skill_in 与 skill_out 必须等量配对，否则人口从技能维度凭空增减")
	eq_int(pop.f_skill_in[g_mid], 2_000,
			"ADV-E03/INV-082：低档结业只能升到高一档（同地区同年龄的 mid 组）")
	eq_int(pop.f_skill_out[g_low], 2_000,
			"ADV-E03/INV-082：流出方必须是原低档组，容差 0")


## ADV-E04 出生死亡双记。检验 INV-071（死亡是唯一净流出、出生是唯一净流入）、
## INV-072（逐组八项来源去向，容差 0）、INV-074（年龄有向）。
func test_adv_e04_birth_death_aging_cannot_double_count() -> void:
	# 故意制造路径冲突：出生、死亡、成年三率同时拉到上限档。
	var r: int = 0
	while r < JWUnits.R:
		pop.birth_ppm[r] = 30_000
		r += 1
	var g: int = 0
	while g < JWUnits.GROUP:
		pop.death_ppm[g] = 50_000
		pop.population[g] = 200_000
		if JWIds.age_of_group(g) == WORKING:
			pop.participation_ppm[g] = 800_000
		g += 1
	pop.age_out_ppm = PackedInt64Array([200_000, 200_000, 200_000])

	var prev: PackedInt64Array = pop.population.duplicate()
	var nation_before: int = _nation_pop()
	JWResult.set_step(JWUnits.Phase.S07)
	var rc: int = pop.update_demography(rng, params)
	eq_int(rc, JWResult.OK, "ADV-E04：极端人口参数下的人口更新不应产生故障")

	var births_total: int = _sum(pop.f_births)
	var deaths_total: int = _sum(pop.f_deaths)
	check(births_total > 0, "ADV-E04：夹具必须真的产生出生，否则这条测试什么也没测到")
	check(deaths_total > 0, "ADV-E04：夹具必须真的产生死亡，否则这条测试什么也没测到")
	eq_int(_nation_pop(), nation_before + births_total - deaths_total,
			"ADV-E04/INV-071：全国人口 == 上季 + Σ出生 − Σ死亡；"
			+ "成年与技能是组间转移，一人也不得从这两条路径进出总量")
	eq_int(_sum(pop.f_age_in), _sum(pop.f_age_out),
			"ADV-E04/INV-072：成年（含退休）必须配对，Σ age_in == Σ age_out")

	g = 0
	while g < JWUnits.GROUP:
		var expect: int = prev[g] + pop.f_births[g] - pop.f_deaths[g] \
				+ pop.f_age_in[g] - pop.f_age_out[g] \
				+ pop.f_skill_in[g] - pop.f_skill_out[g]
		eq_int(pop.population[g], expect,
				"ADV-E04/INV-072：组 %d 的来源去向恒等式必须以容差 0 成立" % g)
		ge_int(pop.population[g], 0, "ADV-E04：组 %d 的人口不得为负" % g)
		le_int(pop.f_deaths[g] + pop.f_age_out[g], prev[g],
				"ADV-E04：组 %d 的单季流出不得超过组内期初人口（同一个人被两条路径同时选中）" % g)
		if JWIds.age_of_group(g) == MINOR:
			eq_int(pop.f_age_in[g], 0,
					"ADV-E04/INV-074：minor 组不接收 age_in（成年只能来自低一档，方向单向）")
		if JWIds.age_of_group(g) == ELDER:
			eq_int(pop.f_age_out[g], 0,
					"ADV-E04/INV-074：elder 组不产生 age_out，即使内容包把 age_out_ppm[elder] 调到上限")
		g += 1

	rc = pop.check_conservation(_zeros(JWUnits.GROUP), _zeros(JWUnits.GROUP))
	eq_int(rc, JWResult.OK, "ADV-E04/INV-071：S07 末的人口守恒终检必须通过")


## ADV-E05 就业人数超过劳动力。检验 INV-075（劳动力定义）、INV-076（Σ employed ≤ Σ labor_force）、
## INV-077（群组侧与 cell 侧逐（地区,技能）精确相等）、INV-074。
func test_adv_e05_employment_cannot_exceed_labor_force() -> void:
	var r: int = 0
	var g_work: int = _grp(r, WORKING, MID)
	pop.population[g_work] = 1_000_000
	pop.participation_ppm[g_work] = 500_000          # 劳动力 = 500 000 人
	# 未成年与老年：即便有人口，也不得有劳动力与在岗（INV-074）
	pop.population[_grp(r, MINOR, LOW)] = 400_000
	pop.population[_grp(r, ELDER, LOW)] = 300_000

	# 四个 cell 各已有 100 000 人在岗（合计 400 000 ≤ 500 000），系数 1 人/Q_s。
	var s: int = 0
	while s < JWUnits.S:
		var cell: int = _cell(r, s)
		io.labor_coeff[JWIds.idx_emp(cell, MID)] = 1_000_000
		lab.cell_employment[JWIds.idx_emp(cell, MID)] = 100_000
		pop.employed[JWIds.idx_group_emp(g_work, s)] = 100_000
		# 每个 cell 想要 200 000 人（= 摩擦上限 2×prev），四个 cell 合计 800 000 人 > 劳动力 500 000
		sec.f_output_plan[cell] = 200_000
		_set_cash_cell(cell, 20_000_000_000)         # 20 U，足够雇满摩擦上限
		s += 1

	JWResult.set_step(JWUnits.Phase.S03)
	var rc: int = lab.hire_and_fire(sec.f_output_plan, io, pricing, pop, accounts, params)
	eq_int(rc, JWResult.OK, "ADV-E05：招不到人不是故障，只是 Q_labor 变紧（docs/12 §3.2）")

	var lf: int = pop.labor_force_region_skill(r, MID)
	eq_int(lf, 500_000,
			"ADV-E05/INV-075：labor_force = mul_div_floor(1 000 000, 500 000, 1e6) = 500 000 人")
	var employed_cells: int = 0
	s = 0
	while s < JWUnits.S:
		employed_cells += lab.employment(_cell(r, s), MID)
		s += 1
	var employed_pub: int = lab.pubserv_employment(r, MID)
	le_int(employed_cells + employed_pub, lf,
			"ADV-E05/INV-076：逐地区逐技能 Σ employed(%d) 必须 ≤ Σ labor_force(%d)；"
			% [employed_cells + employed_pub, lf]
			+ "超出即「就业数照填、产量照出」，会连锁破坏工资总额对账 INV-079")
	check(employed_cells > 400_000,
			"ADV-E05：夹具必须真的触发扩招（期望从 400 000 涨向劳动力上限），否则闸门没被压到")

	rc = lab.check_employment_views(pop)
	eq_int(rc, JWResult.OK,
			"ADV-E05/INV-077：群组侧与 cell 侧就业是同一事实的两个索引，必须逐（地区,技能）精确相等")

	var g: int = 0
	while g < JWUnits.GROUP:
		var age: int = JWIds.age_of_group(g)
		if age == MINOR or age == ELDER:
			eq_int(pop.labor_force(g), 0,
					"ADV-E05/INV-074：非 working 组（组 %d）的劳动力恒为 0" % g)
			eq_int(pop.employed_total(g), 0,
					"ADV-E05/INV-074：非 working 组（组 %d）的在岗人数恒为 0" % g)
		g += 1

	rc = lab.compute_unemployment(pop)
	eq_int(rc, JWResult.OK, "ADV-E05：失业率计算不应失败")
	ge_int(lab.unemployed_persons(), 0,
			"ADV-E05/INV-075：unemployed == labor_force − employed ≥ 0，不得为负")
	var lf_total: int = 0
	g = 0
	while g < JWUnits.GROUP:
		lf_total += pop.labor_force(g)
		g += 1
	eq_int(lab.unemployment_ppm(),
			JWMath.mul_div_floor(lab.unemployed_persons(), PPM, maxi(lf_total, 1)),
			"ADV-E05/INV-075：失业率必须是 mul_div_floor(Σ失业, 1e6, Σ劳动力) 的反算值，不是参数")


## ADV-E06 退休后继续上班。检验 INV-074（非 working 组 participation == 0 且 employed == 0）、
## INV-080（S07 对 employment 的减少量精确等于人口流出带走的就业人数）、INV-077。
func test_adv_e06_retirees_cannot_keep_their_jobs() -> void:
	var r: int = 0
	var g_elder: int = _grp(r, ELDER, MID)
	pop.population[g_elder] = 300_000
	# 攻击：内容包（或存档）把 elder 的参与率改成 30%。派生量必须仍然是 0。
	pop.participation_ppm[g_elder] = 300_000
	eq_int(pop.labor_force(g_elder), 0,
			"ADV-E06/INV-074：即使 participation_ppm[elder] 被改成 300 000，"
			+ "elder 组的劳动力也必须恒为 0（docs/17 §4.14：非 working 组恒返回 0）")

	# 运行期：working 组退休流出时，岗位必须配对剥离，不得「人都老了工厂还在满产」。
	var g_work: int = _grp(r, WORKING, MID)
	pop.population[g_work] = 1_000_000
	pop.participation_ppm[g_work] = 800_000
	pop.employed[JWIds.idx_group_emp(g_work, MANU)] = 200_000
	lab.cell_employment[JWIds.idx_emp(_cell(r, MANU), MID)] = 200_000
	pop.age_out_ppm = PackedInt64Array([0, 100_000, 0])   # working → elder 每季 10%

	JWResult.set_step(JWUnits.Phase.S07)
	var pop_prev: int = pop.population[g_work]
	var employed_prev: int = pop.employed_total(g_work)
	var rc: int = pop.update_demography(rng, params)
	eq_int(rc, JWResult.OK, "ADV-E06：退休流动不应产生故障")
	var outflow: PackedInt64Array = _zeros(JWUnits.GROUP)
	pop.outflow_persons_into(outflow)
	eq_int(outflow[g_work], pop.f_deaths[g_work] + pop.f_age_out[g_work],
			"ADV-E06：本季流出 == 死亡 + 成年出 + 迁出（本夹具无迁移），docs/12 §7.7")
	check(outflow[g_work] > 0, "ADV-E06：夹具必须真的产生退休流出，否则这条测试什么也没测到")

	var cut: PackedInt64Array = _zeros(JWUnits.GROUP_EMP_N)
	rc = lab.release_for_outflow(outflow, pop, cut)
	eq_int(rc, JWResult.OK, "ADV-E06：就业剥离不应失败")
	var expect_cut: int = JWMath.mul_div_floor(outflow[g_work], employed_prev, maxi(pop_prev, 1))
	eq_int(_sum(cut), expect_cut,
			"ADV-E06/INV-080：S07 的就业减少量必须精确等于 "
			+ "mul_div_floor(流出人数, 在岗人数, 期初人口)（docs/12 §7.7），容差 0")
	eq_int(lab.employment(_cell(r, MANU), MID), 200_000 - expect_cut,
			"ADV-E06/INV-080：cell 侧在岗人数必须同步减少同样多，否则人口与就业脱钩")

	rc = pop.apply_employment_cut(cut)
	eq_int(rc, JWResult.OK, "ADV-E06：群组侧回写不应失败")
	eq_int(pop.employed_total(g_work), employed_prev - expect_cut,
			"ADV-E06/INV-077：群组侧在岗人数必须与 cell 侧同步，两侧是同一事实的两个索引")
	rc = lab.check_employment_views(pop)
	eq_int(rc, JWResult.OK, "ADV-E06/INV-077：剥离之后两侧口径仍必须逐（地区,技能）精确相等")


# ══════════════════════════════════════════════════════════════════════════
#  J 族：数值边界攻击（docs/31 §11）
# ══════════════════════════════════════════════════════════════════════════

## ADV-J01 int64 溢出（R-SCALE-01 之后的**新**边界）。
## 检验 INV-006（一切乘法过显式溢出前置检查，release 也执行）、INV-002（先乘后除只允许 mul_div_floor）、
## 裁定 R-SCALE-01 连带要求 1。
func test_adv_j01_new_scale_overflow_boundaries() -> void:
	# 刻度自检：这些数一旦被改回旧刻度，本测试的全部期望值都失去意义。
	eq_int(JWUnits.U_SCALE, 1_000_000_000, "R-SCALE-01：1 U 必须等于 1e9 μU")
	eq_int(JWUnits.AMOUNT_MAX, 4_000_000_000_000_000, "R-SCALE-01：AMOUNT_MAX 必须是 4e15")
	eq_int(JWUnits.PRICE_MIN, 400_000_000, "R-SCALE-01：PRICE_MIN 必须是 4e8")
	eq_int(JWUnits.PRICE_MAX, 2_500_000_000, "R-SCALE-01：PRICE_MAX 必须是 2.5e9")

	# 新边界一：amount × ppm。4e15 × 1e6 = 4e21 > 9.22e18 —— 真溢出，必须被抓且不得饱和截断。
	JWResult.clear_pending()
	var naive: int = JWMath.mul(JWUnits.AMOUNT_MAX, PPM)
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW,
			"ADV-J01/INV-006：mul(AMOUNT_MAX 4e15, PPM 1e6) = 4e21 必须登记 INT_OVERFLOW")
	eq_int(naive, 0, "ADV-J01：溢出时返回 0，不得做饱和截断（docs/17 §4.3 mul 的失败行）")

	JWResult.clear_pending()
	naive = JWMath.mul(-JWUnits.AMOUNT_MAX, PPM)
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW,
			"ADV-J01/INV-006：负方向同样必须被抓（-4e15 × 1e6）")

	# 新边界二：qty × price。1e12 × 2.5e9 = 2.5e21 —— docs/12 §5.6 点名的第二处真溢出。
	JWResult.clear_pending()
	naive = JWMath.mul(JWUnits.QTY_MAX, JWUnits.PRICE_MAX)
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW,
			"ADV-J01/INV-006：mul(QTY_MAX 1e12, PRICE_MAX 2.5e9) = 2.5e21 必须登记 INT_OVERFLOW")

	# 正路：mul_div_floor 必须给出精确值且一次故障都不登记。
	JWResult.clear_pending()
	eq_int(JWMath.mul_div_floor(JWUnits.AMOUNT_MAX, PPM, PPM), JWUnits.AMOUNT_MAX,
			"ADV-J01/R-SCALE-01：mul_div_floor(4e15, 1e6, 1e6) 的数学真值就是 4e15，必须精确返回")
	eq_int(JWMath.mul_ppm(JWUnits.AMOUNT_MAX, PPM), JWUnits.AMOUNT_MAX,
			"ADV-J01/INV-002：mul_ppm 必须走 mul_div_floor；否则它在契约上界处就会返回 0")
	eq_int(JWMath.mul_div_floor(JWUnits.QTY_MAX, JWUnits.PRICE_MAX, Q_SCALE), 2_500_000_000_000_000,
			"ADV-J01/docs/12 §5.6：成交金额 = mul_div_floor(1e12 μQ, 2.5e9 μU/Q_s, 1e6) = 2.5e15 μU")
	le_int(2_500_000_000_000_000, JWUnits.AMOUNT_MAX,
			"ADV-J01/INV-007：契约上界处的成交金额 2.5e15 必须仍落在 AMOUNT_MAX 4e15 之内")
	eq_int(JWResult.pending_code(), 0,
			"ADV-J01：全部走 mul_div_floor 的正路一条故障都不得登记；"
			+ "若这里有 INT_OVERFLOW，说明某个换算仍是裸乘（INV-002 被破坏）")


## ADV-J01（续）数值边界检查本身。检验 INV-007（|金额| ≤ AMOUNT_MAX、|数量| ≤ QTY_MAX、
## price ∈ [PRICE_MIN, PRICE_MAX]）。
func test_adv_j01_range_guards_are_exact_at_the_boundary() -> void:
	JWResult.clear_pending()
	var x: int = JWMath.check_amount(JWUnits.AMOUNT_MAX)
	eq_int(JWResult.pending_code(), 0, "ADV-J01/INV-007：恰好等于 AMOUNT_MAX 是合法值，不得报错")
	eq_int(x, JWUnits.AMOUNT_MAX, "ADV-J01：护栏不改值，只登记")

	JWResult.clear_pending()
	JWMath.check_amount(JWUnits.AMOUNT_MAX + 1)
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW,
			"ADV-J01/INV-007：AMOUNT_MAX + 1 必须越界")
	JWResult.clear_pending()
	JWMath.check_amount(-JWUnits.AMOUNT_MAX - 1)
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW,
			"ADV-J01/INV-007：负方向的 AMOUNT_MAX + 1 同样越界")

	JWResult.clear_pending()
	JWMath.check_qty(JWUnits.QTY_MAX)
	eq_int(JWResult.pending_code(), 0, "ADV-J01/INV-007：恰好等于 QTY_MAX 是合法值")
	JWResult.clear_pending()
	JWMath.check_qty(JWUnits.QTY_MAX + 1)
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW,
			"ADV-J01/INV-007：QTY_MAX + 1 必须越界")

	JWResult.clear_pending()
	JWMath.check_price(JWUnits.PRICE_MIN)
	JWMath.check_price(JWUnits.PRICE_MAX)
	eq_int(JWResult.pending_code(), 0,
			"ADV-J01/INV-066：价格区间的两个端点都是合法值（R-SCALE-01 后为 [4e8, 2.5e9]）")
	JWResult.clear_pending()
	JWMath.check_price(JWUnits.PRICE_MIN - 1)
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW,
			"ADV-J01/INV-066：低于 PRICE_MIN 一个 μU 就必须越界")
	JWResult.clear_pending()
	JWMath.check_price(JWUnits.PRICE_MAX + 1)
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW,
			"ADV-J01/INV-066：高于 PRICE_MAX 一个 μU 就必须越界")


## ADV-J01（续）RNG 种子拼接不得位重叠。检验 INV-010 与 docs/31 ADV-J01 的
## 「(q << 32) ^ index 形式会与季度号发生位重叠」。
##
## **本用例与契约不符，已按契约修正**（原断言见下）。原先断言的是
##   `draw_raw(q=1, index=0) != draw_raw(q=0, index=2^32)`
## 并要求 `index == 2^32` 不登记任何故障——两条合起来等于要求把拼接式换成
## q 与 index 不共位域的另一个式子。但拼接式被三处契约同时钉死：
##   · `docs/12_simulation_contract.md` §0.4 的代码块：
##     `splitmix64(state.rng.root_seed ^ SALT[stream] ^ (q << 32) ^ index)`
##   · `docs/10_variable_dictionary.md` §10（`content/events/event_E05.json` 的
##     `randomness_zh` 逐字引用同一式）
##   · 已发布的 `param.rng_salt` 卡的 `definition` 字段
## 而 `docs/31` `ADV-J01` **自己的断言**是 `assert_eq(RNG.draw_raw(0, 1 << 31, 0),
## RNG.draw_raw_reference(0, 1 << 31, 0))`——比对参考实现，并未要求换式；
## 位重叠出现在 `docs/31` 的失败诊断里，归因写得很清楚：
## 「`1 << 40` 被接受 ⇒ **缺 INV-007 的上界校验**，后续 `(q << 32)` 形式的 RNG 种子拼接
## 会与季度号发生位重叠」——要补的是**操作数的上界校验**，不是另换一个拼接式。
## 按 18 > 12 > 10 > 31 的文档优先级，契约胜。
##
## 于是本用例改为检验契约真正要求的两件事：
##   一、合法定义域 q ∈ [0, 2^31)、index ∈ [0, 2^32) 内，(q, index) → 种子是单射
##       （q 占高 31 位、index 占低 32 位，位域不交叠，同一流在不同季不可能复现同一序列）；
##   二、域外输入必须报 FAULT，而不是悄悄拼出一个重叠的种子。
##       单条流抽满 2^32 = 4.3e9 次在 120 季里不可能发生，真到了就是工程缺陷。
func test_adv_j01_rng_seed_concat_has_no_bit_overlap() -> void:
	# 一、合法域内：季度号与抽样序号的位域不交叠。
	JWResult.clear_pending()
	var a: int = rng.draw_raw(JWUnits.RngStream.MARKET, 1, 0)
	var b: int = rng.draw_raw(JWUnits.RngStream.MARKET, 0, JWRngStreams.INDEX_MAX_EXCL - 1)
	ne_int(a, b,
			"ADV-J01：draw_raw(q=1, index=0) 与 draw_raw(q=0, index=2^32 − 1) 必须不同；"
			+ "相等即说明 index 已经爬进了 q 的位域，季度号与抽样序号发生重叠")
	var e: int = rng.draw_raw(JWUnits.RngStream.MARKET, 2, 0)
	ne_int(a, e, "ADV-J01/INV-010：相邻两季在同一 index 上不得复现同一个原始值")
	var c: int = rng.draw_raw(JWUnits.RngStream.MARKET, 0, 1)
	var d: int = rng.draw_raw(JWUnits.RngStream.EVENT, 0, 1)
	ne_int(c, d, "ADV-J01：不同随机流在同一 (q, index) 上必须给出不同的原始值（双流互不串扰）")
	eq_int(JWResult.pending_code(), 0,
			"ADV-J01：合法域的上界（q = 1、index = 2^32 − 1）不得登记任何故障")

	# 二、域外守卫（docs/31 ADV-J01 失败诊断点名的「上界校验」）。
	JWResult.clear_pending()
	var overlap: int = rng.draw_raw(JWUnits.RngStream.MARKET, 0, JWRngStreams.INDEX_MAX_EXCL)
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE,
			"ADV-J01：index == 2^32 会与 q 的位域重叠，必须登记 INDEX_OUT_OF_RANGE；"
			+ "静默拼接出一个重叠的种子才是这条对抗用例真正要防的事")
	eq_int(overlap, 0, "ADV-J01：越界时返回 0，不得给出一个看起来正常的种子")

	JWResult.clear_pending()
	rng.draw_raw(JWUnits.RngStream.MARKET, JWRngStreams.Q_MAX_EXCL, 0)
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE,
			"ADV-J01：q == 2^31 会让 q << 32 冲掉符号位，同样必须登记 INDEX_OUT_OF_RANGE")
	JWResult.clear_pending()


## ADV-J01（续）玩家可达路径上的契约上界：数量取 QTY_MAX 的生产结算不得溢出。
## 检验 INV-007、INV-043、INV-046。
func test_adv_j01_production_at_contract_ceiling_does_not_overflow() -> void:
	var ceiling: int = JWUnits.QTY_MAX - 1
	var cell: int = _cell(0, MANU)
	io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 1_000_000      # 1 μQ_agri / Q_manu
	inv.inv_input[JWIds.idx_inv(cell, AGRI)] = ceiling
	cap.cell_capacity_active[cell] = ceiling
	sec.f_output_plan[cell] = ceiling

	JWResult.clear_pending()
	inv.begin_production()
	var rc: int = sec.solve_output(cell, cap, lab, inv, io)
	eq_int(rc, JWResult.OK, "ADV-J01：契约上界处的约束求解不应失败")
	eq_int(sec.output_actual(cell), ceiling,
			"ADV-J01/INV-043：三项约束都恰好等于 QTY_MAX − 1 = 999 999 999 999 μQ，实际产量必须等于它；"
			+ "为 0 说明某处换算走了裸乘并被溢出守卫吞掉")
	rc = inv.consume_inputs(cell, ceiling, io)
	eq_int(rc, JWResult.OK, "ADV-J01/INV-046：上界处的耗料反算不应失败")
	eq_int(inv.inv_input[JWIds.idx_inv(cell, AGRI)], 0,
			"ADV-J01：ceil((1e12−1) × 1e6 / 1e6) = 1e12−1，正好用尽库存，不得透支")
	eq_int(JWResult.pending_code(), 0,
			"ADV-J01/INV-006：玩家可达路径（数量取契约上界）上不得出现任何 FAULT")


## ADV-J01（续）哨兵与合法上界的碰撞。
## INV-007 允许 |数量| 取到 QTY_MAX；而 docs/10 §5.3 的「该约束不适用」哨兵 SENTINEL 恰等于 QTY_MAX。
## 于是「计划产量恰好取到合法上界」与「该约束不适用」在编码上不可区分。
## docs/12 §5.3 明说「bound_plan 与 bound_capacity 永远有限」，所以此处必须得到 QTY_MAX 的产量，
## 而不是 Fault.UNBOUNDED_PRODUCTION。
func test_adv_j01_qty_max_plan_collides_with_sentinel() -> void:
	var cell: int = _cell(0, MANU)
	io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 1_000_000
	inv.inv_input[JWIds.idx_inv(cell, AGRI)] = JWUnits.QTY_MAX
	cap.cell_capacity_active[cell] = JWUnits.QTY_MAX
	sec.f_output_plan[cell] = JWUnits.QTY_MAX
	eq_int(JWUnits.SENTINEL, JWUnits.QTY_MAX,
			"ADV-J01/docs/10 §5.3：哨兵值恒等于 QTY_MAX —— 这正是本条测试要暴露的编码碰撞")

	JWResult.clear_pending()
	inv.begin_production()
	var rc: int = sec.solve_output(cell, cap, lab, inv, io)
	eq_int(rc, JWResult.OK,
			"ADV-J01/INV-007：计划与产能恰好取到合法上界 QTY_MAX 时不得判 UNBOUNDED_PRODUCTION；"
			+ "docs/12 §5.3 保证 bound_plan / bound_capacity 永远有限，"
			+ "「合法上界」与「不适用」共用同一个数是哨兵编码的缺口")
	eq_int(sec.output_actual(cell), JWUnits.QTY_MAX,
			"ADV-J01/INV-043：五项约束都等于 QTY_MAX ⇒ 实际产量必须是 QTY_MAX，不是 0")


## ADV-J01（续）现金取到 AMOUNT_MAX 时的招工闸门。
## 检验 INV-002 / INV-006（R-SCALE-01 连带要求 1：一切「先乘后除」只允许 mul_div_floor）、INV-007。
## 现金是合法状态量，其上界就是 AMOUNT_MAX = 4e15；`mul(cash, PPM)` = 4e21 必然溢出，
## 故 S03 §3.2 的「可负担用工」换算必须走 mul_div_floor。
func test_adv_j01_cash_at_amount_max_does_not_break_hiring() -> void:
	var r: int = 0
	var g_work: int = _grp(r, WORKING, MID)
	pop.population[g_work] = 1_000_000
	pop.participation_ppm[g_work] = 500_000
	var s: int = 0
	while s < JWUnits.S:
		var cell: int = _cell(r, s)
		io.labor_coeff[JWIds.idx_emp(cell, MID)] = 1_000_000
		lab.cell_employment[JWIds.idx_emp(cell, MID)] = 100_000
		pop.employed[JWIds.idx_group_emp(g_work, s)] = 100_000
		sec.f_output_plan[cell] = 200_000
		# INV-007：现金的合法上界就是 AMOUNT_MAX，夹具取的是契约允许的极值，不是非法值。
		_set_cash_cell(cell, JWUnits.AMOUNT_MAX)
		s += 1

	JWResult.clear_pending()
	JWResult.set_step(JWUnits.Phase.S03)
	var rc: int = lab.hire_and_fire(sec.f_output_plan, io, pricing, pop, accounts, params)
	eq_int(rc, JWResult.OK,
			"ADV-J01/INV-002：现金取到 AMOUNT_MAX 时招工不得失败；"
			+ "返回 90(INT_OVERFLOW) 说明 S03 的资金闸把两个 μU 量（现金 × 工资总额）直接裸乘，"
			+ "R-SCALE-01 连带要求 1 规定这类「先乘后除」必须走 mul_div_floor")
	ne_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW,
			"ADV-J01/INV-006：合法的现金上界不得让结算登记 INT_OVERFLOW")


## ADV-J02 极端税率的可支配收入侧。检验 INV-086（可支配收入恒等式）、
## INV-063（居民只能花已收到的钱）。
##
## 说明：税率参数的 valid_range 拒绝属命令层（E_PARAM_RANGE），由命令层对抗套件覆盖；
## 本方法检验 100% 税率下**状态侧**必须成立的两条：可支配不得为负、消费预算必须是 0。
func test_adv_j02_full_tax_rate_yields_zero_not_negative() -> void:
	var g: int = _grp(0, WORKING, MID)
	pop.population[g] = 1_000_000
	pop.f_wage_income[g] = 1_360_000_000            # 1.36 U
	pop.f_income_tax_paid[g] = 1_360_000_000        # 税率 100%
	eq_int(pop.disposable_income(g), 0,
			"ADV-J02/INV-086：disposable == 工资 + 财产 + 转移 + 赡养入 − 赡养出 − 个税；"
			+ "100% 税率下恰好为 0，**不是负数**（税额必须被 min(应纳税额, 税基) 夹住）")

	_set_cash_group(g, 0)
	params[JWUnits.Param.MPC_PPM] = 900_000
	params[JWUnits.Param.DISSAVE_PPM] = 0
	var budget: PackedInt64Array = _zeros(JWUnits.GROUP_PROD_N)
	var rc: int = pop.consumption_budget_into(budget, accounts, params)
	eq_int(rc, JWResult.OK, "ADV-J02：零可支配不是故障，预算为 0 是正常结果")
	var spend: int = 0
	var s: int = 0
	while s < JWUnits.S:
		spend += budget[JWIds.idx_group_prod(g, s)]
		s += 1
	eq_int(spend, 0,
			"ADV-J02/INV-063：现金为 0 的组本季消费预算必须是 0；"
			+ "非 0 即说明消费函数用的不是实际可支配现金，而是名义收入")


## ADV-J03 零人口地区。检验 INV-044（禁止除零，也禁止用 max(c,1) 伪装）、
## INV-075（失业率分母是劳动力）。
func test_adv_j03_empty_region_never_divides_by_zero() -> void:
	# 全国人口为 0：失业率的分母是 0，是最典型的除零陷阱。
	JWResult.clear_pending()
	JWResult.set_step(JWUnits.Phase.S03)
	var rc: int = lab.compute_unemployment(pop)
	eq_int(rc, JWResult.OK, "ADV-J03：人口为 0 不是故障")
	ne_int(JWResult.pending_code(), JWResult.Fault.DIV_ZERO,
			"ADV-J03/INV-044：labor_force == 0 时必须不做除法，而不是除零")
	eq_int(lab.unemployment_ppm(), 0,
			"ADV-J03：labor_force == 0 时失业率记 0（并由 UI 显示「—」），"
			+ "而不是用 max(分母,1) 伪装成一个「0% 失业、形势大好」的假值")
	eq_int(lab.unemployed_persons(), 0, "ADV-J03/INV-075：无人则失业人数为 0，不得为负")

	# 该地区的生产：劳动系数 > 0 而在岗为 0 ⇒ 产量 0，最紧约束报告为 labor（显式的 0）。
	var cell: int = _cell(3, MANU)
	io.labor_coeff[JWIds.idx_emp(cell, MID)] = 1_000_000
	cap.cell_capacity_active[cell] = 5_000_000
	sec.f_output_plan[cell] = 5_000_000
	rc = sec.solve_output(cell, cap, lab, inv, io)
	eq_int(rc, JWResult.OK, "ADV-J03：零人口地区的约束求解不应失败")
	eq_int(sec.output_actual(cell), 0,
			"ADV-J03：无人可用 ⇒ bound_labor = floor(0 × 1e6 / 1e6) = 0 ⇒ 产量 0（显式的 0）")
	eq_int(sec.binding_code(cell), B_LABOR,
			"ADV-J03/INV-045：零人口地区的最紧约束必须报告为 labor，玩家才知道缺的是人")
	eq_int(JWResult.pending_code(), 0, "ADV-J03：整条路径一次故障都不得登记")

	# 住房紧张度：容量为 0 是另一个除零陷阱，契约要求返回 1 000 000（满）。
	JWResult.clear_pending()
	eq_int(mig.housing_stress_ppm(pop, cap, 3), 1_000_000,
			"ADV-J03/docs/17 §4.16：housing_capacity == 0 时住房紧张度返回 1 000 000（满），"
			+ "不得除零")
	ne_int(JWResult.pending_code(), JWResult.Fault.DIV_ZERO,
			"ADV-J03/INV-044：容量为 0 的地区不得触发 DIV_ZERO")


## ADV-J04 空群组。检验 INV-003 / INV-124（最大余数法：权重为 0 的项必须先被排除再分余数）、
## INV-044、INV-142（允许空组）。
func test_adv_j04_empty_groups_get_zero_weight_not_leftovers() -> void:
	# 权重为 0 的项一分不得分到；非零项之间的和必须精确等于总额。
	var weights: PackedInt64Array = PackedInt64Array([0, 1, 1, 0, 1])
	var tiebreak: PackedInt64Array = PackedInt64Array([0, 1, 2, 3, 4])
	var out: PackedInt64Array = JWMath.split_lr(1_000_000, weights, tiebreak)
	eq_int(out.size(), 5, "ADV-J04：split_lr 必须返回与权重等长的数组")
	eq_int(out[0], 0, "ADV-J04/INV-124：权重为 0 的空组不得分到任何份额（余数也不行）")
	eq_int(out[3], 0, "ADV-J04/INV-124：第二个空组同样必须是 0")
	eq_int(out[1] + out[2] + out[4], 1_000_000,
			"ADV-J04/INV-003：Σ 分项必须精确等于原额 1 000 000（1e6 除以 3 余 1，余数只能给非零项）")

	# 全部权重为 0：不许平均分，也不许悄悄给某一项 —— 原额作为残差交回调用方登记。
	JWResult.clear_pending()
	var zero_w: PackedInt64Array = PackedInt64Array([0, 0, 0])
	var zero_tb: PackedInt64Array = PackedInt64Array([0, 1, 2])
	var out2: PackedInt64Array = _zeros(3)
	var residual: int = JWMath.split_lr_into(777, zero_w, zero_tb, out2)
	eq_int(residual, 777,
			"ADV-J04/INV-005：权重全 0 时必须把原额作为残差交回（由调用方登记进 log.rounding），"
			+ "不得替调用方发明一条分配规则")
	eq_int(_sum(out2), 0, "ADV-J04：权重全 0 时不得分出任何一份")
	eq_int(JWResult.pending_code(), 0, "ADV-J04：权重全 0 是合法情形，不是故障")

	# 空组的人均量与指数：分母为 0 必须走 max(base,1) 的**指数定义式**，且结果是 0 不是崩溃。
	JWResult.clear_pending()
	var g_empty: int = _grp(2, WORKING, HIGH)
	pop.population[g_empty] = 0
	pop.base_real_cons[g_empty] = 0
	JWResult.set_step(JWUnits.Phase.S07)
	var rc: int = pop.update_living_indices(_zeros(JWUnits.GROUP_SVC_N))
	eq_int(rc, JWResult.OK, "ADV-J04/INV-142：36 组里允许有空组，空组不得让指数计算失败")
	eq_int(pop.consumption_index[g_empty], 0,
			"ADV-J04：空组的消费指数 = mul_div_floor(0, 1e6, max(base,1)) = 0")
	eq_int(pop.labor_force(g_empty), 0, "ADV-J04/INV-075：空组的劳动力恒为 0")
	ne_int(JWResult.pending_code(), JWResult.Fault.DIV_ZERO,
			"ADV-J04/INV-044：空组的人均运算不得除零")


## ADV-J05 全经济归零。检验 INV-044、INV-047、INV-066（价格有界）、
## 以及「恢复之后不留后遗症」。
func test_adv_j05_total_shutdown_then_recovery() -> void:
	# 全部 cell：无产能、无投入、无劳动 ⇒ 全零产出，连续 8 季不得崩、不得留负数。
	var q: int = 0
	while q < 8:
		JWResult.clear_pending()
		inv.begin_production()
		var rc: int = sec.settle_production(cap, lab, inv, io)
		eq_int(rc, JWResult.OK, "ADV-J05：全经济归零不是故障（第 %d 季）" % q)
		var cell: int = 0
		while cell < JWUnits.CELL:
			eq_int(sec.output_actual(cell), 0,
					"ADV-J05：无产能无投入 ⇒ cell %d 的产量必须是 0（第 %d 季）" % [cell, q])
			ge_int(inv.inv_output[cell], 0,
					"ADV-J05/INV-048：cell %d 的成品库存不得为负（第 %d 季）" % [cell, q])
			cell += 1
		rc = inv.check_stock_identity(sec.output_actual_array())
		eq_int(rc, JWResult.OK, "ADV-J05/INV-047：全零经济的库存恒等式仍必须成立（第 %d 季）" % q)
		eq_int(JWResult.pending_code(), 0, "ADV-J05：全零的一季不得登记任何故障（第 %d 季）" % q)
		q += 1

	# 价格在供给恒为 0 的极端缺口下仍必须落在 [PRICE_MIN, PRICE_MAX] 内。
	JWResult.clear_pending()
	JWResult.set_step(JWUnits.Phase.S07)
	var supply: PackedInt64Array = _zeros(JWUnits.S)
	var demand: PackedInt64Array = PackedInt64Array([1_000_000, 1_000_000, 1_000_000, 1_000_000])
	var inv_now: PackedInt64Array = _zeros(JWUnits.S)
	var inv_target: PackedInt64Array = PackedInt64Array([1_000_000, 1_000_000, 0, 0])
	var round_i: int = 0
	while round_i < 8:
		var rc2: int = pricing.update_prices(supply, demand, inv_now, inv_target, io.storable, params)
		eq_int(rc2, JWResult.OK, "ADV-J05：供给为 0 的价格更新不应失败（第 %d 轮）" % round_i)
		_swap_prices("ADV-J05 第 %d 轮" % round_i)
		var s: int = 0
		while s < JWUnits.S:
			in_range_int(pricing.price_of(s), JWUnits.PRICE_MIN, JWUnits.PRICE_MAX,
					"ADV-J05/INV-066：部门 %d 的价格必须始终落在 [4e8, 2.5e9]（第 %d 轮）"
					% [s, round_i])
			s += 1
		round_i += 1
	ne_int(JWResult.pending_code(), JWResult.Fault.DIV_ZERO,
			"ADV-J05/INV-117：供给为 0 不得触发除零（实际 GDP 按基年价重算，不除任何价格指数）")

	# 恢复：给回产能与投入，系统必须能正常走出来，不留取整后遗症。
	JWResult.clear_pending()
	var cell2: int = _cell(0, MANU)
	io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 1_000_000
	inv.inv_input[JWIds.idx_inv(cell2, AGRI)] = 2_000_000
	cap.cell_capacity_active[cell2] = 2_000_000
	sec.f_output_plan[cell2] = 2_000_000
	inv.begin_production()
	var rc3: int = sec.settle_production(cap, lab, inv, io)
	eq_int(rc3, JWResult.OK, "ADV-J05：恢复季的生产结算不应失败")
	eq_int(sec.output_actual(cell2), 2_000_000,
			"ADV-J05：恢复后产量必须回到 min(计划, 产能, 材料) = 2 000 000 μQ —— 能走出来，无后遗症")


## ADV-J06 价格反复触顶。检验 INV-066（价格有界）、INV-067（单季变动有界）、
## INV-068（缺口为 0 时的不动点）、INV-069（每次夹逼写日志并计数）。
func test_adv_j06_price_clamp_is_bounded_logged_and_fixpointed() -> void:
	JWResult.set_step(JWUnits.Phase.S07)
	# 极端持续短缺：供给 1，需求 1e12，连续 40 季撞天花板。
	var supply: PackedInt64Array = PackedInt64Array([1, 1, 1, 1])
	var demand: PackedInt64Array = PackedInt64Array([1_000_000_000_000, 1_000_000_000_000,
			1_000_000_000_000, 1_000_000_000_000])
	var inv_now: PackedInt64Array = _zeros(JWUnits.S)
	var inv_target: PackedInt64Array = PackedInt64Array([1_000_000, 1_000_000, 0, 0])
	var step_max: int = params[JWUnits.Param.PRICE_STEP_MAX_PPM]

	var q: int = 0
	while q < 60:
		var before: PackedInt64Array = pricing.price.duplicate()
		var rc: int = pricing.update_prices(supply, demand, inv_now, inv_target, io.storable, params)
		eq_int(rc, JWResult.OK, "ADV-J06：极端短缺下的价格更新不应失败（第 %d 季）" % q)
		_swap_prices("ADV-J06 第 %d 季" % q)
		var s: int = 0
		while s < JWUnits.S:
			in_range_int(pricing.price_of(s), JWUnits.PRICE_MIN, JWUnits.PRICE_MAX,
					"ADV-J06/INV-066：部门 %d 的价格永不越界（第 %d 季）" % [s, q])
			le_int(JWMath.absi(pricing.price_of(s) - before[s]),
					JWMath.mul_ppm(before[s], step_max),
					"ADV-J06/INV-067：部门 %d 的单季变动不得超过 price_step_max_ppm × 上季价（第 %d 季）"
					% [s, q])
			s += 1
		q += 1

	var s2: int = 0
	while s2 < JWUnits.S:
		eq_int(pricing.price_of(s2), JWUnits.PRICE_MAX,
				"ADV-J06/INV-066：每季至多 +2% 的复利在 47 季内就会撞到上界，"
				+ "60 季之后价格必须恰好停在 2.5e9（部门 %d），而不是穿过去" % s2)
		s2 += 1
	check(pricing.clamp_used > 0, "ADV-J06：60 季撞顶必须真的发生过夹逼，否则这条测试没测到东西")
	eq_int(pricing.log_row_count(), pricing.clamp_used,
			"ADV-J06/INV-069：每一次夹逼都必须写一条 log.clamp，计数与日志行数必须一致")

	# 不动点：缺口恒为 0 时价格序列严格不变（取整偏置不得累积，INV-068）。
	before_each()
	JWResult.set_step(JWUnits.Phase.S07)
	var bal_supply: PackedInt64Array = PackedInt64Array([1_000_000, 1_000_000, 1_000_000, 1_000_000])
	var bal_demand: PackedInt64Array = bal_supply.duplicate()
	var bal_inv: PackedInt64Array = PackedInt64Array([500_000, 500_000, 0, 0])
	var bal_target: PackedInt64Array = bal_inv.duplicate()
	var base_before: PackedInt64Array = pricing.price.duplicate()
	var r2: int = 0
	while r2 < 4:
		var rc2: int = pricing.update_prices(bal_supply, bal_demand, bal_inv, bal_target,
				io.storable, params)
		eq_int(rc2, JWResult.OK, "ADV-J06：平衡态的价格更新不应失败（第 %d 轮）" % r2)
		_swap_prices("ADV-J06 平衡态第 %d 轮" % r2)
		r2 += 1
	eq_int_array(pricing.price, base_before,
			"ADV-J06/INV-068：供需与库存都恰好平衡时价格必须逐位不变（不动点）；"
			+ "漂移即说明存在取整偏置累积")
	eq_int(pricing.clamp_used, 0, "ADV-J06/INV-069：平衡态一次夹逼都不该发生")


## ADV-J07 长程压力（缩减版：人口 + 迁移子系统 120 季）。
## 检验 INV-071 / INV-072 / INV-073 / INV-083 在长程下不漂移；
## 完整的「100 种子 × 120 季全经济」压测需要 JWTurnRunner 驱动，见交付说明的 open_questions。
func test_adv_j07_long_run_population_conservation_120_quarters() -> void:
	_migration_world(1_000_000, 30_000, 400_000_000_000_000, 1_000_000)
	var r: int = 0
	while r < JWUnits.R:
		pop.birth_ppm[r] = 8_000
		r += 1
	var g: int = 0
	while g < JWUnits.GROUP:
		pop.death_ppm[g] = 5_000
		g += 1
	pop.age_out_ppm = PackedInt64Array([20_000, 10_000, 0])

	var nation: int = _nation_pop()
	var q: int = 0
	while q < 120:
		JWResult.clear_pending()
		JWResult.set_step(JWUnits.Phase.S07)
		pop.reset_flows()
		mig.reset_flows()
		rng.begin_quarter(q)
		var prev: PackedInt64Array = pop.population.duplicate()

		var rc: int = pop.update_demography(rng, params)
		eq_int(rc, JWResult.OK, "ADV-J07：第 %d 季的人口更新不应失败" % q)
		rc = mig.run(pop, lab, cap, pricing, ledger, accounts, rng, params)
		eq_int(rc, JWResult.OK, "ADV-J07：第 %d 季的迁移不应失败" % q)
		# docs/12 §7.7：§7.7 的 outflow 含迁出量，而迁出量由 JWMigration 持有 ——
		# 守恒终检要复核两边的账一致，故先把本季迁出登记回人口块。
		rc = pop.record_migration_out(mig.out_by_group())
		eq_int(rc, JWResult.OK, "ADV-J07：第 %d 季的迁出登记不应失败" % q)
		rc = pop.check_conservation(mig.in_by_group(), mig.out_by_group())
		eq_int(rc, JWResult.OK, "ADV-J07/INV-071/072/073：第 %d 季的人口守恒终检必须通过" % q)

		var births: int = _sum(pop.f_births)
		var deaths: int = _sum(pop.f_deaths)
		nation = nation + births - deaths
		eq_int(_nation_pop(), nation,
				"ADV-J07/INV-071：第 %d 季的全国人口 == 上季 + 出生 − 死亡（迁移只搬不生）" % q)
		eq_int(_sum(mig.in_by_group()), _sum(mig.out_by_group()),
				"ADV-J07/INV-073：第 %d 季 Σ 迁入 == Σ 迁出" % q)

		var rr: int = 0
		while rr < JWUnits.R:
			le_int(_region_occupied(rr), cap.housing_stock[rr],
					"ADV-J07/INV-083：第 %d 季地区 %d 的占用不得超过住房存量" % [q, rr])
			le_int(cap.housing_stock[rr], cap.housing_capacity[rr],
					"ADV-J07/INV-083：第 %d 季地区 %d 的存量不得超过容量" % [q, rr])
			rr += 1
		var gg: int = 0
		while gg < JWUnits.GROUP:
			ge_int(pop.population[gg], 0,
					"ADV-J07：第 %d 季组 %d 的人口不得为负（prev=%d）" % [q, gg, prev[gg]])
			gg += 1
		eq_int(JWResult.pending_code(), 0, "ADV-J07：第 %d 季不得登记任何故障" % q)
		q += 1
