## S05 生产约束的独立验收测试（五项约束、零系数、电力不入库存、ceil 不透支、库存恒等式）。
##
## 本文件**只依据契约**编写，不参考实现：
##   docs/18 R-SCALE-01（mul_div_floor 是唯一合法的「先乘后除」入口）
##   docs/12 §5.2 / §5.3 / §5.4 / §5.8（八步结算合同的 S05 条文）
##   docs/10 §14.4 INV-043…INV-053（生产、库存与资产不变量总表）
##   docs/30 T-U-A-13 / T-U-A-15 / T-U-A-17、T-U-CEIL-SAFE、test_u_zero_coefficient
##   docs/31 ADV-D02（制造负库存）、ADV-D04（把电力存起来）、ADV-D06（用损耗掩盖盘点差异）、
##           ADV-D07（能源自举）、ADV-J03（零分母不得除零，禁止 max(c,1)）
##   docs/17 §4.7/§4.13/§4.15/§4.17/§4.18（成员与方法签名，签名不得改）
##
## 期望值一律在注释里写明推导过程，使断言失败时能一眼看出是实现错还是契约变了。
extends JWTest

# ── 契约常量的本地别名（数值来自 docs/10 §14.4 与 JWUnits，不在此处重新定义） ──

const AGRI: int = JWUnits.Sector.AGRI
const MANU: int = JWUnits.Sector.MANU
const ENERGY: int = JWUnits.Sector.ENERGY
const SERVICES: int = JWUnits.Sector.SERVICES

const B_PLAN: int = JWUnits.Binding.PLAN
const B_CAPACITY: int = JWUnits.Binding.CAPACITY
const B_LABOR: int = JWUnits.Binding.LABOR
const B_ENERGY: int = JWUnits.Binding.ENERGY
const B_MATERIALS: int = JWUnits.Binding.MATERIALS

# ── 夹具 ──────────────────────────────────────────────────────────────────

var _io: JWIoTable
var _cap: JWCapital
var _lab: JWLaborMarket
var _inv: JWInventory
var _sec: JWSectorModel
var _params: PackedInt64Array


func before_each() -> void:
	_setup()


## 重建一套干净夹具。测试内部要做第二个独立场景时可以再调一次。
##
## 全部契约数组显式换成**正确长度的全零数组**，这样夹具不依赖 allocate() 的实现状态；
## 私有 scratch 仍由 allocate() 负责。
func _setup() -> void:
	JWResult.clear_pending()

	_io = JWIoTable.new()
	_io.allocate()
	_io.io_coeff = _zeros(JWUnits.IO_N)
	_io.labor_coeff = _zeros(JWUnits.EMP_N)
	_io.energy_coeff = _zeros(JWUnits.CELL)
	_io.spoilage_ppm = _zeros(JWUnits.S)
	_io.depreciation_ppm = _zeros(JWUnits.S)
	_io.capacity_per_capital_ppm = _zeros(JWUnits.S)
	_io.emission_ppm = _zeros(JWUnits.S)
	# INV-150 / INV-049：energy 与 services 必须不可库存。
	_io.storable = PackedInt64Array([1, 1, 0, 0])

	_cap = JWCapital.new()
	_cap.allocate()
	_cap.cell_capacity_active = _zeros(JWUnits.CELL)
	_cap.cell_capacity_pending = _zeros(JWUnits.CELL)
	_cap.cell_capital_value = _zeros(JWUnits.CELL)
	_cap.cell_wip = _zeros(JWUnits.CELL)
	_cap.cell_maint_backlog = _zeros(JWUnits.CELL)
	_cap.grid_capacity = _zeros(JWUnits.R)
	_cap.f_emissions = _zeros(JWUnits.R)

	_lab = JWLaborMarket.new()
	_lab.allocate()
	_lab.cell_employment = _zeros(JWUnits.EMP_N)

	_inv = JWInventory.new()
	_inv.allocate()
	_inv.inv_output = _zeros(JWUnits.CELL)
	_inv.inv_input = _zeros(JWUnits.INV_N)
	_inv.f_consumed = _zeros(JWUnits.INV_N)
	_inv.f_purchased = _zeros(JWUnits.INV_N)
	_inv.f_sold = _zeros(JWUnits.CELL)
	_inv.f_spoilage_out = _zeros(JWUnits.CELL)
	_inv.f_spoilage_in = _zeros(JWUnits.INV_N)
	_inv.f_unmet_demand = _zeros(JWUnits.CELL)
	_inv.m_supply = _zeros(JWUnits.S)
	_inv.m_demand = _zeros(JWUnits.MARKET_N)
	_inv.m_traded = _zeros(JWUnits.MARKET_N)
	_inv.m_unmet = _zeros(JWUnits.MARKET_N)
	_inv.m_rule = _zeros(JWUnits.S)
	_inv.m_inv_target = _zeros(JWUnits.CELL)

	_sec = JWSectorModel.new()
	_sec.allocate()
	_sec.f_output_plan = _zeros(JWUnits.CELL)
	_sec.f_bound_plan = _zeros(JWUnits.CELL)
	_sec.f_bound_capacity = _zeros(JWUnits.CELL)
	_sec.f_bound_labor = _zeros(JWUnits.CELL)
	_sec.f_bound_energy = _zeros(JWUnits.CELL)
	_sec.f_bound_materials = _zeros(JWUnits.CELL)
	_sec.f_binding_code = _zeros(JWUnits.CELL)
	_sec.f_output_actual = _zeros(JWUnits.CELL)
	_sec.f_energy_allocated = _zeros(JWUnits.CELL)
	_sec.f_energy_unused = _zeros(JWUnits.CELL)
	_sec.f_elec_supply = _zeros(JWUnits.R)
	_sec.f_elec_demand = _zeros(JWUnits.R)

	_params = _zeros(JWUnits.PARAM_N)


