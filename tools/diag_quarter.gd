## 诊断：载入出厂内容 → 空命令推进 N 季，第一次故障时打印故障码与调用栈。
## 用法：godot --headless --path <根> --script res://tools/diag_quarter.gd -- [季数] [种子]
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 2
	var seed_v: int = int(args[1]) if args.size() > 1 else 1000000
	JWResult.trace_faults = true
	JWResult.clear_pending()
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all("res://content", st)
	if res == null or not res.ok:
		print("load failed code=%d" % (res.code if res != null else -1))
		for i: int in loader.errors.size():
			print("  code=%d @ %s" % [loader.errors[i].code, loader.error_where(i)])
		quit(1)
		return
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
	st.rng.set_state_scalar(0, seed_v)
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	JWResult.clear_pending()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	var args0: PackedInt64Array = PackedInt64Array()
	args0.resize(JWCommands.ARG_SLOTS)
	for q: int in n_q:
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, args0, q, st.policy_defs)
		var t0: int = Time.get_ticks_usec()
		var code: int = runner.advance_quarter(cmds)
		var ms: int = int((Time.get_ticks_usec() - t0) / 1000)
		var cash: int = st.accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH))
		print("q=%d -> code=%d (%d ms) | 国库现金 %s U | 欠付 %s U | 本季基本支出 %s U | 执政 %d | 终止 %s/%d" % [
				q, code, ms, _u(cash), _u(st.treasury.arrears), _u(st.treasury.f_primary_paid),
				st.politics.mandate_status, str(st.politics.run_terminated), st.politics.termination_reason])
		print("      融资：债务余额 %s ｜ 批次数 %d ｜ 投资池现金 %s ｜ 外部额度 已用/上限 %s/%s" % [
				_u(st.bonds.debt_outstanding()), st.bonds.count,
				_u(st.accounts.cash_of(JWIds.AGENT_INVPOOL)),
				_u(st.world.credit_used), _u(st.world.credit_limit)])
		print("      收入：个税 %s ｜ 企业税 %s ｜ 其他 %s" % [_u(st.treasury.f_receipts_income_tax),
				_u(st.treasury.f_receipts_profit_tax), _u(st.treasury.f_receipts_other)])
		var names: PackedStringArray = PackedStringArray(["偿债", "公职工资", "法定转移", "服务运行费", "项目合同", "采购", "补贴", "相机支出"])
		var line: String = "      新增欠付按线："
		for k: int in st.treasury.f_arrears_added.size():
			if st.treasury.f_arrears_added[k] != 0:
				line += " %s=%s" % [names[k] if k < names.size() else str(k), _u(st.treasury.f_arrears_added[k])]
		print(line)
		var gcash: int = 0
		for g: int in JWUnits.GROUP:
			gcash += st.accounts.cash_of(JWIds.agent_of_group(g))
		var ccash: int = 0
		for c: int in JWUnits.CELL:
			ccash += st.accounts.cash_of(JWIds.agent_of_cell(c))
		print("      居民：工资 %s ｜ 财产 %s ｜ 转移 %s ｜ 消费 %s ｜ 个税实缴 %s ｜ 季末现金 %s" % [
				_u(JWMath.sum(st.pop.f_wage_income)), _u(JWMath.sum(st.pop.f_property_income)),
				_u(JWMath.sum(st.pop.f_transfer_income)), _u(JWMath.sum(st.pop.f_consumption)),
				_u(JWMath.sum(st.pop.f_income_tax_paid)), _u(gcash)])
		var dem: String = "      市场（需求/成交/未满足，按产品）："
		for s_i: int in JWUnits.S:
			var d_: int = 0
			var t_: int = 0
			var u_: int = 0
			for b: int in JWUnits.BUYER_CLASS_N:
				d_ += st.inventory.m_demand[JWIds.idx_market(s_i, b)]
				t_ += st.inventory.m_traded[JWIds.idx_market(s_i, b)]
				u_ += st.inventory.m_unmet[JWIds.idx_market(s_i, b)]
			dem += " [%d] %s/%s/%s" % [s_i, _q(d_), _q(t_), _q(u_)]
		print(dem)
		var prod: String = "      产量（计划/实际，Q）："
		for s_j: int in JWUnits.S:
			var pl: int = 0
			var ac: int = 0
			for r_j: int in JWUnits.R:
				pl += st.sectors.f_output_plan[JWIds.idx_cell(r_j, s_j)]
				ac += st.sectors.f_output_actual[JWIds.idx_cell(r_j, s_j)]
			prod += " [%d] %s/%s" % [s_j, _q(pl), _q(ac)]
		print(prod)
		if q == 1:
			var bn: PackedStringArray = PackedStringArray(["计划", "产能", "劳动", "能源", "材料"])
			for c_k: int in JWUnits.CELL:
				print("        cell %2d 约束=%s  计划 %s 产能 %s 劳动 %s 能源 %s 材料 %s" % [c_k,
						bn[st.sectors.f_binding_code[c_k]] if st.sectors.f_binding_code[c_k] < 5 else "?",
						_q(st.sectors.f_bound_plan[c_k]), _q(st.sectors.f_bound_capacity[c_k]),
						_q(st.sectors.f_bound_labor[c_k]), _q(st.sectors.f_bound_energy[c_k]),
						_q(st.sectors.f_bound_materials[c_k])])
				var inv_line: String = "          投入存量:"
				for j_k: int in JWUnits.S:
					inv_line += " %s" % _q(st.inventory.inv_input[JWIds.idx_inv(c_k, j_k)])
				print(inv_line)
		print("      企业：税前利润 %s ｜ 季末现金 %s ｜ 应收税款 %s" % [
				_u(JWMath.sum(st.sectors.f_profit_pretax)), _u(ccash), _u(st.treasury.tax_receivable)])
		if code != JWResult.OK:
			quit(1)
			return
	print("OK: %d 季无故障" % n_q)
	quit(0)


## μU → 「x.xxx U」展示（诊断脚本属 tools/，允许浮点格式化）。
func _u(v: int) -> String:
	return "%.3f" % (float(v) / 1_000_000_000.0)


func _q(v: int) -> String:
	return "%.2f" % (float(v) / 1_000_000.0)
