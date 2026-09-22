## 项目进度、完工与取消的契约测试（独立于实现，只依据契约编写）。
##
## 依据（冲突时上位者胜）：
##   docs/ref/plan_v1.0.txt §10「这张卡的验收测试」——三条：
##       ① 无施工能力时，付款不得直接制造完工进度
##       ② 第 8 季未交付齐全不得投运
##       ③ 新增容量下一季投入使用（§10「完工条件」行）
##   docs/18_rulings.md R-SCALE-01（1 U == 1 000 000 000 μU）
##   docs/12_simulation_contract.md §5.5（进度公式）、§7.1（完工）、§01.4（pending→active）、§02.7（取消）
##   docs/10_variable_dictionary.md §14.7 INV-087…INV-094
##   docs/30_quality_gates.md T-S-P04-PAY-NO-PROGRESS / T-S-P04-NO-EARLY-COMMISSION /
##       T-S-P04-FAIL-DELIVERY / T-S-D-07；docs/31_adversarial_tests.md ADV-F01 / ADV-F02 / ADV-F04 / ADV-F06
##
## **刻度提示**：docs/30 与 docs/31 的断言字面量（4_000_000、2_000_000、600_000 等）写于
## R-SCALE-01 之前，属于裁定文件点名的「约 200 处字符串正文里的旧刻度数字」。本文件一律按
## 新刻度 ×1000 取值：合同总额 4 U == 4_000_000_000 μU。
extends JWTest

# ── 夹具常量（全部取自计划书 §10 的 P04 卡，按 R-SCALE-01 换算） ────────────

## 海岬（docs/17 §2.1：0 北原 1 中州 2 海岬 3 西岭）
const R_HAIJIA: int = 2
## P04 电网可靠性升级 == 政策下标 3（P01..P12 → 0..11）
const P04: int = 3
## 计划书 §10：总成本 4 U，计划 8 季、每季 0.5 U
const PLANNED_Q: int = 8
const TOTAL_COST_UU: int = 4_000_000_000
const PER_QUARTER_UU: int = 500_000_000
## 计划书 §10：每季 0.2 U 进口设备 / 0.1 U 国产材料 / 0.2 U 施工服务
const LINE_EQUIPMENT_UU: int = 200_000_000
const LINE_MATERIAL_UU: int = 100_000_000
const LINE_CONSTRUCTION_UU: int = 200_000_000
## 三条支出分项的下标（docs/12 §04.4 的固定顺序）
const LINE_EQUIPMENT: int = 0
const LINE_MATERIAL: int = 1
const LINE_CONSTRUCTION: int = 2
## 计划书 §10：启用后每季 0.02 U 运行费
const OPEX_PER_Q_UU: int = 20_000_000
## 计划书 §10：额外 10 单位可用电力服务 == 10 × Q_SCALE μQ_energy/季
const CAPACITY_EFFECT_UQS: int = 10_000_000
## 计划书 §10「合同赔偿按剩余合同规则结算」；docs/30 T-S-D-07 用 300 000 ppm
const EXIT_COMPENSATION_PPM: int = 300_000

## 故意取不能被 PLANNED_Q 整除、也不能整除 PPM 的数：
## 这样 floor 与 ceil / 四舍五入的差别会在断言里暴露出来。
const REQ_CONSTRUCTION_UQS: int = 3_000_001
const REQ_EQUIPMENT_UQS: int = 2_000_003
## floor_div(3_000_001, 8) —— docs/12 §5.5 的 need_uqs
const NEED_CONSTRUCTION_PER_Q: int = 375_000
## floor_div(2_000_003, 8)
const NEED_EQUIPMENT_PER_Q: int = 250_000
## mul_div_floor(375_000, 1e6, 3_000_001)：3_000_001 × 124_999 == 374_997_124_999 ≤ 3.75e11
## < 3_000_001 × 125_000 == 375_000_125_000，故真值 floor 恰为 124_999
const DELTA_CONSTRUCTION_PPM: int = 124_999

## 施工份额上限；本测试自备参数值，不依赖内容包
const CONSTRUCTION_SHARE_CAP_PPM: int = 200_000
## 服务 cell 的实际产量：mul_ppm(5_000_000, 200_000) == 1_000_000 ≥ NEED_CONSTRUCTION_PER_Q
const SERVICES_OUTPUT_UQS: int = 5_000_000

## 开局给政府的现金与在建工程，用来让取消路径走「现金充足」分支
const GOV_CASH_SEED_UU: int = 10_000_000_000
const GOV_WIP_SEED_UU: int = 2_000_000_000

# ── 夹具对象 ───────────────────────────────────────────────────────────────

var accounts: JWAccount = null
var ledger: JWLedger = null
var capital: JWCapital = null
var world: JWWorldMarket = null
var treasury: JWTreasury = null
var defs: JWPolicyDef = null
var pq: JWProjectQueue = null
var comm: JWAssetCommissioning = null
var labor: JWLaborMarket = null
var params: PackedInt64Array = PackedInt64Array()
var entity_seq: int = 0


