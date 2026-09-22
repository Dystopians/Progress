## 账本双边入账 / 科目表覆盖性 / 库存计价 / 居民投资池 —— 契约级单元测试。
##
## 覆盖矩阵 ID（docs/30 §2「类别 A：资金与物资」的 unit 行）：
##   T-U-A-01 test_u_post_balanced、T-U-A-02 test_u_post_rejects_unbalanced、
##   T-U-A-03 test_u_post_rejects_negative_cash、T-U-A-07 test_u_receivable_payable_paired。
## 覆盖不变量（docs/10 §14.2 账本与货币闭合，12 条逐条）：INV-015 … INV-026。
## 另覆盖 docs/10 §2.1 主体表、§2.2 科目表、§2.3 库存计价（裁定 R-SCALE-01）、§2.4 居民投资池。
##
## 期望值来源（docs/30 §0.3 第 4 条）：只用契约文件里的字面量，或本文件内手算、
## 与被测实现不共享代码路径的独立复算。任何「拿实现的返回值当期望值」的写法都不出现在这里。
##
## 符号约定（两套，别混）：
##   · 过账行 `log.ledger.delta_uu` —— docs/10 §2.5：资产增 +，负债增 −，一笔 txn 的行和为 0。
##     `post_multi` 的 `legs_delta` 用的就是这一套（否则「Σ legs_delta == 0」这条前置无法成立）。
##   · 科目余额 `JWAccount.balance` —— docs/10 §2.2 + sim/jw_ids.gd 科目布局注释：
##     资产科目（0..10）余额为正表示资产，负债科目（11..13）余额为正表示负债，
##     这也是 INV-020 恒等式里 `− pay − debt − deposit_liab` 能成立的前提。
##   于是「负债增加」这一腿：过账行是 −X，科目余额是 +X。两处都断言，谁错都红。
##
## 纪律：JWResult 的故障登记是静态的，会跨测试方法残留；每个方法前后都 clear_pending()。
extends JWTest

# ── 夹具常量（FX-MIN 口径：只用到账本底座，不载入内容包） ─────────────────

## 海岬制造业 cell 下标 == idx_cell(HAIJIA=2, MANU=1) == 9，其主体下标 == 1 + 9 == 10。
const CELL_HJ_MANU: int = 9
## 中州制造业 cell 下标 == idx_cell(ZHONGZHOU=1, MANU=1) == 5，其主体下标 == 1 + 5 == 6。
const CELL_ZZ_MANU: int = 5

## docs/10 §2.3：BASE_VALUE_PER_UQS = BASE_PRICE / Q_SCALE = 1e9 / 1e6 = 1000（整除，无余数）。
## 写成字面量而不是算式：这个 1000 正是 R-SCALE-01 迁移中最容易漏改的一处，
## 用实现里的常量去算期望值就等于没检查。
const BASE_VALUE_PER_UQS: int = 1000

var accounts: JWAccount = null
var ledger: JWLedger = null


func before_all() -> void:
	suite_note = "T-U-A-01/02/03/07；INV-015..026；docs/10 §2.1/§2.2/§2.3/§2.4"


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(JWUnits.Phase.S02)
	accounts = JWAccount.new()
	accounts.allocate()
	ledger = JWLedger.new(accounts)
	ledger.allocate()
	ledger.set_context(0, JWUnits.Phase.S02)


func after_each() -> void:
	JWResult.clear_pending()

# ── 夹具辅助（只调 docs/17 §4.6/§4.10 登记过的公开签名） ───────────────────

## 科目下标。等价于 JWIds.idx_account，写成本地包装只是为了让下面的断言短一点。
func _acc(agent: int, code: int) -> int:
	return JWIds.idx_account(agent, code)


## 开账：把初值写成 q = −1 的开账分录（INV-023），这是本文件唯一的「造钱」入口。
## 开账只在 LOAD 期合法（docs/17 §4.10 前置「尚未开始任何季度结算」），
## 故这里临时把上下文切回 IDLE，写完立刻切回 S02 —— 夹具不得靠「结算期还能开账」来偷资源。
func _open(agent: int, code: int, amount_uu: int) -> int:
	ledger.set_context(JWLedger.OPENING_Q, JWUnits.Phase.IDLE)
	var rc: int = ledger.post_opening(agent, code, amount_uu)
	ledger.set_context(0, JWUnits.Phase.S02)
	return rc


## 900 个余额的整表快照，用于「被拒绝的交易不得留下任何痕迹」。
func _snapshot() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(JWUnits.ACCOUNT_N)
	for i: int in JWUnits.ACCOUNT_N:
		out[i] = accounts.get_balance(i)
	return out


## 独立复算的「全经济现金总量」：56 个 cash 科目（4 个 pubserv 不持有现金，docs/10 §2.1）。
## 不调 accounts.total_cash()，否则就是拿被测实现当期望值。
func _cash_total_recomputed() -> int:
	var acc: int = 0
	for a: int in JWUnits.AGENT_N:
		if a >= JWIds.AGENT_PUBSERV_BASE and a < JWIds.AGENT_GROUP_BASE:
			continue
		acc += accounts.get_balance(_acc(a, JWIds.ACC_CASH))
	return acc


## 独立复算的逐主体资产负债残差（INV-020 的原文）：
## cash + Σinv + wip + capital + housing + recv + bondhold + deposit_claim
##   − pay − debt − deposit_liab − nw
func _balance_residual(agent: int) -> int:
	var acc: int = accounts.get_balance(_acc(agent, JWIds.ACC_CASH))
	for s: int in JWUnits.S:
		acc += accounts.get_balance(_acc(agent, JWIds.ACC_INV_BASE + s))
	acc += accounts.get_balance(_acc(agent, JWIds.ACC_WIP))
	acc += accounts.get_balance(_acc(agent, JWIds.ACC_CAPITAL))
	acc += accounts.get_balance(_acc(agent, JWIds.ACC_HOUSING))
	acc += accounts.get_balance(_acc(agent, JWIds.ACC_RECV))
	acc += accounts.get_balance(_acc(agent, JWIds.ACC_BONDHOLD))
	acc += accounts.get_balance(_acc(agent, JWIds.ACC_DEPOSIT_CLAIM))
	acc -= accounts.get_balance(_acc(agent, JWIds.ACC_PAY))
	acc -= accounts.get_balance(_acc(agent, JWIds.ACC_DEBT))
	acc -= accounts.get_balance(_acc(agent, JWIds.ACC_DEPOSIT_LIAB))
	acc -= accounts.get_balance(_acc(agent, JWIds.ACC_NW))
	return acc


## [from_row, to_row) 区间内过账行的有符号和（INV-015 的直接形式）。
func _row_delta_sum(from_row: int, to_row: int) -> int:
	var acc: int = 0
	for i: int in range(from_row, to_row):
		acc += ledger.l_delta[i]
	return acc


## [from_row, to_row) 区间内出现的不同科目个数（INV-015「两端账户不同」的推广形式）。
func _row_distinct_accounts(from_row: int, to_row: int) -> int:
	var seen: PackedInt64Array = PackedInt64Array()
	seen.resize(JWUnits.ACCOUNT_N)
	seen.fill(0)
	var n: int = 0
	for i: int in range(from_row, to_row):
		var a: int = ledger.l_account[i]
		if a >= 0 and a < JWUnits.ACCOUNT_N and seen[a] == 0:
			seen[a] = 1
			n += 1
	return n


## [from_row, to_row) 区间内是否存在金额为 0 的行（INV-015「每行 amount != 0」）。
func _row_has_zero_amount(from_row: int, to_row: int) -> bool:
	for i: int in range(from_row, to_row):
		if ledger.l_delta[i] == 0:
			return true
	return false


## 基年价计值（docs/12 §0.3.3 的 at_base）。独立复算用，不引用实现里的换算函数。
func _at_base(qty_uqs: int) -> int:
	return JWMath.mul_div_floor(qty_uqs, JWUnits.BASE_PRICE, JWUnits.Q_SCALE)

# ── §2.1 双边相等与过账入口 ────────────────────────────────────────────────

