## 诊断：复现 adversarial_money_test 的 F 族 / A01 夹具（经 JWGame 开局与推进），
## 打开 JWResult.trace_faults，故障登记时打印调用栈；逐季打印项目与国库的关键量。
## 用法：godot --headless --path <根> --script res://tools/diag_projects.gd -- <场景> [季数]
## 场景：empty / a01 / f01 / f02 / f03 / f05 / f06 / p12（开启 P12）/ repeal_p03（撤销开局现行制度）
extends SceneTree

const P04: int = 3
const P09: int = 8
const HAIJIA: int = 2


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var which: String = args[0] if args.size() > 0 else "empty"
	var n_q: int = int(args[1]) if args.size() > 1 else 12
	JWResult.trace_faults = true
	JWResult.clear_pending()
	match which:
		"empty":
			_run_empty(n_q)
		"a01":
			_run_a01()
		"f01":
			_run_f01()
		"f02":
			_run_f02()
		"f03":
			_run_f03()
		"f05":
			_run_f05(n_q)
		"f06":
			_run_f06()
		"p12":
			_run_p12()
		"repeal_p03":
			_run_repeal_p03()
		_:
			print("未知场景 %s" % which)
	quit(0)


func _boot() -> JWGame:
	var g: JWGame = JWGame.new()
	var r: JWResult = g.new_game("res://content", 1, 40)
	if r == null or not r.ok:
		print("new_game 失败 code=%d" % (r.code if r != null else -1))
		return null
	JWResult.clear_pending()
	return g


func _a6(s0: int = 0, s1: int = 0, s2: int = 0, s3: int = 0, s4: int = 0,
		s5: int = 0) -> PackedInt64Array:
	return PackedInt64Array([s0, s1, s2, s3, s4, s5])


func _submit(g: JWGame, kind: int, a: PackedInt64Array) -> int:
	var r: JWResult = g.submit_command(kind, a)
	return 0 if (r == null or r.ok) else r.code


## 推进一季；返回 advance 的码。
func _adv(g: JWGame, tag: String) -> int:
	var st: JWSimState = g._st
	var q0: int = st.q
	var m: int = _submit(g, 99, _a6())
	if m != 0:
		print("[%s] q=%d 推进标记被拒 %d" % [tag, q0, m])
		return m
	var r: JWResult = g.advance_quarter()
	var rc: int = 0 if (r == null or r.ok) else r.code
	print("[%s] q=%d -> rc=%d pending=%d@S%d | 国库 %s | 欠付 %s | committed %s | wip %s | nw %s | 执政 %d 终止 %s/%d" % [
			tag, q0, rc, JWResult.pending_code(), JWResult.pending_step(),
			_u(st.accounts.cash_of(JWIds.AGENT_GOV)), _u(st.treasury.arrears),
			_u(st.treasury.committed_memo),
			_u(st.accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_WIP))),
			_u(st.accounts.net_worth_of(JWIds.AGENT_GOV)),
			st.politics.mandate_status, str(st.politics.run_terminated),
			st.politics.termination_reason])
	return rc


func _dump_projects(st: JWSimState) -> void:
	var pq: JWProjectQueue = st.projects
	for p: int in pq.count:
		var paid: int = pq.paid[p * 3] + pq.paid[p * 3 + 1] + pq.paid[p * 3 + 2]
		var plan: int = pq.spend_plan[p * 3] + pq.spend_plan[p * 3 + 1] + pq.spend_plan[p * 3 + 2]
		print("    p%02d r=%d st=%d why=%d slot=%d con=%d del=%d paid=%s/%s resid=%s pen=%s comm_q=%d req_con=%d" % [
				p, pq.region_idx[p], pq.status[p], pq.suspension_reason[p], pq.slot_held[p],
				pq.construction_progress[p], pq.delivery_progress[p], _u(paid), _u(plan),
				_u(pq.residual_value[p]), _u(pq.cancel_penalty[p]), pq.commissioned_q[p],
				pq.required_construction[p]])
	var line: String = "    施工能力/已用："
	for r: int in JWUnits.R:
		line += " r%d %d/%d" % [r, pq.f_construction_capacity[r], pq.f_construction_used[r]]
	print(line)


