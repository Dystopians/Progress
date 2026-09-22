class_name JWLedger
extends RefCounted

## 全系统唯一的过账入口（docs/12 §0.2）。一次 post() 产生一笔 txn，含 ≥ 2 条有符号过账行；
## 持有 log.ledger、log.physical、log.rounding 三条日志通道。
## 日志只有整数；展示文案由 Presentation 用 cause / kind 码查模板表生成（docs/10 §2.5）。
##
## ── 一笔 txn 的构造规则（三个 post 变体共用，实现见 _leg / _settle_nw） ────
##
## 1. 过账行的符号约定是「资产增 +、负债增 −」（docs/10 §2.5）；
##    JWAccount._apply_delta() 把它翻译成余额约定，是全系统唯一一处翻译（docs/17 §2.4）。
## 2. **记入日志的行之和恒为 0**（INV-015），由各入口在写日志前校验或按构造保证。
## 3. 每条行对其主体的 INV-020 残差的贡献恒为 +delta（推导见 account.gd 头注），
##    所以一个主体在本笔 txn 内的行之和 s 就是它的残差变化。_settle_nw() 对每个 s != 0 的主体
##    补一条 **不写日志的隐式 nw 行**（delta = −s），使 INV-020 逐笔按构造成立。
##    这就是 docs/10 §2.2 所说的「nw 是平衡项，由 JWLedger 在每次 post() 内同步维护」。
##    调用方若自己写了 nw 腿（例如 post_multi 的「现金 + 库存 + 价差」），
##    该主体的行之和自然为 0，隐式行不再产生 —— 两条路径给出同一结果，不会重复计入。
##    注意：隐式行**不进日志**，所以一笔 txn 里同一个主体的 nw 腿要么全写要么全不写；
##    半写会让记入日志的行之和不为 0，被 post_multi 的 Σ 校验当场判 LEDGER_IMBALANCE。
## 4. 三重分类码（prod/exp/inc）**每笔 txn 只写在一条行上**，否则同一笔会被正负两腿抵消成 0。
##    承载分类的行：post() 是收款腿；post_noncash() 是 delta 为正的那条腿；
##    post_multi() 是**第 0 腿**（调用约定：调用方须把承载分类金额的腿放在第 0 位）。
##    qty_uqs 同样只写在这条行上，避免被重复加总。

## §1.6 状态块协议：本块各数组所属子系统（与 STATE_ARRAY_IDS 等长）。
const STATE_ARRAY_SUBSYS: PackedInt64Array = []

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
const STATE_ARRAY_IDS: PackedStringArray = []
const STATE_SCALAR_IDS: PackedStringArray = ["state.meta.txn_seq"]

## §1.6 状态块协议：本块各标量所属子系统（与 STATE_SCALAR_IDS 等长）。
##
## 裁定（集成期，INV-013 的粒度）：`state.meta.txn_seq` 归 **SUBSYS_GOV**，不归 SUBSYS_META。
## 本块没有这张表时，JWSimState._reg_add_group 回落到 BLOCK_DEFAULT_SUBSYS[BLK_LEDGER]
## == SUBSYS_META，于是「过一笔账」就成了一次对 META 子系统的写入；而 META 只在
## S01/S02/S08 可写（JWUnits.WRITABLE_SUBSYS）——S04/S05/S06/S07 每一笔 post 都会被
## WriteGuard 判 WRITE_OUT_OF_SCOPE。实测即如此（S04/SUBSYS_META）。
## 归 GOV 是**恢复本来的归属**而不是放宽：txn_seq 是账本流水号，它索引的
## `account.balance` 已经登记在 SUBSYS_GOV（JWAccount.STATE_ARRAY_SUBSYS），
## 而每一个会过账的步骤（S02/S04/S05/S06/S07）的可写子集里都有 GOV。
## 子系统归属只改 subsystem_hash 与 WriteGuard 的粒度，不改 state_hash（全量哈希不按子系统过滤）。
const STATE_SCALAR_SUBSYS: PackedInt64Array = [JWUnits.SUBSYS_GOV]
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = []

## 日志扩容倍率 3/2（docs/10 §12「满则按 1.5 倍扩容并写一条告警」）
const LOG_GROWTH_NUM: int = 3
const LOG_GROWTH_DEN: int = 2

## 三重分类码的取值个数（JWUnits.ProdClass / ExpClass / IncClass 的枚举长度）。
## aggregate_classes 的三个出参缓冲至少要这么长。
const PROD_CLASS_N: int = 5
const EXP_CLASS_N: int = 7
const INC_CLASS_N: int = 4

## 开账分录的季度号（docs/17 §4.10：开账分录 q = −1）
const OPENING_Q: int = -1

## 构造注入的账户表（本类是 _apply_delta 的唯一合法调用方，INV-022）
var _accounts: JWAccount = null

## state.meta.txn_seq —— 交易流水号，写入者 S02..S07
var txn_seq: int = 0