## T-U-A-01（docs/30 §2.1）｜INV-015
## 契约原文的三行交易：agent.gov −150_000、agent.cell_hj_manu +100_000、agent.row +50_000。
## 三腿交易只能经 post_multi（post() 是两腿入口，docs/17 §4.10）。
## 拆掉 post_multi 的「Σ legs_delta == 0」前置检查，本用例的行和断言立刻红。
func test_u_post_balanced() -> void:
	var gov: int = _acc(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	var cell: int = _acc(JWIds.agent_of_cell(CELL_HJ_MANU), JWIds.ACC_CASH)
	var row: int = _acc(JWIds.AGENT_ROW, JWIds.ACC_CASH)
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 1_000_000), JWResult.OK, "开账应成功")
	var before: int = ledger.log_row_count()

	var legs_a: PackedInt64Array = PackedInt64Array([gov, cell, row])
	var legs_d: PackedInt64Array = PackedInt64Array([-150_000, 100_000, 50_000])
	var rc: int = ledger.post_multi(JWUnits.Kind.TRANSFER, legs_a, legs_d, 0, -1, 0, 0)
	var after: int = ledger.log_row_count()

	eq_int(rc, JWResult.OK, "T-U-A-01：平衡的三行交易必须被接受（docs/30 §2.1 返回码 == Fault.OK(0)）")
	eq_int(after - before, 3, "T-U-A-01：本笔 txn 应写 3 条过账行")
	eq_int(_row_delta_sum(before, after), 0, "INV-015：一笔 txn 的有符号行之和必须为 0")
	check_false(_row_has_zero_amount(before, after), "INV-015：每条过账行的金额都不得为 0")
	eq_int(_row_distinct_accounts(before, after), 3, "INV-015：三行的科目必须两两不同")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 850_000, "gov 现金 == 1_000_000 − 150_000")
	eq_int(accounts.cash_of(JWIds.agent_of_cell(CELL_HJ_MANU)), 100_000, "cell 现金 == +100_000")
	eq_int(accounts.cash_of(JWIds.AGENT_ROW), 50_000, "row 现金 == +50_000")


## INV-015 / INV-016 / INV-017｜两腿入口 post() 的最小闭合。
## 一次 post() 恰好 2 行、行和为 0、两端余额精确相反；全经济现金总量不因转账改变。
func test_u_post_two_leg_is_double_entry() -> void:
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 500_000), JWResult.OK, "开账应成功")
	var total_before: int = _cash_total_recomputed()
	var before: int = ledger.log_row_count()

	var rc: int = ledger.post(JWUnits.Kind.TRANSFER,
			_acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
			_acc(JWIds.agent_of_group(0), JWIds.ACC_CASH),
			120_000, 0, -1, 0, 0)
	var after: int = ledger.log_row_count()

	eq_int(rc, JWResult.OK, "合法的两腿过账必须被接受")
	eq_int(after - before, 2, "docs/17 §4.10 后置：一次 post() 写 2 条过账行")
	eq_int(_row_delta_sum(before, after), 0, "INV-015：两行之和为 0")
	eq_int(_row_distinct_accounts(before, after), 2, "INV-015：两端账户不同")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 380_000, "付款方 500_000 − 120_000")
	eq_int(accounts.cash_of(JWIds.agent_of_group(0)), 120_000, "收款方 0 + 120_000")
	eq_int(_cash_total_recomputed() - total_before, 0,
			"INV-017：一笔转账后 Σ 全部主体 Δcash 必须恰为 0")


## T-U-A-02（docs/30 §2.1）｜INV-015
## 不平交易必须在落账前被拒：−100_000 / +99_999。
## 拆掉 post_multi 的行和检查，log 行数增量与余额快照两条断言会同时红。
func test_u_post_rejects_unbalanced() -> void:
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 1_000_000), JWResult.OK, "开账应成功")
	var snap: PackedInt64Array = _snapshot()
	var before: int = ledger.log_row_count()

	var legs_a: PackedInt64Array = PackedInt64Array([
		_acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
		_acc(JWIds.agent_of_cell(CELL_HJ_MANU), JWIds.ACC_CASH),
	])
	var legs_d: PackedInt64Array = PackedInt64Array([-100_000, 99_999])
	var rc: int = ledger.post_multi(JWUnits.Kind.TRANSFER, legs_a, legs_d, 0, -1, 0, 0)

	eq_int(rc, JWResult.Fault.LEDGER_IMBALANCE,
			"T-U-A-02：不平交易必须返回 Fault.LEDGER_IMBALANCE(22)（docs/30 §2.1）")
	eq_int(ledger.log_row_count() - before, 0, "T-U-A-02：被拒交易的 log.ledger 行数增量必须为 0")
	eq_int_array(_snapshot(), snap, "T-U-A-02：被拒交易不得改动任何余额（等价于 state_hash 逐位相同）")
	JWResult.clear_pending()


## T-U-A-03（docs/30 §2.1）｜INV-016
## gov.cash == 1_000 时支付 1_001：必须整笔拒绝，绝不允许先扣成负数再想办法。
## 拆掉 JWAccount._apply_delta 的资产为负检查，余额断言立刻红。
func test_u_post_rejects_negative_cash() -> void:
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 1_000), JWResult.OK, "开账应成功")
	var before: int = ledger.log_row_count()

	var rc: int = ledger.post(JWUnits.Kind.TRANSFER,
			_acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
			_acc(JWIds.agent_of_cell(CELL_HJ_MANU), JWIds.ACC_CASH),
			1_001, 0, -1, 0, 0)

	eq_int(rc, JWResult.Fault.NEGATIVE_CASH,
			"T-U-A-03：现金不足必须返回 Fault.NEGATIVE_CASH(20)（docs/30 §2.1）")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 1_000, "T-U-A-03：付款方现金必须精确不变")
	eq_int(accounts.cash_of(JWIds.agent_of_cell(CELL_HJ_MANU)), 0,
			"T-U-A-03：收款方不得凭空收到钱")
	eq_int(ledger.log_row_count() - before, 0, "T-U-A-03：被拒交易的 log.ledger 行数增量必须为 0")
	JWResult.clear_pending()


## INV-015 / INV-016｜多腿交易的整笔回滚。
## 四腿中最后一腿把某主体现金打成负数：前三腿也必须一起消失（docs/17 §4.10「全部行原子生效或全部不生效」）。
func test_u_post_multi_rolls_back_every_leg() -> void:
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 300_000), JWResult.OK, "开账 gov 现金")
	eq_int(_open(JWIds.agent_of_cell(CELL_HJ_MANU), JWIds.ACC_CASH, 10), JWResult.OK, "开账 cell 现金")
	var snap: PackedInt64Array = _snapshot()
	var before: int = ledger.log_row_count()

	# gov −200_000 → group0 +200_000 是合法的；cell −5_000 会击穿 cell 的 10 μU 现金。
	var legs_a: PackedInt64Array = PackedInt64Array([
		_acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
		_acc(JWIds.agent_of_group(0), JWIds.ACC_CASH),
		_acc(JWIds.agent_of_cell(CELL_HJ_MANU), JWIds.ACC_CASH),
		_acc(JWIds.agent_of_group(1), JWIds.ACC_CASH),
	])
	var legs_d: PackedInt64Array = PackedInt64Array([-200_000, 200_000, -5_000, 5_000])
	var rc: int = ledger.post_multi(JWUnits.Kind.TRANSFER, legs_a, legs_d, 0, -1, 0, 0)

	eq_int(rc, JWResult.Fault.NEGATIVE_CASH, "任一腿现金为负 → 整笔 NEGATIVE_CASH(20)")
	eq_int_array(_snapshot(), snap, "INV-016：整笔回滚后 900 个余额必须与事务前逐位相同")
	eq_int(ledger.log_row_count() - before, 0, "被回滚的交易不得留下过账行")
	JWResult.clear_pending()


## INV-015｜两端账户相同的「自转账」必须被拒（docs/10 §14.2：两端账户不同）。
## 它不是无害的空操作：自转账会让 kind 统计与三法分类凭空多出一笔无对手方的流量。
func test_u_post_rejects_same_account() -> void:
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 100_000), JWResult.OK, "开账应成功")
	var before: int = ledger.log_row_count()
	var same: int = _acc(JWIds.AGENT_GOV, JWIds.ACC_CASH)

	var rc: int = ledger.post(JWUnits.Kind.TRANSFER, same, same, 10_000, 0, -1, 0, 0)

	ne_int(rc, JWResult.OK, "INV-015：payer_account == payee_account 必须被拒绝")
	eq_int(ledger.log_row_count() - before, 0, "自转账不得写任何过账行")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 100_000, "自转账不得改动余额")
	JWResult.clear_pending()


