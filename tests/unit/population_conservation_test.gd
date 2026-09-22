## 人口守恒、出生死亡、年龄队列、技能队列、就业口径与失业率反算的单元测试。
##
## 依据（按优先级）：docs/18 裁定、docs/12 §3.2/§3.4/§7.4/§7.6/§7.7、
## docs/10 §14.6（INV-071…INV-086）、docs/11 §5.7（PopulationInit 与失业率反算链）、
## docs/30 §3 类别 B（T-U-B-02/03/05/06/07/08/12、T-S-B-01）、
## docs/31 §6 E 族（ADV-E03/E04/E05/E06，即计划书点名的 ADV-03/ADV-04 一侧）。
##
## 本文件**不读实现代码**：夹具与期望值全部由上述契约推出。夹具刻意选取
## 「人口全部是 50 000 的整数倍、比率全部能整除」的数，使 mul_ppm 的取整方向
## 不影响期望值——这样断言失败一定是机制错，不是取整口径之争。
##
## 夹具的三个关键数（自身也被断言复核，见 test_fixture_is_calibrated）：
##   Σ 人口       == 24 000 000（4 地区 9/7/5/3 百万，与 docs/11 V-POP-02 同口径）
##   Σ 劳动力     == 10 500 000
##   Σ 在岗       ==  9 660 000  ⇒ 失业 840 000 ⇒ 失业率恰好 80 000 ppm（8%）
extends JWTest

# ── 夹具常量 ───────────────────────────────────────────────────────────────

## 36 组初始人口，下标 == JWIds.idx_group(r, a, k) == r*9 + a*3 + k。
## 全部为 50 000 的整数倍：与下面的出生／死亡／成年比率相乘后都能被 1e6 整除。
const POP_INIT: PackedInt64Array = [
	1_200_000, 600_000, 300_000,       # 北原 未成年 低/中/高
	2_600_000, 1_800_000, 900_000,     # 北原 劳动   低/中/高
	900_000, 450_000, 250_000,         # 北原 老年   低/中/高
	900_000, 500_000, 250_000,         # 中州 未成年
	2_000_000, 1_400_000, 700_000,     # 中州 劳动
	750_000, 350_000, 150_000,         # 中州 老年
	650_000, 350_000, 200_000,         # 海岬 未成年
	1_400_000, 1_000_000, 500_000,     # 海岬 劳动
	500_000, 250_000, 150_000,         # 海岬 老年
	400_000, 200_000, 100_000,         # 西岭 未成年
	850_000, 600_000, 300_000,         # 西岭 劳动
	300_000, 150_000, 100_000,         # 西岭 老年
]

## 逐地区人口合计（docs/11 V-POP-02 的同一口径）。
const REGION_TOTAL: PackedInt64Array = [9_000_000, 7_000_000, 5_000_000, 3_000_000]
const NATION_TOTAL: int = 24_000_000

## 劳动参与率，按技能档（只给 working 组；minor / elder 恒为 0，INV-074）。
const PART_PPM: PackedInt64Array = [720_000, 760_000, 800_000]

## 季度死亡率，按年龄档（取自剧本 content/scenarios/chengwan 的量级）。
const DEATH_PPM_BY_AGE: PackedInt64Array = [80, 320, 20_000]

## 季度出生率，按地区。基数是该地区的 **working 口径人口**（docs/12 §7.4 第 2 步）。
const BIRTH_PPM_BY_REGION: PackedInt64Array = [5_400, 4_400, 4_600, 4_800]

## 季度成年／退休率，按年龄档：minor→working、working→elder；elder 不再流出（INV-074）。
const AGE_OUT_PPM_BY_AGE: PackedInt64Array = [12_500, 5_400, 0]

## 在岗人数占劳动力的比例：92% ⇒ 失业率恰好 8%（docs/12 §3.4 的验收区间中值）。
const EMPLOY_RATE_PPM: int = 920_000

## 组内在岗人数在 4 部门 + pubserv 五个槽位上的拆分权重（split_lr 保证和精确相等）。
const EMP_SLOT_WEIGHT: PackedInt64Array = [40, 30, 10, 15, 5]

const EXPECTED_LABOR_FORCE_TOTAL: int = 10_500_000
const EXPECTED_EMPLOYED_TOTAL: int = 9_660_000
const EXPECTED_UNEMPLOYED_TOTAL: int = 840_000
const EXPECTED_UNEMPLOYMENT_PPM: int = 80_000

## 教育队列夹具参数（本测试自选；参数注册表尚未登记取值，见 open_questions）。
const TRAINING_LAG_Q: int = 4
const STUDENT_TEACHER_RATIO: int = 20
const TEACHERS_BY_REGION: PackedInt64Array = [5_000, 4_000, 3_000, 2_000]
const SEATS_REQUESTED_PER_REGION: int = 30_000

## 剧本静态校验用（docs/11 §5.7 / V-POP-01..05、INV-141/143）。
const SCENARIO_POP_PATH: String = "res://content/scenarios/chengwan/population_init.json"
const REGION_NAMES: PackedStringArray = ["beiyuan", "zhongzhou", "haijia", "xiling"]
const AGE_NAMES: PackedStringArray = ["minor", "working", "elder"]
const SKILL_NAMES: PackedStringArray = ["low", "mid", "high"]
const SECTOR_KEYS: PackedStringArray = [
	"sector.agri", "sector.manu", "sector.energy", "sector.services",
]


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(JWUnits.Phase.S07)


func after_each() -> void:
	JWResult.clear_pending()


# ── 夹具构造 ───────────────────────────────────────────────────────────────

## 构造一个满足全部载入期校验（V-POP-02..05）的 36 组人口块。
func _make_pop() -> JWPopulation:
	var pop: JWPopulation = JWPopulation.new()
	pop.allocate()

	pop.population = POP_INIT.duplicate()

	var part: PackedInt64Array = PackedInt64Array()
	part.resize(JWUnits.GROUP)
	part.fill(0)
	for r: int in JWUnits.R:
		for k: int in JWUnits.K:
			part[JWIds.idx_group(r, JWUnits.Age.WORKING, k)] = PART_PPM[k]
	pop.participation_ppm = part

	var emp: PackedInt64Array = PackedInt64Array()
	emp.resize(JWUnits.GROUP_EMP_N)
	emp.fill(0)
	var slot_n: int = JWUnits.S + 1
	var tb: PackedInt64Array = PackedInt64Array()
	tb.resize(slot_n)
	for i: int in slot_n:
		tb[i] = i
	for r: int in JWUnits.R:
		for k: int in JWUnits.K:
			var g: int = JWIds.idx_group(r, JWUnits.Age.WORKING, k)
			var lf: int = JWMath.mul_div_floor(POP_INIT[g], PART_PPM[k], JWUnits.PPM)
			var e: int = JWMath.mul_div_floor(lf, EMPLOY_RATE_PPM, JWUnits.PPM)
			var parts: PackedInt64Array = JWMath.split_lr(
					e, EMP_SLOT_WEIGHT.duplicate(), tb.duplicate())
			for slot: int in slot_n:
				emp[JWIds.idx_group_emp(g, slot)] = parts[slot]
	pop.employed = emp

	var death: PackedInt64Array = PackedInt64Array()
	death.resize(JWUnits.GROUP)
	for g: int in JWUnits.GROUP:
		death[g] = DEATH_PPM_BY_AGE[JWIds.age_of_group(g)]
	pop.death_ppm = death
	pop.birth_ppm = BIRTH_PPM_BY_REGION.duplicate()
	pop.age_out_ppm = AGE_OUT_PPM_BY_AGE.duplicate()

	var w: PackedInt64Array = PackedInt64Array()
	w.resize(JWUnits.GROUP)
	w.fill(0)
	pop.support_out_weight_ppm = w

	var edu: PackedInt64Array = PackedInt64Array()
	edu.resize(JWUnits.EDU_N)
	edu.fill(0)
	pop.education_cohort = edu

	return pop


