## 敏感性诊断（计划书 §14 校准第三步「改变迁移、投资和价格响应速度，查找结论是否只依赖一个脆弱参数」）。
##
## 对每个响应速度参数取 ×0.5 / ×1 / ×2 三档，各跑一局无冲击无命令基线与三条代表性干预，逐档报告：
##   基线：40 季内最大审查赤字率、最低全国支持度、期末债务、GDP 均值；
##   干预：第 8—23 季（实验 − 对照）的 GDP 与支持度均值——**关心的是符号是否翻转**，不是数值是否相等。
## 用法：godot --headless --path <根> --script res://tools/diag_sensitivity.gd -- [季数=24] [组下标]
## 只读诊断：参数改动只发生在本进程内存里，不改内容、不改代码。
extends SceneTree

const U: float = 1_000_000_000.0

## [名称, 参数下标…]：同一组内的参数一起缩放（价格的库存项恒为缺口项的一半，必须同步）。
var GROUPS: Array = [
	["迁移速度", [JWUnits.Param.MIGRATION_MAX_SHARE_PPM]],
	["投资倾向", [JWUnits.Param.INVEST_PROPENSITY_PPM]],
	["价格响应", [JWUnits.Param.PRICE_GAP_GAIN_PPM, JWUnits.Param.PRICE_COVER_GAIN_PPM]],
	["工资响应", [JWUnits.Param.WAGE_GAIN_PPM]],
]
const FACTORS: Array = [500000, 1000000, 2000000]
const SCENARIOS: Array = ["p01_up@3", "e05@0", "l04_2@0"]

var _n_q: int = 24


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_n_q = int(args[0]) if args.size() > 0 else 24
	# 第二个参数（可选）：只跑某一组（GROUPS 的下标）。
	var only: int = int(args[1]) if args.size() > 1 else -1
	print("敏感性（无冲击，%d 季；干预效应取第 8—%d 季均值，实验 − 对照）" % [_n_q, _n_q - 1])
	print("%-8s %6s │ %8s %8s %8s %8s │ %s" % ["参数组", "倍数", "最大赤字率", "最低支持", "期末债务", "GDP均值",
			"  ".join(PackedStringArray(SCENARIOS.map(func(s: String) -> String: return "%s: ΔGDP / Δ支持‰" % s)))])
	for gi: int in GROUPS.size():
		if only >= 0 and gi != only:
			continue
		var grp: Array = GROUPS[gi]
		for f: int in FACTORS:
			var base: Dictionary = _run(grp[1], f, "")
			var line: String = "%-8s %6.1f │ %8.3f %8.3f %8.1f %8.2f │" % [grp[0], f / 1e6,
					base["max_deficit"], base["min_support"], base["final_debt"], base["gdp_mean"]]
			for sc: String in SCENARIOS:
				var trt: Dictionary = _run(grp[1], f, sc)
				var eff: Vector2 = _effect(base, trt)
				line += "  %s %+6.2f / %+6.2f" % [trt.get("cmd", "?"), eff.x, eff.y]
			print(line)
	quit(0)


func _effect(base: Dictionary, trt: Dictionary) -> Vector2:
	var g0: Array = base["gdp"]
	var g1: Array = trt["gdp"]
	var s0: Array = base["support"]
	var s1: Array = trt["support"]
	var n: int = mini(g0.size(), g1.size())
	var dg: float = 0.0
	var ds: float = 0.0
	var k: int = 0
	for q: int in range(8, n):
		dg += float(g1[q]) - float(g0[q])
		ds += float(s1[q]) - float(s0[q])
		k += 1
	if k == 0:
		return Vector2.ZERO
	return Vector2(dg / k, ds / k)


func _run(pidx: Array, factor: int, scen_arg: String) -> Dictionary:
	var out: Dictionary = {"gdp": [], "support": [], "max_deficit": 0.0, "min_support": 1.0,
			"final_debt": 0.0, "gdp_mean": 0.0, "cmd": "—"}
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all("res://content", st)
	if res == null or not res.ok:
		print("载入失败")
		return out
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
	st.rng.set_state_scalar(0, 1000000)
	st.shocks.hazard_ppm.fill(0)
	for i: int in pidx:
		st.params[i] = JWMath.mul_ppm(st.params[i], factor)
	var scen: String = scen_arg.get_slice("@", 0)
	var at_q: int = int(scen_arg.get_slice("@", 1)) if scen_arg.contains("@") else -1
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	JWResult.clear_pending()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)
	var acc_rev: int = 0
	var acc_out: int = 0
	var gdp_sum: float = 0.0
	for q: int in _n_q:
		if q == at_q and scen != "":
			_submit(scen, cmds, st)
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		var code: int = runner.advance_quarter(cmds)
		if code != JWResult.OK:
			out["cmd"] = "终局@%d" % q
			break
		if q == at_q and scen != "":
			var row: int = cmds.count - 2
			out["cmd"] = "受理" if cmds.c_accepted[row] == 1 else "拒%d" % cmds.c_reject_code[row]
		var gdp: float = st.diag.gdp_production / U
		(out["gdp"] as Array).append(gdp)
		gdp_sum += gdp
		var sup: float = st.politics.support_national_ppm(st.pop) / 1e6
		(out["support"] as Array).append(sup * 1000.0)
		out["min_support"] = minf(out["min_support"], sup)
		acc_rev += st.treasury.f_receipts_income_tax + st.treasury.f_receipts_profit_tax \
				+ st.treasury.f_receipts_other
		acc_out += st.treasury.f_primary_paid + st.treasury.f_interest_paid
		if q % 4 == 3:
			out["max_deficit"] = maxf(out["max_deficit"], float(acc_out - acc_rev) / maxf(1.0, float(acc_rev)))
			acc_rev = 0
			acc_out = 0
	out["final_debt"] = st.bonds.debt_outstanding() / U
	out["gdp_mean"] = gdp_sum / maxf(1.0, float((out["gdp"] as Array).size()))
	return out


func _submit(scen: String, cmds: JWCommands, st: JWSimState) -> void:
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	if scen == "p01_up":
		# P01 第一档税率 20% → 25%（其余三格取模板默认值），预算审议季递交。
		a[0] = 0
		a[1] = 400000
		a[2] = 250000
		a[3] = 1200000
		a[4] = 250000
		cmds.submit(JWCommands.Kind.POLICY_SET_PARAMS, a, st.q, st.policy_defs)
		return
	if scen.begins_with("e") and scen.length() == 3:
		var pe: int = int(scen.substr(1)) - 1
		a[0] = pe
		for j: int in JWIds.POLICY_PARAM_STRIDE:
			a[1 + j] = st.policy_defs.param_default[JWIds.idx_policy_param(pe, j)]
		cmds.submit(JWCommands.Kind.POLICY_ENACT, a, st.q, st.policy_defs)
		return
	if scen.begins_with("l") and scen.contains("_"):
		a[0] = int(scen.substr(1, 2)) - 1
		a[1] = int(scen.get_slice("_", 1))
		a[2] = 1_000_000
		a[3] = 1
		cmds.submit(JWCommands.Kind.PROJECT_LAUNCH, a, st.q, st.policy_defs)
