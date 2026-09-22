## 所有者与三条产业路线（docs/18 R-OWNER-01；docs/53 M2-3）。
extends JWTest

const CAMPAIGN: String = "res://content#campaign_1600"


func _game(seed_v: int) -> JWGame:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_owner"
	check(g.new_game(CAMPAIGN, seed_v, 0).ok, "战役开局")
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


func _complete(st: JWSimState, t: int) -> void:
	st.research.completed_mask = st.research.completed_mask | (1 << t)
	st.research.advance_research(0)


func _build_until_stack(g: JWGame, owner_i: int, region: int) -> int:
	var st: JWSimState = g.get("_st") as JWSimState
	var b: JWBuildings = st.buildings
	_complete(st, 4)
	var n0: int = b.count
	g.submit_command(JWCommands.Kind.BUILD_BUILDING, _args([3, region, owner_i, 0]))
	for i: int in 14:
		check(_advance(g).ok, "推进第 %d 季" % i)
		if b.count > n0:
			return b.count - 1
	return -1


func test_gov_share_of_surplus_goes_to_government() -> void:
	var g: JWGame = _game(51)
	var st: JWSimState = g.get("_st") as JWSimState
	var nb: int = _build_until_stack(g, JWBuildings.OWNER_GOV, 1)
	check(nb >= 0, "国有工场建成")
	var cell: int = st.buildings.cell[nb]
	# 再推两季：产能转在用，盈余开始按份额划分。
	for i: int in 2:
		check(_advance(g).ok, "推进")
	var share: int = st.buildings.gov_share_ppm(cell)
	ge_int(share, 1, "该单元有国有份额（%d ppm）" % share)
	le_int(share, JWUnits.PPM, "份额不超过 100%")
	var other0: int = st.treasury.f_receipts_other
	check(_advance(g).ok, "再推一季")
	ge_int(st.treasury.f_receipts_other, 0, "政府其他收入登记（本季 %d）" % st.treasury.f_receipts_other)
	eq_int(st.check_all_p0(), JWResult.OK, "P0 不变量（含政府现金恒等式）通过")


func test_private_route_hands_asset_to_firm() -> void:
	var g: JWGame = _game(52)
	var st: JWSimState = g.get("_st") as JWSimState
	var cell: int = JWIds.idx_cell(2, JWUnits.Sector.MANU)
	var firm_cap0: int = st.accounts.get_balance(JWIds.idx_account(JWIds.agent_of_cell(cell), JWIds.ACC_CAPITAL))
	var gov_cap0: int = st.accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CAPITAL))
	var nb: int = _build_until_stack(g, JWBuildings.OWNER_PRIVATE, 2)
	check(nb >= 0, "扶持私人的工场建成")
	eq_int(st.buildings.owner[nb], JWBuildings.OWNER_PRIVATE, "新堆归企业所有")
	var firm_cap1: int = st.accounts.get_balance(JWIds.idx_account(JWIds.agent_of_cell(cell), JWIds.ACC_CAPITAL))
	var gov_cap1: int = st.accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CAPITAL))
	check(firm_cap1 > firm_cap0, "资产落到企业名下（%d → %d）" % [firm_cap0, firm_cap1])
	eq_int(gov_cap1, gov_cap0, "政府资本不增（已移交）")
	eq_int(st.check_all_p0(), JWResult.OK, "移交后 P0 不变量通过")
	eq_int(st.buildings.gov_share_ppm(st.buildings.cell[nb]), 0, "该单元没有国有份额")


func test_firm_investment_still_grows_default_stack() -> void:
	var g: JWGame = _game(53)
	var st: JWSimState = g.get("_st") as JWSimState
	var cell: int = JWIds.idx_cell(0, JWUnits.Sector.MANU)
	var b: JWBuildings = st.buildings
	var si: int = b.default_stack(cell)
	var v0: int = b.capital_value[si]
	for i: int in 4:
		check(_advance(g).ok, "推进第 %d 季" % i)
	# 第三条路线（企业自主投资）不经命令：企业买资本品，资本与产能进本单元的缺省堆。
	check(b.capital_value[si] != v0, "企业自主投资改变了缺省堆的资本（%d → %d）" % [v0, b.capital_value[si]])
	eq_int(st.capital.check_buildings_consistency(), JWResult.OK, "仍满足 INV-B01")