## log.ledger.* —— 容量 JWUnits.LOG_CAP0，写入者 S02..S06，不进 state_hash
var l_txn: PackedInt64Array = PackedInt64Array()
var l_q: PackedInt64Array = PackedInt64Array()
var l_step: PackedInt64Array = PackedInt64Array()
var l_kind: PackedInt64Array = PackedInt64Array()
var l_account: PackedInt64Array = PackedInt64Array()
var l_delta: PackedInt64Array = PackedInt64Array()
var l_qty: PackedInt64Array = PackedInt64Array()
var l_product: PackedInt64Array = PackedInt64Array()
var l_cause: PackedInt64Array = PackedInt64Array()
var l_entity: PackedInt64Array = PackedInt64Array()
var l_prod: PackedInt64Array = PackedInt64Array()
var l_exp: PackedInt64Array = PackedInt64Array()
var l_inc: PackedInt64Array = PackedInt64Array()

## log.physical.* —— 写入者 S04, S05
var p_from: PackedInt64Array = PackedInt64Array()
var p_to: PackedInt64Array = PackedInt64Array()
var p_product: PackedInt64Array = PackedInt64Array()
var p_qty: PackedInt64Array = PackedInt64Array()
var p_cause: PackedInt64Array = PackedInt64Array()
var p_step: PackedInt64Array = PackedInt64Array()

## log.rounding.* —— 各步写入
var r_site: PackedInt64Array = PackedInt64Array()
var r_total: PackedInt64Array = PackedInt64Array()
var r_parts: PackedInt64Array = PackedInt64Array()
var r_residual: PackedInt64Array = PackedInt64Array()

## 当前步骤，由 JWTurnRunner 设（S01..S08）
var _step: int = 0

## 当季，由 S01 设
var _q: int = 0

## 三条日志通道的本季写游标
var _log_cursor: int = 0
var _p_cursor: int = 0
var _r_cursor: int = 0

## 扩容次数（诊断用；日志不进 state_hash）
var _log_grow_count: int = 0
var _p_grow_count: int = 0
var _r_grow_count: int = 0

## 本笔 txn 内逐主体的行之和（长 AGENT_N），_settle_nw 据此补隐式 nw 行。
## 预分配，热路径不新建也不 fill 整表：只清被触碰过的下标（docs/17 §1.4）。
var _agent_sum: PackedInt64Array = PackedInt64Array()
## 本笔 txn 触碰过的主体下标表（长 AGENT_N）与其有效长度
var _touched: PackedInt64Array = PackedInt64Array()
var _touched_n: int = 0
## 主体是否已在 _touched 中（长 AGENT_N，0/1）
var _touched_mark: PackedInt64Array = PackedInt64Array()


## 构造注入 JWAccount（docs/17 §4.10 成员表「构造注入」）。
## 步骤：LOAD
## 前置：accounts 已 allocate()
## 后置：_accounts 指向全系统唯一的账户表
## 不变量：INV-022（_apply_delta 只能由本类调用）
## 失败：无
func _init(accounts: JWAccount = null) -> void:
	_accounts = accounts


## 唯一的过账入口。一次调用产生一笔 txn，含 >= 2 条有符号行。
## 步骤：S02..S07（S01/S08 不过账）
## 前置：amount_uu >= 0；payer_account != payee_account；kind 已在三分类表登记；
##       方向由 payer → payee 决定
## 后置：两端余额已更新且都 >= 0（资产科目）；log.ledger 增 2 行；行之和为 0；
##       有实物时同 txn_id 写一条 log.physical
## 不变量：INV-015（行和为 0、amount != 0、两端不同）、INV-016（现金不为负）、
##          INV-022（唯一入口）、INV-026（对外必有 agent.row 对手方）、INV-114（三分类码完备）
## 失败：现金不足 → **整笔回滚**并返回 Fault.NEGATIVE_CASH（调用方决定转欠付／缩规模／延期）；
##       kind 未分类 → Fault.LEDGER_KIND_UNCLASSIFIED；金额为负 → Fault.LEDGER_IMBALANCE
func post(kind: int, payer_account: int, payee_account: int, amount_uu: int,
		qty_uqs: int, product: int, cause: int, entity_ref: int) -> int:
	if _accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	if not JWUnits.kind_is_classified(kind):
		return JWResult.raise_fault(JWResult.Fault.LEDGER_KIND_UNCLASSIFIED, kind, 0)
	# INV-015：每行 amount != 0；金额为负是错账不是现实约束。
	if amount_uu <= 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, amount_uu, 0)
	if amount_uu > JWUnits.AMOUNT_MAX:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, amount_uu, JWUnits.AMOUNT_MAX)
	if payer_account == payee_account:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, payer_account, payee_account)
	var rc: int = _check_account(payer_account)
	if rc != JWResult.OK:
		return rc
	rc = _check_account(payee_account)
	if rc != JWResult.OK:
		return rc
	rc = _accounts.begin_txn()
	if rc != JWResult.OK:
		return rc
	_touched_reset()
	rc = _leg(payer_account, -amount_uu)
	if rc == JWResult.OK:
		rc = _leg(payee_account, amount_uu)
	if rc == JWResult.OK:
		rc = _settle_nw()
	if rc != JWResult.OK:
		_touched_reset()
		_accounts.rollback_txn()
		return rc
	_touched_reset()
	# 过账成立之后才推进流水号与写日志：失败的尝试不留痕于账本行（失败走 log.arrears / 故障包）。
	txn_seq += 1
	_log_row(txn_seq, kind, payer_account, -amount_uu, 0, product, cause, entity_ref, false)
	_log_row(txn_seq, kind, payee_account, amount_uu, qty_uqs, product, cause, entity_ref, true)
	return _accounts.commit_txn()


