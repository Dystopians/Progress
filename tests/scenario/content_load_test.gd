## 内容包载入用例（content-load）：`content/` 全部 JSON 载入之后，剧本硬约束必须逐条成立；
## 缺字段或 ID 悬空时必须**拒绝启动**。
##
## 依据（只依据契约，不依据实现）：
##   - docs/18_rulings.md  R-SCALE-01（1 U = 10⁹ μU）、R-SEASON-01、R-ACCESS-01
##   - docs/12_simulation_contract.md §1 01.8（分期表）、§2 02.0（年计划拆季与基年复核表）
##   - docs/11_data_contract.md §1 规则 4、§3 方言、§5.4、§5.11、§7（加载流水线与 E_* 码）
##   - docs/10_variable_dictionary.md §14 INV-018 / INV-023 / INV-141…INV-149
##   - docs/17_api_skeleton.md §1.6 状态块协议、§4.31 JWContentLoader
##   - docs/30_quality_gates.md `FX-BASE`、T-S-B-01、T-U-B-07、T-S-D-04、T-U-D-13、T-U-D-14、T-S-A-24
##
## 刻度约定：本文件里**所有金额字面量都是新刻度**（R-SCALE-01）。docs/30 与 content/ 里若还留着
## 旧刻度（5e7 / 2e6 / 1e8 / 1e6）的数字，那是尚未同步的残留，不是本文件的依据——
## 裁定文件优先级最高，且 docs/10 §14 已按裁定改写。
extends JWTest

# ── 契约锁定值（计划书 §05 + R-SCALE-01；每个数都在上面的文档里能找到出处） ──

## 1 U 的 μU 数（R-SCALE-01）
const U: int = 1_000_000_000
## 总人口（INV-141）
const POP_TOTAL: int = 24_000_000
## 四地区人口，顺序 == docs/10 §0.5 稠密下标 0 北原 / 1 中州 / 2 海岬 / 3 西岭（INV-141）
const POP_BY_REGION: PackedInt64Array = [9_000_000, 7_000_000, 5_000_000, 3_000_000]
## 政府债务 50 U（INV-144）
const DEBT_UU: int = 50 * U
## 国库现金 2 U（INV-145）
const GOV_CASH_UU: int = 2 * U
## 年收入计划 20 U（INV-146）
const PLAN_RECEIPTS_UU: int = 20 * U
## 年支出计划（含利息、不含还本）22 U（INV-146）
const PLAN_EXPENDITURE_UU: int = 22 * U
## 基线年赤字 2 U（INV-146）
const PLAN_DEFICIT_UU: int = 2 * U
## 基年四季逐批次票息之和（docs/12 §2 02.0 的基年复核表；INV-147）
const INTEREST_YEAR_UU: int = 2_033_700_000
## 基年四季逐季利息（docs/12 §2 02.0 的基年复核表）
const INTEREST_BY_Q_UU: PackedInt64Array = [523_500_000, 513_450_000, 503_400_000, 493_350_000]
## 基年全年名义 GDP 100 U（INV-118）
const BASE_YEAR_GDP_UU: int = 100 * U
## 失业率目标 8%（INV-143 的中心值；剧本实配就业分配恰好命中）
const UNEMP_PPM: int = 80_000
## INV-143 允许的唯一非零容差带
const UNEMP_LO_PPM: int = 79_500
const UNEMP_HI_PPM: int = 80_500
## 全经济现金总量（INV-018，值本身由 scenario.total_cash_uu 提供，不在此另抄一份）。
## R-REGION-01 把企业现金补到「一季工资 + 投入」：企业 20 → 28.716 U，全经济 55 → 63.716 U。
const TOTAL_CASH_UU: int = 63_716_000_000

const CONTENT_ROOT: String = "res://content"
const SCENARIO_DIR: String = "res://content/scenarios/chengwan"

## 被测模块的脚本路径（用 load() + can_instantiate() 实例化，见 _instantiate 的理由）。
const LOADER_PATH: String = "res://systems/content_loader.gd"
const COMMANDS_PATH: String = "res://systems/commands.gd"
const EVENTS_PATH: String = "res://systems/event_engine.gd"
const RUNNER_PATH: String = "res://systems/turn_runner.gd"

## 载入一次、全文件共享的基线状态（每个测试方法都会新建实例，重复载入既慢又没有额外信息）。
static var _base_st: JWSimState = null
static var _base_code: int = -1
static var _base_loaded: bool = false

## 临时内容包的计数器，保证各用例的目录互不干扰。
static var _tmp_seq: int = 0


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(0)


func after_each() -> void:
	JWResult.clear_pending()


# ══════════════════════════════════════════════════════════════════════════
# A 组 内容文件层：磁盘上的 JSON 是否还写着契约锁定值
#   这一组不经过加载器，因此即使加载器尚未实现也能跑；它把「内容漂移」与「加载器缺陷」分开。
# ══════════════════════════════════════════════════════════════════════════

## docs/11 §5.4（`unit_declaration.money_micro_per_unit == JWUnits.U_SCALE`，否则 E_UNIT_MISMATCH）
## + 裁定 R-SCALE-01。四个常量在裁定后不再同值（1e9 / 1e6 / 1e6 / 1e9），必须逐个比对。
func test_scenario_unit_declaration_matches_engine_scale() -> void:
	var sc: Dictionary = _read_json(SCENARIO_DIR + "/scenario.json")
	has_key(sc, "unit_declaration", "scenario.json 必须声明 unit_declaration（docs/11 §5.4 必填）")
	var ud: Dictionary = sc.get("unit_declaration", {})
	eq_int(int(ud.get("money_micro_per_unit", -1)), JWUnits.U_SCALE,
			"money_micro_per_unit 必须逐字等于 JWUnits.U_SCALE（裁定 R-SCALE-01：1 U = 10⁹ μU；"
			+ "docs/11 §5.4 规定不等即 E_UNIT_MISMATCH）")
	eq_int(int(ud.get("quantity_micro_per_qs", -1)), JWUnits.Q_SCALE,
			"quantity_micro_per_qs 必须等于 JWUnits.Q_SCALE（R-SCALE-01 明确 Q_SCALE 不变）")
	eq_int(int(ud.get("ppm_scale", -1)), JWUnits.PPM,
			"ppm_scale 必须等于 JWUnits.PPM（R-SCALE-01 明确 PPM 不变）")
	eq_int(int(ud.get("base_price_uu_per_qs", -1)), JWUnits.BASE_PRICE,
			"base_price_uu_per_qs 必须等于 JWUnits.BASE_PRICE == 10⁹（R-SCALE-01 的表）")