func _zeros(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(0)
	return a


## 独立复算「可用量 → 该 cell 自己产品的 μQ_s」的换算（docs/12 §5.3 的 floor 方向）。
## 用 JWMath.mul_div_floor 是因为裁定 R-SCALE-01 规定它是唯一合法入口，且它已有独立测试。
func _bound_from(avail: int, coeff: int) -> int:
	return JWMath.mul_div_floor(avail, JWUnits.PPM, coeff)


# ── 1 五项约束取最紧 ────────────────────────────────────────────────────────

## INV-043（output_actual == min(激活的候选约束)）、INV-045（slack[binding] == 0，其余 == 候选 − q）。
## 契约：docs/12 §5.3。五项候选全部有限且两两不等，argmin 唯一，诊断信息可逐项核对。
func test_u_five_bounds_take_the_tightest() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.ZHONGZHOU, MANU)   # 1*4+1 == 5

	# 换算方向：可用量 A（μQ_j 或 人）与系数 c（每 Q_s）给出候选 floor(A × 1e6 / c) μQ_s。

	# 1) 计划：直接就是 bound_plan（docs/12 §5.3 第 1 项）
	_sec.f_output_plan[cell] = 900_000_000

	# 2) 产能：维护欠账为 0 ⇒ bound_capacity == capacity_active
	_cap.cell_capacity_active[cell] = 800_000_000
	_cap.cell_maint_backlog[cell] = 0

	# 3) 劳动：低技能档 1 000 人/Q_s，在岗 700 000 人
	#    ⇒ floor(700 000 × 1e6 / 1000) == 700 000 000 μQ_s
	_io.labor_coeff[JWIds.idx_emp(cell, JWUnits.Skill.LOW)] = 1_000
	_lab.cell_employment[JWIds.idx_emp(cell, JWUnits.Skill.LOW)] = 700_000

	# 4) 能源：a_e == 2 000 μQ_e/Q_s，获配 1 200 000 μQ_e
	#    ⇒ floor(1 200 000 × 1e6 / 2000) == 600 000 000 μQ_s
	_io.io_coeff[JWIds.idx_io(ENERGY, MANU)] = 2_000
	_io.energy_coeff[cell] = 2_000                    # V-IO-08：冗余副本必须一致
	_sec.f_energy_allocated[cell] = 1_200_000

	# 5) 材料：agri→manu 500 μQ_agri/Q_manu，期初库存 250 000 μQ_agri
	#    ⇒ floor(250 000 × 1e6 / 500) == 500 000 000 μQ_s ← 最紧
	_io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 500
	_inv.inv_input[JWIds.idx_inv(cell, AGRI)] = 250_000

	var rc: int = _sec.solve_output(cell, _cap, _lab, _inv, _io)
	eq_int(rc, JWResult.OK, "solve_output 在五项约束全部合法时不得返回故障码")

	eq_int(_sec.f_bound_plan[cell], 900_000_000, "bound_plan 就是 output_plan（docs/12 §5.3 第 1 项）")
	eq_int(_sec.f_bound_capacity[cell], 800_000_000,
			"maintenance_backlog == 0 时 bound_capacity 应等于 capacity_active == 800 000 000")
	eq_int(_sec.f_bound_labor[cell], _bound_from(700_000, 1_000),
			"bound_labor 应为 floor(700 000 人 × 1e6 / 1000 人每 Q_s) == 700 000 000 μQ_s")
	eq_int(_sec.f_bound_energy[cell], _bound_from(1_200_000, 2_000),
			"bound_energy 应为 floor(1 200 000 μQ_e × 1e6 / 2000) == 600 000 000 μQ_s")
	eq_int(_sec.f_bound_materials[cell], _bound_from(250_000, 500),
			"bound_materials 应为 floor(250 000 μQ_agri × 1e6 / 500) == 500 000 000 μQ_s")

	eq_int(_sec.output_actual(cell), 500_000_000,
			"五项候选 [9e8, 8e8, 7e8, 6e8, 5e8] 的最小值是 500 000 000（INV-043）")
	eq_int(_sec.binding_code(cell), B_MATERIALS,
			"最紧的一项是材料，binding_code 必须是 4 materials（INV-045，报告的唯一数据源）")

	# INV-045：slack[binding] 恒为 0，其余等于候选值减实际产量且非负。
	var q: int = _sec.output_actual(cell)
	eq_int(_sec.bound_value(cell, B_MATERIALS) - q, 0, "binding 项的 slack 必须恰为 0（INV-045）")
	eq_int(_sec.bound_value(cell, B_PLAN) - q, 400_000_000, "plan 的 slack == 9e8 − 5e8")
	eq_int(_sec.bound_value(cell, B_CAPACITY) - q, 300_000_000, "capacity 的 slack == 8e8 − 5e8")
	eq_int(_sec.bound_value(cell, B_LABOR) - q, 200_000_000, "labor 的 slack == 7e8 − 5e8")
	eq_int(_sec.bound_value(cell, B_ENERGY) - q, 100_000_000, "energy 的 slack == 6e8 − 5e8")

	# INV-043 的两条附带断言：实际产量不得超过计划，也不得超过在用产能。
	le_int(_sec.output_actual(cell), _sec.f_output_plan[cell],
			"INV-043：output_actual 不得超过 output_plan")
	le_int(_sec.output_actual(cell), _cap.cell_capacity_active[cell],
			"INV-043：output_actual 不得超过 capacity_active")


## INV-045（并列时按 plan(0) < capacity(1) < labor(2) < energy(3) < materials(4) 取序号最小者）。
## 契约：docs/12 §5.3「严格小于才替换」。取整后并列是整数刻度下的常态，不是边角情形。
func test_u_binding_tie_breaks_to_lowest_index() -> void:
	# 场景 A：plan 与 capacity 并列最紧 ⇒ 必须判 plan(0)
	var cell: int = JWIds.idx_cell(JWUnits.Region.BEIYUAN, MANU)     # 0*4+1 == 1
	_sec.f_output_plan[cell] = 500_000
	_cap.cell_capacity_active[cell] = 500_000
	_io.labor_coeff[JWIds.idx_emp(cell, JWUnits.Skill.MID)] = 1_000
	_lab.cell_employment[JWIds.idx_emp(cell, JWUnits.Skill.MID)] = 900   # bound_labor == 900 000

	eq_int(_sec.solve_output(cell, _cap, _lab, _inv, _io), JWResult.OK,
			"solve_output 在并列场景 A 不得返回故障码")
	eq_int(_sec.output_actual(cell), 500_000, "并列场景 A 的最小候选是 500 000")
	eq_int(_sec.binding_code(cell), B_PLAN,
			"plan 与 capacity 并列为 500 000 时必须取序号最小的 plan(0)（INV-045）")

	# 场景 B：capacity 与 labor 并列最紧、plan 更大 ⇒ 必须判 capacity(1)
	_setup()
	_sec.f_output_plan[cell] = 900_000
	_cap.cell_capacity_active[cell] = 500_000
	_io.labor_coeff[JWIds.idx_emp(cell, JWUnits.Skill.MID)] = 1_000
	_lab.cell_employment[JWIds.idx_emp(cell, JWUnits.Skill.MID)] = 500   # bound_labor == 500 000

	eq_int(_sec.solve_output(cell, _cap, _lab, _inv, _io), JWResult.OK,
			"solve_output 在并列场景 B 不得返回故障码")
	eq_int(_sec.f_bound_labor[cell], 500_000,
			"bound_labor 应为 floor(500 人 × 1e6 / 1000) == 500 000，与 capacity 并列")
	eq_int(_sec.binding_code(cell), B_CAPACITY,
			"capacity 与 labor 并列为 500 000 时必须取序号较小的 capacity(1)（INV-045）")

	# 场景 C：并列发生在固定序的末端 energy(3) 与 materials(4) ⇒ 必须取 energy(3)
	_setup()
	_sec.f_output_plan[cell] = 900_000
	_cap.cell_capacity_active[cell] = 900_000
	_io.io_coeff[JWIds.idx_io(ENERGY, MANU)] = 2_000
	_io.energy_coeff[cell] = 2_000
	_sec.f_energy_allocated[cell] = 1_000                            # floor(1000 × 1e6 / 2000) == 500 000
	_io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 500
	_inv.inv_input[JWIds.idx_inv(cell, AGRI)] = 250                  # floor(250 × 1e6 / 500) == 500 000

	eq_int(_sec.solve_output(cell, _cap, _lab, _inv, _io), JWResult.OK,
			"solve_output 在并列场景 C 不得返回故障码")
	eq_int(_sec.f_bound_energy[cell], 500_000, "bound_energy 应为 floor(1000 × 1e6 / 2000) == 500 000")
	eq_int(_sec.f_bound_materials[cell], 500_000, "bound_materials 应为 floor(250 × 1e6 / 500) == 500 000")
	eq_int(_sec.binding_code(cell), B_ENERGY,
			"energy(3) 与 materials(4) 并列时必须取 energy(3)；固定序在末端同样生效（INV-045）")


