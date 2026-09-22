## 迁移的拉力／推力合成与三道硬闸（职位、住房、迁移成本），来源去向必须一致（INV-073）。
##
## 持有稀疏的迁移流列式记录：m_from / m_to / m_persons 三列等长，有效行数为 _row_count。
##
## 骨架依据：docs/17_api_skeleton.md §4.16。结算公式依据 docs/12 §7.5（逐字照抄）。
##
## 本类在 S07 内的三处写入，逐条说明依据：
##   (a) 稀疏三列与两个对账缓冲 —— 本类自有的 FLOW_*；
##   (b) `pop.f_migrate_rejected[]` —— docs/10 §6.1 与 population.gd 成员注释明写
##       「写入者 S07（由 JWMigration 写）」；
##   (c) `pop.population[]` 的**配对**增减 —— §7.4 第 6 步把迁移列为人口更新的一环，
##       而 JWPopulation.update_demography 只做前五步、check_conservation「不改状态」，
##       故 §7.4 第 7 步的 INV-072 要成立，迁移的人口落账只能由本类完成。
##       每一笔都是 `population[g_from] -= n` 与 `population[g_to] += n` 同时发生，
##       且与 `_out_by_group` / `_in_by_group` 同步，逐人对上，不新增也不消灭任何人。
class_name JWMigration
extends RefCounted

## 本类不持有任何 state.*（全部为 FLOW_*），STATE_ARRAY_SUBSYS 为空。
## 两张内容表（邻接、迁移成本）与 JWIoTable 的 content.io.* 同一口径登记：归 SUBSYS_META，
## 前缀 content. 使其**不进状态哈希、不进存档**（读档时随内容包重载），只为按稳定 ID 可读。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [JWUnits.SUBSYS_META, JWUnits.SUBSYS_META]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
const STATE_ARRAY_IDS: PackedStringArray = [
	"content.region.adjacency",
	"content.region.migration_cost_uu",
]

const STATE_SCALAR_IDS: PackedStringArray = []

## 稀疏迁移流的三列（m_from / m_to / m_persons）共用 docs/10 的同一个稳定 ID。
## 三列如何映射到 flow_array(i) 的下标尚未在骨架里定死，已登记接口变更请求（见返回值 interface_requests）。
## 在裁定之前，本类按「人数列是该稳定 ID 的正身，来源／去向两列是它的下标伴随列」实现：
## flow_array(0) 返回 m_persons，清零自检 flow_abs_sum() 覆盖全部五张数组与 _row_count。
const FLOW_ARRAY_IDS: PackedStringArray = [
	"flow.group.migrate_flow_persons",
]

const FLOW_SCALAR_IDS: PackedStringArray = []

# ── 流量（F 类，每季 S01 清零） ───────────────────────────────────────────────

## flow.group.migrate_flow_persons[] 的来源组列，长度 MIGRATION_CAP，组下标。写入者 S07。
var m_from: PackedInt64Array = PackedInt64Array()
## flow.group.migrate_flow_persons[] 的去向组列，长度 MIGRATION_CAP，组下标。写入者 S07。
var m_to: PackedInt64Array = PackedInt64Array()
## flow.group.migrate_flow_persons[] 的人数列，长度 MIGRATION_CAP，人。写入者 S07。
var m_persons: PackedInt64Array = PackedInt64Array()

## 本季已写入的稀疏行数（0 <= _row_count <= MIGRATION_CAP）。写入者 S07。
var _row_count: int = 0
## 36，人。本季迁入汇总，INV-073 的对账缓冲。写入者 S07。
var _in_by_group: PackedInt64Array = PackedInt64Array()
## 36，人。本季迁出汇总，INV-073 的对账缓冲。写入者 S07。
var _out_by_group: PackedInt64Array = PackedInt64Array()

# ── 内容（C 类，LOAD 期写入，运行期只读） ─────────────────────────────────────

## content.region.adjacency[]，16（R × R），0/1，对称无自环。写入者 LOAD。
var adjacency: PackedInt64Array = PackedInt64Array()
## content.region.migration_cost_uu[]，16（R × R），μU/人。写入者 LOAD。
var migration_cost: PackedInt64Array = PackedInt64Array()