## INV-141（Σ 人口 == 24 000 000；北原 9 / 中州 7 / 海岬 5 / 西岭 3 百万）
## 对应 docs/30 的 T-S-B-01 载入后一段。
func test_population_init_file_matches_locked_totals() -> void:
	var pop: Dictionary = _read_json(SCENARIO_DIR + "/population_init.json")
	var groups: Array = pop.get("groups", [])
	eq_int(groups.size(), JWUnits.GROUP,
			"population_init.groups 必须恰好 36 组（INV-142：4 地区 × 3 年龄 × 3 技能全组合）")
	var total: int = 0
	var by_region: PackedInt64Array = PackedInt64Array()
	by_region.resize(JWUnits.R)
	by_region.fill(0)
	for g: Variant in groups:
		var gd: Dictionary = g
		var persons: int = int(gd.get("population_persons", -1))
		ge_int(persons, 0, "群组 %s 的 population_persons 必须 ≥ 0（docs/10 §6.1 区间）"
				% str(gd.get("group_id", "?")))
		total += persons
		var r: int = _region_index_of_group_id(str(gd.get("group_id", "")))
		if r >= 0:
			by_region[r] += persons
		else:
			fail("群组 ID %s 的地区段不在 docs/10 §0.5 的四地区枚举内" % str(gd.get("group_id", "")))
	eq_int(total, POP_TOTAL, "Σ population_persons 必须精确等于 24 000 000（计划书 §05 锁定值，INV-141）")
	for r: int in JWUnits.R:
		eq_int(by_region[r], POP_BY_REGION[r],
				"地区下标 %d 的人口必须精确等于 %d（计划书 §05 锁定的 900/700/500/300 万，INV-141）"
				% [r, POP_BY_REGION[r]])


## INV-143（反算失业率 ∈ [79 500, 80 500] ppm，且**剧本 schema 中不存在失业率输入字段**）
## 对应 docs/30 的 T-U-B-07。
func test_population_init_unemployment_is_derived_not_declared() -> void:
	var pop: Dictionary = _read_json(SCENARIO_DIR + "/population_init.json")
	var hits: PackedStringArray = PackedStringArray()
	_collect_keys_containing(pop, "", "unemploy", hits)
	eq_int(hits.size(), 0,
			"population_init.json 里不得出现任何失业率输入字段（INV-143：失业率只能由就业分配反算；"
			+ "命中的键：%s）" % str(hits))

	var groups: Array = pop.get("groups", [])
	var labor: int = 0
	var employed: int = 0
	for g: Variant in groups:
		var gd: Dictionary = g
		var persons: int = int(gd.get("population_persons", 0))
		var part: int = int(gd.get("participation_ppm", 0))
		labor += JWMath.mul_div_floor(persons, part, JWUnits.PPM)
		var emp: Dictionary = gd.get("employed_persons", {})
		for k: Variant in emp.keys():
			employed += int(emp[k])
	ge_int(labor, 1, "劳动力口径分母必须 > 0，否则失业率无定义（Q-ADV-03 禁止 max(分母,1) 兜底）")
	le_int(employed, labor,
			"在岗人数不得超过同口径劳动力（INV-075；在岗 %d，劳动力 %d）" % [employed, labor])
	var ppm: int = JWMath.mul_div_floor(labor - employed, JWUnits.PPM, labor)
	in_range_int(ppm, UNEMP_LO_PPM, UNEMP_HI_PPM,
			"反算失业率必须落在 INV-143 的 [79 500, 80 500] ppm 带内")
	eq_int(ppm, UNEMP_PPM,
			("计划书 §05 的 8%% 在本剧本的就业分配下应当精确命中 80 000 ppm"
			+ "（劳动力 %d，在岗 %d，失业 %d）") % [labor, employed, labor - employed])


## INV-144 / INV-145 / INV-146（债务 50 U、国库现金 2 U、年收支 20 U / 22 U、赤字 2 U）
## 对应 docs/30 的 T-S-D-04 载入后一段与 T-U-D-13。
func test_government_init_file_locks_cash_debt_and_annual_plan() -> void:
	var gov: Dictionary = _read_json(SCENARIO_DIR + "/government_init.json")
	var g: Dictionary = gov.get("gov", {})
	eq_int(int(g.get("cash_uu", -1)), GOV_CASH_UU,
			"gov.cash_uu 必须精确等于 2 U == 2 000 000 000 μU（计划书 §05 锁定，INV-145 / V-FIN-01）")

	var bonds: Array = gov.get("bonds", [])
	ge_int(bonds.size(), 1, "government_init 必须至少有一个存量债券批次（INV-144 的求和对象）")
	var debt: int = 0
	for b: Variant in bonds:
		var bd: Dictionary = b
		var outstanding: int = int(bd.get("principal_outstanding_uu", -1))
		var initial: int = int(bd.get("principal_initial_uu", -1))
		ge_int(initial, 1, "批次 %s 的 principal_initial_uu 必须 > 0（docs/10 §3.3 区间）"
				% str(bd.get("bond_id", "?")))
		in_range_int(outstanding, 0, initial,
				"批次 %s 的 principal_outstanding_uu 必须落在 [0, principal_initial_uu]（INV-028）"
				% str(bd.get("bond_id", "?")))
		debt += outstanding
	eq_int(debt, DEBT_UU,
			"Σ bond.principal_outstanding_uu 必须精确等于 50 U == 50 000 000 000 μU"
			+ "（计划书 §05 锁定，INV-144 / V-FIN-02）")

	var plan: Dictionary = gov.get("annual_plan", {})
	eq_int(int(plan.get("receipts_uu", -1)), PLAN_RECEIPTS_UU,
			"annual_plan.receipts_uu 必须等于 20 U（计划书 §05 锁定，INV-146）")
	eq_int(int(plan.get("expenditure_incl_interest_uu", -1)), PLAN_EXPENDITURE_UU,
			"annual_plan.expenditure_incl_interest_uu 必须等于 22 U（含利息不含还本，INV-146）")
	eq_int(int(plan.get("deficit_uu", -1)), PLAN_DEFICIT_UU,
			"annual_plan.deficit_uu 必须等于 2 U（INV-146）")
	eq_int(int(plan.get("expenditure_incl_interest_uu", 0)) - int(plan.get("receipts_uu", 0)),
			PLAN_DEFICIT_UU,
			"支出 − 收入 必须自洽地等于登记的赤字（V-FIN-03：三个数不允许各写各的）")

	var lines: Dictionary = plan.get("expenditure_lines_uu", {})
	var line_sum: int = 0
	for k: Variant in lines.keys():
		line_sum += int(lines[k])
	eq_int(line_sum, PLAN_EXPENDITURE_UU,
			"Σ expenditure_lines_uu 必须精确等于年支出计划（V-FIN-04：分项与总额不得脱钩）")


