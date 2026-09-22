## 迁移与住房单元测试（S07 §7.5）。
##
## 依据：docs/18 裁定（R-SCALE-01 的 μU 刻度）、docs/12 §7.4/§7.5、
## docs/10 §14.6 的 INV-071…INV-084、docs/30 的 `T-U-B-03` / `T-U-B-13` / `ADV-04`、
## docs/31 的 `ADV-E01`（≡ 计划书 §17 点名「所有工人迁到同一区域是否仍享受无限住房」）与 `ADV-E02`。
##
## 本文件**不读迁移实现**，只按契约构造夹具并断言契约后置条件：
##   movers = min(intent, cap_jobs, cap_housing, cap_cost)；
##   cap_housing = max(0, housing_stock × persons_per_housing_unit − region_population)；
##   被挡回的人写 migrate_rejected_persons；容量不得自动增长；来源去向双边配对。
##
## 纪律：JWResult 的故障登记是静态的，会跨测试方法残留；每个方法前 clear_pending()。
## 夹具**整表赋值**而不是逐位写入，这样即使某个块的 allocate() 尚未实现，
## 失败也会落在被测的迁移逻辑上，而不是落在夹具自己身上。
extends JWTest

# ── 夹具的固定刻度（全部整数，来源见各常量注释） ──────────────────────────

## 迁出地（北原）
const R_FROM: int = 0
## 迁入地（中州）
const R_TO: int = 1
## 迁移成本：剧本 2 000…4 000 μU/人，已随 R-SCALE-01 ×1000，取中值
const MIG_COST_UU: int = 3_000_000
## param.persons_per_housing_unit
const PERSONS_PER_UNIT: int = 3
## 三档季度工资率（μU/人/季）。R-SCALE-01 后人均季度劳动报酬约 1 360 μU
const WAGE_LOW: int = 1_000
const WAGE_MID: int = 1_360
const WAGE_HIGH: int = 2_000
## 迁出地 working.low 人口
const POP_FROM: int = 1_000_000
## 迁入地 working.high 人口
const POP_TO: int = 100_000
## 劳动参与率
const PARTICIPATION_PPM: int = 800_000
## param.migration_max_share_ppm
const MAX_SHARE_PPM: int = 100_000
## param.migration_threshold_ppm
const THRESHOLD_PPM: int = 1_000
## 迁出地在岗人数（LF 800 000 − 400 000 = 400 000 失业）
const EMPLOYED_FROM: int = 400_000
## 迁入地在岗人数（LF 80 000 − 40 000 = 40 000 空缺）
const EMPLOYED_TO: int = 40_000
## 迁入地初始占用住房
const OCCUPIED_TO_UNITS: int = 30_000
## 迁出地初始占用住房
const OCCUPIED_FROM_UNITS: int = 300_000
## 迁出地住房存量／容量（充裕，不构成约束）
const STOCK_FROM_UNITS: int = 1_000_000

var pop: JWPopulation = null
var labor: JWLaborMarket = null
var capital: JWCapital = null
var pricing: JWPricing = null
var accounts: JWAccount = null
var ledger: JWLedger = null
var rng: JWRngStreams = null
var mig: JWMigration = null
var params: PackedInt64Array = PackedInt64Array()

## 迁出组：北原 working.low
var g_from: int = 0
## 迁入地本地组：中州 working.high
var g_to_home: int = 0


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(JWUnits.Phase.S07)
	g_from = JWIds.idx_group(R_FROM, JWUnits.Age.WORKING, JWUnits.Skill.LOW)
	g_to_home = JWIds.idx_group(R_TO, JWUnits.Age.WORKING, JWUnits.Skill.HIGH)
	accounts = JWAccount.new()
	accounts.allocate()
	accounts.balance = _zeros(JWUnits.ACCOUNT_N)
	ledger = JWLedger.new(accounts)
	ledger.allocate()
	ledger.set_context(0, JWUnits.Phase.S07)
	rng = JWRngStreams.new()
	rng.allocate()
	rng.begin_quarter(0)
	pop = JWPopulation.new()
	pop.allocate()
	labor = JWLaborMarket.new()
	labor.allocate()
	capital = JWCapital.new()
	capital.allocate()
	pricing = JWPricing.new()
	pricing.allocate()
	mig = JWMigration.new()
	mig.allocate()
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


## 默认参数：拉力只由工资差驱动（权重和恰为 1e6，docs/12 §7.5 要求），推力权重为 0，
## 这样住房约束在**硬闸**上生效，而不是被推力软化掉——三道硬闸才是被测对象。
func _default_params() -> void:
	params[JWUnits.Param.MIGRATION_W_WAGE_PPM] = 1_000_000
	params[JWUnits.Param.MIGRATION_W_JOB_PPM] = 0
	params[JWUnits.Param.MIGRATION_W_SERVICE_PPM] = 0
	params[JWUnits.Param.MIGRATION_W_HOUSE_PPM] = 0
	params[JWUnits.Param.MIGRATION_W_ENV_PPM] = 0
	params[JWUnits.Param.MIGRATION_THRESHOLD_PPM] = THRESHOLD_PPM
	params[JWUnits.Param.MIGRATION_MAX_SHARE_PPM] = MAX_SHARE_PPM
	params[JWUnits.Param.PERSONS_PER_HOUSING_UNIT] = PERSONS_PER_UNIT


