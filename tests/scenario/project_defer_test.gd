## 项目延期（命令 6，docs/18 R-DEFER-01；docs/31 ADV-F04 / Q-ADV-01）的场景测试。
## 走应用层 JWGame：开局 → 海岬立项 P04（发债）→ 延期 → 逐季核对挂起、槽位、承诺、赔偿与复工。
extends JWTest

const P04: int = 3
const FUNDING_BOND: int = 1
const DEFER_Q: int = 4


func _game() -> JWGame:
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_test"
	var r: JWResult = g.new_game("res://content", 1_000_000, 40)
	check(r != null and r.ok, "开局成功")
	return g


func _args(a: Array) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(JWCommands.ARG_SLOTS)
	out.fill(0)
	for i: int in a.size():
		out[i] = int(a[i])
	return out


func _advance(g: JWGame) -> void:
	g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, _args([]))
	var r: JWResult = g.advance_quarter()
	check(r == null or r.ok, "推进成功（第 %d 季）" % _st(g).q)


func _st(g: JWGame) -> JWSimState:
	return g.get("_st") as JWSimState


## 最后一条某类命令的受理结果：0 == 受理，否则为拒绝码；没有该类命令返回 −1。
func _last_result(g: JWGame, kind: int) -> int:
	var c: JWCommands = g.get("_cmds") as JWCommands
	var i: int = c.count - 1
	while i >= 0:
		if c.c_kind[i] == kind:
			return 0 if c.c_accepted[i] == 1 else int(c.c_reject_code[i])
		i -= 1
	return -1


## 立项并推进一季，返回项目下标。
func _launch(g: JWGame) -> int:
	g.submit_command(JWCommands.Kind.PROJECT_LAUNCH, _args([P04, JWUnits.Region.HAIJIA, JWUnits.PPM, FUNDING_BOND]))
	_advance(g)
	eq_int(_last_result(g, JWCommands.Kind.PROJECT_LAUNCH), 0, "P04 海岬立项受理")
	return _st(g).projects.count - 1


func test_defer_suspends_holds_slot_keeps_commitment_and_charges_fee() -> void:
	var g: JWGame = _game()
	var p: int = _launch(g)
	if p < 0:
		return
	var st: JWSimState = _st(g)
	var pq: JWProjectQueue = st.projects
	eq_int(pq.status[p], JWUnits.ProjectStatus.IN_PROGRESS, "立项后在建")
	var q_defer: int = st.q
	var remaining: int = pq.committed_remaining(p)
	var memo0: int = st.treasury.committed_memo
	var rem0: int = remaining
	var prog0: int = pq.construction_progress[p]
	var fee_rate: int = st.params[JWUnits.Param.DEFER_FEE_PPM_PER_Q] * DEFER_Q
	var fee_expect: int = JWMath.mul_ppm(remaining, fee_rate)
	check(fee_expect > 0, "夹具前提：剩余合同额 × 赔偿率 > 0")
	var arrears0: int = st.treasury.arrears

	g.submit_command(JWCommands.Kind.PROJECT_DEFER, _args([_st(g).projects.entity[p], DEFER_Q]))
	_advance(g)
	eq_int(_last_result(g, JWCommands.Kind.PROJECT_DEFER), 0, "延期受理")
	eq_int(pq.status[p], JWUnits.ProjectStatus.SUSPENDED, "延期 ⇒ 挂起")
	eq_int(pq.suspension_reason[p], JWUnits.SuspendReason.DEFERRED, "挂起原因 == 延期")
	eq_int(pq.defer_until_q[p], q_defer + DEFER_Q, "到期季 == 受理季 + 季数")
	eq_int(pq.defer_count[p], 1, "延期次数 1")
	eq_int(pq.defer_q_total[p], DEFER_Q, "累计延期季数")
	eq_int(pq.slot_held[p], 1, "INV-094：延期期间不释放槽位")
	eq_int(st.treasury.committed_memo, memo0, "INV-032：延期当季承诺不变（没有履约付款，也不冲减）")
	eq_int(pq.committed_remaining(p), rem0, "延期当季没有付款")
	eq_int(pq.construction_progress[p], prog0, "INV-087：延期当季没有施工进度")
	eq_int(pq.defer_fee[p], fee_expect, "延期赔偿 == floor(剩余合同额 × 每季赔偿率 × 季数)")
	check(st.treasury.arrears >= arrears0, "赔偿现金不足只会转欠付，不会凭空消失")

	# 延期期间逐季：不付款、不推进、槽位照占。
	var k: int = 1
	while k < DEFER_Q:
		_advance(g)
		eq_int(pq.status[p], JWUnits.ProjectStatus.SUSPENDED, "延期第 %d 季仍挂起" % (k + 1))
		eq_int(pq.committed_remaining(p), rem0, "延期第 %d 季没有付款" % (k + 1))
		eq_int(pq.construction_progress[p], prog0, "延期第 %d 季没有进度" % (k + 1))
		eq_int(pq.slot_held[p], 1, "延期第 %d 季仍占槽位" % (k + 1))
		k += 1
	eq_int(st.q, q_defer + DEFER_Q, "夹具前提：下一季就是到期季")

	# 到期季 S02 复工：本季重新开出应付、分配施工能力。
	_advance(g)
	check(pq.suspension_reason[p] != JWUnits.SuspendReason.DEFERRED, "到期季复工，不再是延期挂起")
	check(pq.committed_remaining(p) < rem0 or pq.construction_progress[p] > prog0,
			"复工当季重新付款或推进（实测剩余 %d / 原 %d，进度 %d / 原 %d）"
			% [pq.committed_remaining(p), rem0, pq.construction_progress[p], prog0])