## INV-147（支出计划中的利息项 == 基年四季逐批次票息之和），对应 docs/30 的 T-U-D-14。
## 票息按 docs/12 §1 01.8 的分期表定义独立重算：
## 开局存量批次覆盖 `issue_q + 1 … maturity_q` 闭区间，期数 n = maturity_q − issue_q，等权重拆分。
func test_government_init_interest_line_equals_recomputed_coupons() -> void:
	var gov: Dictionary = _read_json(SCENARIO_DIR + "/government_init.json")
	var plan: Dictionary = gov.get("annual_plan", {})
	var lines: Dictionary = plan.get("expenditure_lines_uu", {})
	has_key(lines, "interest", "年支出计划必须有 interest 分项（INV-147 的比对对象）")

	var by_q: PackedInt64Array = PackedInt64Array()
	by_q.resize(4)
	by_q.fill(0)
	for b: Variant in gov.get("bonds", []):
		var bd: Dictionary = b
		var issue_q: int = int(bd.get("issue_q", 0))
		var maturity_q: int = int(bd.get("maturity_q", 0))
		var coupon: int = int(bd.get("coupon_ppm_per_q", 0))
		var initial: int = int(bd.get("principal_initial_uu", 0))
		var outstanding: int = int(bd.get("principal_outstanding_uu", 0))
		var bullet: bool = str(bd.get("amortization", "")) == "bullet"
		ge_int(maturity_q, issue_q + 1,
				"批次 %s 的 maturity_q 必须大于 issue_q（INV-037）" % str(bd.get("bond_id", "?")))
		var n: int = maturity_q - issue_q
		# 等权重最大余数法：余 r 单位给最早的 r 期，各 +1 μU（docs/12 §1 01.8）
		var per: int = JWMath.floor_div(initial, n)
		var rem: int = initial - per * n
		var bal: int = outstanding
		for t: int in 4:
			by_q[t] += JWMath.mul_div_floor(bal, coupon, JWUnits.PPM)
			if not bullet:
				var i_period: int = t - issue_q  # 第 t 季对应 amort_schedule 的第 (t − issue_q − 1) 期
				var due: int = per + (1 if (i_period - 1) < rem else 0)
				bal -= due
			elif maturity_q == t:
				bal = 0
		ge_int(bal, 0,
				"批次 %s 在基年四季内的余额不得为负（分期表与 principal_outstanding 脱钩即 BOND_MISMATCH）"
				% str(bd.get("bond_id", "?")))

	var total: int = 0
	for t: int in 4:
		eq_int(by_q[t], INTEREST_BY_Q_UU[t],
				"基年第 %d 季的逐批次票息之和必须等于 docs/12 §2 02.0 复核表登记的 %d μU"
				% [t, INTEREST_BY_Q_UU[t]])
		total += by_q[t]
	eq_int(total, INTEREST_YEAR_UU,
			"重算的基年全年票息必须等于 docs/12 §2 02.0 的 interest_year_uu == 2 033 700 000 μU")
	eq_int(int(lines.get("interest", -1)), total,
			"annual_plan.expenditure_lines_uu.interest 必须逐 μU 等于重算值"
			+ "（INV-147 / V-FIN-05：防止债务表与利息各写各的）")


## INV-148（基年全部门 price == base_price == 1 000 000 000 μU/Q_s），R-SCALE-01 的新值。
func test_scenario_prices_init_are_base_price() -> void:
	var sc: Dictionary = _read_json(SCENARIO_DIR + "/scenario.json")
	var pi: Dictionary = sc.get("prices_init", {})
	var cur: Array = pi.get("sector_uu_per_qs", [])
	var base: Array = pi.get("base_uu_per_qs", [])
	eq_int(cur.size(), JWUnits.S, "prices_init.sector_uu_per_qs 必须是 4 个部门（docs/10 §0.5）")
	eq_int(base.size(), JWUnits.S, "prices_init.base_uu_per_qs 必须是 4 个部门（docs/10 §0.5）")
	for s: int in mini(cur.size(), JWUnits.S):
		eq_int(int(cur[s]), JWUnits.BASE_PRICE,
				"部门 %d 的基年现行价必须等于 BASE_PRICE == 10⁹ μU/Q_s（INV-148 / R-SCALE-01）" % s)
		in_range_int(int(cur[s]), JWUnits.PRICE_MIN, JWUnits.PRICE_MAX,
				"部门 %d 的价格必须落在 [PRICE_MIN, PRICE_MAX]（INV-066，R-SCALE-01 后为 4e8…2.5e9）" % s)
	for s: int in mini(base.size(), JWUnits.S):
		eq_int(int(base[s]), JWUnits.BASE_PRICE,
				"部门 %d 的基年价必须恒等于 BASE_PRICE（docs/10 §8.1：content.price.base_uu_per_qs 恒 10⁹）" % s)


## INV-042（Σ season_factor_ppm == 1 000 000）+ 裁定 R-SEASON-01（季节系数只作用于基本支出）。
## 对应 docs/30 的 T-U-D-13。
func test_scenario_season_factors_sum_to_one() -> void:
	var sc: Dictionary = _read_json(SCENARIO_DIR + "/scenario.json")
	var sf: Dictionary = sc.get("season_factor_ppm", {})
	ge_int(sf.size(), 1, "scenario.json 必须声明 season_factor_ppm（docs/12 §2 02.0 的唯一读取点）")
	for k: Variant in sf.keys():
		var arr: Array = sf[k]
		eq_int(arr.size(), 4, "季节系数 %s 必须是四季四项" % str(k))
		var s: int = 0
		for v: Variant in arr:
			s += int(v)
		eq_int(s, JWUnits.PPM,
				"季节系数 %s 四季之和必须精确等于 1 000 000 ppm（INV-042，加载期检查）" % str(k))


## docs/11 §5.11（载入期冗余断言集合）+ R-SCALE-01。
## assertions.json 是断言不是输入；它自己写错刻度，等于把一个**被伪造的目标值**塞进拒绝逻辑，
## 正确的加载器会因为重算值与 expect 不符而拒绝启动整个剧本。
func test_assertions_file_uses_contract_scale() -> void:
	var a: Dictionary = _read_json(SCENARIO_DIR + "/assertions.json")
	var checks: Array = a.get("checks", [])
	ge_int(checks.size(), 1, "assertions.json 必须有 checks 列表（docs/11 §5.11）")
	var want: Dictionary = {
		"assert.total_population": POP_TOTAL,
		"assert.gov_debt": DEBT_UU,
		"assert.gov_cash": GOV_CASH_UU,
		"assert.annual_deficit": PLAN_DEFICIT_UU,
		"assert.living_index": JWUnits.PPM,
		"assert.unemployment": UNEMP_PPM,
		"assert.base_year_gdp": BASE_YEAR_GDP_UU,
	}
	var seen: Dictionary = {}
	for c: Variant in checks:
		var cd: Dictionary = c
		var id: String = str(cd.get("id", ""))
		seen[id] = true
		if want.has(id):
			var got: Variant = cd.get("expect", null)
			var t: int = typeof(got)
			check(t == TYPE_INT or t == TYPE_FLOAT,
					"断言 %s 的 expect 必须是一个数（docs/11 §5.11 规定该条是整数目标值）" % id)
			if t == TYPE_INT or t == TYPE_FLOAT:
				eq_int(int(got), int(want[id]),
						("断言 %s 的 expect 必须是 R-SCALE-01 之后的新刻度值"
						+ "（docs/11 §5.11 的规范集合与 docs/10 §14 已同步为该值）") % id)
		if id == "assert.region_population":
			var arr: Array = cd.get("expect", [])
			eq_int(arr.size(), JWUnits.R, "assert.region_population 的 expect 必须是四项")
			for r: int in mini(arr.size(), JWUnits.R):
				eq_int(int(arr[r]), POP_BY_REGION[r],
						"assert.region_population 第 %d 项必须等于 %d（INV-141）" % [r, POP_BY_REGION[r]])
		if id == "assert.base_prices":
			var arr2: Array = cd.get("expect", [])
			eq_int(arr2.size(), JWUnits.S, "assert.base_prices 的 expect 必须是四项")
			for s: int in mini(arr2.size(), JWUnits.S):
				eq_int(int(arr2[s]), JWUnits.BASE_PRICE,
						"assert.base_prices 第 %d 项必须等于 10⁹ μU/Q_s（INV-148 / R-SCALE-01）" % s)
	for id2: Variant in want.keys():
		check(seen.has(id2),
				"docs/11 §5.11 规定的断言 %s 缺失（该集合「不多不少」，缺一条就是少一个拒绝点）" % str(id2))