func before_each() -> void:
	# 静态故障登记是跨实例的；不清掉，上一个测试的故障会被算到本测试头上。
	JWResult.clear_pending()

	accounts = JWAccount.new()
	accounts.allocate()
	ledger = JWLedger.new(accounts)
	ledger.allocate()
	capital = JWCapital.new()
	capital.allocate()
	world = JWWorldMarket.new()
	world.allocate()
	treasury = JWTreasury.new()
	treasury.allocate()
	defs = JWPolicyDef.new()
	defs.allocate()
	pq = JWProjectQueue.new()
	pq.allocate()
	comm = JWAssetCommissioning.new()
	comm.allocate()
	labor = JWLaborMarket.new()
	labor.allocate()

	params.resize(JWUnits.PARAM_N)
	params.fill(0)
	params[JWUnits.Param.CONSTRUCTION_SHARE_CAP_PPM] = CONSTRUCTION_SHARE_CAP_PPM

	_load_p04_definition()
	_seed_region_and_world()
	_seed_gov_balances()
	entity_seq = 0


# ── 夹具装配（只写契约里声明过的公开成员） ─────────────────────────────────

## PackedInt64Array 是值语义，必须「取出—改—写回」，否则写入会落到临时副本上。
func _put(a: PackedInt64Array, i: int, v: int) -> PackedInt64Array:
	a[i] = v
	return a


## 把计划书 §10 的 P04 卡装进 JWPolicyDef（content.policy.* 是 LOAD 期数据）。
func _load_p04_definition() -> void:
	defs.planned_quarters = _put(defs.planned_quarters, P04, PLANNED_Q)
	defs.cost_per_quarter_uu = _put(defs.cost_per_quarter_uu, P04, PER_QUARTER_UU)
	# docs/11 §V-PD-03：`per_quarter_uu × planned_quarters == one_off_uu`（精确，加载器不做归一化补偿）。
	# 合同总额取 one_off_uu，故此处必须是 0.5 U × 8 == 4 U；写 0 会让夹具本身违反 V-PD-03，
	# 属于内容包非法而非实现缺陷，立项会被 JWProjectQueue.launch 正当拒绝。
	defs.cost_one_off_uu = _put(defs.cost_one_off_uu, P04, TOTAL_COST_UU)
	# content.policy.spend_line_uu 的单位是 μU/季（docs/17 §4.8），项目侧的 spend_plan 才是分项总额。
	defs.spend_line_uu = _put(defs.spend_line_uu, P04 * 3 + LINE_EQUIPMENT, LINE_EQUIPMENT_UU)
	defs.spend_line_uu = _put(defs.spend_line_uu, P04 * 3 + LINE_MATERIAL, LINE_MATERIAL_UU)
	defs.spend_line_uu = _put(defs.spend_line_uu, P04 * 3 + LINE_CONSTRUCTION, LINE_CONSTRUCTION_UU)
	defs.opex_per_q_uu = _put(defs.opex_per_q_uu, P04, OPEX_PER_Q_UU)
	defs.required_construction_uqs = _put(defs.required_construction_uqs, P04, REQ_CONSTRUCTION_UQS)
	defs.required_equipment_uqs = _put(defs.required_equipment_uqs, P04, REQ_EQUIPMENT_UQS)
	defs.commission_delay_q = _put(defs.commission_delay_q, P04, 1)
	defs.lag_enact_to_effect_q = _put(defs.lag_enact_to_effect_q, P04, 0)
	defs.effect_magnitude = _put(defs.effect_magnitude, P04, CAPACITY_EFFECT_UQS)
	defs.exit_compensation_ppm = _put(defs.exit_compensation_ppm, P04, EXIT_COMPENSATION_PPM)
	# 效果只能落在 *_pending_* 白名单上（docs/17 §4.8 EFFECT_TARGETS，INV-091 / V-PD-11）。
	var target: int = JWPolicyDef.EFFECT_TARGETS.find("state.region.grid_capacity_pending_uqs_per_q")
	defs.effect_target = _put(defs.effect_target, P04, target)


func _seed_region_and_world() -> void:
	for r: int in JWUnits.R:
		capital.construction_slots = _put(capital.construction_slots, r, 2)
	# 外部交付能力：默认给足，单个测试自行调低
	for s: int in JWUnits.S:
		world.delivery_capacity = _put(world.delivery_capacity, s, JWUnits.QTY_MAX / 1000)
	# 配套条件之一：目标主体人员不为零（docs/17 §4.20 commission_ready 前置，OQ-245）
	for i: int in JWUnits.EMP_N:
		labor.cell_employment = _put(labor.cell_employment, i, 1_000)
	for i: int in JWUnits.PUBSERV_EMP_N:
		labor.pub_employment = _put(labor.pub_employment, i, 1_000)


func _seed_gov_balances() -> void:
	ledger.post_opening(JWIds.AGENT_GOV, JWIds.ACC_CASH, GOV_CASH_SEED_UU)
	# 付款只增 wip 与承包方现金（INV-092）；单元夹具直接开账出 wip，
	# 让取消路径有「已形成的在建工程」可评估残值。
	ledger.post_opening(JWIds.AGENT_GOV, JWIds.ACC_WIP, GOV_WIP_SEED_UU)


