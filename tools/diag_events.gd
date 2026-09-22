## 事件诊断：经 JWGame（装载 12 张事件卡）推进 N 季，逐季打印触发的事件与累计次数。
## 用法：godot --headless --path <根> --script res://tools/diag_events.gd -- [季数=40] [种子=1000000]
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 40
	var seed_v: int = int(args[1]) if args.size() > 1 else 1000000
	JWResult.trace_faults = true
	var g: JWGame = JWGame.new()
	g.autosave_slot = "diag_events_autosave"
	var r: JWResult = g.new_game("res://content", seed_v, 40)
	if r == null or not r.ok:
		print("开局失败 %d" % (0 if r == null else r.code))
		quit(1)
		return
	var st: JWSimState = g.get("_st") as JWSimState
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)
	a0.fill(0)
	for q: int in n_q:
		var before: PackedInt64Array = st.politics.event_fire_count.duplicate()
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a0)
		var ra: JWResult = g.advance_quarter()
		if ra != null and not ra.ok:
			print("第 %d 季推进返回 %d" % [q, ra.code])
			break
		var fired: PackedStringArray = PackedStringArray()
		for e: int in JWUnits.EVENT_N:
			if st.politics.event_fire_count[e] > before[e]:
				fired.append("E%02d" % (e + 1))
		if not fired.is_empty():
			print("q%d 触发：%s │ 支持度 %.3f" % [q, ", ".join(fired), st.politics.support_national_ppm(st.pop) / 1e6])
	print("累计：%s" % str(st.politics.event_fire_count))
	quit(0)