## INV-043 与 docs/12 §5.3 第 2 项：维护欠账按 ppm 压低产能候选，且必须走 mul_ppm（R-SCALE-01）。
func test_u_maintenance_backlog_scales_capacity_bound() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.XILING, MANU)      # 3*4+1 == 13
	_sec.f_output_plan[cell] = 900_000
	_cap.cell_capacity_active[cell] = 1_000_000
	_cap.cell_maint_backlog[cell] = 250_000                          # 25% 欠账

	eq_int(_sec.solve_output(cell, _cap, _lab, _inv, _io), JWResult.OK,
			"solve_output 在只有计划与产能两项候选时不得返回故障码")
	eq_int(_sec.f_bound_capacity[cell], JWMath.mul_ppm(1_000_000, 750_000),
			"bound_capacity 应为 mul_ppm(1 000 000, 1e6 − 250 000) == 750 000（docs/12 §5.3 第 2 项）")
	eq_int(_sec.output_actual(cell), 750_000,
			"min(计划 900 000, 打折后产能 750 000) == 750 000")
	eq_int(_sec.binding_code(cell), B_CAPACITY, "被打折的产能成为最紧约束，binding_code == 1")


# ── 2 系数为零跳过，而不是除零，也不是 max(c, 1) ─────────────────────────────

## INV-044（系数为 0 的约束不产生候选值；禁止除零，禁止 max(c,1)）。
## 契约：docs/12 §5.3 第 3 项、docs/31 ADV-J03。
## 判据：三档劳动系数全为 0 且在岗 0 人。正确实现跳过该约束 ⇒ bound_labor 保持 SENTINEL；
## 若实现写成 `avail / max(c, 1)`，候选值会变成 floor(0 × 1e6 / 1) == 0，产量被假约束压成 0。
func test_u_zero_labor_coefficient_is_skipped_not_divided() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.XILING, SERVICES)  # 3*4+3 == 15
	_sec.f_output_plan[cell] = 400_000
	_cap.cell_capacity_active[cell] = 600_000
	# 三个技能档的系数与在岗人数都是 0；能源行与材料行也全 0 ⇒ 只剩计划与产能两个候选。

	eq_int(_sec.solve_output(cell, _cap, _lab, _inv, _io), JWResult.OK,
			"全部劳动系数为 0 时 solve_output 必须正常返回，不得因除零而失败")
	eq_int(JWResult.pending_code(), JWResult.OK,
			"系数为 0 必须走 continue，绝不能触发 DIV_ZERO(91)（INV-044）")
	eq_int(_sec.f_bound_labor[cell], JWUnits.SENTINEL,
			"全部技能档系数为 0 ⇒ bound_labor 保持 SENTINEL == QTY_MAX（docs/12 §5.3）")
	eq_int(_sec.output_actual(cell), 400_000,
			"该 cell 不受劳动约束，产量应为 min(计划 400 000, 产能 600 000)")
	eq_int(_sec.binding_code(cell), B_PLAN,
			"最紧项是计划；若判成 labor(2) 说明零系数被当成了 0 候选（max(c,1) 的典型症状）")


## INV-044（材料侧的零系数跳过）。契约：docs/12 §5.3 第 5 项。
## 两个判据合并：
##   A 组：零系数的部门库存为 0 —— max(a,1) 会造出候选 0，把产量压成 0；
##   B 组：零系数的部门库存为正 —— max(a,1) 会造出巨大的假候选（9e11 < SENTINEL），
##         使 bound_materials 不再是 SENTINEL，诊断信息随之作废。
func test_u_zero_material_coefficient_is_skipped_not_divided() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.HAIJIA, MANU)      # 2*4+1 == 9

	# A 组：agri 与 services 系数为 0 且库存为 0，只有 manu→manu 真正起作用
	_sec.f_output_plan[cell] = 450_000
	_cap.cell_capacity_active[cell] = 600_000
	_io.io_coeff[JWIds.idx_io(MANU, MANU)] = 400
	_inv.inv_input[JWIds.idx_inv(cell, MANU)] = 200_000              # floor(2e5 × 1e6 / 400) == 500 000

	eq_int(_sec.solve_output(cell, _cap, _lab, _inv, _io), JWResult.OK,
			"零系数的投入部门必须被跳过，不得返回故障码")
	eq_int(JWResult.pending_code(), JWResult.OK,
			"材料系数为 0 必须 continue，绝不能触发 DIV_ZERO(91)（INV-044）")
	eq_int(_sec.f_bound_materials[cell], _bound_from(200_000, 400),
			"bound_materials 只应来自唯一的非零系数行：floor(200 000 × 1e6 / 400) == 500 000")
	eq_int(_sec.output_actual(cell), 450_000,
			"候选为 [450000, 600000, SENTINEL, SENTINEL, 500000]，最小值是计划 450 000")
	eq_int(_sec.binding_code(cell), B_PLAN,
			"若判成 materials(4) 且产量为 0，说明库存为 0 的零系数行造出了假候选 0")

	# B 组：四个投入部门系数全为 0，但库存为正
	_setup()
	_sec.f_output_plan[cell] = 300_000
	_cap.cell_capacity_active[cell] = 600_000
	_inv.inv_input[JWIds.idx_inv(cell, AGRI)] = 900_000

	eq_int(_sec.solve_output(cell, _cap, _lab, _inv, _io), JWResult.OK,
			"全部材料系数为 0 时 solve_output 必须正常返回")
	eq_int(_sec.f_bound_materials[cell], JWUnits.SENTINEL,
			"全部投入系数为 0 ⇒ bound_materials 必须是 SENTINEL；出现 9e11 即证明用了 max(a,1)")
	eq_int(_sec.output_actual(cell), 300_000, "产量应为 min(计划 300 000, 产能 600 000)")