## 立项一个 P04 项目并置为在建。返回项目下标（失败时为 -1）。
func _launch_in_progress(r: int = R_HAIJIA, q: int = 0) -> int:
	entity_seq += 1
	var p: int = pq.launch(entity_seq, P04, r, defs, capital, q)
	if p >= 0:
		pq.set_status(p, JWUnits.ProjectStatus.IN_PROGRESS, JWUnits.SuspendReason.NONE)
	return p


## 走一季 S05 §5.5 的进度推进：先清流量（S01），再折施工能力，再推进度。
func _advance_one_quarter(svc_output_uqs: int) -> void:
	pq.reset_flows()
	world.begin_quarter_delivery()
	var svc: PackedInt64Array = PackedInt64Array()
	svc.resize(JWUnits.CELL)
	svc.fill(0)
	svc[JWIds.idx_cell(R_HAIJIA, JWUnits.Sector.SERVICES)] = svc_output_uqs
	pq.compute_construction_capacity(svc, params)
	pq.advance_progress(world, ledger, accounts)


## 按本季应付清单足额付款（docs/12 §04.4），返回本季实付合计。
func _pay_one_quarter(p: int, q: int) -> int:
	var out_project: PackedInt64Array = PackedInt64Array()
	var out_line: PackedInt64Array = PackedInt64Array()
	var out_payee: PackedInt64Array = PackedInt64Array()
	var out_due: PackedInt64Array = PackedInt64Array()
	out_project.resize(JWUnits.PROJECT_CAP0 * 3)
	out_line.resize(JWUnits.PROJECT_CAP0 * 3)
	out_payee.resize(JWUnits.PROJECT_CAP0 * 3)
	out_due.resize(JWUnits.PROJECT_CAP0 * 3)
	var n: int = pq.payment_due_into(out_project, out_line, out_payee, out_due, q)
	var total: int = 0
	for i: int in n:
		if out_project[i] != p:
			continue
		pq.record_payment(p, out_line[i], out_due[i], treasury)
		total += out_due[i]
	return total


func _gov_cash() -> int:
	return accounts.cash_of(JWIds.AGENT_GOV)


func _gov_wip() -> int:
	return accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_WIP))


func _paid_total(p: int) -> int:
	return pq.paid[p * 3 + 0] + pq.paid[p * 3 + 1] + pq.paid[p * 3 + 2]


func _spend_plan_total(p: int) -> int:
	return pq.spend_plan[p * 3 + 0] + pq.spend_plan[p * 3 + 1] + pq.spend_plan[p * 3 + 2]


# ── 夹具自检 ───────────────────────────────────────────────────────────────

## 检验：docs/17 §2 的契约长度（夹具能否成立的前提）。
## 这条红了说明不是进度逻辑坏了，而是某个块的 allocate() 没按契约长度分配。
func test_fixture_arrays_have_contract_lengths() -> void:
	eq_int(pq.status.size(), JWUnits.PROJECT_CAP0,
			"project SoA 的 status 长度应为 PROJECT_CAP0（docs/17 §4.19）")
	eq_int(pq.paid.size(), JWUnits.PROJECT_CAP0 * 3,
			"paid 按 p*3+line 布局，长度应为 PROJECT_CAP0×3（docs/17 §4.19）")
	eq_int(pq.f_construction_capacity.size(), JWUnits.R,
			"flow.region.construction_capacity_uqs 长度应为 R == 4")
	eq_int(defs.spend_line_uu.size(), JWUnits.POLICY_N * 3,
			"content.policy.spend_line_uu 长度应为 12×3（docs/17 §4.8）")
	eq_int(capital.grid_pending.size(), JWUnits.R,
			"state.region.grid_capacity_pending 长度应为 R == 4")
	eq_int(_gov_cash(), GOV_CASH_SEED_UU,
			"开账后政府现金应等于种子额（post_opening 未生效则后面的取消断言全无意义）")
	eq_int(JWResult.pending_code(), JWResult.Fault.OK,
			"夹具装配（allocate + 开账 + 写内容数组）不得登记任何故障；"
			+ "此处非 0 说明某个块的 allocate() 没按契约长度分配，后面所有断言的现场都不可信")


# ── INV-092：立项与支出计划 ────────────────────────────────────────────────

