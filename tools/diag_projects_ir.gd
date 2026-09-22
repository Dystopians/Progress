## 诊断：docs/18 第三轮裁定（R-WINDOW-01 / R-PROJECT-01 / R-ASSET-01 / R-PUBSERV-01）落地后的**真实路径**核对。
##
## 不再模拟任何接口请求：八步结算、账本、内容包与出厂构建完全相同（原先的 IR-1/IR-2/IR-6 模拟子类已撤掉——
## start()、四腿项目付款、进口登记与销售归集现在都在正式代码里，再模拟一遍就是重复计入）。
## 每个场景打印 PASS / FAIL，末行给出失败合计。故障登记打开 trace_faults。
## 用法：godot --headless --path <根> --script res://tools/diag_projects_ir.gd -- <场景|all>
## 场景：
##   pay        R-PROJECT-01 ①②③：四腿付款、wip == Σpaid、政府净值不因付款下降、设备线计进口、国内线计销售、GDP 恒等
##   toggle     R-PUBSERV-01：开关成本付中州服务 cell、计中州 pubserv 中间消耗；两组对照 GDP 之差 == 开关成本；pubserv 现金恒 0
##   opex       R-PUBSERV-01：运行费只定额度不过账（无 kind 20 行），S05 公共服务买方类按额度成交；不足时 funding_ratio < 1e6
##   commission R-ASSET-01：小规模 P04 完工投运，ASSET_RECLASS 两腿结转 wip → 政府资本，净值不变
##   scale      R-PROJECT-01 ⑤：scale_ppm 同倍缩放合同；0 与退化规模 → E_PARAM_RANGE
##   resume     R-PROJECT-01 ⑤：S02 把挂起项目复工
##   window     R-WINDOW-01：审查窗口前移；P01 非审查季被拒、审查季受理；P09 任意季受理
##   f01 / f06  取消量法（docs/18 第三轮「测试口径更正」）
##   memo       INV-032 三个变动点（T-U-D-08），经真实 pay_line
##   repeal2    P09 开 → 关 → 再开 → 再关：每次撤销只释放本次开启签入的承诺（ADV-A01 第二次撤销的码 22）
extends SceneTree

const P01: int = 0
const P04: int = 3
const P09: int = 8
const HAIJIA: int = 2
const ZHONGZHOU: int = 1


class Rig extends RefCounted:
	var st: JWSimState = null
	var cmds: JWCommands = null
	var runner: JWTurnRunner = null
	var alive: bool = true
	var last_rc: int = 0

	func boot() -> bool:
		st = JWSimState.new()
		st.allocate_all()
		st.horizon_q = 40
		var loader: JWContentLoader = JWContentLoader.new()
		var res: JWResult = loader.load_all("res://content", st)
		if res == null or not res.ok:
			print("load_all 失败")
			return false
		st.build_id = JWGame.BUILD_ID
		st.content_hash = loader.content_hash
		st.param_set_version = loader.param_set_version
		st.rng.set_state_scalar(0, 1)
		cmds = JWCommands.new()
		cmds.allocate()
		var ev: JWEventEngine = JWEventEngine.new()
		ev.allocate()
		JWResult.clear_pending()
		if st.check_all_p0() != JWResult.OK:
			print("开局 P0 失败 %d" % JWResult.pending_code())
			return false
		runner = JWTurnRunner.new(st, ev)
		return true

	func submit(kind: int, a: PackedInt64Array) -> int:
		var r: JWResult = cmds.submit(kind, a, st.q, st.policy_defs)
		return 0 if (r == null or r.ok) else r.code

	func advance(n: int, tag: String) -> void:
		var i: int = 0
		while i < n and alive:
			var q0: int = st.q
			submit(99, PackedInt64Array([0, 0, 0, 0, 0, 0]))
			var rc: int = runner.advance_quarter(cmds)
			last_rc = rc
			if rc != JWResult.OK or JWResult.has_pending():
				print("  [%s] q=%d 推进失败 rc=%d pending=%d@S%d 终止=%s/%d" % [tag, q0, rc,
						JWResult.pending_code(), JWResult.pending_step(),
						str(st.politics.run_terminated), st.politics.termination_reason])
				alive = false
				return
			i += 1

	## 本季（刚推进完的那一季）账本：某 kind 在某科目上的有符号 Σ。
	func leg_sum(kind: int, account: int) -> int:
		var acc: int = 0
		for i: int in st.ledger.log_row_count():
			if st.ledger.l_kind[i] == kind and st.ledger.l_account[i] == account:
				acc += st.ledger.l_delta[i]
		return acc

	## 本季某 kind 的 txn 数与行数。
	func txn_rows(kind: int) -> Vector2i:
		var txns: Dictionary = {}
		var rows: int = 0
		for i: int in st.ledger.log_row_count():
			if st.ledger.l_kind[i] == kind:
				rows += 1
				txns[st.ledger.l_txn[i]] = true
		return Vector2i(txns.size(), rows)

	## 本季某 kind 的全部行在某主体非净值科目上的有符号 Σ（== 该类分录对该主体净值的效果，INV-020 逐笔成立）。
	func nw_effect(kind: int, agent: int) -> int:
		var nw: int = JWIds.idx_account(agent, JWIds.ACC_NW)
		var acc: int = 0
		for i: int in st.ledger.log_row_count():
			var a: int = st.ledger.l_account[i]
			if st.ledger.l_kind[i] == kind and JWMath.floor_div(a, JWUnits.ACCOUNT_CODE_N) == agent \
					and a != nw:
				acc += st.ledger.l_delta[i]
		return acc

	func paid(p: int) -> int:
		return st.projects.paid[p * 3] + st.projects.paid[p * 3 + 1] + st.projects.paid[p * 3 + 2]

	func gov(code: int) -> int:
		return st.accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, code))

	func pub_cash_total() -> int:
		var s: int = 0
		for r: int in JWUnits.PUBSERV:
			s += absi(st.accounts.cash_of(JWIds.agent_of_pubserv(r)))
		return s

	func gdp_ok() -> bool:
		return st.diag.gdp_expenditure == st.diag.gdp_production + st.diag.price_variance_total \
				and st.diag.gdp_income == st.diag.gdp_production