## INV-044 与 INV-052：能源 cell **跳过** bound_energy（自供，自用量从产出净出），
## 非能源 cell 的能源系数为 0 时同样跳过。契约：docs/12 §5.2/§5.3 第 4 项、docs/31 ADV-D07。
## 判据：能源 cell 的 energy_allocated 恒为 0；若实现没跳过，bound_energy 会算成 0，
## 能源部门永远产不出电——这正是「能源自举」攻击要暴露的自指缺陷的反面。
func test_u_energy_bound_skipped_for_energy_cell_and_zero_coefficient() -> void:
	# A 组：能源 cell 自身。a(energy→energy) == 100 000（10% 自用，INV-052 要求 < 1e6）
	var e_cell: int = JWIds.idx_cell(JWUnits.Region.BEIYUAN, ENERGY) # 0*4+2 == 2
	_sec.f_output_plan[e_cell] = 300_000
	_cap.cell_capacity_active[e_cell] = 400_000
	_io.io_coeff[JWIds.idx_io(ENERGY, ENERGY)] = 100_000
	_io.energy_coeff[e_cell] = 100_000
	_sec.f_energy_allocated[e_cell] = 0                              # 能源 cell 不从电网取电

	eq_int(_sec.solve_output(e_cell, _cap, _lab, _inv, _io), JWResult.OK,
			"能源 cell 的 solve_output 不得返回故障码")
	eq_int(_sec.f_bound_energy[e_cell], JWUnits.SENTINEL,
			"能源 cell 必须跳过能源约束，bound_energy == SENTINEL（docs/12 §5.2）")
	eq_int(_sec.output_actual(e_cell), 300_000,
			"能源 cell 的产量应为 min(计划 300 000, 产能 400 000)，不受自身用电约束")
	ne_int(_sec.binding_code(e_cell), B_ENERGY,
			"能源 cell 的 binding_code 不得是 energy(3)（INV-044，docs/31 ADV-D07 的断言）")

	# B 组：非能源 cell 且 a_e == 0（例如不耗电的工序），获配电力为 0
	var a_cell: int = JWIds.idx_cell(JWUnits.Region.BEIYUAN, AGRI)   # 0*4+0 == 0
	_sec.f_output_plan[a_cell] = 250_000
	_cap.cell_capacity_active[a_cell] = 700_000
	_sec.f_energy_allocated[a_cell] = 0

	eq_int(_sec.solve_output(a_cell, _cap, _lab, _inv, _io), JWResult.OK,
			"能源系数为 0 的 cell 的 solve_output 不得返回故障码")
	eq_int(_sec.f_bound_energy[a_cell], JWUnits.SENTINEL,
			"a_e == 0 ⇒ bound_energy == SENTINEL，不得写成 floor(0 × 1e6 / max(0,1)) == 0")
	eq_int(_sec.output_actual(a_cell), 250_000,
			"不耗电的 cell 产量应为 min(计划 250 000, 产能 700 000)")


## INV-044 的**反向判据**：零系数跳过，但「系数为正而可用量为 0」是真约束，必须把产量压到 0。
## 契约：docs/12 §5.3 第 3 项（`if c == 0: continue`，判据是**系数**不是可用量）、
## docs/31 §989「招不到人时 binding_code == labor，而不是就业数照填、产量照出」。
## 若实现把判据写成 `if avail == 0: continue`，本用例会让产量从 0 变成 400 000 000，
## 等于凭空造出一批没有工人的产出。
func test_u_zero_availability_with_positive_coefficient_still_binds() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.XILING, MANU)      # 3*4+1 == 13
	_sec.f_output_plan[cell] = 400_000_000
	_cap.cell_capacity_active[cell] = 600_000_000
	# 低技能档系数为 0（应跳过）；中技能档系数为正但一个人也没招到（不得跳过）。
	_io.labor_coeff[JWIds.idx_emp(cell, JWUnits.Skill.LOW)] = 0
	_lab.cell_employment[JWIds.idx_emp(cell, JWUnits.Skill.LOW)] = 0
	_io.labor_coeff[JWIds.idx_emp(cell, JWUnits.Skill.MID)] = 1_000
	_lab.cell_employment[JWIds.idx_emp(cell, JWUnits.Skill.MID)] = 0

	eq_int(_sec.solve_output(cell, _cap, _lab, _inv, _io), JWResult.OK,
			"可用量为 0 是业务结果，不是故障（docs/17 §1.3）")
	eq_int(_sec.f_bound_labor[cell], 0,
			"中技能档系数为正、在岗 0 人 ⇒ bound_labor == floor(0 × 1e6 / 1000) == 0")
	eq_int(_sec.output_actual(cell), 0, "招不到人 ⇒ 产量为 0（INV-043）")
	eq_int(_sec.binding_code(cell), B_LABOR,
			"最紧项必须是 labor(2)；若判成 plan 且产量为 4e8，说明零可用量被当成了零系数跳过")


## docs/12 §5.3 的溢出复核 + 两类候选的封顶差异（**契约本身不对称，本用例把差异钉住**）：
##   劳动与材料写成 `bound = SENTINEL; bound = min(bound, mul_div_floor(...))` ⇒ 真值超限被封顶在 SENTINEL；
##   能源写成三元式**直接赋值**，没有与 SENTINEL 取 min ⇒ 真值 1e18 原样落进 μQ_s 字段。
## 这与 INV-007「|数量| ≤ QTY_MAX == 1e12，每次写入即检」冲突，已登记为待裁定项；
## 在裁定前，本用例照 docs/12 §5.3 的字面公式断言（契约优先），一旦裁定改为封顶，本用例应随之翻转。
## 契约：docs/12 §5.3（真值上界 1e18 < 9.22e18 的溢出复核）、INV-007、裁定 R-SCALE-01（mul_div_floor）。
func test_u_bounds_at_contract_ceilings_stay_capped_and_do_not_overflow() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.HAIJIA, MANU)      # 2*4+1 == 9
	_sec.f_output_plan[cell] = 1_000_000_000
	_cap.cell_capacity_active[cell] = JWUnits.QTY_MAX

	# 材料：库存取契约上界 QTY_MAX，系数取最小合法值 1 ⇒ 真值 1e12 × 1e6 / 1 == 1e18
	_io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 1
	_inv.inv_input[JWIds.idx_inv(cell, AGRI)] = JWUnits.QTY_MAX
	# 能源：同样取上界
	_io.io_coeff[JWIds.idx_io(ENERGY, MANU)] = 1
	_io.energy_coeff[cell] = 1
	_sec.f_energy_allocated[cell] = JWUnits.QTY_MAX

	eq_int(_sec.solve_output(cell, _cap, _lab, _inv, _io), JWResult.OK,
			"契约上界处 solve_output 必须正常返回")
	eq_int(JWResult.pending_code(), JWResult.OK,
			"真值上界 1e18 < INT64_MAX，全程不得登记 INT_OVERFLOW(90)（docs/12 §5.3 的溢出复核）")
	eq_int(_sec.f_bound_materials[cell], JWUnits.SENTINEL,
			"材料候选由 SENTINEL 起步取 min ⇒ 真值 1e18 被封顶在 SENTINEL == QTY_MAX == 1e12")
	eq_int(_sec.f_bound_energy[cell], JWMath.mul_div_floor(JWUnits.QTY_MAX, JWUnits.PPM, 1),
			"能源候选按 docs/12 §5.3 的字面三元式直接赋值 == 1e18（无 SENTINEL 封顶）；"
			+ "该值写进 μQ_s 字段与 INV-007 的 QTY_MAX 上界冲突，待裁定")
	eq_int(_sec.output_actual(cell), 1_000_000_000,
			"无论候选封不封顶，最紧项仍是计划 1 000 000 000（INV-043）")
	le_int(_sec.output_actual(cell), JWUnits.QTY_MAX,
			"INV-007：实际产量本身绝不得超过 QTY_MAX == 1e12")


