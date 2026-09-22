## 长局诊断（docs/53 M1-3 / M1-9）：无命令推进 N 季，每 `step` 季打印一行价格、工资、GDP、人口、货币与财政。
## 政治终局在 M1-6/M1-7 之前仍按旧规则触发；本诊断用 `force` 参数把终局标志清掉继续跑（只改本进程，用来观察经济长期路径）。
##
## 用法：godot --headless --path . --script res://tools/diag_long.gd -- [剧本=campaign_1600] [季数=400] [步=20] [种子=1] [force]
extends SceneTree

const U: float = 1_000_000_000.0


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scen: String = args[0] if args.size() > 0 else "campaign_1600"
	var n_q: int = int(args[1]) if args.size() > 1 else 400
	var step: int = int(args[2]) if args.size() > 2 else 20
	var seed_v: int = int(args[3]) if args.size() > 3 else 1
	var force: bool = args.has("force")
	# nofinal：把危机的最后补救窗口设为无穷长（只改本进程），用来测 1600 季的数值尺度与性能，不是经济结论。
	var nofinal: bool = args.has("nofinal")
	JWResult.trace_faults = args.has("trace")

	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var spec: String = "res://content" if scen == "chengwan" else "res://content#" + scen
	var res: JWResult = loader.load_all(spec, st)
	if res == null or not res.ok:
		print("载入失败：", res.code if res else -1)
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
	if nofinal:
		st.crisis.final_window_q = 1 << 40
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)

	print("季   价格(农 工 能 服, ×基年)      工资(低 中 高, μU)    名义GDP/季 实际GDP/季  人口(百万) 失业%  现金总量  政府债务  撞界 水平 累计发行")
	var t0: int = Time.get_ticks_msec()
	var bound_hits: int = 0
	for q: int in n_q:
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		var code: int = runner.advance_quarter(cmds)
		if code != 0:
			print("第 %d 季推进失败：码 %d（终局 %s，原因 %d）" % [q, code, str(st.politics.run_terminated),
					st.politics.termination_reason])
			if force and st.politics.run_terminated:
				st.politics.run_terminated = false
				JWResult.clear_pending()
				continue
			break
		for s: int in JWUnits.S:
			var p: int = st.pricing.price[s]
			if p <= JWUnits.PRICE_MIN or p >= JWUnits.PRICE_MAX:
				bound_hits += 1
		if q % step == step - 1 or q == n_q - 1:
			var pr: String = ""
			for s2: int in JWUnits.S:
				pr += "%5.2f " % (st.pricing.price[s2] / U)
			var wg: String = ""
			for k: int in JWUnits.K:
				wg += "%7.0f " % float(st.pricing.wage[k])
			var cash: int = 0
			for a: int in JWUnits.AGENT_N:
				cash += st.accounts.cash_of(a)
			var pop: int = JWMath.sum(st.pop.population)
			var debt: int = 0
			for b: int in st.bonds.principal_outstanding.size():
				debt += st.bonds.principal_outstanding[b]
			var line: String = "%4d %s  %s  %9.2f %9.2f  %7.2f %5.1f  %8.2f %8.2f  %d" % [q + 1, pr, wg,
					st.diag.gdp_production / U, st.diag.gdp_real / U, pop / 1e6,
					st.diag.unemployment_ppm / 1e4, cash / U, debt / U, bound_hits]
			line += "  %.3f %.2f" % [st.money.price_level_ppm / 1e6, st.money.issued_total / U]
			line += "  危机%s 更替%d 席%d" % [str(st.crisis.stage), st.crisis.gov_changes, st.politics.seats_gov]
			print(line)
			if args.has("cap"):
				var cs: String = "     产能/产出/投资(按部门)："
				for s3: int in JWUnits.S:
					var capv: int = 0
					var outv: int = 0
					var inv: int = 0
					for r3: int in JWUnits.R:
						var c3: int = JWIds.idx_cell(r3, s3)
						capv += st.capital.cell_capacity_active[c3]
						outv += st.sectors.f_output_actual[c3]
						inv += st.capital.f_cell_investment[c3]
					cs += " [%.2f/%.2f/%.3f]" % [capv / 1e6, outv / 1e6, inv / U]
				print(cs)
				var cg: int = st.accounts.cash_of(JWIds.AGENT_GOV)
				var cc: int = 0
				for c4: int in JWUnits.CELL:
					cc += st.accounts.cash_of(JWIds.agent_of_cell(c4))
				var cgr: int = 0
				for g4: int in JWUnits.GROUP:
					cgr += st.accounts.cash_of(JWIds.agent_of_group(g4))
				var dep: int = 0
				for g5: int in JWUnits.GROUP:
					dep += st.accounts.get_balance(JWIds.idx_account(JWIds.agent_of_group(g5), JWIds.ACC_DEPOSIT_CLAIM))
				print("     现金：政府 %.2f 企业 %.2f 居民 %.2f 投资池 %.2f 外部 %.2f ｜ 居民存款 %.2f 欠付 %.2f" % [cg / U, cc / U, cgr / U,
						st.accounts.cash_of(JWIds.AGENT_INVPOOL) / U, st.accounts.cash_of(JWIds.AGENT_ROW) / U, dep / U,
						st.treasury.arrears / U])
	print("耗时 %d ms（%d 季）" % [Time.get_ticks_msec() - t0, n_q])
	quit()
