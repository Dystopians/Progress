## 对抗性验收套件 adversarial-c：时序（B 族）／政治（G 族）／存档（H 族）／外部账户（I 族）。
##
## 依据（**只依据契约，不读被测模块的实现**）：
##   docs/31_adversarial_tests.md §3 B 族、§8 G 族、§9 H 族、§10 I 族的全部用例；
##   docs/12_simulation_contract.md §0.6 三种失败语义（REJECT / ARREARS / FAULT，**没有第四种**）；
##   docs/10_variable_dictionary.md §14 的 INV-001..INV-152；
##   docs/11_data_contract.md §6（命令、存档、重放）与 §7（错误码）；
##   docs/17_api_skeleton.md §4 的接口签名；docs/18_rulings.md 的 R-SCALE-01。
##
## 立场（docs/31 §0.2）：每条断言的期望值只能来自契约文本，不得来自「实现现在是这样做的」。
## 若断言与实现冲突，以契约为准——**这条测试红了就是实现有缺陷，不是断言该放宽**。
##
## 夹具纪律（docs/31 §1 末尾）：本文件**不对任何 `state.*` 字段做赋值**。
## 需要构造局面时只走两类入口：(a) 契约登记的写入者方法（`set_credit_limit` 之类，
## 其契约写入者是 LOAD/S01，测试在此扮演 LOAD）；(b) §1.6 状态块协议的 `set_state_array`
## （JWSaves 读档走的同一条路）。`content.*` 类字段（class C）是内容包数据，按内容夹具处理。
extends JWTest

# ── 契约常量（逐条注明出处；**不从实现反推**） ─────────────────────────────

## docs/11 §5.15 首版必备参数默认值表：`param.trust_drop_ppm` / `param.trust_recover_ppm` = 80000 / 20000
const C_TRUST_DROP_PPM: int = 80_000
const C_TRUST_RECOVER_PPM: int = 20_000

## docs/10 §14.3 INV-127：选举只在 q ∈ {15, 31}
const C_ELECTION_Q_FIRST: int = 15
const C_ELECTION_Q_SECOND: int = 31
## docs/10 §14.3 INV-127：预算审查在 q ≡ 3 (mod 4)
const C_BUDGET_REVIEW_MOD: int = 4
const C_BUDGET_REVIEW_REM: int = 3

## docs/31 `ADV-G05`：席位总数是奇数（docs/17 §4.24 前置）。101 是本测试选的奇数样本。
const C_SEATS_TOTAL: int = 101

## docs/18 R-SCALE-01：1 U = 1 000 000 000 μU
const C_U: int = 1_000_000_000

## docs/31 `ADV-I02` 的额度样本（μU），取在 AMOUNT_MAX 之内
const C_CREDIT_LIMIT_UU: int = 1_000_000_000_000
## 分批发行的单笔额（μU）。C_CREDIT_LIMIT_UU / C_SMALL_TRANCHE_UU == 100 笔
const C_SMALL_TRANCHE_UU: int = 10_000_000_000
## 循环上限：实现若不累计额度，循环必须被这道闸拦住而不是把测试跑死
const C_LOOP_GUARD: int = 1_000

## docs/31 `ADV-I01` 的交付能力样本（μQ_s）
const C_DELIVERY_CAP_UQS: int = 1_000_000

## 冲击内容夹具：必然到达（hazard = 1e6 ppm）、强度与时长取定值，使 ADV-H01 的复用路径可判定
const C_SHOCK_HAZARD_PPM: int = 1_000_000
const C_SHOCK_MAG_PPM: int = 200_000
const C_SHOCK_DUR_Q: int = 4
## ADV-H01 的存档季
const C_SAVE_Q: int = 5

## 参数注册表（生成产物，docs/18 R-SCHEMA-01）
const C_PARAM_REGISTRY_PATH: String = "res://content/parameters/registry.json"

## docs/18 R-SCALE-01 连带要求 2 登记的 `content.io.capacity_per_capital_uu_ppm`
## （四部门序 AGRI/MANU/ENERGY/SERVICES，与 `content/scenarios/chengwan/io_table.json` 逐位相同）。
## docs/11 `V-IO-07` 要求该系数每部门 **> 0**：0 不是「还没填」，是不合法的内容包。
const C_CAPACITY_PER_CAPITAL_PPM: PackedInt64Array = [200, 180, 55, 160]


func before_each() -> void:
	# JWResult 的故障登记是静态的，会跨测试方法残留；不清会让后面的断言读到上一个测试的现场。
	JWResult.clear_pending()


func after_each() -> void:
	JWResult.clear_pending()


# ── 夹具辅助（全部只读或只走契约入口） ─────────────────────────────────────

## 一个已分配的权威状态：状态量（class S/F）全为契约初值（零／哨兵），
## 内容量（class C）只填**载入期硬性要求非零**的那一项，见 `_arm_io()`。
func _fresh_state() -> JWSimState:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	_arm_io(st.io)
	return st


## IO 内容夹具。`content.io.capacity_per_capital_uu_ppm` 是 class C，写入者 LOAD；
## 测试在此扮演 LOAD（与 `_arm_shocks()` 同一条夹具纪律，见本文件头部）。
##
## 为什么这一项非填不可：docs/10 §14 INV-132 与 docs/12 §10「载入后」一行要求读档后
## **立即跑一遍全部 P0 不变量**，其中 INV-056 的前置就是该系数 > 0（docs/11 `V-IO-07`）。
## 系数留 0 的状态不是「尚未载入内容的干净状态」，而是一份 `V-IO-07` 判不合法的内容包——
## 它写得出存档却**永远载不进来**，于是 H 族各条的「未被动过的存档必须能原样载入」对照组
## 测的就不再是 JWSaves 的往返能力。填 0 以外的值不放宽任何断言：
## 取值直接取自 docs/18 R-SCALE-01 登记的契约值，不是从实现反推的。
func _arm_io(io: JWIoTable) -> void:
	for s: int in JWUnits.S:
		io.capacity_per_capital_ppm[s] = C_CAPACITY_PER_CAPITAL_PPM[s]


## 一个已分配的命令缓冲。
func _fresh_cmds() -> JWCommands:
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	return cmds


## 一份已分配的政策定义表（JWCommands.submit 的形参，形状校验需要它）。
func _fresh_defs() -> JWPolicyDef:
	var defs: JWPolicyDef = JWPolicyDef.new()
	defs.allocate()
	return defs


## 冲击内容夹具：把三条冲击都配成「必然到达、定强度、定时长」。
## 这些字段是 class C（content.shock.*），写入者 LOAD；测试在此扮演 LOAD。
func _arm_shocks(sh: JWShocks) -> void:
	for k: int in JWUnits.SHOCK_N:
		sh.channel[k] = k
		sh.hazard_ppm[k] = C_SHOCK_HAZARD_PPM
		sh.earliest_q[k] = 0
		sh.min_gap_q[k] = 0
		sh.max_active[k] = 1
		sh.mag_min[k] = C_SHOCK_MAG_PPM
		sh.mag_max[k] = C_SHOCK_MAG_PPM
		sh.dur_min[k] = C_SHOCK_DUR_Q
		sh.dur_max[k] = C_SHOCK_DUR_Q
	for i: int in sh.target_weights_ppm.size():
		sh.target_weights_ppm[i] = JWUnits.PPM / JWUnits.S


## 删除一个存档槽位目录（测试之间互不污染）。
func _purge_slot(slot: String) -> void:
	var dir_path: String = JWSaves.SAVES_ROOT + slot + "/"
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		if not d.current_is_dir():
			d.remove(entry)
		entry = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(dir_path)