## INV-046 的端到端链条：非整除系数下「floor 定候选 → ceil 反算消耗」必须恰好不透支。
## 契约：docs/12 §5.3 + §5.4 的整数引理 T-U-CEIL-SAFE。
## 若候选值误用 ceil（3 333 323），随后的消耗就会要 1 000 001 μQ_agri 而库存只有 1 000 000，
## 压测中会随机冒出 Fault.NEGATIVE_INVENTORY —— 本用例把这条链固定住。
func test_u_floor_bound_then_ceil_consume_never_overdraws() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.ZHONGZHOU, MANU)   # 1*4+1 == 5
	var slot: int = JWIds.idx_inv(cell, AGRI)
	_sec.f_output_plan[cell] = JWUnits.QTY_MAX                       # 让材料成为唯一紧约束
	_cap.cell_capacity_active[cell] = JWUnits.QTY_MAX
	_io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 300_001                 # 故意不整除
	_inv.inv_input[slot] = 1_000_000
	_inv.begin_production()

	eq_int(_sec.solve_output(cell, _cap, _lab, _inv, _io), JWResult.OK, "solve_output 不得返回故障码")
	eq_int(_sec.f_bound_materials[cell], 3_333_322,
			"bound_materials 必须向下取整：floor(1 000 000 × 1e6 / 300 001) == 3 333 322")
	eq_int(_sec.output_actual(cell), 3_333_322, "材料是唯一紧约束，产量等于该候选值")
	eq_int(_sec.binding_code(cell), B_MATERIALS, "binding_code 必须指向材料(4)")

	var q: int = _sec.output_actual(cell)
	eq_int(_inv.consume_inputs(cell, q, _io), JWResult.OK,
			"整数引理保证按该产量 ceil 反算的消耗不会透支库存（INV-046）")
	eq_int(_inv.f_consumed[slot], 1_000_000,
			"消耗 == ceil(3 333 322 × 300 001 / 1e6) == 1 000 000，恰好用尽库存")
	ge_int(_inv.inv_input[slot], 0, "INV-048：消耗后库存必须 ≥ 0")


# ── 3 电力当期使用，不入库存 ────────────────────────────────────────────────

## INV-049（storable == 0 的部门期末库存恒为 0）、INV-051（电力当期使用，不入任何库存）。
## 契约：docs/12 §5.4 的 store_output 分支、docs/17 §4.17、docs/31 ADV-D04「把电力存起来」。
func test_u_nonstorable_output_never_enters_inventory() -> void:
	var e_cell: int = JWIds.idx_cell(JWUnits.Region.ZHONGZHOU, ENERGY)   # 1*4+2 == 6
	var s_cell: int = JWIds.idx_cell(JWUnits.Region.ZHONGZHOU, SERVICES) # 1*4+3 == 7
	var m_cell: int = JWIds.idx_cell(JWUnits.Region.ZHONGZHOU, MANU)     # 1*4+1 == 5

	eq_int(_inv.store_output(e_cell, 777_000, _io), JWResult.OK,
			"能源产出入库调用本身不是故障：它只是不写库存")
	eq_int(_inv.store_output(s_cell, 555_000, _io), JWResult.OK,
			"服务产出入库调用本身不是故障：它只是不写库存")
	eq_int(_inv.store_output(m_cell, 333_000, _io), JWResult.OK,
			"可库存部门的入库必须成功")

	eq_int(_inv.inv_output[e_cell], 0,
			"storable[energy] == 0 ⇒ 能源期末库存恒为 0（INV-049 / INV-051，ADV-D04）")
	eq_int(_inv.inv_output[s_cell], 0,
			"storable[services] == 0 ⇒ 服务期末库存恒为 0（INV-049）")
	eq_int(_inv.inv_output[m_cell], 333_000,
			"storable[manu] == 1 ⇒ 成品入库，期末库存 == 本季产量 333 000")


## INV-051（Σ 配给 ≤ min(能源可交付量, 电网容量)；超出电网的部分作废，不入库存）、INV-052。
## 契约：docs/12 §5.2 的三行公式。
## 期望值推导（四个地区各一个能源 cell，参数相同）：
##   Q_e = min(计划 1 000 000, 产能 1 500 000, SENTINEL, SENTINEL) = 1 000 000 μQ_e
##   self_use = ceil(1 000 000 × 200 000 / 1e6) = 200 000 μQ_e
##   deliver  = 800 000 μQ_e
##   electricity_supply[r] = min(deliver, grid_capacity[r])
func test_u_electricity_supply_capped_by_grid_and_not_stored() -> void:
	_cap.grid_capacity = PackedInt64Array([500_000, 2_000_000, 2_000_000, 2_000_000])
	_io.io_coeff[JWIds.idx_io(ENERGY, ENERGY)] = 200_000

	for r: int in JWUnits.R:
		var cell: int = JWIds.idx_cell(r, ENERGY)
		_sec.f_output_plan[cell] = 1_000_000
		_cap.cell_capacity_active[cell] = 1_500_000
		_io.energy_coeff[cell] = 200_000

	eq_int(_sec.settle_energy(_cap, _inv, _io, _lab, _params), JWResult.OK,
			"settle_energy 在合法内容包下不得返回故障码")

	eq_int(_sec.f_elec_supply[0], 500_000,
			"北原电网容量 500 000 < 可交付 800 000 ⇒ 可供电力被电网截到 500 000（docs/12 §5.2）")
	eq_int(_sec.f_elec_supply[1], 800_000,
			"中州电网充裕 ⇒ 可供电力 == Q_e 1 000 000 − 自用 ceil(20%) 200 000 == 800 000")
	eq_int(_sec.f_elec_supply[2], 800_000, "海岬同上：可交付 800 000 未被电网截断")
	eq_int(_sec.f_elec_supply[3], 800_000, "西岭同上：可交付 800 000 未被电网截断")

	var alloc_sum: int = 0
	var supply_sum: int = 0
	for r: int in JWUnits.R:
		supply_sum += _sec.f_elec_supply[r]
		eq_int(_inv.inv_output[JWIds.idx_cell(r, ENERGY)], 0,
				"INV-051：电力当期使用，任何情况下都不得进入库存")
	for c: int in JWUnits.CELL:
		alloc_sum += _sec.f_energy_allocated[c]
	le_int(alloc_sum, supply_sum,
			"INV-051：Σ 配给不得超过 Σ min(可交付, 电网容量)；本例需求为 0 ⇒ 配给应为 0")