## docs/11 §5.11 + §9 裁定 D-02：tolerance 一律为 0，唯一例外是 assert.unemployment 的 500 ppm；
## 出现第二个非零容差本身即 E_ASSERT_TOLERANCE。
func test_assertions_file_tolerance_policy() -> void:
	var a: Dictionary = _read_json(SCENARIO_DIR + "/assertions.json")
	var nonzero: int = 0
	for c: Variant in a.get("checks", []):
		var cd: Dictionary = c
		var tol: int = int(cd.get("tolerance", -1))
		ge_int(tol, 0, "断言 %s 的 tolerance 不得为负" % str(cd.get("id", "?")))
		if str(cd.get("id", "")) == "assert.unemployment":
			eq_int(tol, 500,
					"assert.unemployment 的容差必须恰好是 500 ppm（docs/11 §5.11 写死在协议里的唯一例外）")
		else:
			eq_int(tol, 0,
					"断言 %s 的容差必须为 0（docs/11 §5.11：出现第二个非零容差即 E_ASSERT_TOLERANCE）"
					% str(cd.get("id", "?")))
		if tol != 0:
			nonzero += 1
	eq_int(nonzero, 1, "全协议只允许存在 1 条非零容差（docs/11 §5.11 裁定 D-02）")


## docs/11 §3 JSON 方言：内容包里不允许出现任何浮点字面量（E_FLOAT_IN_CONTENT，INV-001）；
## 整数绝对值 ≤ 2^53（E_INT_RANGE）。
##
## 这是**词法**检查，不是解析后检查：Godot 4 的 `JSON.parse_string` 把所有 JSON 数字都变成 float，
## 解析之后已经分不出 `1` 与 `1.0`——正因如此，docs/11 §3 才把它定成「字面量」级别的规则。
func test_content_files_contain_no_float_literals() -> void:
	var files: PackedStringArray = _all_content_json()
	ge_int(files.size(), 1, "content/ 下必须能枚举到 JSON 文件（docs/11 §2 的布局）")
	var floats: PackedStringArray = PackedStringArray()
	var oversized: PackedStringArray = PackedStringArray()
	for path: String in files:
		var text: String = FileAccess.get_file_as_string(path)
		check(JSON.parse_string(text) != null, "文件 %s 必须是合法 JSON（E_FILE_FORMAT）" % path)
		_collect_number_literal_violations(text, path, floats, oversized)
	eq_int(floats.size(), 0,
			"内容包中不得出现浮点字面量或指数记号（INV-001 / E_FLOAT_IN_CONTENT；命中：%s）" % str(floats))
	eq_int(oversized.size(), 0,
			"内容包中的整数绝对值必须 ≤ 2^53（E_INT_RANGE，JSON 互操作安全区；命中：%s）" % str(oversized))


# ══════════════════════════════════════════════════════════════════════════
# B 组 载入后状态层：JWContentLoader.load_all 之后，状态里的硬约束
# ══════════════════════════════════════════════════════════════════════════

## docs/17 §4.31 load_all 的后置条件：出厂内容包（docs/30 的 `FX-BASE`）必须**可载入**。
## 任何一条校验失败都拒绝启动，因此这条不通过时 B 组其余用例的失败都是它的下游后果。
func test_load_all_accepts_factory_content() -> void:
	var code: int = _ensure_base_loaded()
	eq_int(code, JWResult.OK,
			"JWContentLoader.load_all(\"%s\") 必须接受出厂剧本（docs/30 的 FX-BASE）；"
			% CONTENT_ROOT + "返回码见 JWResult.Load 枚举")
	check(_base_st != null, "载入成功后必须拿到一个已装配的 JWSimState（docs/17 §4.31 后置：就绪）")
	eq_int(JWResult.pending_code(), JWResult.OK,
			"载入期不得留下未处理的 FAULT 登记（docs/12 §9：不回滚到看起来正常的状态）")


## INV-141 + INV-142，载入之后从状态里读（不是再读一遍 JSON）。对应 docs/30 T-S-B-01 的载入后一段。
func test_loaded_population_totals_match_locked_values() -> void:
	var st: JWSimState = _base_state_or_skip("人口总量")
	if st == null:
		return
	var pop: PackedInt64Array = _array_of(st, "state.group.population_persons")
	eq_int(pop.size(), JWUnits.GROUP,
			"state.group.population_persons 必须是 36 项（INV-142，长度是 schema 的一部分）")
	var total: int = 0
	var by_region: PackedInt64Array = PackedInt64Array()
	by_region.resize(JWUnits.R)
	by_region.fill(0)
	for g: int in pop.size():
		total += pop[g]
		by_region[JWIds.region_of_group(g)] += pop[g]
	eq_int(total, POP_TOTAL, "载入后 Σ state.group.population_persons 必须精确等于 24 000 000（INV-141）")
	for r: int in JWUnits.R:
		eq_int(by_region[r], POP_BY_REGION[r],
				"载入后地区 %d 的人口必须精确等于 %d（INV-141，顺序按 docs/10 §0.5 稠密下标）"
				% [r, POP_BY_REGION[r]])


## INV-143（反算失业率）。载入后从 state.group.* 三个数组独立复算，与 docs/30 T-U-B-07 同法。
func test_loaded_unemployment_rate_is_eight_percent() -> void:
	var st: JWSimState = _base_state_or_skip("失业率")
	if st == null:
		return
	var pop: PackedInt64Array = _array_of(st, "state.group.population_persons")
	var part: PackedInt64Array = _array_of(st, "state.group.participation_ppm")
	var emp: PackedInt64Array = _array_of(st, "state.group.employed_persons")
	eq_int(part.size(), JWUnits.GROUP, "state.group.participation_ppm 必须是 36 项")
	eq_int(emp.size(), JWUnits.GROUP_EMP_N,
			"state.group.employed_persons 必须是 36×5 == 180 项（4 部门 + pubserv，docs/17 §2.1）")
	var labor: int = 0
	for g: int in mini(pop.size(), part.size()):
		labor += JWMath.mul_div_floor(pop[g], part[g], JWUnits.PPM)
	var employed: int = JWMath.sum(emp)
	ge_int(labor, 1, "劳动力必须 > 0，否则失业率无定义（Q-ADV-03：禁止 max(分母,1)）")
	le_int(employed, labor, "在岗不得超过同口径劳动力（INV-075；在岗 %d，劳动力 %d）" % [employed, labor])
	var ppm: int = JWMath.mul_div_floor(labor - employed, JWUnits.PPM, labor)
	in_range_int(ppm, UNEMP_LO_PPM, UNEMP_HI_PPM, "载入后反算失业率必须落在 INV-143 的 ppm 带内")
	eq_int(ppm, UNEMP_PPM,
			"本剧本的就业分配应当精确给出 80 000 ppm（计划书 §05 的 8%%；劳动力 %d，在岗 %d）"
			% [labor, employed])


## INV-145（gov.cash == 2 U）+ docs/10 §2.2（cash 科目是 account.balance 的视图）。
func test_loaded_gov_cash_is_two_units() -> void:
	var st: JWSimState = _base_state_or_skip("国库现金")
	if st == null:
		return
	var bal: PackedInt64Array = _array_of(st, "account.balance")
	eq_int(bal.size(), JWUnits.ACCOUNT_N,
			"account.balance 必须是 60 主体 × 15 科目 == 900 项（docs/17 §2.4）")
	if bal.size() != JWUnits.ACCOUNT_N:
		return
	eq_int(bal[JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)], GOV_CASH_UU,
			"agent.gov 的 cash 科目必须精确等于 2 U == 2 000 000 000 μU（INV-145 / V-FIN-01）")