func _run_empty(n_q: int) -> void:
	var g: JWGame = _boot()
	if g == null:
		return
	for i: int in n_q:
		if _adv(g, "empty") != 0:
			return


func _run_a01() -> void:
	var g: JWGame = _boot()
	if g == null:
		return
	var enact: PackedInt64Array = _a6(P09, 15, 10_000, 500_000, 60_000_000, 0)
	print("enact -> %d" % _submit(g, 1, enact))
	_adv(g, "a01")
	var cm: JWCommands = g._cmds
	for i: int in cm.count:
		print("    cmd#%d q=%d kind=%d accepted=%d reject=%d" % [cm.c_command_id[i], cm.c_issued_q[i],
				cm.c_kind[i], cm.c_accepted[i], cm.c_reject_code[i]])
	print("    P09 enabled=%d enacted_q=%d cooldown_until=%d toggles=%d blocked=%d" % [
			g._st.policy.enabled[P09], g._st.policy.enacted_q[P09], g._st.policy.cooldown_until_q[P09],
			g._st.policy.toggle_count[P09], g._st.policy.blocked_reason(P09)])
	print("repeal@q1 -> %d（期望 1003）" % _submit(g, 3, _a6(P09)))
	_adv(g, "a01")
	var round_i: int = 0
	while round_i < 20:
		var rc: int = 0
		if round_i % 2 == 0:
			rc = _submit(g, 3, _a6(P09))
		else:
			rc = _submit(g, 1, enact)
		print("round %d submit -> %d" % [round_i, rc])
		if _adv(g, "a01") != 0:
			return
		round_i += 1


## 开启一项不需要预算审查窗口的政策（P12），看开关成本能否通过 S06 的 INV-027 终检。
func _run_p12() -> void:
	var g: JWGame = _boot()
	if g == null:
		return
	print("enact P12 -> %d" % _submit(g, 1, _a6(11, 200_000, 250_000, 500_000, 0, 0)))
	_adv(g, "p12")
	var cm: JWCommands = g._cmds
	for i: int in cm.count:
		print("    cmd#%d q=%d kind=%d accepted=%d reject=%d" % [cm.c_command_id[i], cm.c_issued_q[i],
				cm.c_kind[i], cm.c_accepted[i], cm.c_reject_code[i]])
	print("    P12 enabled=%d toggles=%d" % [g._st.policy.enabled[11], g._st.policy.toggle_count[11]])
	_adv(g, "p12")


## 撤销一项开局即生效的现行制度（P03，无预留），看开关成本能否通过 INV-027。
func _run_repeal_p03() -> void:
	var g: JWGame = _boot()
	if g == null:
		return
	print("repeal P03 -> %d" % _submit(g, 3, _a6(2)))
	_adv(g, "repeal_p03")
	var cm: JWCommands = g._cmds
	for i: int in cm.count:
		print("    cmd#%d q=%d kind=%d accepted=%d reject=%d" % [cm.c_command_id[i], cm.c_issued_q[i],
				cm.c_kind[i], cm.c_accepted[i], cm.c_reject_code[i]])
	print("    P03 enabled=%d toggles=%d cooldown_until=%d" % [g._st.policy.enabled[2],
			g._st.policy.toggle_count[2], g._st.policy.cooldown_until_q[2]])
	print("re-enact P03@q1 -> %d（冷却中，S02 应拒）" % _submit(g, 1, _a6(2, 400_000, 0, 0, 0, 0)))
	print("repeal P03@q1 -> %d（已关，S02 应 NOT_FOUND）" % _submit(g, 3, _a6(2)))
	_adv(g, "repeal_p03")
	for i: int in cm.count:
		print("    cmd#%d q=%d kind=%d accepted=%d reject=%d" % [cm.c_command_id[i], cm.c_issued_q[i],
				cm.c_kind[i], cm.c_accepted[i], cm.c_reject_code[i]])


func _run_f01() -> void:
	var g: JWGame = _boot()
	if g == null:
		return
	print("launch -> %d" % _submit(g, 4, _a6(P04, HAIJIA, JWUnits.PPM, 1)))
	for i: int in 4:
		if _adv(g, "f01") != 0:
			_dump_projects(g._st)
			return
		_dump_projects(g._st)
	var pid: int = g._st.projects.count - 1
	print("cancel p%d -> %d" % [pid, _submit(g, 5, _a6(pid))])
	_adv(g, "f01")
	_dump_projects(g._st)