## INV-050（可库存中间投入只来自期初库存；本季购入补的是下季可用库存）。
## 契约：docs/12 §5.1 的「显式的离散化简化」、docs/30 T-U-A-17 `test_u_no_same_quarter_chain`、
## docs/31 ADV-D05「同季链条造货」。
## 判据：上游 agri cell 本季满产，下游 manu cell 的 agri 期初库存为 0。
## 若同季链条被打通，下游会产出 400 000 000 而不是 0——后果不只是造货，
## 而是结算结果依赖部门遍历顺序，直接摧毁可重放性。
func test_u_no_same_quarter_chain() -> void:
	var up: int = JWIds.idx_cell(JWUnits.Region.ZHONGZHOU, AGRI)     # 1*4+0 == 4
	var down: int = JWIds.idx_cell(JWUnits.Region.ZHONGZHOU, MANU)   # 1*4+1 == 5

	_sec.f_output_plan[up] = 500_000_000
	_cap.cell_capacity_active[up] = 500_000_000

	_sec.f_output_plan[down] = 400_000_000
	_cap.cell_capacity_active[down] = 600_000_000
	_io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 500
	_inv.inv_input[JWIds.idx_inv(down, AGRI)] = 0                    # 期初一粒不剩

	_inv.begin_production()
	eq_int(_sec.settle_production(_cap, _lab, _inv, _io), JWResult.OK,
			"settle_production 在库存为 0 时不得返回故障码（缺料是业务结果，不是故障）")

	eq_int(_sec.output_actual(up), 500_000_000, "上游 agri 本季确实满产 500 000 000")
	eq_int(_inv.inv_output[up], 500_000_000, "上游产出入库（storable[agri] == 1）")
	eq_int(_sec.f_bound_materials[down], 0,
			"下游的 agri 期初库存为 0 ⇒ bound_materials == 0（本季产出本季不可用，INV-050）")
	eq_int(_sec.output_actual(down), 0,
			"下游本季产量必须是 0；出现 400 000 000 即同季生产链被打通（ADV-D05）")
	eq_int(_sec.binding_code(down), B_MATERIALS, "下游的最紧项必须是材料(4)")


## INV-051（电力当期使用；未用作废记 energy_unused_uqs，不入任何库存）。
## 契约：docs/12 §5.4 的 `energy_unused = energy_allocated − energy_use`、docs/31 ADV-D04。
## 期望值推导：q_actual = min(计划 4e8, 产能 6e8, bound_energy 6e8) = 400 000 000 μQ_manu
##   energy_use = ceil(4e8 × 2000 / 1e6) = 800 000 μQ_e
##   energy_unused = 1 200 000 − 800 000 = 400 000 μQ_e（显式登记的浪费，不得静默丢弃）
func test_u_unused_electricity_is_registered_not_silently_dropped() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.ZHONGZHOU, MANU)   # 1*4+1 == 5
	_sec.f_output_plan[cell] = 400_000_000
	_cap.cell_capacity_active[cell] = 600_000_000
	_io.io_coeff[JWIds.idx_io(ENERGY, MANU)] = 2_000
	_io.energy_coeff[cell] = 2_000
	_sec.f_energy_allocated[cell] = 1_200_000

	_inv.begin_production()
	eq_int(_sec.settle_production(_cap, _lab, _inv, _io), JWResult.OK,
			"settle_production 不得返回故障码")

	eq_int(_sec.output_actual(cell), 400_000_000, "产量 == min(4e8, 6e8, bound_energy 6e8)")
	eq_int(_sec.f_energy_unused[cell],
			1_200_000 - JWMath.ceil_div(JWMath.mul(400_000_000, 2_000), JWUnits.Q_SCALE),
			"作废电力 == 获配 1 200 000 − ceil(4e8 × 2000 / 1e6) 800 000 == 400 000（INV-051）")
	eq_int(_inv.inv_output[JWIds.idx_cell(JWUnits.Region.ZHONGZHOU, ENERGY)], 0,
			"未用电力必须作废，绝不得转成任何库存（ADV-D04）")


# ── 4 实际消耗用 ceil，且不透支 ─────────────────────────────────────────────

## INV-046（T-U-CEIL-SAFE 整数引理：q_actual ≤ floor(A×1e6/c) ⇒ ceil(q_actual×c/1e6) ≤ A）。
## 契约：docs/12 §5.4。
## 期望值推导（取一组能区分 floor 与 ceil、且恰好顶到库存上界的病态系数）：
##   a = 300 001 μQ_agri/Q_manu，库存 A = 1 000 000 μQ_agri
##   bound_materials = floor(1e6 × 1e6 / 300 001) = 3 333 322 μQ_manu
##   use = ceil(3 333 322 × 300 001 / 1e6) = ceil(999 999.933322 …) = 1 000 000 == A（恰好用尽）
##   若实现误用 floor，use 会是 999 999，凭空少耗 1 μQ —— 正是「少耗料多出产」的入口。
func test_u_consume_inputs_uses_ceil_and_never_overdraws() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.HAIJIA, MANU)      # 2*4+1 == 9
	var slot: int = JWIds.idx_inv(cell, AGRI)
	var a: int = 300_001
	var avail: int = 1_000_000

	_io.io_coeff[JWIds.idx_io(AGRI, MANU)] = a
	_inv.inv_input[slot] = avail
	_inv.begin_production()

	var q: int = _bound_from(avail, a)
	eq_int(q, 3_333_322, "bound_materials == floor(1 000 000 × 1e6 / 300 001) == 3 333 322")

	# 独立复算：ceil 的数学真值（mul 在此不溢出：3.3e6 × 3e5 ≈ 1e12）
	var expect_use: int = JWMath.ceil_div(JWMath.mul(q, a), JWUnits.Q_SCALE)
	eq_int(expect_use, avail, "整数引理要求 ceil 恰好等于可用量 1 000 000，不多也不少")

	eq_int(_inv.consume_inputs(cell, q, _io), JWResult.OK,
			"q_actual 等于 bound_materials 时消耗必须成功（INV-046 的整数引理保证不透支）")
	eq_int(_inv.f_consumed[slot], expect_use,
			"消耗量必须是 ceil(q × a / 1e6) == 1 000 000；出现 999 999 即说明用了 floor")
	eq_int(_inv.inv_input[slot], 0, "库存被恰好用尽，期末为 0")
	ge_int(_inv.inv_input[slot], 0, "INV-048：任何库存字段每次写入后必须 ≥ 0")


## INV-048（不得无提示负库存）、INV-046、docs/31 ADV-D02「制造负库存」。
## 判据：把 q_actual 抬高 1 个 μQ_manu 越过 bound_materials，消耗量变成 1 000 001 > 库存 1 000 000。
## 契约要求登记 Fault.NEGATIVE_INVENTORY(30) 并保留现场，**禁止静默改账**（负库存或悄悄夹到 0 都算失败）。
func test_u_consume_inputs_rejects_overdraw_instead_of_going_negative() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.HAIJIA, MANU)
	var slot: int = JWIds.idx_inv(cell, AGRI)
	var a: int = 300_001
	var avail: int = 1_000_000

	_io.io_coeff[JWIds.idx_io(AGRI, MANU)] = a
	_inv.inv_input[slot] = avail
	_inv.begin_production()

	var q_over: int = _bound_from(avail, a) + 1                      # 3 333 323，越过上界 1 个单位
	eq_int(JWMath.ceil_div(JWMath.mul(q_over, a), JWUnits.Q_SCALE), 1_000_001,
			"越界 1 个单位后应耗 ceil(3 333 323 × 300 001 / 1e6) == 1 000 001 > 库存 1 000 000")

	var rc: int = _inv.consume_inputs(cell, q_over, _io)
	eq_int(rc, JWResult.Fault.NEGATIVE_INVENTORY,
			"透支必须返回 Fault.NEGATIVE_INVENTORY(30)，说明 q_actual 推导有误（docs/12 §5.9）")
	ge_int(_inv.inv_input[slot], 0,
			"INV-048：无论如何库存不得为负，一刻也不行（ADV-D02）")