var _fails: int = 0


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var which: String = args[0] if args.size() > 0 else "all"
	JWResult.trace_faults = true
	var all: bool = which == "all"
	if all or which == "pay":
		_pay()
	if all or which == "toggle":
		_toggle()
	if all or which == "opex":
		_opex()
	if all or which == "commission":
		_commission()
	if all or which == "scale":
		_scale()
	if all or which == "resume":
		_resume()
	if all or which == "window":
		_window()
	if all or which == "f01":
		_f01()
	if all or which == "f06":
		_f06()
	if all or which == "memo":
		_memo()
	if all or which == "repeal2":
		_repeal_twice()
	print("== 断言失败合计 %d ==" % _fails)
	quit(0)


func _a6(s0: int = 0, s1: int = 0, s2: int = 0, s3: int = 0, s4: int = 0,
		s5: int = 0) -> PackedInt64Array:
	return PackedInt64Array([s0, s1, s2, s3, s4, s5])


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("    PASS " + msg)
	else:
		_fails += 1
		print("    FAIL " + msg)


func _new() -> Rig:
	JWResult.clear_pending()
	var g: Rig = Rig.new()
	if not g.boot():
		return null
	return g


func _quarter_close(g: Rig, tag: String) -> void:
	_check(g.gdp_ok(), "%s GDP 三法恒等（支出 %d == 生产 %d + 价差 %d；收入 %d）" % [tag,
			g.st.diag.gdp_expenditure, g.st.diag.gdp_production, g.st.diag.price_variance_total,
			g.st.diag.gdp_income])
	_check(g.st.accounts.check_cash_closure(g.st.cash_expected(), g.st.cash_expected()) == JWResult.OK,
			"%s 现金闭合（含 pubserv 现金 == 0）" % tag)
	_check(g.pub_cash_total() == 0, "%s 四个 pubserv 现金户全为 0" % tag)
	_check(g.st.accounts.check_balance_sheet() == JWResult.OK, "%s INV-020 逐主体恒等" % tag)
	JWResult.clear_pending()


# ── R-PROJECT-01 ①②③ ─────────────────────────────────────────────────────