## 构造与群组侧逐（地区, 部门, 技能）精确相等的 cell / pubserv 侧就业（INV-077 的另一视图）。
func _make_labor(pop: JWPopulation) -> JWLaborMarket:
	var labor: JWLaborMarket = JWLaborMarket.new()
	labor.allocate()
	var ce: PackedInt64Array = PackedInt64Array()
	ce.resize(JWUnits.EMP_N)
	ce.fill(0)
	var pe: PackedInt64Array = PackedInt64Array()
	pe.resize(JWUnits.PUBSERV_EMP_N)
	pe.fill(0)
	for r: int in JWUnits.R:
		for k: int in JWUnits.K:
			var g: int = JWIds.idx_group(r, JWUnits.Age.WORKING, k)
			for s: int in JWUnits.S:
				ce[JWIds.idx_emp(JWIds.idx_cell(r, s), k)] = pop.employed[
						JWIds.idx_group_emp(g, s)]
			pe[JWIds.idx_pubserv_emp(r, k)] = pop.employed[JWIds.idx_group_emp(g, JWUnits.S)]
	labor.cell_employment = ce
	labor.pub_employment = pe
	return labor


func _make_params() -> PackedInt64Array:
	var p: PackedInt64Array = PackedInt64Array()
	p.resize(JWUnits.PARAM_N)
	p.fill(0)
	p[JWUnits.Param.TRAINING_LAG_Q] = TRAINING_LAG_Q
	p[JWUnits.Param.STUDENT_TEACHER_RATIO] = STUDENT_TEACHER_RATIO
	p[JWUnits.Param.EDU_PIPELINE_SLOTS] = JWUnits.EDU_SLOT
	p[JWUnits.Param.PERSONS_PER_HOUSING_UNIT] = 3
	return p


func _make_rng() -> JWRngStreams:
	var rng: JWRngStreams = JWRngStreams.new()
	rng.allocate()
	rng.root_seed = 20260912
	rng.begin_quarter(0)
	return rng


func _zeros(n: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(0)
	return a


## 把申请席位放在各地区的 working.low 组上（升档目标是 working.mid）。
func _seat_requests(seats: int) -> PackedInt64Array:
	var req: PackedInt64Array = _zeros(JWUnits.GROUP)
	for r: int in JWUnits.R:
		req[JWIds.idx_group(r, JWUnits.Age.WORKING, JWUnits.Skill.LOW)] = seats
	return req


func _sum_slice(a: PackedInt64Array, from_idx: int, count: int) -> int:
	var acc: int = 0
	for i: int in count:
		acc += a[from_idx + i]
	return acc


# ── 0 夹具自检：期望值的来源必须先自己成立 ────────────────────────────────

## 检验：夹具本身满足 docs/11 V-POP-02/04/05 的口径（后续所有期望值都建立在这三个数上）。
func test_fixture_is_calibrated() -> void:
	eq_int(JWMath.sum(POP_INIT.duplicate()), NATION_TOTAL,
			"夹具全国人口必须等于 24 000 000（docs/11 V-POP-02 的同一口径）")
	for r: int in JWUnits.R:
		eq_int(_sum_slice(POP_INIT.duplicate(), r * JWUnits.A * JWUnits.K, JWUnits.A * JWUnits.K),
				REGION_TOTAL[r],
				"夹具第 %d 区人口必须等于 docs/11 V-POP-02 规定的 9/7/5/3 百万口径" % r)
	var lf: int = 0
	var emp: int = 0
	for r: int in JWUnits.R:
		for k: int in JWUnits.K:
			var g: int = JWIds.idx_group(r, JWUnits.Age.WORKING, k)
			var lf_g: int = JWMath.mul_div_floor(POP_INIT[g], PART_PPM[k], JWUnits.PPM)
			lf += lf_g
			emp += JWMath.mul_div_floor(lf_g, EMPLOY_RATE_PPM, JWUnits.PPM)
	eq_int(lf, EXPECTED_LABOR_FORCE_TOTAL,
			"夹具劳动力合计（Σ floor(pop×participation/1e6)）必须等于标定值")
	eq_int(emp, EXPECTED_EMPLOYED_TOTAL,
			"夹具在岗合计必须等于标定值，否则 8% 失业率的期望值不成立")
	eq_int(lf - emp, EXPECTED_UNEMPLOYED_TOTAL, "夹具失业人数 == 劳动力 − 在岗")
	eq_int(JWMath.mul_div_floor(lf - emp, JWUnits.PPM, lf), EXPECTED_UNEMPLOYMENT_PPM,
			"夹具失业率必须精确等于 80 000 ppm（docs/12 §3.4 验收区间 [79 500, 80 500] 的中值）")


# ── 1 全国与逐组人口守恒（INV-071 / INV-072） ─────────────────────────────

## 检验 INV-071（docs/30 T-S-B-01 的单季单元形态）：
## 全国人口只能被出生与死亡改变，成年／退休／技能／迁移都是零和的内部转移。
func test_u_nation_population_conserved_by_births_and_deaths_only() -> void:
	var pop: JWPopulation = _make_pop()
	var prev: PackedInt64Array = pop.population.duplicate()
	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "update_demography 在合法夹具上不得返回故障码（docs/17 §4.14）")

	var births: int = JWMath.sum(pop.f_births)
	var deaths: int = JWMath.sum(pop.f_deaths)
	eq_int(JWMath.sum(pop.population), JWMath.sum(prev) + births - deaths,
			"INV-071：Σpop(q) 必须 == Σpop(q−1) + Σ出生 − Σ死亡，残差须恰为 0")
	eq_int(JWMath.sum(pop.f_age_in), JWMath.sum(pop.f_age_out),
			"INV-071：成年／退休是配对转移，Σ成年入 必须 == Σ成年出（不得产生净流入或净流出）")
	eq_int(JWMath.sum(pop.f_skill_in), JWMath.sum(pop.f_skill_out),
			"INV-071/082：技能升档是配对转移，Σ技能入 必须 == Σ技能出")
	ge_int(births, 1, "夹具出生率为正，Σ出生 必须 > 0，否则出生这条流量根本没跑")
	ge_int(deaths, 1, "夹具死亡率为正，Σ死亡 必须 > 0，否则死亡这条流量根本没跑")


## 检验 INV-072（docs/30 T-U-B-02，docs/31 ADV-E04）：
## 逐组八项来源去向齐全，残差恰为 0；且单季流出不得超过组内期初人口。
func test_u_group_flow_identity_is_exact_for_all_36_groups() -> void:
	var pop: JWPopulation = _make_pop()
	var prev: PackedInt64Array = pop.population.duplicate()
	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "update_demography 在合法夹具上不得返回故障码")

	for g: int in JWUnits.GROUP:
		var expected: int = prev[g] + pop.f_births[g] - pop.f_deaths[g] \
				+ pop.f_age_in[g] - pop.f_age_out[g] \
				+ pop.f_skill_in[g] - pop.f_skill_out[g]
		eq_int(pop.population[g], expected,
				("INV-072：第 %d 组（r=%d a=%d k=%d）的人口必须等于"
				+ " 期初 + 出生 − 死亡 + 成年入 − 成年出 + 技能入 − 技能出（本季无迁移）")
				% [g, JWIds.region_of_group(g), JWIds.age_of_group(g), JWIds.skill_of_group(g)])
		ge_int(pop.population[g], 0, "第 %d 组人口不得为负（docs/10 §6.1 区间 ≥ 0）" % g)
		le_int(pop.f_deaths[g] + pop.f_age_out[g] + pop.f_skill_out[g], prev[g],
				("ADV-E04：第 %d 组单季流出（死亡 + 成年出 + 技能出）不得超过期初人口，"
				+ "否则说明各条流量读到了已被上一条改过的 pop") % g)