# ── 内部 scratch（标量，不进 state_hash，不在热路径分配） ─────────────────────

## 本季尚未被占用的空缺岗位预算（人）。run() 入口从 JWLaborMarket 取一次，逐笔递减。
## 这是「职位硬闸」在缺少逐地区空缺读数时的**收紧**实现，见 _cap_jobs() 的说明。
var _jobs_budget: int = 0


## S07 §7.5：按邻接对遍历，合成净拉力，过三道硬闸，写配对的迁移流并支付迁移成本。
## 步骤：S07 §7.5
## 前置：本季 update_demography 已完成；只在邻接地区之间发生（OQ-208）；
##       遍历顺序按 (r_from, r_to) 下标升序（确定性）
## 后置：movers = min(intent, cap_jobs, cap_housing, cap_cost)；
##       被挡回人数写 migrate_rejected_persons；post(kind=MIGRATION_COST, group → cell.services[r_to])
## 不变量：INV-073（migrate_out[a][b] == migrate_in[b][a] 且 Σ 进 == Σ 出）、
##          INV-083（住房硬上限）、INV-084（被挡回必须显式登记，容量不得自动增长）
## 失败：进出不配对 → Fault.MIGRATION_UNPAIRED；住房被突破 → Fault.HOUSING_OVERFLOW
##
## `rng` 形参保留而不使用：§7.5 是纯确定性规则，一次都不抽样（抽样会让重放依赖 draw_count 的
## 调用次序，INV-009/INV-014 的代价远大于收益）。签名不得改，故留形参。
func run(pop: JWPopulation, labor: JWLaborMarket, capital: JWCapital, pricing: JWPricing,
		ledger: JWLedger, accounts: JWAccount, rng: JWRngStreams,
		params: PackedInt64Array) -> int:
	if pop == null or labor == null or capital == null or pricing == null \
			or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 0)
	if params.size() < JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	if adjacency.size() != JWUnits.OD_N or migration_cost.size() != JWUnits.OD_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				adjacency.size(), JWUnits.OD_N)
	if m_from.size() != JWUnits.MIGRATION_CAP or m_to.size() != JWUnits.MIGRATION_CAP \
			or m_persons.size() != JWUnits.MIGRATION_CAP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				m_persons.size(), JWUnits.MIGRATION_CAP)
	if _in_by_group.size() != JWUnits.GROUP or _out_by_group.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				_in_by_group.size(), JWUnits.GROUP)
	if pop.population.size() != JWUnits.GROUP or pop.f_migrate_rejected.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pop.population.size(), JWUnits.GROUP)

	var threshold_ppm: int = params[JWUnits.Param.MIGRATION_THRESHOLD_PPM]
	var max_share_ppm: int = params[JWUnits.Param.MIGRATION_MAX_SHARE_PPM]
	var persons_per_unit: int = params[JWUnits.Param.PERSONS_PER_HOUSING_UNIT]
	# 本季职位预算：空缺是「本季已经算清的存量」，不随迁移自动增长（INV-084）。
	_jobs_budget = labor.vacancies_persons()
	if _jobs_budget < 0:
		_jobs_budget = 0
	# 本季有迁入的地区位掩码（位 r == 1 表示 r 收过人）。用位掩码而不是临时数组：
	# 热路径不新建对象（docs/17 §1.4）。
	var received_mask: int = 0

	var r_from: int = 0
	while r_from < JWUnits.R:
		var r_to: int = 0
		while r_to < JWUnits.R:
			# 只在邻接地区之间发生（OQ-208）；自环在内容校验 V-REG-02 处已被排除，此处再挡一次。
			if r_from == r_to or adjacency[JWIds.idx_od(r_from, r_to)] == 0:
				r_to += 1
				continue
			var net_ppm: int = _net_ppm(pop, labor, capital, pricing, r_from, r_to, params)
			if net_ppm < threshold_ppm:
				r_to += 1
				continue
			var share_ppm: int = net_ppm
			if share_ppm > max_share_ppm:
				share_ppm = max_share_ppm
			if share_ppm <= 0:
				r_to += 1
				continue
			var cost_uu: int = migration_cost[JWIds.idx_od(r_from, r_to)]
			# 只有劳动年龄组迁移：三道硬闸的第一道就是「目的地的职位」，
			# 未成年与老年组既不占职位也不自带工资拉力；他们的消费资金来自区内赡养转移
			# （docs/10 §6.2 的裁定 + OQ-208：跨地区赡养首版为 0），随人迁走无处落账。
			# 迁移者的年龄档与技能档不变（INV-074 年龄有向、INV-078 不允许技能替代）。
			var k: int = 0
			while k < JWUnits.K:
				var g_from: int = JWIds.idx_group(r_from, JWUnits.Age.WORKING, k)
				var g_to: int = JWIds.idx_group(r_to, JWUnits.Age.WORKING, k)
				var rows_before: int = _row_count
				var rc: int = _move_pair(pop, capital, ledger, accounts, g_from, g_to,
						r_to, share_ppm, cost_uu, persons_per_unit)
				if rc != JWResult.OK:
					return rc
				# 只有真的写了一行（movers > 0）才把目的地记入「本季有迁入」。
				if _row_count > rows_before:
					received_mask = received_mask | (1 << r_to)
				k += 1
			r_to += 1
		r_from += 1

	var rc_pair: int = _check_pairing()
	if rc_pair != JWResult.OK:
		return rc_pair
	return _check_housing(pop, capital, persons_per_unit, received_mask)


