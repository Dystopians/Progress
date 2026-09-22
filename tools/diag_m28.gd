## 部门资产负债诊断（docs/53 M2-8 标定）：无命令推进 N 季，每 step 季打印一行
## 「谁手里有钱、钱从哪来、实体经济在做什么」。用来定位长局自行衰退的漏损环节。
##
## 列：
##   现金存量：住户 / 企业 / 政府 / 外部 / 投资池（U）
##   本季流量：贸易差额（出口 − 进口）、货币发行（含外部补足）、政府盈余、企业留存变动（U）
##   实体：实际 GDP、消费、投资、就业率、工资中位、价格水平
##
## 用法：godot --headless --path <根> --script res://tools/diag_m28.gd -- [剧本=campaign_1600] [季数=200] [步=10] [种子=1] [nofinal]
## 只读诊断：不改任何规则，只把已结算状态换个角度打出来。
extends SceneTree

const U: float = 1_000_000_000.0
const ACC_STRIDE: int = JWUnits.ACCOUNT_CODE_N


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scen: String = args[0] if args.size() > 0 else "campaign_1600"
	var n_q: int = int(args[1]) if args.size() > 1 else 200
	var step: int = int(args[2]) if args.size() > 2 else 10
	var seed_v: int = int(args[3]) if args.size() > 3 else 1

	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var spec: String = "res://content" if scen == "chengwan" else "res://content#" + scen
	var res: JWResult = loader.load_all(spec, st)
	if res == null or not res.ok:
		print("载入失败：", res.code if res else -1)
		quit(1)
		return
	st.content_hash = loader.content_hash
	st.rng.set_state_scalar(0, seed_v)
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	loader.load_events_into(events, st)
	JWResult.clear_pending()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	JWResult.trace_faults = true
	if args.has("nofinal"):
		st.crisis.final_window_q = 1 << 40
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)

	print("季  ┃ 现金存量(U)：住户   企业   政府   外部  投资池 ┃ 本季(U)：贸易差 国内发行 外储补足 财政收 财政支 放款 还本 ┃ 实际GDP 失业% 价格水平 资本存量 投资 折旧 撞界 瓶颈分布")
	var bound: int = 0
	for q: int in n_q:
		var gov0: int = st.accounts.cash_of(JWIds.AGENT_GOV)
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		var code: int = runner.advance_quarter(cmds)
		if code != 0:
			print("第 %d 季推进失败：码 %d（终局 %s，原因 %d）" % [q, code, str(st.politics.run_terminated),
					st.politics.termination_reason])
			if st.politics.run_terminated:
				st.politics.run_terminated = false
				JWResult.clear_pending()
				continue
			break
		for s: int in JWUnits.S:
			var p: int = st.pricing.price[s]
			if p <= JWUnits.PRICE_MIN or p >= JWUnits.PRICE_MAX:
				bound += 1
		var trade: int = _trade_balance(st)
		if q % step == step - 1 or q == n_q - 1:
			var gov_in: int = 0
			var gov_out: int = 0
			var iss_dom: int = 0
			var iss_row: int = 0
			for i2: int in st.ledger.log_row_count():
				if st.ledger.l_kind[i2] != JWUnits.Kind.MONEY_ISSUE:
					continue
				var acc2: int = st.ledger.l_account[i2]
				var ag2: int = int(acc2 / ACC_STRIDE)
				if acc2 - ag2 * ACC_STRIDE != JWIds.ACC_CASH or st.ledger.l_delta[i2] <= 0:
					continue
				if ag2 == JWIds.AGENT_ROW:
					iss_row += st.ledger.l_delta[i2]
				else:
					iss_dom += st.ledger.l_delta[i2]
			var nrow: int = st.ledger.log_row_count()
			for i: int in nrow:
				var acc: int = st.ledger.l_account[i]
				var ag: int = int(acc / ACC_STRIDE)
				if ag != JWIds.AGENT_GOV or acc - ag * ACC_STRIDE != JWIds.ACC_CASH:
					continue
				var d: int = st.ledger.l_delta[i]
				if d > 0:
					gov_in += d
				else:
					gov_out -= d
			print(("%4d ┃ %6.1f %6.1f %6.1f %6.1f %6.1f ┃ %+7.2f %8.2f %8.2f %6.2f %6.2f %5.2f %5.2f ┃ %7.2f %5.1f %7.3f %8.1f %5.2f %5.2f %4d" % [
					q + 1,
					_cash_hh(st) / U, _cash_firms(st) / U, st.accounts.cash_of(JWIds.AGENT_GOV) / U,
					st.accounts.cash_of(JWIds.AGENT_ROW) / U, st.accounts.cash_of(JWIds.AGENT_INVPOOL) / U,
					trade / U, iss_dom / U, iss_row / U, gov_in / U, gov_out / U,
					JWMath.sum(st.credit.f_draw) / U, JWMath.sum(st.credit.f_repay) / U,
					st.diag.gdp_real / U, st.diag.unemployment_ppm / 1e4,
					st.money.price_level_ppm / 1e6,
					JWMath.sum(st.capital.cell_capital_value) / U,
					JWMath.sum(st.capital.f_cell_investment) / U,
					JWMath.sum(st.capital.f_cell_dep_uu) / U,
					bound]) + "  " + _binding_mix(st))
	# 末季的政府现金收支按类型拆开：找「随通胀扩大的结构性盈余」到底出在哪一类。
	var kin: Dictionary = {}
	var kout: Dictionary = {}
	for i: int in st.ledger.log_row_count():
		var acc: int = st.ledger.l_account[i]
		var ag: int = int(acc / ACC_STRIDE)
		if ag != JWIds.AGENT_GOV or acc - ag * ACC_STRIDE != JWIds.ACC_CASH:
			continue
		var kd: int = st.ledger.l_kind[i]
		var d: int = st.ledger.l_delta[i]
		if d > 0:
			kin[kd] = int(kin.get(kd, 0)) + d
		else:
			kout[kd] = int(kout.get(kd, 0)) - d
	var names: Dictionary = {}
	for k: String in JWUnits.Kind.keys():
		names[int(JWUnits.Kind[k])] = k
	print("── 末季政府现金收支（按类型，U）──")
	for kd2: int in kin.keys():
		print("   收 %-24s %8.3f" % [names.get(kd2, str(kd2)), int(kin[kd2]) / U])
	for kd3: int in kout.keys():
		print("   支 %-24s %8.3f" % [names.get(kd3, str(kd3)), int(kout[kd3]) / U])
	print("耗时 %d ms（%d 季）" % [Time.get_ticks_msec(), n_q])
	quit(0)


