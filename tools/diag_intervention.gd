## 单一干预诊断（计划书 §14 校准第二步「在固定条件下检查政策作用路径与延迟」）。
##
## 同一种子跑两局：对照组（无命令）与实验组（第 q0 季提交一条干预命令），逐季打印差值（实验 − 对照）。
## 用法：godot --headless --path <根> --script res://tools/diag_intervention.gd -- <场景[@提交季]> [季数=16] [种子] [noshock]
## 场景：
##   p01_up   个税：第一档税率 20% → 25%（policy_set_params）
##   p02_up   利润税 15% → 25%（policy_set_params）
##   p03_up   失业保障替代率 40% → 70%（policy_set_params）
##   p04      海岬电网升级项目（project_launch，规模 100%，发债）
##   p09      设备投资补助（policy_enact，全国，补助率 30%）
##   p10      基础医疗拨款（policy_enact，每季 1.2 亿 μU）
## 只读诊断：不改内容、不改代码；冲击可用 noshock 关掉以隔离政策效应。
extends SceneTree

const U: float = 1_000_000_000.0

var _at_q: int = 0


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scen_arg: String = args[0] if args.size() > 0 else "p02_up@3"
	# 「场景@季」：在第几季提交（税制类须在预算审议季 q ≡ 3 (mod 4) 提出，R-WINDOW-01）。
	var scen: String = scen_arg.get_slice("@", 0)
	_at_q = int(scen_arg.get_slice("@", 1)) if scen_arg.contains("@") else 0
	var n_q: int = int(args[1]) if args.size() > 1 else 16
	var seed_v: int = int(args[2]) if args.size() > 2 else 1000000
	var noshock: bool = args.size() > 3 and args[3] == "noshock"
	var ctl: Dictionary = _run("", n_q, seed_v, noshock)
	var trt: Dictionary = _run(scen, n_q, seed_v, noshock)
	print("场景 %s（%d 季，种子 %d%s）：实验 − 对照" % [scen, n_q, seed_v, "，无冲击" if noshock else ""])
	print("  命令结果：%s" % str(trt.get("cmd", "")))
	var keys: PackedStringArray = PackedStringArray(["GDP", "C", "I", "G", "就业(万)", "失业率‰", "个税", "利润税",
			"非税", "基本支出", "　公职工资", "　法定转移", "　政府采购", "　公服运营", "　补贴", "利息", "新增借款", "征收能力‰", "行政能力‰", "技能·中高(万)", "债务", "国库现金", "支持度‰", "生活‰", "服务可及‰",
			"能源产量", "制造产量", "电网供电", "价格·能源‰", "价格·制造‰"])
	var line: String = "%-10s" % "季"
	for q: int in n_q:
		line += "%8d" % q
	print(line)
	for k: String in keys:
		var a: Array = ctl.get(k, [])
		var b: Array = trt.get(k, [])
		line = "%-10s" % k
		for q: int in mini(a.size(), b.size()):
			var d: float = float(b[q]) - float(a[q])
			line += "%8.2f" % d if absf(d) < 1000.0 else "%8.0f" % d
		print(line)
	quit(0)


func _run(scen: String, n_q: int, seed_v: int, noshock: bool) -> Dictionary:
	var out: Dictionary = {}
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all("res://content", st)
	if res == null or not res.ok:
		print("载入失败")
		return out
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
	for q: int in n_q:
		if q == _at_q and scen != "":
			var rs: JWResult = _submit(scen, cmds, st)
			out["cmd"] = "受理" if (rs != null and rs.ok) else "拒绝 %d" % (0 if rs == null else rs.code)
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		var code: int = runner.advance_quarter(cmds)
		if code != JWResult.OK:
			print("  %s 第 %d 季返回 %d，停止" % ["对照" if scen == "" else scen, q, code])
			break
		if q == _at_q and scen != "":
			# S02 才真正受理：读命令行的受理位与拒绝码。
			var row: int = cmds.count - 2
			if row >= 0:
				out["cmd"] = "受理" if cmds.c_accepted[row] == 1 else "拒绝 %d" % cmds.c_reject_code[row]
		_collect(st, out)
	return out