func _pay() -> void:
	print("── R-PROJECT-01 四腿付款 / wip / 进口 / 销售 ──")
	var g: Rig = _new()
	if g == null:
		return
	_check(g.submit(4, _a6(P04, HAIJIA, JWUnits.PPM, 1)) == 0, "立项命令受理")
	var q: int = 0
	var paid_prev: int = 0
	while q < 3 and g.alive:
		var wip0: int = g.gov(JWIds.ACC_WIP)
		var m0: int = 0
		g.advance(1, "pay")
		if not g.alive:
			return
		var pid: int = 0
		var paid_now: int = g.paid(pid)
		var d_paid: int = paid_now - paid_prev
		var row_cash: int = JWIds.idx_account(JWIds.AGENT_ROW, JWIds.ACC_CASH)
		var eqp_to_row: int = g.leg_sum(JWUnits.Kind.PROJECT_PAYMENT, row_cash)
		var tr: Vector2i = g.txn_rows(JWUnits.Kind.PROJECT_PAYMENT)
		print("    q%d status=%d Δpaid=%d Δwip=%d 付 row=%d kind19 txn=%d 行=%d 进口额=%d" % [q,
				g.st.projects.status[pid], d_paid, g.gov(JWIds.ACC_WIP) - wip0, eqp_to_row, tr.x, tr.y,
				g.st.world.f_imports_uu - m0])
		_check(tr.y == 4 * tr.x, "q%d 项目付款每笔恰为四腿（%d 笔 %d 行）" % [q, tr.x, tr.y])
		_check(g.gov(JWIds.ACC_WIP) - wip0 == d_paid, "q%d 政府 wip 增量 == 本季实付 %d" % [q, d_paid])
		_check(g.leg_sum(JWUnits.Kind.PROJECT_PAYMENT, JWIds.idx_account(JWIds.AGENT_GOV,
				JWIds.ACC_WIP)) == d_paid, "q%d kind19 在政府 wip 科目上的腿之和 == 实付" % q)
		_check(g.nw_effect(JWUnits.Kind.PROJECT_PAYMENT, JWIds.AGENT_GOV) == 0,
				"q%d 项目付款对政府净值的效果 == 0（现金换在建工程）" % q)
		_check(g.st.treasury.f_pay_project[pid] == d_paid, "q%d flow.gov.pay_project_uu[p] == 实付" % q)
		# 设备线付给 row 的金额必须同额计入进口（本季进口额里还含市场进口，故只能下界比较）。
		_check(g.st.world.f_imports_uu >= eqp_to_row and eqp_to_row > 0,
				"q%d 设备线付 row %d 已计入进口（本季进口额 %d）" % [q, eqp_to_row, g.st.world.f_imports_uu])
		_quarter_close(g, "q%d" % q)
		paid_prev = paid_now
		q += 1
	# 精确核对：进口额里项目设备那一份。对照组不立项，其余一切相同。
	var c: Rig = _new()
	if c == null:
		return
	var t: Rig = _new()
	if t == null:
		return
	t.submit(4, _a6(P04, HAIJIA, JWUnits.PPM, 1))
	c.advance(1, "pay-ctrl")
	t.advance(1, "pay-trt")
	if not c.alive or not t.alive:
		return
	var row_cash2: int = JWIds.idx_account(JWIds.AGENT_ROW, JWIds.ACC_CASH)
	var eqp: int = t.leg_sum(JWUnits.Kind.PROJECT_PAYMENT, row_cash2)
	var dom: int = t.leg_sum(JWUnits.Kind.PROJECT_PAYMENT, JWIds.idx_account(JWIds.agent_of_cell(
			JWIds.idx_cell(HAIJIA, JWUnits.Sector.MANU)), JWIds.ACC_CASH)) \
			+ t.leg_sum(JWUnits.Kind.PROJECT_PAYMENT, JWIds.idx_account(JWIds.agent_of_cell(
			JWIds.idx_cell(HAIJIA, JWUnits.Sector.SERVICES)), JWIds.ACC_CASH))
	print("    q0 对照：设备 %d 国内 %d ΔM=%d ΔI(账本 I 类)=%d ΔGDP=%d" % [eqp, dom,
			t.st.world.f_imports_uu - c.st.world.f_imports_uu, _class(t, JWUnits.ExpClass.I)
			- _class(c, JWUnits.ExpClass.I), t.st.diag.gdp_production - c.st.diag.gdp_production])
	_check(t.st.world.f_imports_uu - c.st.world.f_imports_uu == eqp, "q0 ΔM == 设备线实付（同季两组其余进口相同）")
	_check(_class(t, JWUnits.ExpClass.I) - _class(c, JWUnits.ExpClass.I) == eqp + dom,
			"q0 ΔI == 本季项目付款总额")
	_check(t.st.diag.gdp_production - c.st.diag.gdp_production == dom,
			"q0 ΔGDP == 国内承包方收款（设备线 I 与 M 相抵）")


func _class(g: Rig, exp_class: int) -> int:
	var prod: PackedInt64Array = PackedInt64Array()
	prod.resize(8)
	var ex: PackedInt64Array = PackedInt64Array()
	ex.resize(8)
	var inc: PackedInt64Array = PackedInt64Array()
	inc.resize(8)
	g.st.ledger.aggregate_classes(prod, ex, inc)
	return ex[exp_class]


# ── R-PUBSERV-01：开关成本 ─────────────────────────────────────────────────