## INV-015｜负金额必须被拒（docs/17 §4.10 前置：amount_uu >= 0；失败码 LEDGER_IMBALANCE）。
## 允许负金额等于开了一条「反向转账」的后门，方向不再由 payer → payee 决定。
func test_u_post_rejects_negative_amount() -> void:
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 100_000), JWResult.OK, "开账应成功")
	var before: int = ledger.log_row_count()

	var rc: int = ledger.post(JWUnits.Kind.TRANSFER,
			_acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
			_acc(JWIds.AGENT_ROW, JWIds.ACC_CASH),
			-1, 0, -1, 0, 0)

	eq_int(rc, JWResult.Fault.LEDGER_IMBALANCE,
			"docs/17 §4.10：金额为负 → Fault.LEDGER_IMBALANCE(22)")
	eq_int(ledger.log_row_count() - before, 0, "被拒交易不得写过账行")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 100_000, "被拒交易不得改动余额")
	JWResult.clear_pending()


## INV-015｜「至少 2 行、每行 amount != 0」是两条独立的防线，分别验。
## 单腿交易的行和天然为 0，正好是「只查行和不查行数」这种实现的漏网之鱼；
## 而 delta == 0 的行会把一个不存在的科目拖进三法分类与 kind 统计。
func test_u_post_multi_requires_two_nonzero_legs() -> void:
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 500_000), JWResult.OK, "开账应成功")
	var snap: PackedInt64Array = _snapshot()
	var before: int = ledger.log_row_count()

	var one_a: PackedInt64Array = PackedInt64Array([_acc(JWIds.AGENT_GOV, JWIds.ACC_CASH)])
	var one_d: PackedInt64Array = PackedInt64Array([0])
	ne_int(ledger.post_multi(JWUnits.Kind.TRANSFER, one_a, one_d, 0, -1, 0, 0), JWResult.OK,
			"INV-015：单腿「交易」行和虽为 0，但不足 2 行，必须被拒")
	JWResult.clear_pending()

	var zero_a: PackedInt64Array = PackedInt64Array([
		_acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
		_acc(JWIds.AGENT_ROW, JWIds.ACC_CASH),
		_acc(JWIds.agent_of_group(0), JWIds.ACC_CASH),
	])
	var zero_d: PackedInt64Array = PackedInt64Array([-100_000, 100_000, 0])
	ne_int(ledger.post_multi(JWUnits.Kind.TRANSFER, zero_a, zero_d, 0, -1, 0, 0), JWResult.OK,
			"INV-015：金额为 0 的过账行必须被拒（即使整笔行和为 0）")
	eq_int(ledger.log_row_count() - before, 0, "被拒的两种畸形交易都不得写过账行")
	eq_int_array(_snapshot(), snap, "被拒的两种畸形交易都不得改动任何余额")
	JWResult.clear_pending()


## INV-007｜单笔金额不得超过 AMOUNT_MAX（4e15，R-SCALE-01 后的新上界）。
## 越界金额若被放行，后续的 mul 会在别处溢出，故障现场就不在这笔交易上了。
func test_u_post_rejects_amount_over_ceiling() -> void:
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 1_000_000), JWResult.OK, "开账应成功")
	var before: int = ledger.log_row_count()

	var rc: int = ledger.post(JWUnits.Kind.TRANSFER,
			_acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
			_acc(JWIds.AGENT_ROW, JWIds.ACC_CASH),
			JWUnits.AMOUNT_MAX + 1, 0, -1, 0, 0)

	ne_int(rc, JWResult.OK, "INV-007：金额 > AMOUNT_MAX(4e15) 必须被拒")
	eq_int(ledger.log_row_count() - before, 0, "越界金额不得写过账行")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 1_000_000, "越界金额不得改动余额")
	JWResult.clear_pending()


## INV-016 / INV-048｜「资产不得为负」不止管现金：卖掉超过库存的货同样必须被整笔拒绝。
## docs/17 §4.6 后置原文：若为资产科目且结果 < 0 → 不写、返回 NEGATIVE_CASH 供整笔回滚。
## 这条红了，说明「无提示负库存」可以经账本产生——而 S05 的库存恒等式只检查数量腿，抓不到它。
func test_u_post_rejects_negative_asset_balance() -> void:
	var seller: int = JWIds.agent_of_cell(CELL_HJ_MANU)
	var buyer: int = JWIds.agent_of_cell(CELL_ZZ_MANU)
	var manu: int = JWUnits.Sector.MANU
	eq_int(_open(seller, JWIds.ACC_INV_BASE + manu, 1_000_000_000), JWResult.OK, "卖方库存 1e9")
	eq_int(_open(buyer, JWIds.ACC_CASH, 9_000_000_000), JWResult.OK, "买方现金 9e9")
	var snap: PackedInt64Array = _snapshot()
	var before: int = ledger.log_row_count()

	# 卖方只有 1e9 的库存价值，却要卖出 2e9：库存腿会把资产打成 −1e9。
	var legs_a: PackedInt64Array = PackedInt64Array([
		_acc(buyer, JWIds.ACC_CASH),
		_acc(buyer, JWIds.ACC_INV_BASE + manu),
		_acc(seller, JWIds.ACC_CASH),
		_acc(seller, JWIds.ACC_INV_BASE + manu),
	])
	var legs_d: PackedInt64Array = PackedInt64Array([
		-2_000_000_000, 2_000_000_000, 2_000_000_000, -2_000_000_000,
	])
	var rc: int = ledger.post_multi(JWUnits.Kind.INTERMEDIATE_PURCHASE, legs_a, legs_d,
			2_000_000, manu, 0, 0)

	ne_int(rc, JWResult.OK, "INV-016：库存资产会被打成负数的交易必须被拒绝")
	eq_int_array(_snapshot(), snap, "INV-016：拒绝必须是整笔回滚，买方的现金与入库也不得留下")
	eq_int(ledger.log_row_count() - before, 0, "被拒交易不得写过账行")
	JWResult.clear_pending()


## INV-017 / INV-021｜非现金分录不得以 cash 为资产腿（docs/17 §4.10 后置：cash 科目不被触碰）。
## 若放行，折旧/价差这类「不动现金」的分录就能悄悄搬钱，而 INV-018 仍然成立（总量不变），
## 于是没有任何一条季末检查会发现它。
func test_u_noncash_must_not_touch_cash() -> void:
	var cell_agent: int = JWIds.agent_of_cell(CELL_HJ_MANU)
	eq_int(_open(cell_agent, JWIds.ACC_CASH, 800_000), JWResult.OK, "开账现金")
	var before: int = ledger.log_row_count()

	var rc: int = ledger.post_noncash(JWUnits.Kind.OPERATING_SURPLUS, cell_agent,
			JWIds.ACC_CASH, -100_000, 0, 0)

	ne_int(rc, JWResult.OK, "INV-017：非现金分录以 cash 为资产腿必须被拒")
	eq_int(accounts.cash_of(cell_agent), 800_000, "现金必须精确不变")
	eq_int(ledger.log_row_count() - before, 0, "被拒的非现金分录不得写过账行")
	JWResult.clear_pending()


## INV-023 / docs/10 §2.2｜开账的两条边界：nw 不单独开账；结算开始后不得再开账。
## 后者是「在测试里偷偷补入资源」这条人工评审点（计划书 §16 第四条）的机器版：
## 若结算期还能调 post_opening，任何一条现金约束都可以被绕过。
func test_u_opening_rejects_nw_and_late_calls() -> void:
	ledger.set_context(JWLedger.OPENING_Q, JWUnits.Phase.IDLE)
	ne_int(ledger.post_opening(JWIds.AGENT_GOV, JWIds.ACC_NW, 1_000_000), JWResult.OK,
			"docs/10 §2.2：nw 是派生的平衡项，不得单独开账")
	eq_int(accounts.get_balance(_acc(JWIds.AGENT_GOV, JWIds.ACC_NW)), 0, "nw 必须仍为 0")
	JWResult.clear_pending()

	ne_int(ledger.post_opening(JWIds.AGENT_GOV, JWIds.ACC_CASH, -1), JWResult.OK,
			"开账金额为负必须被拒")
	JWResult.clear_pending()

	# 进入结算之后再开账：必须被拒，且现金总量不变。
	ledger.set_context(0, JWUnits.Phase.S02)
	var total_before: int = _cash_total_recomputed()
	ne_int(ledger.post_opening(JWIds.AGENT_GOV, JWIds.ACC_CASH, 1_000_000_000), JWResult.OK,
			"INV-023：结算开始后不得再开账（否则等于凭空补入资源）")
	eq_int(_cash_total_recomputed(), total_before, "INV-018：被拒的开账不得改变现金总量")
	JWResult.clear_pending()