func _read_text(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt


func _write_text(path: String, txt: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(txt)
	f.close()
	return true


func _slot_file(slot: String, name: String) -> String:
	return JWSaves.SAVES_ROOT + slot + "/" + name


## 在 JSON 文本里定位 `"<key>": <literal>` 这一对，容忍冒号后有无空格两种写法。
## 找不到返回空串，由调用方断言（夹具前提失败必须说得出是哪一条）。
func _json_token(txt: String, key: String, literal: String) -> String:
	var spaced: String = "\"%s\": %s" % [key, literal]
	if txt.find(spaced) >= 0:
		return spaced
	var tight: String = "\"%s\":%s" % [key, literal]
	if txt.find(tight) >= 0:
		return tight
	return ""


## 取 state.json 里某个 base64 大数组（`enc: b64le64`）的原文，找不到返回空串。
func _b64_of(txt: String, array_id: String) -> String:
	var at: int = txt.find("\"%s\"" % array_id)
	if at < 0:
		return ""
	var key_at: int = txt.find("\"%s\"" % JWSimState.SAVE_KEY_DATA, at)
	if key_at < 0:
		return ""
	var open_q: int = txt.find("\"", key_at + JWSimState.SAVE_KEY_DATA.length() + 2)
	if open_q < 0:
		return ""
	var close_q: int = txt.find("\"", open_q + 1)
	if close_q < 0:
		return ""
	return txt.substr(open_q + 1, close_q - open_q - 1)


## 写一个存档并返回是否成功；失败时由调用方断言，错误信息里带上错误码。
func _save_slot(st: JWSimState, cmds: JWCommands, slot: String, saves: JWSaves) -> int:
	_purge_slot(slot)
	var r: JWResult = saves.save(st, cmds, slot)
	if r == null:
		return -1
	return r.code


## 构造一个内容加载器。`systems/content_loader.gd` 若当前无法编译（别的实现者正在改它），
## 返回 null 而不是让整个测试方法在 `.new()` 上崩掉——夹具的可用性不该决定断言的成败。
func _maybe_loader() -> JWContentLoader:
	var scr: Script = load("res://systems/content_loader.gd")
	if scr == null or not scr.can_instantiate():
		return null
	return scr.new() as JWContentLoader


## 读档对照组的诊断后缀：内容加载器不可用时，读档失败可能与篡改无关。
func _loader_note() -> String:
	if _maybe_loader() == null:
		return "（注意：systems/content_loader.gd 当前无法实例化，"\
				+ "本条的失败可能来自缺少 loader 而非存档本身）"
	return ""


## 读档并返回错误码（0 == 成功）。
func _load_slot(slot: String, saves: JWSaves) -> int:
	var st2: JWSimState = _fresh_state()
	var cmds2: JWCommands = _fresh_cmds()
	var r: JWResult = saves.load(slot, st2, cmds2, _maybe_loader())
	if r == null:
		return -1
	return r.code


# ══════════════════════════════════════════════════════════════════════════
# B 族：时序攻击（docs/31 §3）
# ══════════════════════════════════════════════════════════════════════════

## `ADV-B01` 同季两次推进。
## 检验 INV-012（八步单向推进，`state.time.q` 只在 S08 末 +1）、
##      INV-137（被拒命令仍入档且状态哈希不变）、docs/11 §6.1 kind 99
##      「每季恰好一条且为该季最后一条」。
func test_adv_b01_double_advance_in_one_quarter() -> void:
	var cmds: JWCommands = _fresh_cmds()
	var defs: JWPolicyDef = _fresh_defs()
	var empty: PackedInt64Array = PackedInt64Array()

	var r1: JWResult = cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, empty, 0, defs)
	var r2: JWResult = cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, empty, 0, defs)

	# docs/11 §6.1 规则 2：被拒命令也必须留在命令流里，否则重放无法复现「玩家试过但被挡住」。
	eq_int(cmds.count, 2, "INV-137 / docs/11 §6.1 规则 2：两条 advance_quarter 都必须入档（含被拒的那条）")
	# docs/11 §6.1 规则 1：(issued_q, command_id) 是全序主键，被拒命令也消耗序号，不跳号。
	eq_int(cmds.c_command_id[1] - cmds.c_command_id[0], 1,
			"docs/11 §6.1 规则 1：command_id 单调递增且不跳号（被拒命令同样消耗序号）")

	# 第一条必须被接受（它是本季合法的唯一推进标记）。
	check(r1 != null and r1.ok, "docs/11 §6.1：本季第一条 advance_quarter 是合法命令，不应被拒")

	# 防线可以落在 submit（形状／顺序）或 check_advance_marker（本季标记唯一性）任一处，
	# 但**必须有一处**以 E_COMMAND_ORDER 拒绝第二条。两处都放行 = ADV-B01 攻击成功。
	var second_rejected: bool = r2 != null and (not r2.ok) \
			and r2.code == JWResult.Reject.COMMAND_ORDER
	var marker_code: int = cmds.check_advance_marker(0)
	var marker_rejected: bool = marker_code == JWResult.Reject.COMMAND_ORDER
	check(second_rejected or marker_rejected,
			"ADV-B01：同季第二条 advance_quarter 必须被 E_COMMAND_ORDER 拒绝；"
			+ "实测 submit.code=%d、check_advance_marker=%d（docs/11 §6.1 kind 99）"
			% [0 if r2 == null else r2.code, marker_code])

	# 无论防线落在哪里，最终**至多一条** kind 99 被接受。
	cmds.validate_batch(0, defs)
	var accepted_markers: int = 0
	for i: int in cmds.count:
		if cmds.c_kind[i] == JWCommands.Kind.ADVANCE_QUARTER and cmds.c_accepted[i] == 1:
			accepted_markers += 1
	le_int(accepted_markers, 1,
			"docs/11 §6.1 kind 99：同一季被接受的 advance_quarter 至多一条（多于一条即生产结算两遍）")

	# INV-012 的静态锚点：q 只有一个写入点，且只在 S08 末生效。
	var st: JWSimState = _fresh_state()
	var q0: int = st.q
	eq_int(st.advance_quarter_index(), JWResult.Fault.PHASE_VIOLATION,
			"INV-012：phase != S08 时推进季号必须登记 PHASE_VIOLATION（q 只在 S08 末 +1）")
	eq_int(st.q, q0, "INV-012：被拒的季号推进不得改变 state.time.q")


## `ADV-B02` 结算中途插入命令。
## 检验 INV-013（每步只写其可写子集白名单）、INV-012（TIME 只在 S08 可写）、
##      INV-138（命令只写 pending_params 与命令日志，绝不改账）。
## 期望的核心：S06 征税**不得**能改政策参数——参数在 S02 冻结。
func test_adv_b02_settlement_step_write_scope() -> void:
	# IDLE 无写权：结算之外没有任何子系统可写。
	eq_int(JWUnits.WRITABLE_SUBSYS[JWUnits.Phase.IDLE], 0,
			"INV-013：phase == IDLE 时可写子集必须为空（结算之外不得有写入者）")

	# ADV-B02 的靶心：S05/S06/S07/S08 都不得写 POLICY 子系统，
	# 否则「S05 生产完、S06 征税前把税率改成 0」这条路径在结构上就是通的。
	var policy_bit: int = 1 << JWUnits.SUBSYS_POLICY
	for step: int in [JWUnits.Phase.S05, JWUnits.Phase.S06, JWUnits.Phase.S07,
			JWUnits.Phase.S08]:
		eq_int(JWUnits.WRITABLE_SUBSYS[step] & policy_bit, 0,
				"INV-013 / ADV-B02：第 S0%d 步不得写 SUBSYS_POLICY（政策参数在 S02 冻结，"
				% step + "docs/12 每步「可写子集」行）")
	# 政策只在 S02（受理）与 S04（budget_spent）可写——这是 INV-096 的结构前提。
	eq_int(JWUnits.WRITABLE_SUBSYS[JWUnits.Phase.S02] & policy_bit, policy_bit,
			"docs/12 S02「可写子集」：政策受理发生在 S02，SUBSYS_POLICY 必须可写")

	# INV-012 的机器形式：TIME 子系统只在 S08 可写。
	var time_bit: int = 1 << JWUnits.SUBSYS_TIME
	for step: int in range(JWUnits.Phase.IDLE, JWUnits.Phase.S08 + 1):
		var expect: int = time_bit if step == JWUnits.Phase.S08 else 0
		eq_int(JWUnits.WRITABLE_SUBSYS[step] & time_bit, expect,
				"INV-012：SUBSYS_TIME 只允许在 S08 被写（第 %d 步的掩码与此不符）" % step)

	# INV-036 的结构前提：债券簿只在「会动债券」的步骤可写。docs/18 第二轮裁定后是三步：
	#   S01 —— 流量整表清零（R-GUARD-01，只清本季应付流量，不碰批次存量）；
	#   S02 —— 付本息与到期再融资；
	#   S04 —— 付款前的预算内融资（R-FINANCE-01，只经 issue_debt 发**新**批次）。
	# 防旧债重定价的防线不在步骤掩码，而在债券簿的票息封印（ADV-C05 专测 INV-038）。
	# 其余步骤能写 BOND 仍是缺陷。
	var bond_bit: int = 1 << JWUnits.SUBSYS_BOND
	for step: int in range(JWUnits.Phase.IDLE, JWUnits.Phase.S08 + 1):
		var bond_step: bool = step == JWUnits.Phase.S01 or step == JWUnits.Phase.S02 				or step == JWUnits.Phase.S04
		var expect_bond: int = bond_bit if bond_step else 0
		eq_int(JWUnits.WRITABLE_SUBSYS[step] & bond_bit, expect_bond,
				"INV-036：SUBSYS_BOND 只允许在 S01/S02/S04 被写（docs/18 R-GUARD-01、R-FINANCE-01；第 %d 步的掩码与此不符）" % step)

	# INV-138：命令受理绝不改账。提交一批命令后权威状态必须逐位不变。
	var st: JWSimState = _fresh_state()
	var cmds: JWCommands = _fresh_cmds()
	var defs: JWPolicyDef = _fresh_defs()
	var h0: String = st.state_hash()
	cmds.submit(JWCommands.Kind.POLICY_ENACT,
			PackedInt64Array([0, 0, 0, 0, 0, JWCommands.FundingSource.CASH]), 0, defs)
	cmds.submit(JWCommands.Kind.ISSUE_BOND,
			PackedInt64Array([C_U, 8, JWUnits.Holder.INVPOOL]), 0, defs)
	eq_str(st.state_hash(), h0,
			"INV-138 / docs/11 §6.1 规则 4：命令只写 pending_params 与命令日志，"
			+ "受理命令后 state_hash 必须逐位不变")