## 邻接对登记（对称无自环；对角线迁移成本恒为 0，docs/12 §7.5 注释）。
func _link(a: int, b: int, adjacency: PackedInt64Array, cost: PackedInt64Array) -> void:
	adjacency[JWIds.idx_od(a, b)] = 1
	adjacency[JWIds.idx_od(b, a)] = 1
	cost[JWIds.idx_od(a, b)] = MIG_COST_UU
	cost[JWIds.idx_od(b, a)] = MIG_COST_UU


## 两地区夹具：北原（低工资、高失业）↔ 中州（高工资）。
## `stock_to_units` 决定住房硬闸松紧，`cash_from_uu` 决定迁移成本硬闸松紧，
## `vacancies_to` 决定职位硬闸松紧。
func _world_two_region(stock_to_units: int, cash_from_uu: int, employed_to: int) -> void:
	var population: PackedInt64Array = _zeros(JWUnits.GROUP)
	var participation: PackedInt64Array = _zeros(JWUnits.GROUP)
	var group_emp: PackedInt64Array = _zeros(JWUnits.GROUP_EMP_N)
	var occupied: PackedInt64Array = _zeros(JWUnits.GROUP)
	var service_access: PackedInt64Array = _zeros(JWUnits.GROUP_SVC_N)
	var cell_emp: PackedInt64Array = _zeros(JWUnits.EMP_N)

	population[g_from] = POP_FROM
	participation[g_from] = PARTICIPATION_PPM
	group_emp[JWIds.idx_group_emp(g_from, JWUnits.Sector.SERVICES)] = EMPLOYED_FROM
	cell_emp[JWIds.idx_emp(JWIds.idx_cell(R_FROM, JWUnits.Sector.SERVICES), JWUnits.Skill.LOW)] = \
			EMPLOYED_FROM
	occupied[g_from] = OCCUPIED_FROM_UNITS

	population[g_to_home] = POP_TO
	participation[g_to_home] = PARTICIPATION_PPM
	group_emp[JWIds.idx_group_emp(g_to_home, JWUnits.Sector.SERVICES)] = employed_to
	cell_emp[JWIds.idx_emp(JWIds.idx_cell(R_TO, JWUnits.Sector.SERVICES), JWUnits.Skill.HIGH)] = \
			employed_to
	occupied[g_to_home] = OCCUPIED_TO_UNITS

	pop.population = population
	pop.participation_ppm = participation
	pop.employed = group_emp
	pop.housing_occupied = occupied
	pop.service_access = service_access
	pop.f_migrate_rejected = _zeros(JWUnits.GROUP)

	labor.cell_employment = cell_emp
	labor.pub_employment = _zeros(JWUnits.PUBSERV_EMP_N)
	# 空缺人数在 S03 写入；本文件不跑 S03，按「迁入地 LF − 在岗」预置，
	# 让职位闸在两种可能口径（全国标量 / 逐地区反算）下取值一致。
	labor.set("_vacancies_persons", JWMath.mul_ppm(POP_TO, PARTICIPATION_PPM) - employed_to)

	var stock: PackedInt64Array = _zeros(JWUnits.R)
	var capacity: PackedInt64Array = _zeros(JWUnits.R)
	stock[R_FROM] = STOCK_FROM_UNITS
	capacity[R_FROM] = STOCK_FROM_UNITS
	stock[R_TO] = stock_to_units
	capacity[R_TO] = stock_to_units + 6_000
	capital.housing_stock = stock
	capital.housing_capacity = capacity
	capital.env_exposure = _zeros(JWUnits.R)

	pricing.wage = PackedInt64Array([WAGE_LOW, WAGE_MID, WAGE_HIGH])

	var adjacency: PackedInt64Array = _zeros(JWUnits.OD_N)
	var cost: PackedInt64Array = _zeros(JWUnits.OD_N)
	_link(R_FROM, R_TO, adjacency, cost)
	mig.adjacency = adjacency
	mig.migration_cost = cost

	accounts.balance[JWIds.idx_account(JWIds.agent_of_group(g_from), JWIds.ACC_CASH)] = cash_from_uu


func _run() -> int:
	return mig.run(pop, labor, capital, pricing, ledger, accounts, rng, params)


func _sum_occupied_in_region(r: int) -> int:
	var total: int = 0
	var g: int = 0
	while g < JWUnits.GROUP:
		if JWIds.region_of_group(g) == r:
			total += pop.housing_occupied[g]
		g += 1
	return total


func _cash_of_group(g: int) -> int:
	return accounts.cash_of(JWIds.agent_of_group(g))


# ── §7.5 住房紧张度（迁移推力与租金的共同输入） ────────────────────────────

## 检验 docs/12 §7.5 注释的 `housing_stress_ppm[r] = clamp(floor(occupied×1e6/capacity), 0, 1e6)`
## 与 INV-083。夹具取 stock == capacity，使「分母是存量还是容量」的口径歧义不影响期望值。
func test_housing_stress_ppm_equals_occupancy_ratio() -> void:
	_world_two_region(40_000, 3_000_000_000_000, EMPLOYED_TO)
	var stock: PackedInt64Array = _zeros(JWUnits.R)
	var capacity: PackedInt64Array = _zeros(JWUnits.R)
	stock[R_TO] = 40_000
	capacity[R_TO] = 40_000
	stock[R_FROM] = 40_000
	capacity[R_FROM] = 40_000
	capital.housing_stock = stock
	capital.housing_capacity = capacity
	var occupied: PackedInt64Array = _zeros(JWUnits.GROUP)
	occupied[g_to_home] = 10_000
	pop.housing_occupied = occupied

	eq_int(mig.housing_stress_ppm(pop, capital, R_TO), 250_000,
			"住房紧张度应为 floor(10 000 套占用 × 1e6 / 40 000 套) = 250 000 ppm（docs/12 §7.5 注释）")
	eq_int(mig.housing_stress_ppm(pop, capital, R_FROM), 0,
			"无人占用的地区紧张度应为 0 ppm（docs/12 §7.5 注释）")
	check_false(JWResult.has_pending(),
			"housing_stress_ppm 是纯函数，不应登记任何故障（当前码 %d）" % JWResult.pending_code())