## 多腿过账（一次交易涉及 3 条以上行，例如「现金 + 库存 + 价差」）。
## 步骤：S05（成交入库）、S06（折旧、营业盈余结转、价差）
## 前置：legs_account 与 legs_delta 等长且 Σ legs_delta == 0；至少 2 行；每行 delta != 0
## 后置：全部行原子生效或全部不生效
## 不变量：INV-015, INV-016, INV-020, INV-114
## 失败：行和不为 0 → Fault.LEDGER_IMBALANCE；任一现金为负 → 整笔回滚 + NEGATIVE_CASH
func post_multi(kind: int, legs_account: PackedInt64Array, legs_delta: PackedInt64Array,
		qty_uqs: int, product: int, cause: int, entity_ref: int) -> int:
	if _accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	if not JWUnits.kind_is_classified(kind):
		return JWResult.raise_fault(JWResult.Fault.LEDGER_KIND_UNCLASSIFIED, kind, 0)
	var n: int = legs_account.size()
	if n != legs_delta.size():
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, n, legs_delta.size())
	if n < 2:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, n, 2)
	# 先整体校验再动账：校验不通过时连事务都不开，状态一位不改。
	var sum_delta: int = 0
	var i: int = 0
	while i < n:
		var d: int = legs_delta[i]
		if d == 0:
			return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, i, 0)
		if d > JWUnits.AMOUNT_MAX or d < -JWUnits.AMOUNT_MAX:
			return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, i, d)
		var rc_i: int = _check_account(legs_account[i])
		if rc_i != JWResult.OK:
			return rc_i
		sum_delta += d
		i += 1
	if sum_delta != 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, n, sum_delta)
	var rc: int = _accounts.begin_txn()
	if rc != JWResult.OK:
		return rc
	_touched_reset()
	i = 0
	while i < n and rc == JWResult.OK:
		rc = _leg(legs_account[i], legs_delta[i])
		i += 1
	if rc == JWResult.OK:
		rc = _settle_nw()
	if rc != JWResult.OK:
		_touched_reset()
		_accounts.rollback_txn()
		return rc
	_touched_reset()
	txn_seq += 1
	i = 0
	while i < n:
		# 第 0 腿承载三重分类码与数量（见文件头「一笔 txn 的构造规则」第 4 条）。
		var qty_i: int = 0
		if i == 0:
			qty_i = qty_uqs
		_log_row(txn_seq, kind, legs_account[i], legs_delta[i], qty_i, product,
				cause, entity_ref, i == 0)
		i += 1
	return _accounts.commit_txn()


## 非现金分录（折旧、价差、营业盈余结转、开账）：资产/净值两腿，不动现金。
## 步骤：S06 §6.1/§6.6、LOAD（开账）
## 前置：kind ∈ {DEPRECIATION, OPERATING_SURPLUS, PRICE_VARIANCE, OPENING_BALANCE, WRITEOFF}
## 后置：cash 科目不被触碰（静态断言）；nw 同步调整
## 不变量：INV-021（Δnw 被损益流量完全解释）、INV-017（现金不变）
## 失败：kind 不在白名单 → Fault.LEDGER_KIND_UNCLASSIFIED
func post_noncash(kind: int, agent: int, asset_code: int, delta_uu: int,
		cause: int, entity_ref: int) -> int:
	if _accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	if not _is_noncash_kind(kind):
		return JWResult.raise_fault(JWResult.Fault.LEDGER_KIND_UNCLASSIFIED, kind, 0)
	if agent < 0 or agent >= JWUnits.AGENT_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, agent, JWUnits.AGENT_N)
	if asset_code < 0 or asset_code >= JWUnits.ACCOUNT_CODE_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				asset_code, JWUnits.ACCOUNT_CODE_N)
	if asset_code == JWIds.ACC_CASH:
		# INV-017：非现金分录不得触碰现金科目。
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, asset_code, 0)
	if asset_code == JWIds.ACC_NW:
		# nw 腿由本函数生成，不由调用方给（nw 不是独立可写字段，docs/10 §2.2）。
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, asset_code, 0)
	if delta_uu == 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, 0, 0)
	if delta_uu > JWUnits.AMOUNT_MAX or delta_uu < -JWUnits.AMOUNT_MAX:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, delta_uu, JWUnits.AMOUNT_MAX)
	var asset_account: int = JWIds.idx_account(agent, asset_code)
	var nw_account: int = JWIds.idx_account(agent, JWIds.ACC_NW)
	var rc: int = _accounts.begin_txn()
	if rc != JWResult.OK:
		return rc
	_touched_reset()
	# 只过账资产腿：nw 腿由 _settle_nw() 以 −delta 补平，与下面登记的 nw 日志行逐位相等。
	rc = _leg(asset_account, delta_uu)
	if rc == JWResult.OK:
		rc = _settle_nw()
	if rc != JWResult.OK:
		_touched_reset()
		_accounts.rollback_txn()
		return rc
	_touched_reset()
	txn_seq += 1
	# 分类码落在 delta 为正的那条腿上：折旧（资产 −X）落在 nw 行 +X，
	# 使 inc_class = consumption_of_fixed_capital 汇总出 +X 而不是 −X。
	_log_row(txn_seq, kind, asset_account, delta_uu, 0, -1, cause, entity_ref, delta_uu > 0)
	_log_row(txn_seq, kind, nw_account, -delta_uu, 0, -1, cause, entity_ref, delta_uu < 0)
	return _accounts.commit_txn()


