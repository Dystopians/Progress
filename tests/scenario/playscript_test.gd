## 行动脚本（application/playscript.gd，2026-09-23 用户要求）：按季度经真实命令路径提交脚本动作并推进。
## 脚本只产生普通命令，照常经 S02 受理或拒绝；同一脚本同一种子必须逐位可复现。
extends JWTest

const CAMPAIGN: String = "res://content#campaign_1600"


func _game(seed_v: int) -> JWGame:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test_playscript"
	check(g.new_game(CAMPAIGN, seed_v, 0).ok, "战役开局")
	return g


func _script(extra: Dictionary) -> Dictionary:
	var d: Dictionary = {"schema_kind": "playscript", "schema_version": 1, "name": "测试",
			"scenario": "campaign_1600", "seed": 5, "events": {"default": "skip"}}
	d.merge(extra, true)
	return d


func test_time_parsing() -> void:
	eq_int(JWPlayscript._parse_q("1600", 1600), 0, "开局年春 = 第 0 季")
	eq_int(JWPlayscript._parse_q("1650", 1600), 200, "1650 年春 = 第 200 季")
	eq_int(JWPlayscript._parse_q("1601秋", 1600), 6, "1601 年秋 = 第 6 季")
	eq_int(JWPlayscript._parse_q("q:37", 1600), 37, "直接写季下标")
	eq_int(JWPlayscript._parse_q("明年", 1600), -1, "认不出的写法返回 −1")
	eq_int(JWPlayscript._parse_q("1650", 0), -1, "没有公历年的剧本不能按年份写")


func test_ids_resolve_against_loaded_content() -> void:
	var g: JWGame = _game(5)
	var ps: JWPlayscript = JWPlayscript.from_dict(_script({"research": ["tech.survey", "tech.bookkeeping"],
			"build_queue": [{"build": "building.market_hall", "region": "region.zhongzhou"}],
			"timeline": [{"at": "1601", "do": [{"trade": "partner.south_isles", "mode": "import"}]}]}))
	check(g.playscript_bind(ps), "全部 ID 都能解析：" + str(ps.errors))
	eq_int(ps.pending_count(), 2, "时间线 1 项 + 建造队列 1 项待执行")
	var bad: JWPlayscript = JWPlayscript.from_dict(_script({"research": ["tech.no_such"],
			"timeline": [{"at": "1601", "do": [{"build": "building.nope", "region": "region.beiyuan"}]}]}))
	check(not g.playscript_bind(bad), "错 ID 必须报出来")
	eq_int(bad.errors.size(), 2, "两处错误各记一条")


func test_research_queue_and_build_go_through_s02() -> void:
	var g: JWGame = _game(5)
	var st: JWSimState = g.get("_st") as JWSimState
	var ps: JWPlayscript = JWPlayscript.from_dict(_script({"research": ["tech.bookkeeping"],
			"build_queue": [{"build": "building.market_hall", "region": "region.zhongzhou"}]}))
	check(g.playscript_bind(ps), "绑定")
	var stacks0: int = st.buildings.count
	var out: Dictionary = g.run_playscript(ps, 40)
	eq_int(int(out["code"]), 0, "推进无故障")
	eq_int(st.q, 40, "推进到第 40 季")
	check((st.research.completed_mask >> 3) & 1 == 1, "复式记账研究完成")
	eq_int(ps.pending_count(), 0, "建造队列执行完")
	eq_int(st.buildings.count, stacks0 + 1, "多了一个市集商行的建筑堆")
	var accepted: int = 0
	for e: Dictionary in ps.log:
		if bool(e["accepted"]):
			accepted += 1
	eq_int(accepted, ps.log.size(), "脚本动作全部被 S02 受理")


func test_rejected_action_is_retried_then_dropped() -> void:
	var g: JWGame = _game(5)
	# 未研究「行会工场」时手工工场不能建：守卫让它一直等，而不是被拒。改用发债上限外的金额制造真正的拒绝。
	var ps: JWPlayscript = JWPlayscript.from_dict(_script({"rules": {"retry_quarters": 2},
			"timeline": [{"at": "1600", "do": [{"bond_u": 100000, "tenor_q": 8}]}]}))
	check(g.playscript_bind(ps), "绑定")
	g.run_playscript(ps, 6)
	var rej: int = 0
	var gave_up: bool = false
	for e: Dictionary in ps.log:
		if not bool(e["accepted"]):
			rej += 1
		if String(e["label"]).ends_with("放弃）"):
			gave_up = true
	ge_int(rej, 3, "被拒后按规则重试")
	check(gave_up, "超过重试期就放弃并留档")
	eq_int(ps.pending_count(), 0, "放弃后出队")


func test_same_script_same_seed_is_bit_identical() -> void:
	var d: Dictionary = _script({"research": ["tech.survey", "tech.water_management"],
			"events": {"default": 0},
			"build_queue": [{"build": "building.irrigation_basic", "region": "region.beiyuan", "owner": "gov"}]})
	var hashes: PackedStringArray = PackedStringArray()
	for i: int in 2:
		var g: JWGame = _game(9)
		var ps: JWPlayscript = JWPlayscript.from_dict(d)
		check(g.playscript_bind(ps), "绑定")
		g.run_playscript(ps, 24)
		hashes.append(str((g.get("_st") as JWSimState).state_hash()))
	eq_str(hashes[0], hashes[1], "两次运行状态哈希一致")


func test_shipped_playscripts_parse() -> void:
	var g: JWGame = _game(1)
	for f: String in DirAccess.get_files_at("res://tools/playscripts"):
		if not f.ends_with(".json"):
			continue
		var ps: JWPlayscript = JWPlayscript.from_file("res://tools/playscripts/" + f)
		check(ps.ok(), f + " 能读")
		check(g.playscript_bind(ps), f + " 的 ID 全部能解析：" + str(ps.errors))
		ge_int(ps.until_q, 1, f + " 写了截止时间")