## 检验 INV-071：出生只进 minor.low，且基数是地区 working 口径人口（docs/12 §7.4 第 2 步）。
## 区间上下界分别对应「两相结构读 pop_prev」与「顺序结构读扣死亡后的人口」，
## 两种实现都合法；若实现误用地区总人口作基数，结果会远在此区间之外。
func test_u_births_enter_only_minor_low_and_scale_with_working_population() -> void:
	var pop: JWPopulation = _make_pop()
	var prev: PackedInt64Array = pop.population.duplicate()
	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "update_demography 在合法夹具上不得返回故障码")

	for g: int in JWUnits.GROUP:
		if JWIds.age_of_group(g) == JWUnits.Age.MINOR \
				and JWIds.skill_of_group(g) == JWUnits.Skill.LOW:
			continue
		eq_int(pop.f_births[g], 0,
				("INV-071：出生是唯一净流入，且只能落在 group.<r>.minor.low"
				+ "（docs/11 §5.7 birth_target_skill = low）；第 %d 组不得有出生") % g)

	for r: int in JWUnits.R:
		var working_prev: int = 0
		for k: int in JWUnits.K:
			working_prev += prev[JWIds.idx_group(r, JWUnits.Age.WORKING, k)]
		var working_after_death: int = working_prev - JWMath.mul_ppm(
				working_prev, DEATH_PPM_BY_AGE[JWUnits.Age.WORKING])
		var hi: int = JWMath.mul_ppm(working_prev, BIRTH_PPM_BY_REGION[r])
		var lo: int = JWMath.mul_ppm(working_after_death, BIRTH_PPM_BY_REGION[r])
		var g_target: int = JWIds.idx_group(r, JWUnits.Age.MINOR, JWUnits.Skill.LOW)
		in_range_int(pop.f_births[g_target], lo, hi,
				("INV-071 / docs/12 §7.4 第 2 步：第 %d 区出生数 = mul_ppm(该区 working 人口, %d ppm)，"
				+ "区间两端分别对应扣死亡前／后的基数；落在区间外说明基数取错"
				+ "（例如误用了地区总人口）") % [r, BIRTH_PPM_BY_REGION[r]])


## 检验 INV-071：死亡逐组按 mul_ppm(期初人口, 该年龄档死亡率) 单独登记，不与出生互相抵消。
## 夹具人口全为 50 000 的倍数、死亡率能整除，故期望值与取整方向无关。
func test_u_deaths_are_registered_per_group_and_not_netted_against_births() -> void:
	var pop: JWPopulation = _make_pop()
	var prev: PackedInt64Array = pop.population.duplicate()
	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "update_demography 在合法夹具上不得返回故障码")

	for g: int in JWUnits.GROUP:
		var rate: int = DEATH_PPM_BY_AGE[JWIds.age_of_group(g)]
		eq_int(pop.f_deaths[g], JWMath.mul_ppm(prev[g], rate),
				("INV-071 / docs/12 §7.4 第 1 步：第 %d 组死亡数必须 == mul_ppm(期初人口 %d, %d ppm)；"
				+ "死亡在期初人口上计算，且与出生分开登记") % [g, prev[g], rate])
		ge_int(pop.f_deaths[g], 0, "第 %d 组死亡数不得为负" % g)


## 检验 INV-071：把出生率整体置 0 后，全国人口的减少量必须精确等于死亡数——
## 出生与死亡各自成账，不允许用「净增长率」一笔带过。
func test_u_zero_birth_rate_leaves_deaths_as_the_only_net_outflow() -> void:
	var pop: JWPopulation = _make_pop()
	pop.birth_ppm = _zeros(JWUnits.R)
	var prev_total: int = JWMath.sum(pop.population)
	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "update_demography 在出生率为 0 的夹具上不得返回故障码")

	eq_int(JWMath.sum(pop.f_births), 0,
			"INV-071：出生率为 0 时 Σ出生 必须恰为 0（不得有任何其它净流入口）")
	var deaths: int = JWMath.sum(pop.f_deaths)
	ge_int(deaths, 1, "死亡率仍为正，Σ死亡 必须 > 0")
	eq_int(JWMath.sum(pop.population), prev_total - deaths,
			"INV-071：出生为 0 时全国人口的减少量必须精确等于 Σ死亡")


## 检验 INV-071：把死亡率整体置 0 后，全国人口的增加量必须精确等于出生数。
func test_u_zero_death_rate_leaves_births_as_the_only_net_inflow() -> void:
	var pop: JWPopulation = _make_pop()
	pop.death_ppm = _zeros(JWUnits.GROUP)
	var prev_total: int = JWMath.sum(pop.population)
	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "update_demography 在死亡率为 0 的夹具上不得返回故障码")

	eq_int(JWMath.sum(pop.f_deaths), 0,
			"INV-071：死亡率为 0 时 Σ死亡 必须恰为 0（不得有任何其它净流出口）")
	var births: int = JWMath.sum(pop.f_births)
	ge_int(births, 1, "出生率仍为正，Σ出生 必须 > 0")
	eq_int(JWMath.sum(pop.population), prev_total + births,
			"INV-071：死亡为 0 时全国人口的增加量必须精确等于 Σ出生")


# ── 2 成年与退休队列（INV-074 / INV-072） ─────────────────────────────────

## 检验 INV-074（docs/30 T-U-B-08，docs/31 ADV-E06）：
## minor 与 elder 不进劳动力口径——参与率为 0、在岗为 0、labor_force() 恒为 0。
func test_u_minor_and_elder_never_enter_the_labor_aggregate() -> void:
	var pop: JWPopulation = _make_pop()
	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "update_demography 在合法夹具上不得返回故障码")

	for g: int in JWUnits.GROUP:
		if JWIds.age_of_group(g) == JWUnits.Age.WORKING:
			continue
		eq_int(pop.participation_ppm[g], 0,
				"INV-074：第 %d 组是 minor/elder，participation_ppm 必须为 0（docs/10 §6.1 区间）" % g)
		eq_int(pop.employed_total(g), 0, "INV-074：第 %d 组是 minor/elder，在岗必须为 0" % g)
		eq_int(pop.labor_force(g), 0,
				"INV-074/075：第 %d 组非 working，labor_force() 必须恒返回 0（docs/17 §4.14）" % g)


## 检验 INV-074 与 INV-075（docs/31 ADV-E06「退休后继续上班」）：
## 即使有人把 elder 组的 participation_ppm 写成非 0，labor_force 也必须视其为 0，
## 且 labor_force_region_skill 不得把它计入。
func test_u_dirty_elder_participation_does_not_create_labor_force() -> void:
	var pop: JWPopulation = _make_pop()
	var r: int = JWUnits.Region.ZHONGZHOU
	var k: int = JWUnits.Skill.MID
	var g_elder: int = JWIds.idx_group(r, JWUnits.Age.ELDER, k)
	var g_work: int = JWIds.idx_group(r, JWUnits.Age.WORKING, k)
	var expected_rk: int = JWMath.mul_div_floor(
			pop.population[g_work], PART_PPM[k], JWUnits.PPM)

	var dirty: PackedInt64Array = pop.participation_ppm.duplicate()
	dirty[g_elder] = 300_000
	pop.participation_ppm = dirty

	eq_int(pop.labor_force(g_elder), 0,
			"ADV-E06 / INV-074：elder 组即使被写入 300 000 ppm 的参与率，劳动力也必须为 0")
	eq_int(pop.labor_force_region_skill(r, k), expected_rk,
			("INV-075：(地区 %d, 技能 %d) 的劳动力只能来自 working 组，"
			+ "必须等于 floor(%d × %d / 1e6)") % [r, k, pop.population[g_work], PART_PPM[k]])