## 开账分录（q = −1，对手方 agent.opening）。
## 步骤：LOAD
## 前置：尚未开始任何季度结算
## 后置：全部初值经分录生成；agent.opening 的 **cash 恒为 0**（OQ-217：现金腿与自身 nw 配平，
##       不经 opening 的现金科目）；开账后 Σ cash == scenario.total_cash_uu
## 不变量：INV-023（初值过账本）、INV-015、INV-018
## 失败：Load.BALANCE_INIT / Load.CASH_TOTAL
func post_opening(agent: int, code: int, amount_uu: int) -> int:
	if _accounts == null:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, 0)
	if _step != JWUnits.Phase.IDLE:
		# 开账只在 LOAD 期，任何一步结算开始后再开账都是错账。
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, _step, 0)
	if agent < 0 or agent >= JWUnits.AGENT_N:
		return JWResult.raise_fault(JWResult.Load.BALANCE_INIT, agent, JWUnits.AGENT_N)
	if code < 0 or code >= JWUnits.ACCOUNT_CODE_N:
		return JWResult.raise_fault(JWResult.Load.BALANCE_INIT, code, JWUnits.ACCOUNT_CODE_N)
	if code == JWIds.ACC_NW:
		# nw 是平衡项：它的初值由其余科目的开账分录推出，不单独开账。
		return JWResult.raise_fault(JWResult.Load.BALANCE_INIT, code, 0)
	if amount_uu < 0:
		return JWResult.raise_fault(JWResult.Load.BALANCE_INIT, amount_uu, 0)
	if amount_uu > JWUnits.AMOUNT_MAX:
		return JWResult.raise_fault(JWResult.Load.BALANCE_INIT, amount_uu, JWUnits.AMOUNT_MAX)
	if amount_uu == 0:
		# 初值为 0 的科目不产生分录（INV-015 要求每行 amount != 0）。
		return JWResult.OK
	# 行约定「资产增 +、负债增 −」：负债科目的初值是正数额度，其过账行取负。
	var delta: int = amount_uu
	if code >= JWIds.ACC_PAY:
		delta = -amount_uu
	var asset_account: int = JWIds.idx_account(agent, code)
	var nw_account: int = JWIds.idx_account(agent, JWIds.ACC_NW)
	var rc: int = _accounts.begin_txn()
	if rc != JWResult.OK:
		return rc
	_touched_reset()
	rc = _leg(asset_account, delta)
	if rc == JWResult.OK:
		rc = _settle_nw()
	if rc != JWResult.OK:
		_touched_reset()
		_accounts.rollback_txn()
		return rc
	_touched_reset()
	txn_seq += 1
	# OQ-217：现金腿与自身 nw 配平，不经 agent.opening 的现金科目 —— 否则 opening 会先收后付，
	# Σ cash 在开账中途不等于剧本登记值。同一理由适用于其余科目：agent.opening 不能持负资产，
	# 所以它只作为**对手方标记**（entity_ref）出现，余额恒为 0。
	_log_row(txn_seq, JWUnits.Kind.OPENING_BALANCE, asset_account, delta, 0, -1,
			JWUnits.Kind.OPENING_BALANCE, JWIds.AGENT_OPENING, true)
	_log_row(txn_seq, JWUnits.Kind.OPENING_BALANCE, nw_account, -delta, 0, -1,
			JWUnits.Kind.OPENING_BALANCE, JWIds.AGENT_OPENING, false)
	# 开账行的季度号是 −1（docs/17 §4.10）；_log_row 按 _q 填，这里就地改写这两行。
	l_q[_log_cursor - 2] = OPENING_Q
	l_q[_log_cursor - 1] = OPENING_Q
	return _accounts.commit_txn()