## `ADV-B03` 立项当季取消、回收预留。
## 检验 INV-033（`reserved_memo ≤ cash` 且季末归零）、INV-032、INV-093
##      （取消不退已付、现金不增加）。
## 核心：`_memo_uu` 是表外备查量，释放预留**不产生任何账本分录**。
func test_adv_b03_reservation_is_off_balance_sheet() -> void:
	var st: JWSimState = _fresh_state()
	var tre: JWTreasury = st.treasury
	var acc: JWAccount = st.accounts

	var cash0: int = acc.cash_of(JWIds.AGENT_GOV)
	eq_int(tre.reserved_memo, 0, "docs/10 §5.2：`reserved_memo` 初值为 0")

	# 现金为 0 却要预留 1 μU：INV-033 不允许「先预留再想办法」。
	var code: int = tre.reserve(1, acc)
	ne_int(code, JWResult.OK,
			"ADV-B03 / INV-033：现金不足时预留必须被拒（三种失败语义里的 REJECT），"
			+ "不得静默记一笔表外预留")
	le_int(tre.reserved_memo, acc.cash_of(JWIds.AGENT_GOV),
			"INV-033：`reserved_memo ≤ cash` 恒成立——预留不是可以透支的额度")
	eq_int(acc.cash_of(JWIds.AGENT_GOV), cash0,
			"INV-033：被拒的预留不得改变现金（REJECT 语义要求状态完全不变）")

	# 释放预留是 memo 层的动作：季末归零，且**不得**让现金增加。
	var cash_before_release: int = acc.cash_of(JWIds.AGENT_GOV)
	tre.release_reservations()
	eq_int(tre.reserved_memo, 0, "INV-033：预留季末归零（要么执行要么释放）")
	eq_int(acc.cash_of(JWIds.AGENT_GOV), cash_before_release,
			"ADV-B03 / INV-093：释放预留不得增加现金——`reserved_memo` 是表外备查量，"
			+ "把它当真账户就是凭空造钱")
	eq_int(tre.committed_memo, 0,
			"INV-032：没有新签合同时 `committed_memo` 不得自行变动")


## `ADV-B04` 先小规模立项通过审核，再改大。
## 检验 INV-096（`budget_spent ≤ budget_committed`，超预留必须重新审核）、
##      docs/11 §6.1 kind 4 的 `scale_ppm` 范围校验、docs/17 §4.28
##      （形状与范围校验在 JWCommands，早于 S02 的语义校验）。
func test_adv_b04_project_scale_out_of_range_is_rejected() -> void:
	var cmds: JWCommands = _fresh_cmds()
	var defs: JWPolicyDef = _fresh_defs()

	# 对照组：一条**只有 scale_ppm 合法**、其余与实验组逐字相同的立项命令。
	# 它存在的唯一目的是让「范围校验确实被执行到」可判定：
	# 若实验组与对照组拿到同一个拒绝码，说明范围校验被前面的语义判定短路了。
	var in_range: PackedInt64Array = PackedInt64Array([0, 0, JWUnits.PPM,
			JWCommands.FundingSource.CASH])
	var r_ctrl: JWResult = cmds.submit(JWCommands.Kind.PROJECT_LAUNCH, in_range, 0, defs)

	# scale_ppm 是比率，值域 [0, 1e6]。10 倍放大 = 10e6，必须被范围校验挡住。
	var too_big: PackedInt64Array = PackedInt64Array([0, 0, 10 * JWUnits.PPM,
			JWCommands.FundingSource.CASH])
	var r_big: JWResult = cmds.submit(JWCommands.Kind.PROJECT_LAUNCH, too_big, 0, defs)
	check(r_big != null and not r_big.ok,
			"ADV-B04：scale_ppm = 10e6 超出 ppm 值域，必须被拒（不得先立项再说）")
	ne_int(r_big.code, r_ctrl.code,
			"docs/17 §4.28：范围校验属于 JWCommands 的职责且早于语义校验。"
			+ "越界的 scale_ppm 与合法的 scale_ppm 拿到同一个拒绝码（均为 %d），"
			% r_ctrl.code + "说明范围这一关根本没被执行到——玩家改大规模的路径是通的")
	eq_int(r_big.code, JWResult.Reject.PARAM_RANGE,
			"docs/31 ADV-B04：越界的 scale_ppm 必须给 E_PARAM_RANGE（1015），实测 %d"
			% r_big.code)

	var negative: PackedInt64Array = PackedInt64Array([0, 0, -1,
			JWCommands.FundingSource.CASH])
	var r_neg: JWResult = cmds.submit(JWCommands.Kind.PROJECT_LAUNCH, negative, 0, defs)
	eq_int(r_neg.code, JWResult.Reject.PARAM_RANGE,
			"docs/10 §0.8：负的 scale_ppm 是越界而不是「规模为 0」，必须 E_PARAM_RANGE")

	# funding_source 是闭枚举（docs/11 §6.1 kind 4）。自由取值即攻击面。
	var bad_funding: PackedInt64Array = PackedInt64Array([0, 0, JWUnits.PPM,
			JWCommands.FUNDING_SOURCE_N])
	var r_fund: JWResult = cmds.submit(JWCommands.Kind.PROJECT_LAUNCH, bad_funding, 0, defs)
	check(r_fund != null and not r_fund.ok,
			"ADV-B04 / docs/11 §4 规则 3：funding_source 是闭枚举，越界取值必须被拒")

	# 四条都被拒，但四条都必须留在命令流里（INV-137）。
	eq_int(cmds.count, 4, "INV-137：被拒的立项命令同样入档")


## `ADV-B05` 让生效季回溯到过去。
## 检验 INV-098（`effective_from_q` 单调不回溯）、INV-138（命令不得携带直接状态值）、
##      docs/31 §3「正向白名单优于负向黑名单」。
func test_adv_b05_effective_from_q_is_not_player_writable() -> void:
	# 结构性防线：命令只有 6 个固定语义的整数槽（docs/17 §4.28），槽位表里没有生效季。
	eq_int(JWCommands.ARG_SLOTS, 6, "docs/17 §4.28：命令参数固定 6 个整数槽")
	eq_int(JWCommands.SLOT_ENACT_FUNDING, 5,
			"docs/17 §4.28：policy_enact 的第 6 槽是 funding_source —— 6 个槽已被占满，"
			+ "没有留给 effective_from_q 的位置（INV-098）")

	var cmds: JWCommands = _fresh_cmds()
	var defs: JWPolicyDef = _fresh_defs()

	# 攻击：在合法载荷后面追加第 7 个槽，冒充 effective_from_q = 4（当前 q = 10）。
	var smuggled: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0,
			JWCommands.FundingSource.CASH, 4])
	var r: JWResult = cmds.submit(JWCommands.Kind.POLICY_ENACT, smuggled, 10, defs)
	check(r != null and not r.ok,
			"ADV-B05 / INV-138：命令携带白名单之外的参数槽必须被拒——"
			+ "正向白名单（args 键必须在该 kind 的 player_params 内）优于负向黑名单")
	eq_int(r.code, JWResult.Reject.DIRECT_STATE_WRITE,
			"INV-138：夹带生效季属于「命令携带直接状态值」，拒绝码必须是 E_DIRECT_STATE_WRITE")

	# 被拒之后命令流仍完整，且没有任何状态被改（INV-137）。
	var st: JWSimState = _fresh_state()
	var h0: String = st.state_hash()
	cmds.submit(JWCommands.Kind.POLICY_SET_PARAMS, smuggled, 10, defs)
	eq_str(st.state_hash(), h0,
			"INV-137：被拒命令必须让状态哈希逐位不变（拒绝是「纯」的）")
	eq_int(cmds.count, 2, "INV-137：两条被拒的回溯命令都必须入档并记原因码")


# ══════════════════════════════════════════════════════════════════════════
# G 族：政治攻击（docs/31 §8）
# ══════════════════════════════════════════════════════════════════════════

## `ADV-G01` 一次性补贴刷支持率。
## 检验 INV-121（生活／预期／信任分开存储，禁止合成单一「满意度」）、
##      INV-122（`trust_ppm` 的更新式中**结构上不存在** transfer_income 通道；
##      且 `trust_recover_ppm < trust_drop_ppm`）。
func test_adv_g01_trust_has_no_transfer_income_channel() -> void:
	# INV-121：四个主观量必须是四条独立的状态数组，各有各的稳定 ID。
	var ids: PackedStringArray = JWPolitics.STATE_ARRAY_IDS
	for wanted: String in ["state.group.living_index_ppm", "state.group.expectation_ppm",
			"state.group.trust_ppm", "state.group.support_ppm"]:
		check(ids.has(wanted),
				"INV-121：%s 必须作为独立的状态数组存在（三分量禁止被合并）" % wanted)

	# INV-121 的反面：全状态注册表里不得出现任何「满意度」合成字段。
	var st: JWSimState = _fresh_state()
	var synthesized: String = ""
	for e: int in st.registry_size():
		var id: String = st.registry_id(e)
		if id.findn("satisfaction") >= 0:
			synthesized = id
			break
	eq_str(synthesized, "",
			"INV-121：SimCore 内禁止合成单一「满意度」字段；注册表里出现了 \"%s\"" % synthesized)

	# INV-122 的结构检查：信任更新函数的入参里不得有任何转移支付／补助通道。
	# docs/17 §4.24 的签名是 update_subjective(pop, pricing, breach_count_by_group, params)。
	var allowed: PackedStringArray = PackedStringArray(["pop", "pricing",
			"breach_count_by_group", "params"])
	var found_signature: bool = false
	for m: Dictionary in st.politics.get_method_list():
		if String(m.get("name", "")) != "update_subjective":
			continue
		found_signature = true
		var args: Array = m.get("args", [])
		for a: Dictionary in args:
			var an: String = String(a.get("name", ""))
			check(allowed.has(an),
					"INV-122：信任更新式的入参只能是 %s；出现了 \"%s\" —— "
					% [str(allowed), an]
					+ "多一个通道就等于「发钱即赢」，docs/31 ADV-G01 的失败诊断第一条")
	check(found_signature,
			"docs/17 §4.24：JWPolitics 必须提供 update_subjective（INV-121 的三分量分开更新点）")

	# INV-122 的非对称：恢复慢于下降。参数卡是这条不变量的加载期落地点（docs/11 §7.1）。
	check(C_TRUST_RECOVER_PPM < C_TRUST_DROP_PPM,
			"INV-122：docs/11 §5.15 登记的默认值必须满足 recover(%d) < drop(%d)"
			% [C_TRUST_RECOVER_PPM, C_TRUST_DROP_PPM])
	var cards: Dictionary = _param_cards()
	check(cards.has("param.trust_drop_ppm") and cards.has("param.trust_recover_ppm"),
			"INV-122：`param.trust_drop_ppm` 与 `param.trust_recover_ppm` 必须各有一张参数身份证，"
			+ "否则加载期的 recover < drop 交叉校验（docs/11 §7.1）无处可做")
	if cards.has("param.trust_drop_ppm") and cards.has("param.trust_recover_ppm"):
		check(int(cards["param.trust_recover_ppm"]) < int(cards["param.trust_drop_ppm"]),
				"INV-122：内容包登记的 trust_recover_ppm 必须严格小于 trust_drop_ppm")


