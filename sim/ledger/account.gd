class_name JWAccount
extends RefCounted

## 60 个主体 × 15 个科目 = 900 个余额的稠密表（docs/10 §2.1/§2.2）。
## 全系统唯一持有 cash / inv / capital / debt 数值的地方；
## state.gov.cash_uu、state.cell.cash_uu[]、state.group.cash_uu[]、state.invpool.* 都是本表的视图。
## 本表的写入口只有一个 _apply_delta()，静态检查要求其调用点只出现在 sim/ledger/ledger.gd（INV-022）。
##
## ── 两套符号约定与它们之间唯一的一次翻译（docs/17 §2.4） ──────────────────
##
## 过账行（log.ledger.delta_uu）的约定：**资产增 +、负债增 −**（docs/10 §2.5）。
## 余额（balance[]）的约定：资产科目 0..10 正数即资产，负债科目 11..13 正数即负债，
## nw 正数即净值。`_apply_delta()` 是全系统唯一一处做这两套约定之间翻译的地方：
##
##   资产科目：balance += delta
##   负债科目：balance −= delta      （行 delta 为负 ⇒ 负债增加）
##   nw：      balance −= delta      （nw 与负债同侧，行 delta 为负 ⇒ 净值增加）
##
## 于是**每一条行对该主体 INV-020 残差的贡献恒等于 +delta**：
##   残差 R(a) = Σ资产 − Σ负债 − nw，资产行 +delta、负债行 −(−delta) = +delta、nw 行 −(−delta) = +delta。
## 因此「逐主体资产负债恒等式成立」等价于「每个主体在一笔 txn 内的行之和为 0」——
## 这正是 JWLedger._settle_nw() 用一条**不写日志的隐式 nw 行**补平的量（docs/10 §2.2：
## 「nw 是平衡项，由 JWLedger 在每次 post() 内同步维护，不是独立可写字段」）。

## §1.6 状态块协议：本块各数组所属子系统（与 STATE_ARRAY_IDS 等长）。
## account.balance 的 900 个元素按 §2.5 的主体映射逐元素归属；
## 这里登记的是数组级归属，逐元素归属由 subsystem_of_account() 给出。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [JWUnits.SUBSYS_GOV]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
const STATE_ARRAY_IDS: PackedStringArray = ["account.balance"]
const STATE_SCALAR_IDS: PackedStringArray = []
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = []

## 事务撤销记录的初始容量。一笔 txn 的腿数远小于此；
## 超出时按倍增扩容（冷路径，正常结算不会触发）。
const UNDO_CAP0: int = 64

## account.<agent>.<code> —— 900 元素，μU，写入者 S02..S07（全部经 JWLedger.post()）
var balance: PackedInt64Array = PackedInt64Array()

## INV-018 的缓存（μU）
var _cash_total_cached: int = 0

## 非 0 表示当前在 JWLedger 的过账事务内
var _owner_guard: int = 0

## 事务撤销记录：逐次写入前的「下标 → 原值」，rollback_txn 逆序还原。
## 预分配，热路径不新建（docs/17 §1.4）。
var _undo_account: PackedInt64Array = PackedInt64Array()
var _undo_value: PackedInt64Array = PackedInt64Array()
## 撤销记录的有效长度
var _undo_n: int = 0

## 本次事务内现金科目的净变动，commit 时并入 _cash_total_cached，rollback 时丢弃。
var _cash_delta_txn: int = 0