## 检验 docs/17 §4.16 的失败行「capacity == 0 → 返回 1 000 000（满）」，且不得除零。
func test_housing_stress_ppm_is_full_when_capacity_zero() -> void:
	_world_two_region(40_000, 3_000_000_000_000, EMPLOYED_TO)
	capital.housing_stock = _zeros(JWUnits.R)
	capital.housing_capacity = _zeros(JWUnits.R)

	eq_int(mig.housing_stress_ppm(pop, capital, R_TO), 1_000_000,
			"容量为 0 时住房紧张度必须是满值 1 000 000 ppm（docs/17 §4.16 失败行）")
	ne_int(JWResult.pending_code(), JWResult.Fault.DIV_ZERO,
			"容量为 0 必须走 max(capacity, 1)，不得触发 DIV_ZERO（docs/12 §7.5 注释）")


## 检验紧张度恒落在 [0, 1e6]：占用超过容量（不该发生，但夹具强制构造）也必须被 clamp。
func test_housing_stress_ppm_is_clamped_to_ppm_range() -> void:
	_world_two_region(40_000, 3_000_000_000_000, EMPLOYED_TO)
	var stock: PackedInt64Array = _zeros(JWUnits.R)
	stock[R_TO] = 1_000
	capital.housing_stock = stock
	var capacity: PackedInt64Array = _zeros(JWUnits.R)
	capacity[R_TO] = 1_000
	capital.housing_capacity = capacity
	var occupied: PackedInt64Array = _zeros(JWUnits.GROUP)
	occupied[g_to_home] = 9_999
	pop.housing_occupied = occupied

	in_range_int(mig.housing_stress_ppm(pop, capital, R_TO), 0, 1_000_000,
			"住房紧张度必须 clamp 在 [0, 1 000 000]（docs/12 §7.5、docs/17 §4.16 后置）")


# ── §7.5 三道硬闸 ─────────────────────────────────────────────────────────

## 检验 `T-U-B-13` / `ADV-04` / INV-083：住房是**硬上限**，movers 精确等于 cap_housing。
## cap_housing = max(0, 34 000 套 × 3 人/套 − 100 000 人) = 2 000 人（docs/12 §7.5）。
## 其余三项均宽松：intent ≥ 40 000、cap_jobs = 40 000、cap_cost = 1 000 000。
func test_housing_gate_caps_movers_at_cap_housing() -> void:
	_world_two_region(34_000, 3_000_000_000_000, EMPLOYED_TO)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "干净夹具上的迁移不应返回故障码")

	var moved_in: int = JWMath.sum(mig.in_by_group())
	var moved_out: int = JWMath.sum(mig.out_by_group())
	eq_int(moved_out, 2_000,
			"movers 应被住房硬闸截到 cap_housing = 34 000 × 3 − 100 000 = 2 000 人（docs/12 §7.5）")
	eq_int(moved_in, moved_out,
			"迁入总数必须等于迁出总数（INV-073）")
	eq_int(pop.region_population(R_TO), 102_000,
			"迁入后中州人口应恰为住房承载上限 34 000 套 × 3 人/套 = 102 000 人（INV-083）")


## 检验 INV-084：被住房闸挡回的人数必须显式登记在 migrate_rejected_persons，
## 且登记值 == intent − movers（intent ≥ mul_ppm(失业 400 000, max_share 100 000) = 40 000）。
func test_rejected_persons_registered_when_housing_gate_binds() -> void:
	_world_two_region(34_000, 3_000_000_000_000, EMPLOYED_TO)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "干净夹具上的迁移不应返回故障码")

	var rejected: int = pop.f_migrate_rejected[g_from]
	var moved_out: int = mig.out_by_group()[g_from]
	ge_int(rejected, 1,
			"住房只放行 2 000 人而意向至少 40 000 人，被挡回人数必须 > 0（INV-084 / ADV-04 ②）")
	eq_int(rejected + moved_out, JWMath.mul_ppm(POP_FROM, MAX_SHARE_PPM),
			"被挡回 + 实际迁出应等于意向人数；意向上界 = mul_ppm(1 000 000 人, 100 000 ppm) = 100 000 人（docs/12 §7.5）")


## 检验 INV-084 的「容量不得自动增长」：迁移不得写 housing_stock / housing_capacity。
## 对应 `ADV-E01` 失败诊断「存量自动增长 ⇒ 住房被写成了需求驱动的软约束」。
func test_housing_stock_and_capacity_never_grow_during_migration() -> void:
	_world_two_region(34_000, 3_000_000_000_000, EMPLOYED_TO)
	var stock_before: PackedInt64Array = capital.housing_stock.duplicate()
	var capacity_before: PackedInt64Array = capital.housing_capacity.duplicate()
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "干净夹具上的迁移不应返回故障码")

	eq_int_array(capital.housing_stock, stock_before,
			"迁移不得写 state.region.housing_stock_units（INV-084：容量只能由 P06 完工形成）")
	eq_int_array(capital.housing_capacity, capacity_before,
			"迁移不得写 state.region.housing_capacity_units（INV-084 / ADV-04 ④）")