## INV-114（在过账入口处）｜未登记三重分类的 kind 必须被拒。
## docs/17 §4.10 失败行：kind 未分类 → Fault.LEDGER_KIND_UNCLASSIFIED(52)。
## kind 的合法闭区间是 [1, 28]（JWUnits.Kind 逐字对应 docs/11 §5.3 的 28 项）。
func test_u_post_rejects_unclassified_kind() -> void:
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 100_000), JWResult.OK, "开账应成功")
	var payer: int = _acc(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	var payee: int = _acc(JWIds.AGENT_ROW, JWIds.ACC_CASH)
	var before: int = ledger.log_row_count()

	eq_int(ledger.post(0, payer, payee, 1_000, 0, -1, 0, 0),
			JWResult.Fault.LEDGER_KIND_UNCLASSIFIED, "kind == 0 是占位下标，不是合法交易类型")
	JWResult.clear_pending()
	eq_int(ledger.post(JWUnits.KIND_N, payer, payee, 1_000, 0, -1, 0, 0),
			JWResult.Fault.LEDGER_KIND_UNCLASSIFIED, "kind == KIND_N(29) 越出 docs/11 §5.3 的闭集合")
	eq_int(ledger.log_row_count() - before, 0, "未分类 kind 不得落账")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 100_000, "未分类 kind 不得改动余额")
	JWResult.clear_pending()


## INV-021 / INV-017｜非现金分录的白名单与「不碰现金」。
## docs/17 §4.10 前置：kind ∈ {DEPRECIATION, OPERATING_SURPLUS, PRICE_VARIANCE,
## OPENING_BALANCE, WRITEOFF}；后置：cash 科目不被触碰。
func test_u_noncash_respects_kind_whitelist() -> void:
	var cell_agent: int = JWIds.agent_of_cell(CELL_HJ_MANU)
	eq_int(_open(cell_agent, JWIds.ACC_CAPITAL, 4_000_000_000), JWResult.OK, "开账固定资产")
	eq_int(_open(cell_agent, JWIds.ACC_CASH, 700_000), JWResult.OK, "开账现金")
	var cash_before: int = accounts.cash_of(cell_agent)
	var rows_before: int = ledger.log_row_count()

	# 白名单外的 kind：工资支付不是非现金分录。
	eq_int(ledger.post_noncash(JWUnits.Kind.WAGE_PAYMENT, cell_agent, JWIds.ACC_CAPITAL,
			-1_000, 0, 0), JWResult.Fault.LEDGER_KIND_UNCLASSIFIED,
			"docs/17 §4.10：kind 不在非现金白名单 → LEDGER_KIND_UNCLASSIFIED(52)")
	eq_int(ledger.log_row_count() - rows_before, 0, "白名单外的非现金分录不得落账")
	JWResult.clear_pending()

	# 白名单内：折旧 −1_000_000 μU。
	var rc: int = ledger.post_noncash(JWUnits.Kind.DEPRECIATION, cell_agent,
			JWIds.ACC_CAPITAL, -1_000_000, 0, 0)
	eq_int(rc, JWResult.OK, "折旧是合法的非现金分录")
	eq_int(accounts.get_balance(_acc(cell_agent, JWIds.ACC_CAPITAL)), 3_999_000_000,
			"资本 4_000_000_000 − 1_000_000")
	eq_int(accounts.cash_of(cell_agent), cash_before, "INV-017：非现金分录不得触碰 cash 科目")


## INV-021｜净值不得自己动：Δnw 必须等于本笔损益腿的金额，且只由分录产生。
## 折旧 −1_000_000 ⇒ nw 恰好 −1_000_000；纯现金转账 ⇒ 两端 nw 等额反向。
func test_u_net_worth_moves_only_with_postings() -> void:
	var cell_agent: int = JWIds.agent_of_cell(CELL_HJ_MANU)
	eq_int(_open(cell_agent, JWIds.ACC_CAPITAL, 2_000_000_000), JWResult.OK, "开账固定资产")
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 900_000), JWResult.OK, "开账 gov 现金")
	var nw_cell_0: int = accounts.net_worth_of(cell_agent)
	var nw_gov_0: int = accounts.net_worth_of(JWIds.AGENT_GOV)
	var nw_group_0: int = accounts.net_worth_of(JWIds.agent_of_group(0))

	eq_int(ledger.post_noncash(JWUnits.Kind.DEPRECIATION, cell_agent, JWIds.ACC_CAPITAL,
			-1_000_000, 0, 0), JWResult.OK, "折旧应成功")
	eq_int(accounts.net_worth_of(cell_agent) - nw_cell_0, -1_000_000,
			"INV-021：折旧 1_000_000 μU ⇒ 净值恰好下降 1_000_000（不多不少）")

	eq_int(ledger.post(JWUnits.Kind.TRANSFER, _acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
			_acc(JWIds.agent_of_group(0), JWIds.ACC_CASH), 250_000, 0, -1, 0, 0),
			JWResult.OK, "转移支付应成功")
	eq_int(accounts.net_worth_of(JWIds.AGENT_GOV) - nw_gov_0, -250_000,
			"INV-021：付款方净值下降额 == 转账额")
	eq_int(accounts.net_worth_of(JWIds.agent_of_group(0)) - nw_group_0, 250_000,
			"INV-021：收款方净值上升额 == 转账额（双边，容差 0）")


## T-U-A-07（docs/30 §2.1 的应收应付一半）｜INV-019
## 造一笔欠付：政府应付 300_000，承包方等额应收。Σ recv == Σ pay 必须精确成立。
## 注：本用例只覆盖账本侧；gov.arrears_uu 与 log.arrears 的增量归 JWTreasury 的用例（见 open_questions）。
func test_u_receivable_payable_paired() -> void:
	var payee_agent: int = JWIds.agent_of_cell(CELL_HJ_MANU)
	var rows_before: int = ledger.log_row_count()

	# 欠付：政府记应付（负债 +300_000 ⇒ 过账行 −300_000），承包方记应收（资产 +300_000）。
	var legs_a: PackedInt64Array = PackedInt64Array([
		_acc(JWIds.AGENT_GOV, JWIds.ACC_PAY),
		_acc(payee_agent, JWIds.ACC_RECV),
	])
	var legs_d: PackedInt64Array = PackedInt64Array([-300_000, 300_000])
	var rc: int = ledger.post_multi(JWUnits.Kind.PROJECT_PAYMENT, legs_a, legs_d, 0, -1, 0, 0)

	eq_int(rc, JWResult.OK, "欠付分录（应付/应收两腿）必须被接受")
	eq_int(_row_delta_sum(rows_before, ledger.log_row_count()), 0,
			"INV-015：应付 −300_000 与应收 +300_000 的行和为 0（docs/10 §2.5 负债增记负）")
	eq_int(accounts.get_balance(_acc(JWIds.AGENT_GOV, JWIds.ACC_PAY)), 300_000,
			"docs/10 §2.2：负债科目余额为正表示负债，应付 == 300_000")
	eq_int(accounts.get_balance(_acc(payee_agent, JWIds.ACC_RECV)), 300_000,
			"承包方应收 == 300_000")

	var recv_sum: int = 0
	var pay_sum: int = 0
	for a: int in JWUnits.AGENT_N:
		recv_sum += accounts.get_balance(_acc(a, JWIds.ACC_RECV))
		pay_sum += accounts.get_balance(_acc(a, JWIds.ACC_PAY))
	eq_int(recv_sum, 300_000, "全经济应收合计 == 300_000")
	eq_int(recv_sum - pay_sum, 0, "INV-019：Σ recv == Σ pay，残差恰为 0")
	eq_int(accounts.check_receivable_payable(), JWResult.OK,
			"INV-019：实现自带的应收应付对账也必须通过")


