## P09 补助诊断：第 0 季通过 P09（全国、门槛 1%、补助率 30%、每 cell 封顶 0.06 U），逐季打印资格链各环。
## 用法：godot --headless --path <根> --script res://tools/diag_p09.gd -- [季数=6]
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 6
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
	st.shocks.hazard_ppm.fill(0)
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	JWResult.clear_pending()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)
	var p: int = 8
	print("槽位：mask %d rate %d cap %d min_ratio %d；部门掩码 %d；封顶 %d" % [st.policy_defs.mask_slot[p],
			st.policy_defs.rate_slot[p], st.policy_defs.cap_slot[p], st.policy_defs.min_ratio_slot[p],
			st.params[JWUnits.Param.P09_ELIGIBLE_SECTOR_MASK], st.policy_defs.spend_line(p, 0)])
	for q: int in n_q:
		if q == 0:
			var a: PackedInt64Array = PackedInt64Array()
			a.resize(JWCommands.ARG_SLOTS)
			a.fill(0)
			a[0] = p
			a[1] = 15
			a[2] = 10000
			a[3] = 300000
			a[4] = 60000000
			var r0: JWResult = cmds.submit(JWCommands.Kind.POLICY_ENACT, a, st.q, st.policy_defs)
			print("递交：%s" % ("ok" if r0 == null or r0.ok else str(r0.code)))
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		var code: int = runner.advance_quarter(cmds)
		if code != JWResult.OK:
			print("第 %d 季返回 %d" % [q, code])
			break
		if q == 0:
			var row: int = cmds.count - 2
			print("受理 %d 拒绝码 %d" % [cmds.c_accepted[row], cmds.c_reject_code[row]])
		var sub: int = JWMath.sum(st.treasury.f_pay_subsidies)
		var line: String = "q%d 生效 %d(from %d) 区域掩码 %d 参数[%d,%d,%d,%d] 承诺 %d 已付 %d 本季补助 %d │ 投资(manu,energy)×地区:" % [q,
				1 if st.policy.is_effective(p, q) else 0, st.policy.effective_from_q[p], st.policy.region_mask[p],
				st.policy.params_ppm[p * 4], st.policy.params_ppm[p * 4 + 1], st.policy.params_ppm[p * 4 + 2],
				st.policy.params_uu[p * 4 + 3], st.policy.budget_committed[p], st.policy.budget_spent[p], sub]
		for r: int in JWUnits.R:
			for s: int in [JWUnits.Sector.MANU, JWUnits.Sector.ENERGY]:
				var c: int = JWIds.idx_cell(r, s)
				line += " %.3f/%.2f" % [st.capital.f_cell_investment[c] / 1e9, st.capital.cell_capital_value[c] / 1e9]
		print(line)
	quit(0)
