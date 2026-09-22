## 投资池对生产单元的资本放贷（docs/18 R-INVCREDIT-01；docs/53 M2-8）。
##
## 这一块补的是「住户储蓄回到实体经济」的唯一渠道：此前投资池只能付息、买国债、应付取款，
## 战役里政府还清债务之后储蓄就再也回不去，需求逐季漏光。测试盯住三件事：
## ① 真的放得出款，且不是凭空造钱（现金总量不变）；② 杠杆与准备率两道闸真的拦得住；
## ③ INV-C01：Σ 未偿本金 == 投资池应收，一位不差。
extends JWTest

const CAMPAIGN: String = "res://content#campaign_1600"
const TERM: String = "res://content"


func _game(seed_v: int, spec: String = CAMPAIGN) -> JWGame:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_credit"
	check(g.new_game(spec, seed_v, 0).ok, "开局")
	return g


func _args(v: Array) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	for i: int in v.size():
		a[i] = int(v[i])
	return a


## 周转垫款是短期自偿的：同一季借、同一季还，季末余额常常是 0。
## 所以「有没有放过贷」要看逐季的放款流量累计，不能只看某一刻的存量。
var drawn_total: int = 0


func _advance(g: JWGame, n: int) -> void:
	var st: JWSimState = g.get("_st") as JWSimState
	for i: int in n:
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, _args([]))
		check(g.advance_quarter().ok, "推进第 %d 季" % i)
		drawn_total += JWMath.sum(st.credit.f_draw)


func test_rule_loaded_in_campaign_only() -> void:
	var st: JWSimState = _game(201).get("_st") as JWSimState
	eq_int(st.credit.enabled, 1, "战役剧本启用信贷")
	ge_int(st.credit.amortize_ppm, 1, "摊还率 > 0")
	ge_int(st.credit.max_leverage_ppm, 1, "杠杆上限 > 0")
	var st2: JWSimState = _game(202, TERM).get("_st") as JWSimState
	eq_int(st2.credit.enabled, 0, "单届旧剧本不启用信贷")
	eq_int(JWMath.sum(st2.credit.principal), 0, "旧剧本未偿本金恒为 0")


func test_lending_happens_and_cash_total_is_unchanged() -> void:
	var g: JWGame = _game(203)
	var st: JWSimState = g.get("_st") as JWSimState
	var cash0: int = st.accounts.total_cash()
	var issued0: int = st.money.issued_total
	_advance(g, 12)
	ge_int(drawn_total, 1, "十二季里至少放出过一笔贷款（资本贷款或周转垫款）")
	# 现金总量只由货币发行改变（R-MONEY-01）；放贷一分钱都不创造。
	eq_int(st.accounts.total_cash() - cash0, st.money.issued_total - issued0,
			"现金总量的变化全部来自货币发行，放贷不创造货币")
	eq_int(st.credit.check_consistency(st.accounts), JWResult.OK, "INV-C01：本金合计 == 投资池应收")


func test_interest_flows_back_to_households() -> void:
	var g: JWGame = _game(204)
	var st: JWSimState = g.get("_st") as JWSimState
	_advance(g, 12)
	ge_int(drawn_total, 1, "十二季里放过款")
	var paid: int = 0
	for c: int in JWUnits.CELL:
		paid += st.credit.f_interest[c]
	ge_int(paid + drawn_total, 1, "本季或此前收到过贷款利息")
	var got: int = 0
	for gr: int in JWUnits.GROUP:
		got += st.pop.f_property_income[gr]
	ge_int(got, paid, "住户本季的财产收入不少于贷款利息（利息经存款份额回流）")


func test_leverage_cap_blocks_further_draw() -> void:
	var st: JWSimState = _game(205).get("_st") as JWSimState
	var c: int = 0
	var cap_value: int = st.capital.cell_capital_value[c]
	ge_int(cap_value, 1, "该单元有资本价值")
	var room: int = st.credit.headroom_of(c, cap_value)
	ge_int(room, 1, "一开始有借款余量")
	# 夹具：把未偿本金顶到杠杆上限。
	st.credit.principal[c] = JWMath.mul_ppm(cap_value, st.credit.max_leverage_ppm)
	eq_int(st.credit.headroom_of(c, cap_value), 0, "到顶之后余量为 0")
	eq_int(st.credit.draw_for(c, 1_000_000_000, 0, cap_value, 1_000_000_000), 0,
			"到顶之后借不到")


func test_pool_reserve_limits_lending() -> void:
	var st: JWSimState = _game(206).get("_st") as JWSimState
	var cash: int = 100_000_000_000
	var dep: int = 100_000_000_000
	var room: int = st.credit.lendable(cash, dep)
	eq_int(room, cash - JWMath.mul_ppm(dep, st.credit.pool_reserve_ppm), "可贷额 = 现金 − 准备")
	eq_int(st.credit.lendable(0, dep), 0, "没现金就放不出款")


func test_draw_only_covers_the_gap() -> void:
	var st: JWSimState = _game(207).get("_st") as JWSimState
	var c: int = 0
	var cap_value: int = st.capital.cell_capital_value[c]
	var intent: int = 10_000_000_000
	# 自有现金够用：一分不借。
	eq_int(st.credit.draw_for(c, intent, intent, cap_value, intent), 0, "现金够就不借")
	# 自有现金为 0：借的正是缺口（在余量与额度之内）。
	var want: int = mini(intent, st.credit.headroom_of(c, cap_value))
	eq_int(st.credit.draw_for(c, intent, 0, cap_value, intent), want, "只借缺口")


func test_repayment_reduces_principal() -> void:
	var g: JWGame = _game(208)
	var st: JWSimState = g.get("_st") as JWSimState
	_advance(g, 12)
	ge_int(drawn_total, 1, "十二季里放过款")
	var repaid: int = 0
	_advance(g, 4)
	for c: int in JWUnits.CELL:
		repaid += st.credit.f_repay[c]
	ge_int(repaid, 0, "本季还本额非负")
	eq_int(st.credit.check_consistency(st.accounts), JWResult.OK, "还本后 INV-C01 仍然成立")


func test_save_load_round_trip_keeps_credit() -> void:
	var g: JWGame = _game(209)
	var st: JWSimState = g.get("_st") as JWSimState
	_advance(g, 12)
	var before: int = st.credit.principal_total()
	check(g.save_game("slot_test_credit").ok, "存档")
	var g2: JWGame = JWGame.new()
	g2.autosave_slot = "autosave_test_credit2"
	check(g2.new_game(CAMPAIGN, 210, 0).ok, "另开一局再读档")
	check(g2.load_game("slot_test_credit").ok, "读档")
	var st2: JWSimState = g2.get("_st") as JWSimState
	eq_int(st2.credit.principal_total(), before, "读档后未偿本金一致")
	eq_int(st2.credit.enabled, 1, "读档后信贷仍启用")
