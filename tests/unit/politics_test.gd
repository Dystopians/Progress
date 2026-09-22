## JWPolitics / JWInterestGroups 单元测试：政治与社会（docs/10 §14.10，INV-121…INV-130）。
##
## 依据（只读契约，不读被测实现）：
##   docs/18 R-SUPPORT-01（支持度相对基年映射）、R-SCALE-01（先乘后除走 mul_div_floor）
##   docs/12 §8.1 三个主观量分开更新 / §8.2 支持度 / §8.3 集团反应 / §8.5 留任、选举与终局 / §2.1 资格链
##   docs/10 §14.10 INV-121…INV-130
##   docs/17 §4.24 JWPolitics、§4.25 JWInterestGroups（签名不得改）
##   docs/31 ADV-G01（补贴刷支持率）、ADV-G02（选举季套利）、ADV-G03（事件改账）、
##           ADV-G04（终局之后继续玩）、ADV-G05（席位阈值边界）
##
## 覆盖的三条分离线（INV-125）：
##   票     = JWPolitics.update_support / seat_rule
##   组织力 = JWInterestGroups.update_blocs / org_power
##   行政力 = JWPolitics.set_admin_capacity
## 三者由三个函数算，互不引用对方的量——本文件用「改 A 不动 B」的行为断言把它钉死。
##
## 纪律：JWResult 的故障登记是静态的，会跨测试方法残留；每个方法前必须 clear_pending()。
extends JWTest

const G: int = JWUnits.GROUP
const B: int = JWUnits.BLOC_N
const PN: int = JWUnits.PARAM_N

## 剧本 politics_init 的席位（docs/12 §8.2 的推导表：56 / 101 == 554 455 ppm）
const SEATS_TOTAL: int = 101
const SEATS_GOV_BASE: int = 56
## docs/12 §8.2 推导表：基年剧本登记的人口加权支持度
const BASE_SUPPORT_NATIONAL: int = 544_127
## docs/12 §8.2 推导表：绝对加权式在基年给出的值（R-SUPPORT-01 判定为错误口径）
const ABSOLUTE_WEIGHTED_TRAP: int = 871_864
## docs/12 §8.2 推导表：基年非未成年人口加权的三项水平值
const BASE_LIVING_LEVEL: int = 1_000_000
const BASE_EXPECTATION_LEVEL: int = 964_935
const BASE_TRUST_LEVEL: int = 569_117
## docs/12 §8.2 推导表所用权重
const W_LIVING: int = 450_000
const W_EXPECTATION: int = 275_000
const W_TRUST: int = 275_000

## docs/12 §8.2 要求的四组基年基准（content.base_*）。docs/17 §4.24 的成员表未登记它们的成员名，
## 故此处按命名惯例（参照 JWPopulation 的 content.base_per_capita_real_income_uu -> base_real_income）
## 逐个候选探测；一个都找不到即判失败并指出契约条款，不做静默跳过。
const NAMES_BASE_SUPPORT: Array = ["base_support", "base_support_ppm", "content_base_support"]
const NAMES_BASE_LIVING: Array = ["base_living", "base_living_ppm", "base_living_index",
		"content_base_living"]
const NAMES_BASE_EXPECTATION: Array = ["base_expectation", "base_expectation_ppm",
		"content_base_expectation"]
const NAMES_BASE_TRUST: Array = ["base_trust", "base_trust_ppm", "content_base_trust"]
## docs/17 §4.25 同时登记了成员 `org_power` 与方法 `org_power(b)`——同名不可共存，
## 故组织影响力的存储成员名只能探测（见 interface_requests）。
const NAMES_ORG_POWER: Array = ["org_power_ppm", "org_power_value", "_org_power", "org_power"]


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(0)


func after_each() -> void:
	JWResult.clear_pending()


# ── 夹具 ───────────────────────────────────────────────────────────────────

## §1.6 状态块协议：每个块 new() 之后必须跑一次 allocate() 才有契约长度的数组
## （sim/state/sim_state.gd allocate_all() 就是这样构造全部块的）。
func _new_pricing() -> JWPricing:
	var pr: JWPricing = JWPricing.new()
	pr.allocate()
	return pr


func _new_treasury() -> JWTreasury:
	var tr: JWTreasury = JWTreasury.new()
	tr.allocate()
	return tr


func _new_sectors() -> JWSectorModel:
	var x: JWSectorModel = JWSectorModel.new()
	x.allocate()
	return x


func _new_labor() -> JWLaborMarket:
	var x: JWLaborMarket = JWLaborMarket.new()
	x.allocate()
	return x


func _new_capital() -> JWCapital:
	var x: JWCapital = JWCapital.new()
	x.allocate()
	return x


func _new_defs() -> JWPolicyDef:
	var x: JWPolicyDef = JWPolicyDef.new()
	x.allocate()
	return x


func _filled(n: int, v: int) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(n)
	a.fill(v)
	return a


func _prop_exists(obj: Object, name: String) -> bool:
	for d: Dictionary in obj.get_property_list():
		if String(d.get("name", "")) == name:
			return true
	return false


func _find_prop(obj: Object, candidates: Array) -> String:
	for n: Variant in candidates:
		if _prop_exists(obj, String(n)):
			return String(n)
	return ""


## 写入一组契约要求存在、但 docs/17 未登记成员名的数组。找不到即记一条失败，返回 false。
func _set_base(obj: Object, candidates: Array, value: PackedInt64Array) -> bool:
	var n: String = _find_prop(obj, candidates)
	check(n != "", "契约要求存在该字段（docs/12 §8.2 的 content.base_* / docs/17 §4.25 的 org_power），候选成员名 %s 全部不存在"
			% str(candidates))
	if n == "":
		return false
	obj.set(n, value)
	return true