## 物资流水（与资金行共享 txn_id）。
## 步骤：S04（项目物资）、S05（生产与交易）
## 前置：qty_uqs != 0；from/to 是库存位置码（可为 -1 表示无）
## 后置：log.physical 增一行
## 不变量：INV-047（库存恒等式的可追溯性）、INV-139
## 失败：日志满 → 扩容并写告警，不失败
func log_physical(from_loc: int, to_loc: int, product: int, qty_uqs: int, cause: int) -> void:
	if _p_cursor >= p_from.size():
		_physical_grow()
	p_from[_p_cursor] = from_loc
	p_to[_p_cursor] = to_loc
	p_product[_p_cursor] = product
	p_qty[_p_cursor] = qty_uqs
	p_cause[_p_cursor] = cause
	p_step[_p_cursor] = _step
	_p_cursor += 1


## 取整余数登记（换算类，不产生债权债务）。
## 步骤：各步
## 前置：site_code 已登记
## 后置：log.rounding 增一行
## 不变量：INV-005（季末 gov.rounding_residual 的变化必须被本日志逐条解释）
## 失败：无
func log_rounding(site_code: int, total: int, parts: int, residual: int) -> void:
	if _r_cursor >= r_site.size():
		_rounding_grow()
	r_site[_r_cursor] = site_code
	r_total[_r_cursor] = total
	r_parts[_r_cursor] = parts
	r_residual[_r_cursor] = residual
	_r_cursor += 1


## GDP 三口径的分类汇总（唯一数据源是本季账本行的三个分类码）。
## 步骤：S06 §6.4
## 前置：本季全部分录已写入
## 后置：out_prod/out_exp/out_inc 被填满；不改任何状态
## 不变量：INV-112（禁止用 Σ 销售额求和）、INV-114（完备性与互斥性）、INV-115、INV-116
## 失败：应分类却为 none → Fault.GDP_CLASS_MISSING（detail_a = 行号）；
##       同口径计入两类 → Fault.GDP_CLASS_DUPLICATE；kind 未登记 → LEDGER_KIND_UNCLASSIFIED
func aggregate_classes(out_prod: PackedInt64Array, out_exp: PackedInt64Array,
		out_inc: PackedInt64Array) -> int:
	if out_prod.size() < PROD_CLASS_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				out_prod.size(), PROD_CLASS_N)
	if out_exp.size() < EXP_CLASS_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				out_exp.size(), EXP_CLASS_N)
	if out_inc.size() < INC_CLASS_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				out_inc.size(), INC_CLASS_N)
	out_prod.fill(0)
	out_exp.fill(0)
	out_inc.fill(0)
	# 一笔 txn 的各行在日志中连续（三个 post 变体都是整笔一次性追加），
	# 于是「同一笔内某口径恰好被计入一次」可以按连续段扫描判定，不需要字典（INV-008 / 热路径纪律）。
	var i: int = 0
	while i < _log_cursor:
		var txn: int = l_txn[i]
		var kind: int = l_kind[i]
		if not JWUnits.kind_is_classified(kind):
			return JWResult.raise_fault(JWResult.Fault.LEDGER_KIND_UNCLASSIFIED, kind, i)
		var want_prod: int = JWUnits.KIND_PROD_CLASS[kind]
		var want_exp: int = JWUnits.KIND_EXP_CLASS[kind]
		var want_inc: int = JWUnits.KIND_INC_CLASS[kind]
		var cnt_prod: int = 0
		var cnt_exp: int = 0
		var cnt_inc: int = 0
		var j: int = i
		while j < _log_cursor and l_txn[j] == txn:
			var cp: int = l_prod[j]
			if cp != JWUnits.ProdClass.NONE:
				if cp != want_prod:
					# 计入了本 kind 不该计入的类（互斥性破裂）。
					return JWResult.raise_fault(JWResult.Fault.GDP_CLASS_DUPLICATE, j, cp)
				cnt_prod += 1
				out_prod[cp] += l_delta[j]
			var ce: int = l_exp[j]
			if ce != JWUnits.ExpClass.NONE:
				if ce != want_exp:
					return JWResult.raise_fault(JWResult.Fault.GDP_CLASS_DUPLICATE, j, ce)
				cnt_exp += 1
				out_exp[ce] += l_delta[j]
			var ci: int = l_inc[j]
			if ci != JWUnits.IncClass.NONE:
				if ci != want_inc:
					return JWResult.raise_fault(JWResult.Fault.GDP_CLASS_DUPLICATE, j, ci)
				cnt_inc += 1
				out_inc[ci] += l_delta[j]
			j += 1
		# 完备性（INV-114）：应被分类的 kind 出现 none 即 FAULT。
		if want_prod != JWUnits.ProdClass.NONE and cnt_prod == 0:
			return JWResult.raise_fault(JWResult.Fault.GDP_CLASS_MISSING, i, want_prod)
		if want_exp != JWUnits.ExpClass.NONE and cnt_exp == 0:
			return JWResult.raise_fault(JWResult.Fault.GDP_CLASS_MISSING, i, want_exp)
		if want_inc != JWUnits.IncClass.NONE and cnt_inc == 0:
			return JWResult.raise_fault(JWResult.Fault.GDP_CLASS_MISSING, i, want_inc)
		# 互斥性：同一口径在一笔 txn 内只能被计入一次，否则同一笔被重复加总。
		if cnt_prod > 1:
			return JWResult.raise_fault(JWResult.Fault.GDP_CLASS_DUPLICATE, i, cnt_prod)
		if cnt_exp > 1:
			return JWResult.raise_fault(JWResult.Fault.GDP_CLASS_DUPLICATE, i, cnt_exp)
		if cnt_inc > 1:
			return JWResult.raise_fault(JWResult.Fault.GDP_CLASS_DUPLICATE, i, cnt_inc)
		i = j
	return JWResult.OK