## 唯一的余额写入口。**只允许 sim/ledger/ledger.gd 调用**（静态检查 INV-022）。
## 步骤：S02..S07（由 post() 间接触发）
## 前置：_owner_guard != 0（必须在一次 post() 事务内）；account 在 [0, 900)
## 后置：balance[account] += delta；若为资产科目且结果 < 0 → 不写、返回 NEGATIVE_CASH 供整笔回滚
## 不变量：INV-016（cash >= 0，永不先扣成负数）、INV-007（幅度上限）
## 失败：现金为负 → Fault.NEGATIVE_CASH（**不改任何余额**）；越界 → INDEX_OUT_OF_RANGE
func _apply_delta(account: int, delta: int) -> int:
	if _owner_guard == 0:
		# 不在事务内就改余额 = 绕开了整笔原子性，直接判违规，不写。
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, account, delta)
	if account < 0 or account >= JWUnits.ACCOUNT_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, account, JWUnits.ACCOUNT_N)
	if delta == 0:
		# 零腿不改账也不留撤销记录。行级「delta != 0」由 JWLedger 在写日志前把关（INV-015）。
		return JWResult.OK
	if delta > JWUnits.AMOUNT_MAX or delta < -JWUnits.AMOUNT_MAX:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, account, delta)
	# 下标反解：与 JWIds.idx_account 同为纯布局算术（account == agent * 15 + code）。
	var agent: int = JWMath.floor_div(account, JWUnits.ACCOUNT_CODE_N)
	var code: int = account - agent * JWUnits.ACCOUNT_CODE_N
	var stored: int = balance[account]
	var next_v: int = 0
	if code <= JWIds.ACC_DEPOSIT_CLAIM:
		# 资产科目（0..10）：行约定与余额约定同向。
		next_v = stored + delta
		if next_v < 0:
			# INV-016：永不先扣成负数再想办法。余额一位不改，由 post() 整笔回滚。
			# 全部资产科目共用 NEGATIVE_CASH（docs/17 §4.6 的失败行），
			# 调用方据此转欠付／缩规模／延期。
			return JWResult.raise_fault(JWResult.Fault.NEGATIVE_CASH, account, next_v)
	elif code <= JWIds.ACC_DEPOSIT_LIAB:
		# 负债科目（11..13）：行 delta 为负表示负债增加。
		next_v = stored - delta
		if next_v < 0:
			# 负债被冲成负数 = 清偿额超过了欠额，是错账不是现实约束（INV-030 要求 arrears >= 0）。
			return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, account, next_v)
	else:
		# nw（14）：平衡项，与负债同侧；可正可负，不设符号闸。
		next_v = stored - delta
	if next_v > JWUnits.AMOUNT_MAX or next_v < -JWUnits.AMOUNT_MAX:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, account, next_v)
	_undo_push(account, stored)
	balance[account] = next_v
	if code == JWIds.ACC_CASH:
		_cash_delta_txn += delta
	return JWResult.OK


## 压入一条撤销记录（写入前的原值）。容量不足时倍增（冷路径）。
## 步骤：S02..S07
## 前置：在事务内
## 后置：_undo_n += 1
## 不变量：INV-015（整笔回滚的前提）
## 失败：无
func _undo_push(account: int, old_value: int) -> void:
	var cap: int = _undo_account.size()
	if _undo_n >= cap:
		var next_cap: int = cap + cap
		if next_cap < UNDO_CAP0:
			next_cap = UNDO_CAP0
		_undo_account.resize(next_cap)
		_undo_value.resize(next_cap)
	_undo_account[_undo_n] = account
	_undo_value[_undo_n] = old_value
	_undo_n += 1


## 开始一次过账事务。post() 用它做「整笔回滚」。
## 步骤：S02..S07
## 前置：begin 时 _owner_guard == 0
## 后置：余额快照已留存，后续 _apply_delta 可被 rollback_txn 逐位还原
## 不变量：INV-015（一笔 txn 要么全成立要么全不成立）
## 失败：嵌套 begin → Fault.PHASE_VIOLATION
func begin_txn() -> int:
	if _owner_guard != 0:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, _owner_guard, 0)
	_owner_guard = 1
	_undo_n = 0
	_cash_delta_txn = 0
	return JWResult.OK