## 单个（来源组 → 去向组）的三道硬闸与落账。docs/12 §7.5 的循环体。
## 步骤：S07 §7.5
## 前置：g_from / g_to 是同年龄同技能、分属两个相邻地区的组；share_ppm ∈ (0, 1 000 000]
## 后置：movers = min(intent, cap_jobs, cap_housing, cap_cost)；
##       intent − movers 写 f_migrate_rejected[g_from]；movers 同时写三列、两个对账缓冲与人口两端
## 不变量：INV-073、INV-083、INV-084、INV-016（现金不为负，由 post 保证）
## 失败：行数超 MIGRATION_CAP → INDEX_OUT_OF_RANGE；过账失败 → 原样返回 post 的故障码
func _move_pair(pop: JWPopulation, capital: JWCapital, ledger: JWLedger, accounts: JWAccount,
		g_from: int, g_to: int, r_to: int, share_ppm: int, cost_uu: int,
		persons_per_unit: int) -> int:
	var eligible: int = pop.population[g_from]
	if eligible <= 0:
		return JWResult.OK
	# rounding: floor, reason=M1，意愿人数只取整一次，少给优于凭空多给
	var intent: int = JWMath.mul_ppm(eligible, share_ppm)
	if intent > eligible:
		intent = eligible
	if intent <= 0:
		return JWResult.OK

	var movers: int = intent
	# 硬闸一：职位。
	var cap_jobs: int = _cap_jobs()
	if cap_jobs < movers:
		movers = cap_jobs
	# 硬闸二：住房（ADV-04 的防线；容量不会自动增长）。
	var cap_housing: int = JWMath.mul(capital.housing_stock_of(r_to), persons_per_unit) \
			- pop.region_population(r_to)
	if cap_housing < 0:
		cap_housing = 0
	if cap_housing < movers:
		movers = cap_housing
	# 硬闸三：迁移成本（成本为 0 的 OD 对不设资金闸；对角与非邻接根本走不到这里）。
	if cost_uu > 0:
		var cash_uu: int = accounts.cash_of(JWIds.agent_of_group(g_from))
		# rounding: floor, reason=能出得起的人数不得多算，余额不足一人的零头不构成一次迁移
		var cap_cost: int = JWMath.floor_div(cash_uu, cost_uu)
		if cap_cost < movers:
			movers = cap_cost
	if movers < 0:
		movers = 0

	# 被挡回必须显式登记（INV-084）。先登记再落账：任何一道闸挡下的人都留痕。
	var rejected: int = intent - movers
	if rejected > 0:
		pop.f_migrate_rejected[g_from] = pop.f_migrate_rejected[g_from] + rejected
	if movers == 0:
		return JWResult.OK
	# 稀疏表容量在**过账之前**核：先收钱再发现写不下行，就成了收了钱没迁人的静默改账。
	if _row_count >= JWUnits.MIGRATION_CAP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				_row_count, JWUnits.MIGRATION_CAP)

	# 迁移成本是真实支出：群组现金 → 目的地服务 cell（docs/11 §5.3 kind 25：sale_final / C）。
	if cost_uu > 0:
		var amount_uu: int = JWMath.mul(movers, cost_uu)
		if amount_uu > JWUnits.AMOUNT_MAX:
			return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW,
					amount_uu, JWUnits.AMOUNT_MAX)
		var payer: int = JWIds.idx_account(JWIds.agent_of_group(g_from), JWIds.ACC_CASH)
		var payee_cell: int = JWIds.idx_cell(r_to, JWUnits.Sector.SERVICES)
		var payee: int = JWIds.idx_account(JWIds.agent_of_cell(payee_cell), JWIds.ACC_CASH)
		# qty_uqs = 0：§7.5 只给了金额口径，没有给对应的实物量；不自造「量 × 价」。
		# cause = -1：本笔由规则驱动，没有政策／项目／事件来源操作码。
		# entity_ref = g_from：相关实体是付款的群组（docs/10 §2.5 第 9 列）。
		var rc: int = ledger.post(JWUnits.Kind.MIGRATION_COST, payer, payee, amount_uu,
				0, JWUnits.Sector.SERVICES, -1, g_from)
		if rc != JWResult.OK:
			# 现金闸已经保证过付得起；到这里仍失败说明账实不符，不缩规模、不改账，直接上抛。
			return rc

	m_from[_row_count] = g_from
	m_to[_row_count] = g_to
	m_persons[_row_count] = movers
	_row_count += 1
	_out_by_group[g_from] = _out_by_group[g_from] + movers
	_in_by_group[g_to] = _in_by_group[g_to] + movers
	# 人口的配对转移：来源减、去向加，同一笔同一个数，禁止造人。
	pop.population[g_from] = pop.population[g_from] - movers
	pop.population[g_to] = pop.population[g_to] + movers
	_jobs_budget -= movers
	return JWResult.OK