## 检验 INV-074 与 INV-072（docs/31 ADV-E04）：年龄流动是有向且逐（地区, 技能）配对的。
## minor 不接收 age_in（只接收出生）；elder 不产生 age_out（只被死亡带走）；
## 成年目标组的技能档由来源 minor 组决定（docs/12 §7.4 第 3 步）。
func test_u_age_queue_is_directed_and_paired_per_region_skill() -> void:
	var pop: JWPopulation = _make_pop()
	var prev: PackedInt64Array = pop.population.duplicate()
	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "update_demography 在合法夹具上不得返回故障码")

	for g: int in JWUnits.GROUP:
		var a: int = JWIds.age_of_group(g)
		if a == JWUnits.Age.MINOR:
			eq_int(pop.f_age_in[g], 0,
					"INV-074：第 %d 组是 minor，不得有成年转入（成年只能来自低一档，minor 已是最低档）" % g)
		if a == JWUnits.Age.ELDER:
			eq_int(pop.f_age_out[g], 0,
					"INV-074：第 %d 组是 elder，不得有年龄转出（死亡是唯一净流出）" % g)

	for r: int in JWUnits.R:
		for k: int in JWUnits.K:
			var g_minor: int = JWIds.idx_group(r, JWUnits.Age.MINOR, k)
			var g_work: int = JWIds.idx_group(r, JWUnits.Age.WORKING, k)
			var g_elder: int = JWIds.idx_group(r, JWUnits.Age.ELDER, k)
			eq_int(pop.f_age_in[g_work], pop.f_age_out[g_minor],
					("INV-074：(区 %d, 技能 %d) 成年入 working 的人数必须等于同区同技能档 minor 的"
					+ "成年出人数——目标技能档由来源 minor 组决定（docs/12 §7.4 第 3 步）") % [r, k])
			eq_int(pop.f_age_in[g_elder], pop.f_age_out[g_work],
					("INV-074：(区 %d, 技能 %d) 退休入 elder 的人数必须等于同区同技能档 working 的"
					+ "退休出人数") % [r, k])
			le_int(pop.f_age_out[g_minor], prev[g_minor],
					"ADV-E04：(区 %d, 技能 %d) minor 的成年出不得超过其期初人口" % [r, k])
			ge_int(pop.f_age_out[g_minor], 1,
					("夹具 minor 成年率为 %d ppm、人口为 %d，(区 %d, 技能 %d) 的成年出必须 > 0，"
					+ "否则成年队列根本没跑") % [AGE_OUT_PPM_BY_AGE[0], prev[g_minor], r, k])
			ge_int(pop.f_age_out[g_work], 1,
					"夹具 working 退休率为正，(区 %d, 技能 %d) 的退休出必须 > 0" % [r, k])


# ── 3 技能转变：来源、去向、滞后（INV-081 / INV-082） ─────────────────────

## 检验 INV-081（docs/30 T-U-B-12 第 1 条，docs/31 ADV-E03）：
## 拨款当季只形成在读席位，不得产生任何 skill_in / skill_out。
func test_u_funding_quarter_produces_no_skill_transition() -> void:
	var pop: JWPopulation = _make_pop()
	var params: PackedInt64Array = _make_params()
	var rc: int = pop.update_education(
			TEACHERS_BY_REGION.duplicate(), _seat_requests(SEATS_REQUESTED_PER_REGION), 0, params)
	eq_int(rc, JWResult.OK, "update_education 在席位未超上限时不得返回故障码（docs/17 §4.14）")

	eq_int(JWMath.sum(pop.f_skill_in), 0,
			"INV-081：拨款当季 Σskill_in 必须恰为 0（禁止「花钱即升级」）")
	eq_int(JWMath.sum(pop.f_skill_out), 0,
			"INV-081/082：拨款当季 Σskill_out 也必须恰为 0（升档只能来自到期的结业队列）")
	eq_int(JWMath.sum(pop.education_cohort), SEATS_REQUESTED_PER_REGION * JWUnits.R,
			("INV-081：申请的 %d × 4 个席位均在教师上限之内（最紧的西岭为 %d × %d = %d），"
			+ "必须全部入队") % [SEATS_REQUESTED_PER_REGION, TEACHERS_BY_REGION[3],
			STUDENT_TEACHER_RATIO, TEACHERS_BY_REGION[3] * STUDENT_TEACHER_RATIO])
	eq_int(JWMath.sum(pop.population), NATION_TOTAL,
			"INV-072：入队本身不移动人口，Σpop 必须仍等于 24 000 000")


## 检验 INV-081（docs/31 ADV-E03 / 计划书点名 ADV-03）：
## 教师为 0 时席位上限为 0——拨款照付，但一个人也不得升档。
func test_u_adv03_no_teachers_means_no_seats_and_no_skill_in() -> void:
	var pop: JWPopulation = _make_pop()
	var params: PackedInt64Array = _make_params()
	var rc: int = pop.update_education(
			_zeros(JWUnits.R), _seat_requests(SEATS_REQUESTED_PER_REGION), 0, params)
	eq_int(rc, JWResult.OK,
			"ADV-E03：教师为 0 是业务性短缺（截到上限并写 log.clamp），不是故障（docs/17 §4.14）")

	eq_int(JWMath.sum(pop.education_cohort), 0,
			"INV-081：max_seats = teachers × ratio = 0 ⇒ 新增席位必须恰为 0")
	eq_int(JWMath.sum(pop.f_skill_in), 0, "ADV-03：教师为 0 时 Σskill_in 必须恰为 0")
	ge_int(pop.edu_seats_clamped(), 1,
			"ADV-E03 / INV-100：申请被截到上限必须留下可解释的记录（edu_seats_clamped > 0）")


## 检验 INV-081：新增席位 ≤ teachers × ratio − 在读席位（上限是硬的，不随申请量增长）。
func test_u_seat_cap_is_teachers_times_ratio_minus_enrolled() -> void:
	var pop: JWPopulation = _make_pop()
	var params: PackedInt64Array = _make_params()
	var huge: int = 10_000_000
	var rc: int = pop.update_education(
			TEACHERS_BY_REGION.duplicate(), _seat_requests(huge), 0, params)
	eq_int(rc, JWResult.OK, "申请超上限应截断，不是故障（docs/17 §4.14 失败行）")

	var cap_total: int = 0
	for r: int in JWUnits.R:
		cap_total += TEACHERS_BY_REGION[r] * STUDENT_TEACHER_RATIO
	eq_int(JWMath.sum(pop.education_cohort), cap_total,
			("INV-081：申请 %d/区远超上限时，在读席位必须恰好等于 Σ teachers×ratio = %d，"
			+ "既不得超出，也不得莫名少于上限") % [huge, cap_total])

	var rc2: int = pop.update_education(
			TEACHERS_BY_REGION.duplicate(), _seat_requests(huge), 1, params)
	eq_int(rc2, JWResult.OK, "第二季继续申请仍应被截断而不是故障")
	eq_int(JWMath.sum(pop.education_cohort), cap_total,
			("INV-081：上限要减去**在读**席位；队列已满时第二季不得再新增，"
			+ "总在读必须仍为 %d") % cap_total)