## 检验 §7.5 的 cap_cost = idiv_floor(group.cash, migration_cost)：
## 现金只够 7 个人的迁移成本时，最多只能走 7 个人。
func test_cost_gate_caps_movers_by_group_cash() -> void:
	_world_two_region(1_000_000, 7 * MIG_COST_UU, EMPLOYED_TO)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "干净夹具上的迁移不应返回故障码")

	eq_int(mig.out_by_group()[g_from], 7,
			"现金 21 000 000 μU ÷ 迁移成本 3 000 000 μU/人 = 7 人，cap_cost 必须精确截到 7（docs/12 §7.5）")
	eq_int(_cash_of_group(g_from), 0,
			"迁移成本是真实支出：7 人 × 3 000 000 μU 应把该组现金花光（docs/12 §7.5 post(MIGRATION_COST)）")
	eq_int(accounts.cash_of(JWIds.agent_of_cell(JWIds.idx_cell(R_TO, JWUnits.Sector.SERVICES))),
			7 * MIG_COST_UU,
			"迁移成本的收款方是 cell.services[r_to]，应恰好收到 21 000 000 μU（docs/12 §7.5）")


## 检验 §7.5 的 cap_cost 下界：现金为 0 ⇒ 一个人也走不了，且全部意向写 migrate_rejected（INV-084）。
func test_zero_cash_blocks_migration_entirely() -> void:
	_world_two_region(1_000_000, 0, EMPLOYED_TO)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "现金不足是业务约束不是故障，不应返回故障码")

	eq_int(JWMath.sum(mig.out_by_group()), 0,
			"cap_cost = floor(0 / 3 000 000) = 0，不得有任何人迁出（docs/12 §7.5）")
	eq_int(pop.population[g_from], POP_FROM,
			"无人迁出时迁出组人口必须一位不动（INV-072）")
	ge_int(pop.f_migrate_rejected[g_from], 1,
			"付不起迁移成本的意向必须登记为 migrate_rejected_persons，不得静默消失（INV-084）")


## 检验 §7.5 的 cap_jobs：迁入地零空缺 ⇒ movers == 0。
## 夹具让迁入地在岗 == 劳动力，两种可能口径（全国空缺标量 / 逐地区 LF − 在岗）都得 0。
func test_job_gate_blocks_migration_when_no_vacancies() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000,
			JWMath.mul_ppm(POP_TO, PARTICIPATION_PPM))
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "零空缺是业务约束不是故障，不应返回故障码")

	eq_int(JWMath.sum(mig.in_by_group()), 0,
			"cap_jobs = 迁入地空缺岗位 = 80 000 劳动力 − 80 000 在岗 = 0，不得有人迁入（docs/12 §7.5）")
	ge_int(pop.f_migrate_rejected[g_from], 1,
			"被职位闸挡回的人同样必须显式登记（INV-084）")


## 检验 §7.5 的 `intent = mul_ppm(eligible_pop, min(net_ppm, max_share_ppm))`：
## 三道硬闸全松时，迁出人数不得超过 mul_ppm(该组人口, migration_max_share_ppm)。
func test_max_share_bounds_one_quarter_outflow() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, EMPLOYED_TO)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "干净夹具上的迁移不应返回故障码")

	var moved_out: int = mig.out_by_group()[g_from]
	ge_int(moved_out, 1,
			"工资优势 100%（1 000 → 2 000 μU）且三闸全松时必须有人迁出，否则迁移函数根本没接通（ADV-E01 失败诊断三）")
	le_int(moved_out, JWMath.mul_ppm(POP_FROM, MAX_SHARE_PPM),
			"单季迁出上限 = mul_ppm(1 000 000 人, 100 000 ppm) = 100 000 人（docs/12 §7.5 max_share）")
	le_int(moved_out, POP_FROM,
			"迁出人数不得超过该组人口本身（INV-072 禁止造人）")


# ── §7.5 触发条件与邻接约束 ───────────────────────────────────────────────

## 检验 §7.5 的 `if net_ppm < param.migration_threshold_ppm: continue`。
## 门槛拉满到 1e6 时，即使 net_ppm 达到上限 1e6 也不满足严格小于，
## 但把门槛设成 1e6 而 pull 因权重减半只有 5e5 时必须整季不迁移。
func test_threshold_blocks_weak_pull() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, EMPLOYED_TO)
	params[JWUnits.Param.MIGRATION_W_WAGE_PPM] = 500_000
	params[JWUnits.Param.MIGRATION_W_JOB_PPM] = 500_000
	params[JWUnits.Param.MIGRATION_THRESHOLD_PPM] = 1_000_000
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "未达门槛不是故障，不应返回故障码")

	eq_int(JWMath.sum(mig.out_by_group()), 0,
			"net_ppm = 500 000（工资 1e6 × 权重 5e5 + 职位优势 0）< 门槛 1 000 000，本季不得迁移（docs/12 §7.5）")
	eq_int(JWMath.sum(pop.f_migrate_rejected), 0,
			"未达门槛的对连意向都不产生，不应登记 migrate_rejected（docs/12 §7.5 先 continue 后算 intent）")


## 检验 OQ-208 / §7.5「只在邻接地区之间发生」：断开邻接后诱因再大也不迁移。
func test_non_adjacent_regions_never_exchange_population() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, EMPLOYED_TO)
	mig.adjacency = _zeros(JWUnits.OD_N)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "无邻接对可遍历不是故障，不应返回故障码")

	eq_int(JWMath.sum(mig.in_by_group()), 0,
			"adjacency 全 0 时不存在可遍历的邻接对，迁移必须为 0（docs/12 §7.5 / OQ-208）")
	eq_int(pop.region_population(R_TO), POP_TO,
			"无邻接即无迁入，中州人口应保持 100 000 人（INV-072）")