## 硬闸一的读数：本季尚未被占用的空缺岗位数。
## 步骤：S07 §7.5
## 前置：run() 入口已把 _jobs_budget 置为本季空缺总数
## 后置：不改状态
## 不变量：INV-084（容量不得自动增长）
## 失败：无
##
## 契约写的是「r_to 的**空缺岗位数**」，但 JWLaborMarket 首版只暴露全国口径
## （`vacancies_persons()`，docs/17 §4.15 无逐地区读数），已登记接口请求
## `vacancies_in_region(r)`。在它落地之前，本类把全国空缺当作**全季共享的预算**，
## 按 (r_from, r_to, skill) 升序逐笔扣减：
## Σ_r 逐地区空缺 == 全国空缺，故「Σ 全部迁移 ≤ 全国空缺」是逐地区硬闸的必要条件，
## 这样取的结果只会比真闸更紧或相等，绝不会放行超过全国空缺的迁移。
## 这是**显式收紧**，不是静默放宽；换成逐地区读数后本函数是唯一改动点。
func _cap_jobs() -> int:
	if _jobs_budget < 0:
		return 0
	return _jobs_budget


## 净拉力（拉力减推力，ppm）。docs/12 §7.5 的前半段，逐字照抄。
## 步骤：S07 §7.5
## 前置：r_from / r_to 相邻且不相等
## 后置：不改状态；返回值 ∈ [−1 000 000, 1 000 000]
## 不变量：INV-005（换算只取整一次）
## 失败：无（分母为 0 一律取 max(·, 1)）
func _net_ppm(pop: JWPopulation, labor: JWLaborMarket, capital: JWCapital, pricing: JWPricing,
		r_from: int, r_to: int, params: PackedInt64Array) -> int:
	var wage_from: int = labor.region_wage_index(pricing, r_from)
	var wage_to: int = labor.region_wage_index(pricing, r_to)
	var wage_den: int = wage_from
	if wage_den < 1:
		wage_den = 1
	# rounding: floor, reason=R-SCALE-01，工资已是 μU 量级，先乘后除一律走 mul_div_floor
	var wage_adv_ppm: int = JWMath.clamp_i(
			JWMath.mul_div_floor(wage_to - wage_from, JWUnits.PPM, wage_den),
			-JWUnits.PPM, JWUnits.PPM)
	var job_adv_ppm: int = JWMath.clamp_i(
			_unemp_ppm(pop, labor, r_from) - _unemp_ppm(pop, labor, r_to),
			-JWUnits.PPM, JWUnits.PPM)
	var service_adv_ppm: int = JWMath.clamp_i(
			_service_access_ppm(pop, r_to) - _service_access_ppm(pop, r_from),
			-JWUnits.PPM, JWUnits.PPM)
	# R-MIGRATE-01：推力与拉力同为「目的地 − 来源地」的相对量。原式把目的地的住房占用率（≈ 0.9—1.0）
	# 与环境暴露当作**水平值**扣减，而拉力是**差值**（±10% 量级）：净拉力恒在 −0.87…−1.0，
	# 迁移在任何局面下都触发不了（×0.5 / ×2 迁移速度的敏感性结果逐位相同）。
	var house_adv_ppm: int = JWMath.clamp_i(
			housing_stress_ppm(pop, capital, r_to) - housing_stress_ppm(pop, capital, r_from),
			-JWUnits.PPM, JWUnits.PPM)
	var env_adv_ppm: int = JWMath.clamp_i(
			_env_exposure_ppm(capital, r_to) - _env_exposure_ppm(capital, r_from),
			-JWUnits.PPM, JWUnits.PPM)
	var pull_ppm: int = JWMath.mul_ppm(wage_adv_ppm, params[JWUnits.Param.MIGRATION_W_WAGE_PPM]) 			+ JWMath.mul_ppm(job_adv_ppm, params[JWUnits.Param.MIGRATION_W_JOB_PPM]) 			+ JWMath.mul_ppm(service_adv_ppm, params[JWUnits.Param.MIGRATION_W_SERVICE_PPM])
	var push_ppm: int = JWMath.mul_ppm(house_adv_ppm, params[JWUnits.Param.MIGRATION_W_HOUSE_PPM]) 			+ JWMath.mul_ppm(env_adv_ppm, params[JWUnits.Param.MIGRATION_W_ENV_PPM])
	return JWMath.clamp_i(pull_ppm - push_ppm, -JWUnits.PPM, JWUnits.PPM)


