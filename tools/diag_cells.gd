## 生产单元诊断（docs/53 M2-8）：在指定季数区间逐季打印某个部门四个生产单元的计划、实际产出、
## 各约束的上限、最紧约束、在岗人数与现金。用来看「某部门为什么突然停产」。
##
## 用法：godot --headless --path <根> --script res://tools/diag_cells.gd -- [剧本=campaign_1600] [起=60] [止=76] [部门=2] [种子=1]
## 部门：0 农业 / 1 制造 / 2 能源 / 3 服务。只读诊断。
extends SceneTree

const Q: float = 1_000_000.0
const U: float = 1_000_000_000.0


func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var scen: String = a[0] if a.size() > 0 else "campaign_1600"
	var q_from: int = int(a[1]) if a.size() > 1 else 60
	var q_to: int = int(a[2]) if a.size() > 2 else 76
	var sec: int = int(a[3]) if a.size() > 3 else JWUnits.Sector.ENERGY
	var seed_v: int = int(a[4]) if a.size() > 4 else 1
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var spec: String = "res://content" if scen == "chengwan" else "res://content#" + scen
	if not loader.load_all(spec, st).ok:
		print("载入失败")
		quit(1)
		return
	st.content_hash = loader.content_hash
	st.rng.set_state_scalar(0, seed_v)
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	loader.load_events_into(events, st)
	JWResult.clear_pending()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	st.crisis.final_window_q = 1 << 40
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)
	var bnames: PackedStringArray = ["计划", "产能", "劳动", "电力", "投入"]
	for q: int in q_to:
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		if runner.advance_quarter(cmds) != 0:
			print("第 %d 季推进失败" % q)
			break
		if q + 1 < q_from:
			continue
		var line: String = "%3d" % (q + 1)
		for r: int in JWUnits.R:
			var c: int = JWIds.idx_cell(r, sec)
			var sm: JWSectorModel = st.sectors
			var emp: int = 0
			for k: int in JWUnits.K:
				emp += st.labor.cell_employment[JWIds.idx_emp(c, k)]
			var b: int = sm.f_binding_code[c]
			line += " │区%d 计%.2f 产%.2f 限[能%.2f 劳%.2f 电%.2f 料%.2f] %s 人%.2f万 现%.2f" % [r,
					sm.f_output_plan[c] / Q, sm.f_output_actual[c] / Q,
					sm.f_bound_capacity[c] / Q, sm.f_bound_labor[c] / Q, sm.f_bound_energy[c] / Q,
					sm.f_bound_materials[c] / Q, bnames[b] if b >= 0 and b < 5 else "?",
					emp / 1e4, st.accounts.cash_of(JWIds.agent_of_cell(c)) / U]
		print(line)
	quit(0)