## 检验 INV-073 的对角线部分：迁移流不得出现同地区自环（migration_cost 对角线为 0，
## 若走到自环会连带触发 cap_cost 的除零）。
func test_no_self_loop_rows_in_migration_flow() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, EMPLOYED_TO)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "干净夹具上的迁移不应返回故障码")

	var self_loops: int = 0
	var i: int = 0
	while i < mig._row_count:
		if JWIds.region_of_group(mig.m_from[i]) == JWIds.region_of_group(mig.m_to[i]):
			self_loops += 1
		i += 1
	eq_int(self_loops, 0,
			"迁移只遍历邻接对，不得出现 r_from == r_to 的自环行（docs/12 §7.5 注释：对角线成本为 0）")
	ne_int(JWResult.pending_code(), JWResult.Fault.DIV_ZERO,
			"对角线迁移成本为 0，走到自环会在 cap_cost 处除零——不得出现 DIV_ZERO（docs/12 §7.5 注释）")


# ── INV-071 / INV-072 / INV-073 来源去向一致，禁止造人 ────────────────────

## 检验 `T-U-B-03` / INV-073：Σ 迁入 == Σ 迁出，且稀疏行与进出汇总逐组对账。
func test_migration_is_paired_row_by_row() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, EMPLOYED_TO)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "干净夹具上的迁移不应返回故障码")

	var in_by: PackedInt64Array = mig.in_by_group()
	var out_by: PackedInt64Array = mig.out_by_group()
	eq_int(JWMath.sum(in_by), JWMath.sum(out_by),
			"Σ 迁入必须等于 Σ 迁出（INV-073 / T-U-B-03）")
	ge_int(JWMath.sum(out_by), 1,
			"夹具意在产生真实迁移；迁移为 0 会让本条配对断言变成空转（T-U-B-03 夹具前提）")

	var rebuilt_in: PackedInt64Array = _zeros(JWUnits.GROUP)
	var rebuilt_out: PackedInt64Array = _zeros(JWUnits.GROUP)
	var i: int = 0
	while i < mig._row_count:
		rebuilt_out[mig.m_from[i]] += mig.m_persons[i]
		rebuilt_in[mig.m_to[i]] += mig.m_persons[i]
		i += 1
	eq_int_array(rebuilt_out, out_by,
			"稀疏迁移流按来源组汇总应逐位等于 out_by_group()（INV-073 的双边记账，不是两次单边写入）")
	eq_int_array(rebuilt_in, in_by,
			"稀疏迁移流按去向组汇总应逐位等于 in_by_group()（INV-073）")


## 检验 INV-071 / INV-072 / `ADV-E02`：迁移只搬运人口，既不造人也不杀人；
## 逐组 Δpop 必须精确等于 迁入 − 迁出。
func test_migration_conserves_population_group_by_group() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, EMPLOYED_TO)
	var before: PackedInt64Array = pop.population.duplicate()
	var national_before: int = JWMath.sum(before)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "干净夹具上的迁移不应返回故障码")

	eq_int(JWMath.sum(pop.population), national_before,
			"迁移不是出生也不是死亡，全国人口必须一位不变（INV-071：死亡是唯一净流出、出生是唯一净流入）")
	var in_by: PackedInt64Array = mig.in_by_group()
	var out_by: PackedInt64Array = mig.out_by_group()
	var expected: PackedInt64Array = _zeros(JWUnits.GROUP)
	var g: int = 0
	while g < JWUnits.GROUP:
		expected[g] = before[g] + in_by[g] - out_by[g]
		g += 1
	eq_int_array(pop.population, expected,
			"逐组人口必须精确等于 期初 + 迁入 − 迁出，容差 0（INV-072 / ADV-E01 断言块）")


## 检验 INV-073 与 `ADV-E02`：对称诱因下双向同季迁移，净人口变化为 0，
## 但两个方向的迁移成本照收——迁移不是免费的。
func test_symmetric_two_way_migration_creates_no_person() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, EMPLOYED_TO)
	# 两地工资指数相同 ⇒ wage_adv == 0；改由服务可及性对称拉动，双向 net_ppm 相等。
	pricing.wage = PackedInt64Array([WAGE_MID, WAGE_MID, WAGE_MID])
	params[JWUnits.Param.MIGRATION_W_WAGE_PPM] = 0
	params[JWUnits.Param.MIGRATION_W_SERVICE_PPM] = 1_000_000
	var service_access: PackedInt64Array = _zeros(JWUnits.GROUP_SVC_N)
	var g: int = 0
	while g < JWUnits.GROUP:
		var kind: int = 0
		while kind < JWUnits.SERVICE_KIND:
			service_access[JWIds.idx_group_svc(g, kind)] = 1_000_000
			kind += 1
		g += 1
	pop.service_access = service_access
	accounts.balance[JWIds.idx_account(JWIds.agent_of_group(g_to_home), JWIds.ACC_CASH)] = \
			3_000_000_000_000
	var national_before: int = JWMath.sum(pop.population)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "对称诱因不应产生故障码")

	eq_int(JWMath.sum(pop.population), national_before,
			"双向迁移必须是一次性双边记账；总人口变化即说明写成了先加后减的两趟循环（ADV-E02 失败诊断）")
	eq_int(JWMath.sum(mig.in_by_group()), JWMath.sum(mig.out_by_group()),
			"Σ 迁入 == Σ 迁出（INV-073）")