## 地区失业率（ppm）：该地区失业人数 × 1e6 / 该地区劳动力，向下取整。
## 步骤：S07 §7.5
## 前置：本季 S03 的就业匹配已完成
## 后置：不改状态；返回 [0, 1 000 000]
## 不变量：INV-075（分母是劳动力）、INV-076（在岗不超过劳动力）
## 失败：无（劳动力为 0 → 取 max(·, 1)，返回 0）
func _unemp_ppm(pop: JWPopulation, labor: JWLaborMarket, r: int) -> int:
	var labor_force: int = 0
	var employed: int = 0
	var k: int = 0
	while k < JWUnits.K:
		labor_force += pop.labor_force_region_skill(r, k)
		var s: int = 0
		while s < JWUnits.S:
			employed += labor.employment(JWIds.idx_cell(r, s), k)
			s += 1
		employed += labor.pubserv_employment(r, k)
		k += 1
	var unemployed: int = labor_force - employed
	if unemployed < 0:
		unemployed = 0
	var den: int = labor_force
	if den < 1:
		den = 1
	# rounding: floor, reason=docs/12 §7.5 明写 idiv_floor
	return JWMath.clamp_i(JWMath.mul_div_floor(unemployed, JWUnits.PPM, den), 0, JWUnits.PPM)