## INV-020｜逐主体资产负债恒等式，独立复算 60 个主体。
## 期望值不是「实现算出来的 nw」，而是 docs/10 §14.2 INV-020 原文的左式减右式 == 0。
func test_u_balance_sheet_identity_every_agent() -> void:
	var cell_agent: int = JWIds.agent_of_cell(CELL_HJ_MANU)
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 2_000_000_000), JWResult.OK, "开账 gov 现金")
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_DEBT, 1_500_000_000), JWResult.OK, "开账 gov 计息借款")
	eq_int(_open(cell_agent, JWIds.ACC_CAPITAL, 3_000_000_000), JWResult.OK, "开账 cell 资本")
	eq_int(_open(cell_agent, JWIds.ACC_INV_BASE + JWUnits.Sector.MANU, 1_000_000_000),
			JWResult.OK, "开账 cell 制成品库存")
	eq_int(_open(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD, 1_500_000_000),
			JWResult.OK, "开账投资池持债")
	eq_int(_open(JWIds.AGENT_INVPOOL, JWIds.ACC_DEPOSIT_LIAB, 1_500_000_000),
			JWResult.OK, "开账投资池存款负债")
	eq_int(_open(JWIds.agent_of_group(7), JWIds.ACC_DEPOSIT_CLAIM, 1_500_000_000),
			JWResult.OK, "开账居民存款债权")

	eq_int(ledger.post(JWUnits.Kind.TRANSFER, _acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
			_acc(cell_agent, JWIds.ACC_CASH), 700_000_000, 0, -1, 0, 0),
			JWResult.OK, "补助转账应成功")
	eq_int(ledger.post_noncash(JWUnits.Kind.DEPRECIATION, cell_agent, JWIds.ACC_CAPITAL,
			-90_000_000, 0, 0), JWResult.OK, "折旧应成功")

	var broken: int = 0
	for a: int in JWUnits.AGENT_N:
		if _balance_residual(a) != 0:
			broken += 1
	eq_int(broken, 0, "INV-020：60 个主体的资产负债恒等式残差必须全部恰为 0")
	eq_int(accounts.check_balance_sheet(), JWResult.OK,
			"INV-020：实现自带的 check_balance_sheet 也必须通过（与上面的独立复算互证）")
	JWResult.clear_pending()


## INV-017 / INV-018｜现金闭合。
## 转账、欠付、折旧三类分录都不得改变全经济现金总量；错误的期望总量必须被 check_cash_closure 抓住。
func test_u_cash_total_is_conserved() -> void:
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 5_000_000_000), JWResult.OK, "开账 gov 现金")
	eq_int(_open(JWIds.AGENT_ROW, JWIds.ACC_CASH, 1_000_000_000), JWResult.OK, "开账外部世界现金")
	var total: int = _cash_total_recomputed()
	eq_int(total, 6_000_000_000, "开账后全经济现金总量 == 5e9 + 1e9（独立复算，不调 total_cash()）")

	eq_int(ledger.post(JWUnits.Kind.IMPORT, _acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
			_acc(JWIds.AGENT_ROW, JWIds.ACC_CASH), 400_000_000, 0, -1, 0, 0),
			JWResult.OK, "进口付汇应成功")
	eq_int(ledger.post(JWUnits.Kind.TRANSFER, _acc(JWIds.AGENT_ROW, JWIds.ACC_CASH),
			_acc(JWIds.agent_of_group(3), JWIds.ACC_CASH), 250_000_000, 0, -1, 0, 0),
			JWResult.OK, "对内转账应成功")
	eq_int(_open(JWIds.agent_of_cell(CELL_ZZ_MANU), JWIds.ACC_CAPITAL, 2_000_000_000),
			JWResult.OK, "开账 cell 资本（折旧要有东西可折）")
	eq_int(ledger.post_noncash(JWUnits.Kind.DEPRECIATION, JWIds.agent_of_cell(CELL_ZZ_MANU),
			JWIds.ACC_CAPITAL, -120_000_000, 0, 0), JWResult.OK, "折旧应成功")

	eq_int(_cash_total_recomputed(), 6_000_000_000,
			"INV-018：现金总量恒定（首版不模拟商业银行与货币创造）")
	eq_int(accounts.total_cash(), 6_000_000_000,
			"INV-018：实现的 total_cash() 必须等于独立复算值")
	eq_int(accounts.check_cash_closure(6_000_000_000, 6_000_000_000), JWResult.OK,
			"INV-017/018：期初期末总量一致时必须通过")

	eq_int(accounts.check_cash_closure(6_000_000_001, 6_000_000_000),
			JWResult.Fault.CASH_TOTAL_CHANGED,
			"INV-018：期望总量与实际差 1 μU 就必须返回 CASH_TOTAL_CHANGED(24)")
	eq_int(JWResult.pending_code(), JWResult.Fault.CASH_TOTAL_CHANGED,
			"现金闭合失败必须登记故障，而不是只返回码")
	JWResult.clear_pending()


## INV-026｜外部世界是显式账户，不存在无对手方的对外收支。
## 对外支付后：国内现金减少额 == agent.row 现金增加额，总量不变。
func test_u_row_is_explicit_counterparty() -> void:
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 3_000_000_000), JWResult.OK, "开账 gov 现金")
	var row_before: int = accounts.cash_of(JWIds.AGENT_ROW)
	var total_before: int = _cash_total_recomputed()

	eq_int(ledger.post(JWUnits.Kind.IMPORT, _acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
			_acc(JWIds.AGENT_ROW, JWIds.ACC_CASH), 800_000_000, 0, -1, 0, 0),
			JWResult.OK, "进口付款必须以 agent.row 为对手方")
	eq_int(accounts.cash_of(JWIds.AGENT_ROW) - row_before, 800_000_000,
			"INV-026：对外付款必须等额进入 agent.row，而不是消失")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 2_200_000_000, "gov 现金 == 3e9 − 8e8")
	eq_int(_cash_total_recomputed() - total_before, 0,
			"INV-018：把外部世界算进来之后，对外收支也不改变现金总量")


## INV-022｜账本之外不存在改余额的 API。
## 两条防线：JWAccount 不暴露任何公开写接口；唯一写入口 _apply_delta 在事务之外不生效。
func test_u_no_direct_balance_writer() -> void:
	check_false(accounts.has_method("set_balance"), "INV-022：不得存在公开的 set_balance")
	check_false(accounts.has_method("set_cash"), "INV-022：不得存在公开的 set_cash")
	check_false(accounts.has_method("add_balance"), "INV-022：不得存在公开的 add_balance")
	check_false(accounts.has_method("set_inv"), "INV-022：不得存在公开的 set_inv")
	check(accounts.has_method("_apply_delta"),
			"docs/17 §4.6：唯一的余额写入口 _apply_delta 必须存在（供静态检查锚定）")

	var acc_idx: int = _acc(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	var before: int = accounts.get_balance(acc_idx)
	accounts._apply_delta(acc_idx, 1_000_000)
	eq_int(accounts.get_balance(acc_idx), before,
			"docs/17 §4.6 前置：_owner_guard == 0（不在 post() 事务内）时不得写入余额")
	JWResult.clear_pending()


## INV-023｜初值经 q = −1 的开账分录生成，开账后 agent.opening 现金恒为 0。
## 拆掉 post_opening 的对手方配平，行和断言与 opening 现金断言会同时红。
func test_u_opening_entries_are_postings() -> void:
	var rows_before: int = ledger.log_row_count()
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 2_000_000_000), JWResult.OK,
			"docs/10 §3.1：国库现金初值 2 U == 2_000_000_000 μU")
	var rows_after: int = ledger.log_row_count()

	ge_int(rows_after - rows_before, 2, "INV-023：开账必须写成分录（至少两腿），不是直接赋值")
	eq_int(_row_delta_sum(rows_before, rows_after), 0, "INV-015：开账分录的行和同样必须为 0")
	for i: int in range(rows_before, rows_after):
		eq_int(ledger.l_q[i], -1, "INV-023：开账分录的 q 必须是 −1")
		eq_int(ledger.l_kind[i], JWUnits.Kind.OPENING_BALANCE,
				"INV-023：开账分录的 kind 必须是 24 opening_balance（docs/11 §5.3）")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 2_000_000_000, "开账后国库现金 == 2_000_000_000")
	eq_int(accounts.cash_of(JWIds.AGENT_OPENING), 0,
			"docs/10 §2.1 + OQ-217：开账完成后 agent.opening 的现金恒为 0")
	eq_int(_balance_residual(JWIds.AGENT_GOV), 0, "INV-020 从第 0 秒起就成立")
	eq_int(_balance_residual(JWIds.AGENT_OPENING), 0, "开账对手方自身的恒等式也必须成立")