## INV-044（消耗侧的零系数同样必须跳过，不得除零、不得凭空扣料）。契约：docs/12 §5.4。
func test_u_consume_inputs_skips_zero_coefficient() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.XILING, MANU)      # 3*4+1 == 13
	var slot: int = JWIds.idx_inv(cell, AGRI)
	_io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 0
	_inv.inv_input[slot] = 12_345
	_inv.begin_production()

	eq_int(_inv.consume_inputs(cell, 900_000, _io), JWResult.OK,
			"系数为 0 的投入部门必须被跳过，不得返回故障码")
	eq_int(JWResult.pending_code(), JWResult.OK,
			"消耗反算时系数为 0 必须 continue，绝不能触发 DIV_ZERO(91)（INV-044）")
	eq_int(_inv.f_consumed[slot], 0, "系数为 0 ⇒ 本季不耗用该投入，消耗登记必须是 0")
	eq_int(_inv.inv_input[slot], 12_345, "系数为 0 ⇒ 库存必须原封不动")


# ── 5 库存恒等式 ────────────────────────────────────────────────────────────

## INV-047（逐 cell 逐品种：期末 == 期初 + 生产 + 购入 − 售出 − 生产耗用 − 损耗）、
## INV-053（损耗显式登记，不允许用「盘点差异」吸收）。
## 契约：docs/12 §5.8、docs/30 T-U-A-13、docs/31 ADV-D06。
## 成品侧期望值推导（μQ_manu）：
##   期初 1 000 000 + 生产 500 000 − 售出 400 000 = 1 100 000
##   损耗 = mul_ppm(1 100 000, 50 000 ppm) = 55 000
##   期末 = 1 045 000
func test_u_output_inventory_identity_holds() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.BEIYUAN, MANU)     # 0*4+1 == 1
	_io.spoilage_ppm[MANU] = 50_000                                  # 5%/季

	_inv.inv_output[cell] = 1_000_000
	_inv.begin_production()

	eq_int(_inv.store_output(cell, 500_000, _io), JWResult.OK, "可库存部门的成品入库必须成功")
	eq_int(_inv.inv_output[cell], 1_500_000, "入库后库存 == 1 000 000 + 500 000")

	# 模拟本季向居民售出 400 000（实物双边：卖方库存减少量精确等于成交量，INV-059）。
	# 市场侧同步登记，使 INV-059（Σ 成交 + Σ 未满足 == Σ 需求，Σ 成交 ≤ 供给）也自洽。
	_inv.m_supply[MANU] = 1_500_000
	_inv.m_demand[JWIds.idx_market(MANU, JWUnits.BuyerClass.HOUSEHOLD)] = 400_000
	_inv.m_traded[JWIds.idx_market(MANU, JWUnits.BuyerClass.HOUSEHOLD)] = 400_000
	_inv.f_sold[cell] = 400_000
	_inv.inv_output[cell] -= 400_000

	eq_int(_inv.apply_spoilage(_io), JWResult.OK, "损耗结转不得返回故障码")
	eq_int(_inv.f_spoilage_out[cell], JWMath.mul_ppm(1_100_000, 50_000),
			"损耗 == mul_ppm(售后库存 1 100 000, 50 000 ppm) == 55 000，必须显式登记（INV-053）")
	eq_int(_inv.inv_output[cell], 1_045_000,
			"期末 == 1 000 000 + 500 000 − 400 000 − 55 000 == 1 045 000（INV-047）")

	# 独立复算残差：断言先由测试自己算一遍，再交给被测的恒等式检查，
	# 这样失败时能区分「我的算术错了」与「实现的恒等式检查错了」。
	var residual: int = _inv.inv_output[cell] - (
			1_000_000 + 500_000 + 0 - _inv.f_sold[cell] - 0 - _inv.f_spoilage_out[cell])
	eq_int(residual, 0, "测试自算残差：期末 − (期初 + 生产 + 购入 − 售出 − 耗用 − 损耗) 必须为 0")

	var produced: PackedInt64Array = _zeros(JWUnits.CELL)
	produced[cell] = 500_000
	eq_int(_inv.check_stock_identity(produced), JWResult.OK,
			"六项齐全且残差为 0 时 check_stock_identity 必须返回 OK（INV-047，容差 0）")


## INV-047 的投入品侧（逐 cell 逐品种同一条恒等式）、INV-050（本季购入补的是**下季**可用库存）。
## 契约：docs/12 §5.8、docs/30 T-U-A-13。
## 期望值推导（买方 manu cell 的 agri 投入，μQ_agri）：
##   期初 1 000 000 − 生产耗用 200 000 + 购入 300 000 = 1 100 000
##   投入品损耗 = mul_ppm(1 100 000, 10 000 ppm) = 11 000
##   期末 = 1 089 000
## 卖方 agri cell 同步记账（INV-059：卖方库存减少量精确等于成交量）：
##   期初 500 000 − 售出 300 000 = 200 000，损耗 2 000 ⇒ 期末 198 000
func test_u_input_inventory_identity_holds() -> void:
	var buyer: int = JWIds.idx_cell(JWUnits.Region.BEIYUAN, MANU)    # 0*4+1 == 1
	var seller: int = JWIds.idx_cell(JWUnits.Region.BEIYUAN, AGRI)   # 0*4+0 == 0
	var slot: int = JWIds.idx_inv(buyer, AGRI)
	_io.spoilage_ppm[AGRI] = 10_000                                  # 1%/季
	_io.io_coeff[JWIds.idx_io(AGRI, MANU)] = 200                     # 200 μQ_agri / Q_manu

	_inv.inv_input[slot] = 1_000_000
	_inv.inv_output[seller] = 500_000
	_inv.begin_production()

	# q_actual = 1 000 000 000 μQ_manu ⇒ use = ceil(1e9 × 200 / 1e6) = 200 000 μQ_agri
	eq_int(_inv.consume_inputs(buyer, 1_000_000_000, _io), JWResult.OK, "耗用在库存充足时必须成功")
	eq_int(_inv.f_consumed[slot], 200_000,
			"耗用 == ceil(1 000 000 000 × 200 / 1e6) == 200 000 μQ_agri")
	eq_int(_inv.inv_input[slot], 800_000, "耗用后库存 == 1 000 000 − 200 000")

	# 模拟卖方 → 买方的一笔企业投入成交 300 000 μQ_agri，市场侧同步登记（INV-059）
	_inv.m_supply[AGRI] = 500_000
	_inv.m_demand[JWIds.idx_market(AGRI, JWUnits.BuyerClass.FIRM_INPUT)] = 300_000
	_inv.m_traded[JWIds.idx_market(AGRI, JWUnits.BuyerClass.FIRM_INPUT)] = 300_000
	_inv.f_sold[seller] = 300_000
	_inv.inv_output[seller] -= 300_000
	_inv.f_purchased[slot] = 300_000
	_inv.inv_input[slot] += 300_000

	eq_int(_inv.apply_spoilage(_io), JWResult.OK, "投入品损耗结转不得返回故障码")
	eq_int(_inv.f_spoilage_in[slot], JWMath.mul_ppm(1_100_000, 10_000),
			"投入品损耗 == mul_ppm(1 100 000, 10 000 ppm) == 11 000，必须显式登记（INV-053）")
	eq_int(_inv.inv_input[slot], 1_089_000,
			"买方期末 == 1 000 000 + 300 000 − 200 000 − 11 000 == 1 089 000（INV-047）")
	eq_int(_inv.inv_output[seller], 198_000,
			"卖方期末 == 500 000 − 300 000 − mul_ppm(200 000, 10 000 ppm) 2 000 == 198 000（INV-047）")

	var produced: PackedInt64Array = _zeros(JWUnits.CELL)
	eq_int(_inv.check_stock_identity(produced), JWResult.OK,
			"买卖双方六项齐全且各自残差为 0 时必须返回 OK（INV-047，容差 0）")