## 地区服务可及性（ppm）：组内先按三类服务取算术平均，再按组人口加权平均。
## 步骤：S07 §7.5
## 前置：pop.service_access 长度 GROUP_SVC_N
## 后置：不改状态；返回 [0, 1 000 000]
## 不变量：INV-103、R-ACCESS-01（各组可以不同，区间 0..1 000 000）
## 失败：数组长度不符或该地区人口为 0 → 返回 0（不除零，也不假装满分）
func _service_access_ppm(pop: JWPopulation, r: int) -> int:
	if pop.service_access.size() != JWUnits.GROUP_SVC_N:
		return 0
	var num: int = 0
	var den: int = 0
	var a: int = 0
	while a < JWUnits.A:
		var k: int = 0
		while k < JWUnits.K:
			var g: int = JWIds.idx_group(r, a, k)
			var acc: int = 0
			var kind: int = 0
			while kind < JWUnits.SERVICE_KIND:
				acc += pop.service_access[JWIds.idx_group_svc(g, kind)]
				kind += 1
			# rounding: floor, reason=三类服务的组内平均，只取整一次
			var avg_ppm: int = JWMath.floor_div(acc, JWUnits.SERVICE_KIND)
			var persons: int = pop.population[g]
			num += JWMath.mul(persons, avg_ppm)
			den += persons
			k += 1
		a += 1
	if den < 1:
		return 0
	# rounding: floor, reason=人口加权平均的唯一一次取整
	return JWMath.clamp_i(JWMath.floor_div(num, den), 0, JWUnits.PPM)


## 目的地环境暴露（ppm，推力输入）。
## 步骤：S07 §7.5
## 前置：capital.env_exposure 已由上一季 S07 §7.9 写入
## 后置：不改状态；返回 [0, 3 000 000]（区间见 docs/10 §7）
## 不变量：INV-057
## 失败：数组长度不符 → 返回 0
func _env_exposure_ppm(capital: JWCapital, r: int) -> int:
	if r < 0 or r >= capital.env_exposure.size():
		return 0
	return capital.env_exposure[r]


## INV-073 的收尾对账：三列之和 == Σ 迁入 == Σ 迁出，且每行来源去向成对。
## 步骤：S07 §7.5 末
## 前置：本季全部迁移已落账
## 后置：不改状态
## 不变量：INV-073
## 失败：任一项不符 → Fault.MIGRATION_UNPAIRED
func _check_pairing() -> int:
	var rows_total: int = 0
	var i: int = 0
	while i < _row_count:
		var n: int = m_persons[i]
		if n <= 0:
			return JWResult.raise_fault(JWResult.Fault.MIGRATION_UNPAIRED, i, n)
		var g_from: int = m_from[i]
		var g_to: int = m_to[i]
		if g_from == g_to or g_from < 0 or g_from >= JWUnits.GROUP \
				or g_to < 0 or g_to >= JWUnits.GROUP:
			return JWResult.raise_fault(JWResult.Fault.MIGRATION_UNPAIRED, g_from, g_to)
		# 迁移不改变年龄档与技能档：来源与去向必须是同一类人（INV-074、INV-078）。
		if JWIds.age_of_group(g_from) != JWIds.age_of_group(g_to) \
				or JWIds.skill_of_group(g_from) != JWIds.skill_of_group(g_to):
			return JWResult.raise_fault(JWResult.Fault.MIGRATION_UNPAIRED, g_from, g_to)
		rows_total += n
		i += 1
	var in_total: int = JWMath.sum(_in_by_group)
	var out_total: int = JWMath.sum(_out_by_group)
	if in_total != out_total:
		return JWResult.raise_fault(JWResult.Fault.MIGRATION_UNPAIRED, in_total, out_total)
	if rows_total != in_total:
		return JWResult.raise_fault(JWResult.Fault.MIGRATION_UNPAIRED, rows_total, in_total)
	return JWResult.OK


