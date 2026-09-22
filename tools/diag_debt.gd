## 债务定价诊断：逐季打印偿债率（dsr）、本季新发票息、存量平均票息、未来四季到期本金与利息。
##
## 用法：godot --headless --path <根> --script res://tools/diag_debt.gd -- [季数=40] [种子] [noshock]
## 只读诊断：不改内容、不改代码。用来检查「新发票息 vs 存量票息」是否让基线利息自行螺旋上升
## （计划书 §14 校准第一步：基线不应因定价口径而自行恶化）。
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 40
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
	print("季  债务U  平均票息‰/季  新发票息‰/季  dsr‰  4季本金U  4季利息U  年化收入U  利息U  批次")
	_row(st, -1)
	for q: int in n_q:
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		var code: int = runner.advance_quarter(cmds)
		if code != JWResult.OK:
			print("第 %d 季推进返回 %d，停止" % [q, code])
			break
		_row(st, q)
	quit(0)


func _row(st: JWSimState, q: int) -> void:
	var b: JWBondBook = st.bonds
	var bal_sum: int = 0
	var wsum: float = 0.0
	var prin4: int = 0
	var int4: int = 0
	var qn: int = st.q
	for i: int in b.count:
		var bal: int = b.principal_outstanding[i]
		if bal <= 0:
			continue
		bal_sum += bal
		wsum += float(bal) * float(b.coupon_ppm[i])
		var bb: int = bal
		for t: int in 4:
			var qq: int = qn + t
			int4 += bb * b.coupon_ppm[i] / 1_000_000
			var due: int = 0
			if b.amortization[i] == JWUnits.Amortization.BULLET:
				if qq == b.maturity_q[i]:
					due = bb
			else:
				due = mini(b._sched_at(i, qq), bb)
			prin4 += due
			bb -= due
	var avg_cp: float = wsum / maxf(1.0, float(bal_sum))
	var ann: int = st.treasury.state_scalar(8)
	var dsr: float = float(prin4 + int4) / maxf(1.0, float(ann))
	print("%3d %7.2f %10.2f %12.2f %8.0f %9.2f %9.2f %10.2f %7.2f %5d" % [q, bal_sum / 1e9, avg_cp / 1000.0,
			st.treasury._q_coupon_dom / 1000.0, dsr * 1000.0, prin4 / 1e9, int4 / 1e9, ann / 1e9,
			st.treasury.f_interest_paid / 1e9, b.count])