func _run_f02() -> void:
	var g: JWGame = _boot()
	if g == null:
		return
	var st: JWSimState = g._st
	var rounds: int = 0
	while rounds < 6:
		for rr: int in JWUnits.R:
			var k: int = 0
			while k < st.capital.slots_total(rr) + 3:
				_submit(g, 4, _a6(P04, rr, JWUnits.PPM, 1))
				k += 1
		if _adv(g, "f02-launch") != 0:
			_dump_projects(st)
			return
		_dump_projects(st)
		for p: int in st.projects.count:
			if st.projects.status[p] != JWUnits.ProjectStatus.CANCELLED \
					and st.projects.status[p] != JWUnits.ProjectStatus.COMMISSIONED:
				_submit(g, 5, _a6(p))
		if _adv(g, "f02-cancel") != 0:
			_dump_projects(st)
			return
		_dump_projects(st)
		rounds += 1


func _run_f03() -> void:
	var g: JWGame = _boot()
	if g == null:
		return
	var st: JWSimState = g._st
	print("launch -> %d" % _submit(g, 4, _a6(P04, HAIJIA, JWUnits.PPM, 1)))
	_adv(g, "f03")
	_dump_projects(st)
	var pid: int = st.projects.count - 1
	var prev_progress: int = st.projects.construction_progress[pid]
	var q: int = 1
	while q < 10:
		if _adv(g, "f03") != 0:
			_dump_projects(st)
			return
		_dump_projects(st)
		var used: int = st.projects.f_construction_used[HAIJIA]
		var required: int = st.projects.required_construction[pid]
		var progress: int = st.projects.construction_progress[pid]
		var expect: int = JWMath.mul_div_floor(used, JWUnits.PPM, required)
		print("    Δprogress=%d 期望=%d（used=%d required=%d）%s" % [progress - prev_progress, expect,
				used, required, "" if progress - prev_progress == expect or progress >= JWUnits.PPM else " <<< 不符"])
		prev_progress = progress
		q += 1


func _run_f05(n_q: int) -> void:
	var gw: JWGame = _boot()
	var gs: JWGame = _boot()
	if gw == null or gs == null:
		return
	print("whole launch -> %d" % _submit(gw, 4, _a6(P04, HAIJIA, JWUnits.PPM, 1)))
	for k: int in 9:
		print("split launch %d -> %d" % [k, _submit(gs, 4, _a6(P04, HAIJIA, 111_111, 1))])
	for i: int in n_q:
		var a: int = _adv(gw, "f05-whole")
		_dump_projects(gw._st)
		var b: int = _adv(gs, "f05-split")
		_dump_projects(gs._st)
		if a != 0 or b != 0:
			return


func _run_f06() -> void:
	var g: JWGame = _boot()
	if g == null:
		return
	var st: JWSimState = g._st
	print("launch -> %d" % _submit(g, 4, _a6(P04, HAIJIA, JWUnits.PPM, 1)))
	_adv(g, "f06")
	_dump_projects(st)
	var pid: int = st.projects.count - 1
	var wip_before: int = st.accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_WIP))
	var nw_before: int = st.accounts.net_worth_of(JWIds.AGENT_GOV)
	print("cancel p%d -> %d" % [pid, _submit(g, 5, _a6(pid))])
	_adv(g, "f06")
	_dump_projects(st)
	var pen: int = 0
	var led: JWLedger = st.ledger
	for i: int in led.log_row_count():
		if led.l_kind[i] == JWUnits.Kind.CANCEL_PENALTY and led.l_delta[i] > 0:
			pen += led.l_delta[i]
	var d_nw: int = st.accounts.net_worth_of(JWIds.AGENT_GOV) - nw_before
	print("    Δnw=%d 残值=%d wip_before=%d penalty=%d 期望Δnw=%d" % [d_nw,
			st.projects.residual_value[pid], wip_before, pen,
			st.projects.residual_value[pid] - wip_before - pen])


## μU → 「x.xxx U」（诊断脚本属 tools/，允许浮点格式化）。
func _u(v: int) -> String:
	return "%.3f" % (float(v) / 1_000_000_000.0)
