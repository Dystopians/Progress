## 状态块协议自检（docs/17 §1.6；M2 审阅 T2 / T6）。
##
## 两件事以前都靠人肉对齐，这里改成遍历检查：
## ① 每个状态块声明的 *_IDS 与 *_SUBSYS 等长、访问器逐下标往返不变、清零后流量绝对值和为 0。
##    新增一个字段却漏了某一处（例如信贷块的标量 SUBSYS 少一项）会在这里直接报出块名与下标。
## ② 战役模式下，被拒的推进（本季没有推进标记）「状态一位不改」——包括 S01 里按价格水平
##    重算的贸易倍率。此前那一步排在推进标记检查之前，被拒时也会改状态哈希。
extends JWTest

const CAMPAIGN: String = "res://content#campaign_1600"
const PAIRS: Array = [
	["STATE_ARRAY_IDS", "STATE_ARRAY_SUBSYS"],
	["STATE_SCALAR_IDS", "STATE_SCALAR_SUBSYS"],
	["FLOW_ARRAY_IDS", "FLOW_ARRAY_SUBSYS"],
	["FLOW_SCALAR_IDS", "FLOW_SCALAR_SUBSYS"],
]


func _state(spec: String) -> JWSimState:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var r: JWResult = loader.load_all(spec, st)
	check(r != null and r.ok, "载入 " + spec)
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
	return st


func test_ids_and_subsys_have_equal_length() -> void:
	var st: JWSimState = _state(CAMPAIGN)
	var blocks: Array = st.get("_blocks")
	for bi: int in blocks.size():
		var b: Object = blocks[bi]
		var cm: Dictionary = (b.get_script() as Script).get_script_constant_map()
		for pr: Array in PAIRS:
			if not cm.has(pr[0]) or not cm.has(pr[1]):
				continue
			eq_int((cm[pr[1]] as Array).size() if cm[pr[1]] is Array else cm[pr[1]].size(),
					cm[pr[0]].size(), "块 %d（%s）的 %s 与 %s 等长" % [bi,
					(b.get_script() as Script).get_global_name(), pr[0], pr[1]])


func test_accessors_round_trip_and_flows_reset() -> void:
	var st: JWSimState = _state(CAMPAIGN)
	var blocks: Array = st.get("_blocks")
	for bi: int in blocks.size():
		var b: Object = blocks[bi]
		var name: String = (b.get_script() as Script).get_global_name()
		var cm: Dictionary = (b.get_script() as Script).get_script_constant_map()
		if cm.has("STATE_ARRAY_IDS") and b.has_method("state_array") and b.has_method("set_state_array"):
			for i: int in cm["STATE_ARRAY_IDS"].size():
				var v: PackedInt64Array = b.call("state_array", i)
				eq_int(int(b.call("set_state_array", i, v)), JWResult.OK,
						"%s 数组 %d 写回原值被接受" % [name, i])
				check(b.call("state_array", i) == v, "%s 数组 %d 往返不变" % [name, i])
		if cm.has("STATE_SCALAR_IDS") and b.has_method("state_scalar") and b.has_method("set_state_scalar"):
			for j: int in cm["STATE_SCALAR_IDS"].size():
				var s: int = b.call("state_scalar", j)
				eq_int(int(b.call("set_state_scalar", j, s)), JWResult.OK,
						"%s 标量 %d 写回原值被接受" % [name, j])
				eq_int(int(b.call("state_scalar", j)), s, "%s 标量 %d 往返不变" % [name, j])
		if b.has_method("reset_flows") and b.has_method("flow_abs_sum"):
			b.call("reset_flows")
			eq_int(int(b.call("flow_abs_sum")), 0, "%s 清零后流量绝对值和为 0" % name)


func test_rejected_advance_leaves_state_untouched_in_campaign() -> void:
	var st: JWSimState = _state(CAMPAIGN)
	# 夹具：让价格水平偏离基年，使 S01 的贸易倍率重算「一旦执行就会改状态」。
	st.money.price_level_ppm = 1_500_000
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var before: String = st.state_hash()
	# 本季没有推进标记：命令流不合法，应被拒，状态一位不改。
	var code: int = runner.advance_quarter(cmds)
	check(code != JWResult.OK, "没有推进标记的一季被拒")
	eq_str(st.state_hash(), before, "被拒的推进状态哈希不变（战役模式，价格水平 ≠ 基年）")
	JWResult.clear_pending()