## INV-047 的**反向判据**：恒等式检查必须真的能抓到差额，而不是恒返回 OK。
## 契约：docs/12 §5.8「不允许用盘点差异吸收」、docs/17 §4.17（失败 → Fault.STOCK_IDENTITY）、
## docs/31 ADV-D06。这是本文件里唯一一个「制造缺陷」的用例：
## 若它变绿，说明 check_stock_identity 是个空壳，前两个恒等式用例的绿色也不作数。
func test_u_stock_identity_detects_injected_discrepancy() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.BEIYUAN, MANU)
	_inv.inv_output[cell] = 1_000_000
	_inv.begin_production()
	eq_int(_inv.store_output(cell, 500_000, _io), JWResult.OK, "入库必须成功")

	# 凭空多出 1 μQ_manu：六项流量都没有对应记录，正是「盘点差异」的形态。
	_inv.inv_output[cell] += 1

	var produced: PackedInt64Array = _zeros(JWUnits.CELL)
	produced[cell] = 500_000
	eq_int(_inv.check_stock_identity(produced), JWResult.Fault.STOCK_IDENTITY,
			"凭空多出的 1 μQ 必须被判 Fault.STOCK_IDENTITY(34)；返回 OK 即说明恒等式检查形同虚设")

	# 反方向：库存悄悄少了 1 μQ 而六项流量里没有任何一项对应——正是「用损耗吸收盘点差异」的形态。
	_setup()
	_inv.inv_output[cell] = 1_000_000
	_inv.begin_production()
	eq_int(_inv.store_output(cell, 500_000, _io), JWResult.OK, "入库必须成功")
	_inv.inv_output[cell] -= 1

	var produced2: PackedInt64Array = _zeros(JWUnits.CELL)
	produced2[cell] = 500_000
	eq_int(_inv.check_stock_identity(produced2), JWResult.Fault.STOCK_IDENTITY,
			"凭空少掉的 1 μQ 同样必须被判 Fault.STOCK_IDENTITY(34)（INV-053：不得用盘点差异吸收）")


## INV-048（库存写入后 ≥ 0）与 docs/12 §5.8 的取整方向（`rounding: floor`）。
## 判据：库存 9 μQ、损耗率取 valid_range 上限 100 000 ppm ⇒ mul_ppm(9, 100 000) == 0（floor）。
## 若实现用 ceil 或四舍五入，会吃掉 1 μQ；在 20 季压测里这就是一条稳定的单向漏损，
## 而 docs/31 ADV-D06 正是要抓这种「方向对我有利就白得货」的偏置。
func test_u_spoilage_rounds_down_and_never_goes_negative() -> void:
	var cell: int = JWIds.idx_cell(JWUnits.Region.XILING, AGRI)      # 3*4+0 == 12
	var slot: int = JWIds.idx_inv(cell, MANU)
	_io.spoilage_ppm[AGRI] = 100_000                                 # 10%/季，valid_range 上限
	_io.spoilage_ppm[MANU] = 100_000

	_inv.inv_output[cell] = 9
	_inv.inv_input[slot] = 9
	_inv.begin_production()

	eq_int(_inv.apply_spoilage(_io), JWResult.OK, "损耗结转不得返回故障码")
	eq_int(_inv.f_spoilage_out[cell], 0,
			"mul_ppm(9, 100 000) == floor(0.9) == 0：不足 1 μQ 的损耗必须记 0，不得进位")
	eq_int(_inv.inv_output[cell], 9, "取整为 0 ⇒ 成品库存原封不动")
	eq_int(_inv.f_spoilage_in[slot], 0, "投入品损耗同方向：floor(0.9) == 0")
	eq_int(_inv.inv_input[slot], 9, "取整为 0 ⇒ 投入品库存原封不动")
	ge_int(_inv.inv_output[cell], 0, "INV-048：损耗写入后库存必须 ≥ 0")

	var produced: PackedInt64Array = _zeros(JWUnits.CELL)
	eq_int(_inv.check_stock_identity(produced), JWResult.OK,
			"损耗为 0 时六项恒等式同样必须精确成立（INV-047，容差 0）")


## INV-049 的收尾断言：不可库存部门在走完「入库 → 损耗结转」全程后期末库存仍恒为 0。
## 契约：docs/12 §5.4 末行与 §5.8、docs/31 ADV-D04。
func test_u_nonstorable_inventory_stays_zero_through_spoilage() -> void:
	var e_cell: int = JWIds.idx_cell(JWUnits.Region.HAIJIA, ENERGY)  # 2*4+2 == 10
	var s_cell: int = JWIds.idx_cell(JWUnits.Region.HAIJIA, SERVICES)# 2*4+3 == 11
	_io.spoilage_ppm[ENERGY] = 50_000
	_io.spoilage_ppm[SERVICES] = 50_000

	_inv.begin_production()
	eq_int(_inv.store_output(e_cell, 1_000_000, _io), JWResult.OK, "能源产出入库调用必须返回 OK")
	eq_int(_inv.store_output(s_cell, 1_000_000, _io), JWResult.OK, "服务产出入库调用必须返回 OK")
	eq_int(_inv.apply_spoilage(_io), JWResult.OK, "损耗结转不得返回故障码")

	eq_int(_inv.inv_output[e_cell], 0, "INV-049：energy 期末库存恒为 0")
	eq_int(_inv.inv_output[s_cell], 0, "INV-049：services 期末库存恒为 0")
	eq_int(_inv.f_spoilage_out[e_cell], 0, "库存恒为 0 ⇒ 不可库存部门不可能产生成品损耗")
	eq_int(_inv.f_spoilage_out[s_cell], 0, "同上：服务部门的成品损耗必须是 0")

	# S06 §6.2 取用的数量口径：不可库存部门的库存变动恒为 0，否则增加值会凭空多出一块。
	eq_int(_inv.d_inventory_output(e_cell), 0,
			"能源的库存变动必须恒为 0（期初 0、期末 0），不得给 S06 送进一笔假的存货增加")
	eq_int(_inv.d_inventory_output(s_cell), 0,
			"服务的库存变动必须恒为 0（期初 0、期末 0）")