## 取某方法的形参名表（用于 INV-125 / INV-128 的结构性断言）。方法不存在返回空表。
func _method_args(obj: Object, method: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for m: Dictionary in obj.get_method_list():
		if String(m.get("name", "")) != method:
			continue
		var args: Array = m.get("args", [])
		for a: Dictionary in args:
			out.append(String(a.get("name", "")))
		return out
	return out


## 全部 param.* 取剧本量级的合法值；与本文件的期望值一一对应，改这里就要同步改断言。
func _make_params() -> PackedInt64Array:
	var p: PackedInt64Array = _filled(PN, 0)
	p[JWUnits.Param.SUPPORT_WEIGHT_PPM_0] = W_LIVING
	p[JWUnits.Param.SUPPORT_WEIGHT_PPM_1] = W_EXPECTATION
	p[JWUnits.Param.SUPPORT_WEIGHT_PPM_2] = W_TRUST
	# INV-122：恢复必须慢于下降
	p[JWUnits.Param.TRUST_DROP_PPM] = 300_000
	p[JWUnits.Param.TRUST_RECOVER_PPM] = 100_000
	p[JWUnits.Param.TRUST_STREAK_CAP_Q] = 8
	p[JWUnits.Param.EXPECTATION_INERTIA_PPM] = 800_000
	p[JWUnits.Param.LIVING_WEIGHT_HOUSE_PPM] = 250_000
	p[JWUnits.Param.LIVING_WEIGHT_SERVICE_PPM] = 250_000
	p[JWUnits.Param.NO_CONFIDENCE_Q] = 2
	p[JWUnits.Param.DEFAULT_GRACE_Q] = 3
	p[JWUnits.Param.BLOC_ORG_INERTIA_PPM] = 600_000
	p[JWUnits.Param.BLOC_W_SIZE_PPM] = 200_000
	p[JWUnits.Param.BLOC_W_RESOURCE_PPM] = 200_000
	p[JWUnits.Param.BLOC_CARE_GAIN_PPM] = 100_000
	p[JWUnits.Param.BLOC_RESOURCE_REF_UU] = 1_000_000_000_000
	p[JWUnits.Param.PERSONS_PER_HOUSING_UNIT] = 3
	p[JWUnits.Param.STUDENT_TEACHER_RATIO] = 20
	p[JWUnits.Param.AMOUNT_MAX_UU] = JWUnits.AMOUNT_MAX
	p[JWUnits.Param.QTY_MAX_UQS] = JWUnits.QTY_MAX
	p[JWUnits.Param.TAX_BASE_RATE_PPM] = 150_000
	p[JWUnits.Param.MPC_PPM] = 800_000
	return p


## 人口夹具：36 组等人口（非未成年组权重相同，便于让全国加权恒等于逐组值）。
func _make_pop(per_group_persons: int) -> JWPopulation:
	var pop: JWPopulation = JWPopulation.new()
	pop.allocate()
	pop.population = _filled(G, per_group_persons)
	pop.base_real_income = _filled(G, 1_400)          # R-SCALE-01 后的量级（μU/人/季）
	return pop


## 基年状态：三项指标全部等于基年基准，Δ 全为 0。
func _make_politics_at_base() -> JWPolitics:
	var pol: JWPolitics = JWPolitics.new()
	pol.allocate()
	pol.living_index = _filled(G, BASE_LIVING_LEVEL)
	pol.expectation = _filled(G, BASE_EXPECTATION_LEVEL)
	pol.trust = _filled(G, BASE_TRUST_LEVEL)
	pol.support = _filled(G, BASE_SUPPORT_NATIONAL)
	pol.keep_streak_q = _filled(G, 0)
	pol._support_decomp = _filled(G * 3, 0)
	pol.seats_total = SEATS_TOTAL
	pol.seats_gov = SEATS_GOV_BASE
	pol.term_index = 0
	pol.next_election_q = 15
	pol.next_budget_review_q = 3
	pol.f_budget_review_due = 0
	pol.mandate_goal = JWUnits.MandateGoal.LIVELIHOOD
	pol.mandate_status = JWUnits.MandateStatus.OK
	pol.admin_capacity_ppm = 700_000
	pol.legal_authority_mask = 0
	pol.run_terminated = false
	pol.termination_reason = JWUnits.Termination.NONE
	pol._at_risk_streak_q = 0
	var ok: bool = _set_base(pol, NAMES_BASE_LIVING, _filled(G, BASE_LIVING_LEVEL))
	ok = _set_base(pol, NAMES_BASE_EXPECTATION, _filled(G, BASE_EXPECTATION_LEVEL)) and ok
	ok = _set_base(pol, NAMES_BASE_TRUST, _filled(G, BASE_TRUST_LEVEL)) and ok
	ok = _set_base(pol, NAMES_BASE_SUPPORT, _filled(G, BASE_SUPPORT_NATIONAL)) and ok
	return pol


func _make_blocs() -> JWInterestGroups:
	var bl: JWInterestGroups = JWInterestGroups.new()
	bl.allocate()
	_set_base(bl, NAMES_ORG_POWER, _filled(B, 400_000))
	bl.stance = _filled(JWUnits.STANCE_N, 0)
	bl.resource = _filled(B, 500_000_000_000)
	bl.care_prev = _filled(B, 0)
	bl.veto_domain_mask = _filled(B, 0)
	bl.affiliation_ppm = _filled(JWUnits.AFFIL_N, 0)
	return bl


# ══ 一、R-SUPPORT-01：基年支持度 ═══════════════════════════════════════════

## 检验 docs/18 R-SUPPORT-01 与 docs/12 §8.2 的验收断言 T-S-SUPPORT-BASE-IDENTITY，
## 同时覆盖 INV-124（全国值只由逐组加权得出）。
## 这是本文件最重要的一条：基年支持度必须恒等于剧本登记值，而不是绝对加权算出的约 87%。
func test_support_base_year_identity_not_absolute_weighting() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	var pop: JWPopulation = _make_pop(100_000)
	var params: PackedInt64Array = _make_params()

	pol.update_support(pop, params)

	for g: int in G:
		eq_int(pol.support[g], BASE_SUPPORT_NATIONAL,
				"R-SUPPORT-01：q=0 三个 Δ 全为 0 ⇒ 第 %d 组 support 必须恒等于剧本 base_support（docs/12 §8.2 T-S-SUPPORT-BASE-IDENTITY，容差 0）" % g)
	# 绝对加权式 Σ wᵢ·indexᵢ 在基年恰好给出 871 864（docs/12 §8.2 推导表），这正是被裁定推翻的口径。
	ne_int(pol.support[0], ABSOLUTE_WEIGHTED_TRAP,
			"R-SUPPORT-01：支持度等于 871 864 说明用的是绝对加权 Σ wᵢ·indexᵢ（docs/12 §8.2 推导表），不是相对基年的变化量映射")
	ne_int(pol.support[0], 554_455,
			"R-SUPPORT-01：支持度等于席位占比 56/101 说明 support 抄了 politics_init 的席位，而不是剧本登记的支持度")
	eq_int(pol.support_national_ppm(pop), BASE_SUPPORT_NATIONAL,
			"INV-124：逐组全部为 %d 时，人口加权全国值必须精确等于同一值" % BASE_SUPPORT_NATIONAL)


## 检验 docs/12 §8.2 的「单次取整」要求（三项先各自成积再求和，最后只除一次）。
## 逐项 mul_ppm 后相加会把 1 ppm 的合计变化整体吞掉，是最难被肉眼发现的一类错。
func test_support_delta_uses_single_rounding() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	var pop: JWPopulation = _make_pop(100_000)
	var params: PackedInt64Array = _make_params()
	# 三项各 +1 ppm：num = 450000 + 275000 + 275000 == 1 000 000 ⇒ delta == 1。
	# 若实现写成 mul_ppm(w0,1)+mul_ppm(w1,1)+mul_ppm(w2,1)，三次 floor 后是 0+0+0 == 0。
	pol.living_index = _filled(G, BASE_LIVING_LEVEL + 1)
	pol.expectation = _filled(G, BASE_EXPECTATION_LEVEL + 1)
	pol.trust = _filled(G, BASE_TRUST_LEVEL + 1)

	pol.update_support(pop, params)

	eq_int(pol.support[0], BASE_SUPPORT_NATIONAL + 1,
			"docs/12 §8.2：num = 450000·1 + 275000·1 + 275000·1 = 1 000 000，idiv_floor 后 delta == 1；得到 +0 说明逐项取整了三次")


## 检验 docs/12 §8.2 的 `delta_ppm = idiv_floor(num, 1e6)` 对负数向 −∞ 取整。
## GDScript 的裸 `/` 对负数向零截断，会在下行方向系统性少扣一格。
func test_support_delta_floors_toward_negative_infinity() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	var pop: JWPopulation = _make_pop(100_000)
	var params: PackedInt64Array = _make_params()
	pol.living_index = _filled(G, BASE_LIVING_LEVEL - 1)   # num == −450 000

	pol.update_support(pop, params)

	eq_int(pol.support[0], BASE_SUPPORT_NATIONAL - 1,
			"docs/12 §8.2：num = −450 000，floor(−450000/1e6) == −1；得到 0 说明用了向零截断的裸除法")


## 检验 docs/12 §8.2 的 clamp(base + delta, 0, 1e6)（两侧边界都要夹住）。
func test_support_is_clamped_to_ppm_range() -> void:
	var pop: JWPopulation = _make_pop(100_000)
	var params: PackedInt64Array = _make_params()

	var hi: JWPolitics = _make_politics_at_base()
	_set_base(hi, NAMES_BASE_SUPPORT, _filled(G, 1_000_000))
	hi.living_index = _filled(G, BASE_LIVING_LEVEL + 1_000_000)
	hi.update_support(pop, params)
	eq_int(hi.support[0], 1_000_000,
			"docs/12 §8.2：base 1e6 且 Δ 为正 ⇒ clamp 上界 1 000 000")

	var lo: JWPolitics = _make_politics_at_base()
	_set_base(lo, NAMES_BASE_SUPPORT, _filled(G, 0))
	lo.living_index = _filled(G, 0)
	lo.expectation = _filled(G, 0)
	lo.trust = _filled(G, 0)
	lo.update_support(pop, params)
	eq_int(lo.support[0], 0,
			"docs/12 §8.2：base 0 且 Δ 全为负 ⇒ clamp 下界 0，不得出现负 ppm")


## 检验 INV-123：每次变动都有生活／预期／信任三项来源分解，且分解与合计的差 ≤ 2 ppm
## （docs/12 §8.2：三次 floor 对一次 floor，报告以 delta_ppm 为准）。
func test_support_change_has_three_way_decomposition() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	var pop: JWPopulation = _make_pop(100_000)
	var params: PackedInt64Array = _make_params()
	# Δliving = +40 000，Δexpectation = −20 000，Δtrust = +10 000
	pol.living_index = _filled(G, BASE_LIVING_LEVEL + 40_000)
	pol.expectation = _filled(G, BASE_EXPECTATION_LEVEL - 20_000)
	pol.trust = _filled(G, BASE_TRUST_LEVEL + 10_000)

	pol.update_support(pop, params)

	var d0: int = JWMath.mul_ppm(W_LIVING, 40_000)          # 18 000
	var d1: int = JWMath.mul_ppm(W_EXPECTATION, -20_000)    # −5 500
	var d2: int = JWMath.mul_ppm(W_TRUST, 10_000)           # 2 750
	var num: int = JWMath.mul(W_LIVING, 40_000) + JWMath.mul(W_EXPECTATION, -20_000) \
			+ JWMath.mul(W_TRUST, 10_000)
	var delta: int = JWMath.floor_div(num, JWUnits.PPM)
	eq_int(pol.support[0], BASE_SUPPORT_NATIONAL + delta,
			"docs/12 §8.2：support == base + floor(num/1e6)，num 由三项积相加得到")
	eq_int(pol._support_decomp[0], d0,
			"INV-123：第 0 组的生活项贡献必须是 mul_ppm(w0, Δliving) == %d" % d0)
	eq_int(pol._support_decomp[1], d1,
			"INV-123：第 0 组的预期项贡献必须是 mul_ppm(w1, Δexpectation) == %d（负向也要 floor）" % d1)
	eq_int(pol._support_decomp[2], d2,
			"INV-123：第 0 组的信任项贡献必须是 mul_ppm(w2, Δtrust) == %d" % d2)
	var residual: int = JWMath.absi(d0 + d1 + d2 - delta)
	le_int(residual, 2,
			"docs/12 §8.2：三项分解之和与 delta_ppm 至多差 2 ppm；差更多说明分解与合计走了两套公式")


## 检验 docs/12 §8.2 的验收断言 T-S-SUPPORT-DELTA-ONLY：把三项置回基年值即回到基年支持度，
## 与到达该状态的路径无关（支持度只由当期差驱动，不积分历史）。
func test_support_is_path_independent_delta_only() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	var pop: JWPopulation = _make_pop(100_000)
	var params: PackedInt64Array = _make_params()

	pol.living_index = _filled(G, BASE_LIVING_LEVEL + 300_000)
	pol.update_support(pop, params)
	ne_int(pol.support[0], BASE_SUPPORT_NATIONAL,
			"前置：抬高生活指数后支持度必须先离开基年值，否则本测试没有区分力")

	pol.living_index = _filled(G, BASE_LIVING_LEVEL)
	pol.update_support(pop, params)
	eq_int(pol.support[0], BASE_SUPPORT_NATIONAL,
			"docs/12 §8.2 T-S-SUPPORT-DELTA-ONLY：三项回到基年值 ⇒ support 必须回到 base_support；不回去说明 support 被写成了累加式")


## 检验 INV-124：全国支持度只由逐组按**非未成年人口**最大余数法加权得出。
## 未成年组的人口不得进入分母，也不得让其 support 进入分子。
func test_support_national_weights_exclude_minors() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	var pop: JWPopulation = _make_pop(0)
	var work: int = JWIds.idx_group(0, JWUnits.Age.WORKING, JWUnits.Skill.LOW)
	var elder: int = JWIds.idx_group(0, JWUnits.Age.ELDER, JWUnits.Skill.LOW)
	var minor: int = JWIds.idx_group(0, JWUnits.Age.MINOR, JWUnits.Skill.LOW)
	var popv: PackedInt64Array = _filled(G, 0)
	popv[work] = 3_000_000
	popv[elder] = 1_000_000
	popv[minor] = 20_000_000
	pop.population = popv
	var sup: PackedInt64Array = _filled(G, 0)
	sup[work] = 800_000
	sup[elder] = 400_000
	sup[minor] = 0
	pol.support = sup

	# (3·800000 + 1·400000) / 4 == 700 000，整除，无余数歧义。
	eq_int(pol.support_national_ppm(pop), 700_000,
			"INV-124：非未成年加权 (3·800000+1·400000)/4 == 700 000；得到 116 666 说明未成年被计入分母")
	eq_int(pol.support_region_ppm(pop, 0), 700_000,
			"INV-124：北原区内同样只按非未成年加权")
	# INV-124 的后半句：全国值不得吞掉逐组分布。
	eq_int(pol.support[work], 800_000,
			"INV-124：算完全国值后逐组 support 必须原样保留（禁止只保留全国值）")
	eq_int(pol.support[elder], 400_000,
			"INV-124：算完全国值后逐组 support 必须原样保留（禁止只保留全国值）")


## 检验 INV-124：加权必须是人口加权而非算术平均，且空区不得除零（docs/17 §4.24「失败：无」）。
func test_support_national_is_population_weighted_not_arithmetic_mean() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	var pop: JWPopulation = _make_pop(0)
	var g1: int = JWIds.idx_group(0, JWUnits.Age.WORKING, JWUnits.Skill.LOW)
	var g2: int = JWIds.idx_group(0, JWUnits.Age.WORKING, JWUnits.Skill.MID)
	var popv: PackedInt64Array = _filled(G, 0)
	popv[g1] = 1_000_000
	popv[g2] = 2_000_000
	pop.population = popv
	var sup: PackedInt64Array = _filled(G, 0)
	sup[g1] = 1_000_000
	sup[g2] = 0
	pol.support = sup

	var nat: int = pol.support_national_ppm(pop)
	in_range_int(nat, 333_333, 333_334,
			"INV-124：1:2 人口 × (1e6, 0) 的加权值是 1/3 ≈ 333 333；落在别处说明权重不是人口")
	ne_int(nat, 500_000,
			"INV-124：500 000 是两组的算术平均，说明加权用的是组数而不是人口")
	JWResult.clear_pending()
	var empty_region: int = pol.support_region_ppm(pop, JWUnits.Region.XILING)
	in_range_int(empty_region, 0, 1_000_000,
			"INV-124：空区（非未成年人口为 0）必须返回合法 ppm，不得返回垃圾值")
	ne_int(JWResult.pending_code(), JWResult.Fault.DIV_ZERO,
			"docs/17 §4.24：support_region_ppm 标注「失败：无」，空区必须走 max(pop,1) 而不是除零")


# ══ 二、三种权力分离（INV-125） ════════════════════════════════════════════

## 检验 INV-125：支持度公式里不出现 admin_capacity_ppm。
## 行政能力从 0 改到 1e6，逐组 support 必须逐位不变。
func test_support_does_not_read_admin_capacity() -> void:
	var pop: JWPopulation = _make_pop(100_000)
	var params: PackedInt64Array = _make_params()

	var a: JWPolitics = _make_politics_at_base()
	a.living_index = _filled(G, BASE_LIVING_LEVEL + 120_000)
	a.admin_capacity_ppm = 0
	a.update_support(pop, params)

	var b: JWPolitics = _make_politics_at_base()
	b.living_index = _filled(G, BASE_LIVING_LEVEL + 120_000)
	b.admin_capacity_ppm = 1_000_000
	b.update_support(pop, params)

	eq_int_array(a.support, b.support,
			"INV-125：行政能力 0 与 1e6 两种状态下 support 必须逐位相同；不同则说明票的公式引用了行政能力")


## 检验 INV-125：行政能力更新不得顺带改动票与席位（三套量三个写入者）。
## 同时检验 docs/17 §4.24 的后置条件 admin_capacity_ppm ∈ [0, 1e6]。
func test_set_admin_capacity_clamps_and_leaves_votes_untouched() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	var before: PackedInt64Array = pol.support.duplicate()
	var seats_before: int = pol.seats_gov

	pol.set_admin_capacity(1_500_000)
	eq_int(pol.admin_capacity_ppm, 1_000_000,
			"docs/17 §4.24：admin_capacity_ppm 后置区间 [0, 1e6]，1 500 000 必须夹到 1 000 000")
	pol.set_admin_capacity(-5)
	eq_int(pol.admin_capacity_ppm, 0,
			"docs/17 §4.24：admin_capacity_ppm 后置区间 [0, 1e6]，负值必须夹到 0")
	eq_int_array(pol.support, before,
			"INV-125：写行政能力不得改动任何一组的 support（票与行政能力是两套量）")
	eq_int(pol.seats_gov, seats_before,
			"INV-125：写行政能力不得改动席位")


## 检验 INV-125 的结构性落地（docs/17 §4.24/§4.25）：
## JWPolitics 不得持有集团的量，JWInterestGroups 不得持有票与行政能力的量。
func test_three_powers_are_structurally_separate_classes() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	var bl: JWInterestGroups = _make_blocs()

	check_false(_prop_exists(pol, "org_power"),
			"INV-125：JWPolitics 不得持有 org_power（组织影响力归 JWInterestGroups）")
	check_false(_prop_exists(pol, "stance"),
			"INV-125：JWPolitics 不得持有 stance；集团立场只能经 check_authority 的形参传入")
	check_false(_prop_exists(bl, "support"),
			"INV-125：JWInterestGroups 不得持有 support（票归 JWPolitics）")
	check_false(_prop_exists(bl, "admin_capacity_ppm"),
			"INV-125：JWInterestGroups 不得持有 admin_capacity_ppm（行政能力归 JWPolitics）")
	# update_blocs 的形参表里不得出现 politics / support / admin 之类的入口（docs/17 §4.25）。
	var args: PackedStringArray = _method_args(bl, "update_blocs")
	check(args.size() > 0, "docs/17 §4.25：JWInterestGroups 必须有 update_blocs 方法")
	for a: String in args:
		check_false(a.findn("politic") >= 0 or a.findn("support") >= 0 or a.findn("admin") >= 0,
				"INV-125：update_blocs 的形参 \"%s\" 把票／行政能力引进了组织影响力的计算" % a)


## 检验 INV-121：三个主观量分开存储，禁止合成单一「满意度」字段（ADV-G01 的静态断言）。
func test_no_synthetic_satisfaction_field() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	check(_prop_exists(pol, "living_index"), "INV-121：living_index 必须独立存在")
	check(_prop_exists(pol, "expectation"), "INV-121：expectation 必须独立存在")
	check(_prop_exists(pol, "trust"), "INV-121：trust 必须独立存在")
	check(_prop_exists(pol, "support"), "INV-121：support 必须独立存在")
	check_false(_prop_exists(pol, "satisfaction_ppm"),
			"INV-121 / ADV-G01：出现 satisfaction_ppm 说明三分量在某处被合成了单一满意度")
	check_false(_prop_exists(pol, "satisfaction"),
			"INV-121 / ADV-G01：出现 satisfaction 说明三分量在某处被合成了单一满意度")


# ══ 三、主观量三层分离与信任非对称（INV-121 / INV-122，ADV-G01） ═══════════

## 检验 INV-122：trust 的更新式里结构上不存在 transfer_income 通道。
## 把转移支付拉到极大，trust 必须逐位不变（ADV-G01「一次性补贴刷支持率」的核心断言）。
func test_trust_has_no_transfer_income_channel() -> void:
	var params: PackedInt64Array = _make_params()
	var pricing: JWPricing = _new_pricing()
	var breach: PackedInt64Array = _filled(G, 0)

	var a: JWPolitics = _make_politics_at_base()
	var pa: JWPopulation = _make_pop(100_000)
	pa.f_transfer_income = _filled(G, 0)
	a.update_subjective(pa, pricing, breach, params)

	var b: JWPolitics = _make_politics_at_base()
	var pb: JWPopulation = _make_pop(100_000)
	pb.f_transfer_income = _filled(G, 900_000_000)     # 每组 0.9 U 的一次性转移
	b.update_subjective(pb, pricing, breach, params)

	eq_int_array(a.trust, b.trust,
			"INV-122 / ADV-G01：发钱前后 trust 必须逐位相同；不同则 transfer_income 进了信任公式，游戏退化为「发钱即赢」")


## 检验 INV-122 的数值形态（docs/12 §8.1）：
##   breach_ppm = clamp(breach_count × 250 000, 0, 1e6)
##   keep_ppm   = clamp(floor(keep_streak × 1e6 / cap), 0, 1e6)
##   trust = clamp(trust − mul_ppm(drop, breach_ppm) + mul_ppm(recover, keep_ppm), 0, 1e6)
## 并检验「下降快于恢复」：一次失信的跌幅 > 一季满 streak 的涨幅。
func test_trust_drop_and_recover_are_asymmetric() -> void:
	var params: PackedInt64Array = _make_params()
	var pricing: JWPricing = _new_pricing()
	var pop: JWPopulation = _make_pop(100_000)

	var pol: JWPolitics = _make_politics_at_base()
	pol.trust = _filled(G, 500_000)
	pol.keep_streak_q = _filled(G, 0)
	var breach: PackedInt64Array = _filled(G, 1)
	pol.update_subjective(pop, pricing, breach, params)
	# breach_ppm = 250 000；drop = mul_ppm(300 000, 250 000) == 75 000
	eq_int(pol.trust[0], 425_000,
			"docs/12 §8.1：一次失信 ⇒ trust 500 000 − mul_ppm(300000, 250000) == 425 000")
	eq_int(pol.keep_streak_q[0], 0,
			"docs/12 §8.1：本季有失信 ⇒ keep_streak 必须归零")

	# 之后一个干净季：keep_streak = 1，cap = 8 ⇒ keep_ppm = 125 000，涨 mul_ppm(100000,125000) == 12 500
	var clean: PackedInt64Array = _filled(G, 0)
	pol.update_subjective(pop, pricing, clean, params)
	eq_int(pol.keep_streak_q[0], 1,
			"docs/12 §8.1：连续无失信季数 +1")
	eq_int(pol.trust[0], 437_500,
			"docs/12 §8.1：一个干净季 ⇒ trust 425 000 + mul_ppm(100000, floor(1·1e6/8)) == 437 500")
	le_int(pol.trust[0], 500_000,
			"INV-122：恢复慢于下降 ⇒ 一次失信后单季不得回到原值 500 000")
	check(500_000 - 425_000 > 437_500 - 425_000,
			"INV-122 / ADV-G01：单季跌幅 75 000 必须大于单季涨幅 12 500，否则失信没有长期代价")


## 检验 INV-122 的下界与 §8.1 的 breach_ppm 上限夹逼：多次失信不得把 trust 压成负数。
func test_trust_is_clamped_at_zero_and_breach_saturates() -> void:
	var params: PackedInt64Array = _make_params()
	var pricing: JWPricing = _new_pricing()
	var pop: JWPopulation = _make_pop(100_000)
	var pol: JWPolitics = _make_politics_at_base()
	pol.trust = _filled(G, 100_000)
	# breach_count = 9 ⇒ 9 × 250 000 = 2 250 000，clamp 到 1 000 000
	# drop = mul_ppm(300 000, 1 000 000) == 300 000 > 100 000 ⇒ clamp 到 0
	pol.update_subjective(pop, pricing, _filled(G, 9), params)
	eq_int(pol.trust[0], 0,
			"docs/12 §8.1：breach_ppm 饱和到 1e6 ⇒ 跌 300 000，trust 由 100 000 夹到 0，不得为负")
	ge_int(pol.trust[0], 0,
			"INV-122：trust 的区间是 [0, 1e6]")


## 检验 INV-121：三层分离——失信只走信任通道，不得顺带改动预期。
## 两次运行只差 breach_count，expectation 必须逐位相同、trust 必须不同。
func test_breach_moves_trust_only_not_expectation() -> void:
	var params: PackedInt64Array = _make_params()
	var pricing: JWPricing = _new_pricing()

	var a: JWPolitics = _make_politics_at_base()
	a.update_subjective(_make_pop(100_000), pricing, _filled(G, 0), params)

	var b: JWPolitics = _make_politics_at_base()
	b.update_subjective(_make_pop(100_000), pricing, _filled(G, 2), params)

	eq_int_array(a.expectation, b.expectation,
			"INV-121：失信计数只进 trust 的更新式；expectation 随之改变说明三层被串在了一起")
	ne_int(a.trust[0], b.trust[0],
			"INV-122：失信必须让 trust 下降；两者相同说明 breach_count 根本没被读")
	eq_int_array(a.living_index, b.living_index,
			"INV-121：失信计数不得改动生活指数（生活只由收入／住房／服务三项合成）")


# ══ 四、席位规则（INV-126，ADV-G05） ═══════════════════════════════════════

## 检验 INV-126 与 docs/12 §8.2 推导表：基年席位占比 56/101 对应 554 455 ppm。
## 554455 × 101 = 55 999 955 ⇒ 商 55、余 999 955；反方 44 + 余 999 045；
## 剩 2 席按最大余数法各得 1 ⇒ 政府 56。
func test_seat_rule_reproduces_base_year_seats() -> void:
	eq_int(JWPolitics.seat_rule(554_455, SEATS_TOTAL), SEATS_GOV_BASE,
			"INV-126 / docs/12 §8.2：554 455 ppm × 101 席按最大余数法必须给出 56 席（剧本 politics_init 的开局席位）")


## 检验 INV-126 / ADV-G05：跳变点两侧、两个极端、以及纯函数性（同输入同输出）。
## 495 049 × 101 = 49 999 949（余 999 949，多拿 1 席）⇒ 50；
## 504 951 × 101 = 51 000 051（余 51，不多拿）⇒ 51。
func test_seat_rule_boundaries_and_purity() -> void:
	eq_int(JWPolitics.seat_rule(0, SEATS_TOTAL), 0,
			"ADV-G05：支持度 0 ⇒ 0 席，不得为负")
	eq_int(JWPolitics.seat_rule(1_000_000, SEATS_TOTAL), SEATS_TOTAL,
			"ADV-G05：支持度 1e6 ⇒ 全部 101 席，不得越界")
	eq_int(JWPolitics.seat_rule(495_049, SEATS_TOTAL), 50,
			"INV-126：49 999 949/1e6 的余数 999 949 > 反方余数 51，最大余数法把剩余席给政府 ⇒ 50 席")
	eq_int(JWPolitics.seat_rule(504_951, SEATS_TOTAL), 51,
			"INV-126：51 000 051/1e6 的余数 51 < 反方余数，剩余席归反方 ⇒ 51 席")
	for s: int in [0, 1, 495_048, 495_049, 495_050, 999_999, 1_000_000]:
		var seats: int = JWPolitics.seat_rule(s, SEATS_TOTAL)
		in_range_int(seats, 0, SEATS_TOTAL,
				"ADV-G05：support=%d 时席位必须落在 [0, %d]" % [s, SEATS_TOTAL])
		eq_int(JWPolitics.seat_rule(s, SEATS_TOTAL), seats,
				"INV-126：seat_rule 是纯函数，support=%d 重复调用必须同值" % s)


## 检验 INV-125：seat_rule 是静态纯函数，形参只有支持度与总席位，
## 结构上不可能引用 org_power_ppm 或 admin_capacity_ppm。
func test_seat_rule_signature_excludes_other_powers() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	var args: PackedStringArray = _method_args(pol, "seat_rule")
	eq_int(args.size(), 2,
			"docs/17 §4.24：seat_rule(support_national_ppm, seats_total) 只有两个形参，多出来的形参就是 INV-125 的缺口")
	for a: String in args:
		check_false(a.findn("org") >= 0 or a.findn("admin") >= 0 or a.findn("stance") >= 0,
				"INV-125：seat_rule 的形参 \"%s\" 把组织影响力／行政能力引进了席位换算" % a)


# ══ 五、预算审查（INV-127） ════════════════════════════════════════════════

## 检验 INV-127 与 docs/12 §02.8：预算审查标记只在 q == next_budget_review_q 置位，
## 且置位后 next_budget_review_q += 4。
func test_budget_review_marks_only_on_due_quarter() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	pol.next_budget_review_q = 3
	pol.f_budget_review_due = 0

	pol.mark_budget_review(2)
	eq_int(pol.f_budget_review_due, 0,
			"docs/12 §02.8：q=2 不是审查季，不得置位 budget_review_due")
	eq_int(pol.next_budget_review_q, 3,
			"docs/12 §02.8：未命中审查季时 next_budget_review_q 不得推进")

	pol.mark_budget_review(3)
	eq_int(pol.f_budget_review_due, 1,
			"docs/12 §02.8：q=3 == next_budget_review_q ⇒ 置位 budget_review_due")
	eq_int(pol.next_budget_review_q, 7,
			"docs/12 §02.8：置位后 next_budget_review_q += 4 ⇒ 7")


## 检验 INV-127：整局 40 季里，预算审查恰好落在 q ≡ 3 (mod 4) 的 10 个季。
func test_budget_review_schedule_is_every_fourth_quarter() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	pol.next_budget_review_q = 3
	var marked: int = 0
	for q: int in 40:
		pol.f_budget_review_due = 0             # S01 每季清流量
		pol.mark_budget_review(q)
		if pol.f_budget_review_due == 1:
			marked += 1
			eq_int(q % 4, 3,
					"INV-127：预算审查只能在 q ≡ 3 (mod 4)，实际落在 q=%d" % q)
	eq_int(marked, 10,
			"INV-127：40 季内 q ∈ {3,7,…,39} 共 10 次审查；数目不符说明审查排期漂了")


# ══ 六、资格链（docs/12 §02.1，INV-099 / INV-125） ═════════════════════════

## 检验 docs/12 §02.1 资格链第 1 环的三个分支与它们的顺序。
func test_check_authority_returns_precise_reject_codes() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	pol.legal_authority_mask = 1 << 3
	pol.seats_gov = 51
	pol.seats_total = SEATS_TOTAL
	var stance: PackedInt64Array = _filled(JWUnits.STANCE_N, 1_000_000)

	# 权限位齐、席位够（floor(51·1e6/101) == 504 950 >= 500 000）、无否决
	eq_int(pol.check_authority(3, 500_000, 0, stance, 5), JWResult.OK,
			"docs/12 §02.1：权限位齐 + 席位 504 950 ppm ≥ 500 000 + 无否决 ⇒ 放行")
	# 权限位缺失
	eq_int(pol.check_authority(4, 500_000, 0, stance, 5), JWResult.Reject.AUTHORITY,
			"docs/12 §02.1：legal_authority_mask 的第 4 位未置 ⇒ E_AUTHORITY")
	# 席位不足：floor(51·1e6/101) == 504 950 < 600 000
	eq_int(pol.check_authority(3, 600_000, 0, stance, 5), JWResult.Reject.SEATS_SHORT,
			"docs/12 §02.1：mul_div_floor(51, 1e6, 101) == 504 950 < 600 000 ⇒ E_SEATS_SHORT")
	# 顺序：权限检查先于席位检查（两者同时不满足时必须报 AUTHORITY）
	eq_int(pol.check_authority(4, 600_000, 0, stance, 5), JWResult.Reject.AUTHORITY,
			"docs/12 §02.1：资格链按 1→2→3 顺序短路，权限与席位同时不满足时必须报 E_AUTHORITY")


## 检验 docs/12 §02.1 的集团否决分支：veto_bloc_mask 命中且该集团立场跌到底 ⇒ E_BLOC_VETO。
## 立场经形参传入（INV-125），本类不引用 JWInterestGroups。
func test_check_authority_bloc_veto_uses_passed_in_stance() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	pol.legal_authority_mask = 1 << 3
	pol.seats_gov = 90
	pol.seats_total = SEATS_TOTAL
	var pidx: int = 5
	var hostile: PackedInt64Array = _filled(JWUnits.STANCE_N, 1_000_000)
	hostile[JWIds.idx_stance(JWUnits.Bloc.BUSINESS, pidx)] = -1_000_000
	var friendly: PackedInt64Array = _filled(JWUnits.STANCE_N, 1_000_000)

	eq_int(pol.check_authority(3, 0, 1 << JWUnits.Bloc.BUSINESS, hostile, pidx),
			JWResult.Reject.BLOC_VETO,
			"docs/12 §02.1：business 有该政策域的否决权且立场 −1e6（区间下界）⇒ E_BLOC_VETO")
	eq_int(pol.check_authority(3, 0, 1 << JWUnits.Bloc.BUSINESS, friendly, pidx),
			JWResult.OK,
			"docs/12 §02.1：同一集团立场 +1e6 时不得否决")
	eq_int(pol.check_authority(3, 0, 0, hostile, pidx), JWResult.OK,
			"docs/12 §02.1：veto_bloc_mask 为 0 ⇒ 即使立场为 −1e6 也无人有否决权")
	eq_int(pol.check_authority(3, 0, 1 << JWUnits.Bloc.AGRI_COOP, hostile, pidx),
			JWResult.OK,
			"docs/12 §02.1：否决权属于 agri_coop 时，business 的敌意立场不得触发否决")


## 检验 docs/17 §4.24 的「只读，不改状态」后置条件：资格链不得留下任何副作用。
func test_check_authority_is_read_only() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	pol.legal_authority_mask = 1 << 3
	pol.seats_gov = 51
	var support_before: PackedInt64Array = pol.support.duplicate()
	var seats_before: int = pol.seats_gov
	var status_before: int = pol.mandate_status
	var admin_before: int = pol.admin_capacity_ppm
	var stance: PackedInt64Array = _filled(JWUnits.STANCE_N, -1_000_000)

	pol.check_authority(4, 900_000, 1 << JWUnits.Bloc.BUSINESS, stance, 5)

	eq_int_array(pol.support, support_before,
			"docs/17 §4.24：check_authority 标注「不改状态」，support 被改说明资格链有副作用")
	eq_int(pol.seats_gov, seats_before, "docs/17 §4.24：check_authority 不得改席位")
	eq_int(pol.mandate_status, status_before, "docs/17 §4.24：check_authority 不得改任期状态")
	eq_int(pol.admin_capacity_ppm, admin_before, "docs/17 §4.24：check_authority 不得改行政能力")


# ══ 七、选举、留任与终局（INV-127 / INV-128，ADV-G02 / G04） ═══════════════

## 检验 INV-127：选举只在 q ∈ {15, 31} 发生，其它季不得改席位。
func test_election_happens_only_at_q15_and_q31() -> void:
	var params: PackedInt64Array = _make_params()
	var pop: JWPopulation = _make_pop(100_000)

	var quiet: JWPolitics = _make_politics_at_base()
	quiet.support = _filled(G, 495_049)          # 落选口径
	quiet.seats_gov = 99
	quiet.review_and_terminate(_new_treasury(), pop, 14, 40, 0, params)
	eq_int(quiet.seats_gov, 99,
			"INV-127：q=14 不是选举季，seats_gov 不得被重算")
	check_false(quiet.run_terminated,
			"INV-127：q=14 不是选举季，不得因支持度不足而终局")

	var at15: JWPolitics = _make_politics_at_base()
	at15.support = _filled(G, 495_049)
	at15.seats_gov = 99
	at15.review_and_terminate(_new_treasury(), pop, 15, 40, 0, params)
	eq_int(at15.seats_gov, 50,
			"INV-126/127：q=15 必须用 seat_rule(495 049, 101) == 50 重算席位")

	var at31: JWPolitics = _make_politics_at_base()
	at31.support = _filled(G, 554_455)
	at31.seats_gov = 1
	at31.review_and_terminate(_new_treasury(), pop, 31, 40, 0, params)
	eq_int(at31.seats_gov, SEATS_GOV_BASE,
			"INV-127：q=31 是第二个选举季，必须用 seat_rule(554 455, 101) == 56 重算席位")


## 检验 docs/12 §8.5：`seats_gov × 2 <= seats_total` 即失去执政（刚好过半算失去）。
## 50/101 ⇒ 100 <= 101 ⇒ 终局；51/101 ⇒ 102 > 101 ⇒ 留任。
func test_lost_election_boundary_is_bare_majority() -> void:
	var params: PackedInt64Array = _make_params()
	var pop: JWPopulation = _make_pop(100_000)

	var lost: JWPolitics = _make_politics_at_base()
	lost.support = _filled(G, 495_049)
	lost.review_and_terminate(_new_treasury(), pop, 15, 40, 0, params)
	check(lost.run_terminated,
			"docs/12 §8.5：50 席 × 2 == 100 <= 101 ⇒ 必须终局")
	eq_int(lost.termination_reason, JWUnits.Termination.LOST_ELECTION,
			"docs/12 §8.5：选举失利的终局原因必须是 lost_election")

	var kept: JWPolitics = _make_politics_at_base()
	kept.support = _filled(G, 504_951)
	kept.review_and_terminate(_new_treasury(), pop, 15, 40, 0, params)
	eq_int(kept.seats_gov, 51,
			"INV-126：seat_rule(504 951, 101) == 51")
	check_false(kept.run_terminated,
			"docs/12 §8.5：51 席 × 2 == 102 > 101 ⇒ 留任，不得终局")


## 检验 docs/12 §8.5：q == horizon_q − 1 ⇒ 以 horizon 收尾。
func test_horizon_termination_at_last_quarter() -> void:
	var params: PackedInt64Array = _make_params()
	var pop: JWPopulation = _make_pop(100_000)

	var early: JWPolitics = _make_politics_at_base()
	early.support = _filled(G, 900_000)
	early.review_and_terminate(_new_treasury(), pop, 38, 40, 0, params)
	check_false(early.run_terminated,
			"docs/12 §8.5：q=38 < horizon_q − 1 == 39，不得提前以 horizon 收尾")

	var last: JWPolitics = _make_politics_at_base()
	last.support = _filled(G, 900_000)
	last.review_and_terminate(_new_treasury(), pop, 39, 40, 0, params)
	check(last.run_terminated,
			"docs/12 §8.5：q == horizon_q − 1 == 39 ⇒ 必须终局")
	eq_int(last.termination_reason, JWUnits.Termination.HORIZON,
			"docs/12 §8.5：跑满 40 季的终局原因必须是 horizon")


## 检验 docs/12 §8.5：连续 param.no_confidence_q 季 mandate_status == LOST ⇒ 终局。
## 本夹具 no_confidence_q == 2：第 1 季不终局，第 2 季终局。
func test_no_confidence_termination_needs_full_streak() -> void:
	var params: PackedInt64Array = _make_params()
	var pop: JWPopulation = _make_pop(100_000)
	var pol: JWPolitics = _make_politics_at_base()
	pol.support = _filled(G, 900_000)
	pol.mandate_status = JWUnits.MandateStatus.LOST

	pol.review_and_terminate(_new_treasury(), pop, 4, 40, 0, params)
	check_false(pol.run_terminated,
			"docs/12 §8.5：param.no_confidence_q == 2，第 1 个 LOST 季不得终局")
	pol.mandate_status = JWUnits.MandateStatus.LOST
	pol.review_and_terminate(_new_treasury(), pop, 5, 40, 0, params)
	check(pol.run_terminated,
			"docs/12 §8.5：连续第 2 个 LOST 季必须终局")
	eq_int(pol.termination_reason, JWUnits.Termination.LOST_CONFIDENCE,
			"docs/12 §8.5：不信任终局的原因码必须是 lost_confidence")


## 检验 docs/12 §8.5：连续 param.default_grace_q 季付不出第 1 档 ⇒ 财政重整失败终局。
## 连续季数由 JWTreasury 汇总后经形参 default_streak_q 传入（docs/17 §4.24）。
func test_default_streak_termination_at_grace_boundary() -> void:
	var params: PackedInt64Array = _make_params()
	var pop: JWPopulation = _make_pop(100_000)

	var within: JWPolitics = _make_politics_at_base()
	within.support = _filled(G, 900_000)
	within.review_and_terminate(_new_treasury(), pop, 8, 40, 2, params)
	check_false(within.run_terminated,
			"docs/12 §8.5：default_streak_q == 2 < param.default_grace_q == 3，宽限期内不得终局")

	var over: JWPolitics = _make_politics_at_base()
	over.support = _filled(G, 900_000)
	over.review_and_terminate(_new_treasury(), pop, 8, 40, 3, params)
	check(over.run_terminated,
			"docs/12 §8.5：default_streak_q == 3 == param.default_grace_q ⇒ 必须终局")
	eq_int(over.termination_reason, JWUnits.Termination.FISCAL_RESTRUCTURING_FAILED,
			"docs/12 §8.5：财政终局的原因码必须是 fiscal_restructuring_failed")


## 检验 INV-128：终局判定式中不含任何 GDP 项，且终局后再判定不得改写已定的终局原因（ADV-G04）。
func test_termination_takes_no_gdp_input_and_is_sticky() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	var args: PackedStringArray = _method_args(pol, "review_and_terminate")
	check(args.size() > 0, "docs/17 §4.24：JWPolitics 必须有 review_and_terminate 方法")
	for a: String in args:
		check_false(a.findn("gdp") >= 0 or a.findn("output") >= 0 or a.findn("growth") >= 0,
				"INV-128：review_and_terminate 的形参 \"%s\" 把产出口径引进了终局判定（经济下滑本身不是失败）" % a)
	check_false(_prop_exists(pol, "gdp_production_uu"),
			"INV-128：JWPolitics 不得持有任何 GDP 字段")

	var params: PackedInt64Array = _make_params()
	var pop: JWPopulation = _make_pop(100_000)
	pol.support = _filled(G, 495_049)
	pol.review_and_terminate(_new_treasury(), pop, 15, 40, 0, params)
	eq_int(pol.termination_reason, JWUnits.Termination.LOST_ELECTION,
			"前置：q=15 选举失利，终局原因为 lost_election")
	var reason: int = pol.termination_reason
	var seats: int = pol.seats_gov
	pol.review_and_terminate(_new_treasury(), pop, 16, 40, 9, params)
	eq_int(pol.termination_reason, reason,
			"ADV-G04：已终局的存档再次判定不得改写终局原因（终局是终态）")
	eq_int(pol.seats_gov, seats,
			"ADV-G04 / INV-128：终局后状态不得再被推进（席位必须逐位不变）")


## 检验 docs/12 §8.5：预算审查的判定必须**有条件**——
##   (a) 未到审查季（budget_review_due == 0）不得判定；
##   (b) 审查季但欠付为 0、无连续赤字 ⇒ 留在 ok；
##   (c) 审查季且欠付巨大 ⇒ 判成 at_risk。
## (b) 与 (c) 同为 at_risk 即说明审查是无条件置位，「连续赤字超限或欠付超限」这条判据没有落地。
func test_budget_review_flags_at_risk_only_on_breach() -> void:
	var params: PackedInt64Array = _make_params()
	var pop: JWPopulation = _make_pop(100_000)

	var not_due: JWPolitics = _make_politics_at_base()
	not_due.support = _filled(G, 900_000)
	not_due.f_budget_review_due = 0
	var t0: JWTreasury = _new_treasury()
	t0.arrears = 2_000_000_000_000
	not_due.review_and_terminate(t0, pop, 5, 40, 0, params)
	eq_int(not_due.mandate_status, JWUnits.MandateStatus.OK,
			"docs/12 §8.5：budget_review_due == 0 的季根本不做预算审查，mandate_status 不得被改写")

	var clean: JWPolitics = _make_politics_at_base()
	clean.support = _filled(G, 900_000)
	clean.f_budget_review_due = 1
	var t1: JWTreasury = _new_treasury()
	t1.arrears = 0
	clean.review_and_terminate(t1, pop, 3, 40, 0, params)
	eq_int(clean.mandate_status, JWUnits.MandateStatus.OK,
			"docs/12 §8.5：欠付为 0、无连续赤字的审查季不得判成 at_risk（判据是「超限」，不是「做了审查」）")
	check_false(clean.run_terminated,
			"docs/12 §8.5：一次干净的预算审查不得终局")

	var dirty: JWPolitics = _make_politics_at_base()
	dirty.support = _filled(G, 900_000)
	dirty.f_budget_review_due = 1
	var t2: JWTreasury = _new_treasury()
	t2.arrears = 2_000_000_000_000              # 2 000 U 的欠付，远超任何合理阈值
	dirty.review_and_terminate(t2, pop, 3, 40, 0, params)
	eq_int(dirty.mandate_status, JWUnits.MandateStatus.AT_RISK,
			"docs/12 §8.5：欠付 2 000 U 的审查季必须判成 at_risk；仍为 ok 说明审查读不到欠付")


# ══ 八、事件落点白名单（INV-130，ADV-G03） ════════════════════════════════

## 检验 INV-130 / ADV-G03：事件效果落点必须是**正向枚举**的白名单。
## 不在白名单内的 target_code 一律登记 Fault.WRITE_OUT_OF_SCOPE，且不得改动任何状态。
func test_event_delta_rejects_targets_outside_whitelist() -> void:
	var pol: JWPolitics = _make_politics_at_base()
	var support_before: PackedInt64Array = pol.support.duplicate()
	var trust_before: PackedInt64Array = pol.trust.duplicate()
	var expectation_before: PackedInt64Array = pol.expectation.duplicate()
	var admin_before: int = pol.admin_capacity_ppm

	for bad: int in [-1, 9_999, 1_000_000]:
		JWResult.clear_pending()
		pol.apply_event_delta(bad, 0, 50_000)
		eq_int(JWResult.pending_code(), JWResult.Fault.WRITE_OUT_OF_SCOPE,
				"INV-130 / ADV-G03：target_code=%d 不在白名单内，必须登记 WRITE_OUT_OF_SCOPE（白名单要正向枚举，不是黑名单）" % bad)
	JWResult.clear_pending()

	eq_int_array(pol.support, support_before,
			"INV-130：非法落点不得改动 support")
	eq_int_array(pol.trust, trust_before,
			"INV-130：非法落点不得改动 trust")
	eq_int_array(pol.expectation, expectation_before,
			"INV-130：非法落点不得改动 expectation")
	eq_int(pol.admin_capacity_ppm, admin_before,
			"INV-130：非法落点不得改动 admin_capacity_ppm")


# ══ 九、集团成员与组织影响力（INV-125 / INV-129，docs/12 §8.3） ════════════

## 检验 INV-129 与 docs/12 §8.3：membership_persons 是「加权人数」——
## Σ_g mul_ppm(population[g], affiliation_ppm[g][b])，允许重叠（各集团之和可超过总人口）。
func test_membership_is_weighted_persons_and_allows_overlap() -> void:
	var bl: JWInterestGroups = _make_blocs()
	var pop: JWPopulation = _make_pop(0)
	var g0: int = JWIds.idx_group(0, JWUnits.Age.WORKING, JWUnits.Skill.LOW)
	var popv: PackedInt64Array = _filled(G, 0)
	popv[g0] = 1_000_000
	pop.population = popv
	var af: PackedInt64Array = _filled(JWUnits.AFFIL_N, 0)
	af[JWIds.idx_affil(g0, JWUnits.Bloc.AGRI_COOP)] = 300_000
	af[JWIds.idx_affil(g0, JWUnits.Bloc.BUSINESS)] = 800_000
	bl.affiliation_ppm = af

	eq_int(bl.membership_persons(pop, JWUnits.Bloc.AGRI_COOP), 300_000,
			"INV-129：mul_ppm(1 000 000 人, 300 000 ppm) == 300 000 加权人数")
	eq_int(bl.membership_persons(pop, JWUnits.Bloc.BUSINESS), 800_000,
			"INV-129：mul_ppm(1 000 000 人, 800 000 ppm) == 800 000 加权人数")
	eq_int(bl.membership_persons(pop, JWUnits.Bloc.LABOR_PUBLIC), 0,
			"INV-129：归属比例为 0 的集团加权人数为 0")
	var total: int = bl.membership_persons(pop, 0) + bl.membership_persons(pop, 1) \
			+ bl.membership_persons(pop, 2)
	check(total > popv[g0],
			"INV-129：允许重叠成员 ⇒ 三集团加权人数之和 %d 可以超过该组人口 %d；若被压到人口以内说明成员被强行去重了"
					% [total, popv[g0]])


## 检验 INV-129：集团成员规模由群组人口映射得出——人口结构一变，成员规模同步变。
## 这是「集团成员随结构变化」的可测形态（docs/12 §8.3）。
func test_membership_follows_population_structure_change() -> void:
	var bl: JWInterestGroups = _make_blocs()
	var pop: JWPopulation = _make_pop(0)
	var g0: int = JWIds.idx_group(0, JWUnits.Age.WORKING, JWUnits.Skill.LOW)
	var g1: int = JWIds.idx_group(JWUnits.Region.HAIJIA, JWUnits.Age.WORKING, JWUnits.Skill.MID)
	var af: PackedInt64Array = _filled(JWUnits.AFFIL_N, 0)
	af[JWIds.idx_affil(g0, JWUnits.Bloc.LABOR_PUBLIC)] = 300_000
	af[JWIds.idx_affil(g1, JWUnits.Bloc.LABOR_PUBLIC)] = 500_000
	bl.affiliation_ppm = af

	var v0: PackedInt64Array = _filled(G, 0)
	v0[g0] = 1_000_000
	pop.population = v0
	eq_int(bl.membership_persons(pop, JWUnits.Bloc.LABOR_PUBLIC), 300_000,
			"INV-129：只有 g0 有人时 == mul_ppm(1e6, 300 000) == 300 000")

	var v1: PackedInt64Array = v0.duplicate()
	v1[g1] = 2_000_000                       # 海岬中技能组新增 200 万人
	pop.population = v1
	eq_int(bl.membership_persons(pop, JWUnits.Bloc.LABOR_PUBLIC), 1_300_000,
			"INV-129：人口结构变化后 == 300 000 + mul_ppm(2e6, 500 000) == 1 300 000；不变说明成员规模是写死的剧本常量")

	var v2: PackedInt64Array = v1.duplicate()
	v2[g0] = 0                               # 该组清空
	pop.population = v2
	eq_int(bl.membership_persons(pop, JWUnits.Bloc.LABOR_PUBLIC), 1_000_000,
			"INV-129：群组清空后其贡献必须归零 ⇒ 1 000 000")


## 检验 docs/17 §4.25 的越界语义：下标非法 ⇒ INDEX_OUT_OF_RANGE 并返回 0（不得静默给值）。
func test_bloc_accessors_reject_out_of_range_indices() -> void:
	var bl: JWInterestGroups = _make_blocs()
	var st: PackedInt64Array = _filled(JWUnits.STANCE_N, 0)
	st[JWIds.idx_stance(JWUnits.Bloc.BUSINESS, 5)] = 420_000
	bl.stance = st
	eq_int(bl.stance_of(JWUnits.Bloc.BUSINESS, 5), 420_000,
			"docs/17 §4.25：合法下标必须按 idx_stance(b, p) == b·12 + p 取到 420 000")

	JWResult.clear_pending()
	eq_int(bl.stance_of(JWUnits.BLOC_N, 0), 0,
			"docs/17 §4.25：集团下标越界返回 0")
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE,
			"docs/17 §4.25：集团下标越界必须登记 INDEX_OUT_OF_RANGE，不得静默")

	JWResult.clear_pending()
	eq_int(bl.stance_of(0, JWUnits.POLICY_N), 0,
			"docs/17 §4.25：政策下标越界返回 0")
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE,
			"docs/17 §4.25：政策下标越界必须登记 INDEX_OUT_OF_RANGE")

	JWResult.clear_pending()
	eq_int(bl.org_power(JWUnits.BLOC_N), 0,
			"docs/17 §4.25：org_power 下标越界返回 0")
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE,
			"docs/17 §4.25：org_power 下标越界必须登记 INDEX_OUT_OF_RANGE")
	JWResult.clear_pending()