## 检验 §1.6 状态块协议：reset_flows() 之后本季迁移痕迹必须全部归零，
## 否则 S01 的 `flow_abs_sum != 0` 自检（Fault.FLOW_NOT_RESET）在下一季会漏判。
func test_reset_flows_clears_migration_rows() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, EMPLOYED_TO)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "干净夹具上的迁移不应返回故障码")
	ge_int(JWMath.sum(mig.out_by_group()), 1, "本测试前提：本季确实发生了迁移")

	mig.reset_flows()
	eq_int(mig.flow_abs_sum(), 0,
			"reset_flows() 后 flow_abs_sum() 必须为 0，否则 S01 会判 FLOW_NOT_RESET（docs/17 §1.6）")
	eq_int(JWMath.sum(mig.in_by_group()), 0, "reset_flows() 后进出汇总必须清零（docs/17 §1.6）")
	eq_int(JWMath.sum(mig.out_by_group()), 0, "reset_flows() 后进出汇总必须清零（docs/17 §1.6）")
	eq_int(mig._row_count, 0, "reset_flows() 后稀疏迁移流行数必须归零（docs/17 §4.16）")


# ── 计划书 §17 点名题：全员迁入一区是否仍享无限住房（ADV-04 / ADV-E01） ────

## 检验 `ADV-04` / `ADV-E01` / INV-083 / INV-084：
## 三个外围地区的劳动人口同时被中州的高工资吸引，连跑 20 季。
## 期望：住房容量是硬上限，中州人口封顶在 40 000 套 × 3 人/套 = 120 000 人；
## 每季 Σ occupied ≤ stock ≤ capacity；存量与容量一位不增；全国人口守恒；累计被挡回 > 0。
func test_all_workers_funnel_into_one_region_stay_within_housing_cap() -> void:
	_build_funnel_world()
	var national_before: int = JWMath.sum(pop.population)
	var stock_before: PackedInt64Array = capital.housing_stock.duplicate()
	var capacity_before: PackedInt64Array = capital.housing_capacity.duplicate()
	var cap_persons: int = 40_000 * PERSONS_PER_UNIT

	var over_cap_quarters: int = 0
	var first_over_cap_q: int = -1
	var first_over_cap_pop: int = 0
	var inv083_violations: int = 0
	var conservation_violations: int = 0
	var rejected_cum: int = 0

	var quarter: int = 0
	while quarter < 20:
		mig.reset_flows()
		pop.f_migrate_rejected = _zeros(JWUnits.GROUP)
		rng.begin_quarter(quarter)
		ledger.set_context(quarter, JWUnits.Phase.S07)
		var rc: int = _run()
		if rc != JWResult.OK:
			fail("第 %d 季迁移返回故障码 %d（20 季全程不应有故障）" % [quarter, rc])
			return
		rejected_cum += JWMath.sum(pop.f_migrate_rejected)
		if pop.region_population(R_TO) > cap_persons:
			over_cap_quarters += 1
			if first_over_cap_q < 0:
				first_over_cap_q = quarter
				first_over_cap_pop = pop.region_population(R_TO)
		var r: int = 0
		while r < JWUnits.R:
			if _sum_occupied_in_region(r) > capital.housing_stock[r]:
				inv083_violations += 1
			if capital.housing_stock[r] > capital.housing_capacity[r]:
				inv083_violations += 1
			r += 1
		if JWMath.sum(pop.population) != national_before:
			conservation_violations += 1
		quarter += 1

	eq_int(over_cap_quarters, 0,
			"中州人口不得超过住房承载上限 40 000 套 × 3 人/套 = 120 000 人；首次越界在第 %d 季，人口 %d（INV-083 / ADV-04 ①）"
			% [first_over_cap_q, first_over_cap_pop])
	eq_int(inv083_violations, 0,
			"每季每地区必须满足 Σ occupied ≤ housing_stock ≤ housing_capacity，违例数应为 0（INV-083 / ADV-04 ①）")
	eq_int(conservation_violations, 0,
			"20 季全程全国人口必须恒为 %d 人，违例季数应为 0（INV-071 / ADV-04 ③）" % national_before)
	eq_int_array(capital.housing_stock, stock_before,
			"住房存量只能由 P06 完工形成；迁移压力不得把它撑大一位（INV-084 / ADV-04 ④）")
	eq_int_array(capital.housing_capacity, capacity_before,
			"住房容量的非项目来源增量必须为 0（INV-084 / ADV-04 ④）")
	ge_int(rejected_cum, 1,
			"极端诱因下竟无一人被挡回，说明迁移函数根本没有住房闸门（ADV-E01 断言 assert_gt + 失败诊断三）")
	eq_int(pop.region_population(R_TO), cap_persons,
			"三地意向合计 ≥ 300 000 人而住房只放行 20 000 人，20 季后中州应恰好填满 120 000 人并停住——"
			+ "填不满说明住房闸算错了容量，填过头说明它根本不是硬上限（INV-083 / ADV-04 ①）")


