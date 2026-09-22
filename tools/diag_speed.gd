## 推进路径分项计时（docs/53 M1-9）：结算器 / 自动存档追加 / 状态哈希 / 检查点追加。
## 用法：godot --headless --path . --script res://tools/diag_speed.gd -- [季数=200]
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n: int = int(args[0]) if args.size() > 0 else 200
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_diag_speed"
	g.new_game("res://content" if args.has("term") else "res://content#campaign_1600", 1, 0)
	var st: JWSimState = g.get("_st") as JWSimState
	st.crisis.final_window_q = 1 << 40
	var runner: JWTurnRunner = g.get("_runner") as JWTurnRunner
	var cmds: JWCommands = g.get("_cmds") as JWCommands
	var saves: JWSaves = g.get("_saves") as JWSaves
	var t_run: int = 0
	var t_auto: int = 0
	var t_hash: int = 0
	var t_ck: int = 0
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	for i: int in n:
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a)
		var t0: int = Time.get_ticks_usec()
		var code: int = runner.advance_quarter(cmds)
		var t1: int = Time.get_ticks_usec()
		saves.autosave_append(st, cmds, g.autosave_slot)
		var t2: int = Time.get_ticks_usec()
		var h: String = st.state_hash()
		var t3: int = Time.get_ticks_usec()
		saves.append_checkpoint(st.q - 1, h, runner.step_hashes(), g.autosave_slot)
		var t4: int = Time.get_ticks_usec()
		t_run += t1 - t0
		t_auto += t2 - t1
		t_hash += t3 - t2
		t_ck += t4 - t3
		if code != 0:
			print("第 %d 季失败 %d" % [i, code])
			break
		if i % 50 == 49 or i == n - 1:
			print("到第 %d 季：结算 %.1f ms/季，自动存档 %.1f，状态哈希 %.1f，检查点 %.1f" % [i + 1,
					t_run / 1000.0 / (i + 1), t_auto / 1000.0 / (i + 1), t_hash / 1000.0 / (i + 1),
					t_ck / 1000.0 / (i + 1)])
	quit()