# ── §2.2 科目表覆盖性（docs/10 §2.1 / §2.2） ───────────────────────────────

## docs/10 §2.1 主体表｜60 个主体的下标布局无重叠、无空洞，且现金主体口径为 56 / 55。
## 这条红了说明有主体在结构上无法被寻址——「无来源资金」就又变得可表达了。
func test_u_agent_layout_covers_sixty_agents() -> void:
	eq_int(JWUnits.AGENT_N, 60, "docs/10 §2.1：首版共 60 个主体")
	eq_int(1 + JWUnits.CELL + JWUnits.PUBSERV + JWUnits.GROUP + 3, 60,
			"1 gov + 16 cell + 4 pubserv + 36 group + invpool + row + opening == 60")

	var seen: PackedInt64Array = PackedInt64Array()
	seen.resize(JWUnits.AGENT_N)
	seen.fill(0)
	seen[JWIds.AGENT_GOV] += 1
	for c: int in JWUnits.CELL:
		seen[JWIds.agent_of_cell(c)] += 1
	for r: int in JWUnits.R:
		seen[JWIds.agent_of_pubserv(r)] += 1
	for g: int in JWUnits.GROUP:
		seen[JWIds.agent_of_group(g)] += 1
	seen[JWIds.AGENT_INVPOOL] += 1
	seen[JWIds.AGENT_ROW] += 1
	seen[JWIds.AGENT_OPENING] += 1

	var wrong: int = 0
	for a: int in JWUnits.AGENT_N:
		if seen[a] != 1:
			wrong += 1
	eq_int(wrong, 0, "docs/10 §2.1：每个主体下标必须恰好被一类主体占用一次（无重叠、无空洞）")
	eq_int(JWIds.agent_of_cell(0), 1, "cell 段起点 == 1")
	eq_int(JWIds.agent_of_cell(JWUnits.CELL - 1), 16, "cell 段终点 == 16")
	eq_int(JWIds.agent_of_pubserv(0), 17, "pubserv 段起点 == 17")
	eq_int(JWIds.agent_of_group(0), 21, "group 段起点 == 21")
	eq_int(JWIds.agent_of_group(JWUnits.GROUP - 1), 56, "group 段终点 == 56")
	eq_int(JWIds.AGENT_CASH_ACCOUNTS, 60 - JWUnits.PUBSERV,
			"持现金的科目数 == 60 − 4 个 pubserv（其支付由 agent.gov 执行）")
	eq_int(JWIds.AGENT_CASH_ACTIVE, 55, "docs/10 §2.1：真正持有现金的主体 55 个（不含 opening）")


## docs/10 §2.2 科目表｜15 个科目代码覆盖 0..14，互不重叠；900 个科目下标是双射。
## 少一个科目代码，某类资产就只能挂在别的科目上——INV-020 会在一个「看起来合理」的数上失败。
func test_u_chart_of_accounts_is_complete() -> void:
	eq_int(JWUnits.ACCOUNT_CODE_N, 15, "docs/10 §2.2：科目表共 15 个科目代码")
	eq_int(JWUnits.ACCOUNT_N, 900, "60 主体 × 15 科目 == 900")
	eq_int(JWUnits.AGENT_N * JWUnits.ACCOUNT_CODE_N, JWUnits.ACCOUNT_N, "ACCOUNT_N 必须是两者之积")

	var codes: PackedInt64Array = PackedInt64Array()
	codes.resize(JWUnits.ACCOUNT_CODE_N)
	codes.fill(0)
	codes[JWIds.ACC_CASH] += 1
	for s: int in JWUnits.S:
		codes[JWIds.ACC_INV_BASE + s] += 1
	codes[JWIds.ACC_WIP] += 1
	codes[JWIds.ACC_CAPITAL] += 1
	codes[JWIds.ACC_HOUSING] += 1
	codes[JWIds.ACC_RECV] += 1
	codes[JWIds.ACC_BONDHOLD] += 1
	codes[JWIds.ACC_DEPOSIT_CLAIM] += 1
	codes[JWIds.ACC_PAY] += 1
	codes[JWIds.ACC_DEBT] += 1
	codes[JWIds.ACC_DEPOSIT_LIAB] += 1
	codes[JWIds.ACC_NW] += 1
	var wrong: int = 0
	for c: int in JWUnits.ACCOUNT_CODE_N:
		if codes[c] != 1:
			wrong += 1
	eq_int(wrong, 0, "docs/10 §2.2：cash/inv×4/wip/capital/housing/recv/bondhold/deposit_claim/"
			+ "pay/debt/deposit_liab/nw 必须恰好覆盖 0..14 各一次")
	eq_int(JWIds.ACC_CASH, 0, "cash 必须是 0 号科目（现金闭合按该下标求和）")
	eq_int(JWIds.ACC_INV_BASE + JWUnits.S - 1, 4, "四个库存科目占 1..4")
	eq_int(JWIds.ACC_NW, JWUnits.ACCOUNT_CODE_N - 1, "nw 是最后一个科目（平衡项）")

	var hit: PackedInt64Array = PackedInt64Array()
	hit.resize(JWUnits.ACCOUNT_N)
	hit.fill(0)
	for a: int in JWUnits.AGENT_N:
		for c: int in JWUnits.ACCOUNT_CODE_N:
			var idx: int = JWIds.idx_account(a, c)
			in_range_int(idx, 0, JWUnits.ACCOUNT_N - 1, "idx_account 必须落在 [0, 900)")
			hit[idx] += 1
	var dup: int = 0
	for i: int in JWUnits.ACCOUNT_N:
		if hit[i] != 1:
			dup += 1
	eq_int(dup, 0, "idx_account 必须是 60×15 → 0..899 的双射（无碰撞、无空洞）")


## docs/17 §1.3 查询约定｜科目下标越界返回 0 并登记 INDEX_OUT_OF_RANGE，不静默返回垃圾值。
func test_u_account_index_out_of_range_is_registered() -> void:
	eq_int(accounts.get_balance(JWUnits.ACCOUNT_N), 0, "越界读必须返回 0")
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE,
			"docs/17 §1.3：越界查询必须登记 INDEX_OUT_OF_RANGE(92)")
	JWResult.clear_pending()
	eq_int(accounts.get_balance(-1), 0, "负下标同样返回 0")
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE, "负下标同样登记越界")
	JWResult.clear_pending()

# ── §2.3 库存计价（裁定 R-SCALE-01） ───────────────────────────────────────

## docs/10 §2.3 + docs/12 §0.3.3｜库存按基年价计价，换算系数恒为 1000，且整除无余数。
## R-SCALE-01 之前这个系数是 1，「μU 数值 == μQ_s 数值」曾经字面成立；
## 本用例钉死新系数：任何一处漏改都会让库存价值少算 1000 倍，且不触发任何区间检查。
func test_u_inventory_valued_at_base_price() -> void:
	eq_int(JWUnits.BASE_PRICE, 1_000_000_000, "R-SCALE-01：BASE_PRICE == 1e9 μU/Q_s")
	eq_int(JWUnits.Q_SCALE, 1_000_000, "Q_SCALE 不随货币刻度改变")
	eq_int(JWMath.floor_div(JWUnits.BASE_PRICE, JWUnits.Q_SCALE), BASE_VALUE_PER_UQS,
			"docs/10 §2.3：BASE_VALUE_PER_UQS == 1000")
	eq_int(JWMath.mul(BASE_VALUE_PER_UQS, JWUnits.Q_SCALE), JWUnits.BASE_PRICE,
			"1000 × Q_SCALE 必须精确还原 BASE_PRICE（整除、无余数）")

	eq_int(_at_base(1), 1_000, "1 μQ_s 的基年价值 == 1000 μU")
	eq_int(_at_base(1_000_000), 1_000_000_000, "1 Q_s 的基年价值 == BASE_PRICE")
	eq_int(_at_base(1_500_000), 1_500_000_000, "1.5 Q_s 的基年价值 == 1.5e9 μU")
	ne_int(_at_base(1_500_000), 1_500_000,
			"R-SCALE-01 回归哨兵：若价值等于数量本身，说明换算漏乘了 1000")