## 检验 INV-082（docs/30 T-U-B-12，docs/31 ADV-E03 的滞后与配对断言）：
## 升档只来自到期的结业队列，滞后恰好 param.training_lag_q 季，
## skill_out 与 skill_in 等量配对且只发生在相邻档之间。
func test_u_skill_upgrade_is_lagged_and_paired_between_adjacent_tiers() -> void:
	var pop: JWPopulation = _make_pop()
	var params: PackedInt64Array = _make_params()
	var rng: JWRngStreams = _make_rng()
	var seats: int = SEATS_REQUESTED_PER_REGION

	var rc0: int = pop.update_education(
			TEACHERS_BY_REGION.duplicate(), _seat_requests(seats), 0, params)
	eq_int(rc0, JWResult.OK, "q=0 入队不得返回故障码")

	# q = 1 … training_lag_q −1：不申请新席位，也不得有任何结业
	for q: int in range(1, TRAINING_LAG_Q):
		pop.f_skill_in = _zeros(JWUnits.GROUP)
		pop.f_skill_out = _zeros(JWUnits.GROUP)
		var rc: int = pop.update_education(
				TEACHERS_BY_REGION.duplicate(), _zeros(JWUnits.GROUP), q, params)
		eq_int(rc, JWResult.OK, "第 %d 季 update_education 不得返回故障码" % q)
		eq_int(JWMath.sum(pop.f_skill_in), 0,
				("INV-082：滞后期为 %d 季，第 %d 季（< 滞后期）Σskill_in 必须恰为 0")
				% [TRAINING_LAG_Q, q])

	# q == training_lag_q：结业，等量配对
	pop.f_skill_in = _zeros(JWUnits.GROUP)
	pop.f_skill_out = _zeros(JWUnits.GROUP)
	var prev: PackedInt64Array = pop.population.duplicate()
	var rc_g: int = pop.update_education(
			TEACHERS_BY_REGION.duplicate(), _zeros(JWUnits.GROUP), TRAINING_LAG_Q, params)
	eq_int(rc_g, JWResult.OK, "结业季 update_education 不得返回故障码")

	var in_total: int = JWMath.sum(pop.f_skill_in)
	var out_total: int = JWMath.sum(pop.f_skill_out)
	eq_int(out_total, seats * JWUnits.R,
			("INV-082：第 %d 季应有 q=0 入队的全部 %d × 4 人结业并写 skill_out")
			% [TRAINING_LAG_Q, seats])
	eq_int(in_total, out_total, "INV-082：skill_in 与 skill_out 必须等量配对")

	for r: int in JWUnits.R:
		var g_low: int = JWIds.idx_group(r, JWUnits.Age.WORKING, JWUnits.Skill.LOW)
		var g_mid: int = JWIds.idx_group(r, JWUnits.Age.WORKING, JWUnits.Skill.MID)
		var g_high: int = JWIds.idx_group(r, JWUnits.Age.WORKING, JWUnits.Skill.HIGH)
		eq_int(pop.f_skill_out[g_low], seats,
				"INV-082：第 %d 区 working.low 的 skill_out 必须等于该区入队人数 %d" % [r, seats])
		eq_int(pop.f_skill_in[g_mid], seats,
				("INV-082：第 %d 区结业者只能升到相邻的 working.mid，人数必须等于 %d")
				% [r, seats])
		eq_int(pop.f_skill_in[g_low], 0, "INV-082：第 %d 区 working.low 不得有 skill_in（它已是最低档）" % r)
		eq_int(pop.f_skill_in[g_high], 0,
				"INV-082：第 %d 区不得出现 low→high 的跨档升级（升档只发生在相邻档之间）" % r)
		eq_int(pop.f_skill_out[g_high], 0,
				"INV-082：第 %d 区 working.high 不得有 skill_out（它已是最高档）" % r)

	# 升档必须真的搬人：来源组减、去向组增，且全国总量不变（INV-072 的技能两项）
	for r: int in JWUnits.R:
		var g_low2: int = JWIds.idx_group(r, JWUnits.Age.WORKING, JWUnits.Skill.LOW)
		var g_mid2: int = JWIds.idx_group(r, JWUnits.Age.WORKING, JWUnits.Skill.MID)
		eq_int(pop.population[g_low2], prev[g_low2] - seats,
				"INV-072：第 %d 区 working.low 的人口必须按 skill_out 减少" % r)
		eq_int(pop.population[g_mid2], prev[g_mid2] + seats,
				"INV-072：第 %d 区 working.mid 的人口必须按 skill_in 增加" % r)
	eq_int(JWMath.sum(pop.population), JWMath.sum(prev),
			"INV-071：技能升档是内部转移，全国人口总量必须逐位不变")
	eq_int(JWMath.sum(pop.education_cohort), 0,
			"INV-082：结业后该批队列必须清空，不得留在队列里被重复结业")
	# rng 只是为了让签名依赖显式化，避免未使用变量告警
	ge_int(rng.draw_count_of(JWUnits.RngStream.DEMOGRAPHY), 0, "rng 抽样计数不得为负")


# ── 4 就业口径与失业率反算（INV-075 / INV-076 / INV-077） ─────────────────

## 检验 INV-075：labor_force(g) == mul_div_floor(pop, participation, 1e6)，
## 且 labor_force_region_skill 与逐组口径一致（docs/12 §3.4 的分母定义）。
func test_u_labor_force_matches_the_contract_formula() -> void:
	var pop: JWPopulation = _make_pop()
	var total: int = 0
	for r: int in JWUnits.R:
		for k: int in JWUnits.K:
			var g: int = JWIds.idx_group(r, JWUnits.Age.WORKING, k)
			var expected: int = JWMath.mul_div_floor(
					pop.population[g], PART_PPM[k], JWUnits.PPM)
			eq_int(pop.labor_force(g), expected,
					("INV-075：第 %d 组劳动力必须 == mul_div_floor(%d, %d, 1e6) == %d"
					+ "（docs/12 §3.4）") % [g, pop.population[g], PART_PPM[k], expected])
			eq_int(pop.labor_force_region_skill(r, k), expected,
					("INV-075：(区 %d, 技能 %d) 的劳动力聚合必须等于该口径下唯一 working 组的劳动力")
					% [r, k])
			total += expected
	eq_int(total, EXPECTED_LABOR_FORCE_TOTAL,
			"INV-075：全国劳动力必须等于夹具标定值 10 500 000")


## 检验 INV-076（docs/30 T-U-B-05，docs/31 ADV-E05）：
## 逐（地区, 技能）Σ在岗 ≤ Σ劳动力，且群组侧的分槽在岗之和与 employed_total 一致。
func test_u_employment_never_exceeds_labor_force_per_region_skill() -> void:
	var pop: JWPopulation = _make_pop()
	var employed_nation: int = 0
	for r: int in JWUnits.R:
		for k: int in JWUnits.K:
			var g: int = JWIds.idx_group(r, JWUnits.Age.WORKING, k)
			var by_slot: int = 0
			for slot: int in JWUnits.S + 1:
				by_slot += pop.employed[JWIds.idx_group_emp(g, slot)]
			eq_int(pop.employed_total(g), by_slot,
					("INV-077：第 %d 组的 employed_total() 必须等于 5 个槽位（4 部门 + pubserv）"
					+ "之和 %d") % [g, by_slot])
			le_int(pop.employed_total(g), pop.labor_force_region_skill(r, k),
					("INV-076：(区 %d, 技能 %d) 的在岗人数不得超过同口径劳动力 %d"
					+ "——这是计划书 §17「就业人数不超过同口径劳动力」的执行点")
					% [r, k, pop.labor_force_region_skill(r, k)])
			employed_nation += pop.employed_total(g)
	eq_int(employed_nation, EXPECTED_EMPLOYED_TOTAL,
			"夹具全国在岗必须等于标定值 9 660 000（失业率期望值的来源）")


## 检验 INV-075 与 INV-143（docs/30 T-U-B-07）：失业率是**反算**出来的，
## 且在本夹具上恰好等于 80 000 ppm，落在协议唯一的非零容差区间 [79 500, 80 500] 内。
func test_u_unemployment_is_reverse_computed_and_equals_8_percent() -> void:
	var pop: JWPopulation = _make_pop()
	var labor: JWLaborMarket = _make_labor(pop)
	var rc: int = labor.compute_unemployment(pop)
	eq_int(rc, JWResult.OK, "compute_unemployment 在 在岗 ≤ 劳动力 的夹具上不得返回故障码")

	eq_int(labor.unemployed_persons(), EXPECTED_UNEMPLOYED_TOTAL,
			("INV-075：失业人数 == Σ劳动力 %d − Σ在岗 %d")
			% [EXPECTED_LABOR_FORCE_TOTAL, EXPECTED_EMPLOYED_TOTAL])
	eq_int(labor.unemployment_ppm(), EXPECTED_UNEMPLOYMENT_PPM,
			("INV-075：失业率 == mul_div_floor(840 000, 1e6, 10 500 000) == 80 000 ppm；"
			+ "夹具刻意标定到 8%，任何偏差都说明分子或分母口径被改过"))
	in_range_int(labor.unemployment_ppm(), 79_500, 80_500,
			"INV-143 / docs/12 §3.4：q=0 的失业率必须落在协议唯一的非零容差区间内")
	eq_int(labor.unemployment_ppm(),
			JWMath.mul_div_floor(labor.unemployed_persons(), JWUnits.PPM,
					maxi(EXPECTED_LABOR_FORCE_TOTAL, 1)),
			"INV-075：失业率必须与独立复算值逐位相同（取整方向为 floor）")