func _submit(scen: String, cmds: JWCommands, st: JWSimState) -> JWResult:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	if scen == "p01_up":
		# P01 槽位：0 第二档税率、1 免征额、2 第二档起点、3 第一档税率（treasury.P01_SLOT_*）。
		a[0] = 0
		a[1] = 400000
		a[2] = 250000
		a[3] = 1200000
		a[4] = 250000
		return cmds.submit(JWCommands.Kind.POLICY_SET_PARAMS, a, st.q, st.policy_defs)
	if scen == "p02_up":
		a[0] = 1
		a[1] = 250000
		a[2] = 1
		return cmds.submit(JWCommands.Kind.POLICY_SET_PARAMS, a, st.q, st.policy_defs)
	if scen == "p03_up":
		a[0] = 2
		a[1] = 700000
		a[2] = 4
		a[3] = 1
		a[4] = 15
		return cmds.submit(JWCommands.Kind.POLICY_SET_PARAMS, a, st.q, st.policy_defs)
	if scen == "p04":
		a[0] = 3
		a[1] = JWUnits.Region.HAIJIA
		a[2] = 1_000_000
		a[3] = 1
		return cmds.submit(JWCommands.Kind.PROJECT_LAUNCH, a, st.q, st.policy_defs)
	if scen == "p09":
		a[0] = 8
		a[1] = 15
		a[2] = 10000
		a[3] = 300000
		a[4] = 60000000
		a[5] = 0
		return cmds.submit(JWCommands.Kind.POLICY_ENACT, a, st.q, st.policy_defs)
	if scen == "p10":
		a[0] = 9
		a[1] = 15
		a[2] = 120000000
		a[3] = 1000000
		a[4] = 2
		a[5] = 0
		return cmds.submit(JWCommands.Kind.POLICY_ENACT, a, st.q, st.policy_defs)
	# 通用：eNN == 以模板默认参数通过政策 NN（policy_enact，资金来源 0）；
	#       lNN_r == 在地区 r 以满规模立项政策 NN（project_launch，发债）。
	if scen.begins_with("e") and scen.length() == 3:
		var pe: int = int(scen.substr(1)) - 1
		a[0] = pe
		for j: int in JWIds.POLICY_PARAM_STRIDE:
			a[1 + j] = st.policy_defs.param_default[JWIds.idx_policy_param(pe, j)]
		a[5] = 0
		return cmds.submit(JWCommands.Kind.POLICY_ENACT, a, st.q, st.policy_defs)
	if scen.begins_with("l") and scen.contains("_"):
		var pl: int = int(scen.substr(1, 2)) - 1
		a[0] = pl
		a[1] = int(scen.get_slice("_", 1))
		a[2] = 1_000_000
		a[3] = 1
		return cmds.submit(JWCommands.Kind.PROJECT_LAUNCH, a, st.q, st.policy_defs)
	print("未知场景 %s" % scen)
	return null


func _collect(st: JWSimState, out: Dictionary) -> void:
	var e: PackedInt64Array = st.diag._agg_exp
	var g_out: int = 0
	for r: int in JWUnits.PUBSERV:
		g_out += st.capital.f_pub_output[r]
	_p(out, "GDP", st.diag.gdp_production / U)
	_p(out, "C", e[JWUnits.ExpClass.C] / U)
	_p(out, "I", e[JWUnits.ExpClass.I] / U)
	_p(out, "G", g_out / U)
	var emp: int = JWMath.sum(st.labor.cell_employment) + JWMath.sum(st.labor.pub_employment)
	_p(out, "就业(万)", emp / 10000.0)
	_p(out, "失业率‰", st.labor.unemployment_ppm() / 1000.0)
	_p(out, "个税", st.treasury.f_receipts_income_tax / U)
	_p(out, "利润税", st.treasury.f_receipts_profit_tax / U)
	_p(out, "非税", st.treasury.f_receipts_other / U)
	_p(out, "基本支出", st.treasury.f_primary_paid / U)
	_p(out, "　公职工资", st.treasury.f_pay_public_wages / U)
	_p(out, "　法定转移", JWMath.sum(st.treasury.f_pay_transfers) / U)
	_p(out, "　政府采购", st.treasury.f_pay_procurement / U)
	_p(out, "　公服运营", JWMath.sum(st.treasury.f_pay_opex) / U)
	_p(out, "　补贴", JWMath.sum(st.treasury.f_pay_subsidies) / U)
	_p(out, "新增借款", st.treasury.f_new_borrowing / U)
	_p(out, "征收能力‰", st.treasury.tax_capacity_ppm / 1000.0)
	_p(out, "行政能力‰", st.politics.admin_capacity_ppm / 1000.0)
	var hi: int = 0
	for g: int in JWUnits.GROUP:
		if JWIds.SKILL_OF_GROUP[g] >= 1 and JWIds.age_of_group(g) == JWUnits.Age.WORKING:
			hi += st.pop.population[g]
	_p(out, "技能·中高(万)", hi / 10000.0)
	_p(out, "利息", st.treasury.f_interest_paid / U)
	_p(out, "债务", st.bonds.debt_outstanding() / U)
	_p(out, "国库现金", st.accounts.cash_of(JWIds.AGENT_GOV) / U)
	_p(out, "支持度‰", st.politics.support_national_ppm(st.pop) / 1000.0)
	var li: int = 0
	var sa: int = 0
	for g: int in JWUnits.GROUP:
		li += st.politics.living_index[g]
		for k: int in JWUnits.SERVICE_KIND:
			sa += st.pop.service_access[JWIds.idx_group_svc(g, k)]
	_p(out, "生活‰", li / JWUnits.GROUP / 1000.0)
	_p(out, "服务可及‰", sa / (JWUnits.GROUP * JWUnits.SERVICE_KIND) / 1000.0)
	var e_out: int = 0
	var m_out: int = 0
	for r2: int in JWUnits.R:
		e_out += st.sectors.f_output_actual[JWIds.idx_cell(r2, JWUnits.Sector.ENERGY)]
		m_out += st.sectors.f_output_actual[JWIds.idx_cell(r2, JWUnits.Sector.MANU)]
	_p(out, "能源产量", e_out / 1e6)
	_p(out, "制造产量", m_out / 1e6)
	var sup: int = 0
	for r3: int in JWUnits.R:
		sup += st.sectors.f_elec_supply[r3]
	_p(out, "电网供电", sup / 1e6)
	_p(out, "价格·能源‰", st.pricing.price_of(JWUnits.Sector.ENERGY) / 1e6)
	_p(out, "价格·制造‰", st.pricing.price_of(JWUnits.Sector.MANU) / 1e6)


func _p(out: Dictionary, k: String, v: float) -> void:
	if not out.has(k):
		out[k] = []
	(out[k] as Array).append(v)
