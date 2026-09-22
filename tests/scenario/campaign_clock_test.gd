## 多剧本并存与长时钟（docs/18 R-SCENARIO-01、R-CLOCK-01；docs/53 M1-1）。
## 旧剧本 chengwan 默认载入、模式为单届；战役剧本 campaign_1600 经 `#剧本名` 载入，
## 模式、起始年份、1600 季时长各自就位；内容指纹按剧本分开；v1 存档迁移到 v2。
extends JWTest

const CAMPAIGN: String = "res://content#campaign_1600"


func _load(spec: String) -> Array:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var ld: JWContentLoader = JWContentLoader.new()
	var r: JWResult = ld.load_all(spec, st)
	return [r, st, ld]


func test_default_scenario_is_term_mode() -> void:
	var x: Array = _load("res://content")
	var r: JWResult = x[0]
	var st: JWSimState = x[1]
	check(r != null and r.ok, "不带后缀 ⇒ 载入旧剧本")
	eq_str(st.scenario_id, "scenario.chengwan", "默认剧本是 chengwan")
	eq_int(st.mode, JWUnits.Mode.TERM, "旧剧本不写 mode ⇒ 单届")
	eq_int(st.start_year, 0, "旧剧本不显示公历年份")
	eq_int(st.horizon_q, 40, "旧剧本 40 季")


func test_campaign_scenario_loads() -> void:
	var x: Array = _load(CAMPAIGN)
	var r: JWResult = x[0]
	var st: JWSimState = x[1]
	var ld: JWContentLoader = x[2]
	check(r != null and r.ok, "战役剧本载入成功（错误 %s）" % (str(ld.errors) if r == null or not r.ok else ""))
	eq_str(st.scenario_id, "scenario.campaign_1600", "剧本 ID")
	eq_int(st.mode, JWUnits.Mode.CAMPAIGN, "战役模式")
	eq_int(st.start_year, 1600, "起始 1600 年")
	eq_int(st.horizon_q, JWUnits.HORIZON_Q_MAX, "1600 季")
	eq_str(ld.root_path(), CAMPAIGN, "root_path 原样返回带后缀的根，重放据此重载同一剧本")


func test_bad_scenario_name_rejected() -> void:
	for bad: String in ["res://content#../x", "res://content#", "res://content#Camp", "res://content#nope"]:
		var x: Array = _load(bad)
		var r: JWResult = x[0]
		check(r != null and not r.ok, "非法或不存在的剧本名被拒：" + bad)


func test_content_hash_is_per_scenario() -> void:
	var a: Array = _load("res://content")
	var b: Array = _load(CAMPAIGN)
	var la: JWContentLoader = a[2]
	var lb: JWContentLoader = b[2]
	check(la.content_hash != "" and lb.content_hash != "", "两个指纹都算出来了")
	check(la.content_hash != lb.content_hash, "两个剧本的内容指纹不同")
	check(la.scenario_hash != lb.scenario_hash, "两个剧本的剧本指纹不同")
	# 再载一次旧剧本：指纹稳定（与别的剧本目录无关）。
	var c: Array = _load("res://content")
	eq_str((c[2] as JWContentLoader).content_hash, la.content_hash, "旧剧本指纹稳定")


func test_campaign_new_game_advances_and_replays() -> void:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_campaign"
	var r: JWResult = g.new_game(CAMPAIGN, 4242, 0)
	check(r != null and r.ok, "战役开局")
	for i: int in 4:
		var a: PackedInt64Array = PackedInt64Array()
		a.resize(JWCommands.ARG_SLOTS)
		a.fill(0)
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a)
		var ra: JWResult = g.advance_quarter()
		check(ra == null or ra.ok, "推进第 %d 季" % i)
	eq_int(g.view().q(), 4, "推进一年")
	var rs: JWResult = g.save_game("test_campaign_clock")
	check(rs != null and rs.ok, "存档")
	var rv: JWResult = g.verify_replay("test_campaign_clock")
	check(rv != null and rv.ok, "重放逐位一致（重放按 root_path 重载同一战役剧本）")

	# 在一局旧剧本里读战役存档：JWGame 按 manifest 换内容包。
	var h: JWGame = JWGame.new()
	h.autosave_slot = "autosave_test_campaign2"
	check(h.new_game("res://content", 7, 0).ok, "旧剧本开局")
	var rl: JWResult = h.load_game("test_campaign_clock")
	check(rl != null and rl.ok, "跨剧本读档成功")
	eq_str(h.view().scenario_id(), "scenario.campaign_1600", "读档后是战役剧本")
	eq_int(h.view().q(), 4, "读回第 4 季")
	check(not h.read_only_mode, "内容指纹一致 ⇒ 不进只读")


func test_v1_save_migrates_to_v2() -> void:
	var x: Array = _load("res://content")
	var st: JWSimState = x[1]
	var d: Dictionary = st.to_dict()
	var sc: Dictionary = d[JWSimState.SAVE_KEY_SCALARS]
	check(sc.has("state.meta.mode") and sc.has("state.time.start_year"), "v2 存档含两个新标量")
	sc.erase("state.meta.mode")
	sc.erase("state.time.start_year")
	for k: String in ["state.money.issued_total_uu", "state.money.price_level_ppm",
			"state.money.target_level_ppm", "flow.gov.money_issued_uu"]:
		sc.erase(k)
	var arrs: Dictionary = d[JWSimState.SAVE_KEY_ARRAYS]
	arrs.erase("state.money.real_gdp_ring_uu")
	arrs.erase("state.project.entity")
	arrs.erase("state.bond.entity")
	for bid: String in JWBuildings.STATE_ARRAY_IDS:
		arrs.erase(bid)
	sc.erase("state.building.count")
	arrs.erase("state.crisis.stage")
	arrs.erase("state.crisis.since_q")
	sc.erase("state.politics.gov_changes")
	sc.erase("state.politics.last_gov_change_q")
	d[JWSimState.SAVE_KEY_SCHEMA] = 1
	var sv: JWSaves = JWSaves.new()
	var rm: JWResult = sv.migrate(d, 1)
	check(rm != null and rm.ok, "v1 → v2 迁移成功")
	eq_int(int(d[JWSimState.SAVE_KEY_SCHEMA]), 2, "迁移后版本 2")
	var st2: JWSimState = JWSimState.new()
	st2.allocate_all()
	var rf: JWResult = st2.from_dict(d)
	check(rf != null and rf.ok, "迁移后的字典可读入")
	eq_int(st2.mode, JWUnits.Mode.TERM, "v1 存档迁移为单届")
	eq_int(st2.buildings.count, JWUnits.CELL, "v1 存档迁移出每个 cell 一个既有设施堆")
	eq_int(st2.capital.check_buildings_consistency(), JWResult.OK, "迁移后 cell 三列 == 堆表求和")
	eq_int(st2.bonds.entity[0], -1, "开局存量债的实体号由 ID 解析为 −1")