## 结束一次过账事务并让余额生效。
## 步骤：S02..S07
## 前置：_owner_guard != 0
## 后置：余额生效；_owner_guard 归零
## 不变量：INV-015
## 失败：未在事务内 → Fault.PHASE_VIOLATION
func commit_txn() -> int:
	if _owner_guard == 0:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	_undo_n = 0
	_cash_total_cached += _cash_delta_txn
	_cash_delta_txn = 0
	_owner_guard = 0
	return JWResult.OK


## 回滚一次过账事务。
## 步骤：S02..S07
## 前置：_owner_guard != 0
## 后置：余额与 begin 前逐位相同
## 不变量：INV-015
## 失败：未在事务内 → Fault.PHASE_VIOLATION
func rollback_txn() -> int:
	if _owner_guard == 0:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	# 逆序还原：同一科目被多次触碰时，最后写入的最先还原，最终落回最早的原值。
	var i: int = _undo_n - 1
	while i >= 0:
		balance[_undo_account[i]] = _undo_value[i]
		i -= 1
	_undo_n = 0
	_cash_delta_txn = 0
	_owner_guard = 0
	return JWResult.OK


## 只读访问器（全系统读余额的唯一方式）。
## 步骤：全部
## 前置：下标合法
## 后置：不改状态
## 不变量：—
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func get_balance(account: int) -> int:
	if account < 0 or account >= balance.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, account, JWUnits.ACCOUNT_N)
		return 0
	return balance[account]


## 读取某主体的现金余额。
## 步骤：全部
## 前置：agent 在 [0, 60)
## 后置：不改状态
## 不变量：—
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func cash_of(agent: int) -> int:
	if agent < 0 or agent >= JWUnits.AGENT_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, agent, JWUnits.AGENT_N)
		return 0
	return balance[JWIds.idx_account(agent, JWIds.ACC_CASH)]


## 读取某主体某部门的库存价值腿。
## 步骤：全部
## 前置：agent 在 [0, 60)；sector 在 [0, 4)
## 后置：不改状态
## 不变量：—
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func inv_of(agent: int, sector: int) -> int:
	if agent < 0 or agent >= JWUnits.AGENT_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, agent, JWUnits.AGENT_N)
		return 0
	if sector < 0 or sector >= JWUnits.S:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, sector, JWUnits.S)
		return 0
	return balance[JWIds.idx_account(agent, JWIds.ACC_INV_BASE + sector)]


## 读取某主体的净值科目。
## 步骤：全部
## 前置：agent 在 [0, 60)
## 后置：不改状态
## 不变量：—
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func net_worth_of(agent: int) -> int:
	if agent < 0 or agent >= JWUnits.AGENT_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, agent, JWUnits.AGENT_N)
		return 0
	return balance[JWIds.idx_account(agent, JWIds.ACC_NW)]


## 逐主体资产负债恒等式检查。
## 步骤：S06 §6.9、季末、载入后
## 前置：无
## 后置：不改状态
## 不变量：INV-020（cash+Σinv+wip+capital+housing+recv+bondhold+deposit_claim
##          −pay−debt−deposit_liab == nw）
## 失败：任一主体不成立 → Fault.BALANCE_SHEET_BROKEN，detail_a = 主体下标，detail_b = 残差
func check_balance_sheet() -> int:
	if balance.size() != JWUnits.ACCOUNT_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				balance.size(), JWUnits.ACCOUNT_N)
	var a: int = 0
	while a < JWUnits.AGENT_N:
		var base: int = JWIds.idx_account(a, 0)
		var assets: int = balance[base + JWIds.ACC_CASH]
		var s: int = 0
		while s < JWUnits.S:
			assets += balance[base + JWIds.ACC_INV_BASE + s]
			s += 1
		assets += balance[base + JWIds.ACC_WIP]
		assets += balance[base + JWIds.ACC_CAPITAL]
		assets += balance[base + JWIds.ACC_HOUSING]
		assets += balance[base + JWIds.ACC_RECV]
		assets += balance[base + JWIds.ACC_BONDHOLD]
		assets += balance[base + JWIds.ACC_DEPOSIT_CLAIM]
		var liabs: int = balance[base + JWIds.ACC_PAY]
		liabs += balance[base + JWIds.ACC_DEBT]
		liabs += balance[base + JWIds.ACC_DEPOSIT_LIAB]
		var residual: int = assets - liabs - balance[base + JWIds.ACC_NW]
		if residual != 0:
			# 不做任何「平衡修正」：残差原样报出，由故障包定位到具体主体。
			return JWResult.raise_fault(JWResult.Fault.BALANCE_SHEET_BROKEN, a, residual)
		a += 1
	return JWResult.OK


