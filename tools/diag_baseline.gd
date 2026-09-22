## 基年校准仪表盘：无命令推进 N 季，逐季并排打印「模型实测 vs 基年核算目标」。
##
## 用法：godot --headless --path <根> --script res://tools/diag_baseline.gd -- [季数=4] [种子] [市场季号,…] [noshock]
##
## 目标值取自 content/scenarios/chengwan/io_table.json 的 _note_base_year_accounting
## 与 population_init.json 的 _note_derived_check。诊断脚本属于 tools/，可以读注释键做对照，
## 但这些注释键**永远不是 SimCore 的事实来源**（docs/11 §5.15.1 第 4 条）。
## 计划书 §14 校准第一步：「先无冲击运行：检查基线是否因计算错误自行崩溃，而不是强迫所有变量恒定。」
extends SceneTree

const U: float = 1_000_000_000.0

var _t: Dictionary = {}
## 预算审查的滚动 4 季累计（收入 / 支出），审查季清零。
var _acc_rev: int = 0
var _acc_out: int = 0


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 4
	var seed_v: int = int(args[1]) if args.size() > 1 else 1000000
	# 第三个参数：逗号分隔的季号，打印这些季的分部门市场拆解（默认 0,1）。
	var show_q: PackedInt64Array = PackedInt64Array([0, 1])
	if args.size() > 2:
		show_q = PackedInt64Array()
		for t: String in args[2].split(","):
			show_q.append(int(t))
	_load_targets()

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
	# 第四个参数 noshock：计划书 §14 校准第一步「先无冲击运行」——把三类冲击的到达率置 0（只改本诊断进程）。
	if args.size() > 3 and args[3] == "noshock":
		st.shocks.hazard_ppm.fill(0)
		print("（无冲击模式：三类冲击到达率置 0）")
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	JWResult.clear_pending()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)

	print("")
	print("指标（U/季）            目标 │ " + _cols(n_q))
	var rows: Dictionary = {}
	for q: int in n_q:
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		var code: int = runner.advance_quarter(cmds)
		if code != JWResult.OK:
			print("第 %d 季推进返回 %d，停止；终局原因 %d（JWUnits.Termination）" % [q, code,
					st.politics.termination_reason])
			n_q = q
			break
		_collect(st, rows)
		if show_q.has(q):
			_print_market(st, q)
	_print_rows(rows, n_q)
	quit(0)


func _load_targets() -> void:
	var io: Dictionary = _json("res://content/scenarios/chengwan/io_table.json")
	var acc: Dictionary = io.get("_note_base_year_accounting", {})
	var fu: Dictionary = acc.get("final_use_uu", {})
	var ac: Dictionary = acc.get("accounting_checks", {})
	_t["GDP"] = _q(ac.get("gdp_production_uu", {}).get("total_uu", 0))
	_t["C 居民消费"] = _q(fu.get("household_consumption", {}).get("total_uu", 0))
	_t["G 公共产出"] = _q(fu.get("government_nonmarket_output", {}).get("total_uu", 0))
	_t["I 资本形成"] = _q(fu.get("gross_capital_formation", {}).get("total_uu", 0))
	_t["X 出口"] = _q(fu.get("exports", {}).get("total_uu", 0))
	_t["M 进口"] = _q(fu.get("imports", {}).get("total_uu", 0))
	var pop: Dictionary = _json("res://content/scenarios/chengwan/population_init.json")
	var inc: Dictionary = pop.get("_note_derived_check", {}).get("base_income_identity_uu_per_q", {})
	_t["居民工资"] = float(int(inc.get("wage", 0))) / U
	_t["居民经营分配"] = float(int(inc.get("business_distribution", 0))) / U
	_t["居民转移"] = float(int(inc.get("transfer", 0))) / U
	_t["个税"] = float(int(inc.get("income_tax_paid", 0))) / U


func _json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v: Variant = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}


## 年值（μU）→ 季值（U）
func _q(v: Variant) -> float:
	return float(int(v)) / U / 4.0


