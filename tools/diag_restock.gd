## 诊断：第 0 季结束后逐 cell 打印投入品的实耗、期末存量、补货需求与 cell 现金。
extends SceneTree


func _init() -> void:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	loader.load_all("res://content", st)
	st.rng.set_state_scalar(0, 1000000)
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	JWResult.clear_pending()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)
	cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, 0, st.policy_defs)
	runner.advance_quarter(cmds)
	var names: PackedStringArray = PackedStringArray(["农", "制", "能", "服"])
	print("cell │ 投入品：实耗/期末存量/补货需求（Q） ×4 │ 现金 U")
	for c: int in JWUnits.CELL:
		var line: String = "%2d │" % c
		for j: int in JWUnits.S:
			var idx: int = JWIds.idx_inv(c, j)
			line += " %s %4.2f/%4.2f/%4.2f" % [names[j], st.inventory.f_consumed[idx] / 1e6,
					st.inventory.inv_input[idx] / 1e6, st.inventory._firm_demand[idx] / 1e6]
		line += " │ %5.2f" % (st.accounts.cash_of(JWIds.agent_of_cell(c)) / 1e9)
		print(line)
	quit(0)
