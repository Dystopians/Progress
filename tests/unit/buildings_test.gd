## 建筑堆是生产单元产能与资本的唯一来源（docs/18 R-BUILDING-01；docs/53 M1-5）。
extends JWTest


func _game(spec: String, seed_v: int) -> JWGame:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_buildings"
	check(g.new_game(spec, seed_v, 0).ok, "开局 " + spec)
	return g


func _advance(g: JWGame, n: int) -> void:
	for i: int in n:
		var a: PackedInt64Array = PackedInt64Array()
		a.resize(JWCommands.ARG_SLOTS)
		a.fill(0)
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a)
		var r: JWResult = g.advance_quarter()
		check(r == null or r.ok, "推进第 %d 季" % i)


func test_legacy_seed_matches_scenario() -> void:
	var g: JWGame = _game("res://content", 3)
	var st: JWSimState = g.get("_st") as JWSimState
	eq_int(st.buildings.count, JWUnits.CELL, "每个 cell 一个既有设施堆")
	for c: int in JWUnits.CELL:
		eq_int(st.buildings.cell[c], c, "第 %d 堆属于 cell %d" % [c, c])
		eq_int(st.buildings.capacity_active[c], st.capital.cell_capacity_active[c], "在用产能迁移")
		eq_int(st.buildings.capital_value[c], st.capital.cell_capital_value[c], "资本价值迁移")
	eq_int(st.capital.check_buildings_consistency(), JWResult.OK, "开局一致")


func test_consistency_holds_while_running() -> void:
	var g: JWGame = _game("res://content", 5)
	var st: JWSimState = g.get("_st") as JWSimState
	for q: int in 6:
		_advance(g, 1)
		eq_int(st.capital.check_buildings_consistency(), JWResult.OK, "第 %d 季末 cell 三列 == 堆表求和" % q)
	# 篡改一个堆 ⇒ 一致性检查必须抓到（INV-B01 不是空检查）。
	st.buildings.capacity_active[0] += 1
	check(st.capital.check_buildings_consistency() != JWResult.OK, "篡改堆表被 INV-B01 抓到")
	JWResult.clear_pending()


func test_two_stacks_in_one_cell_aggregate_and_depreciate() -> void:
	var g: JWGame = _game("res://content#campaign_1600", 7)
	var st: JWSimState = g.get("_st") as JWSimState
	var c: int = JWIds.idx_cell(1, JWUnits.Sector.MANU)
	var cap0: int = st.capital.cell_capacity_active[c]
	var val0: int = st.capital.cell_capital_value[c]
	# 把该 cell 的既有设施拆成两堆（总量不变），第二堆记为政府所有（M2 的国有试点形态）。
	var half_cap: int = JWMath.floor_div(cap0, 2)
	var half_val: int = JWMath.floor_div(val0, 2)
	st.buildings.capacity_active[c] = cap0 - half_cap
	st.buildings.capital_value[c] = val0 - half_val
	var b2: int = st.buildings.add_stack(c, JWBuildings.TYPE_LEGACY, JWBuildings.OWNER_GOV,
			JWBuildings.METHOD_LEGACY, 1, half_cap, half_val, 0, 900)
	check(b2 >= 0, "新增第二堆")
	st.capital.sync_cells_from_buildings()
	eq_int(st.capital.cell_capacity_active[c], cap0, "两堆求和 == 原在用产能")
	eq_int(st.capital.cell_capital_value[c], val0, "两堆求和 == 原资本价值")
	_advance(g, 2)
	eq_int(st.capital.check_buildings_consistency(), JWResult.OK, "两堆 cell 推进两季后仍一致")
	check(st.buildings.capacity_active[b2] < half_cap, "第二堆也在折旧")
	eq_int(st.buildings.default_stack(c), c, "企业购置与项目完工仍落在私人所有的既有设施堆")