## 检验 INV-075/076（docs/31 ADV-E05「就业人数超过劳动力」）：
## 在岗超过全国劳动力时必须显式故障，不得把负的失业人数静默夹成 0。
func test_u_employment_above_labor_force_raises_employment_overflow() -> void:
	var pop: JWPopulation = _make_pop()
	var g: int = JWIds.idx_group(JWUnits.Region.BEIYUAN, JWUnits.Age.WORKING, JWUnits.Skill.LOW)
	var emp: PackedInt64Array = pop.employed.duplicate()
	# 多塞 1 000 000 人：超过全国 840 000 的失业缓冲，使 Σ在岗 > Σ劳动力
	emp[JWIds.idx_group_emp(g, 0)] = emp[JWIds.idx_group_emp(g, 0)] + 1_000_000
	pop.employed = emp

	var labor: JWLaborMarket = _make_labor(pop)
	var rc: int = labor.compute_unemployment(pop)
	eq_int(rc, JWResult.Fault.EMPLOYMENT_OVERFLOW,
			("ADV-E05 / INV-075：Σ在岗（%d）超过 Σ劳动力（%d）时必须返回 EMPLOYMENT_OVERFLOW(42)，"
			+ "禁止把负失业人数静默改成 0")
			% [EXPECTED_EMPLOYED_TOTAL + 1_000_000, EXPECTED_LABOR_FORCE_TOTAL])
	eq_int(JWResult.pending_code(), JWResult.Fault.EMPLOYMENT_OVERFLOW,
			"docs/12 §9：故障必须登记到 JWResult 的待处理槽位，而不是只做返回值")


## 检验 INV-077 / INV-151（docs/30 T-U-B-06，docs/31 ADV-E05 第二条）：
## 群组侧与 cell/pubserv 侧就业是同一事实的两个索引视图，容差 0；
## 任一侧被单独改动都必须被交叉校验发现。
func test_u_employment_two_views_cross_check_catches_one_sided_edit() -> void:
	var pop: JWPopulation = _make_pop()
	var labor: JWLaborMarket = _make_labor(pop)
	eq_int(labor.check_employment_views(pop), JWResult.OK,
			"INV-077：两侧就业按 (地区, 部门, 技能) 逐项构造相等时，交叉校验必须通过")

	for r: int in JWUnits.R:
		for k: int in JWUnits.K:
			var g: int = JWIds.idx_group(r, JWUnits.Age.WORKING, k)
			var cell_side: int = 0
			for s: int in JWUnits.S:
				cell_side += labor.employment(JWIds.idx_cell(r, s), k)
			cell_side += labor.pubserv_employment(r, k)
			eq_int(cell_side, pop.employed_total(g),
					("INV-077：(区 %d, 技能 %d) 的 cell+pubserv 侧在岗必须与群组侧精确相等")
					% [r, k])

	var pe: PackedInt64Array = labor.pub_employment.duplicate()
	pe[JWIds.idx_pubserv_emp(JWUnits.Region.HAIJIA, JWUnits.Skill.HIGH)] += 1
	labor.pub_employment = pe
	ne_int(labor.check_employment_views(pop), JWResult.OK,
			("INV-077/151：只改 pubserv 侧 1 个人就必须被交叉校验发现；"
			+ "通过即说明两侧是两套独立数据而不是同一事实的两个索引"))


# ── 5 人口流出与就业配对、守恒终检（INV-080 / INV-071 / INV-073） ─────────

## 检验 INV-080（docs/12 §7.7）：本季流出 == 死亡 + 成年出 + 迁出。
## 技能升档**不是**流出：它不带走岗位，若被算进去会导致 S07 错误裁员。
func test_u_outflow_is_deaths_plus_age_out_plus_migration_only() -> void:
	var pop: JWPopulation = _make_pop()
	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "update_demography 在合法夹具上不得返回故障码")

	var flow: PackedInt64Array = _zeros(JWUnits.GROUP)
	pop.outflow_persons_into(flow)
	for g: int in JWUnits.GROUP:
		eq_int(flow[g], pop.f_deaths[g] + pop.f_age_out[g],
				("INV-080 / docs/12 §7.7：第 %d 组无迁移时的流出必须 == 死亡 %d + 成年出 %d；"
				+ "技能升档不得计入流出（它不带走岗位）")
				% [g, pop.f_deaths[g], pop.f_age_out[g]])

	var mig_out: PackedInt64Array = _zeros(JWUnits.GROUP)
	var g_mig: int = JWIds.idx_group(JWUnits.Region.ZHONGZHOU, JWUnits.Age.WORKING,
			JWUnits.Skill.LOW)
	mig_out[g_mig] = 12_345
	var rc_m: int = pop.record_migration_out(mig_out)
	eq_int(rc_m, JWResult.OK, "record_migration_out 登记迁出汇总不得返回故障码")
	var flow2: PackedInt64Array = _zeros(JWUnits.GROUP)
	pop.outflow_persons_into(flow2)
	eq_int(flow2[g_mig], pop.f_deaths[g_mig] + pop.f_age_out[g_mig] + 12_345,
			("INV-080：登记 12 345 人迁出后，第 %d 组的流出必须把迁出量一并计入") % g_mig)


## 检验 INV-080（docs/12 §7.7，docs/31 ADV-E06）：人口流出必须按比例带走岗位，
## 扣减量精确等于 mul_div_floor(流出, 组内在岗, 组内期初人口)，且扣减后两侧就业仍然相等。
func test_u_employment_cut_equals_the_share_carried_away_by_outflow() -> void:
	var pop: JWPopulation = _make_pop()
	var labor: JWLaborMarket = _make_labor(pop)
	var pop_prev: PackedInt64Array = pop.population.duplicate()
	var emp_prev: PackedInt64Array = pop.employed.duplicate()
	var slot_n: int = JWUnits.S + 1

	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "update_demography 在合法夹具上不得返回故障码")

	var outflow: PackedInt64Array = _zeros(JWUnits.GROUP)
	pop.outflow_persons_into(outflow)
	var cut: PackedInt64Array = _zeros(JWUnits.GROUP_EMP_N)
	var rc_rel: int = labor.release_for_outflow(outflow, pop, cut)
	eq_int(rc_rel, JWResult.OK, "release_for_outflow 在合法夹具上不得返回故障码")

	for g: int in JWUnits.GROUP:
		var emp_g_prev: int = 0
		var cut_g: int = 0
		for slot: int in slot_n:
			emp_g_prev += emp_prev[JWIds.idx_group_emp(g, slot)]
			cut_g += cut[JWIds.idx_group_emp(g, slot)]
		var expected: int = JWMath.mul_div_floor(outflow[g], emp_g_prev, maxi(pop_prev[g], 1))
		eq_int(cut_g, expected,
				("INV-080 / docs/12 §7.7：第 %d 组的就业扣减必须 == mul_div_floor(流出 %d,"
				+ " 在岗 %d, 期初人口 %d) == %d；S07 对 employment 的减少量不许多也不许少")
				% [g, outflow[g], emp_g_prev, pop_prev[g], expected])
		le_int(cut_g, emp_g_prev, "INV-080：第 %d 组的扣减不得超过该组在岗人数" % g)
		if JWIds.age_of_group(g) != JWUnits.Age.WORKING:
			eq_int(cut_g, 0, "INV-074：第 %d 组是 minor/elder，本就无岗位可扣" % g)

	var rc_apply: int = pop.apply_employment_cut(cut)
	eq_int(rc_apply, JWResult.OK, "apply_employment_cut 在配对一致时不得返回故障码")
	for g: int in JWUnits.GROUP:
		var emp_g_prev2: int = 0
		var cut_g2: int = 0
		for slot: int in slot_n:
			emp_g_prev2 += emp_prev[JWIds.idx_group_emp(g, slot)]
			cut_g2 += cut[JWIds.idx_group_emp(g, slot)]
		eq_int(pop.employed_total(g), emp_g_prev2 - cut_g2,
				"INV-080：第 %d 组回写后的在岗必须 == 期初在岗 − 扣减" % g)
	eq_int(labor.check_employment_views(pop), JWResult.OK,
			"INV-077：S07 的流出配对扣减之后，群组侧与 cell/pubserv 侧必须仍然逐项相等")


