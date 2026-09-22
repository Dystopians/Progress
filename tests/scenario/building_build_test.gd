## 建筑类型、生产方式、建造与改造（docs/18 R-METHOD-01；docs/53 M2-2）。
extends JWTest

const CAMPAIGN: String = "res://content#campaign_1600"


func _game(spec: String, seed_v: int) -> JWGame:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_build"
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


func _last_code(g: JWGame, kind: int) -> int:
	var log: Dictionary = g.command_log_copy()
	var kinds: PackedInt64Array = log["kind"]
	var acc: PackedInt64Array = log["accepted"]
	var rej: PackedInt64Array = log["reject_code"]
	for i: int in range(kinds.size() - 1, -1, -1):
		if kinds[i] == kind:
			return 0 if acc[i] == 1 else rej[i]
	return -1


## 夹具：把某项科技直接标成已完成（只改研究状态，不绕过任何结算规则）。
func _complete(st: JWSimState, t: int) -> void:
	st.research.completed_mask = st.research.completed_mask | (1 << t)
	st.research.advance_research(0)


func test_cards_loaded() -> void:
	var st: JWSimState = (_game(CAMPAIGN, 41).get("_st")) as JWSimState
	var b: JWBuildings = st.buildings
	eq_int(b.type_count, 7, "6 张建筑卡 + 既有设施 == 7 类")
	eq_int(b.method_count, 5, "4 张方式卡 + 既有方式 == 5 种")
	eq_int(b.m_output_ppm[0], JWUnits.PPM, "既有方式的倍率恒为 1e6")
	for m: int in range(1, b.method_count):
		ge_int(b.m_building[m], 1, "方式 %d 指向一个建筑类型" % m)


func test_build_requires_unlock_then_succeeds() -> void:
	var g: JWGame = _game(CAMPAIGN, 42)
	var st: JWSimState = g.get("_st") as JWSimState
	var b: JWBuildings = st.buildings
	# 工场（建筑 3）由「行会工场」（科技 4）解锁；未解锁时建造被拒。
	g.submit_command(JWCommands.Kind.BUILD_BUILDING, _args([3, 1, JWBuildings.OWNER_GOV, 0]))
	check(_advance(g).ok, "推进一季")
	eq_int(_last_code(g, JWCommands.Kind.BUILD_BUILDING), JWResult.Reject.PRECONDITION,
			"科技未解锁 ⇒ 建造被拒")
	_complete(st, 4)
	var stacks0: int = b.count
	g.submit_command(JWCommands.Kind.BUILD_BUILDING, _args([3, 1, JWBuildings.OWNER_GOV, 0]))
	check(_advance(g).ok, "推进一季（已解锁）")
	eq_int(_last_code(g, JWCommands.Kind.BUILD_BUILDING), 0, "解锁后建造受理")
	ge_int(st.projects.count, 1, "建了一个项目")
	var p: int = st.projects.count - 1
	eq_int(st.projects.building_type[p], 3, "项目记下建筑类型")
	eq_int(st.projects.policy_idx[p], -1, "建筑项目没有政策卡")
	eq_int(b.count, stacks0, "开工时还没有新堆（完工才建堆）")


func test_completed_building_lands_on_a_stack() -> void:
	var g: JWGame = _game(CAMPAIGN, 43)
	var st: JWSimState = g.get("_st") as JWSimState
	var b: JWBuildings = st.buildings
	_complete(st, 4)
	g.submit_command(JWCommands.Kind.BUILD_BUILDING, _args([3, 1, JWBuildings.OWNER_GOV, 0]))
	check(_advance(g).ok, "开工")
	var cell: int = JWIds.idx_cell(1, JWUnits.Sector.MANU)
	var cap0: int = st.capital.cell_capacity_active[cell]
	var stacks0: int = b.count
	# 工期 4 季 + 转入 1 季：推进足够多季直到出现新堆。
	for i: int in 12:
		_advance(g)
		if b.count > stacks0:
			break
	ge_int(b.count, stacks0 + 1, "完工后多了一个建筑堆")
	var nb: int = b.count - 1
	eq_int(b.type[nb], 3, "新堆的类型是工场")
	eq_int(b.owner[nb], JWBuildings.OWNER_GOV, "新堆归政府所有")
	eq_int(b.cell[nb], cell, "新堆落在该地区的制造业单元")
	eq_int(st.capital.check_buildings_consistency(), JWResult.OK, "cell 三列仍等于堆表求和")
	for i2: int in 2:
		_advance(g)
	ge_int(st.capital.cell_capacity_active[cell], cap0, "该单元的在用产能不低于开工前")


