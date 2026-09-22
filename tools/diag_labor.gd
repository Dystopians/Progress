## 劳动市场松紧度诊断：逐季打印空缺、失业、劳动力与松紧度（(空缺 − 失业) / 劳动力，ppm），以及三档工资率。
## 用法：godot --headless --path <根> --script res://tools/diag_labor.gd -- [季数=12] [种子] [noshock]
## 只读诊断。用途：R-NAIRU-01 的基年松紧度锚点取值与复核。
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 12
	var seed_v: int = int(args[1]) if args.size() > 1 else 1000000
	var noshock: bool = args.size() > 2 and args[2] == "noshock"
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
	st.rng.set_state_scalar(0, seed_v)
	if noshock:
		st.shocks.hazard_ppm.fill(0)
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	JWResult.clear_pending()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)
	print("季   空缺(万)  失业(万)  劳动力(万)  松紧度‰  失业率‰  工资·低  工资·中  工资·高")
	for q: int in n_q:
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		var code: int = runner.advance_quarter(cmds)
		if code != JWResult.OK:
			print("第 %d 季推进返回 %d，停止" % [q, code])
			break
		var v: int = st.labor.vacancies_persons()
		var u: int = st.labor.unemployed_persons()
		var lf: int = 0
		for g: int in JWUnits.GROUP:
			lf += st.pop.labor_force(g)
		var t: float = 0.0
		if lf > 0:
			t = float(v - u) * 1000.0 / float(lf)
		print("%3d %9.2f %9.2f %11.2f %8.1f %8.1f %8d %8d %8d" % [q, v / 1e4, u / 1e4, lf / 1e4, t,
				st.labor.unemployment_ppm() / 1000.0, st.pricing.wage[0], st.pricing.wage[1], st.pricing.wage[2]])
	quit(0)
