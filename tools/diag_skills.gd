## 技能结构诊断（docs/53 M2-8）：每 step 季打印三档技能的劳动力、在岗人数与失业率，以及三档工资。
## 用来看「失业率平稳而产出下滑」时，是不是某一档技能（通常是中高技能）在长期短缺。
##
## 用法：godot --headless --path <根> --script res://tools/diag_skills.gd -- [剧本=campaign_1600] [季数=160] [步=20] [种子=1]
## 只读诊断。
extends SceneTree


func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	var scen: String = a[0] if a.size() > 0 else "campaign_1600"
	var n_q: int = int(a[1]) if a.size() > 1 else 160
	var step: int = int(a[2]) if a.size() > 2 else 20
	var seed_v: int = int(a[3]) if a.size() > 3 else 1
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
	var names: PackedStringArray = ["低", "中", "高"]
	print("季   ┃ 技能：劳动力(万) 在岗(万) 失业%   ×3 ┃ 工资(低 中 高) ┃ 总人口(万) 实际GDP")
	for q: int in n_q:
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		if runner.advance_quarter(cmds) != 0:
			print("第 %d 季推进失败" % q)
			break
		if q % step != step - 1:
			continue
		var line: String = "%4d ┃" % (q + 1)
		for k: int in JWUnits.K:
			var lf: int = 0
			for r: int in JWUnits.R:
				lf += st.pop.labor_force_region_skill(r, k)
			var emp: int = 0
			for c: int in JWUnits.CELL:
				emp += st.labor.cell_employment[JWIds.idx_emp(c, k)]
			for r2: int in JWUnits.R:
				emp += st.labor.pub_employment[JWIds.idx_pubserv_emp(r2, k)]
			var un: float = 0.0 if lf <= 0 else 100.0 * (lf - emp) / lf
			line += " %s %6.1f %6.1f %5.1f%%" % [names[k], lf / 1e4, emp / 1e4, un]
		line += " ┃ %5d %5d %5d ┃ %7.1f %6.2f" % [st.pricing.wage[0], st.pricing.wage[1], st.pricing.wage[2],
				JWMath.sum(st.pop.population) / 1e4, st.diag.gdp_real / 1e9]
		print(line)
	quit(0)