## 检验 INV-071/072（docs/31 ADV-E04）：把死亡率与成年率同时推到极端（两者之和 > 1e6），
## 同一个人不得被两条路径各扣一次——逐组流出仍不得超过期初人口，人口不得为负。
func test_u_extreme_rates_never_remove_more_people_than_exist() -> void:
	var pop: JWPopulation = _make_pop()
	var death: PackedInt64Array = pop.death_ppm.duplicate()
	for g: int in JWUnits.GROUP:
		death[g] = 400_000
	pop.death_ppm = death
	var age_out: PackedInt64Array = PackedInt64Array([700_000, 700_000, 0])
	pop.age_out_ppm = age_out

	var prev: PackedInt64Array = pop.population.duplicate()
	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK,
			"ADV-E04：极端但合法（每项都在 0..1e6 内）的人口学比率不得让 S07 直接故障")

	for g: int in JWUnits.GROUP:
		ge_int(pop.population[g], 0, "ADV-E04：第 %d 组人口不得为负" % g)
		le_int(pop.f_deaths[g] + pop.f_age_out[g], prev[g],
				("ADV-E04：第 %d 组的 死亡 %d + 成年出 %d 不得超过期初人口 %d——"
				+ "两条比率之和为 1 100 000 ppm 时，同一个人被两条路径各扣一次就会在这里暴露")
				% [g, pop.f_deaths[g], pop.f_age_out[g], prev[g]])
		var expected: int = prev[g] + pop.f_births[g] - pop.f_deaths[g] \
				+ pop.f_age_in[g] - pop.f_age_out[g] \
				+ pop.f_skill_in[g] - pop.f_skill_out[g]
		eq_int(pop.population[g], expected, "INV-072：极端比率下第 %d 组的来源去向恒等式仍须精确成立" % g)
	eq_int(JWMath.sum(pop.population),
			JWMath.sum(prev) + JWMath.sum(pop.f_births) - JWMath.sum(pop.f_deaths),
			"INV-071：极端比率下全国人口守恒仍须精确成立")


## 检验 INV-072：空组（人口为 0）必须产生全零流量，且不得触发除零。
## docs/10 §6 明确「允许空组，空组仍参与全部恒等式检查」。
func test_u_empty_group_produces_no_flows_and_no_div_zero() -> void:
	var pop: JWPopulation = _make_pop()
	# 选 minor.high：它既不接收出生（出生只进 minor.low），也不接收成年入（minor 已是最低档），
	# 因此清空后本季应当全程保持 0——任何非零都不是配对转移，而是凭空出现。
	var g_empty: int = JWIds.idx_group(JWUnits.Region.XILING, JWUnits.Age.MINOR,
			JWUnits.Skill.HIGH)
	var p: PackedInt64Array = pop.population.duplicate()
	var moved: int = p[g_empty]
	p[g_empty] = 0
	p[JWIds.idx_group(JWUnits.Region.XILING, JWUnits.Age.MINOR, JWUnits.Skill.LOW)] += moved
	pop.population = p

	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "空组存在时 update_demography 不得返回故障码（docs/10 §6 允许空组）")
	eq_int(JWResult.pending_code(), 0,
			"docs/10 §14.1：空组不得触发 DIV_ZERO(91) 或任何其它故障登记")
	eq_int(pop.f_deaths[g_empty], 0, "空组的死亡必须为 0")
	eq_int(pop.f_age_out[g_empty], 0, "空组的年龄流出必须为 0")
	eq_int(pop.f_births[g_empty], 0, "INV-071：出生只进 minor.low，minor.high 不得有出生")
	eq_int(pop.f_age_in[g_empty], 0, "INV-074：minor 档不接收成年入")
	eq_int(pop.population[g_empty], 0,
			"INV-072：既无出生也无成年入的空 minor.high 组不得凭空出现人口")
	eq_int(JWMath.sum(pop.population),
			NATION_TOTAL + JWMath.sum(pop.f_births) - JWMath.sum(pop.f_deaths),
			"INV-071：含空组时全国人口守恒仍须精确成立")


## 检验 INV-071/072（docs/12 §7.4 第 7 步）：守恒终检在合法状态下通过，
## 而在有人凭空多出一个人时必须报 POPULATION_NOT_CONSERVED——这是本模块的最后一道闸。
func test_u_check_conservation_rejects_a_fabricated_person() -> void:
	var pop: JWPopulation = _make_pop()
	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "update_demography 在合法夹具上不得返回故障码")

	var zero_in: PackedInt64Array = _zeros(JWUnits.GROUP)
	var zero_out: PackedInt64Array = _zeros(JWUnits.GROUP)
	eq_int(pop.check_conservation(zero_in, zero_out), JWResult.OK,
			"INV-071/072：合法的人口更新之后，守恒终检必须通过（残差恰为 0）")

	var tampered: PackedInt64Array = pop.population.duplicate()
	tampered[7] = tampered[7] + 1
	pop.population = tampered
	JWResult.clear_pending()
	eq_int(pop.check_conservation(zero_in, zero_out),
			JWResult.Fault.POPULATION_NOT_CONSERVED,
			("INV-071：第 7 组凭空多出 1 个人时，守恒终检必须返回 POPULATION_NOT_CONSERVED(40)；"
			+ "容差为 0，1 个人也不许放过"))


## 检验 INV-073（docs/30 T-U-B-03 的守恒侧）：迁移进出汇总不配对时，
## 终检必须失败——迁移不得成为第二个净流入／净流出口。
func test_u_check_conservation_rejects_unpaired_migration() -> void:
	var pop: JWPopulation = _make_pop()
	var rc: int = pop.update_demography(_make_rng(), _make_params())
	eq_int(rc, JWResult.OK, "update_demography 在合法夹具上不得返回故障码")

	var mig_in: PackedInt64Array = _zeros(JWUnits.GROUP)
	var mig_out: PackedInt64Array = _zeros(JWUnits.GROUP)
	mig_in[JWIds.idx_group(JWUnits.Region.HAIJIA, JWUnits.Age.WORKING, JWUnits.Skill.LOW)] = 10_000
	JWResult.clear_pending()
	var rc2: int = pop.check_conservation(mig_in, mig_out)
	ne_int(rc2, JWResult.OK,
			("INV-073：Σ迁入（10 000）≠ Σ迁出（0）时守恒终检必须失败；"
			+ "通过即说明迁移可以凭空造人"))
	check(rc2 == JWResult.Fault.POPULATION_NOT_CONSERVED
			or rc2 == JWResult.Fault.MIGRATION_UNPAIRED,
			("docs/12 §7.10：迁移不配对的失败码必须是 POPULATION_NOT_CONSERVED(40) 或"
			+ " MIGRATION_UNPAIRED(41)，实际为 %d") % rc2)


## 检验 INV-141：地区与全国人口聚合器与逐组求和一致（迁移与出生的推力都以它为基数）。
func test_u_region_and_nation_population_aggregates() -> void:
	var pop: JWPopulation = _make_pop()
	for r: int in JWUnits.R:
		eq_int(pop.region_population(r), REGION_TOTAL[r],
				("INV-141：第 %d 区人口必须等于该区 9 组之和 %d（docs/11 V-REG-05 同口径）")
				% [r, REGION_TOTAL[r]])
	eq_int(pop.nation_population(), NATION_TOTAL,
			"INV-141：全国人口必须等于 36 组之和 24 000 000")


# ── 6 剧本内容的静态复核（INV-141 / INV-143，docs/11 V-POP-02..05） ───────

