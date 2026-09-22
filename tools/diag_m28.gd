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
	if args.has("nofinal"):
		st.crisis.final_window_q = 1 << 40
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)

	print("季  ┃ 现金存量(U)：住户   企业   政府   外部  投资池 ┃ 本季(U)：贸易差 发行 财政收 财政支 放款 还本 ┃ 实际GDP 失业% 价格水平 撞界")
	var prev_issued: int = 0
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
		var issued: int = st.money.issued_total - prev_issued
		prev_issued = st.money.issued_total
		if q % step == step - 1 or q == n_q - 1:
			var gov_in: int = 0
			var gov_out: int = 0
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
			print("%4d ┃ %6.1f %6.1f %6.1f %6.1f %6.1f ┃ %+7.2f %6.2f %6.2f %6.2f %5.2f %5.2f ┃ %7.2f %5.1f %7.3f %4d" % [
					q + 1,
					_cash_hh(st) / U, _cash_firms(st) / U, st.accounts.cash_of(JWIds.AGENT_GOV) / U,
					st.accounts.cash_of(JWIds.AGENT_ROW) / U, st.accounts.cash_of(JWIds.AGENT_INVPOOL) / U,
					trade / U, issued / U, gov_in / U, gov_out / U,
					JWMath.sum(st.credit.f_draw) / U, JWMath.sum(st.credit.f_repay) / U,
					st.diag.gdp_real / U, st.diag.unemployment_ppm / 1e4,
					st.money.price_level_ppm / 1e6, bound])
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