## 检验 docs/12 §2.1 与 docs/17 §4.25：has_veto 只读 veto_domain_mask 的对应位，逐集团逐政策独立。
##
## 位序的口径依据（本条原先按「位序 == 政策下标」写，与契约不符，已按契约改正）：
##   docs/10 §8.3 `content.bloc.veto_domains[]` 的语义是「可否决的**改革域** id 列表」；
##   docs/11 §5.10 politics_init 里它的取值是 `["land_reform"]` / `["tax_law"]` 之类的域名；
##   docs/12 §2.1 的否决判据写的是「policy_def[p] 的 **domain** ∈ bloc.veto_domains[b]」。
## 三处一致：位序是改革域下标（0…4），不是政策下标。政策与域之间隔着一张映射表
## （`JWInterestGroups.policy_domain`，类 C，写入者 LOAD；内容层尚缺字段，见 OQ-252），
## 本测试在此扮演 LOAD 把它写满。四条断言一条不减：域命中、域未命中、以及两条不得串集团。
func test_has_veto_reads_domain_mask_per_bloc_and_policy() -> void:
	var bl: JWInterestGroups = _make_blocs()
	var mask: PackedInt64Array = _filled(B, 0)
	mask[JWUnits.Bloc.BUSINESS] = 1 << JWInterestGroups.DOMAIN_TAX_LAW
	bl.veto_domain_mask = mask
	# 政策 5 归 tax_law 域，其余政策归 social_program 域（工商业联盟对后者没有否决权）。
	var domains: PackedInt64Array = _filled(JWUnits.POLICY_N,
			JWInterestGroups.DOMAIN_SOCIAL_PROGRAM)
	domains[5] = JWInterestGroups.DOMAIN_TAX_LAW
	bl.policy_domain = domains

	check(bl.has_veto(JWUnits.Bloc.BUSINESS, 5),
			"docs/12 §2.1：政策 5 属 tax_law 域且 veto_domain_mask[business] 已置该域位 ⇒ 有否决权")
	check_false(bl.has_veto(JWUnits.Bloc.BUSINESS, 4),
			"docs/12 §2.1：政策 4 属 social_program 域，该域位未置 ⇒ 无否决权")
	check_false(bl.has_veto(JWUnits.Bloc.AGRI_COOP, 5),
			"docs/17 §4.25：否决权不得在集团之间串位")
	check_false(bl.has_veto(JWUnits.Bloc.LABOR_PUBLIC, 5),
			"docs/17 §4.25：否决权不得在集团之间串位")

	# OQ-252 的安全默认：LOAD 还没写入 policy_domain 时，未知归属不得凭默认值长出否决权。
	var unmapped: JWInterestGroups = _make_blocs()
	unmapped.veto_domain_mask = mask
	for p: int in JWUnits.POLICY_N:
		check_false(unmapped.has_veto(JWUnits.Bloc.BUSINESS, p),
				"OQ-252：policy_domain 未由 LOAD 写入时，政策 %d 不得凭 allocate() 的默认值取得否决资格" % p)