func _toggle() -> void:
	print("── R-PUBSERV-01 开关成本 → 中州服务 cell ──")
	var c: Rig = _new()
	var t: Rig = _new()
	if c == null or t == null:
		return
	var enact: PackedInt64Array = _a6(P09, 15, 10_000, 500_000, 60_000_000, 0)
	_check(t.submit(1, enact) == 0, "P09 开启命令形状合法")
	c.advance(1, "toggle-ctrl")
	t.advance(1, "toggle-trt")
	if not c.alive or not t.alive:
		return
	var zz_svc: int = JWIds.agent_of_cell(JWIds.idx_cell(ZHONGZHOU, JWUnits.Sector.SERVICES))
	var cost: int = t.leg_sum(JWUnits.Kind.POLICY_TOGGLE_COST, JWIds.idx_account(zz_svc, JWIds.ACC_CASH))
	var gov_out: int = -t.leg_sum(JWUnits.Kind.POLICY_TOGGLE_COST,
			JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH))
	var d_pub_ic: int = t.st.inventory.f_pub_intermediate[ZHONGZHOU] \
			- c.st.inventory.f_pub_intermediate[ZHONGZHOU]
	var d_prod: int = t.st.diag.gdp_production - c.st.diag.gdp_production
	var d_exp: int = t.st.diag.gdp_expenditure - c.st.diag.gdp_expenditure
	print("    P09 enabled=%d 开关成本→中州服务 %d 政府付出 %d Δ中州 pubserv 中间消耗 %d ΔGDP 生产 %d 支出 %d" % [
			t.st.policy.enabled[P09], cost, gov_out, d_pub_ic, d_prod, d_exp])
	_check(t.st.policy.enabled[P09] == 1, "P09 在 q0 受理（R-WINDOW-01：P09 不受立法窗口约束）")
	_check(cost == 10_000_000 and gov_out == cost, "开关成本 1e7 全额付给中州服务 cell")
	var pub_rows: int = 0
	for i: int in t.st.ledger.log_row_count():
		var a: int = t.st.ledger.l_account[i]
		var ag: int = JWMath.floor_div(a, JWUnits.ACCOUNT_CODE_N)
		if ag >= JWIds.AGENT_PUBSERV_BASE and ag < JWIds.AGENT_GROUP_BASE \
				and a % JWUnits.ACCOUNT_CODE_N == JWIds.ACC_CASH:
			pub_rows += 1
	_check(pub_rows == 0, "本季没有任何分录触碰 pubserv 现金户（%d 行）" % pub_rows)
	_check(d_pub_ic == cost, "中州 pubserv 中间消耗恰增开关成本（%d）" % d_pub_ic)
	_check(d_prod == cost and d_exp == cost, "两组 GDP（生产 / 支出）之差都恰等于开关成本")
	_quarter_close(t, "trt q0")
	_quarter_close(c, "ctrl q0")
	# 撤销：冷却过后撤销，开关成本与违约金同样付给中州服务 cell。
	t.advance(3, "toggle-trt")
	if not t.alive:
		return
	_check(t.submit(3, _a6(P09)) == 0, "q4 撤销命令形状合法（冷却 4 季已过）")
	t.advance(1, "toggle-trt")
	if not t.alive:
		return
	var cost2: int = t.leg_sum(JWUnits.Kind.POLICY_TOGGLE_COST, JWIds.idx_account(zz_svc, JWIds.ACC_CASH))
	var pen2: int = t.leg_sum(JWUnits.Kind.CANCEL_PENALTY, JWIds.idx_account(zz_svc, JWIds.ACC_CASH))
	print("    q4 撤销：P09 enabled=%d 开关成本→中州服务 %d 违约金→中州服务 %d 欠付 %d" % [
			t.st.policy.enabled[P09], cost2, pen2, t.st.treasury.arrears])
	_check(t.st.policy.enabled[P09] == 0, "q4 撤销受理")
	_check(cost2 == 10_000_000 or t.st.treasury.arrears_by_payee[zz_svc] > 0,
			"撤销的开关成本付给中州服务 cell（付不起则挂在它名下欠付）")
	_quarter_close(t, "trt q4")


# ── R-PUBSERV-01：运行费 ───────────────────────────────────────────────────

func _opex() -> void:
	print("── R-PUBSERV-01 运行费只定额度、S05 市场成交 ──")
	for committed: int in [40_000_000, 60_000_000_000]:
		var g: Rig = _new()
		if g == null:
			return
		g.st.treasury.service_opex_committed = committed
		g.advance(1, "opex")
		if not g.alive:
			continue
		var tr20: Vector2i = g.txn_rows(JWUnits.Kind.SERVICE_OPEX)
		var grant: int = JWMath.sum(g.st.treasury.f_pay_opex)
		var pub_ic: int = JWMath.sum(g.st.inventory.f_pub_intermediate)
		var min_ratio: int = JWUnits.PPM
		for r: int in JWUnits.PUBSERV:
			min_ratio = mini(min_ratio, g.st.capital.f_pub_funding_ratio[r])
		print("    承诺 %d：kind20 行=%d 额度 Σpay_opex=%d pubserv 中间消耗=%d 最低到位率=%d deferral=%d 欠付=%d" % [
				committed, tr20.y, grant, pub_ic, min_ratio,
				g.st.treasury.deferral_flag[JWUnits.PayLine.SERVICE_OPEX], g.st.treasury.arrears])
		_check(tr20.y == 0, "S04 不再为运行费过账（kind 20 行数 0）")
		_check(grant <= committed and grant > 0, "额度 0 < %d ≤ 承诺 %d" % [grant, committed])
		if grant == committed:
			_check(min_ratio == JWUnits.PPM, "足额时各地区到位率 == 1e6")
			_check(g.st.treasury.deferral_flag[JWUnits.PayLine.SERVICE_OPEX] == 0, "足额时不置推迟标记")
		else:
			_check(min_ratio < JWUnits.PPM, "不足时到位率 < 1e6（INV-102）")
			_check(g.st.treasury.deferral_flag[JWUnits.PayLine.SERVICE_OPEX] == 1, "不足时置推迟标记")
		_check(g.st.treasury.arrears_by_payee[JWIds.agent_of_pubserv(0)] == 0
				and g.st.treasury.arrears_by_payee[JWIds.agent_of_pubserv(1)] == 0
				and g.st.treasury.arrears_by_payee[JWIds.agent_of_pubserv(2)] == 0
				and g.st.treasury.arrears_by_payee[JWIds.agent_of_pubserv(3)] == 0,
				"欠拨不登记为对 pubserv 的欠付")
		_check(pub_ic > 0 and pub_ic <= grant, "S05 公共服务买方类按额度成交（中间消耗 %d ≤ 额度 %d）" % [
				pub_ic, grant])
		_quarter_close(g, "承诺 %d" % committed)


# ── R-ASSET-01 ─────────────────────────────────────────────────────────────

