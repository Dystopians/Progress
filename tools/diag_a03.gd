## 诊断：ADV-A03 的两组对照（开启 P09 vs 不开），逐季打印支出法 C、补助、开关成本、
## 中州服务 cell 的销售与现金，定位两组 C 之差的来源。
## 用法：godot --headless --path <根> --script res://tools/diag_a03.gd -- [季数]
extends SceneTree

const P09: int = 8


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 8
	JWResult.trace_faults = true
	JWResult.clear_pending()
	var g_on: JWGame = _boot()
	var g_c: JWGame = _boot()
	if g_on == null or g_c == null:
		quit(1)
		return
	var enact: PackedInt64Array = PackedInt64Array([P09, 15, 10_000, 500_000, 60_000_000, 0])
	var r: JWResult = g_on.submit_command(1, enact)
	print("enact P09 -> %d" % (0 if (r == null or r.ok) else r.code))
	var zz_svc: int = JWIds.agent_of_cell(JWIds.idx_cell(JWUnits.Region.ZHONGZHOU,
			JWUnits.Sector.SERVICES))
	var q: int = 0
	while q < n_q:
		_adv(g_on)
		_adv(g_c)
		var c_on: int = _class_c(g_on._st)
		var c_c: int = _class_c(g_c._st)
		print("q=%d  C_on=%d C_ctrl=%d ΔC=%d | 补助 on=%d | 开关成本 on=%d | 中州服务现金 on=%d ctrl=%d | GDP on=%d ctrl=%d" % [
				q, c_on, c_c, c_on - c_c, _kind_pos(g_on._st, JWUnits.Kind.SUBSIDY),
				_kind_pos(g_on._st, JWUnits.Kind.POLICY_TOGGLE_COST),
				g_on._st.accounts.cash_of(zz_svc), g_c._st.accounts.cash_of(zz_svc),
				g_on._st.diag.gdp_production, g_c._st.diag.gdp_production])
		q += 1
	quit(0)


func _boot() -> JWGame:
	var g: JWGame = JWGame.new()
	var r: JWResult = g.new_game("res://content", 1, 40)
	if r == null or not r.ok:
		print("new_game 失败 code=%d" % (r.code if r != null else -1))
		return null
	JWResult.clear_pending()
	return g


func _adv(g: JWGame) -> void:
	g.submit_command(99, PackedInt64Array([0, 0, 0, 0, 0, 0]))
	var r: JWResult = g.advance_quarter()
	if r != null and not r.ok:
		print("advance -> %d pending=%d" % [r.code, JWResult.pending_code()])


func _class_c(st: JWSimState) -> int:
	var prod: PackedInt64Array = PackedInt64Array()
	prod.resize(8)
	var ex: PackedInt64Array = PackedInt64Array()
	ex.resize(8)
	var inc: PackedInt64Array = PackedInt64Array()
	inc.resize(8)
	st.ledger.aggregate_classes(prod, ex, inc)
	return ex[JWUnits.ExpClass.C]


func _kind_pos(st: JWSimState, kind: int) -> int:
	var led: JWLedger = st.ledger
	var acc: int = 0
	var i: int = 0
	while i < led.log_row_count():
		if led.l_kind[i] == kind and led.l_delta[i] > 0 \
				and led.l_account[i] % JWUnits.ACCOUNT_CODE_N == JWIds.ACC_CASH:
			acc += led.l_delta[i]
		i += 1
	return acc