## 检验：INV-092（Σ spend_plan == total_cost）、INV-094（占槽）、计划书 §10「投入与工期」。
func test_launch_expands_spend_plan_to_total_cost() -> void:
	var p: int = _launch_in_progress()
	ge_int(p, 0, "有空槽时 launch 应返回项目下标（docs/17 §4.19；-1 表示无空槽）")
	eq_int(pq.total_cost[p], TOTAL_COST_UU,
			"合同总额应为计划书 §10 的 4 U，按 R-SCALE-01 == 4 000 000 000 μU")
	eq_int(_spend_plan_total(p), TOTAL_COST_UU,
			"INV-092：Σ_line spend_plan 必须精确等于 total_cost，不允许有取整漏项")
	eq_int(pq.spend_plan[p * 3 + LINE_EQUIPMENT], LINE_EQUIPMENT_UU * PLANNED_Q,
			"进口设备分项 == 每季 0.2 U × 8 季（计划书 §10「支出落点」）")
	eq_int(pq.spend_plan[p * 3 + LINE_MATERIAL], LINE_MATERIAL_UU * PLANNED_Q,
			"国产材料分项 == 每季 0.1 U × 8 季")
	eq_int(pq.spend_plan[p * 3 + LINE_CONSTRUCTION], LINE_CONSTRUCTION_UU * PLANNED_Q,
			"施工服务分项 == 每季 0.2 U × 8 季")
	eq_int(pq.planned_quarters[p], PLANNED_Q, "计划工期应为 8 季（计划书 §10）")
	eq_int(pq.slot_held[p], 1, "INV-094：立项必须占住一个施工槽位")
	eq_int(pq.slots_used(R_HAIJIA), 1, "INV-094：该地区已占槽位应为 1")
	eq_int(pq.required_construction[p], REQ_CONSTRUCTION_UQS,
			"所需施工服务总量应原样取自政策定义（docs/17 §4.8）")
	eq_int(pq.commissioned_q[p], -1, "未投运的项目 commissioned_q 必须是 −1（docs/10 §8.1）")


## 检验：INV-087（payment_due_into 本步不写任何进度字段）、计划书 §10「支出落点：各有收款方」。
func test_payment_due_lines_have_distinct_payees_and_no_progress_write() -> void:
	var p: int = _launch_in_progress()
	var out_project: PackedInt64Array = PackedInt64Array()
	var out_line: PackedInt64Array = PackedInt64Array()
	var out_payee: PackedInt64Array = PackedInt64Array()
	var out_due: PackedInt64Array = PackedInt64Array()
	out_project.resize(JWUnits.PROJECT_CAP0 * 3)
	out_line.resize(JWUnits.PROJECT_CAP0 * 3)
	out_payee.resize(JWUnits.PROJECT_CAP0 * 3)
	out_due.resize(JWUnits.PROJECT_CAP0 * 3)

	var n: int = pq.payment_due_into(out_project, out_line, out_payee, out_due, 0)
	eq_int(n, 3, "在建项目本季应产生 3 条应付行（进口设备 / 国产材料 / 施工服务）")

	var due_total: int = 0
	for i: int in n:
		due_total += out_due[i]
	eq_int(due_total, PER_QUARTER_UU,
			"本季应付合计 == 计划书 §10 的每季 0.5 U == 500 000 000 μU")

	var payee_equipment: int = -1
	var payee_material: int = -1
	var payee_construction: int = -1
	for i: int in n:
		if out_line[i] == LINE_EQUIPMENT:
			payee_equipment = out_payee[i]
		elif out_line[i] == LINE_MATERIAL:
			payee_material = out_payee[i]
		elif out_line[i] == LINE_CONSTRUCTION:
			payee_construction = out_payee[i]
	eq_int(payee_equipment, JWIds.AGENT_ROW,
			"进口设备的收款方必须是 agent.row（docs/12 §04.4；对外必有 row 对手方，INV-026）")
	eq_int(payee_material, JWIds.agent_of_cell(JWIds.idx_cell(R_HAIJIA, JWUnits.Sector.MANU)),
			"国产材料的收款方必须是本地区制造 cell（docs/12 §04.4）")
	eq_int(payee_construction, JWIds.agent_of_cell(JWIds.idx_cell(R_HAIJIA, JWUnits.Sector.SERVICES)),
			"施工服务的收款方必须是本地区服务 cell（docs/12 §04.4）")

	eq_int(pq.construction_progress[p], 0,
			"INV-087：应付清单这一步不得写施工进度")
	eq_int(pq.delivery_progress[p], 0,
			"INV-089：应付清单这一步不得写交付进度")


# ── INV-087：付款不制造进度 ───────────────────────────────────────────────

## 检验：INV-087；docs/30 `T-S-P04-PAY-NO-PROGRESS`（夹具 FX-NOCON：服务产能为 0）；
## 计划书 §10 验收测试第 ① 条「无施工能力时，付款不得直接制造完工进度」。
func test_payment_without_construction_capacity_makes_no_progress() -> void:
	var p: int = _launch_in_progress()
	var paid_q0: int = _pay_one_quarter(p, 0)
	eq_int(paid_q0, PER_QUARTER_UU, "第 0 季应付款 0.5 U（付款照常发生，钱是够的）")

	# FX-NOCON：服务 cell 实际产量为 0 ⇒ 本地区施工能力为 0
	_advance_one_quarter(0)
	eq_int(pq.f_construction_capacity[R_HAIJIA], 0,
			"INV-088：施工能力由服务 cell 的**实际产量**折出，产量为 0 时能力必须为 0")
	eq_int(pq.construction_progress[p], 0,
			"INV-087：付了 0.5 U 但没有一分钟施工，施工进度增量必须是 0")
	eq_int(pq.status[p], JWUnits.ProjectStatus.SUSPENDED,
			"docs/12 §5.5：grant == 0 且 need > 0 ⇒ 项目转 suspended，不是静默推进")
	eq_int(pq.suspension_reason[p], JWUnits.SuspendReason.CONGESTION,
			"docs/12 §5.5：能力为零造成的中断，原因码必须是 congestion（码精确命中）")

	# 第 1 季：恢复在建、再付一季款，仍然没有施工能力
	pq.set_status(p, JWUnits.ProjectStatus.IN_PROGRESS, JWUnits.SuspendReason.NONE)
	var paid_q1: int = _pay_one_quarter(p, 1)
	eq_int(paid_q1, PER_QUARTER_UU, "第 1 季继续按计划付款")
	_advance_one_quarter(0)
	eq_int(_paid_total(p), PER_QUARTER_UU * 2,
			"两季累计已付 1 U —— 付款路径本身没有被进度堵住")
	eq_int(pq.construction_progress[p], 0,
			"INV-087：累计付了 1 U，施工进度仍必须精确为 0（付款与进度无函数依赖）")
	eq_int(capital.grid_pending[R_HAIJIA], 0,
			"docs/30 T-S-P04-PAY-NO-PROGRESS：grid_capacity_pending 增量必须为 0")
	eq_int(capital.grid(R_HAIJIA), 0,
			"docs/30 T-S-P04-PAY-NO-PROGRESS：grid_capacity_active 增量必须为 0")