## 检验 docs/17 §4.25：stance_array() 必须原样返回 36 项立场表（供资格链按形参传入，INV-125）。
func test_stance_array_exposes_full_table_for_pass_by_value() -> void:
	var bl: JWInterestGroups = _make_blocs()
	var st: PackedInt64Array = _filled(JWUnits.STANCE_N, 0)
	st[JWIds.idx_stance(JWUnits.Bloc.AGRI_COOP, 0)] = -700_000
	st[JWIds.idx_stance(JWUnits.Bloc.LABOR_PUBLIC, 11)] = 250_000
	bl.stance = st

	var out: PackedInt64Array = bl.stance_array()
	eq_int(out.size(), JWUnits.STANCE_N,
			"docs/17 §4.25：stance_array 长度必须是 BLOC_N × POLICY_N == 36")
	eq_int_array(out, st,
			"docs/17 §4.25：stance_array 必须逐位等于 state.bloc.stance_ppm，不得做任何折算")


# ══ 十、集团反应与 R-SCALE-01（docs/12 §8.3，INV-125） ════════════════════

## 检验 docs/12 §8.3 的 org_power 合成式：
##   org_power = mul_ppm(prev, inertia) + mul_ppm(size_ppm, w_size) + mul_ppm(res_ppm, w_resource)
## 本夹具：prev = 400 000、inertia = 600 000 ⇒ 240 000；
##         membership == nation_population ⇒ size_ppm = 1e6，× w_size 200 000 ⇒ 200 000；
##         resource == bloc_resource_ref_uu ⇒ res_ppm = 1e6，× w_resource 200 000 ⇒ 200 000。
##         合计 640 000。三项权重之和 == 1e6，故上界恒为 1e6（INV：org_power ∈ [0, 1e6]）。
func test_update_blocs_composes_org_power_from_size_and_resource() -> void:
	var params: PackedInt64Array = _make_params()
	var bl: JWInterestGroups = _make_blocs()
	var pop: JWPopulation = _make_pop(0)
	var g0: int = JWIds.idx_group(0, JWUnits.Age.WORKING, JWUnits.Skill.LOW)
	var popv: PackedInt64Array = _filled(G, 0)
	popv[g0] = 1_000_000
	pop.population = popv
	var af: PackedInt64Array = _filled(JWUnits.AFFIL_N, 0)
	for b: int in B:
		af[JWIds.idx_affil(g0, b)] = 1_000_000
	bl.affiliation_ppm = af
	bl.resource = _filled(B, params[JWUnits.Param.BLOC_RESOURCE_REF_UU])

	bl.update_blocs(_new_sectors(), _new_labor(), _new_capital(), pop, 0, _new_defs(), params)

	for b: int in B:
		eq_int(bl.org_power(b), 640_000,
				"docs/12 §8.3：集团 %d 的 org_power = mul_ppm(400000,600000) + mul_ppm(1e6,200000) + mul_ppm(1e6,200000) == 640 000" % b)
		in_range_int(bl.stance_of(b, 0), -1_000_000, 1_000_000,
				"docs/12 §8.3：集团 %d 对政策 0 的立场必须落在 [−1e6, 1e6]" % b)