## 读参数注册表（生成产物，docs/18 R-SCHEMA-01）里的 parameter_id → value。
func _param_cards() -> Dictionary:
	var out: Dictionary = {}
	var txt: String = _read_text(C_PARAM_REGISTRY_PATH)
	if txt == "":
		return out
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = parsed
	var cards: Variant = d.get("cards", [])
	if typeof(cards) != TYPE_ARRAY:
		return out
	for c: Variant in cards:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cd: Dictionary = c
		var pid: String = String(cd.get("parameter_id", ""))
		if pid != "":
			out[pid] = cd.get("value", 0)
	return out


## `ADV-G02` 选举季前后套利。
## 检验 INV-127（选举只在 q ∈ {15, 31}；预算审查在 q ≡ 3 (mod 4)）、
##      INV-030（欠付恒等式：延期不得把欠付抹掉）。
## 判定的是「账没被藏掉」，不是「策略不许用」（docs/31 §8 原话）。
func test_adv_g02_election_and_budget_review_calendar() -> void:
	var st: JWSimState = _fresh_state()
	var p: JWPolitics = st.politics

	eq_int(p.next_election_q, C_ELECTION_Q_FIRST,
			"INV-127：首次选举季必须是 q = %d（docs/17 §4.24 初值）" % C_ELECTION_Q_FIRST)
	eq_int(C_ELECTION_Q_SECOND - C_ELECTION_Q_FIRST, 16,
			"INV-127：两次选举相隔 16 季（q ∈ {15, 31}）")

	eq_int(p.next_budget_review_q % C_BUDGET_REVIEW_MOD, C_BUDGET_REVIEW_REM,
			"INV-127：首次预算审查季必须满足 q ≡ 3 (mod 4)（docs/17 §4.24 初值 3），"
			+ "实测 %d" % p.next_budget_review_q)

	# 机制本身：把日历放到一个契约合法的审查季（走 §1.6 状态块协议，
	# 即 JWSaves 读档用的同一条写入路径，测试在此扮演 LOAD），再验证推进规则。
	var slot_idx: int = -1
	for i: int in JWPolitics.STATE_SCALAR_IDS.size():
		if JWPolitics.STATE_SCALAR_IDS[i] == "state.politics.next_budget_review_q":
			slot_idx = i
			break
	ge_int(slot_idx, 0,
			"docs/17 §1.6：`state.politics.next_budget_review_q` 必须是可存档的状态标量"
			+ "（跨季记忆留在类 L 里会让存档与直接推进分叉，INV-131/INV-133）")
	p.set_state_scalar(slot_idx, C_BUDGET_REVIEW_REM)
	var q_due: int = p.next_budget_review_q
	eq_int(q_due, C_BUDGET_REVIEW_REM, "夹具前提：审查季已置于 q = 3")

	# 审查季调用：置位，并把下一次推到 +4 季后（仍然 ≡ 3 mod 4）。
	p.mark_budget_review(q_due)
	eq_int(p.f_budget_review_due, 1,
			"docs/17 §4.24：审查季调用 mark_budget_review 必须置 f_budget_review_due")
	eq_int(p.next_budget_review_q, q_due + C_BUDGET_REVIEW_MOD,
			"INV-127：下一次预算审查 = 本次 + 4 季")
	eq_int(p.next_budget_review_q % C_BUDGET_REVIEW_MOD, C_BUDGET_REVIEW_REM,
			"INV-127：推进后的审查季仍必须 ≡ 3 (mod 4)")

	# 藏账攻击的账面侧：欠付恒等式的起点必须是可见的（INV-030）。
	eq_int(st.treasury.arrears, 0, "INV-030：开局欠付为 0，是后续恒等式的基准")
	var by_payee_sum: int = 0
	for i: int in st.treasury.arrears_by_payee.size():
		by_payee_sum += st.treasury.arrears_by_payee[i]
	eq_int(by_payee_sum, st.treasury.arrears,
			"INV-030：`arrears == Σ arrears_by_payee`，延期不得让总额与明细脱钩"
			+ "（脱钩就是 ADV-G02 的「把账藏起来」）")


## `ADV-G03` 用事件改账。
## 检验 INV-130（事件 `effects.target` 只能是六个主观量之一；
##      **事件不得直接写现金、库存、产能、人口，首版事件没有任何账本效应**）。
func test_adv_g03_events_cannot_touch_the_ledger() -> void:
	# 白名单是正向枚举，恰好 6 个（docs/10 §14.3 INV-130 逐字列出）。
	eq_int(JWEventEngine.TARGET_N, 6,
			"INV-130：事件效果目标白名单恰好 6 项（expectation / trust / support / "
			+ "org_power / stance / admin_capacity）")
	eq_int(JWEventEngine.TARGET_EXPECTATION_PPM, 0, "INV-130：白名单顺序是 schema 的一部分")
	eq_int(JWEventEngine.TARGET_ADMIN_CAPACITY_PPM, 5, "INV-130：白名单顺序是 schema 的一部分")

	var st: JWSimState = _fresh_state()
	var p: JWPolitics = st.politics
	var acc: JWAccount = st.accounts

	# 合法落点不得有任何账本效应：现金总量逐位不变。
	var cash0: int = acc.total_cash()
	p.apply_event_delta(JWPolitics.EVT_TRUST_PPM, 0, 10_000)
	eq_int(acc.total_cash(), cash0,
			"INV-130：首版事件没有任何账本效应——改信任不得让任何主体的现金变动")

	# 越界落点必须被拒，且不得改状态。
	for bad_target: int in [-1, JWEventEngine.TARGET_N, 99]:
		var h_before: String = st.subsystem_hash(JWUnits.SUBSYS_POLITICS)
		var code: int = p.apply_event_delta(bad_target, 0, 10_000)
		eq_int(code, JWResult.Fault.WRITE_OUT_OF_SCOPE,
				"INV-130：target = %d 不在六项白名单内，必须 WRITE_OUT_OF_SCOPE"
				% bad_target)
		eq_str(st.subsystem_hash(JWUnits.SUBSYS_POLITICS), h_before,
				"INV-130：被拒的事件落点不得留下半截写入（target = %d）" % bad_target)
		JWResult.clear_pending()

	# 组织影响力属于 JWInterestGroups，不是 JWPolitics 的落点（INV-125 的三套权力分离）。
	var h_org: String = st.subsystem_hash(JWUnits.SUBSYS_POLITICS)
	var code_org: int = p.apply_event_delta(JWEventEngine.TARGET_ORG_POWER_PPM, 0, 10_000)
	ne_int(code_org, JWResult.OK,
			"INV-125：org_power 由 JWInterestGroups 计算，JWPolitics 不得受理这个落点")
	eq_str(st.subsystem_hash(JWUnits.SUBSYS_POLITICS), h_org,
			"INV-125：被拒的越权落点不得改变政治子系统的哈希")


## `ADV-G04` 终局之后继续玩。
## 检验 INV-128（`run_terminated == true` 后任何 `advance_quarter` 返回 REJECT
##      且状态哈希不变；终局条件式中不含任何 GDP 项）。
func test_adv_g04_no_advance_after_termination() -> void:
	var st: JWSimState = _fresh_state()
	var p: JWPolitics = st.politics

	eq_int(int(p.run_terminated), 0, "夹具前提：开局未终止")

	# 走到 horizon 的最后一季：docs/17 §4.24「q == horizon_q − 1 ⇒ 终止」。
	p.review_and_terminate(st.treasury, st.pop, st.horizon_q - 1, st.horizon_q, 0, st.params)
	JWResult.clear_pending()
	check(p.run_terminated,
			"docs/12 §8.5：q == horizon_q − 1（%d）时必须终局" % (st.horizon_q - 1))
	ne_int(p.termination_reason, JWUnits.Termination.NONE,
			"docs/12 §8.5：终局必须带一个明确的原因码，不得是 NONE")

	# 终局后再点推进：REJECT，且状态逐位不变。
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	var cmds: JWCommands = _fresh_cmds()
	var h0: String = st.state_hash()
	var rejected: int = 0
	var first_code: int = 0
	for i: int in 10:
		var code: int = runner.advance_quarter(cmds)
		if i == 0:
			first_code = code
		if code == JWResult.Reject.RUN_TERMINATED:
			rejected += 1
	eq_int(rejected, 10,
			"INV-128：终局后连续 10 次 advance_quarter 必须全部返回 E_RUN_TERMINATED（1000）；"
			+ "实测只有 %d 次，首次返回码 %d —— 返回 0 意味着玩家点一下就能继续玩"
			% [rejected, first_code])
	eq_str(st.state_hash(), h0,
			"INV-128：终局后被拒的推进必须让 state_hash 逐位不变（结算档案可看，但状态不可推进）")


