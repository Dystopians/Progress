## 诊断：逐条复刻 adversarial_money_test 的 ADV-A01 命令序列（经 JWGame），打开 trace_faults，
## 故障登记时打印调用栈；逐季打印 P09 状态、国库、承诺、预留与欠付。
## 用法：godot --headless --path <根> --script res://tools/diag_a01.gd
extends SceneTree

const P09: int = 8


func _init() -> void:
	JWResult.trace_faults = true
	JWResult.clear_pending()
	var g: JWGame = JWGame.new()
	var r: JWResult = g.new_game("res://content", 1, 40)
	if r == null or not r.ok:
		print("new_game 失败")
		quit(1)
		return
	JWResult.clear_pending()
	var enact: PackedInt64Array = PackedInt64Array([P09, 15, 10_000, 500_000, 60_000_000, 0])
	print("q0 enact -> %d" % _sub(g, 1, enact))
	if not _adv(g):
		quit(0)
		return
	print("q1 repeal -> %d" % _sub(g, 3, PackedInt64Array([P09, 0, 0, 0, 0, 0])))
	if not _adv(g):
		quit(0)
		return
	var round_i: int = 0
	while round_i < 20:
		var code: int = 0
		if round_i % 2 == 0:
			code = _sub(g, 3, PackedInt64Array([P09, 0, 0, 0, 0, 0]))
		else:
			code = _sub(g, 1, enact)
		print("round %d (q%d) %s -> %d" % [round_i, g._st.q, "repeal" if round_i % 2 == 0 else "enact", code])
		if not _adv(g):
			break
		round_i += 1
	quit(0)


func _sub(g: JWGame, kind: int, a: PackedInt64Array) -> int:
	var r: JWResult = g.submit_command(kind, a)
	return 0 if (r == null or r.ok) else r.code


func _adv(g: JWGame) -> bool:
	var st: JWSimState = g._st
	var q0: int = st.q
	_sub(g, 99, PackedInt64Array([0, 0, 0, 0, 0, 0]))
	var r: JWResult = g.advance_quarter()
	var rc: int = 0 if (r == null or r.ok) else r.code
	var cm: JWCommands = g._cmds
	var line: String = ""
	for i: int in cm.count:
		if cm.c_issued_q[i] == q0 and cm.c_kind[i] != 99:
			line += " cmd(kind=%d acc=%d rej=%d)" % [cm.c_kind[i], cm.c_accepted[i], cm.c_reject_code[i]]
	print("[q%d] rc=%d pending=%d@S%d | P09 en=%d toggles=%d cd_until=%d committed_p=%d spent_p=%d | 国库 %d 预留 %d 承诺 %d 欠付 %d%s" % [
			q0, rc, JWResult.pending_code(), JWResult.pending_step(), st.policy.enabled[P09],
			st.policy.toggle_count[P09], st.policy.cooldown_until_q[P09], st.policy.budget_committed[P09],
			st.policy.budget_spent[P09], st.accounts.cash_of(JWIds.AGENT_GOV), st.treasury.reserved_memo,
			st.treasury.committed_memo, st.treasury.arrears, line])
	return rc == 0 and not JWResult.has_pending()
