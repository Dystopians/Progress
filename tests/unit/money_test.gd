## 长期货币与价格水平（docs/18 R-MONEY-01、R-PRICE-LONG-01；docs/53 M1-3）。
extends JWTest

const CAMPAIGN: String = "res://content#campaign_1600"


func _state(spec: String) -> JWSimState:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var ld: JWContentLoader = JWContentLoader.new()
	var r: JWResult = ld.load_all(spec, st)
	check(r != null and r.ok, "载入 " + spec)
	return st


func test_issue_rule_arithmetic() -> void:
	var m: JWMoney = JWMoney.new()
	m.allocate()
	m.enabled = 1
	m.base_money_uu = 1_000_000
	m.base_real_gdp_q_uu = 100
	m.adjust_ppm = 500_000
	m.issue_cap_ppm = 100_000
	eq_int(m.compute_issue(1_000_000), 0, "四季窗口未填满 ⇒ 不发行")
	for q: int in 4:
		m.record_real_gdp(q, 150)
	# M* = 1e6 × 150/100 × 1.0 = 1.5e6；缺口 5e5；×50% = 2.5e5；上限 = 1e6 × 10% = 1e5。
	eq_int(m.compute_issue(1_000_000), 100_000, "发行额受每季上限约束")
	m.issue_cap_ppm = 1_000_000
	eq_int(m.compute_issue(1_000_000), 250_000, "未触上限时发行缺口的 adjust 比例")
	eq_int(m.compute_issue(2_000_000), 0, "货币量已超过目标 ⇒ 不回收、不发行")
	m.enabled = 0
	eq_int(m.compute_issue(1_000_000), 0, "关闭时恒为 0")


func test_target_level_compounds() -> void:
	var m: JWMoney = JWMoney.new()
	m.allocate()
	m.enabled = 1
	m.target_inflation_ppm_per_year = 40_000
	for i: int in 4:
		m.compute_issue(0)
	# 每季 1%，四季复利 ≈ 1.040604。
	in_range_int(m.target_level_ppm, 1_040_500, 1_040_700, "目标水平按季复利（年 4%）")


func test_price_level_index() -> void:
	var st: JWSimState = _state(CAMPAIGN)
	var base: PackedInt64Array = st.pricing.base_price
	var p: PackedInt64Array = base.duplicate()
	eq_int(st.money.update_price_level(p, base), JWResult.OK, "计算成功")
	eq_int(st.money.price_level_ppm, JWUnits.PPM, "现价 == 基年价 ⇒ 指数恰为 1e6")
	for s: int in JWUnits.S:
		p[s] = base[s] * 2
	st.money.update_price_level(p, base)
	eq_int(st.money.price_level_ppm, 2 * JWUnits.PPM, "全部翻倍 ⇒ 指数 2e6")


func test_relative_band_moves_with_level() -> void:
	var st: JWSimState = _state(CAMPAIGN)
	var pr: JWPricing = st.pricing
	var n: int = JWUnits.S
	var sup: PackedInt64Array = PackedInt64Array()
	var dem: PackedInt64Array = PackedInt64Array()
	var inv: PackedInt64Array = PackedInt64Array()
	var tgt: PackedInt64Array = PackedInt64Array()
	var sto: PackedInt64Array = PackedInt64Array()
	for s: int in n:
		sup.append(1_000_000)
		dem.append(1_000_000)
		inv.append(0)
		tgt.append(0)
		sto.append(0)
	# 价格水平 10 倍：相对带宽下限 = 基年价 × 10 × 1/4 = 2.5 倍，高于现价（基年价）⇒ 被托到 2.5 倍。
	pr.set_long_run_bounds(true, 10 * JWUnits.PPM, 250_000, 4_000_000, 50_000, 50_000_000, 5 * JWUnits.PPM)
	eq_int(pr.update_prices(sup, dem, inv, tgt, sto, st.params), JWResult.OK, "定价成功")
	for s2: int in n:
		eq_int(pr.price_pending[s2], JWMath.mul_ppm(pr.base_price[s2], 2_500_000),
				"部门 %d 被相对带宽下限托住" % s2)
	# 水平 300 倍：带宽下限 75 倍越过绝对上限 50 倍 ⇒ 钉在绝对上限。
	pr.set_long_run_bounds(true, 300 * JWUnits.PPM, 250_000, 4_000_000, 50_000, 50_000_000, JWUnits.PPM)
	pr.update_prices(sup, dem, inv, tgt, sto, st.params)
	eq_int(pr.price_pending[0], JWMath.mul_ppm(pr.base_price[0], 50_000_000), "钉在绝对护栏")
	# 关闭：回到旧的绝对上下限（0.4—2.5 倍），现价 == 基年价、零缺口 ⇒ 不变。
	pr.set_long_run_bounds(false, JWUnits.PPM, 0, 0, 0, 0, JWUnits.PPM)
	pr.update_prices(sup, dem, inv, tgt, sto, st.params)
	eq_int(pr.price_pending[0], pr.price[0], "关闭时零缺口不变价")


func test_issuing_keeps_cash_closure() -> void:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_money"
	check(g.new_game(CAMPAIGN, 11, 0).ok, "战役开局")
	var st: JWSimState = g.get("_st") as JWSimState
	# 夹具：目标通胀 40% / 年、每季补足缺口、上限 5%，迫使规则一定发行。
	st.money.target_inflation_ppm_per_year = 400_000
	st.money.adjust_ppm = JWUnits.PPM
	st.money.issue_cap_ppm = 50_000
	var cash0: int = st.accounts.total_cash()
	for i: int in 8:
		var a: PackedInt64Array = PackedInt64Array()
		a.resize(JWCommands.ARG_SLOTS)
		a.fill(0)
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a)
		var r: JWResult = g.advance_quarter()
		check(r == null or r.ok, "推进第 %d 季（季末现金闭合检查通过）" % i)
	check(st.money.issued_total > 0, "规则确有发行（累计 %d μU）" % st.money.issued_total)
	eq_int(st.accounts.total_cash(), cash0 + st.money.issued_total, "现金总量 == 开局 + 累计发行")
	eq_int(st.check_all_p0(), JWResult.OK, "P0 不变量（含 INV-018 期望值）通过")


func test_term_mode_never_issues() -> void:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_money2"
	check(g.new_game("res://content", 11, 0).ok, "旧剧本开局")
	var st: JWSimState = g.get("_st") as JWSimState
	eq_int(st.money.enabled, 0, "旧剧本不启用货币发行")
	for i: int in 4:
		var a: PackedInt64Array = PackedInt64Array()
		a.resize(JWCommands.ARG_SLOTS)
		a.fill(0)
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a)
		g.advance_quarter()
	eq_int(st.money.issued_total, 0, "旧剧本累计发行恒为 0")
	eq_int(st.accounts.total_cash(), st.total_cash_uu, "旧剧本现金总量恒等于剧本登记值")