func _commission() -> void:
	print("── R-ASSET-01 投运结转 ──")
	var g: Rig = _new()
	if g == null:
		return
	_check(g.submit(4, _a6(P04, HAIJIA, 250_000, 1)) == 0, "立项（scale 0.25）受理")
	var pid: int = 0
	var q: int = 0
	while q < 12 and g.alive:
		var wip0: int = g.gov(JWIds.ACC_WIP)
		var cap0: int = g.gov(JWIds.ACC_CAPITAL)
		var nw0: int = g.st.accounts.net_worth_of(JWIds.AGENT_GOV)
		g.advance(1, "commission")
		if not g.alive:
			break
		var tr: Vector2i = g.txn_rows(JWUnits.Kind.ASSET_RECLASS)
		print("    q%d status=%d con=%d del=%d paid=%d wip %d→%d 资本 %d→%d reclass txn=%d 行=%d opex承诺=%d" % [
				q, g.st.projects.status[pid], g.st.projects.construction_progress[pid],
				g.st.projects.delivery_progress[pid], g.paid(pid), wip0, g.gov(JWIds.ACC_WIP), cap0,
				g.gov(JWIds.ACC_CAPITAL), tr.x, tr.y, g.st.treasury.service_opex_committed])
		if tr.x > 0:
			var v: int = g.leg_sum(JWUnits.Kind.ASSET_RECLASS, JWIds.idx_account(JWIds.AGENT_GOV,
					JWIds.ACC_CAPITAL))
			_check(tr.x == 1 and tr.y == 2, "ASSET_RECLASS 一笔两腿")
			_check(v == g.paid(pid), "结转额 == 项目 Σpaid（%d）" % v)
			_check(g.leg_sum(JWUnits.Kind.ASSET_RECLASS, JWIds.idx_account(JWIds.AGENT_GOV,
					JWIds.ACC_WIP)) == -v, "政府 wip −V")
			_check(g.nw_effect(JWUnits.Kind.ASSET_RECLASS, JWIds.AGENT_GOV) == 0, "结转不改政府净值")
			_check(g.st.projects.status[pid] == JWUnits.ProjectStatus.COMPLETED, "项目 COMPLETED")
			_quarter_close(g, "投运季 q%d" % q)
		q += 1
	var st: int = g.st.projects.status[pid]
	_check(st == JWUnits.ProjectStatus.COMPLETED or st == JWUnits.ProjectStatus.COMMISSIONED,
			"项目在推进期内完工 / 投运（status=%d）" % st)


# ── R-PROJECT-01 ⑤：规模 ───────────────────────────────────────────────────

func _scale() -> void:
	print("── R-PROJECT-01 ⑤ scale_ppm ──")
	var g: Rig = _new()
	if g == null:
		return
	_check(g.submit(4, _a6(P04, HAIJIA, 500_000, 1)) == 0, "scale 0.5 立项形状合法")
	_check(g.submit(4, _a6(P04, JWUnits.Region.XILING, 0, 1)) == 0, "scale 0 形状合法（[0, PPM]）")
	_check(g.submit(4, _a6(P04, JWUnits.Region.BEIYUAN, 1, 1)) == 0, "scale 1 ppm 形状合法")
	g.advance(1, "scale")
	if not g.alive:
		return
	var pq: JWProjectQueue = g.st.projects
	_check(pq.count == 1, "只有 scale 0.5 的项目入队（实际 %d）" % pq.count)
	var defs: JWPolicyDef = g.st.policy_defs
	var p: int = 0
	var plan: int = pq.spend_plan[0] + pq.spend_plan[1] + pq.spend_plan[2]
	print("    total=%d plan=%d req_con=%d req_eqp=%d effect=%d opex=%d quarters=%d" % [pq.total_cost[p],
			plan, pq.required_construction[p], pq.required_equipment[p], pq.capacity_effect[p],
			pq.opex_per_q[p], pq.planned_quarters[p]])
	_check(pq.total_cost[p] == JWMath.mul_ppm(defs.cost_one_off_uu[P04], 500_000), "合同额 × 0.5")
	_check(plan == pq.total_cost[p], "Σ spend_plan == 合同额（INV-092）")
	_check(pq.required_construction[p] == JWMath.mul_ppm(defs.required_construction_uqs[P04], 500_000),
			"施工量 × 0.5")
	_check(pq.required_equipment[p] == JWMath.mul_ppm(defs.required_equipment_uqs[P04], 500_000), "设备量 × 0.5")
	_check(pq.capacity_effect[p] == JWMath.mul_ppm(defs.effect_magnitude[P04], 500_000), "产能效果 × 0.5")
	_check(pq.opex_per_q[p] == JWMath.mul_ppm(defs.opex_per_q_uu[P04], 500_000), "运行费 × 0.5")
	_check(pq.planned_quarters[p] == defs.planned_quarters[P04], "工期不随规模变化")
	_check(g.st.treasury.committed_memo >= pq.total_cost[p] - g.paid(p), "承诺按缩放后的合同额签入")
	var rej: PackedInt64Array = PackedInt64Array()
	for i: int in g.cmds.count:
		if g.cmds.c_kind[i] == 4:
			rej.append(g.cmds.c_reject_code[i])
	print("    三条立项的拒绝码 %s" % str(rej))
	_check(rej.size() == 3 and rej[0] == 0 and rej[1] == JWResult.Reject.PARAM_RANGE
			and rej[2] == JWResult.Reject.PARAM_RANGE, "scale 0 与 1 ppm → E_PARAM_RANGE（合同退化）")