## 检验 docs/18 R-SCALE-01 连带要求 1：`res_ppm` 必须走 mul_div_floor。
## 新刻度下 resource_uu 的契约上界 AMOUNT_MAX(4e15) × PPM(1e6) = 4e21 真的溢出 int64，
## 裸乘会登记 INT_OVERFLOW 并返回 0——组织影响力会在最富的集团上突然塌成 0。
func test_update_blocs_resource_ratio_survives_amount_max() -> void:
	var params: PackedInt64Array = _make_params()
	# ref 取 4e9：真值 4e15 × 1e6 / 4e9 == 1e12，int64 装得下（clamp 后为 1e6）；
	# 而裸乘的中间量 4e15 × 1e6 == 4e21 装不下。两者只差一个 mul_div_floor。
	params[JWUnits.Param.BLOC_RESOURCE_REF_UU] = 4_000_000_000
	var bl: JWInterestGroups = _make_blocs()
	var pop: JWPopulation = _make_pop(100_000)
	bl.resource = _filled(B, JWUnits.AMOUNT_MAX)

	JWResult.clear_pending()
	bl.update_blocs(_new_sectors(), _new_labor(), _new_capital(), pop, 0, _new_defs(), params)

	ne_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW,
			"R-SCALE-01：resource_uu == AMOUNT_MAX(4e15) 时 mul(resource, PPM) = 4e21 溢出 int64；登记 INT_OVERFLOW 说明该处没走 mul_div_floor")
	for b: int in B:
		in_range_int(bl.org_power(b), 0, 1_000_000,
				"docs/12 §8.3：res_ppm 被 clamp 到 1e6 后，集团 %d 的 org_power 仍必须落在 [0, 1e6]" % b)
		ge_int(bl.org_power(b), JWMath.mul_ppm(400_000, params[JWUnits.Param.BLOC_ORG_INERTIA_PPM]),
				"R-SCALE-01：溢出被静默吞掉会让 org_power 掉到惯性项之下（集团 %d）" % b)


## 检验 docs/17 §4.25 的失败行：`care_prev == 0` 时用 max(|care_prev|, 1) 兜底，不得除零。
func test_update_blocs_does_not_divide_by_zero_care_prev() -> void:
	var params: PackedInt64Array = _make_params()
	var bl: JWInterestGroups = _make_blocs()
	bl.care_prev = _filled(B, 0)
	var pop: JWPopulation = _make_pop(100_000)

	JWResult.clear_pending()
	bl.update_blocs(_new_sectors(), _new_labor(), _new_capital(), pop, 0, _new_defs(), params)

	ne_int(JWResult.pending_code(), JWResult.Fault.DIV_ZERO,
			"docs/17 §4.25：care_prev == 0 必须走 max(absi(care_prev), 1)，不得登记 DIV_ZERO")
