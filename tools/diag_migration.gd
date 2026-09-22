## 迁移诊断：逐季打印各相邻地区对的综合吸引力差（ppm）与阈值、实际迁移人数、被挡回人数、本季空缺。
## 用法：godot --headless --path <根> --script res://tools/diag_migration.gd -- [季数=12] [noshock]
## 只读诊断（_net_ppm 是 JWMigration 的内部函数，这里只读调用，不改状态）。
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 12
	var noshock: bool = args.size() > 1 and args[1] == "noshock"
	JWResult.trace_faults = true
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
	var thr: int = st.params[JWUnits.Param.MIGRATION_THRESHOLD_PPM]
	print("阈值 %d ppm；邻接：" % thr)
	for r1: int in JWUnits.R:
		var s: String = "  %d →" % r1
		for r2: int in JWUnits.R:
			if st.migration.adjacency[JWIds.idx_od(r1, r2)] != 0:
				s += " %d" % r2
		print(s)
	for q: int in n_q:
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		var code: int = runner.advance_quarter(cmds)
		if code != JWResult.OK:
			print("第 %d 季返回 %d" % [q, code])
			break
		var line: String = "q%-2d 空缺 %6d 迁出 %6d 挡回 %6d │ 吸引力差(ppm):" % [q, st.labor.vacancies_persons(),
				JWMath.sum(st.migration.out_by_group()), JWMath.sum(st.pop.f_migrate_rejected)]
		for r1: int in JWUnits.R:
			for r2: int in JWUnits.R:
				if r1 == r2 or st.migration.adjacency[JWIds.idx_od(r1, r2)] == 0:
					continue
				line += " %d→%d:%d/%d" % [r1, r2, st.migration._net_ppm(st.pop, st.labor, st.capital, st.pricing, r1, r2, st.params),
						_net_diff(st, r1, r2)]
		print(line)
	quit(0)


## 诊断用：推力也取「目的地 − 来源地」差值的口径（住房紧张、环境暴露），与拉力同为相对量。
func _net_diff(st: JWSimState, r1: int, r2: int) -> int:
	var m: JWMigration = st.migration
	var w_from: int = st.labor.region_wage_index(st.pricing, r1)
	var w_to: int = st.labor.region_wage_index(st.pricing, r2)
	var wage_adv: int = JWMath.clamp_i(JWMath.mul_div_floor(w_to - w_from, JWUnits.PPM, maxi(w_from, 1)), -JWUnits.PPM, JWUnits.PPM)
	var job_adv: int = m._unemp_ppm(st.pop, st.labor, r1) - m._unemp_ppm(st.pop, st.labor, r2)
	var svc_adv: int = m._service_access_ppm(st.pop, r2) - m._service_access_ppm(st.pop, r1)
	var house_d: int = m.housing_stress_ppm(st.pop, st.capital, r2) - m.housing_stress_ppm(st.pop, st.capital, r1)
	var env_d: int = m._env_exposure_ppm(st.capital, r2) - m._env_exposure_ppm(st.capital, r1)
	var p: PackedInt64Array = st.params
	return JWMath.mul_ppm(wage_adv, p[JWUnits.Param.MIGRATION_W_WAGE_PPM]) + JWMath.mul_ppm(job_adv, p[JWUnits.Param.MIGRATION_W_JOB_PPM]) 			+ JWMath.mul_ppm(svc_adv, p[JWUnits.Param.MIGRATION_W_SERVICE_PPM]) - JWMath.mul_ppm(house_d, p[JWUnits.Param.MIGRATION_W_HOUSE_PPM]) 			- JWMath.mul_ppm(env_d, p[JWUnits.Param.MIGRATION_W_ENV_PPM])