## `ADV-G05` 席位阈值边界微调。
## 检验 INV-126（`seat_rule` 是纯函数、整数、最大余数法、`0 ≤ seats_gov ≤ seats_total`）、
##      INV-003（最大余数法拆分，Σ 分项 == 总额）。
func test_adv_g05_seat_rule_is_pure_and_bounded() -> void:
	var samples: PackedInt64Array = PackedInt64Array([0, 1, 499_999, 500_000, 500_001,
			999_999, 1_000_000])
	var prev_seats: int = -1
	for s: int in samples:
		var seats: int = JWPolitics.seat_rule(s, C_SEATS_TOTAL)
		ge_int(seats, 0, "INV-126：支持度 %d ppm 不得算出负席位" % s)
		le_int(seats, C_SEATS_TOTAL,
				"INV-126：支持度 %d ppm 不得算出超过总席位（%d）的席位" % [s, C_SEATS_TOTAL])
		# 纯函数：同输入同输出，不读状态、不读随机数（否则 INV-014 的重放会分歧）。
		eq_int(JWPolitics.seat_rule(s, C_SEATS_TOTAL), seats,
				"INV-126：seat_rule 必须是纯函数，同输入两次调用必须同值（s = %d）" % s)
		# 最大余数法的和恒等：执政 + 在野 == 总席位。
		eq_int(seats + (C_SEATS_TOTAL - seats), C_SEATS_TOTAL,
				"INV-003 / INV-126：席位分配之和必须精确等于总席位（s = %d）" % s)
		ge_int(seats, prev_seats,
				"INV-126：席位对支持度必须单调不减（s = %d 处出现回落）" % s)
		prev_seats = seats

	eq_int(JWPolitics.seat_rule(0, C_SEATS_TOTAL), 0,
			"INV-126：支持度 0 ⇒ 0 席（比例 + 最大余数法的边界）")
	eq_int(JWPolitics.seat_rule(JWUnits.PPM, C_SEATS_TOTAL), C_SEATS_TOTAL,
			"INV-126：支持度 1e6 ppm ⇒ 全部席位")
	# 50% 支持率在奇数总席位上只能落在 (n−1)/2 或 (n+1)/2，不存在第三种整数解。
	in_range_int(JWPolitics.seat_rule(JWUnits.PPM / 2, C_SEATS_TOTAL),
			(C_SEATS_TOTAL - 1) / 2, (C_SEATS_TOTAL + 1) / 2,
			"INV-126：支持度恰好 50% 时席位必须落在 (n±1)/2 —— 别的取值说明没走最大余数法")

	# 越界输入不得给出越界席位（docs/10 §0.8：越界是缺陷，但不得用「随便返回」掩盖）。
	le_int(JWPolitics.seat_rule(2 * JWUnits.PPM, C_SEATS_TOTAL), C_SEATS_TOTAL,
			"INV-126：支持度越界时仍不得算出超过总席位的席位")
	ge_int(JWPolitics.seat_rule(-1, C_SEATS_TOTAL), 0,
			"INV-126：支持度为负时仍不得算出负席位")
	JWResult.clear_pending()


# ══════════════════════════════════════════════════════════════════════════
# H 族：存档攻击（docs/31 §9）
# ══════════════════════════════════════════════════════════════════════════

## `ADV-H01` 存档重载重抽已确定事件〔≡ 计划书点名 ⑥，别名 ADV-06〕。
## 检验 INV-109（S01 **先查 `shock_log` 再抽样**，已有记录则复用且**不推进计数器**）、
##      INV-133（save → load → advance 与 advance 的结果逐位相同）、
##      INV-131（存档含 6 个计数器与冲击记录）、INV-010。
func test_adv_h01_reload_cannot_reroll_a_resolved_shock() -> void:
	var params: PackedInt64Array = PackedInt64Array()
	params.resize(JWUnits.PARAM_N)
	params.fill(0)

	# 分支一：直接推进到 C_SAVE_Q 并抽样。
	var a: JWSimState = _fresh_state()
	_arm_shocks(a.shocks)
	a.rng.begin_quarter(C_SAVE_Q)
	var fa: int = a.shocks.resolve_quarter(a.rng, a.world, C_SAVE_Q, params)
	eq_int(fa, JWResult.OK, "夹具前提：S01 §01.6 的冲击结算不应报故障（实测码 %d）" % fa)
	var mag_a: PackedInt64Array = PackedInt64Array()
	for k: int in JWUnits.SHOCK_N:
		mag_a.append(a.shocks.magnitude(k))
	var draws_a: int = a.rng.draw_count_of(JWUnits.RngStream.SHOCK)
	var rows_a: PackedInt64Array = a.shocks.export_shock_log()
	ge_int(rows_a.size(), 1,
			"INV-109：每次冲击抽样都必须写 shock_log，否则读档后无从复用")

	# 分支二：save → load → advance。存档带回 shock_log 与 6 个计数器（INV-131）。
	var b: JWSimState = _fresh_state()
	_arm_shocks(b.shocks)
	var lr: JWResult = b.shocks.load_shock_log(rows_a)
	eq_int(lr.code, JWResult.OK, "INV-131：冲击记录必须能原样灌回（实测码 %d）" % lr.code)
	b.rng.set_state_array(0, a.rng.state_array(0))
	eq_int(b.rng.draw_count_of(JWUnits.RngStream.SHOCK), draws_a,
			"INV-131：存档必须带回 6 条随机流的计数器，读档后逐位相同")
	b.rng.begin_quarter(C_SAVE_Q)
	var fb: int = b.shocks.resolve_quarter(b.rng, b.world, C_SAVE_Q, params)
	eq_int(fb, JWResult.OK,
			"INV-109：复用 shock_log 的路径不得报故障（实测码 %d）" % fb)

	for k: int in JWUnits.SHOCK_N:
		eq_int(b.shocks.magnitude(k), mag_a[k],
				"INV-133 / ADV-06：读档后第 %d 号冲击的强度必须与直接推进逐位相同——"
				% k + "读档重来不能改变已经确定的抽样结果")
		eq_int(int(b.shocks.is_active(k)), int(a.shocks.is_active(k)),
				"INV-133：读档后第 %d 号冲击的激活状态必须一致" % k)
		eq_int(b.shocks.remaining(k), a.shocks.remaining(k),
				"INV-133：读档后第 %d 号冲击的剩余季数必须一致" % k)

	eq_int(b.rng.draws_this_quarter_of(JWUnits.RngStream.SHOCK), 0,
			"INV-109：本季已有 shock_log 记录时必须**复用**，"
			+ "rng.shock 的计数器一次也不许推进（推进了就说明读档真的重抽了）")
	eq_int(b.rng.draw_count_of(JWUnits.RngStream.SHOCK), draws_a,
			"INV-010：抽样是 f(root_seed, stream, q, index) 的计数器式函数，"
			+ "复用路径不得改变计数器")


## `ADV-H02` 直接篡改存档字段。
## 检验 INV-132（读档复算 `state_hash` 并比对，不符即 `E_SAVE_CORRUPT` 拒绝载入，
##      **不做尽力修复、不部分载入、不降级继续**）。
func test_adv_h02_tampered_save_is_rejected() -> void:
	var slot: String = "adv_h02"
	var st: JWSimState = _fresh_state()
	var cmds: JWCommands = _fresh_cmds()
	var saves: JWSaves = JWSaves.new()

	var save_code: int = _save_slot(st, cmds, slot, saves)
	eq_int(save_code, JWResult.OK, "夹具前提：存档必须写成功（实测码 %d）" % save_code)

	# 对照：**没被动过**的存档必须能原样载入。没有这条，下面的 E_SAVE_CORRUPT
	# 就可能是「什么档都载不进去」的假绿（docs/11 §6.6 的读档流程是可往返的）。
	var clean_code: int = _load_slot(slot, saves)
	eq_int(clean_code, JWResult.OK,
			"INV-133 / docs/11 §6.6：刚写出的存档必须能原样载入（实测码 %d）——"
			% clean_code + "它是 ADV-H02 的对照组，不通过则下面的拒绝毫无鉴别力" + _loader_note())

	var state_path: String = _slot_file(slot, JWSaves.FILE_STATE)
	var txt: String = _read_text(state_path)
	var token: String = _json_token(txt, "state.politics.seats_total", "0")
	ne_int(int(token == ""), 1,
			"夹具前提：state.json 里应能定位到可篡改的标量条目 "
			+ "state.politics.seats_total（docs/11 §6.4）")
	if token == "":
		_purge_slot(slot)
		return
	check(_write_text(state_path, txt.replace(token, token.replace(" 0", " 777")
			.replace(":0", ":777"))),
			"夹具前提：篡改后的 state.json 必须能写回磁盘")

	var code: int = _load_slot(slot, saves)
	eq_int(code, JWResult.Load.SAVE_CORRUPT,
			"INV-132：state.json 被外部修改后 manifest.state_hash 复算必然不符，"
			+ "读档必须返回 E_SAVE_CORRUPT 并拒绝载入（实测码 %d）" % code)
	_purge_slot(slot)