## docs/10 §2.3｜库存科目余额恒等于 1000 × 库存数量；买方的价差调节项 == at_base − 实付。
## 用两笔方向相反的成交（低于/高于基年价）各验一次，正负两侧都不许含糊。
func test_u_inventory_purchase_records_price_variance() -> void:
	var buyer: int = JWIds.agent_of_cell(CELL_ZZ_MANU)
	var seller: int = JWIds.agent_of_cell(CELL_HJ_MANU)
	var manu: int = JWUnits.Sector.MANU
	var qty: int = 1_500_000                       # μQ_s，基年价值 1_500_000_000 μU
	eq_int(_open(buyer, JWIds.ACC_CASH, 4_000_000_000), JWResult.OK, "开账买方现金")
	eq_int(_open(seller, JWIds.ACC_INV_BASE + manu, 3_000_000_000), JWResult.OK, "开账卖方库存")
	var nw_buyer_0: int = accounts.net_worth_of(buyer)

	# 成交价低于基年价：实付 1_400_000_000，入库计 1_500_000_000。
	var legs_a: PackedInt64Array = PackedInt64Array([
		_acc(buyer, JWIds.ACC_CASH),
		_acc(buyer, JWIds.ACC_INV_BASE + manu),
		_acc(seller, JWIds.ACC_CASH),
		_acc(seller, JWIds.ACC_INV_BASE + manu),
	])
	var legs_d: PackedInt64Array = PackedInt64Array([
		-1_400_000_000, 1_500_000_000, 1_400_000_000, -1_500_000_000,
	])
	eq_int(ledger.post_multi(JWUnits.Kind.INTERMEDIATE_PURCHASE, legs_a, legs_d,
			qty, manu, 0, 0), JWResult.OK, "按基年价入库的四腿成交必须被接受")

	eq_int(accounts.inv_of(buyer, manu), 1_500_000_000,
			"docs/10 §2.3：入库价值 == 1000 × 1_500_000 μQ_s，与实付价无关")
	eq_int(accounts.inv_of(buyer, manu), JWMath.mul(BASE_VALUE_PER_UQS, qty),
			"库存科目的 μU 数值恒等于 1000 倍的 μQ_s 数值")
	eq_int(accounts.inv_of(seller, manu), 1_500_000_000, "卖方库存 3e9 − 1.5e9")
	eq_int(accounts.cash_of(buyer), 2_600_000_000, "买方现金 4e9 − 1.4e9（实付价，不是计价价）")

	var variance: int = _at_base(qty) - 1_400_000_000
	eq_int(variance, 100_000_000, "docs/10 §2.3：价差 == at_base(qty) − paid == +1e8")
	eq_int(accounts.net_worth_of(buyer) - nw_buyer_0, 100_000_000,
			"INV-119：买方净值的变化恰好是这笔价差，不承认持有损益之外的任何差额")

	# docs/10 §2.5：过账行必须带关联数量与产品下标，否则 INV-119「价差逐笔可追溯」无从谈起。
	var last: int = ledger.log_row_count()
	var qty_rows: int = 0
	for i: int in range(last - 4, last):
		if ledger.l_qty[i] != 0:
			qty_rows += 1
			eq_int(ledger.l_product[i], manu, "带数量的过账行必须登记产品下标 == sector.manu(1)")
	ge_int(qty_rows, 1, "docs/10 §2.5：实物成交必须至少有一条行登记 qty_uqs")

	# 反向一笔：成交价高于基年价 ⇒ 价差为负。只验正侧会放过「对负价差取绝对值」这类实现。
	var nw_buyer_1: int = accounts.net_worth_of(buyer)
	var legs_d2: PackedInt64Array = PackedInt64Array([
		-1_600_000_000, 1_500_000_000, 1_600_000_000, -1_500_000_000,
	])
	eq_int(ledger.post_multi(JWUnits.Kind.INTERMEDIATE_PURCHASE, legs_a, legs_d2,
			qty, manu, 0, 0), JWResult.OK, "高于基年价的成交同样必须被接受")
	eq_int(_at_base(qty) - 1_600_000_000, -100_000_000,
			"docs/10 §2.3：价差可正可负，这一笔是 −1e8")
	eq_int(accounts.net_worth_of(buyer) - nw_buyer_1, -100_000_000,
			"买方净值必须等额下降；对负价差取绝对值或截断为 0 都会在这里露馅")
	eq_int(accounts.inv_of(buyer, manu), 3_000_000_000,
			"两笔各 1.5e9 的基年价入库 ⇒ 库存价值 3e9，与两次不同的成交价无关")


## docs/10 §2.3 + INV-007｜库存计价在契约上界处仍与金额上限相容，且必须走 mul_div_floor。
## 裸乘 QTY_MAX × BASE_PRICE == 1e21 真的溢出 int64（R-SCALE-01 连带要求 1）。
func test_u_inventory_value_ceiling_requires_mul_div_floor() -> void:
	eq_int(_at_base(JWUnits.QTY_MAX), 1_000_000_000_000_000,
			"QTY_MAX(1e12 μQ_s) 的基年价值 == 1e15 μU")
	le_int(1_000_000_000_000_000, JWUnits.AMOUNT_MAX,
			"INV-007：1e15 必须仍在 AMOUNT_MAX(4e15) 之内")
	eq_int(JWMath.mul(JWUnits.QTY_MAX, JWUnits.BASE_PRICE), 0,
			"裸乘 1e12 × 1e9 溢出 int64，mul 必须返回 0 而不是回卷值")
	eq_int(JWResult.pending_code(), JWResult.Fault.INT_OVERFLOW,
			"R-SCALE-01：裸乘必须登记 INT_OVERFLOW(90)，这不是理论风险")
	JWResult.clear_pending()

# ── §2.4 居民投资池 agent.invpool ─────────────────────────────────────────

## INV-024｜Σ group.deposit_uu == invpool.deposit_liab == invpool.cash + invpool.bondhold。
## 三段等式在开账后、居民新增存款后、投资池买债后各验一次——买债只改变资产构成，不改变总额。
func test_u_invpool_deposit_identity() -> void:
	eq_int(_open(JWIds.agent_of_group(0), JWIds.ACC_DEPOSIT_CLAIM, 500_000), JWResult.OK, "组 0 存款")
	eq_int(_open(JWIds.agent_of_group(1), JWIds.ACC_DEPOSIT_CLAIM, 300_000), JWResult.OK, "组 1 存款")
	eq_int(_open(JWIds.agent_of_group(2), JWIds.ACC_DEPOSIT_CLAIM, 200_000), JWResult.OK, "组 2 存款")
	eq_int(_open(JWIds.AGENT_INVPOOL, JWIds.ACC_DEPOSIT_LIAB, 1_000_000), JWResult.OK, "池存款负债")
	eq_int(_open(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH, 600_000), JWResult.OK, "池现金")
	eq_int(_open(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD, 400_000), JWResult.OK, "池持债")
	eq_int(_open(JWIds.agent_of_group(0), JWIds.ACC_CASH, 200_000), JWResult.OK, "组 0 现金")
	eq_int(_open(JWIds.AGENT_GOV, JWIds.ACC_CASH, 1_000), JWResult.OK, "gov 现金（发债收款用）")

	_assert_invpool_identity(1_000_000, "开账后")

	# 居民新增存款 50_000：group.cash −，group.deposit_claim +，pool.cash +，pool.deposit_liab +。
	var legs_a: PackedInt64Array = PackedInt64Array([
		_acc(JWIds.agent_of_group(0), JWIds.ACC_CASH),
		_acc(JWIds.agent_of_group(0), JWIds.ACC_DEPOSIT_CLAIM),
		_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH),
		_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_DEPOSIT_LIAB),
	])
	var legs_d: PackedInt64Array = PackedInt64Array([-50_000, 50_000, 50_000, -50_000])
	eq_int(ledger.post_multi(JWUnits.Kind.TRANSFER, legs_a, legs_d, 0, -1, 0, 0),
			JWResult.OK, "居民存款分录（docs/12 §6：post(group.cash -> invpool.cash) 且 deposit 双边）")
	_assert_invpool_identity(1_050_000, "新增存款 50_000 后")

	# 投资池认购新债 400_000：现金换持债，存款负债不变。
	var bond_a: PackedInt64Array = PackedInt64Array([
		_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH),
		_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD),
		_acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
		_acc(JWIds.AGENT_GOV, JWIds.ACC_DEBT),
	])
	var bond_d: PackedInt64Array = PackedInt64Array([-400_000, 400_000, 400_000, -400_000])
	eq_int(ledger.post_multi(JWUnits.Kind.BOND_ISSUE, bond_a, bond_d, 0, -1, 0, 0),
			JWResult.OK, "认购国债的四腿分录必须被接受")
	_assert_invpool_identity(1_050_000, "认购 400_000 国债后")
	eq_int(accounts.get_balance(_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH)), 250_000,
			"池现金 600_000 + 50_000 − 400_000")
	eq_int(accounts.get_balance(_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD)), 800_000,
			"池持债 400_000 + 400_000")