# ── R-PROJECT-01 ⑤：复工 ───────────────────────────────────────────────────

func _resume() -> void:
	print("── R-PROJECT-01 ⑤ 挂起复工 ──")
	var g: Rig = _new()
	if g == null:
		return
	g.submit(4, _a6(P04, HAIJIA, JWUnits.PPM, 1))
	g.advance(1, "resume")
	if not g.alive:
		return
	var pq: JWProjectQueue = g.st.projects
	# 人为挂起（两种原因各验一次）：下一季 S02 必须复工，S04 照常付款、S05 照常配额。
	for reason: int in [JWUnits.SuspendReason.FINANCING, JWUnits.SuspendReason.CONGESTION]:
		if pq.status[0] == JWUnits.ProjectStatus.IN_PROGRESS:
			pq.set_status(0, JWUnits.ProjectStatus.SUSPENDED, reason)
		var paid0: int = g.paid(0)
		var con0: int = pq.construction_progress[0]
		g.advance(1, "resume")
		if not g.alive:
			return
		print("    挂起原因 %d → 本季末 status=%d why=%d Δpaid=%d Δcon=%d" % [reason, pq.status[0],
				pq.suspension_reason[0], g.paid(0) - paid0, pq.construction_progress[0] - con0])
		_check(g.paid(0) > paid0, "挂起原因 %d：复工后本季照常付款" % reason)
		_check(pq.construction_progress[0] > con0 or pq.status[0] == JWUnits.ProjectStatus.SUSPENDED,
				"挂起原因 %d：复工后本季照常推进（或按本季实况再挂起）" % reason)
	# 单元级：resume_suspended 只动 SUSPENDED。
	var n_susp: int = 0
	for p: int in pq.count:
		if pq.status[p] == JWUnits.ProjectStatus.SUSPENDED:
			n_susp += 1
	var rc: int = pq.resume_suspended(0)
	_check(rc == JWResult.OK, "resume_suspended 返回 OK")
	for p2: int in pq.count:
		_check(pq.status[p2] != JWUnits.ProjectStatus.SUSPENDED, "p%d 不再挂起" % p2)


# ── R-WINDOW-01 ────────────────────────────────────────────────────────────

func _window() -> void:
	print("── R-WINDOW-01 立法窗口 ──")
	var defs_rbr: PackedInt64Array = PackedInt64Array()
	var g: Rig = _new()
	if g == null:
		return
	for p: int in JWUnits.POLICY_N:
		defs_rbr.append(g.st.policy_defs.requires_budget_review[p])
	print("    requires_budget_review = %s" % str(defs_rbr))
	_check(defs_rbr == PackedInt64Array([1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0]),
			"只有 P01/P02/P06/P10 需要审查窗口")
	var en: PackedInt64Array = PackedInt64Array()
	for p2: int in JWUnits.POLICY_N:
		en.append(g.st.policy.enabled[p2])
	print("    开局 enabled = %s" % str(en))
	var enact_p09: PackedInt64Array = _a6(P09, 15, 10_000, 500_000, 60_000_000, 0)
	_check(g.submit(1, enact_p09) == 0, "q0 开启 P09 形状合法")
	# 需要审查窗口、开局未生效、非项目类的政策 P10（基础医疗）：非审查季 q0 提交一条开启，看它的拒绝码。
	# 参数取内容包默认值（region_mask 15、grant 2e7、staff_target 1e6、weight_rule 2）。
	var probe: int = 9
	var p10_args: PackedInt64Array = _a6(probe, 15, 20_000_000, 1_000_000, 2, 0)
	# 仅诊断：开局没有 P10 的法定授权（资格链第 1 项先于窗口，会给 1004），把授权位全开，
	# 让拒绝码只可能来自其后的窗口 / 资金判定。
	g.st.politics.legal_authority_mask = (1 << 62) - 1
	if en[probe] == 0:
		g.submit(1, p10_args)
	else:
		probe = -1
	g.advance(1, "window")
	_check(g.st.policy.enabled[P09] == 1, "P09 在非审查季 q0 受理")
	var code_q0: int = _last_reject(g, 1, probe)
	g.advance(2, "window")
	if not g.alive:
		return
	# q3 是审查季：命令受理之前窗口已打开（f_budget_review_due 在本季 S02 开头置位）。
	if probe >= 0:
		g.submit(1, p10_args)
	g.advance(1, "window")
	var code_q3: int = _last_reject(g, 1, probe)
	print("    探针政策 P%02d：q0 拒绝码 %d，q3 拒绝码 %d（1011 == PRECONDITION）；q3 审查标记=%d" % [
			probe + 1, code_q0, code_q3, g.st.politics.f_budget_review_due])
	_check(g.st.politics.f_budget_review_due == 1, "q3 本季审查标记已置位")
	if probe >= 0:
		_check(code_q0 == JWResult.Reject.PRECONDITION, "需要窗口的政策在 q0 被拒（窗口未开）")
		_check(code_q3 != code_q0 or code_q3 == 0, "q3 的拒绝码不再是窗口未开（命令受理前已置位）")