func test_retrofit_freezes_then_switches_method() -> void:
	var g: JWGame = _game(CAMPAIGN, 44)
	var st: JWSimState = g.get("_st") as JWSimState
	var b: JWBuildings = st.buildings
	_complete(st, 4)
	_complete(st, 5)
	# 先建一座工场并等它完工。
	g.submit_command(JWCommands.Kind.BUILD_BUILDING, _args([3, 1, JWBuildings.OWNER_GOV, 0]))
	check(_advance(g).ok, "开工")
	var stacks0: int = b.count
	for i: int in 12:
		_advance(g)
		if b.count > stacks0:
			break
	var nb: int = b.count - 1
	eq_int(b.method[nb], 0, "建成时是既有方式")
	# 再推一季：完工写的是待投运产能，S01 才转在用（INV-091）。
	check(_advance(g).ok, "完工后再推一季，产能转在用")
	var cap_before: int = b.effective_capacity(nb)
	ge_int(cap_before, 1, "新堆已有在用产能")
	# 改造成水力工场（方式 4）。
	g.submit_command(JWCommands.Kind.RETROFIT_STACK, _args([b.entity[nb], 4]))
	check(_advance(g).ok, "改造开工")
	eq_int(_last_code(g, JWCommands.Kind.RETROFIT_STACK), 0, "改造受理")
	eq_int(b.frozen_ppm[nb], b.m_retrofit_frozen[4], "改造期间冻结部分产能")
	check(b.effective_capacity(nb) < cap_before, "冻结期间该堆的有效产能下降")
	eq_int(st.capital.check_buildings_consistency(), JWResult.OK, "冻结也走同一条汇总，不破坏 INV-B01")
	for i2: int in 10:
		_advance(g)
		if b.method[nb] == 4:
			break
	eq_int(b.method[nb], 4, "改造完工后切到新方式")
	eq_int(b.frozen_ppm[nb], 0, "解冻")
	eq_int(st.capital.check_buildings_consistency(), JWResult.OK, "改造完工后仍一致")


func test_method_multipliers_reach_production() -> void:
	var g: JWGame = _game(CAMPAIGN, 45)
	var st: JWSimState = g.get("_st") as JWSimState
	var b: JWBuildings = st.buildings
	var cell: int = JWIds.idx_cell(2, JWUnits.Sector.MANU)
	check(_advance(g).ok, "推进一季")
	eq_int(st.io.labor_of(cell, 0), st.io.labor(cell, 0), "全是既有设施 ⇒ 倍率 1.0，与基线逐位相同")
	# 夹具：把该单元的既有设施堆整体切到「水力工场」方式（低技能劳动系数 0.85）。
	var si: int = b.default_stack(cell)
	b.method[si] = 4
	b.type[si] = 3
	st.capital.sync_cells_from_buildings()
	check(_advance(g).ok, "再推进一季（S01 重算倍率）")
	eq_int(st.io.cell_labor_mult[JWIds.idx_emp(cell, 0)], b.m_labor_ppm[4 * JWUnits.K + 0],
			"单堆 cell 的倍率就是该方式的倍率")
	eq_int(st.io.labor_of(cell, 0), JWMath.mul_ppm(st.io.labor(cell, 0), b.m_labor_ppm[4 * JWUnits.K]),
			"生产函数读到的劳动系数按方式折算")


func test_term_mode_cannot_build() -> void:
	var g: JWGame = _game("res://content", 46)
	var st: JWSimState = g.get("_st") as JWSimState
	eq_int(st.buildings.type_count, 7, "旧剧本也读到建筑卡（内容包公共区）")
	g.submit_command(JWCommands.Kind.BUILD_BUILDING, _args([3, 1, JWBuildings.OWNER_GOV, 0]))
	check(_advance(g).ok, "推进一季")
	eq_int(_last_code(g, JWCommands.Kind.BUILD_BUILDING), JWResult.Reject.PRECONDITION,
			"旧剧本没有研究，建筑未解锁 ⇒ 建造被拒")
