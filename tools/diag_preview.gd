## 情景预测自检：开局推进 2 季后调 JWGame.preview_four_quarters()，确认能跑完且不改真实状态哈希。
extends SceneTree


func _init() -> void:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "diag_preview_autosave"
	g.new_game("res://content", 1000000, 40)
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)
	a0.fill(0)
	for i: int in 2:
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a0)
		g.advance_quarter()
	var st: JWSimState = g.get("_st") as JWSimState
	var h0: String = st.state_hash()
	var r: JWResult = g.preview_four_quarters()
	print("预测：%s；真实状态哈希%s" % ["ok" if r != null and r.ok else "失败 %d" % (0 if r == null else r.code),
			"不变" if st.state_hash() == h0 else "**被改动**"])
	quit(0)