func test_defer_count_and_total_limits() -> void:
	var g: JWGame = _game()
	var p: int = _launch(g)
	if p < 0:
		return
	var st: JWSimState = _st(g)
	var pq: JWProjectQueue = st.projects
	eq_int(st.params[JWUnits.Param.MAX_DEFER_COUNT], 2, "夹具前提：延期次数上限 2")
	eq_int(st.params[JWUnits.Param.MAX_DEFER_QUARTERS], 8, "夹具前提：累计上限 8 季")

	# 累计超限：一次 9 季（形状合法，≤ 16）→ 前置条件拒绝，状态不变。
	var memo0: int = st.treasury.committed_memo
	g.submit_command(JWCommands.Kind.PROJECT_DEFER, _args([_st(g).projects.entity[p], 9]))
	_advance(g)
	eq_int(_last_result(g, JWCommands.Kind.PROJECT_DEFER), JWResult.Reject.PRECONDITION, "累计 9 季 > 8 ⇒ 拒绝")
	eq_int(pq.defer_count[p], 0, "被拒不计次数")
	eq_int(pq.defer_fee[p], 0, "被拒不收赔偿")
	check(pq.suspension_reason[p] != JWUnits.SuspendReason.DEFERRED, "被拒不挂起")
	check(st.treasury.committed_memo <= memo0, "承诺只因履约付款减少")

	# 第一次：3 季，受理。
	g.submit_command(JWCommands.Kind.PROJECT_DEFER, _args([_st(g).projects.entity[p], 3]))
	_advance(g)
	eq_int(_last_result(g, JWCommands.Kind.PROJECT_DEFER), 0, "第一次延期受理")
	# 延期中再延 → 拒绝。
	g.submit_command(JWCommands.Kind.PROJECT_DEFER, _args([_st(g).projects.entity[p], 1]))
	_advance(g)
	eq_int(_last_result(g, JWCommands.Kind.PROJECT_DEFER), JWResult.Reject.PRECONDITION, "延期中不能再延")
	_advance(g)
	# 到期复工后第二次：5 季（累计 8），受理。
	g.submit_command(JWCommands.Kind.PROJECT_DEFER, _args([_st(g).projects.entity[p], 5]))
	_advance(g)
	eq_int(_last_result(g, JWCommands.Kind.PROJECT_DEFER), 0, "复工后第二次延期受理（累计 8 季）")
	eq_int(pq.defer_count[p], 2, "次数 2")
	eq_int(pq.defer_q_total[p], 8, "累计 8 季")
	var k: int = 0
	while k < 5:
		_advance(g)
		k += 1
	check(pq.suspension_reason[p] != JWUnits.SuspendReason.DEFERRED, "第二次延期到期复工")
	# 第三次：次数已满 → 拒绝。
	g.submit_command(JWCommands.Kind.PROJECT_DEFER, _args([_st(g).projects.entity[p], 1]))
	_advance(g)
	eq_int(_last_result(g, JWCommands.Kind.PROJECT_DEFER), JWResult.Reject.PRECONDITION, "次数已满 ⇒ 拒绝")
	eq_int(pq.defer_count[p], 2, "次数仍为 2")


func test_cancel_during_deferral_and_save_roundtrip() -> void:
	var g: JWGame = _game()
	var p: int = _launch(g)
	if p < 0:
		return
	g.submit_command(JWCommands.Kind.PROJECT_DEFER, _args([_st(g).projects.entity[p], DEFER_Q]))
	_advance(g)
	eq_int(_last_result(g, JWCommands.Kind.PROJECT_DEFER), 0, "延期受理")
	var st: JWSimState = _st(g)

	# 存档 → 另一实例读档：延期字段随存档往返，读档后继续推进与直接推进逐位一致。
	var rs: JWResult = g.save_game("defer_test")
	check(rs == null or rs.ok, "存档成功")
	var g2: JWGame = JWGame.new()
	g2.autosave_slot = "autosave_test"
	g2.new_game("res://content", 1_000_000, 40)
	var rl: JWResult = g2.load_game("defer_test")
	check(rl == null or rl.ok, "读档成功")
	var st2: JWSimState = _st(g2)
	eq_int(st2.projects.defer_until_q[p], st.projects.defer_until_q[p], "读档后到期季一致")
	eq_int(st2.projects.defer_fee[p], st.projects.defer_fee[p], "读档后赔偿一致")
	_advance(g)
	_advance(g2)
	check(st2.state_hash() == st.state_hash(), "读档后推进一季，与直接推进逐位一致")

	# 延期中取消：合法（SUSPENDED → CANCELLED），释放槽位，剩余承诺冲销。
	g.submit_command(JWCommands.Kind.PROJECT_CANCEL, _args([_st(g).projects.entity[p]]))
	_advance(g)
	eq_int(_last_result(g, JWCommands.Kind.PROJECT_CANCEL), 0, "延期中可以取消")
	eq_int(st.projects.status[p], JWUnits.ProjectStatus.CANCELLED, "已取消")
	eq_int(st.projects.slot_held[p], 0, "取消释放槽位")
