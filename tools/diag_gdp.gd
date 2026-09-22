## 诊断：跑到第一次故障（或 N 季），打印三口径 GDP 的全部分项。
extends SceneTree


func _init() -> void:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	loader.load_all("res://content", st)
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
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
	var code: int = runner.advance_quarter(cmds)
	var d: JWDiagnostics = st.diag
	print("code=%d" % code)
	var e: PackedInt64Array = d._agg_exp
	var p: PackedInt64Array = d._agg_prod
	print("账本支出类 C=%s G(账本)=%s I=%s DINV=%s X=%s M=%s" % [_u(e[1]), _u(e[2]), _u(e[3]), _u(e[4]), _u(e[5]), _u(e[6])])
	print("账本生产类 终售=%s 中间售=%s 存货变动=%s 非市场VA=%s" % [_u(p[1]), _u(p[2]), _u(p[3]), _u(p[4])])
	var g_uu: int = 0
	var pub_va: int = 0
	for r: int in JWUnits.PUBSERV:
		g_uu += st.capital.f_pub_output[r]
		pub_va += st.capital.f_pub_output[r] - st.inventory.f_pub_intermediate[r]
	var va: int = 0
	var out_v: int = 0
	for c: int in JWUnits.CELL:
		va += st.sectors.value_added(c)
	print("G(公共产出)=%s 公共VA=%s 市场VA合计=%s 价差=%s" % [_u(g_uu), _u(pub_va), _u(va), _u(st.inventory.price_variance_total())])
	print("世界 X=%s M=%s" % [_u(st.world.f_exports_uu), _u(st.world.f_imports_uu)])
	print("gdp_production=%s gdp_expenditure=%s" % [_u(d.gdp_production), _u(d.gdp_expenditure)])
	print("cell | 销售额 | 总产出 | 中间 | 增加值 | 购电Q | 已耗用(基) | 价差")
	for c: int in JWUnits.CELL:
		print("%2d | %s | %s | %s | %s | %s | %s | %s" % [c, _u(st.sectors._sales_rev[c]),
				_u(st.sectors.f_gross_output[c]), _u(st.sectors.f_intermediate[c]),
				_u(st.sectors.value_added(c)), _u(st.sectors._elec_bought_qty[c] * 1000),
				_u(st.inventory.used_total(c) * 1000), _u(st.inventory.f_price_variance[c])])
	quit(0)


func _u(v: int) -> String:
	return "%.3f" % (float(v) / 1_000_000_000.0)