## 全经济现金总量。
## 步骤：S06 §6.9、季末
## 前置：无
## 后置：不改状态
## 不变量：INV-018（Σ cash == scenario.total_cash_uu）
## 失败：无
func total_cash() -> int:
	# 60 个主体全部参与求和：pubserv 的 4 个与 opening 的 1 个恒为 0，
	# 但必须参与 —— 否则「恒为 0」这件事就没人检查了（jw_ids.gd 的 AGENT_CASH_ACTIVE 注释）。
	var total: int = 0
	var a: int = 0
	while a < JWUnits.AGENT_N:
		total += balance[JWIds.idx_account(a, JWIds.ACC_CASH)]
		a += 1
	return total


## 现金变动闭合检查。
## 步骤：S06 §6.9、季末
## 前置：quarter_start_cash_total 由 S01 记下
## 后置：不改状态
## 不变量：INV-017（Σ Δcash == 0）、INV-018（Σ cash == scenario.total_cash_uu）
## 失败：Fault.CASH_TOTAL_CHANGED，detail_b = 实际总量 − 期望总量
func check_cash_closure(expected_total: int, start_total: int) -> int:
	var actual: int = total_cash()
	# INV-017：本季 Σ Δcash == 0，即期末总量与期初总量逐位相同。
	if actual != start_total:
		return JWResult.raise_fault(JWResult.Fault.CASH_TOTAL_CHANGED,
				actual, actual - start_total)
	# INV-018：全经济现金总量恒等于剧本登记值。
	if actual != expected_total:
		return JWResult.raise_fault(JWResult.Fault.CASH_TOTAL_CHANGED,
				actual, actual - expected_total)
	# 增量缓存与全量重算不一致 ⇒ 有人绕开 _apply_delta 改了现金（INV-022 的运行期兜底）。
	if _cash_total_cached != actual:
		return JWResult.raise_fault(JWResult.Fault.CASH_TOTAL_CHANGED,
				actual, actual - _cash_total_cached)
	# pubserv 不持有现金（docs/10 §2.1），其支付由 agent.gov 执行。
	var r: int = 0
	while r < JWUnits.PUBSERV:
		var pub_cash: int = balance[JWIds.idx_account(JWIds.agent_of_pubserv(r), JWIds.ACC_CASH)]
		if pub_cash != 0:
			return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE,
					JWIds.agent_of_pubserv(r), pub_cash)
		r += 1
	return JWResult.OK


## Σ recv == Σ pay。
## 步骤：季末
## 前置：无
## 后置：不改状态
## 不变量：INV-019
## 失败：Fault.LEDGER_IMBALANCE
func check_receivable_payable() -> int:
	var recv: int = 0
	var pay: int = 0
	var a: int = 0
	while a < JWUnits.AGENT_N:
		var base: int = JWIds.idx_account(a, 0)
		recv += balance[base + JWIds.ACC_RECV]
		pay += balance[base + JWIds.ACC_PAY]
		a += 1
	if recv != pay:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, recv, recv - pay)
	return JWResult.OK