## 检验：INV-087；docs/31 `ADV-F04`「一次性付清能不能把进度买出来」。
## 一次性付清整份合同（INV-092 允许：paid ≤ spend_plan），进度仍只能按实投施工量走。
func test_lump_sum_prepayment_does_not_accelerate_progress() -> void:
	var p: int = _launch_in_progress()
	# 第 0 季就把三条分项的合同额一次付满
	pq.record_payment(p, LINE_EQUIPMENT, pq.spend_plan[p * 3 + LINE_EQUIPMENT], treasury)
	pq.record_payment(p, LINE_MATERIAL, pq.spend_plan[p * 3 + LINE_MATERIAL], treasury)
	pq.record_payment(p, LINE_CONSTRUCTION, pq.spend_plan[p * 3 + LINE_CONSTRUCTION], treasury)
	eq_int(_paid_total(p), TOTAL_COST_UU,
			"一次付清 4 U 应被接受（INV-092 只约束 Σ paid ≤ Σ spend_plan）")

	# 交付能力为 0（FX-NODEL），施工能力充足
	world.delivery_capacity = _put(world.delivery_capacity, JWUnits.Sector.MANU, 0)
	_advance_one_quarter(SERVICES_OUTPUT_UQS)

	eq_int(pq.construction_progress[p], DELTA_CONSTRUCTION_PPM,
			"INV-088：进度增量 == mul_div_floor(实投 375 000, 1e6, 3 000 001) == 124 999；"
			+ "付满全款不得让它跳到 1 000 000")
	eq_int(pq.delivery_progress[p], 0,
			"INV-089：交付进度只由实际到货量决定，付满全款而外部交付能力为 0 时必须是 0")
	check_false(pq.progress_ready(p),
			"INV-090：两项进度都没满，progress_ready 必须为假")


# ── INV-088：施工进度的整数公式 ───────────────────────────────────────────

## 检验：INV-088（Δconstruction == mul_div_floor(实投量, PPM, required_construction)）；
## 实投量受本季 construction_capacity 约束（docs/12 §5.5）。
func test_construction_progress_is_floor_of_granted_share() -> void:
	var p: int = _launch_in_progress()
	# 只想让下面那条故障断言指向 advance_progress 自己，先把立项阶段的登记清干净。
	JWResult.clear_pending()
	_advance_one_quarter(SERVICES_OUTPUT_UQS)

	eq_int(pq.f_construction_capacity[R_HAIJIA], 1_000_000,
			"施工能力 == mul_ppm(服务实际产量 5 000 000, share 200 000 ppm) == 1 000 000 μQ_services")
	eq_int(pq.f_construction_used[R_HAIJIA], NEED_CONSTRUCTION_PER_Q,
			"本季实投 == need == floor_div(3 000 001, 8) == 375 000（能力富余时取需求）")
	eq_int(pq.construction_progress[p], DELTA_CONSTRUCTION_PPM,
			"INV-088：mul_div_floor(375 000, 1 000 000, 3 000 001) == 124 999（向下取整，"
			+ "取 125 000 说明用了 ceil 或四舍五入）")
	eq_int(pq.delivery_progress[p], 0,
			"本测试未给设备到货，交付进度应仍为 0（两条进度互不串台）")
	eq_int(JWResult.pending_code(), JWResult.Fault.OK,
			"推进进度不得登记任何故障（required_* > 0，不应出现 DIV_ZERO）")


## 检验：INV-088 / INV-089 的上界 clamp（docs/12 §5.5 两处 clamp 到 [0, 1e6]）。
func test_progress_is_clamped_at_full() -> void:
	var p: int = _launch_in_progress()
	pq.construction_progress = _put(pq.construction_progress, p, 999_990)
	pq.delivery_progress = _put(pq.delivery_progress, p, 999_990)
	_advance_one_quarter(SERVICES_OUTPUT_UQS)
	eq_int(pq.construction_progress[p], 1_000_000,
			"docs/12 §5.5：999 990 + 124 999 必须 clamp 到 1 000 000，不得溢出上界")
	le_int(pq.delivery_progress[p], 1_000_000,
			"docs/12 §5.5：交付进度同样不得超过 1 000 000")