## 设置当前 q 与步骤（供日志行填充）；只由 TurnRunner 调用。
## 步骤：S01..S08 入口
## 前置：step ∈ JWUnits.Phase
## 后置：后续日志行带上正确的 q 与 step
## 不变量：INV-012
## 失败：无
func set_context(q: int, step: int) -> void:
	_q = q
	_step = step

# ── 内部实现（本类私有；_apply_delta 的唯一调用方，INV-022） ────────────────

## 过一条腿：写余额并累计该主体在本笔 txn 内的行之和。
## 步骤：S02..S07
## 前置：已在 _accounts.begin_txn() 之内
## 后置：余额已改；_agent_sum[主体] += delta；主体已登记进 _touched
## 不变量：INV-016, INV-020（残差贡献恒为 +delta）
## 失败：转发 _apply_delta 的错误码，由调用方整笔回滚
func _leg(account: int, delta: int) -> int:
	var rc: int = _accounts._apply_delta(account, delta)
	if rc != JWResult.OK:
		return rc
	var agent: int = JWMath.floor_div(account, JWUnits.ACCOUNT_CODE_N)
	if _touched_mark[agent] == 0:
		_touched_mark[agent] = 1
		_touched[_touched_n] = agent
		_touched_n += 1
	_agent_sum[agent] += delta
	return JWResult.OK


## 对每个行之和非 0 的主体补一条**不写日志**的隐式 nw 行，使 INV-020 逐笔按构造成立。
## 步骤：S02..S07
## 前置：本笔 txn 的全部显式腿已过账
## 后置：每个被触碰主体的（显式 + 隐式）行之和为 0
## 不变量：INV-020, INV-021（nw 只由本函数随分录同步维护，不自己动）
## 失败：转发 _apply_delta 的错误码
func _settle_nw() -> int:
	var i: int = 0
	while i < _touched_n:
		var agent: int = _touched[i]
		var s: int = _agent_sum[agent]
		if s != 0:
			# 行 delta = −s ⇒ nw 余额 += s（nw 与负债同侧，见 account.gd 的翻译表）。
			var rc: int = _accounts._apply_delta(JWIds.idx_account(agent, JWIds.ACC_NW), -s)
			if rc != JWResult.OK:
				return rc
		i += 1
	return JWResult.OK


## 清空本笔 txn 的逐主体累计（只清被触碰过的下标，不整表 fill）。
## 步骤：S02..S07
## 前置：无
## 后置：_touched_n == 0；_agent_sum / _touched_mark 全 0
## 不变量：热路径不分配（docs/17 §1.4）
## 失败：无
func _touched_reset() -> void:
	var i: int = 0
	while i < _touched_n:
		var agent: int = _touched[i]
		_agent_sum[agent] = 0
		_touched_mark[agent] = 0
		i += 1
	_touched_n = 0


## 账户下标合法性。
## 步骤：S02..S07
## 前置：无
## 后置：不改状态
## 不变量：INV-007
## 失败：越界 → INDEX_OUT_OF_RANGE
func _check_account(account: int) -> int:
	if account < 0 or account >= JWUnits.ACCOUNT_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				account, JWUnits.ACCOUNT_N)
	return JWResult.OK


## 非现金分录的 kind 白名单（docs/17 §4.10 的前置条件，逐字照抄）。
## 步骤：S06 §6.1/§6.6、LOAD
## 前置：无
## 后置：不改状态
## 不变量：INV-114
## 失败：无（返回 false，由调用方转 LEDGER_KIND_UNCLASSIFIED）
func _is_noncash_kind(kind: int) -> bool:
	if kind == JWUnits.Kind.DEPRECIATION:
		return true
	if kind == JWUnits.Kind.OPERATING_SURPLUS:
		return true
	if kind == JWUnits.Kind.PRICE_VARIANCE:
		return true
	if kind == JWUnits.Kind.OPENING_BALANCE:
		return true
	if kind == JWUnits.Kind.WRITEOFF:
		return true
	return false