## INV-144 + INV-035（derived.gov.debt_uu == Σ active bond.principal_outstanding_uu）。
## 对应 docs/30 T-S-D-04 的载入后一段。
func test_loaded_bond_principal_sums_to_fifty_units() -> void:
	var st: JWSimState = _base_state_or_skip("政府债务")
	if st == null:
		return
	var out: PackedInt64Array = _array_of(st, "state.bond.principal_outstanding_uu")
	ge_int(out.size(), 1,
			"state.bond.principal_outstanding_uu 必须已按 SoA 容量分配（docs/10 §3.3）")
	eq_int(JWMath.sum(out), DEBT_UU,
			"载入后 Σ bond.principal_outstanding_uu 必须精确等于 50 U == 50 000 000 000 μU（INV-144）")
	var holder: PackedInt64Array = _array_of(st, "state.bond.holder")
	var bondhold: PackedInt64Array = _array_of(st, "account.balance")
	if holder.size() == out.size() and bondhold.size() == JWUnits.ACCOUNT_N:
		var by_holder: int = bondhold[JWIds.idx_account(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD)] \
				+ bondhold[JWIds.idx_account(JWIds.AGENT_ROW, JWIds.ACC_BONDHOLD)]
		eq_int(by_holder, DEBT_UU,
				"Σ(invpool.bondhold + row.bondhold) 必须等于债务总额（INV-025：融资必须有对手方）")


## INV-148，载入后从 state.price / content.price 读（两者都必须是 10⁹）。
func test_loaded_prices_equal_base_price() -> void:
	var st: JWSimState = _base_state_or_skip("基年价格")
	if st == null:
		return
	var price: PackedInt64Array = _array_of(st, "state.price.sector_uu_per_qs")
	eq_int(price.size(), JWUnits.S, "state.price.sector_uu_per_qs 必须是 4 项（docs/10 §0.5 部门下标）")
	for s: int in price.size():
		eq_int(price[s], JWUnits.BASE_PRICE,
				"载入后部门 %d 的现行价必须等于 10⁹ μU/Q_s（INV-148；基年名义额与实际额由此恒等）" % s)
	var base: PackedInt64Array = st.pricing.base_price
	eq_int(base.size(), JWUnits.S, "content.price.base_uu_per_qs 必须是 4 项")
	for s2: int in base.size():
		eq_int(base[s2], JWUnits.BASE_PRICE,
				"content.price.base_uu_per_qs[%d] 的唯一合法值是 JWUnits.BASE_PRICE（INV-148）" % s2)


## INV-018（Σ 全经济现金 == scenario.total_cash_uu）+ INV-023 / OQ-217（agent.opening 开账后现金恒 0）。
## 对应 docs/30 T-S-A-05 的载入后一段与 docs/17 §4.31 build_opening_ledger 的后置条件。
func test_loaded_cash_total_matches_scenario_declaration() -> void:
	var st: JWSimState = _base_state_or_skip("现金总量")
	if st == null:
		return
	var bal: PackedInt64Array = _array_of(st, "account.balance")
	eq_int(bal.size(), JWUnits.ACCOUNT_N, "account.balance 必须是 900 项")
	if bal.size() != JWUnits.ACCOUNT_N:
		return
	eq_int(st.total_cash_uu, TOTAL_CASH_UU,
			"state.total_cash_uu 必须等于 scenario.json 声明的 55 U（构成：gov 2 + invpool 9 + row 15 "
			+ "+ 36 群组 9 + 16 cell 20，全部 ×10⁹ μU）")
	var total: int = 0
	for a: int in JWUnits.AGENT_N:
		var c: int = bal[JWIds.idx_account(a, JWIds.ACC_CASH)]
		ge_int(c, 0, "主体 %d 的现金科目不得为负（INV-016）" % a)
		total += c
	eq_int(total, st.total_cash_uu,
			"开账完成后 Σ 全部 56 个现金科目必须精确等于 scenario.total_cash_uu（INV-018 / E_CASH_TOTAL）")
	eq_int(bal[JWIds.idx_account(JWIds.AGENT_OPENING, JWIds.ACC_CASH)], 0,
			"agent.opening 的现金科目开账后恒为 0（OQ-217 / docs/17 §4.31 build_opening_ledger 后置）")
	for r: int in JWUnits.R:
		eq_int(bal[JWIds.idx_account(JWIds.agent_of_pubserv(r), JWIds.ACC_CASH)], 0,
				"agent.pubserv.%d 不持有现金，其支付由 agent.gov 执行（docs/10 §2.1）" % r)


## INV-149（基期人口加权的 consumption_index_ppm == 1 000 000；**不含 service_access_ppm**，R-ACCESS-01）。
func test_loaded_consumption_index_base_is_one() -> void:
	var st: JWSimState = _base_state_or_skip("民生基线指数")
	if st == null:
		return
	var pop: PackedInt64Array = _array_of(st, "state.group.population_persons")
	var idx: PackedInt64Array = _array_of(st, "state.group.consumption_index_ppm")
	eq_int(idx.size(), JWUnits.GROUP, "state.group.consumption_index_ppm 必须是 36 项")
	var num: int = 0
	var den: int = 0
	for g: int in mini(pop.size(), idx.size()):
		num += JWMath.mul(pop[g], idx[g])
		den += pop[g]
	ge_int(den, 1, "人口加权的分母必须 > 0")
	eq_int(JWMath.floor_div(num, den), JWUnits.PPM,
			"基期人口加权消费指数必须等于 1 000 000 ppm（INV-149：指数 100.00 的 ppm 写法）")
	var access: PackedInt64Array = _array_of(st, "state.group.service_access_ppm")
	eq_int(access.size(), JWUnits.GROUP_SVC_N,
			"state.group.service_access_ppm 必须是 36×3 == 108 项（docs/17 §2.1）")
	for i: int in access.size():
		in_range_int(access[i], 0, JWUnits.PPM,
				"service_access_ppm[%d] 必须落在 [0, 1 000 000]（R-ACCESS-01 保留区间、删除加权恒等式）" % i)


## INV-150（邻接矩阵对称、对角为 0）。缺这条，R-ADJ-01 里「北原—海岬不相邻」之类的裁定就无人守。
func test_loaded_region_adjacency_is_symmetric_without_self_loops() -> void:
	var st: JWSimState = _base_state_or_skip("地区邻接矩阵")
	if st == null:
		return
	var adj: PackedInt64Array = _array_of(st, "content.region.adjacency")
	eq_int(adj.size(), JWUnits.OD_N, "content.region.adjacency 必须是 4×4 == 16 项（docs/10 §7）")
	if adj.size() != JWUnits.OD_N:
		return
	for a: int in JWUnits.R:
		eq_int(adj[JWIds.idx_od(a, a)], 0, "邻接矩阵对角线必须为 0（无自环，INV-150）")
		for b: int in JWUnits.R:
			eq_int(adj[JWIds.idx_od(a, b)], adj[JWIds.idx_od(b, a)],
					"邻接矩阵必须对称：(%d,%d) 与 (%d,%d) 不一致（INV-150）" % [a, b, b, a])
			in_range_int(adj[JWIds.idx_od(a, b)], 0, 1, "邻接矩阵元素只能是 0 或 1（docs/10 §7）")


# ══════════════════════════════════════════════════════════════════════════
# C 组 拒绝启动：缺字段、ID 悬空、方言违规都必须让 load_all 失败
#   每条都是**差分**用例：先确认基线内容包能载入，再确认注入缺陷后被拒绝；
#   基线本身就被拒绝时判失败——否则「注入后也被拒绝」是空话。
# ══════════════════════════════════════════════════════════════════════════