## 检验：INV-092（Σ_line paid ≤ Σ_line spend_plan）；docs/12 §4.3「超出合同剩余额 ⇒ 拒付 + suspended」。
func test_overpay_is_refused_and_does_not_change_paid() -> void:
	var p: int = _launch_in_progress()
	var line_cap: int = pq.spend_plan[p * 3 + LINE_CONSTRUCTION]
	pq.record_payment(p, LINE_CONSTRUCTION, line_cap + 1, treasury)
	eq_int(pq.paid[p * 3 + LINE_CONSTRUCTION], 0,
			"INV-092：超出分项合同额的付款必须被整笔拒绝，paid 一分不得增加")
	eq_int(pq.status[p], JWUnits.ProjectStatus.SUSPENDED,
			"docs/12 §4.3：超付的项目转 suspended（不是静默截断后照付）")
	le_int(_paid_total(p), _spend_plan_total(p),
			"INV-092：Σ paid 恒不得超过 Σ spend_plan")


# ── INV-089：交付进度只由到货决定 ─────────────────────────────────────────

## 检验：INV-089；docs/30 `T-S-P04-FAIL-DELIVERY`（夹具 FX-NODEL）。
## 交付能力为 0 时交付进度逐季增量恒为 0，而施工进度照常增长（证明两条进度互相独立）。
func test_delivery_progress_stays_zero_without_delivery_capacity() -> void:
	var p: int = _launch_in_progress()
	world.delivery_capacity = _put(world.delivery_capacity, JWUnits.Sector.MANU, 0)

	for k: int in 4:
		_pay_one_quarter(p, k)
		_advance_one_quarter(SERVICES_OUTPUT_UQS)
		eq_int(pq.delivery_progress[p], 0,
				"INV-089：外部交付能力为 0 ⇒ 交付进度增量必须逐季精确为 0（第 %d 季）" % k)

	eq_int(pq.construction_progress[p], DELTA_CONSTRUCTION_PPM * 4,
			"施工进度应照常按季累加 4 × 124 999 —— 交付卡住不得连坐施工（两条进度独立）")
	check_false(pq.progress_ready(p),
			"INV-090：交付未达 1 000 000 时 progress_ready 必须为假")


## 检验：INV-089（到货量 ≤ world.delivery_capacity_uqs）与 INV-104（进口受交付能力约束）。
func test_delivery_progress_is_capped_by_delivery_capacity() -> void:
	var p: int = _launch_in_progress()
	# 交付能力 100 000 < 本季设备需求 250 000 ⇒ 到货量必然恰为交付能力
	world.delivery_capacity = _put(world.delivery_capacity, JWUnits.Sector.MANU, 100_000)
	_pay_one_quarter(p, 0)
	_advance_one_quarter(SERVICES_OUTPUT_UQS)

	# mul_div_floor(100 000, 1e6, 2 000 003)：2 000 003 × 49 999 == 99 998 149 997 ≤ 1e11
	# < 2 000 003 × 50 000 == 100 000 150 000 ⇒ 真值 floor 恰为 49 999
	eq_int(pq.delivery_progress[p], 49_999,
			"INV-089：Δdelivery == mul_div_floor(到货 100 000, 1e6, 2 000 003) == 49 999；"
			+ "若等于 125 000 说明交付进度被「已订量」或付款推动了")
	le_int(pq.delivery_progress[p], 1_000_000, "交付进度不得越过 1 000 000")
	eq_int(world.delivery_remaining(JWUnits.Sector.MANU), 0,
			"INV-104：本季交付额度应被这笔到货吃满（额度未扣减说明到货没走 world 的账）")
	ge_int(NEED_EQUIPMENT_PER_Q, 100_000,
			"夹具前提：本季设备需求 250 000 大于交付能力 100 000，交付能力才是紧约束")


# ── INV-090 / INV-091：完工与投运 ─────────────────────────────────────────

## 检验：INV-090（完工充要条件）；docs/30 `T-S-P04-NO-EARLY-COMMISSION`；
## 计划书 §10 验收测试第 ② 条「第 8 季未交付齐全不得投运」。
func test_no_commission_until_both_progresses_are_full() -> void:
	var p: int = _launch_in_progress()
	pq.construction_progress = _put(pq.construction_progress, p, 1_000_000)
	pq.delivery_progress = _put(pq.delivery_progress, p, 999_999)

	comm.commission_ready(pq, capital, treasury, labor, ledger, accounts, 7)

	check_false(pq.progress_ready(p),
			"INV-090：交付差 1 ppm 就不算齐全，progress_ready 必须为假")
	ne_int(pq.status[p], JWUnits.ProjectStatus.COMPLETED,
			"INV-090：交付进度 999 999 < 1 000 000 时不得判完工")
	ne_int(pq.status[p], JWUnits.ProjectStatus.COMMISSIONED,
			"INV-090：未完工更不得投运（计划书 §10：第 8 季未交付齐全不得投运）")
	eq_int(capital.grid_pending[R_HAIJIA], 0,
			"docs/30 T-S-P04-NO-EARLY-COMMISSION：未完工时 grid_capacity_pending 增量必须为 0")
	eq_int(capital.grid(R_HAIJIA), 0,
			"docs/30 T-S-P04-NO-EARLY-COMMISSION：grid_capacity_active 增量必须为 0")
	eq_int(pq.commissioned_q[p], -1, "未投运的项目 commissioned_q 必须仍是 −1")
	eq_int(pq.slot_held[p], 1, "INV-094：未完工的项目必须继续占着槽位")