func _collect(st: JWSimState, rows: Dictionary) -> void:
	var d: JWDiagnostics = st.diag
	var e: PackedInt64Array = d._agg_exp
	var g_out: int = 0
	for r: int in JWUnits.PUBSERV:
		g_out += st.capital.f_pub_output[r]
	_push(rows, "GDP", d.gdp_production)
	_push(rows, "C 居民消费", e[JWUnits.ExpClass.C])
	_push(rows, "G 公共产出", g_out)
	_push(rows, "I 资本形成", e[JWUnits.ExpClass.I])
	_push(rows, "X 出口", st.world.f_exports_uu)
	_push(rows, "M 进口", st.world.f_imports_uu)
	_push(rows, "价差", st.inventory.price_variance_total())
	_push(rows, "居民工资", JWMath.sum(st.pop.f_wage_income))
	_push(rows, "居民经营分配", JWMath.sum(st.pop.f_property_income))
	_push(rows, "居民转移", JWMath.sum(st.pop.f_transfer_income))
	_push(rows, "个税", st.treasury.f_receipts_income_tax)
	_push(rows, "企业税", st.treasury.f_receipts_profit_tax)
	_push(rows, "政府基本支出", st.treasury.f_primary_paid)
	_push(rows, "　公职工资", st.treasury.f_pay_public_wages)
	_push(rows, "　法定转移", JWMath.sum(st.treasury.f_pay_transfers))
	_push(rows, "　公服运营", JWMath.sum(st.treasury.f_pay_opex))
	_push(rows, "　政府采购", st.treasury.f_pay_procurement)
	_push(rows, "　补贴", JWMath.sum(st.treasury.f_pay_subsidies))
	_push(rows, "利息支出", st.treasury.f_interest_paid)
	_push(rows, "非税收入", st.treasury.f_receipts_other)
	_push(rows, "新增借款", st.treasury.f_new_borrowing)
	_push(rows, "企业税前利润", JWMath.sum(st.sectors.f_profit_pretax))
	_push(rows, "国库现金", st.accounts.cash_of(JWIds.AGENT_GOV))
	_push(rows, "债务余额", st.bonds.debt_outstanding())
	_push(rows, "欠付", st.treasury.arrears)
	# 政治（×1e9 以便同列显示：1.00 == 1 000 000 ppm == 100%）
	_push(rows, "全国支持度", st.politics.support_national_ppm(st.pop) * 1000)
	_push(rows, "席位(÷101)", JWPolitics.seat_rule(st.politics.support_national_ppm(st.pop),
			st.politics.seats_total) * 1_000_000_000 / maxi(1, st.politics.seats_total))
	var sa: int = 0
	var li: int = 0
	for g: int in JWUnits.GROUP:
		li += st.politics.living_index[g]
		for k: int in JWUnits.SERVICE_KIND:
			sa += st.pop.service_access[JWIds.idx_group_svc(g, k)]
	_push(rows, "服务可及(均)", sa / (JWUnits.GROUP * JWUnits.SERVICE_KIND) * 1000)
	_push(rows, "生活指数(均)", li / JWUnits.GROUP * 1000)
	_push(rows, "授权状态×1e9", st.politics.mandate_status * 1_000_000_000)
	# 预算审查口径（politics.review_and_terminate）：滚动 4 季（基本支出 + 利息 − 三项收入）/ 收入；
	# 只在审查季（q ≡ 3 mod 4）显示，限值 param.budget_review_deficit_limit_ppm（0.15）。
	_acc_rev += st.treasury.f_receipts_income_tax + st.treasury.f_receipts_profit_tax 			+ st.treasury.f_receipts_other
	_acc_out += st.treasury.f_primary_paid + st.treasury.f_interest_paid
	var q_done: int = st.q - 1
	if q_done % 4 == 3:
		_push(rows, "审查赤字率", (_acc_out - _acc_rev) * 1_000_000_000 / maxi(1, _acc_rev))
		_acc_rev = 0
		_acc_out = 0
	else:
		_push(rows, "审查赤字率", 0)
	_push(rows, "外部(row)现金", st.accounts.cash_of(JWIds.AGENT_ROW))
	_push(rows, "居民现金", _sum_group_cash(st))
	_push(rows, "企业现金", _sum_cell_cash(st))
	_push(rows, "投资池现金", st.accounts.cash_of(JWIds.AGENT_INVPOOL))
	var dep: int = 0
	var sav: int = 0
	for g2: int in JWUnits.GROUP:
		dep += st.accounts.get_balance(JWIds.idx_account(JWIds.agent_of_group(g2), JWIds.ACC_DEPOSIT_CLAIM))
		sav += st.pop.f_savings[g2]
	_push(rows, "居民存款", dep)
	_push(rows, "居民储蓄(流量)", sav)
	# 人口与劳动（万人，×1e9 以便同列显示：1.00 == 1 万人）
	var pop_age: PackedInt64Array = PackedInt64Array([0, 0, 0])
	for g: int in JWUnits.GROUP:
		pop_age[JWIds.age_of_group(g)] += st.pop.population[g]
	var lf: int = 0
	for r: int in JWUnits.R:
		for k: int in JWUnits.K:
			lf += st.pop.labor_force_region_skill(r, k)
	var emp_m: int = 0
	for ei: int in JWUnits.EMP_N:
		emp_m += st.labor.cell_employment[ei]
	var emp_p: int = JWMath.sum(st.labor.pub_employment)
	_push(rows, "人口·少年(万)", pop_age[0] * 100_000)
	_push(rows, "人口·劳动(万)", pop_age[1] * 100_000)
	_push(rows, "人口·老年(万)", pop_age[2] * 100_000)
	_push(rows, "劳动力(万)", lf * 100_000)
	_push(rows, "市场就业(万)", emp_m * 100_000)
	_push(rows, "公共就业(万)", emp_p * 100_000)
	var grid_t: int = 0
	var esup: int = 0
	var edem: int = 0
	var ecap: int = 0
	for r2: int in JWUnits.R:
		grid_t += st.capital.grid(r2)
		esup += st.sectors.f_elec_supply[r2]
		edem += st.sectors.f_elec_demand[r2]
		ecap += st.capital.cell_capacity(JWIds.idx_cell(r2, JWUnits.Sector.ENERGY))
	_push(rows, "电网容量(Q)", grid_t * 1000)
	_push(rows, "电网供电(Q)", esup * 1000)
	_push(rows, "用电需求(Q)", edem * 1000)
	_push(rows, "能源产能(Q)", ecap * 1000)
	var names: PackedStringArray = PackedStringArray(["农业", "制造", "能源", "服务"])
	for s: int in JWUnits.S:
		var out: int = 0
		for r: int in JWUnits.R:
			out += st.sectors.f_output_actual[JWIds.idx_cell(r, s)]
		# 产量按基价计值（μQ × 1e9 / 1e6），与金额同列展示
		_push(rows, "产量·" + names[s], JWMath.mul_div_floor(out, JWUnits.BASE_PRICE, JWUnits.Q_SCALE))
		_push(rows, "价格·" + names[s], st.pricing.price_of(s))