## docs/11 §1 规则 4 与 docs/17 §4.31：「缺字段即拒绝启动」。删掉 gov.cash_uu 这一必填字段。
func test_reject_when_required_field_missing() -> void:
	var mut: Callable = func(dir: String) -> bool:
		var p: String = dir + "/scenarios/chengwan/government_init.json"
		var d: Dictionary = _read_json(p)
		var g: Dictionary = d.get("gov", {})
		g.erase("cash_uu")
		d["gov"] = g
		return _write_json(p, d)
	_assert_mutation_rejected("删除 government_init.gov.cash_uu",
			"必填字段缺失必须拒绝启动（docs/11 §1 规则 4：不自动修正、不填默认值兜底）", mut)


## docs/11 §7「跨文件引用解析（悬空引用即失败）」。把启用政策指向一个不存在的 ID。
func test_reject_when_policy_id_does_not_exist() -> void:
	var mut: Callable = func(dir: String) -> bool:
		var p: String = dir + "/scenarios/chengwan/scenario.json"
		var d: Dictionary = _read_json(p)
		var list: Array = d.get("enabled_policies", [])
		if list.is_empty():
			return false
		list[0] = "policy.P99"
		d["enabled_policies"] = list
		return _write_json(p, d)
	_assert_mutation_rejected("把 enabled_policies[0] 改成不存在的 policy.P99",
			"悬空的政策引用必须拒绝启动（docs/11 §7 跨文件引用解析，E_NOT_FOUND）", mut)


## docs/11 §7 同上，换一个命名空间：地区邻接表指向不存在的地区。
func test_reject_when_region_id_does_not_exist() -> void:
	var mut: Callable = func(dir: String) -> bool:
		var p: String = dir + "/scenarios/chengwan/regions.json"
		var d: Dictionary = _read_json(p)
		var regions: Array = d.get("regions", [])
		if regions.is_empty():
			return false
		var r0: Dictionary = regions[0]
		var adj: Array = r0.get("adjacency", [])
		adj.append("region.wulong")
		r0["adjacency"] = adj
		regions[0] = r0
		d["regions"] = regions
		return _write_json(p, d)
	_assert_mutation_rejected("在 regions[0].adjacency 里加入不存在的 region.wulong",
			"悬空的地区引用必须拒绝启动（docs/11 §7；E_REGION_SET / E_NOT_FOUND）", mut)


## docs/11 §3 方言限制 + INV-001：内容包里出现浮点字面量即 E_FLOAT_IN_CONTENT。
func test_reject_when_content_contains_float() -> void:
	var mut: Callable = func(dir: String) -> bool:
		var p: String = dir + "/scenarios/chengwan/government_init.json"
		var text: String = FileAccess.get_file_as_string(p)
		var needle: String = "\"tax_capacity_ppm\": 760000"
		if text.find(needle) < 0:
			return false
		text = text.replace(needle, "\"tax_capacity_ppm\": 760000.5")
		var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
		if f == null:
			return false
		f.store_string(text)
		f.close()
		return true
	_assert_mutation_rejected("把 gov.tax_capacity_ppm 写成 760000.5",
			"内容包里的浮点字面量必须拒绝启动（INV-001 / E_FLOAT_IN_CONTENT，Godot 的 JSON 解析会丢精度）",
			mut)


## docs/11 §4 与 §7「ID 唯一性」：重复的 group_id 即 E_DUP_ID。
## 同时也让 36 组的全组合覆盖（INV-142）出现缺口——两条都应当拒绝。
func test_reject_when_group_id_duplicated() -> void:
	var mut: Callable = func(dir: String) -> bool:
		var p: String = dir + "/scenarios/chengwan/population_init.json"
		var d: Dictionary = _read_json(p)
		var groups: Array = d.get("groups", [])
		if groups.size() < 2:
			return false
		var g1: Dictionary = groups[1]
		var g0: Dictionary = groups[0]
		g1["group_id"] = g0.get("group_id", "")
		groups[1] = g1
		d["groups"] = groups
		return _write_json(p, d)
	_assert_mutation_rejected("把 groups[1].group_id 改成与 groups[0] 相同",
			"重复 ID 必须拒绝启动（docs/11 §7 ID 唯一性，E_DUP_ID；同时破坏 INV-142 的全组合覆盖）", mut)


## docs/11 §5.4：`unit_declaration.money_micro_per_unit != JWUnits.U_SCALE` 即 E_UNIT_MISMATCH。
## 这条专门钉「刻度声明与引擎常量脱钩」——R-SCALE-01 之后它是最容易被漏改的一处。
func test_reject_when_unit_declaration_mismatches_engine() -> void:
	var mut: Callable = func(dir: String) -> bool:
		var p: String = dir + "/scenarios/chengwan/scenario.json"
		var d: Dictionary = _read_json(p)
		var ud: Dictionary = d.get("unit_declaration", {})
		ud["money_micro_per_unit"] = 1_000_000  # 旧刻度，R-SCALE-01 之前的值
		d["unit_declaration"] = ud
		return _write_json(p, d)
	_assert_mutation_rejected("把 money_micro_per_unit 改成旧刻度 10⁶",
			"刻度声明与 JWUnits.U_SCALE 不一致必须拒绝启动（docs/11 §5.4，E_UNIT_MISMATCH）", mut)


## 剧本硬约束的会计对账（docs/11 §7 最后一段）：把一个群组的人口改掉，总人口就不再是 2400 万。
## 这条证明 INV-141 是**加载期的拒绝点**，不是只写在文档里的口号。
func test_reject_when_population_total_broken() -> void:
	var mut: Callable = func(dir: String) -> bool:
		var p: String = dir + "/scenarios/chengwan/population_init.json"
		var d: Dictionary = _read_json(p)
		var groups: Array = d.get("groups", [])
		if groups.is_empty():
			return false
		var g0: Dictionary = groups[0]
		g0["population_persons"] = int(g0.get("population_persons", 0)) + 1
		groups[0] = g0
		d["groups"] = groups
		return _write_json(p, d)
	_assert_mutation_rejected("给 groups[0].population_persons 加 1 人",
			"总人口偏离 24 000 000 必须拒绝启动（INV-141 / V-POP-02，E_POP_TOTAL；容差 0）", mut)


## 同上，财政侧：把一个债券批次的未偿本金改掉，Σ 就不再是 50 U。
func test_reject_when_debt_total_broken() -> void:
	var mut: Callable = func(dir: String) -> bool:
		var p: String = dir + "/scenarios/chengwan/government_init.json"
		var d: Dictionary = _read_json(p)
		var bonds: Array = d.get("bonds", [])
		if bonds.is_empty():
			return false
		var b0: Dictionary = bonds[0]
		b0["principal_outstanding_uu"] = int(b0.get("principal_outstanding_uu", 0)) - 1_000_000
		bonds[0] = b0
		d["bonds"] = bonds
		return _write_json(p, d)
	_assert_mutation_rejected("把 bonds[0].principal_outstanding_uu 减少 0.001 U",
			"Σ 未偿本金偏离 50 U 必须拒绝启动（INV-144 / V-FIN-02，E_DEBT_TOTAL；容差 0）", mut)


# ══════════════════════════════════════════════════════════════════════════
# D 组 基年四季：GDP 三口径
# ══════════════════════════════════════════════════════════════════════════