## 检验：INV-091（完工只写 *_pending_*）、INV-054（本季完工的产能对本季生产毫无影响）；
## docs/12 §7.1「只写 pending」。
func test_completion_writes_pending_capacity_only() -> void:
	var p: int = _launch_in_progress()
	pq.construction_progress = _put(pq.construction_progress, p, 1_000_000)
	pq.delivery_progress = _put(pq.delivery_progress, p, 1_000_000)
	var opex_before: int = treasury.service_opex_committed

	comm.commission_ready(pq, capital, treasury, labor, ledger, accounts, 7)

	check(pq.progress_ready(p), "两项进度均达 1 000 000，progress_ready 必须为真")
	eq_int(pq.status[p], JWUnits.ProjectStatus.COMPLETED,
			"docs/12 §7.1：两项进度齐全且配套条件满足 ⇒ status = completed")
	eq_int(capital.grid_pending[R_HAIJIA], CAPACITY_EFFECT_UQS,
			"INV-091：完工新增容量必须写进 grid_capacity_pending（计划书 §10：额外 10 单位电力服务）")
	eq_int(capital.grid(R_HAIJIA), 0,
			"INV-054：完工当季 grid_capacity_active 必须一动不动，否则本季生产就用上了新产能")
	eq_int(pq.commissioned_q[p], -1,
			"INV-091：完工当季还没投运，commissioned_q 仍应是 −1")
	eq_int(pq.slot_held[p], 0, "docs/12 §7.1：完工要释放施工槽位")
	eq_int(pq.slots_used(R_HAIJIA), 0, "INV-094：槽位释放后该地区已占槽位应回到 0")
	eq_int(treasury.service_opex_committed, opex_before + OPEX_PER_Q_UU,
			"docs/12 §7.1：完工要把每季运行费 0.02 U 计入 service_opex_committed")


## 检验：INV-091 / docs/12 §01.4 验收测试 `T-S-COMMISSION-LAG`；
## 计划书 §10「新增容量下一季投入使用」（验收测试第 ③ 条的数据流前提）。
func test_commission_lag_is_exactly_one_quarter() -> void:
	var p: int = _launch_in_progress()
	pq.construction_progress = _put(pq.construction_progress, p, 1_000_000)
	pq.delivery_progress = _put(pq.delivery_progress, p, 1_000_000)

	# q = 7：S07 完工
	comm.commission_ready(pq, capital, treasury, labor, ledger, accounts, 7)
	eq_int(capital.grid(R_HAIJIA), 0,
			"T-S-COMMISSION-LAG：q=7（完工季）的在用电网容量不含新增")

	# q = 8：S01 先把 pending 转 active，再把 completed 提升为 commissioned
	capital.commit_pending()
	comm.promote_completed(pq, 8)

	eq_int(capital.grid(R_HAIJIA), CAPACITY_EFFECT_UQS,
			"T-S-COMMISSION-LAG：q=8 的在用电网容量必须含新增的 10 单位")
	eq_int(capital.grid_pending[R_HAIJIA], 0,
			"docs/12 §01.4 断言：转入后 Σ capacity_pending == 0")
	eq_int(pq.status[p], JWUnits.ProjectStatus.COMMISSIONED,
			"INV-091：上季完工的项目本季应转 commissioned")
	eq_int(pq.commissioned_q[p], 8,
			"INV-091：commissioned_q 必须精确等于完工季 7 + 1 == 8（T-S-COMMISSION-LAG）")


# ── INV-093：取消时的残值与赔偿 ───────────────────────────────────────────

## 检验：INV-093（paid 不回退、现金不增加）、INV-032；
## docs/30 `T-S-D-07` / docs/31 `ADV-F01`；计划书 §17「项目取消不会释放已实际花掉的钱」。
func test_cancel_never_refunds_paid_and_never_adds_cash() -> void:
	var p: int = _launch_in_progress()
	# 推进到 q=3 末：4 季 × 0.5 U == 2 U 已付
	for k: int in 4:
		_pay_one_quarter(p, k)
	eq_int(_paid_total(p), 2_000_000_000,
			"夹具前提：4 季按计划付款后已付 2 U（docs/30 T-S-D-07 的 2 000 000 为旧刻度值）")
	var paid_before: int = _paid_total(p)
	var cash_before: int = _gov_cash()

	pq.cancel(p, defs, treasury, ledger, accounts, capital)

	eq_int(_paid_total(p), paid_before,
			"INV-093：取消后 paid_uu 必须逐分不变 —— 冲销已付分录就是账本层面的时间倒流")
	le_int(_gov_cash(), cash_before,
			"INV-093 / ADV-F01：政府现金只会因取消而减少，绝不增加")
	eq_int(pq.status[p], JWUnits.ProjectStatus.CANCELLED,
			"docs/12 §02.7：取消后状态必须是 cancelled")
	eq_int(pq.slot_held[p], 0, "INV-094：取消要释放槽位")
	eq_int(capital.grid_pending[R_HAIJIA], 0,
			"docs/30 T-S-D-07 ⑤：取消不得写出任何待投运容量")
	eq_int(capital.grid(R_HAIJIA), 0, "取消更不得写在用容量")