## 写一行 log.ledger。classed == true 的那行承载本笔 txn 的三重分类码与数量。
## 步骤：S02..S06
## 前置：本笔 txn 已过账成立
## 后置：_log_cursor += 1；必要时先扩容
## 不变量：INV-015（行和为 0 由调用方保证）、INV-114、INV-139
## 失败：无
func _log_row(txn: int, kind: int, account: int, delta: int, qty: int, product: int,
		cause: int, entity_ref: int, classed: bool) -> void:
	if _log_cursor >= l_txn.size():
		_log_grow()
	l_txn[_log_cursor] = txn
	l_q[_log_cursor] = _q
	l_step[_log_cursor] = _step
	l_kind[_log_cursor] = kind
	l_account[_log_cursor] = account
	l_delta[_log_cursor] = delta
	l_qty[_log_cursor] = qty
	l_product[_log_cursor] = product
	l_cause[_log_cursor] = cause
	l_entity[_log_cursor] = entity_ref
	if classed:
		l_prod[_log_cursor] = JWUnits.KIND_PROD_CLASS[kind]
		l_exp[_log_cursor] = JWUnits.KIND_EXP_CLASS[kind]
		l_inc[_log_cursor] = JWUnits.KIND_INC_CLASS[kind]
	else:
		l_prod[_log_cursor] = JWUnits.ProdClass.NONE
		l_exp[_log_cursor] = JWUnits.ExpClass.NONE
		l_inc[_log_cursor] = JWUnits.IncClass.NONE
	_log_cursor += 1


## 下一档容量：按 1.5 倍扩容，且至少 +1（docs/10 §12）。
## 步骤：日志写满时
## 前置：无
## 后置：返回值 > cap
## 不变量：INV-139
## 失败：无
func _next_capacity(cap: int) -> int:
	var next_cap: int = JWUnits.LOG_CAP0
	if cap > 0:
		# rounding: ceil, reason=1.5 倍扩容宁可多要一行也不能因取整停在原容量上
		next_cap = JWMath.ceil_div(JWMath.mul(cap, LOG_GROWTH_NUM), LOG_GROWTH_DEN)
	if next_cap <= cap:
		next_cap = cap + 1
	return next_cap


## log.ledger 的 13 张列数组同步扩容。
## 步骤：写日志时容量耗尽
## 前置：无
## 后置：13 张数组等长且 > 原长
## 不变量：INV-139
## 失败：无
func _log_grow() -> void:
	var next_cap: int = _next_capacity(l_txn.size())
	l_txn.resize(next_cap)
	l_q.resize(next_cap)
	l_step.resize(next_cap)
	l_kind.resize(next_cap)
	l_account.resize(next_cap)
	l_delta.resize(next_cap)
	l_qty.resize(next_cap)
	l_product.resize(next_cap)
	l_cause.resize(next_cap)
	l_entity.resize(next_cap)
	l_prod.resize(next_cap)
	l_exp.resize(next_cap)
	l_inc.resize(next_cap)
	_log_grow_count += 1


## log.physical 的 6 张列数组同步扩容。
## 步骤：写日志时容量耗尽
## 前置：无
## 后置：6 张数组等长且 > 原长
## 不变量：INV-139
## 失败：无
func _physical_grow() -> void:
	var next_cap: int = _next_capacity(p_from.size())
	p_from.resize(next_cap)
	p_to.resize(next_cap)
	p_product.resize(next_cap)
	p_qty.resize(next_cap)
	p_cause.resize(next_cap)
	p_step.resize(next_cap)
	_p_grow_count += 1


## log.rounding 的 4 张列数组同步扩容。
## 步骤：写日志时容量耗尽
## 前置：无
## 后置：4 张数组等长且 > 原长
## 不变量：INV-005, INV-139
## 失败：无
func _rounding_grow() -> void:
	var next_cap: int = _next_capacity(r_site.size())
	r_site.resize(next_cap)
	r_total.resize(next_cap)
	r_parts.resize(next_cap)
	r_residual.resize(next_cap)
	_r_grow_count += 1

# ── §1.7 日志通道协议 ──────────────────────────────────────────────────────

## §1.7 日志协议：每季 S01 重置本季游标（日志不进 state_hash）。
## 步骤：S01
## 前置：phase == S01
## 后置：三条日志通道的写游标归零
## 不变量：INV-011（日志行数对账）
## 失败：无
func log_reset_quarter() -> void:
	_log_cursor = 0
	_p_cursor = 0
	_r_cursor = 0


## §1.7 日志协议：本季已写行数，供 INV-011 / INV-139 对账。
## 步骤：各步末
## 前置：无
## 后置：不改状态
## 不变量：INV-011, INV-139
## 失败：无
func log_row_count() -> int:
	return _log_cursor