## INV-115（expenditure == production + price_variance，残差恰为 0）+ INV-116（income == production），逐季、容差 0。
## INV-118 按裁定 R-INV118-01 分两层：内容层的基年核算三口径恰为 100 U（载入期 V-GDP，容差 0，
## 见本文件的内容校验用例）；运行期首年只是**校准指标**——无命令基线首年 Σ GDP 落在 [90, 110] U 即可。
## 计划书 §14：「先无冲击运行，检查基线是否因计算错误自行崩溃，而不是强迫所有变量恒定」；
## 首年价格随供需调整、价差调节项非零是机制的正常结果，由 INV-115 的恒等式逐季对账。
## 对应 docs/30 的 T-S-A-24 与 T-U-A-23，断言值按 R-SCALE-01 换算为新刻度。
func test_base_year_gdp_matches_across_three_measures() -> void:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: Object = _instantiate(LOADER_PATH, "JWContentLoader")
	if loader == null:
		return
	var res: JWResult = loader.call("load_all", CONTENT_ROOT, st)
	if res == null or not res.ok:
		check(false, ("基年 GDP 用例无法起跑：load_all 拒绝了出厂内容包（code=%d）；"
				+ "先修好 test_load_all_accepts_factory_content 指出的问题，本条才有意义（INV-118）")
				% (0 if res == null else res.code))
		return

	var cmds: Object = _instantiate(COMMANDS_PATH, "JWCommands")
	var events: Object = _instantiate(EVENTS_PATH, "JWEventEngine")
	if cmds == null or events == null:
		return
	# 与 JWGame.new_game / 其它回合测试同一套装配：命令流与事件引擎在推进前必须 allocate()。
	cmds.call("allocate")
	events.call("allocate")
	var runner_script: Script = load(RUNNER_PATH) as Script
	if runner_script == null or not runner_script.can_instantiate():
		check(false, "JWTurnRunner（%s）当前无法实例化，基年四季无法推进" % RUNNER_PATH)
		return
	var runner: Object = runner_script.new(st, events)
	var sum_prod: int = 0
	var sum_exp: int = 0
	var sum_inc: int = 0
	for t: int in 4:
		# 99 == JWCommands.Kind.ADVANCE_QUARTER（docs/11 §6.1「值不得改」）。
		# 这里写字面量而不是引用常量：JWCommands 尚未通过解析时，引用它会让**本测试文件**也编译不过。
		var adv_args: PackedInt64Array = PackedInt64Array()
		adv_args.resize(int(cmds.get("ARG_SLOTS")))
		cmds.call("submit", 99, adv_args, st.q, st.policy_defs)
		var code: int = runner.call("advance_quarter", cmds)
		eq_int(code, JWResult.OK,
				"基年第 %d 季必须在无命令的情况下推进成功（docs/30 的 FX-BASE：无命令跑满四季）" % t)
		if code != JWResult.OK:
			return
		var prod: int = st.diag.gdp_production
		var expd: int = st.diag.gdp_expenditure
		var inc: int = st.diag.gdp_income
		var pv: int = st.diag.price_variance_total
		eq_int(expd - prod - pv, 0,
				"第 %d 季支出法 − 生产法 − 价差调节项必须恰为 0（INV-115，残差不得非零）" % t)
		eq_int(inc, prod, "第 %d 季收入法必须等于生产法（INV-116）" % t)
		sum_prod += prod
		sum_exp += expd
		sum_inc += inc

	# R-INV118-01：运行期首年是校准带，不是恒等式。
	in_range_int(sum_prod, BASE_YEAR_GDP_UU * 9 / 10, BASE_YEAR_GDP_UU * 11 / 10,
			"无命令基线首年生产法 GDP 合计须落在基年 100 U 的 ±10% 内（R-INV118-01 校准带）")
	eq_int(sum_inc, sum_prod, "首年收入法合计必须恰等于生产法合计（INV-116，逐季恒等的加总）")
	eq_int(st.diag.gdp_annual_nominal, sum_prod,
			"q=3 末的滚动四季名义 GDP 必须恰等于首年四季生产法之和（derived.gdp.annual_nominal_uu 的定义）")


# ══════════════════════════════════════════════════════════════════════════
# 夹具与工具（不含任何断言）
# ══════════════════════════════════════════════════════════════════════════

## 「模块尚未通过解析」的哨兵码（不在 JWResult.Load 枚举里，因此不会与真实拒绝码混淆）。
const E_MODULE_UNAVAILABLE: int = -9001
## 「被拒绝却没登记错误码」的哨兵码。
const E_RESULT_WITHOUT_CODE: int = -9002


## 载入一次出厂内容包，返回 load_all 的错误码（0 == OK）。
func _ensure_base_loaded() -> int:
	if _base_loaded:
		return _base_code
	_base_loaded = true
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: Object = _instantiate(LOADER_PATH, "JWContentLoader")
	if loader == null:
		_base_code = E_MODULE_UNAVAILABLE
		return _base_code
	var res: JWResult = loader.call("load_all", CONTENT_ROOT, st)
	if res == null:
		_base_code = JWResult.Load.FILE_FORMAT
		return _base_code
	if res.ok and res.code == JWResult.OK:
		_base_st = st
		_base_code = JWResult.OK
	elif res.code != JWResult.OK:
		_base_code = res.code
	else:
		# ok == false 却没带错误码：docs/17 §4.31 要求「返回第一条错误的 JWResult」，
		# 拒绝而不登记码本身就是缺陷（否则调用方无从知道被拒的理由）。
		_base_code = E_RESULT_WITHOUT_CODE
	return _base_code


## 安全实例化：脚本尚未通过解析（实现进行中）时记一条**可读**的失败并返回 null，
## 而不是让整个测试方法在 `X.new()` 处静默中断——那样运行器只会报「0 断言」，看不出根因。
func _instantiate(script_path: String, label: String) -> Object:
	var scr: Script = load(script_path) as Script
	if scr == null:
		check(false, "无法加载 %s（%s）：文件不存在或不是脚本" % [label, script_path])
		return null
	if not scr.can_instantiate():
		check(false, ("%s（%s）当前无法实例化：该脚本未通过解析"
				+ "（实现中的语法错误或缺失函数），本用例因此无法执行") % [label, script_path])
		return null
	return scr.new()


## 取基线状态；载入失败时记一条失败并返回 null（不让下游断言把同一个缺陷重复报成十条）。
func _base_state_or_skip(what: String) -> JWSimState:
	var code: int = _ensure_base_loaded()
	if _base_st == null:
		check(false, "%s 用例无法起跑：出厂内容包未能载入（load_all code=%d）。"
				% [what, code] + "根因见 test_load_all_accepts_factory_content")
		return null
	return _base_st


## 按 docs/17 §1.6 的状态块协议，用稳定 ID 取一个整数数组。
## 找不到就返回空数组——调用方用长度断言把「ID 未注册」报成可读的失败。
func _array_of(st: JWSimState, id: String) -> PackedInt64Array:
	for b: Variant in _blocks_of(st):
		if b == null or not (b as Object).has_method("state_array"):
			continue
		var gds: GDScript = (b as Object).get_script() as GDScript
		if gds == null:
			continue
		var cmap: Dictionary = gds.get_script_constant_map()
		if not cmap.has("STATE_ARRAY_IDS"):
			continue
		var ids: PackedStringArray = cmap["STATE_ARRAY_IDS"]
		var i: int = ids.find(id)
		if i >= 0:
			return b.state_array(i)
		if cmap.has("CONTENT_ARRAY_IDS"):
			var cids: PackedStringArray = cmap["CONTENT_ARRAY_IDS"]
			var j: int = cids.find(id)
			if j >= 0:
				return b.state_array(ids.size() + j)
	return PackedInt64Array()