## INV-024 的三段等式断言（供上面的用例复用；每次调用产生 3 条断言）。
func _assert_invpool_identity(expected_total: int, when: String) -> void:
	var deposits: int = 0
	for g: int in JWUnits.GROUP:
		deposits += accounts.get_balance(_acc(JWIds.agent_of_group(g), JWIds.ACC_DEPOSIT_CLAIM))
	var liab: int = accounts.get_balance(_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_DEPOSIT_LIAB))
	var assets: int = accounts.get_balance(_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH)) \
			+ accounts.get_balance(_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD))
	eq_int(deposits, expected_total, "INV-024（%s）：Σ group.deposit_uu 应等于契约期望额" % when)
	eq_int(liab, expected_total, "INV-024（%s）：invpool.deposit_liab 应等于同一个数" % when)
	eq_int(assets, expected_total, "INV-024（%s）：invpool.cash + bondhold 应等于同一个数" % when)


## docs/10 §2.4｜投资池不是银行：它不创造货币，只把存款换成持债。
## 存款与认购两步之后，全经济现金总量必须一个子儿都不变（INV-018）。
func test_u_invpool_creates_no_money() -> void:
	eq_int(_open(JWIds.agent_of_group(0), JWIds.ACC_CASH, 1_000_000), JWResult.OK, "组 0 现金")
	eq_int(_open(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH, 200_000), JWResult.OK, "池现金")
	# 池的期初现金全部是居民的存款，故开账时必须有等额的存款负债与之配对（INV-024）；
	# 少了这一腿，投资池开局就凭空多出 200_000 的净值，等于把居民的钱算成了池的自有资金。
	eq_int(_open(JWIds.AGENT_INVPOOL, JWIds.ACC_DEPOSIT_LIAB, 200_000), JWResult.OK, "池存款负债")
	eq_int(_open(JWIds.agent_of_group(1), JWIds.ACC_DEPOSIT_CLAIM, 200_000), JWResult.OK, "组 1 存款债权")
	var total: int = _cash_total_recomputed()
	eq_int(total, 1_200_000, "开账后现金总量 == 1_000_000 + 200_000")
	eq_int(accounts.net_worth_of(JWIds.AGENT_INVPOOL), 0,
			"docs/10 §2.4：投资池的资产全部是居民存款的对价，开局净值为 0")

	var legs_a: PackedInt64Array = PackedInt64Array([
		_acc(JWIds.agent_of_group(0), JWIds.ACC_CASH),
		_acc(JWIds.agent_of_group(0), JWIds.ACC_DEPOSIT_CLAIM),
		_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH),
		_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_DEPOSIT_LIAB),
	])
	var legs_d: PackedInt64Array = PackedInt64Array([-400_000, 400_000, 400_000, -400_000])
	eq_int(ledger.post_multi(JWUnits.Kind.TRANSFER, legs_a, legs_d, 0, -1, 0, 0),
			JWResult.OK, "存款分录必须被接受")

	eq_int(_cash_total_recomputed(), 1_200_000,
			"INV-018：存款只是现金易手，总量不变（投资池不创造货币）")
	eq_int(accounts.get_balance(_acc(JWIds.agent_of_group(0), JWIds.ACC_DEPOSIT_CLAIM)), 400_000,
			"居民存款债权 == 400_000")
	eq_int(accounts.get_balance(_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_DEPOSIT_LIAB)), 600_000,
			"池存款负债 == 200_000（期初）+ 400_000（新增）")
	eq_int(_balance_residual(JWIds.AGENT_INVPOOL), 0,
			"INV-020：投资池自身的资产负债恒等式必须成立（现金 +400_000 对存款负债 +400_000）")
	eq_int(accounts.net_worth_of(JWIds.AGENT_INVPOOL), 0,
			"存款转入不改变投资池净值：它只是中介，不吃差价")


## INV-025｜Σ(invpool.bondhold + row.bondhold) == gov.debt。
## 两个持有人各买一笔，债务余额必须与两人持债之和逐笔对上；这是 ADV-B02 在单元层的前哨。
func test_u_bondhold_matches_gov_debt() -> void:
	eq_int(_open(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH, 900_000), JWResult.OK, "池现金")
	eq_int(_open(JWIds.AGENT_ROW, JWIds.ACC_CASH, 500_000), JWResult.OK, "外部世界现金")
	eq_int(_assert_debt_identity(), 0, "开账后（尚无债务）两侧都应为 0")

	var a1: PackedInt64Array = PackedInt64Array([
		_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_CASH),
		_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD),
		_acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
		_acc(JWIds.AGENT_GOV, JWIds.ACC_DEBT),
	])
	var d1: PackedInt64Array = PackedInt64Array([-600_000, 600_000, 600_000, -600_000])
	eq_int(ledger.post_multi(JWUnits.Kind.BOND_ISSUE, a1, d1, 0, -1, 0, 0), JWResult.OK,
			"向 invpool 发债应成功")
	eq_int(_assert_debt_identity(), 600_000, "INV-025：一笔内债后两侧都是 600_000")

	var a2: PackedInt64Array = PackedInt64Array([
		_acc(JWIds.AGENT_ROW, JWIds.ACC_CASH),
		_acc(JWIds.AGENT_ROW, JWIds.ACC_BONDHOLD),
		_acc(JWIds.AGENT_GOV, JWIds.ACC_CASH),
		_acc(JWIds.AGENT_GOV, JWIds.ACC_DEBT),
	])
	var d2: PackedInt64Array = PackedInt64Array([-250_000, 250_000, 250_000, -250_000])
	eq_int(ledger.post_multi(JWUnits.Kind.BOND_ISSUE, a2, d2, 0, -1, 0, 0), JWResult.OK,
			"向 row 发债应成功")
	eq_int(_assert_debt_identity(), 850_000, "INV-025：加上外债后两侧都是 850_000")
	eq_int(accounts.cash_of(JWIds.AGENT_GOV), 850_000, "政府拿到的现金 == 两笔发债之和")


## INV-025 的两侧对账；返回持债合计供调用方再断言一次数值来源。
func _assert_debt_identity() -> int:
	var held: int = accounts.get_balance(_acc(JWIds.AGENT_INVPOOL, JWIds.ACC_BONDHOLD)) \
			+ accounts.get_balance(_acc(JWIds.AGENT_ROW, JWIds.ACC_BONDHOLD))
	var debt: int = accounts.get_balance(_acc(JWIds.AGENT_GOV, JWIds.ACC_DEBT))
	eq_int(held - debt, 0,
			"INV-025：Σ(invpool.bondhold + row.bondhold) − gov.debt 必须恰为 0，实际持债 %d" % held)
	return held


## INV-024 尾数条款 + INV-003｜利息按 deposit 份额用最大余数法分回，Σ 分配 == Σ 收到。
## 期望值是手算的：1_000_001 按 [5:3:2] 拆 ⇒ 底数 [500_000, 300_000, 200_000]（合计 1_000_000），
## 余 1 归小数部分最大者（0.5 > 0.3 > 0.2），即第 0 组 ⇒ [500_001, 300_000, 200_000]。
func test_u_invpool_interest_distribution_is_exact() -> void:
	var deposits: PackedInt64Array = PackedInt64Array([500_000, 300_000, 200_000])
	var tiebreak: PackedInt64Array = PackedInt64Array([0, 1, 2])
	var received: int = 1_000_001

	var parts: PackedInt64Array = JWMath.split_lr(received, deposits, tiebreak)
	eq_int(parts.size(), 3, "分配结果应与组数等长")
	eq_int_array(parts, PackedInt64Array([500_001, 300_000, 200_000]),
			"docs/10 §2.4：利息按 deposit_uu 份额最大余数法分回，余 1 归小数部分最大的第 0 组")
	var distributed: int = parts[0] + parts[1] + parts[2]
	eq_int(distributed - received, 0,
			"INV-024：Σ interest_distributed == Σ interest_received，精确成立（S06）")
	ge_int(parts[2], 0, "任一组的分配额不得为负")
