## 贸易伙伴分账（docs/18 R-TRADE-01；docs/53 M2-4）。
extends JWTest

const CAMPAIGN: String = "res://content#campaign_1600"


func _game(spec: String, seed_v: int) -> JWGame:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_trade"
	check(g.new_game(spec, seed_v, 0).ok, "开局 " + spec)
	return g


func _args(v: Array) -> PackedInt64Array:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	for i: int in v.size():
		a[i] = int(v[i])
	return a


func _advance(g: JWGame) -> JWResult:
	g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, _args([]))
	return g.advance_quarter()


func test_partners_loaded() -> void:
	var st: JWSimState = _game(CAMPAIGN, 61).get("_st") as JWSimState
	var p: JWPartners = st.partners
	eq_int(p.partner_count, 3, "载入 3 个伙伴")
	eq_int(p.export_multiplier_ppm(), JWUnits.PPM, "出口份额合计 == 1e6（与无伙伴时同一通道）")
	in_range_int(p.import_price_multiplier_ppm(), 900_000, 1_100_000, "进口价格倍率在基准附近")


func test_subledger_balances_trade_net() -> void:
	var g: JWGame = _game(CAMPAIGN, 62)
	var st: JWSimState = g.get("_st") as JWSimState
	var p: JWPartners = st.partners
	var acc: int = 0
	for i: int in 4:
		check(_advance(g).ok, "推进第 %d 季" % i)
		acc += st.world.f_exports_uu - st.world.f_imports_uu
	eq_int(p.balance_total(), acc, "INV-P01：Σ 子账余额 == 累计（出口 − 进口）")
	check(p.balance_uu[0] != 0 or p.balance_uu[1] != 0 or p.balance_uu[2] != 0, "确有分账发生")


func test_arrangement_changes_channel_and_relation() -> void:
	var g: JWGame = _game(CAMPAIGN, 63)
	var st: JWSimState = g.get("_st") as JWSimState
	var p: JWPartners = st.partners
	var e0: int = p.export_share_ppm[0]
	var r0: int = p.relation_ppm[0]
	g.submit_command(JWCommands.Kind.TRADE_ARRANGE, _args([0, 0, 1]))
	check(_advance(g).ok, "推进一季")
	eq_int(p.export_share_ppm[0], e0 + p.quota_step_ppm, "出口额度加一档")
	check(p.relation_ppm[0] > r0, "关系上升")
	# 倍率在下一季 S01 重算（命令在 S02 生效，S01 已经过去）。
	check(_advance(g).ok, "再推一季")
	check(st.world.partner_export_mult_ppm > JWUnits.PPM, "出口通道倍率随之提高")
	# 协定：同一伙伴只能缔结一次。
	g.submit_command(JWCommands.Kind.TRADE_ARRANGE, _args([0, 2, 1]))
	check(_advance(g).ok, "推进一季")
	check(((p.treaty_mask[0] >> JWPartners.TREATY_TRADE) & 1) == 1, "贸易协定已缔结")
	eq_int(p.arrange(0, 2, 1), JWResult.Reject.ALREADY_ENACTED, "重复缔约被拒")
	eq_int(p.arrange(9, 0, 1), JWResult.Reject.NOT_FOUND, "不存在的伙伴被拒")


func test_treaty_lowers_import_price() -> void:
	var g: JWGame = _game(CAMPAIGN, 64)
	var st: JWSimState = g.get("_st") as JWSimState
	var p: JWPartners = st.partners
	var before: int = p.import_price_multiplier_ppm()
	eq_int(p.arrange(1, 2, 1), JWResult.OK, "与第二个伙伴缔约")
	check(p.import_price_multiplier_ppm() < before, "缔约后进口价格倍率下降（%d → %d）"
			% [before, p.import_price_multiplier_ppm()])


func test_term_mode_has_no_partners() -> void:
	var g: JWGame = _game("res://content", 65)
	var st: JWSimState = g.get("_st") as JWSimState
	eq_int(st.partners.partner_count, 0, "旧剧本没有贸易伙伴")
	eq_int(st.partners.export_multiplier_ppm(), JWUnits.PPM, "出口通道不变")
	eq_int(st.partners.arrange(0, 0, 1), JWResult.Reject.PRECONDITION, "旧剧本贸易安排被拒")
	check(_advance(g).ok, "推进一季")
	eq_int(st.partners.balance_total(), 0, "没有子账")