## 本季贸易差额：外部现金账上，出口收入减进口支出（从本季台账逐笔取，不另立账）。
static func _trade_balance(st: JWSimState) -> int:
	var t: int = 0
	var n: int = st.ledger.log_row_count()
	for i: int in n:
		var acc: int = st.ledger.l_account[i]
		var agent: int = int(acc / ACC_STRIDE)
		if agent != JWIds.AGENT_ROW or acc - agent * ACC_STRIDE != JWIds.ACC_CASH:
			continue
		# 外部现金减少 = 本国净出口。
		t -= st.ledger.l_delta[i]
	return t


## 十六个生产单元本季各自被什么卡住（数量分布）。
static func _binding_mix(st: JWSimState) -> String:
	var names: PackedStringArray = ["计划", "产能", "劳动", "电力", "投入", "其它"]
	var cnt: PackedInt64Array = PackedInt64Array()
	cnt.resize(names.size())
	cnt.fill(0)
	for c: int in JWUnits.CELL:
		var b: int = st.sectors.f_binding_code[c]
		cnt[b if b >= 0 and b < names.size() else names.size() - 1] += 1
	var parts: PackedStringArray = PackedStringArray()
	for i: int in names.size():
		if cnt[i] > 0:
			parts.append("%s%d" % [names[i], cnt[i]])
	return " ".join(parts)


static func _cash_hh(st: JWSimState) -> int:
	var t: int = 0
	for g: int in JWUnits.GROUP:
		t += st.accounts.cash_of(JWIds.agent_of_group(g))
	return t


static func _cash_firms(st: JWSimState) -> int:
	var t: int = 0
	for c: int in JWUnits.CELL:
		t += st.accounts.cash_of(JWIds.agent_of_cell(c))
	return t