## `ADV-H03` 篡改后重算哈希使之自洽。
## 检验 INV-132 的后半段（**载入后立即跑一遍全部 P0 不变量**）、
##      INV-018（全经济现金总量守恒）、INV-020（逐主体资产负债恒等式）。
## 这条才是 ADV-H02 的真正价值：哈希防的是意外损坏，不变量防的是逻辑不自洽。
func test_adv_h03_rehashed_tampered_save_is_still_rejected() -> void:
	var slot: String = "adv_h03"
	var st: JWSimState = _fresh_state()
	var cmds: JWCommands = _fresh_cmds()
	var saves: JWSaves = JWSaves.new()

	var hash_before: String = st.state_hash()
	var save_code: int = _save_slot(st, cmds, slot, saves)
	eq_int(save_code, JWResult.OK, "夹具前提：存档必须写成功（实测码 %d）" % save_code)
	var clean_code: int = _load_slot(slot, saves)
	eq_int(clean_code, JWResult.OK,
			"INV-133 / docs/11 §6.6：未被动过的存档必须能原样载入（实测码 %d），"
			% clean_code + "否则本条测试无法区分「抓住了篡改」与「什么档都载不进去」" + _loader_note())

	# 攻击第一步：把政府现金改成一个凭空的大数。account.balance 是 b64le64 大数组，
	# 直接在文本里换掉它的 data 串——不做 JSON 往返，避免整数被解析成浮点而改变别的字段。
	var state_path: String = _slot_file(slot, JWSaves.FILE_STATE)
	var raw: String = _read_text(state_path)
	var old_b64: String = _b64_of(raw, "account.balance")
	ne_int(int(old_b64 == ""), 1,
			"夹具前提：存档里必须有 account.balance 的 b64le64 数据（docs/10 §2.1 的 900 个余额）")
	if old_b64 == "":
		_purge_slot(slot)
		return
	var bal: PackedInt64Array = Marshalls.base64_to_raw(old_b64).to_int64_array()
	var gov_cash_idx: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	ge_int(bal.size(), gov_cash_idx + 1,
			"夹具前提：account.balance 的长度必须覆盖 gov.cash 下标")
	if bal.size() <= gov_cash_idx:
		_purge_slot(slot)
		return
	bal[gov_cash_idx] = bal[gov_cash_idx] + 9_000 * C_U
	var new_b64: String = Marshalls.raw_to_base64(bal.to_byte_array())
	check(_write_text(state_path, raw.replace(old_b64, new_b64)),
			"夹具前提：篡改后的 state.json 必须能写回磁盘")

	# 攻击第二步：把哈希重算成自洽的（玩家的「聪明」做法）。
	# 用同样的改动喂一份内存里的状态，取它的 state_hash 作为「重算后的哈希」。
	var doc: Dictionary = st.to_dict()
	var arrays: Dictionary = doc[JWSimState.SAVE_KEY_ARRAYS]
	var rec: Dictionary = arrays["account.balance"]
	rec[JWSimState.SAVE_KEY_DATA] = new_b64
	arrays["account.balance"] = rec
	doc[JWSimState.SAVE_KEY_ARRAYS] = arrays
	var scratch: JWSimState = _fresh_state()
	var fr: JWResult = scratch.from_dict(doc)
	eq_int(fr.code, JWResult.OK,
			"夹具前提：被篡改的状态在**形状**上仍然合法（实测码 %d）——"
			% fr.code + "本条测的正是「形状合法但账不自洽」")
	var rehashed: String = scratch.state_hash()
	check(rehashed != hash_before,
			"夹具前提：凭空多出 9000 U 现金后 state_hash 必然与原哈希不同")
	var man_path: String = _slot_file(slot, JWSaves.FILE_MANIFEST)
	var man_txt: String = _read_text(man_path)
	check(man_txt.find(hash_before) >= 0,
			"夹具前提：manifest.json 里应写着篡改前的 state_hash（docs/11 §6.3）")
	check(_write_text(man_path, man_txt.replace(hash_before, rehashed)),
			"夹具前提：重算后的哈希必须能写回 manifest")

	# 期望：哈希校验过得去，但载入后的 P0 不变量全查会抓住它。
	var code: int = _load_slot(slot, saves)
	ne_int(code, JWResult.OK,
			"INV-132 后半段：哈希自洽也必须被拒——凭空多出 9000 U 现金会同时破坏 "
			+ "INV-018（现金总量）与 INV-020（资产负债恒等式），"
			+ "「载入后立即跑全部 P0 不变量」不能只是文档里的一句话")
	check(code == JWResult.Load.BALANCE_INIT or code == JWResult.Load.CASH_TOTAL
			or code == JWResult.Load.ASSERT_TOLERANCE or code == JWResult.Load.SAVE_CORRUPT,
			"docs/31 ADV-H03：拒绝码必须落在 {E_BALANCE_INIT, E_CASH_TOTAL, "
			+ "E_ASSERT_TOLERANCE, E_SAVE_CORRUPT} 内，实测 %d" % code)
	_purge_slot(slot)


## `ADV-H04` 跨版本存档。
## 检验 INV-135（`schema_version` 高于上限 ⇒ 拒绝，不猜测）、
##      INV-134（`content_hash` 不符 ⇒ 只读检视模式；`build_id` 不符 ⇒ 可继续但
##      `replay_unreliable`）。**四种之外没有第五种（例如「静默继续」）。**
func test_adv_h04_cross_version_save_branches() -> void:
	var st: JWSimState = _fresh_state()
	var cmds: JWCommands = _fresh_cmds()

	# 分支一：schema_version 高于当前上限 ⇒ 拒绝。
	var slot_new: String = "adv_h04_new"
	var saves_new: JWSaves = JWSaves.new()
	eq_int(_save_slot(st, cmds, slot_new, saves_new), JWResult.OK,
			"夹具前提：存档必须写成功")
	var clean_code: int = _load_slot(slot_new, saves_new)
	eq_int(clean_code, JWResult.OK,
			"INV-133 / docs/11 §6.6：未被动过的存档必须能原样载入（实测码 %d）——"
			% clean_code + "它是本条三个分支共同的对照组" + _loader_note())
	var man_path: String = _slot_file(slot_new, JWSaves.FILE_MANIFEST)
	var man: String = _read_text(man_path)
	var ver_token: String = _json_token(man, JWSaves.MK_SCHEMA_VERSION,
			str(JWSaves.CURRENT_SCHEMA_VERSION))
	check(ver_token != "",
			"夹具前提：manifest 里应写着当前 schema_version（docs/11 §6.3）")
	_write_text(man_path, man.replace(ver_token,
			ver_token.replace(str(JWSaves.CURRENT_SCHEMA_VERSION),
			str(JWSaves.CURRENT_SCHEMA_VERSION + 1))))
	eq_int(_load_slot(slot_new, saves_new), JWResult.Load.SAVE_VERSION_TOO_NEW,
			"INV-135：schema_version 高于当前支持上限必须拒绝载入，不得尝试猜测向下兼容")
	_purge_slot(slot_new)

	# 分支二：content_hash 不符 ⇒ 只读检视模式（可看不可推进），不是静默继续。
	var slot_ch: String = "adv_h04_content"
	var saves_ch: JWSaves = JWSaves.new()
	eq_int(_save_slot(st, cmds, slot_ch, saves_ch), JWResult.OK, "夹具前提：存档必须写成功")
	var man_ch_path: String = _slot_file(slot_ch, JWSaves.FILE_MANIFEST)
	var man_ch: String = _read_text(man_ch_path)
	var ch_token: String = _json_token(man_ch, JWSaves.MK_CONTENT_HASH,
			"\"%s\"" % st.content_hash)
	check(ch_token != "",
			"夹具前提：manifest 里应写着 content_hash（docs/11 §6.3）")
	_write_text(man_ch_path, man_ch.replace(ch_token, ch_token.replace(
			"\"%s\"" % st.content_hash,
			"\"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\"")))
	_load_slot(slot_ch, saves_ch)
	check(saves_ch.read_only_required,
			"INV-134：content_hash 不符必须进入只读检视模式（可看不可推进），"
			+ "第五种「静默继续」不存在")
	_purge_slot(slot_ch)

	# 分支三：build_id 不符 ⇒ 可继续游玩，但置 replay_unreliable 并禁用重放验证。
	var slot_bid: String = "adv_h04_build"
	var saves_bid: JWSaves = JWSaves.new()
	eq_int(_save_slot(st, cmds, slot_bid, saves_bid), JWResult.OK, "夹具前提：存档必须写成功")
	var man_bid_path: String = _slot_file(slot_bid, JWSaves.FILE_MANIFEST)
	var man_bid: String = _read_text(man_bid_path)
	var bid_token: String = _json_token(man_bid, JWSaves.MK_BUILD_ID,
			"\"%s\"" % st.build_id)
	check(bid_token != "", "夹具前提：manifest 里应写着 build_id")
	_write_text(man_bid_path, man_bid.replace(bid_token, bid_token.replace(
			"\"%s\"" % st.build_id, "\"some-other-build/jingwei-0.0.1\"")))
	_load_slot(slot_bid, saves_bid)
	check(saves_bid.replay_unreliable,
			"INV-134：build_id 不符必须置 replay_unreliable（重放确定性只在同构建下承诺）")
	check_false(saves_bid.read_only_required,
			"INV-134：build_id 不符**不**进只读检视——三个分支的后果各不相同，不得混为一谈")
	_purge_slot(slot_bid)