## 账户下标 → 子系统（§2.5 的主体映射：gov/invpool/row/opening → GOV，cell → CELL，group → GROUP）。
## 步骤：LOAD / 哈希 / WriteGuard
## 前置：account 在 [0, 900)
## 后置：不改状态
## 不变量：INV-013（写入者标注的机器化前提）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func subsystem_of_account(account: int) -> int:
	if account < 0 or account >= JWUnits.ACCOUNT_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, account, JWUnits.ACCOUNT_N)
		return 0
	var agent: int = JWMath.floor_div(account, JWUnits.ACCOUNT_CODE_N)
	if agent >= JWIds.AGENT_CELL_BASE and agent < JWIds.AGENT_PUBSERV_BASE:
		return JWUnits.SUBSYS_CELL
	if agent >= JWIds.AGENT_PUBSERV_BASE and agent < JWIds.AGENT_GROUP_BASE:
		# docs/17 §2.5 的映射表漏列了 pubserv；按主体语义归 SUBSYS_PUBSERV。
		return JWUnits.SUBSYS_PUBSERV
	if agent >= JWIds.AGENT_GROUP_BASE and agent < JWIds.AGENT_INVPOOL:
		return JWUnits.SUBSYS_GROUP
	# gov / invpool / row / opening
	return JWUnits.SUBSYS_GOV


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：尚未 allocate 过
## 后置：balance.size() == JWUnits.ACCOUNT_N，全部为 0
## 不变量：INV-136（数组长度是 schema 的一部分）
## 失败：无
func allocate() -> void:
	balance.resize(JWUnits.ACCOUNT_N)
	balance.fill(0)
	_undo_account.resize(UNDO_CAP0)
	_undo_value.resize(UNDO_CAP0)
	_undo_n = 0
	_owner_guard = 0
	_cash_total_cached = 0
	_cash_delta_txn = 0


## §1.6 状态块协议：只读取用（返回引用，调用方不得写）。
## 步骤：全部
## 前置：i 在 [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return balance
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：仅 LOAD / MIG 可调（静态检查限定 systems/content_loader.gd 与 systems/saves.gd）。
## 步骤：LOAD / MIG
## 前置：v.size() 等于契约长度
## 后置：对应数组被整体替换
## 不变量：INV-136
## 失败：长度不符 → Load.SCHEMA_HEADER；越界 → INDEX_OUT_OF_RANGE
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i != 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	if v.size() != JWUnits.ACCOUNT_N:
		return JWResult.raise_fault(JWResult.Load.SCHEMA_HEADER, v.size(), JWUnits.ACCOUNT_N)
	if _owner_guard != 0:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, _owner_guard, 0)
	# duplicate()：Packed*Array 传参是引用语义，直接赋值会让权威状态与调用方的临时数组共用内存。
	balance = v.duplicate()
	_undo_n = 0
	_cash_delta_txn = 0
	# 载入后重算现金缓存，使 check_cash_closure 的「缓存 vs 全量」对账从存档第一秒起有效。
	_cash_total_cached = total_cash()
	return JWResult.OK


## §1.6 状态块协议：本类无标量状态，恒返回 0。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func state_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：本类无标量状态。
## 步骤：LOAD / MIG
## 前置：无
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE
func set_state_scalar(i: int, v: int) -> int:
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v)


## §1.6 状态块协议：本类 FLOW_* 为空。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func flow_array(i: int) -> PackedInt64Array:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：本类 FLOW_* 为空。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：仅 S01；全部 FLOW_* 归零。本类无流量，空操作。
## 步骤：S01
## 前置：phase == S01
## 后置：无流量可清
## 不变量：INV-009（流量整表清零）
## 失败：无
func reset_flows() -> void:
	pass


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01
## 前置：reset_flows() 已调用
## 后置：不改状态
## 不变量：INV-009
## 失败：非 0 → 调用方 raise Fault.FLOW_NOT_RESET
func flow_abs_sum() -> int:
	return 0
