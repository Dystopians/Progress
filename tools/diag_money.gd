## 货币发行诊断（R-MONEY-01）：战役剧本、强制高目标通胀，逐季打印发行额并打印故障现场。
## 用法：godot --headless --path . --script res://tools/diag_money.gd -- [季数=8]
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n: int = int(args[0]) if args.size() > 0 else 8
	JWResult.trace_faults = true
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_diag_money"
	print("new_game ok=", g.new_game("res://content#campaign_1600", 11, 0).ok)
	var st: JWSimState = g.get("_st") as JWSimState
	st.money.target_inflation_ppm_per_year = 400_000
	st.money.adjust_ppm = JWUnits.PPM
	st.money.issue_cap_ppm = 50_000
	for i: int in n:
		var a: PackedInt64Array = PackedInt64Array()
		a.resize(JWCommands.ARG_SLOTS)
		a.fill(0)
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a)
		var r: JWResult = g.advance_quarter()
		print("q%d ok=%s code=%d issued_q=%d total=%d level=%d" % [i, str(r == null or r.ok),
				r.code if r else 0, st.treasury.f_money_issued, st.money.issued_total, st.money.price_level_ppm])
		if r != null and not r.ok:
			break
	quit()