## `ADV-H05` Save-scumming 市场结果。
## 检验 INV-010（`draw = f(root_seed, stream, q, index)`，与调用顺序无关）、
##      INV-009（随机流隔离：多触发一个事件不改变冲击）、INV-008（遍历按稳定 ID 升序）。
func test_adv_h05_sampling_is_independent_of_call_order() -> void:
	var st: JWSimState = _fresh_state()
	var rng: JWRngStreams = st.rng

	# 同一 (stream, q, index) 的取值是纯函数，读档后重算必然相同。
	var base: int = rng.draw_raw(JWUnits.RngStream.SHOCK, C_SAVE_Q, 3)
	eq_int(rng.draw_raw(JWUnits.RngStream.SHOCK, C_SAVE_Q, 3), base,
			"INV-010：draw_raw 必须是 f(root_seed, stream, q, index) 的纯函数")

	# 攻击：读档后插入一堆经济中性的动作（这里用 rng.event 的抽样代表「多写一句新闻」）。
	rng.begin_quarter(C_SAVE_Q)
	for i: int in 50:
		rng.draw_below(JWUnits.RngStream.EVENT, 1_000, 0)
	eq_int(rng.draw_raw(JWUnits.RngStream.SHOCK, C_SAVE_Q, 3), base,
			"INV-010 / ADV-H05：在别的流上抽 50 次之后，rng.shock 在同一 (q, index) 的取值"
			+ "必须逐位不变——否则 save-scumming 真的有效，且重放会分歧")
	eq_int(rng.draws_this_quarter_of(JWUnits.RngStream.SHOCK), 0,
			"INV-009：rng.event 抽 50 次不得推进 rng.shock 的计数器（流隔离）")
	eq_int(rng.draws_this_quarter_of(JWUnits.RngStream.EVENT), 50,
			"INV-011：每次抽样都记在自己的流上，计数必须与实际抽样次数一致")

	# 盐值确实把 6 条流分开了：两两不同是「结构性独立」的前提。
	# 盐值相同 ⇒ 两条流在同一 (q, index) 给出同一个数 ⇒ 多写一句新闻真的会改变经济抽样。
	var collisions: int = 0
	for i: int in JWUnits.RNG_STREAM_N:
		for j: int in range(i + 1, JWUnits.RNG_STREAM_N):
			if rng.salt[i] == rng.salt[j]:
				collisions += 1
	eq_int(collisions, 0,
			"INV-009：6 条随机流的盐值必须两两不同，实测有 %d 对相同（salt = %s）——"
			% [collisions, str(rng.salt)]
			+ "盐值相同会让两条流在同一 (q, index) 给出同一个数，"
			+ "计划书 §12「多写一句新闻也改变经济抽样」的风险就变成现实")
	ne_int(rng.draw_raw(JWUnits.RngStream.EVENT, C_SAVE_Q, 3), base,
			"INV-009 / INV-010：不同随机流在同一 (q, index) 不得给出同一个取值")

	# 计数器是完整的随机流状态（docs/11 §6.3）：同一 (q, index) 在任何时刻都可直接重算。
	rng.begin_quarter(C_SAVE_Q + 1)
	eq_int(rng.draw_raw(JWUnits.RngStream.SHOCK, C_SAVE_Q, 3), base,
			"INV-010：跨季之后仍可直接重算任意历史季的任意一次抽样（无状态式 RNG）")


## `ADV-H06` 删改命令流尾部。
## 检验 INV-131（存档含完整命令流，含被拒命令）、INV-137、
##      `manifest.command_log_hash`、INV-132。
func test_adv_h06_truncated_command_log_is_rejected() -> void:
	var defs: JWPolicyDef = _fresh_defs()

	# 分支一：删掉尾部若干行。
	var slot_cut: String = "adv_h06_cut"
	var st: JWSimState = _fresh_state()
	var cmds: JWCommands = _fresh_cmds()
	for i: int in 5:
		# 故意提交会被拒的命令：它们同样必须进命令流（INV-137），删掉就是洗白历史。
		cmds.submit(JWCommands.Kind.ISSUE_BOND,
				PackedInt64Array([C_U, 0, JWUnits.Holder.INVPOOL]), 0, defs)
	cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, PackedInt64Array(), 0, defs)
	eq_int(cmds.count, 6, "INV-131：被拒命令与推进标记都必须在命令流里")

	var saves_cut: JWSaves = JWSaves.new()
	eq_int(_save_slot(st, cmds, slot_cut, saves_cut), JWResult.OK, "夹具前提：存档必须写成功")
	var clean_code: int = _load_slot(slot_cut, saves_cut)
	eq_int(clean_code, JWResult.OK,
			"INV-133 / docs/11 §6.6：带 6 条命令（含 5 条被拒）的存档必须能原样载入"
			+ "（实测码 %d）——它是本条两个分支的对照组" % clean_code + _loader_note())
	var cmd_path: String = _slot_file(slot_cut, JWSaves.FILE_COMMANDS)
	var lines: PackedStringArray = _read_text(cmd_path).split("\n", false)
	ge_int(lines.size(), 6, "INV-131：commands.jsonl 必须逐条写下全部命令（含被拒的）")
	var kept: PackedStringArray = PackedStringArray()
	for i: int in maxi(lines.size() - 5, 0):
		kept.append(lines[i])
	_write_text(cmd_path, "\n".join(kept) + "\n")
	eq_int(_load_slot(slot_cut, saves_cut), JWResult.Load.SAVE_CORRUPT,
			"INV-131 / docs/11 §6.3：删掉 commands.jsonl 尾部 5 行后 command_log_hash "
			+ "必然不符，读档必须 E_SAVE_CORRUPT——否则「重放是权威的」这一承诺失效")
	_purge_slot(slot_cut)

	# 分支二：把某条被拒命令的 accepted 字段改成 1（伪造历史）。
	var slot_flip: String = "adv_h06_flip"
	var st2: JWSimState = _fresh_state()
	var cmds2: JWCommands = _fresh_cmds()
	cmds2.submit(JWCommands.Kind.ISSUE_BOND,
			PackedInt64Array([C_U, 0, JWUnits.Holder.INVPOOL]), 0, defs)
	cmds2.submit(JWCommands.Kind.ADVANCE_QUARTER, PackedInt64Array(), 0, defs)
	var saves_flip: JWSaves = JWSaves.new()
	eq_int(_save_slot(st2, cmds2, slot_flip, saves_flip), JWResult.OK,
			"夹具前提：存档必须写成功")
	var flip_path: String = _slot_file(slot_flip, JWSaves.FILE_COMMANDS)
	var flip_txt: String = _read_text(flip_path)
	var acc_token: String = _json_token(flip_txt, JWCommands.JSON_KEY_ACCEPTED, "0")
	check(acc_token != "",
			"INV-137：commands.jsonl 必须逐条记 accepted 与 reject_code（docs/11 §6.1）")
	_write_text(flip_path, flip_txt.replace(acc_token,
			acc_token.replace("0", "1")))
	eq_int(_load_slot(slot_flip, saves_flip), JWResult.Load.SAVE_CORRUPT,
			"INV-132：篡改命令的 accepted 字段必须被 command_log_hash 抓住并拒绝载入")
	_purge_slot(slot_flip)


# ══════════════════════════════════════════════════════════════════════════
# I 族：外部账户攻击（docs/31 §10）
# ══════════════════════════════════════════════════════════════════════════

## `ADV-I01` 无限进口。
## 检验 INV-104（`imports_uqs[s] ≤ world.delivery_capacity_uqs[s]`，
##      且进口支出受买方现金与外部信用额度双重约束）、INV-026。
## 计划书 §07：「不能仅靠『外汇充足』标签无限采购。」
func test_adv_i01_imports_bounded_by_delivery_capacity() -> void:
	var st: JWSimState = _fresh_state()
	var w: JWWorldMarket = st.world
	var s: int = JWUnits.Sector.MANU

	w.set_delivery_capacity(s, C_DELIVERY_CAP_UQS)
	w.begin_quarter_delivery()
	eq_int(w.delivery_remaining(s), C_DELIVERY_CAP_UQS,
			"docs/17 §4.22：begin_quarter_delivery 后本季剩余交付额度 == 交付能力")

	# 攻击：一次要 1.5 倍交付能力的货。
	w.record_import(s, C_DELIVERY_CAP_UQS + C_DELIVERY_CAP_UQS / 2, C_U)
	le_int(w.f_imports_uqs[s], C_DELIVERY_CAP_UQS,
			"INV-104：本季进口量不得超过交付能力（%d μQ_s）——超了就等于外部世界是无限供给方，"
			% C_DELIVERY_CAP_UQS + "所有瓶颈都能用进口解决，五项供给约束全部失效")
	ge_int(w.delivery_remaining(s), 0,
			"INV-104：剩余交付额度不得为负（短缺必须显露为未满足需求，不是负额度）")

	# 攻击第二波：额度已用尽后再来一笔，一点也不许进来。
	var before: int = w.f_imports_uqs[s]
	w.record_import(s, C_DELIVERY_CAP_UQS, C_U)
	le_int(w.f_imports_uqs[s], C_DELIVERY_CAP_UQS,
			"INV-104：额度用尽后继续下单不得突破上限（实测由 %d 变为 %d）"
			% [before, w.f_imports_uqs[s]])

	# 别的部门的额度不得被这笔进口牵连（逐部门独立，docs/10 §8.4）。
	var other: int = JWUnits.Sector.AGRI
	eq_int(w.f_imports_uqs[other], 0,
			"docs/10 §8.4：交付能力逐部门独立，manu 的进口不得记到 agri 名下")