func _last_reject(g: Rig, kind: int, p: int) -> int:
	var code: int = -1
	for i: int in g.cmds.count:
		if g.cmds.c_kind[i] == kind and g.cmds.arg_at(i, JWCommands.SLOT_POLICY) == p:
			code = g.cmds.c_reject_code[i]
	return code


# ── F01 / F06：取消量法 ────────────────────────────────────────────────────

func _cancel_legs(g: Rig, pid: int, account: int) -> int:
	var acc: int = 0
	for i: int in g.st.ledger.log_row_count():
		var k: int = g.st.ledger.l_kind[i]
		if (k == JWUnits.Kind.CANCEL_PENALTY or k == JWUnits.Kind.WRITEOFF) \
				and g.st.ledger.l_entity[i] == pid and g.st.ledger.l_account[i] == account:
			acc += g.st.ledger.l_delta[i]
	return acc


func _cancel_nw(g: Rig, pid: int) -> int:
	var nw: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_NW)
	var acc: int = 0
	for i: int in g.st.ledger.log_row_count():
		var k: int = g.st.ledger.l_kind[i]
		var a: int = g.st.ledger.l_account[i]
		if (k == JWUnits.Kind.CANCEL_PENALTY or k == JWUnits.Kind.WRITEOFF) \
				and g.st.ledger.l_entity[i] == pid \
				and JWMath.floor_div(a, JWUnits.ACCOUNT_CODE_N) == JWIds.AGENT_GOV and a != nw:
			acc += g.st.ledger.l_delta[i]
	return acc


func _f01() -> void:
	print("── F01 取消不退款（取消相关分录量法） ──")
	var g: Rig = _new()
	if g == null:
		return
	_check(g.submit(4, _a6(P04, HAIJIA, JWUnits.PPM, 1)) == 0, "立项命令受理")
	g.advance(4, "f01")
	if not g.alive:
		return
	var pid: int = g.st.projects.count - 1
	var cash_before: int = g.st.accounts.cash_of(JWIds.AGENT_GOV)
	var paid_before: int = g.paid(pid)
	var committed_before: int = g.st.treasury.committed_memo
	var unpaid: int = g.st.projects.total_cost[pid] - paid_before
	_check(g.submit(5, _a6(pid)) == 0, "取消命令受理")
	g.advance(1, "f01")
	if not g.alive:
		return
	var gov_cash: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	var cancel_cash: int = _cancel_legs(g, pid, gov_cash)
	var pen: int = g.leg_sum(JWUnits.Kind.CANCEL_PENALTY, gov_cash)
	print("    整季 Δcash=%d 取消相关 Δcash=%d 赔偿=%d 本项目 penalty=%d 新增借款=%d" % [
			g.st.accounts.cash_of(JWIds.AGENT_GOV) - cash_before, cancel_cash, -pen,
			g.st.projects.cancel_penalty[pid], g.st.treasury.f_new_borrowing])
	_check(cancel_cash <= 0 and cancel_cash == pen, "① 取消相关分录只减现金、恰为 −赔偿")
	_check(g.paid(pid) == paid_before, "② paid 不回退")
	_check(g.st.treasury.committed_memo == committed_before - unpaid, "③ committed 只减未付")
	_check(g.st.projects.residual_value[pid] <= paid_before, "④ 残值 ≤ 已付")
	_check(g.st.projects.status[pid] == JWUnits.ProjectStatus.CANCELLED, "⑥ 终态 cancelled")
	_quarter_close(g, "F01 取消季")


func _f06() -> void:
	print("── F06 残值不超过已付（取消相关分录量法） ──")
	var g: Rig = _new()
	if g == null:
		return
	_check(g.submit(4, _a6(P04, HAIJIA, JWUnits.PPM, 1)) == 0, "立项命令受理")
	g.advance(1, "f06")
	if not g.alive:
		return
	var pid: int = g.st.projects.count - 1
	var paid: int = g.paid(pid)
	var wip_before: int = g.gov(JWIds.ACC_WIP)
	var nw_before: int = g.st.accounts.net_worth_of(JWIds.AGENT_GOV)
	_check(g.submit(5, _a6(pid)) == 0, "取消命令受理")
	g.advance(1, "f06")
	if not g.alive:
		return
	var residual: int = g.st.projects.residual_value[pid]
	var pen: int = -g.leg_sum(JWUnits.Kind.CANCEL_PENALTY, JWIds.idx_account(JWIds.AGENT_GOV,
			JWIds.ACC_CASH))
	var d_nw: int = _cancel_nw(g, pid)
	print("    paid=%d wip_before=%d residual=%d penalty=%d 取消相关Δnw=%d 期望=%d 整季Δnw=%d" % [
			paid, wip_before, residual, pen, d_nw, residual - wip_before - pen,
			g.st.accounts.net_worth_of(JWIds.AGENT_GOV) - nw_before])
	_check(residual <= wip_before and wip_before <= paid, "① 残值 ≤ wip ≤ 已付")
	_check(d_nw == residual - wip_before - pen, "③ 取消相关 Δnw == 残值 − wip − 赔偿")
	_quarter_close(g, "F06 取消季")