func _push(rows: Dictionary, key: String, v: int) -> void:
	if not rows.has(key):
		rows[key] = []
	(rows[key] as Array).append(v)


func _cols(n: int) -> String:
	var s: String = ""
	for q: int in n:
		s += "   q%-5d" % q
	return s


func _print_rows(rows: Dictionary, n: int) -> void:
	for key: String in rows.keys():
		var vals: Array = rows[key]
		var tgt: String = "      —"
		if _t.has(key):
			tgt = "%7.2f" % float(_t[key])
		var line: String = "%-18s %s │" % [key, tgt]
		for i: int in mini(n, vals.size()):
			var v: int = int(vals[i])
			if key.begins_with("价格"):
				line += "  %6.3f  " % (float(v) / U)
			else:
				line += " %8.2f" % (float(v) / U)
		print(line)


## 分部门、分买方类的供需拆解（Q）。
func _print_market(st: JWSimState, q: int) -> void:
	var names: PackedStringArray = PackedStringArray(["农业", "制造", "能源", "服务"])
	var cls: PackedStringArray = PackedStringArray(["居民", "公服", "政采", "企业投入", "出口", "资本品"])
	print("── 第 %d 季市场（需求/成交，Q） ──" % q)
	for s: int in JWUnits.S:
		var line: String = "  %s 供给 %6.2f │" % [names[s], float(st.inventory.m_supply[s]) / 1e6]
		for b: int in JWUnits.BUYER_CLASS_N:
			var mi: int = JWIds.idx_market(s, b)
			line += " %s %5.2f/%5.2f" % [cls[b], float(st.inventory.m_demand[mi]) / 1e6, float(st.inventory.m_traded[mi]) / 1e6]
		var pl: int = 0
		var ac: int = 0
		var bind: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0])
		for r: int in JWUnits.R:
			var c: int = JWIds.idx_cell(r, s)
			pl += st.sectors.f_output_plan[c]
			ac += st.sectors.f_output_actual[c]
			var bc: int = st.sectors.f_binding_code[c]
			if bc >= 0 and bc < 5:
				bind[bc] += 1
		line += " │ 计划 %5.2f 实产 %5.2f 约束[计划/产能/劳动/能源/材料]=%s" % [float(pl) / 1e6, float(ac) / 1e6, str(bind)]
		print(line)


func _sum_group_cash(st: JWSimState) -> int:
	var t: int = 0
	for g: int in JWUnits.GROUP:
		t += st.accounts.cash_of(JWIds.agent_of_group(g))
	return t


func _sum_cell_cash(st: JWSimState) -> int:
	var t: int = 0
	for c: int in JWUnits.CELL:
		t += st.accounts.cash_of(JWIds.agent_of_cell(c))
	return t