## 住房硬闸的收尾核对：本季有迁入的地区，其人口不得超过 housing_stock × persons_per_unit。
## 步骤：S07 §7.5 末
## 前置：本季全部迁移已落账
## 后置：不改状态
## 不变量：INV-083（住房硬上限）、INV-084（容量不得自动增长）
## 失败：被突破 → Fault.HOUSING_OVERFLOW（cap_housing 之后仍发生即缺陷）
##
## 只核这一条、且只核有迁入的地区：`Σ occupied ≤ stock ≤ capacity` 的另两截由住房存量的
## 写入者（JWCapital / 载入期 V-REG-03）负责。本类一位都不写 housing_occupied，
## 把目的地**既有**的拥挤算到迁移头上会让故障包指向错误的第一现场（docs/12 §9）。
func _check_housing(pop: JWPopulation, capital: JWCapital, persons_per_unit: int,
		received_mask: int) -> int:
	var r: int = 0
	while r < JWUnits.R:
		if (received_mask & (1 << r)) != 0:
			var stock: int = capital.housing_stock_of(r)
			var persons: int = pop.region_population(r)
			var limit: int = JWMath.mul(stock, persons_per_unit)
			if persons > limit:
				return JWResult.raise_fault(JWResult.Fault.HOUSING_OVERFLOW, persons, limit)
		r += 1
	return JWResult.OK


## 地区已占用住房（套）：derived.region.housing_occupied_units[r] 的就地求和。
## 步骤：S07 §7.5
## 前置：pop.housing_occupied 长度 GROUP
## 后置：不改状态
## 不变量：INV-083
## 失败：长度不符 → 返回 0
func _housing_occupied(pop: JWPopulation, r: int) -> int:
	if pop.housing_occupied.size() != JWUnits.GROUP:
		return 0
	var acc: int = 0
	var a: int = 0
	while a < JWUnits.A:
		var k: int = 0
		while k < JWUnits.K:
			acc += pop.housing_occupied[JWIds.idx_group(r, a, k)]
			k += 1
		a += 1
	return acc


## 本季迁移的迁入汇总（供 JWPopulation.check_conservation 复核）。
## 步骤：S07 §7.4 第 7 步
## 前置：run() 已完成
## 后置：不改状态
## 不变量：INV-073
## 失败：无
func in_by_group() -> PackedInt64Array:
	return _in_by_group


## 本季迁移的迁出汇总（供 JWPopulation.check_conservation 复核）。
## 步骤：S07 §7.4 第 7 步
## 前置：run() 已完成
## 后置：不改状态
## 不变量：INV-073
## 失败：无
func out_by_group() -> PackedInt64Array:
	return _out_by_group


## 住房紧张度（迁移推力输入，也是 JWPricing 的租金输入）。
## 步骤：S07 §7.5 / §7.3
## 前置：capital 的住房存量与 pop 的占用量已更新
## 后置：不改状态；返回 [0, 1 000 000]
## 不变量：INV-083
## 失败：capacity == 0 → 返回 1_000_000（满）
##
## 分母取 housing_capacity_units：docs/12 §7.5 写的是 `max(capacity, 1)`，
## 与 JWPricing.update_housing_rent(occupied_units, capacity_units, …) 的口径一致。
func housing_stress_ppm(pop: JWPopulation, capital: JWCapital, r: int) -> int:
	if pop == null or capital == null:
		return JWUnits.PPM
	var capacity: int = capital.housing_capacity_of(r)
	if capacity <= 0:
		return JWUnits.PPM
	var occupied: int = _housing_occupied(pop, r)
	# rounding: floor, reason=docs/12 §7.5 明写 idiv_floor(occupied × 1e6, max(capacity, 1))
	return JWMath.clamp_i(JWMath.mul_div_floor(occupied, JWUnits.PPM, capacity),
			0, JWUnits.PPM)


# ── §1.6 状态块协议（全部为 FLOW_*，子系统 SUBSYS_GROUP） ────────────────────

## LOAD 期一次性把本块各数组 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：尚未分配；只允许 JWContentLoader / JWSaves 调用
## 后置：全部数组长度等于契约长度，内容为 0；此后不再 resize
## 不变量：INV-136（数组顺序与长度是 schema 的一部分）
## 失败：无（长度不符在载入校验处报 Load.UNIT_MISMATCH）
func allocate() -> void:
	m_from.resize(JWUnits.MIGRATION_CAP)
	m_from.fill(0)
	m_to.resize(JWUnits.MIGRATION_CAP)
	m_to.fill(0)
	m_persons.resize(JWUnits.MIGRATION_CAP)
	m_persons.fill(0)
	_row_count = 0
	_in_by_group.resize(JWUnits.GROUP)
	_in_by_group.fill(0)
	_out_by_group.resize(JWUnits.GROUP)
	_out_by_group.fill(0)
	adjacency.resize(JWUnits.OD_N)
	adjacency.fill(0)
	migration_cost.resize(JWUnits.OD_N)
	migration_cost.fill(0)
	_jobs_budget = 0


