## 5 区夹具的单季诊断（R-SCENARIO-02）：生成夹具、开局、推进，打印故障现场。
## 用法：godot --headless --path . --script res://tools/diag_region5.gd -- [季数]
extends SceneTree


func _init() -> void:
	var n: int = 1
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		n = args[0].to_int()
	var T: GDScript = load("res://tests/scenario/region_dims_test.gd")
	var spec: String = T.build_fixture()
	JWResult.trace_faults = true
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_diag_region5"
	var r: JWResult = g.new_game(spec, 99, 0)
	print("new_game ok=%s code=%d" % [str(r.ok), r.code])
	for i: int in n:
		var a: PackedInt64Array = PackedInt64Array()
		a.resize(JWCommands.ARG_SLOTS)
		a.fill(0)
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a)
		var ra: JWResult = g.advance_quarter()
		print("q%d ok=%s code=%d a=%d b=%d step=%d" % [i, str(ra == null or ra.ok), ra.code if ra else 0,
				ra.detail_a if ra else 0, ra.detail_b if ra else 0, JWResult.pending_step()])
		if ra != null and not ra.ok:
			break
	quit()