## 检验：INV-093（cancel_penalty 按剩余合同额结算；committed_memo 只减未付部分）；
## docs/30 `T-S-D-07` ②③；计划书 §10「合同赔偿按剩余合同规则结算」。
func test_cancel_penalty_is_share_of_unpaid_contract() -> void:
	var p: int = _launch_in_progress()
	for k: int in 4:
		_pay_one_quarter(p, k)
	# 承诺台账由 S02 的立项预留写入（launch 的形参表里没有 treasury），此处按契约口径手工置位：
	# committed_memo == 尚未支付的合同额（docs/30 T-U-D-08 的三次读数口径）。
	treasury.committed_memo = TOTAL_COST_UU
	var unpaid: int = TOTAL_COST_UU - _paid_total(p)
	var cash_before: int = _gov_cash()

	pq.cancel(p, defs, treasury, ledger, accounts, capital)

	eq_int(unpaid, 2_000_000_000, "夹具前提：剩余合同额 == 4 U − 已付 2 U == 2 U")
	eq_int(pq.cancel_penalty[p], 600_000_000,
			"INV-093：赔偿 == mul_ppm(剩余合同 2 000 000 000, 300 000 ppm) == 600 000 000 μU")
	eq_int(cash_before - _gov_cash(), 600_000_000,
			"docs/30 T-S-D-07 ②：取消当季政府现金的变化量应恰为 −600 000 000（赔偿真的付出去了）")
	eq_int(treasury.committed_memo, TOTAL_COST_UU - unpaid,
			"docs/30 T-S-D-07 ③：committed_memo 只减未付部分（减 2 U），已付部分早已不在承诺里")


## 检验：INV-093 / INV-020；docs/31 `ADV-F06`「残值套利」。
## 只付一季就取消，残值不得超过实际已投入 —— 残值若引用 total_cost 就会在这里露馅。
func test_cancel_residual_cannot_exceed_actual_investment() -> void:
	var p: int = _launch_in_progress()
	_pay_one_quarter(p, 0)
	var paid_before: int = _paid_total(p)
	var wip_before: int = _gov_wip()
	treasury.committed_memo = TOTAL_COST_UU

	pq.cancel(p, defs, treasury, ledger, accounts, capital)

	ge_int(pq.residual_value[p], 0, "INV-093：残值不得为负")
	le_int(pq.residual_value[p], wip_before,
			"ADV-F06：residual_value ≤ 取消时的 gov.wip —— 残值是已形成在建工程的评估值")
	le_int(pq.residual_value[p], TOTAL_COST_UU,
			"ADV-F06：残值一旦超过合同总额，说明残值函数在凭空创造资产")
	eq_int(_paid_total(p), paid_before,
			"INV-093：只付一季就取消，已付的 0.5 U 同样不回退")
	le_int(_gov_cash() - 0, GOV_CASH_SEED_UU,
			"ADV-F06：付一点点钱再取消，不得因此拿到比开局更多的现金")


# ── INV-094：槽位是硬约束 ─────────────────────────────────────────────────

## 检验：INV-094（Σ queue_slot_held ≤ construction_slots_total，超出者不得静默排队）；
## docs/31 `ADV-F02`「反复立项占队列」——取消当季必须释放槽位，且不得泄漏。
func test_queue_slot_is_a_hard_limit_and_is_released_on_cancel() -> void:
	capital.construction_slots = _put(capital.construction_slots, R_HAIJIA, 1)

	var p0: int = _launch_in_progress()
	ge_int(p0, 0, "第 1 个项目应占到唯一的槽位")
	eq_int(pq.slots_used(R_HAIJIA), 1, "INV-094：已占槽位应为 1")

	entity_seq += 1
	var p1: int = pq.launch(entity_seq, P04, R_HAIJIA, defs, capital, 0)
	eq_int(p1, -1,
			"INV-094：槽位已满时 launch 必须返回 −1（调用方置 blocked_reason = QUEUE 并 REJECT(NO_SLOT)），"
			+ "不得静默排队")
	eq_int(pq.slots_used(R_HAIJIA), 1,
			"被拒的立项不得留下任何槽位占用（泄漏一个槽位就等于永久堵死队列）")

	treasury.committed_memo = TOTAL_COST_UU
	pq.cancel(p0, defs, treasury, ledger, accounts, capital)
	eq_int(pq.slots_used(R_HAIJIA), 0, "ADV-F02：取消当季必须释放槽位")

	entity_seq += 1
	var p2: int = pq.launch(entity_seq, P04, R_HAIJIA, defs, capital, 1)
	ge_int(p2, 0, "ADV-F02：槽位释放后应能重新立项（跑完一轮立项—取消，可用槽位必须回到初值）")