## 只读取用某个状态数组（本类无 state.*，恒返回空数组）。
## 步骤：LOAD、哈希、存档
## 前置：0 <= i < STATE_ARRAY_IDS.size()
## 后置：不改状态
## 不变量：INV-136
## 失败：任意下标都越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return adjacency
	if i == 1:
		return migration_cost
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## 写入某个状态数组（仅 LOAD / MIG；本类无 state.*）。
## 步骤：LOAD、MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd；长度与契约一致
## 后置：对应成员被整体替换
## 不变量：INV-136
## 失败：越界或长度不符 → 返回非 0 故障码
##
## `adjacency` / `migration_cost` 是 **content.***，不在 STATE_ARRAY_IDS 里（那张表按契约为空），
## 因此不经本通道：它们与 JWPopulation.birth_ppm、JWCapital 的内容表一样，
## 由 JWContentLoader 在 LOAD 期直接整体赋值给公开成员（长度由本类 run() 入口再核一次）。
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if (i == 0 or i == 1) and v.size() != JWUnits.OD_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), JWUnits.OD_N)
	if i == 0:
		adjacency = v.duplicate()
		return JWResult.OK
	if i == 1:
		migration_cost = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())


## 读取某个状态标量（本类无状态标量，恒返回 0）。
## 步骤：LOAD、哈希、存档
## 前置：0 <= i < STATE_SCALAR_IDS.size()
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func state_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## 写入某个状态标量（仅 LOAD / MIG；本类无状态标量）。
## 步骤：LOAD、MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd
## 后置：无
## 不变量：INV-136
## 失败：任意下标都越界 → 返回非 0 故障码
func set_state_scalar(i: int, v: int) -> int:
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v)


## 只读取用某个流量数组。
## 步骤：哈希、诊断
## 前置：0 <= i < FLOW_ARRAY_IDS.size()
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func flow_array(i: int) -> PackedInt64Array:
	if i == 0:
		return m_persons
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## 读取某个流量标量（本类无流量标量，恒返回 0）。
## 步骤：哈希、诊断
## 前置：0 <= i < FLOW_SCALAR_IDS.size()
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## 仅 S01：把全部 FLOW_* 归零（含 _row_count 与两个对账缓冲）。
## 步骤：S01 §01.3
## 前置：调用点位于 systems/turn_runner.gd 的 _step_s01 内
## 后置：三列、两个对账缓冲逐位为 0，_row_count == 0
## 不变量：INV-013（流量每季清零）、INV-073
## 失败：无（清零失败由 flow_abs_sum() 在其后检出）
func reset_flows() -> void:
	m_from.fill(0)
	m_to.fill(0)
	m_persons.fill(0)
	_in_by_group.fill(0)
	_out_by_group.fill(0)
	_row_count = 0
	_jobs_budget = 0


## S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 刚刚执行
## 后置：不改状态
## 不变量：INV-013
## 失败：返回非 0 由调用方判为 Fault.FLOW_NOT_RESET
func flow_abs_sum() -> int:
	var acc: int = JWMath.sum_abs(m_from)
	acc += JWMath.sum_abs(m_to)
	acc += JWMath.sum_abs(m_persons)
	acc += JWMath.sum_abs(_in_by_group)
	acc += JWMath.sum_abs(_out_by_group)
	acc += JWMath.absi(_row_count)
	return acc


## §1.6 状态块协议：读档时写回流量数组（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_array 逐项对称生成）。
## 步骤：LOAD（JWSaves 经 JWSimState 调用）
## 前置：v 的长度与本块当前分配的长度一致（长度是 schema 的一部分，INV-136）
## 后置：对应成员被整体替换
## 不变量：INV-133（读档后与原进程逐位相同）
## 失败：下标越界或长度不符 → INDEX_OUT_OF_RANGE
func set_flow_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != m_persons.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		m_persons = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