func _load_scenario() -> Dictionary:
	var f: FileAccess = FileAccess.open(SCENARIO_POP_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var v: Variant = JSON.parse_string(text)
	if v is Dictionary:
		return v as Dictionary
	return {}


func _group_index_of(group_id: String) -> int:
	var parts: PackedStringArray = group_id.split(".")
	if parts.size() != 4:
		return -1
	var r: int = REGION_NAMES.find(parts[1])
	var a: int = AGE_NAMES.find(parts[2])
	var k: int = SKILL_NAMES.find(parts[3])
	if r < 0 or a < 0 or k < 0:
		return -1
	return JWIds.idx_group(r, a, k)


func _employed_of(entry: Dictionary) -> int:
	var emp: Dictionary = entry.get("employed_persons", {}) as Dictionary
	var acc: int = 0
	for key: String in SECTOR_KEYS:
		acc += int(emp.get(key, 0))
	acc += int(emp.get("pubserv", 0))
	return acc


## 递归统计含 needle 的键名个数。**跳过 `_note_*` 子树**：docs/11 §5.15.1 规定注释键
## 「不进加载器、不进 content_hash」，它可以（也应该）写明失业率是怎么反算出来的；
## INV-143 禁的是**输入字段**，不是文档。
func _count_input_keys_matching(v: Variant, needle: String) -> int:
	var n: int = 0
	if v is Dictionary:
		var d: Dictionary = v as Dictionary
		for key: Variant in d.keys():
			var name: String = String(key)
			if name.begins_with("_note"):
				continue
			if name.to_lower().find(needle) >= 0:
				n += 1
			n += _count_input_keys_matching(d[key], needle)
	elif v is Array:
		for item: Variant in (v as Array):
			n += _count_input_keys_matching(item, needle)
	return n


## 检验 INV-143（docs/30 T-U-B-07 的静态分支）：
## 剧本 schema 里不得存在任何失业率输入字段——失业率只能由就业分配反算。
func test_u_scenario_has_no_unemployment_input_field() -> void:
	var doc: Dictionary = _load_scenario()
	check(not doc.is_empty(), "必须能读到剧本 %s（缺文件则本条无法检验）" % SCENARIO_POP_PATH)
	eq_int(_count_input_keys_matching(doc, "unemploy"), 0,
			("INV-143：population_init 的**输入字段**中含 \"unemploy\" 的键数量必须为 0"
			+ "（`_note_*` 注释子树不计，docs/11 §5.15.1）——"
			+ "「禁止把 8% 写成参数再反推就业」（docs/12 §3.4）"))
	eq_int(_count_input_keys_matching(doc, "失业"), 0,
			"INV-143：剧本中也不得用中文键名夹带失业率输入字段")
	# 逐组再查一遍：36 条 group 记录里不允许出现任何失业相关字段
	var groups: Array = doc.get("groups", []) as Array
	eq_int(_count_input_keys_matching(groups, "unemploy"), 0,
			"INV-143：36 条群组记录中不得出现任何失业率／失业人数输入字段")
	eq_int(_count_input_keys_matching(doc.get("demography_rates", {}), "unemploy"), 0,
			"INV-143：demography_rates 中不得出现失业率输入字段")


## 检验 INV-141（docs/11 V-POP-01/02）：剧本 36 组齐全、全国 24 000 000、逐区 9/7/5/3 百万。
func test_u_scenario_population_totals_match_the_contract() -> void:
	var doc: Dictionary = _load_scenario()
	check(not doc.is_empty(), "必须能读到剧本 %s" % SCENARIO_POP_PATH)
	var groups: Array = doc.get("groups", []) as Array
	eq_int(groups.size(), JWUnits.GROUP, "V-POP-01：剧本必须恰好有 36 个人口组")

	var by_group: PackedInt64Array = _zeros(JWUnits.GROUP)
	var seen: PackedInt64Array = _zeros(JWUnits.GROUP)
	for item: Variant in groups:
		var e: Dictionary = item as Dictionary
		var g: int = _group_index_of(String(e.get("group_id", "")))
		check(g >= 0, "V-POP-01：group_id \"%s\" 无法解析为 36 组之一" % String(e.get("group_id", "")))
		if g < 0:
			continue
		seen[g] = seen[g] + 1
		by_group[g] = int(e.get("population_persons", 0))
	eq_int(JWMath.sum(seen), JWUnits.GROUP, "V-POP-01：36 个组 ID 必须各出现恰好一次")

	eq_int(JWMath.sum(by_group), NATION_TOTAL,
			"V-POP-02 / INV-141：剧本全国人口必须精确等于 24 000 000")
	for r: int in JWUnits.R:
		eq_int(_sum_slice(by_group, r * JWUnits.A * JWUnits.K, JWUnits.A * JWUnits.K),
				REGION_TOTAL[r],
				"V-POP-02 / INV-141：第 %d 区人口必须精确等于 %d" % [r, REGION_TOTAL[r]])


## 检验 INV-074 与 INV-076（docs/11 V-POP-03/V-POP-04）：
## 剧本里非 working 组不得有参与率、在岗与赡养转出权重；逐组在岗不得超过该组劳动力。
func test_u_scenario_age_role_and_group_employment_bounds() -> void:
	var doc: Dictionary = _load_scenario()
	check(not doc.is_empty(), "必须能读到剧本 %s" % SCENARIO_POP_PATH)
	var groups: Array = doc.get("groups", []) as Array
	for item: Variant in groups:
		var e: Dictionary = item as Dictionary
		var gid: String = String(e.get("group_id", ""))
		var g: int = _group_index_of(gid)
		if g < 0:
			continue
		var pop_g: int = int(e.get("population_persons", 0))
		var part: int = int(e.get("participation_ppm", 0))
		var emp_g: int = _employed_of(e)
		if JWIds.age_of_group(g) != JWUnits.Age.WORKING:
			eq_int(part, 0, "V-POP-03 / INV-074：%s 是非 working 组，participation_ppm 必须为 0" % gid)
			eq_int(emp_g, 0, "V-POP-03 / INV-074：%s 是非 working 组，在岗人数必须全为 0" % gid)
			eq_int(int(e.get("support_out_weight_ppm", 0)), 0,
					"V-POP-03：%s 是非 working 组，support_out_weight_ppm 必须为 0" % gid)
		else:
			var lf_g: int = JWMath.mul_div_floor(pop_g, part, JWUnits.PPM)
			le_int(emp_g, lf_g,
					("V-POP-04 / INV-076：%s 的在岗 %d 不得超过该组劳动力 floor(%d × %d / 1e6) == %d")
					% [gid, emp_g, pop_g, part, lf_g])


## 检验 INV-143（docs/30 T-U-B-07 的反算分支，docs/11 V-POP-05）：
## 直接按契约的反算链复算剧本的失业率，必须落在 [79 500, 80 500] ppm。
func test_u_scenario_unemployment_reverse_computes_into_the_accepted_band() -> void:
	var doc: Dictionary = _load_scenario()
	check(not doc.is_empty(), "必须能读到剧本 %s" % SCENARIO_POP_PATH)
	var groups: Array = doc.get("groups", []) as Array
	var lf_total: int = 0
	var emp_total: int = 0
	for item: Variant in groups:
		var e: Dictionary = item as Dictionary
		var g: int = _group_index_of(String(e.get("group_id", "")))
		if g < 0:
			continue
		emp_total += _employed_of(e)
		if JWIds.age_of_group(g) == JWUnits.Age.WORKING:
			lf_total += JWMath.mul_div_floor(int(e.get("population_persons", 0)),
					int(e.get("participation_ppm", 0)), JWUnits.PPM)
	ge_int(lf_total, 1, "剧本劳动力合计必须为正，否则失业率的分母无定义")
	ge_int(lf_total - emp_total, 0,
			("V-POP-04 / INV-075：剧本全国失业人数 = 劳动力 %d − 在岗 %d 必须 ≥ 0")
			% [lf_total, emp_total])
	var ppm: int = JWMath.mul_div_floor(lf_total - emp_total, JWUnits.PPM, lf_total)
	in_range_int(ppm, 79_500, 80_500,
			("V-POP-05 / INV-143：剧本反算失业率必须落在 [79 500, 80 500] ppm——"
			+ "这是协议里唯一的非零容差；实际 %d（劳动力 %d，在岗 %d）")
			% [ppm, lf_total, emp_total])