## JWSimState 持有的全部状态块（docs/17 §4.27 的成员表，顺序无关紧要）。
func _blocks_of(st: JWSimState) -> Array:
	return [st.rng, st.accounts, st.ledger, st.io, st.policy_defs, st.pricing, st.bonds,
			st.capital, st.pop, st.world, st.treasury, st.labor, st.shocks, st.inventory,
			st.projects, st.migration, st.politics, st.sectors, st.commissioning,
			st.policy, st.blocs, st.diag]


## 差分拒绝用例的公共骨架：复制一份内容包 → 注入缺陷 → 断言被拒。
func _assert_mutation_rejected(what: String, why: String, mutate: Callable) -> void:
	var base_code: int = _ensure_base_loaded()
	if base_code != JWResult.OK:
		check(false, "差分用例「%s」无法起跑：基线内容包本身就被拒绝（code=%d），"
				% [what, base_code]
				+ "此时「注入缺陷后也被拒绝」证明不了任何事。先修基线。")
		return

	var dir: String = _make_tmp_content_copy()
	if dir == "":
		check(false, "无法复制内容包到临时目录，用例「%s」未能执行" % what)
		return
	var ok: bool = mutate.call(dir)
	if not ok:
		check(false, "注入缺陷失败（%s）：目标字段不在预期位置，用例未能执行" % what)
		_remove_tree(dir)
		return

	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: Object = _instantiate(LOADER_PATH, "JWContentLoader")
	if loader == null:
		_remove_tree(dir)
		return
	var res: JWResult = loader.call("load_all", dir, st)
	var code: int = JWResult.OK if res == null else res.code
	rejects(code, JWResult.OK, "%s —— %s" % [what, why])
	check(res == null or not res.ok,
			"%s：被拒绝的载入结果 ok 必须为 false（docs/17 §4.31：任何一条失败都拒绝启动）" % what)
	_remove_tree(dir)


## 把 res://content 整棵树（只取 *.json）复制到 user:// 下的一个新目录，返回目录路径；失败返回 ""。
func _make_tmp_content_copy() -> String:
	_tmp_seq += 1
	var dst: String = "user://jw_content_load_test_%d" % _tmp_seq
	_remove_tree(dst)
	if not _copy_tree(CONTENT_ROOT, dst):
		return ""
	return dst


func _copy_tree(src: String, dst: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(dst) != OK:
		return false
	var d: DirAccess = DirAccess.open(src)
	if d == null:
		return false
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = d.get_next()
			continue
		var s: String = "%s/%s" % [src, entry]
		var t: String = "%s/%s" % [dst, entry]
		if d.current_is_dir():
			if not _copy_tree(s, t):
				d.list_dir_end()
				return false
		elif entry.ends_with(".json"):
			var bytes: PackedByteArray = FileAccess.get_file_as_bytes(s)
			var f: FileAccess = FileAccess.open(t, FileAccess.WRITE)
			if f == null:
				d.list_dir_end()
				return false
			f.store_buffer(bytes)
			f.close()
		entry = d.get_next()
	d.list_dir_end()
	return true


func _remove_tree(path: String) -> void:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var p: String = "%s/%s" % [path, entry]
			if d.current_is_dir():
				_remove_tree(p)
			else:
				DirAccess.remove_absolute(p)
		entry = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


## 读一个 JSON 文件为字典；读不到或不是对象时返回空字典（调用方的 has_key/eq_int 会把它报成失败）。
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


## 写回一个 JSON 文件（只用于临时内容包的缺陷注入；LF 结尾，符合 docs/11 §3 的文件格式要求）。
func _write_json(path: String, data: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t") + "\n")
	f.close()
	return true


## 枚举 content/ 下全部 *.json（含子目录）。
func _all_content_json() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	_walk_json(CONTENT_ROOT, out)
	out.sort()
	return out


func _walk_json(dir_path: String, out: PackedStringArray) -> void:
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var p: String = "%s/%s" % [dir_path, entry]
			if d.current_is_dir():
				_walk_json(p, out)
			elif entry.ends_with(".json"):
				out.append(p)
		entry = d.get_next()
	d.list_dir_end()


## 递归收集所有键名里含有 needle 的路径（用于「schema 中不存在某字段」类静态检查）。
## 跳过 `_note_*` 注释键的整棵子树：docs/11 §1 规则 5 与 §5.15 规定它们只供 Presentation 读、
## 加载器不读，因此在注释里写「本组失业 N 人」是**登记推导来源**，不是给 schema 加输入字段。
func _collect_keys_containing(node: Variant, path: String, needle: String,
		out: PackedStringArray) -> void:
	if typeof(node) == TYPE_DICTIONARY:
		var d: Dictionary = node
		for k: Variant in d.keys():
			var key: String = str(k)
			if key.begins_with("_note"):
				continue
			var p: String = "%s/%s" % [path, key]
			if key.findn(needle) >= 0:
				out.append(p)
			_collect_keys_containing(d[k], p, needle, out)
	elif typeof(node) == TYPE_ARRAY:
		var a: Array = node
		for i: int in a.size():
			_collect_keys_containing(a[i], "%s[%d]" % [path, i], needle, out)


## 词法扫描 JSON 数字字面量：只看**取值位置**上的数（紧跟 `:`、`,` 或 `[`），
## 因此中文说明串里的「1.5 倍」不会被误判——它前面隔着一个引号。
func _collect_number_literal_violations(text: String, path: String, floats: PackedStringArray,
		oversized: PackedStringArray) -> void:
	# 先把全部字符串字面量挖空：中文说明里写「上限 1e6」「约 1.5 倍」是文案，不是内容数值，
	# docs/11 §1 规则 5 已经把 `label_zh` / `_note_*` 划成只供 Presentation 读的文案。
	var strip: RegEx = RegEx.new()
	strip.compile("\"(?:[^\"\\\\]|\\\\.)*\"")
	var bare: String = strip.sub(text, "\"\"", true)

	var re: RegEx = RegEx.new()
	# 取值位置的数字：小数点、指数记号、负零都属于 docs/11 §3 禁止的写法。
	re.compile("[:,\\[]\\s*(-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)")
	for m: RegExMatch in re.search_all(bare):
		var lit: String = m.get_string(1)
		if lit.contains(".") or lit.containsn("e"):
			floats.append("%s → %s" % [path, lit])
			continue
		if lit == "-0":
			floats.append("%s → -0（docs/11 §3 禁止负零）" % path)
			continue
		var digits: String = lit.trim_prefix("-")
		if digits.length() > 16:
			oversized.append("%s → %s" % [path, lit])
		elif digits.length() == 16 and digits.to_int() > JWSimState.JSON_SAFE_INT_MAX:
			oversized.append("%s → %s" % [path, lit])


## group_id 的第二段 → 地区稠密下标（docs/10 §0.5）；不认识就返回 −1。
func _region_index_of_group_id(group_id: String) -> int:
	var parts: PackedStringArray = group_id.split(".")
	if parts.size() < 2:
		return -1
	var names: PackedStringArray = PackedStringArray(["beiyuan", "zhongzhou", "haijia", "xiling"])
	return names.find(parts[1])