## `ADV-I02` 分批绕过外债额度。
## 检验 INV-034（外部融资 ≤ `credit_limit_uu − credit_used_uu`，
##      且额度是**增量额度**：R-CREDIT-01）、INV-107。
func test_adv_i02_external_credit_limit_is_cumulative() -> void:
	var st: JWSimState = _fresh_state()
	var w: JWWorldMarket = st.world
	w.set_credit_limit(C_CREDIT_LIMIT_UU)
	eq_int(w.credit_headroom(), C_CREDIT_LIMIT_UU,
			"R-CREDIT-01：credit_used 初值为 0，开局余额 == 额度全额")

	var half: int = C_CREDIT_LIMIT_UU * 6 / 10
	eq_int(w.use_external_credit(half), JWResult.OK,
			"INV-034：额度内的第一笔外部融资应被接受")
	eq_int(w.credit_used, half, "INV-034：已用额度必须累计记账")

	# 攻击：第二笔单看也「不超总额」，但累计已经超了。
	var second: int = w.use_external_credit(half)
	eq_int(second, JWResult.Reject.CREDIT_LIMIT,
			"INV-034 / ADV-I02：额度检查必须用**累计已用量**而不是单笔额度——"
			+ "逐笔检查代替累计检查是本族最经典的漏洞")
	eq_int(w.credit_used, half,
			"docs/12 §0.6 REJECT 语义：被拒的额度占用不得改变 credit_used")

	# 攻击升级：拆成 100 笔小额。总额仍不得越线。
	var n: int = 0
	while n < C_LOOP_GUARD and w.use_external_credit(C_SMALL_TRANCHE_UU) == JWResult.OK:
		n += 1
	le_int(n, C_LOOP_GUARD - 1,
			"INV-034：分批发行必须在 %d 笔之内被额度拦住；跑满循环上限说明额度根本没生效"
			% C_LOOP_GUARD)
	le_int(w.credit_used, w.credit_limit,
			"INV-034：无论拆成多少笔，累计占用都不得超过 credit_limit_uu")
	eq_int(w.credit_headroom(), w.credit_limit - w.credit_used,
			"docs/17 §4.22：credit_headroom() 必须等于 limit − used，两个量不得各写各的")


## `ADV-I03` 汇率套利。
## 检验 INV-105（`fx_rate_ppm` 恒为 1 000 000，任何写入即 FAULT）、INV-013、INV-138。
## 计划书 §02 明确排除「玩家直接操纵汇率」。
func test_adv_i03_fx_rate_has_no_write_path() -> void:
	eq_int(JWWorldMarket.FX_RATE_PPM, JWUnits.PPM,
			"INV-105：fx_rate_ppm 恒为 1 000 000 ppm（首版固定汇率）")
	eq_int(JWWorldMarket.FX_RATE_PPM, JWUnits.FX_RATE_PPM,
			"INV-105：汇率常量只有一处定义，JWUnits 与 JWWorldMarket 必须一致")

	# 结构性防线：汇率不是状态条目——它不进状态数组、不进标量、不进注册表，
	# 因此既不进 state_hash 也不进存档，也就不存在任何「改了再重算哈希」的路径。
	for id: String in JWWorldMarket.STATE_SCALAR_IDS:
		check_false(id.findn("fx_rate") >= 0,
				"INV-105：fx_rate 不得登记为可写状态标量（出现在 %s）" % id)
	for id: String in JWWorldMarket.STATE_ARRAY_IDS:
		check_false(id.findn("fx_rate") >= 0,
				"INV-105：fx_rate 不得登记为可写状态数组（出现在 %s）" % id)

	var st: JWSimState = _fresh_state()
	var leaked: String = ""
	for e: int in st.registry_size():
		var id: String = st.registry_id(e)
		if id.findn("fx_rate") >= 0:
			leaked = id
			break
	eq_str(leaked, "",
			"INV-105：全状态注册表里不得出现汇率条目；出现了 \"%s\" 就意味着存在一条"
			% leaked + "未来会被误用的写入路径（即使数值现在没变，同样判失败）")

	# 命令侧：12 种命令的参数槽里没有任何一个能落到 world 上（docs/11 §6.1）。
	var cmds: JWCommands = _fresh_cmds()
	var defs: JWPolicyDef = _fresh_defs()
	var h0: String = st.subsystem_hash(JWUnits.SUBSYS_WORLD)
	for kind: int in JWCommands.KIND_CODES:
		var args: PackedInt64Array = PackedInt64Array()
		for slot: int in JWCommands.ARG_SLOTS:
			args.append(JWUnits.PPM)
		cmds.submit(kind, args, 0, defs)
	eq_str(st.subsystem_hash(JWUnits.SUBSYS_WORLD), h0,
			"INV-138：把 12 种命令的参数槽全部灌满也不得改动 world 子系统的任何一位")


## `ADV-I04` 自造出口订单。
## 检验 INV-059（市场对账：Σ 成交 + Σ 未满足 == Σ 需求）、INV-064、
##      计划书 §09 P08「不能自造订单」。
## 出口量 = min(可供出口量, 外部需求)；港口升级只放松**供给侧**约束。
func test_adv_i04_exports_cannot_exceed_external_demand() -> void:
	var st: JWSimState = _fresh_state()
	var w: JWWorldMarket = st.world
	var s: int = JWUnits.Sector.MANU

	# 内容夹具：基准出口量存在，但外部需求被冲击压到 0（docs/31 ADV-I04 的对照组）。
	w.base_export_uqs[s] = C_DELIVERY_CAP_UQS
	w.set_export_demand(s, 0)
	w.set_delivery_capacity(s, C_DELIVERY_CAP_UQS)
	w.begin_quarter_delivery()
	eq_int(w.export_demand(s), 0, "夹具前提：外部需求被压到 0")

	# 攻击：产能就是需求，我造多少就卖多少。
	w.record_export(s, C_DELIVERY_CAP_UQS, C_U)
	eq_int(w.f_exports_uqs[s], 0,
			"ADV-I04：外部需求为 0 时出口成交必须为 0——供给不能创造需求。"
			+ "出口随港口容量上升是本目录里最隐蔽的重复计数：它不违反任何账本恒等式，"
			+ "却让「先建设」路线无条件占优（计划书 §17 策略差异验收项）")
	eq_int(w.f_exports_uu, 0,
			"INV-064：卖不出去的产量只能写 unmet_demand，不得记成出口收入")

	# 需求恢复后，出口上限是 min(基准×需求, 交付能力)，不是「想卖多少卖多少」。
	w.set_export_demand(s, JWUnits.PPM)
	var cap: int = JWMath.mul_ppm(w.base_export_uqs[s], w.export_demand(s))
	w.record_export(s, cap * 3, C_U)
	le_int(w.f_exports_uqs[s], cap,
			"INV-059 / 计划书 §09 P08：出口量不得超过外部需求上限 %d μQ_s" % cap)


## `ADV-I05` 经常账户不闭合。
## 检验 INV-106（`current_account(q) == current_account(q−1) + 出口 − 进口
##      − 对外利息 + 对外净借款`，容差 0）、INV-107、INV-110、INV-026。
func test_adv_i05_current_account_identity_has_zero_residual() -> void:
	var st: JWSimState = _fresh_state()
	var w: JWWorldMarket = st.world
	var acc: JWAccount = st.accounts

	# 制造一个四类对外流量同时发生的极端季。
	for s: int in JWUnits.S:
		w.base_export_uqs[s] = C_DELIVERY_CAP_UQS
		w.set_export_demand(s, JWUnits.PPM)
		w.set_delivery_capacity(s, C_DELIVERY_CAP_UQS)
	w.begin_quarter_delivery()
	w.record_export(JWUnits.Sector.MANU, C_DELIVERY_CAP_UQS / 2, 3 * C_U)
	w.record_import(JWUnits.Sector.ENERGY, C_DELIVERY_CAP_UQS / 2, 2 * C_U)

	var ca0: int = w.current_account
	var exports_uu: int = w.f_exports_uu
	var imports_uu: int = w.f_imports_uu
	var foreign_interest: int = C_U / 2
	var net_borrowing: int = C_U

	var code: int = w.settle_current_account(foreign_interest, net_borrowing, 0, acc)
	eq_int(code, JWResult.OK,
			"INV-106：经常账户结算不得报故障（残差不为 0 即 LEDGER_IMBALANCE，实测码 %d）" % code)
	eq_int(w.current_account,
			ca0 + exports_uu - imports_uu - foreign_interest + net_borrowing,
			"INV-106：经常账户恒等式的残差必须**恒为 0**（不是「接近 0」）——"
			+ "残差非 0 说明某类对外流量走了单边过账（INV-026）")

	# INV-020 对 agent.row 同样成立：它是完整的账户主体，不是一个记号。
	eq_int(acc.check_balance_sheet(), JWResult.OK,
			"INV-020：agent.row 是真实主体，逐主体资产负债恒等式对它同样成立；"
			+ "对外单边过账会同时触发 INV-018 与 INV-020（两个不变量同时红是最快的定位信号）")
