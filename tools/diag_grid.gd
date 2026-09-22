## 分地区电网诊断：逐季打印各地区电网容量、本地发电、用电需求、实际供电与未满足量（Q）。
## 用法：godot --headless --path <根> --script res://tools/diag_grid.gd -- [季数=8] [noshock]
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 8
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all("res://content", st)
	if res == null or not res.ok:
		print("载入失败")
		quit(1)
		return
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
	st.rng.set_state_scalar(0, 1000000)
	if args.size() > 1 and args[1] == "noshock":
		st.shocks.hazard_ppm.fill(0)
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	JWResult.clear_pending()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)
	var names: PackedStringArray = ["北原", "中州", "海岬", "西岭"]
	for q: int in n_q:
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		if runner.advance_quarter(cmds) != JWResult.OK:
			print("第 %d 季推进失败" % q)
			break
		var line: String = "q%-2d" % q
		for r: int in JWUnits.R:
			var gen: int = st.sectors.f_output_actual[JWIds.idx_cell(r, JWUnits.Sector.ENERGY)]
			var manu_bind: int = st.sectors.f_binding_code[JWIds.idx_cell(r, JWUnits.Sector.MANU)]
			line += " │ %s 容量 %.2f 发电 %.2f 需求 %.2f 供电 %.2f 缺 %.2f 制造约束 %d" % [names[r],
					st.capital.grid_capacity[r] / 1e6, gen / 1e6, st.sectors.f_elec_demand[r] / 1e6,
					st.sectors.f_elec_supply[r] / 1e6, st.sectors.f_elec_unmet[r] / 1e6, manu_bind]
		print(line)
	quit(0)