## 三个低工资地区同时邻接高工资的中州；中州住房存量 40 000 套（承载 120 000 人），
## 初始 100 000 人，可容纳的净迁入总额只有 20 000 人，而三地意向合计 ≥ 120 000 人。
func _build_funnel_world() -> void:
	var population: PackedInt64Array = _zeros(JWUnits.GROUP)
	var participation: PackedInt64Array = _zeros(JWUnits.GROUP)
	var group_emp: PackedInt64Array = _zeros(JWUnits.GROUP_EMP_N)
	var occupied: PackedInt64Array = _zeros(JWUnits.GROUP)
	var cell_emp: PackedInt64Array = _zeros(JWUnits.EMP_N)
	var stock: PackedInt64Array = _zeros(JWUnits.R)
	var capacity: PackedInt64Array = _zeros(JWUnits.R)
	var adjacency: PackedInt64Array = _zeros(JWUnits.OD_N)
	var cost: PackedInt64Array = _zeros(JWUnits.OD_N)
	var balance: PackedInt64Array = _zeros(JWUnits.ACCOUNT_N)

	var sources: PackedInt64Array = PackedInt64Array([0, 2, 3])
	var i: int = 0
	while i < sources.size():
		var r: int = sources[i]
		var g: int = JWIds.idx_group(r, JWUnits.Age.WORKING, JWUnits.Skill.LOW)
		population[g] = POP_FROM
		participation[g] = PARTICIPATION_PPM
		group_emp[JWIds.idx_group_emp(g, JWUnits.Sector.SERVICES)] = EMPLOYED_FROM
		cell_emp[JWIds.idx_emp(JWIds.idx_cell(r, JWUnits.Sector.SERVICES), JWUnits.Skill.LOW)] = \
				EMPLOYED_FROM
		occupied[g] = OCCUPIED_FROM_UNITS
		stock[r] = STOCK_FROM_UNITS
		capacity[r] = STOCK_FROM_UNITS
		# 现金充裕：迁移成本不构成约束，逼住房闸独自承担（ADV-E01 要求的是住房硬上限）
		balance[JWIds.idx_account(JWIds.agent_of_group(g), JWIds.ACC_CASH)] = 3_000_000_000_000
		_link(r, R_TO, adjacency, cost)
		i += 1

	population[g_to_home] = POP_TO
	participation[g_to_home] = PARTICIPATION_PPM
	group_emp[JWIds.idx_group_emp(g_to_home, JWUnits.Sector.SERVICES)] = EMPLOYED_TO
	cell_emp[JWIds.idx_emp(JWIds.idx_cell(R_TO, JWUnits.Sector.SERVICES), JWUnits.Skill.HIGH)] = \
			EMPLOYED_TO
	occupied[g_to_home] = OCCUPIED_TO_UNITS
	stock[R_TO] = 40_000
	capacity[R_TO] = 40_000

	pop.population = population
	pop.participation_ppm = participation
	pop.employed = group_emp
	pop.housing_occupied = occupied
	pop.service_access = _zeros(JWUnits.GROUP_SVC_N)
	pop.f_migrate_rejected = _zeros(JWUnits.GROUP)
	labor.cell_employment = cell_emp
	labor.pub_employment = _zeros(JWUnits.PUBSERV_EMP_N)
	# 空缺充足：职位闸不参与，本用例只考住房闸（其余闸另有专门用例）
	labor.set("_vacancies_persons", 1_000_000)
	capital.housing_stock = stock
	capital.housing_capacity = capacity
	capital.env_exposure = _zeros(JWUnits.R)
	pricing.wage = PackedInt64Array([WAGE_LOW, WAGE_MID, WAGE_HIGH])
	mig.adjacency = adjacency
	mig.migration_cost = cost
	accounts.balance = balance


# ── 边界与恶意夹具：最容易出错的四个角落 ─────────────────────────────────

## 检验 §7.5 的 `cap_housing = max(0, ...)` 里那个 max：
## 迁入地已经住得超过承载上限（30 000 套 × 3 = 90 000 人 < 现有 100 000 人）时，
## 括号内为 −10 000。若实现漏了 max(0, ·)，min() 会取到负数 movers，
## 于是「迁移」会把人从迁入地倒吸回来——那是造人/灭人，不是迁移（INV-071/072/083）。
func test_cap_housing_clamped_to_zero_when_region_already_over_capacity() -> void:
	_world_two_region(30_000, 3_000_000_000_000, EMPLOYED_TO)
	var national_before: int = JWMath.sum(pop.population)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "已住满不是故障，不应返回故障码")

	eq_int(JWMath.sum(mig.out_by_group()), 0,
			"cap_housing = max(0, 30 000 × 3 − 100 000) = max(0, −10 000) = 0，不得有人迁入（docs/12 §7.5）")
	ge_int(JWMath.sum(mig.in_by_group()), 0,
			"迁入人数不得为负：负的 movers 意味着漏了 cap_housing 的 max(0, ·)（INV-084）")
	eq_int(pop.region_population(R_TO), POP_TO,
			"住满的地区人口必须一位不动，不得被负 movers 倒吸走（INV-072）")
	eq_int(pop.region_population(R_FROM), POP_FROM,
			"迁出地人口必须一位不动（INV-072）")
	eq_int(JWMath.sum(pop.population), national_before,
			"全国人口必须守恒（INV-071）")
	ge_int(pop.f_migrate_rejected[g_from], 1,
			"被住房闸全额挡回的意向必须登记（INV-084 / ADV-04 ②）")


## 检验 §7.5 的门槛是**严格小于**：`if net_ppm < threshold: continue`。
## net_ppm 恰好等于门槛时必须放行；写成 `<=` 就会在边界上少放一整批人。
func test_threshold_is_strict_less_than_at_boundary() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, EMPLOYED_TO)
	params[JWUnits.Param.MIGRATION_THRESHOLD_PPM] = 1_000_000
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "边界夹具不应返回故障码")

	ge_int(JWMath.sum(mig.out_by_group()), 1,
			"net_ppm = 1 000 000 恰等于门槛 1 000 000，条件是严格小于才跳过，因此必须放行（docs/12 §7.5）")