# ── INV-032 三个变动点（T-U-D-08），经真实 pay_line ─────────────────────────

func _memo() -> void:
	print("── INV-032 三个变动点（T-U-D-08） ──")
	JWResult.clear_pending()
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all("res://content", st)
	if res == null or not res.ok:
		print("load_all 失败")
		return
	JWResult.clear_pending()
	var pq: JWProjectQueue = st.projects
	var tre: JWTreasury = st.treasury
	st.ledger.set_context(0, JWUnits.Phase.S02)
	var memo0: int = tre.committed_memo
	var p: int = pq.launch(1, P04, HAIJIA, st.policy_defs, st.capital, 0)
	_check(p >= 0 and pq.status[p] == JWUnits.ProjectStatus.PLANNED, "launch → PLANNED")
	_check(tre.committed_memo == memo0, "launch 本身不登记承诺（未签约）")
	_check(pq.start(p, tre) == JWResult.OK, "start 成功")
	_check(tre.committed_memo - memo0 == 4_000_000_000, "签约 +4 U")
	# 履约付款：真实 S04 路径（payment_due_into → pay_line 四腿 → record_payment）。
	st.ledger.set_context(0, JWUnits.Phase.S04)
	var wip0: int = st.accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_WIP))
	var nw0: int = st.accounts.net_worth_of(JWIds.AGENT_GOV)
	var cap: int = 3
	var o_p: PackedInt64Array = PackedInt64Array()
	o_p.resize(cap)
	var o_l: PackedInt64Array = PackedInt64Array()
	o_l.resize(cap)
	var o_a: PackedInt64Array = PackedInt64Array()
	o_a.resize(cap)
	var o_d: PackedInt64Array = PackedInt64Array()
	o_d.resize(cap)
	var n: int = pq.payment_due_into(o_p, o_l, o_a, o_d, 0)
	_check(n == 3, "三条支出线各一行应付")
	tre.begin_quarter(st.accounts)
	var rc_pl: int = tre.pay_line(JWUnits.PayLine.PROJECT_CONTRACTS, o_a, o_d, JWUnits.Kind.PROJECT_PAYMENT,
			st.ledger, st.accounts)
	_check(rc_pl == JWResult.OK, "pay_line 成功")
	for i: int in n:
		pq.record_payment(o_p[i], o_l[i], tre.last_paid_of(i), tre)
	var wip1: int = st.accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_WIP))
	_check(wip1 - wip0 == 500_000_000, "付款同时 wip +0.5 U（%d）" % (wip1 - wip0))
	_check(st.accounts.net_worth_of(JWIds.AGENT_GOV) == nw0, "付款不改政府净值")
	_check(tre.committed_memo - memo0 == 3_500_000_000, "履约 −0.5 U")
	st.ledger.set_context(0, JWUnits.Phase.S02)
	var cash0: int = st.accounts.cash_of(JWIds.AGENT_GOV)
	var rc: int = pq.cancel(p, st.policy_defs, tre, st.ledger, st.accounts, st.capital)
	_check(rc == JWResult.OK, "取消成功（rc=%d）" % rc)
	_check(tre.committed_memo == memo0, "取消 −3.5 U")
	_check(cash0 - st.accounts.cash_of(JWIds.AGENT_GOV) == pq.cancel_penalty[p], "现金减少恰为赔偿")
	var wip2: int = st.accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_WIP))
	_check(wip2 - wip0 == pq.residual_value[p], "取消后 wip 只剩残值")
	_check(JWResult.pending_code() == 0, "全程无故障登记（实际 %d）" % JWResult.pending_code())


# ── P09 两次开关：承诺按「本次开启」口径释放 ─────────────────────────────────

func _repeal_twice() -> void:
	print("── P09 开 → 关 → 再开 → 再关（INV-032） ──")
	var g: Rig = _new()
	if g == null:
		return
	var enact: PackedInt64Array = _a6(P09, 15, 10_000, 500_000, 60_000_000, 0)
	var rep: PackedInt64Array = _a6(P09)
	var memo0: int = g.st.treasury.committed_memo
	var plan: Array = [[0, 1, enact], [4, 3, rep], [8, 1, enact], [12, 3, rep]]
	for step: Array in plan:
		while g.alive and g.st.q < int(step[0]):
			g.advance(1, "repeal2")
		if not g.alive:
			print("    提前终局于 q%d（校准问题，与本场景无关）" % g.st.q)
			return
		var code: int = g.submit(int(step[1]), step[2])
		g.advance(1, "repeal2")
		if not g.alive:
			return
		print("    q%d kind=%d 提交码=%d → enabled=%d toggles=%d committed_p=%d spent_p=%d memo=%d" % [
				int(step[0]), int(step[1]), code, g.st.policy.enabled[P09], g.st.policy.toggle_count[P09],
				g.st.policy.budget_committed[P09], g.st.policy.budget_spent[P09],
				g.st.treasury.committed_memo])
		var want: int = memo0 + (2_400_000_000 if g.st.policy.enabled[P09] == 1 else 0)
		_check(g.st.treasury.committed_memo == want, "q%d 后 committed_memo == %d" % [int(step[0]), want])
		_check(JWResult.pending_code() == 0, "q%d 无故障登记" % int(step[0]))