## §1.7 日志协议：当前容量；写满时按 1.5 倍扩容并写一条告警行。
## 步骤：各步
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func log_capacity() -> int:
	return l_txn.size()


## log.physical 本季已写行数（INV-047 / INV-139 对账用）。
## 步骤：各步末
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func physical_row_count() -> int:
	return _p_cursor


## log.rounding 本季已写行数（INV-005 对账用）。
## 步骤：各步末
## 前置：无
## 后置：不改状态
## 不变量：INV-005, INV-139
## 失败：无
func rounding_row_count() -> int:
	return _r_cursor


## 三条日志通道累计扩容次数（诊断用；不进 state_hash）。
## 步骤：各步末
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func log_grow_count() -> int:
	return _log_grow_count + _p_grow_count + _r_grow_count

# ── §1.6 状态块协议 ────────────────────────────────────────────────────────

## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：尚未 allocate 过
## 后置：三条日志通道全部 resize 到 JWUnits.LOG_CAP0
## 不变量：INV-136
## 失败：无
func allocate() -> void:
	l_txn.resize(JWUnits.LOG_CAP0)
	l_q.resize(JWUnits.LOG_CAP0)
	l_step.resize(JWUnits.LOG_CAP0)
	l_kind.resize(JWUnits.LOG_CAP0)
	l_account.resize(JWUnits.LOG_CAP0)
	l_delta.resize(JWUnits.LOG_CAP0)
	l_qty.resize(JWUnits.LOG_CAP0)
	l_product.resize(JWUnits.LOG_CAP0)
	l_cause.resize(JWUnits.LOG_CAP0)
	l_entity.resize(JWUnits.LOG_CAP0)
	l_prod.resize(JWUnits.LOG_CAP0)
	l_exp.resize(JWUnits.LOG_CAP0)
	l_inc.resize(JWUnits.LOG_CAP0)
	l_txn.fill(0)
	l_q.fill(0)
	l_step.fill(0)
	l_kind.fill(0)
	l_account.fill(0)
	l_delta.fill(0)
	l_qty.fill(0)
	l_product.fill(0)
	l_cause.fill(0)
	l_entity.fill(0)
	l_prod.fill(0)
	l_exp.fill(0)
	l_inc.fill(0)
	p_from.resize(JWUnits.LOG_CAP0)
	p_to.resize(JWUnits.LOG_CAP0)
	p_product.resize(JWUnits.LOG_CAP0)
	p_qty.resize(JWUnits.LOG_CAP0)
	p_cause.resize(JWUnits.LOG_CAP0)
	p_step.resize(JWUnits.LOG_CAP0)
	p_from.fill(0)
	p_to.fill(0)
	p_product.fill(0)
	p_qty.fill(0)
	p_cause.fill(0)
	p_step.fill(0)
	r_site.resize(JWUnits.LOG_CAP0)
	r_total.resize(JWUnits.LOG_CAP0)
	r_parts.resize(JWUnits.LOG_CAP0)
	r_residual.resize(JWUnits.LOG_CAP0)
	r_site.fill(0)
	r_total.fill(0)
	r_parts.fill(0)
	r_residual.fill(0)
	_agent_sum.resize(JWUnits.AGENT_N)
	_agent_sum.fill(0)
	_touched.resize(JWUnits.AGENT_N)
	_touched.fill(0)
	_touched_mark.resize(JWUnits.AGENT_N)
	_touched_mark.fill(0)
	_touched_n = 0
	_log_cursor = 0
	_p_cursor = 0
	_r_cursor = 0
	_log_grow_count = 0
	_p_grow_count = 0
	_r_grow_count = 0


## §1.6 状态块协议：只读取用（返回引用，调用方不得写）。本类无状态数组。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func state_array(i: int) -> PackedInt64Array:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：仅 LOAD / MIG。本类无状态数组。
## 步骤：LOAD / MIG
## 前置：无
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE
func set_state_array(i: int, v: PackedInt64Array) -> int:
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())


## §1.6 状态块协议：读标量状态（0 == state.meta.txn_seq）。
## 步骤：全部
## 前置：i 在 [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func state_scalar(i: int) -> int:
	if i == 0:
		return txn_seq
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：仅 LOAD / MIG（静态检查限定 systems/content_loader.gd 与 systems/saves.gd）。
## 步骤：LOAD / MIG
## 前置：i 在 [0, STATE_SCALAR_IDS.size())
## 后置：txn_seq 被写
## 不变量：INV-010（实体 ID 来自 entity_seq，重放一致）、INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE
func set_state_scalar(i: int, v: int) -> int:
	if i != 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	if v < 0:
		return JWResult.raise_fault(JWResult.Load.SAVE_CORRUPT, v, 0)
	txn_seq = v
	return JWResult.OK


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
## 不变量：INV-009
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
