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
	# 重放校验要有东西可比：手动存档必须带上本局 4 季的检查点（此前新槽是空文件，校验空过）。
	var ck: String = FileAccess.get_file_as_string("user://saves/test_campaign_clock/checkpoints.jsonl")
	eq_int(ck.strip_edges().split("\n", false).size(), 4, "手动存档带 4 条检查点（本局的，不含别局）")
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
	# 按 v1 基线提交导出的真实键表把当前存档裁成 v1 形状（tests/fixtures/v1_save_keys.json）。
	# 此前是手工逐个删已知的新键，漏删一个就测不出来——信贷流量漏迁移就是这么溜过去的。
	var fx: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v1_save_keys.json"))
	check(fx is Dictionary, "v1 键表夹具可读")
	var v1: Dictionary = fx
	var keep_sc: Dictionary = {}
	for k: Variant in v1["scalars"]:
		keep_sc[String(k)] = true
	var keep_ar: Dictionary = {}
	for k2: Variant in v1["arrays"]:
		keep_ar[String(k2)] = true
	var sc: Dictionary = d[JWSimState.SAVE_KEY_SCALARS]
	var arrs: Dictionary = d[JWSimState.SAVE_KEY_ARRAYS]
	var dropped: int = 0
	for k3: Variant in sc.keys():
		if not keep_sc.has(String(k3)):
			sc.erase(k3)
			dropped += 1
	for k4: Variant in arrs.keys():
		if not keep_ar.has(String(k4)):
			arrs.erase(k4)
			dropped += 1
	ge_int(dropped, 1, "当前存档确实比 v1 多出新键（否则本测试没有意义）")
	d[JWSimState.SAVE_KEY_SCHEMA] = 1
	var sv: JWSaves = JWSaves.new()
	var rm: JWResult = sv.migrate(d, 1)
	check(rm != null and rm.ok, "v1 → v2 迁移成功")
	eq_int(int(d[JWSimState.SAVE_KEY_SCHEMA]), 2, "迁移后版本 2")
	var st2: JWSimState = JWSimState.new()
	st2.allocate_all()
	var rf: JWResult = st2.from_dict(d)
	check(rf != null and rf.ok, "迁移后的字典可读入（任何新 ID 忘了写迁移都会在这里失败）")
	if rf == null or not rf.ok:
		return
	eq_int(st2.mode, JWUnits.Mode.TERM, "v1 存档迁移为单届")
	eq_int(st2.buildings.count, JWUnits.CELL, "v1 存档迁移出每个 cell 一个既有设施堆")
	eq_int(st2.capital.check_buildings_consistency(), JWResult.OK, "迁移后 cell 三列 == 堆表求和")
	eq_int(st2.bonds.entity[0], -1, "开局存量债的实体号由 ID 解析为 −1")


## R-CLOCK-01 第二部分：批量推进就是逐季推进，逐位相同。
func test_batch_equals_quarter_by_quarter() -> void:
	var a: JWGame = JWGame.new()
	a.autosave_slot = "autosave_test_batch_a"
	check(a.new_game(CAMPAIGN, 77, 0).ok, "开局 A")
	var r: Dictionary = a.advance_batch(6)
	eq_int(int(r["advanced"]), 6, "批量推进 6 季（第 15 季才选举，途中不该停）")
	eq_int(int(r["reason"]), JWGame.Pause.NONE, "无暂停原因")
	var b: JWGame = JWGame.new()
	b.autosave_slot = "autosave_test_batch_b"
	check(b.new_game(CAMPAIGN, 77, 0).ok, "开局 B")
	for i: int in 6:
		var args: PackedInt64Array = PackedInt64Array()
		args.resize(JWCommands.ARG_SLOTS)
		args.fill(0)
		b.submit_command(JWCommands.Kind.ADVANCE_QUARTER, args)
		check(b.advance_quarter().ok, "逐季第 %d 季" % i)
	eq_str((a.get("_st") as JWSimState).state_hash(), (b.get("_st") as JWSimState).state_hash(),
			"批量与逐季逐位相同")


func test_batch_pauses_at_election() -> void:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_batch_c"
	check(g.new_game(CAMPAIGN, 78, 0).ok, "开局")
	var r: Dictionary = g.advance_batch(40)
	var reason: int = int(r["reason"])
	check(reason != JWGame.Pause.NONE, "40 季内必有暂停原因（第 15 季选举）")
	le_int(int(r["advanced"]), 16, "最迟在第一次选举后停下（推进 %d 季，原因 %d）" % [int(r["advanced"]), reason])