## 检验 §7.4 的分步语义：迁移是**跨地区**的一步，年龄与技能只能由成年／退休／结业改变。
## 若迁移顺手改了年龄档或技能档，INV-074（年龄有向）与 INV-082（技能只来自结业队列）被架空。
func test_movers_keep_age_and_skill_only_region_changes() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, EMPLOYED_TO)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "干净夹具上的迁移不应返回故障码")
	ge_int(mig._row_count, 1, "本测试前提：本季确实产生了迁移行")

	var age_changed: int = 0
	var skill_changed: int = 0
	var region_same: int = 0
	var i: int = 0
	while i < mig._row_count:
		var a: int = mig.m_from[i]
		var b: int = mig.m_to[i]
		if JWIds.age_of_group(a) != JWIds.age_of_group(b):
			age_changed += 1
		if JWIds.skill_of_group(a) != JWIds.skill_of_group(b):
			skill_changed += 1
		if JWIds.region_of_group(a) == JWIds.region_of_group(b):
			region_same += 1
		i += 1
	eq_int(age_changed, 0,
			"迁移不得改变年龄档：年龄只能由 §7.4 的成年／退休两步改变（INV-074）")
	eq_int(skill_changed, 0,
			"迁移不得改变技能档：技能升档只来自结业队列（INV-082 / INV-078）")
	eq_int(region_same, 0,
			"每一行迁移都必须跨地区（docs/12 §7.5 只遍历邻接对）")


## 检验 §7.5 的方向性：反向（高工资 → 低工资）的 pull 被 clamp 到 0，
## 因此本季不得出现任何 r_to → r_from 的迁移行。
func test_no_backflow_from_high_wage_to_low_wage_region() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, EMPLOYED_TO)
	accounts.balance[JWIds.idx_account(JWIds.agent_of_group(g_to_home), JWIds.ACC_CASH)] = \
			3_000_000_000_000
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "干净夹具上的迁移不应返回故障码")

	var backflow: int = 0
	var i: int = 0
	while i < mig._row_count:
		if JWIds.region_of_group(mig.m_from[i]) == R_TO:
			backflow += mig.m_persons[i]
		i += 1
	eq_int(backflow, 0,
			"中州→北原的 wage_adv = (1 000 − 2 000) × 1e6 / 2 000 = −500 000，pull clamp 到 0 < 门槛 1 000，不得有人回流（docs/12 §7.5）")
	eq_int(mig.out_by_group()[g_to_home], 0,
			"中州本地组不得有迁出（docs/12 §7.5 pull clamp 到 [0, 1e6]）")


## 检验 §7.5：三道闸全松时不得产生「幽灵拒绝」——movers == intent 时 rejected 必须精确为 0。
## intent = mul_ppm(1 000 000 人, 50 000 ppm) = 50 000 < cap_jobs 70 000 < cap_housing、cap_cost。
func test_no_phantom_rejection_when_all_three_gates_are_slack() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, 10_000)
	params[JWUnits.Param.MIGRATION_MAX_SHARE_PPM] = 50_000
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "干净夹具上的迁移不应返回故障码")

	eq_int(mig.out_by_group()[g_from], 50_000,
			"三闸全松时 movers 应等于 intent = mul_ppm(1 000 000 人, 50 000 ppm) = 50 000 人（docs/12 §7.5）")
	eq_int(JWMath.sum(pop.f_migrate_rejected), 0,
			"没有人被挡回时 migrate_rejected_persons 必须精确为 0，不得虚记（INV-084）")


## 检验 INV-072 的「不得超支」：组人口只有 5 人、放行比例拉满 100% 时，
## 迁出人数不得超过 5，迁出后人口不得为负。
func test_tiny_group_cannot_send_more_people_than_it_has() -> void:
	_world_two_region(1_000_000, 3_000_000_000_000, EMPLOYED_TO)
	params[JWUnits.Param.MIGRATION_MAX_SHARE_PPM] = 1_000_000
	var population: PackedInt64Array = pop.population.duplicate()
	population[g_from] = 5
	pop.population = population
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "小规模夹具不应返回故障码")

	le_int(mig.out_by_group()[g_from], 5,
			"迁出人数不得超过该组仅有的 5 人（INV-072：逐组来源去向齐全，禁止造人）")
	ge_int(pop.population[g_from], 0,
			"迁出后组人口不得为负（INV-072）")
	eq_int(pop.population[g_from] + mig.out_by_group()[g_from], 5,
			"期末人口 + 迁出 应恰为期初 5 人（INV-072，容差 0）")


## 检验 R-SCALE-01 的连带要求与 INV-006/INV-007：
## 现金取契约上界 AMOUNT_MAX = 4e15 μU 时，cap_cost 的整数除法与迁移成本的乘法
## 都不得登记 INT_OVERFLOW，且实际扣款必须精确等于 movers × 3 000 000 μU。
func test_cap_cost_at_amount_max_does_not_overflow() -> void:
	_world_two_region(1_000_000, JWUnits.AMOUNT_MAX, EMPLOYED_TO)
	var rc: int = _run()
	eq_int(rc, JWResult.OK, "契约上界现金不应返回故障码")

	ne_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW,
			"cap_cost = floor(4e15 / 3e6) 与 movers × 3e6 都在 int64 内，不得登记 INT_OVERFLOW（R-SCALE-01 连带要求 1）")
	var moved_out: int = mig.out_by_group()[g_from]
	ge_int(moved_out, 1, "本测试前提：现金充裕时必须有人迁出")
	eq_int(_cash_of_group(g_from), JWUnits.AMOUNT_MAX - moved_out * MIG_COST_UU,
			"扣款必须精确等于 movers × 迁移成本 3 000 000 μU/人（docs/12 §7.5 post(MIGRATION_COST)）")
