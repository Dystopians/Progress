class_name JWTreasury
extends RefCounted

## 国库现金流的**编排者**（docs/10 §3.1/§3.2）：支付优先级、欠付、延期、
## 到期债务、新发债、税收入账、预算预留。持有 log.arrears。
## **它自己不改余额**——一切资金移动仍走 JWLedger.post()。
##
## 三个写入者（S02/S04/S06）为什么不互相放大：arrears 与 arrears_by_payee 在三步中
## 只做**单调累加或清偿**，且每次变动都写 flow.gov.arrears_added/cleared 与 log.arrears；
## INV-030（arrears_end == arrears_start + 新增 − 清偿）在季末一次性验证，任何重复登记都会被它抓住。
##
## 裁定 R-SEASON-01 在本文件的落点：季节系数只作用于「年度支出 − 利息 − 还本」。
## 本文件里的利息与到期本金**只来自 JWBondBook 的逐批次计提**（pay_debt_service），
## 任何季节系数都进不来；季节性拆分发生在年度计划展开成各档 due 的上游（TurnRunner 与
## JWPolicyEngine / JWProjectQueue），treasury 收到的 due 已经是本季数额。

## §1.6 状态块协议：本块各数组所属子系统（与 STATE_ARRAY_IDS 等长）。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_GOV,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.gov.arrears_by_payee_uu",
	"state.gov.payment_priority",
	"state.gov.deferral_flag",
]
const STATE_SCALAR_IDS: PackedStringArray = [
	"state.gov.arrears_uu",
	"state.gov.tax_receivable_uu",
	"state.gov.committed_memo_uu",
	"state.gov.reserved_memo_uu",
	"state.gov.credit_limit_domestic_memo_uu",
	"state.gov.service_opex_committed_uu",
	"state.gov.tax_capacity_ppm",
	"state.gov.rounding_residual_uu",
	# R-DSR-01：§2.6 dsr 的分母（上季实收 × 4）是跨季量，必须进存档与状态哈希；
	# 开局由剧本年度计划的收入合计给出（第 0 季还没有「上季实收」）。
	"state.gov.receipts_annualized_uu",
	# R-P11-02：征收能力的建成水平（P11 落点抬到的最高值；断供后回升的上限）。
	"state.gov.tax_capacity_built_ppm",
]
const FLOW_ARRAY_IDS: PackedStringArray = [
	"flow.gov.pay_transfers_uu",
	"flow.gov.pay_subsidies_uu",
	"flow.gov.pay_project_uu",
	"flow.gov.pay_opex_uu",
	"flow.gov.arrears_added_uu",
	"flow.gov.arrears_cleared_uu",
	"flow.gov.nonmarket_output_uu",
	# 第三轮裁定（重组核销欠付）新增：追加在末尾，既有下标不变。
	"flow.gov.arrears_written_off_uu",
]
const FLOW_SCALAR_IDS: PackedStringArray = [
	"flow.gov.receipts_income_tax_uu",
	"flow.gov.receipts_profit_tax_uu",
	"flow.gov.receipts_other_uu",
	"flow.gov.new_borrowing_uu",
	"flow.gov.primary_paid_uu",
	"flow.gov.interest_paid_uu",
	"flow.gov.principal_paid_uu",
	"flow.gov.recognized_writeoffs_uu",
	"flow.gov.pay_public_wages_uu",
	"flow.gov.pay_procurement_uu",
	"flow.gov.final_consumption_uu",
	"flow.gov.gross_capital_formation_uu",
	# R-PROCURE-01：本季核定的政府采购预算（S04 按优先级融资并核定，S05 市场的买方类 2 按它采购）。
	"flow.gov.procurement_budget_q_uu",
	# R-ROLLOVER-01：本季续发额（已同时计入 new_borrowing 与 principal_paid，本项只作展示与核对）。
	"flow.gov.rollover_uu",
	# R-MONEY-01：本季货币发行（战役模式；政府现金增加的一个来源，进 INV-027）。
	"flow.gov.money_issued_uu",
]

# ── 本文件的局部常量（避免裸字面量，check_param_coverage 的白名单只有 0/1/−1/1e6 与维度常量） ──

## 政策槽位：政策下标 == content 里 policy.P01..P12 的登记顺序（docs/11 §5.12 要求 ID 连续）。
const POLICY_INCOME_TAX: int = 0
const POLICY_PROFIT_TAX: int = 1
## policy.P01 的 4 个 player_param 槽位（content/policies/policy_P01.json 的 state_slot 顺序）
# 槽位与 content/policies/policy_P01.json 的 player_params 顺序（及各项 state_slot）逐一对应，
# j=0 是主速率槽（JWPolicyDef.PARAM_SLOT_PRIMARY）。曾被写成 0/1/2/3 = 免征额/起征点/税率1/税率2，
# 结果第一档税率读到 120%——测试 test_p01_slots_match_content 钉死这张对照表。
const P01_SLOT_RATE2_PPM: int = 0
const P01_SLOT_EXEMPTION_PPM: int = 1
const P01_SLOT_BRACKET2_PPM: int = 2
const P01_SLOT_RATE1_PPM: int = 3
## policy.P02 的槽位 0 == rate_ppm
const P02_SLOT_RATE_PPM: int = 0

## log.ledger.product 的「无关联产品」值（docs/10 §2.5 第 7 列）
const PRODUCT_NONE: int = -1
## log.ledger.cause 的「规则驱动、无具体来源操作」值。
## docs/10 §2.5 只规定该列是「来源操作码（政策／项目／事件／冲击／规则）」而没有给出码表，
## 因此与 product 列取同一个「无」值 −1；有码表之后逐处替换（见 open_questions）。
const CAUSE_RULE: int = -1

## §2.6 的 dsr 封顶（docs/12 §2.6：min(dsr_ppm, 2_000_000)）
const DSR_CAP_PPM: int = 2_000_000
## 一年的季数（年化收入与 debt_service_next4q 的口径）
const QUARTERS_PER_YEAR: int = 4
## 发行／还本的过账腿数：gov 现金、gov 债务、holder 现金、holder 持债
const BOND_LEG_N: int = 4

## 日志扩容倍数 3/2（docs/17 §1.7「写满时按 1.5 倍扩容并写一条告警行」）
const LOG_GROW_NUM: int = 3
const LOG_GROW_DEN: int = 2
## 扩容告警行的 payee 与 reason 占位（不是真实收款方，也不是真实档位）
const LOG_MARK_NONE: int = -1

## 「连续 param.default_grace_q 季无法支付第 1 档」的信号码（INV-040）。
## 取值即 JWUnits.Termination.FISCAL_RESTRUCTURING_FAILED，S08 可直接写进
## meta.termination_reason；它与 JWResult.OK(0) 以及全部 Fault 码（0/1/10+）、
## Reject 码（1000+）都不冲突，调用方一眼能分辨。
const SIGNAL_FISCAL_RESTRUCTURING_FAILED: int = JWUnits.Termination.FISCAL_RESTRUCTURING_FAILED

## state.gov.arrears_uu —— μU，写入者 S02, S04, S06
var arrears: int = 0

## state.gov.arrears_by_payee_uu[] —— 60 元素，μU，写入者 S02, S04, S06
var arrears_by_payee: PackedInt64Array = PackedInt64Array()

## state.gov.tax_receivable_uu —— μU，写入者 S06
var tax_receivable: int = 0

## state.gov.committed_memo_uu —— memo，μU，写入者 S02, S04, S07
var committed_memo: int = 0

## state.gov.reserved_memo_uu —— memo，μU，写入者 S02, S04
var reserved_memo: int = 0

## state.gov.credit_limit_domestic_memo_uu —— memo，μU，写入者 S02
var credit_limit_domestic: int = 0

## state.gov.service_opex_committed_uu —— μU/季，写入者 S07
var service_opex_committed: int = 0

## state.gov.tax_capacity_ppm —— ppm，写入者 S07（P11）
var tax_capacity_ppm: int = 0
## state.gov.tax_capacity_built_ppm —— ppm，写入者 S07（P11 落点），LOAD 初值 == 基年征收能力（R-P11-02）
var tax_capacity_built_ppm: int = 0

## state.gov.payment_priority[] —— 8 元素，JWUnits.PayLine 的全排列，写入者 CMD→S02
var payment_priority: PackedInt64Array = PackedInt64Array()

## state.gov.deferral_flag[] —— 8 元素，0/1，写入者 S02, S04
var deferral_flag: PackedInt64Array = PackedInt64Array()

## state.gov.rounding_residual_uu —— μU，写入者 S02, S04, S05, S06
var rounding_residual: int = 0

## flow.gov.receipts_income_tax_uu —— μU，写入者 S06
var f_receipts_income_tax: int = 0

## flow.gov.receipts_profit_tax_uu —— μU，写入者 S06
var f_receipts_profit_tax: int = 0

## flow.gov.receipts_other_uu —— μU，写入者 S05, S06
var f_receipts_other: int = 0

## flow.gov.new_borrowing_uu —— μU，写入者 S02
var f_new_borrowing: int = 0

## flow.gov.primary_paid_uu —— μU，写入者 S04, S05
var f_primary_paid: int = 0

## flow.gov.interest_paid_uu —— μU，**仅 S02**
var f_interest_paid: int = 0

## flow.gov.principal_paid_uu —— μU，**仅 S02**
var f_principal_paid: int = 0

## flow.gov.recognized_writeoffs_uu —— μU，写入者 S02
var f_writeoffs: int = 0

## flow.gov.pay_public_wages_uu —— μU，写入者 S04
var f_pay_public_wages: int = 0

## flow.gov.pay_transfers_uu[] —— 36 元素，μU，写入者 S04
var f_pay_transfers: PackedInt64Array = PackedInt64Array()

## flow.gov.pay_subsidies_uu[] —— 16 元素，μU，写入者 S04
var f_pay_subsidies: PackedInt64Array = PackedInt64Array()

## flow.gov.pay_project_uu[] —— JWUnits.PROJECT_CAP0 元素，μU，写入者 S04
var f_pay_project: PackedInt64Array = PackedInt64Array()

## flow.gov.pay_opex_uu[] —— 12 元素，μU，写入者 S04
var f_pay_opex: PackedInt64Array = PackedInt64Array()

## flow.gov.pay_procurement_uu —— μU，写入者 S05
var f_pay_procurement: int = 0

## flow.gov.arrears_added_uu[] —— 60 元素，μU，写入者 S02, S04, S06
var f_arrears_added: PackedInt64Array = PackedInt64Array()

## flow.gov.arrears_cleared_uu[] —— 60 元素，μU，写入者 S02, S04
var f_arrears_cleared: PackedInt64Array = PackedInt64Array()

## flow.gov.arrears_written_off_uu[] —— 60 元素，μU，写入者 S02（第三轮裁定：债务重组核销欠付）。
## 非现金了结的欠付备查额：减记 / 违约了结的已计未付，以及延期时顺延回分期表的逾期本金。
## INV-030 扩展为 arrears_end == start + 新增 − 清偿 − 核销。
var f_arrears_written_off: PackedInt64Array = PackedInt64Array()

## flow.gov.nonmarket_output_uu[] —— 4 元素，μU，写入者 S06
var f_nonmarket_output: PackedInt64Array = PackedInt64Array()

## flow.gov.final_consumption_uu —— μU，写入者 S06
var f_final_consumption: int = 0

## flow.gov.gross_capital_formation_uu —— μU，写入者 S06
var f_gross_capital_formation: int = 0

## log.arrears.* —— 容量 JWUnits.LOG_CAP0，写入者 S02, S04, S06，不进 state_hash
var a_payee: PackedInt64Array = PackedInt64Array()
var a_amount: PackedInt64Array = PackedInt64Array()
var a_reason: PackedInt64Array = PackedInt64Array()
var a_step: PackedInt64Array = PackedInt64Array()

## 最近一次 issue_debt / issue_debt_up_to / issue_bond_to 实际发出的面值合计（μU，国内 + 外部）。
## 只读输出口：每次上述调用入口清零，不跨调用累积；不进状态块、不进 state_hash
## （它是返回值的延长线，同 JWBondBook.last_writeoff_uu）。issue_debt_up_to 部分融资时，
## 调用方用它（或 gov.cash 的变化）确定还差多少，差额照常交给 pay_line / pay_debt_service 记欠付。
var last_issued_uu: int = 0

## μU，INV-027 的基准，写入者 S01
var _cash_at_quarter_start: int = 0

## 季，连续无法付第 1 档的季数，写入者 S02
var _default_streak_q: int = 0

# ── 以下私有成员是 docs/17 §4.12 成员表之外的实现细节（不进 state_hash、不进存档） ──
#
# 它们存在的理由都是「契约要求的终检需要一个季初基准，而成员表只给了现金那一个」：
# INV-028 要 debt_start、INV-030 要 arrears_start。没有基准就只能写出一个恒成立的
# 恒等式——那等于没检查。见 open_questions。

## μU，INV-030 的季初基准，写入者 begin_quarter（S01）
var _arrears_at_quarter_start: int = 0
## μU，INV-028 的季初基准，写入者 pay_debt_service / issue_debt*（本季首次调用时从
## JWBondBook.debt_at_quarter_start 取，那是本季第一次改账之前的未偿本金）
var _debt_at_quarter_start: int = 0
## 已武装 debt 基准的季；−1 表示本局尚未武装（载入后直接终检时用它跳过 INV-028）
var _debt_baseline_q: int = -1
## 1 表示 begin_quarter 已在本局跑过（载入后直接终检时用它跳过 INV-027/030）
var _cash_baseline_armed: int = 0
## 1 表示本季的预算预留窗口仍开着：begin_quarter（S01）打开，release_reservations（S04 末）关上。
## 裁定 R-RESERVE-01：reserved_memo == 0 是**季末**不变量——窗口开着时（S02 步末）预留合法非零，
## 只核 reserved_memo <= cash；窗口关上之后才核归零。若某季漏了释放，窗口到下一季 S01 仍开着，
## begin_quarter 在那里把残留的预留报成故障——「季末归零」不会因为跳过而变成恒真式。
var _reserve_open: int = 0

## state.gov.receipts_annualized_uu —— μU，上一季已结算的年化经常性收入（§2.6 的 dsr 分母）。
## 开局取剧本年度计划收入（R-DSR-01），此后每季 S06 末按「本季实收 × 4」重写。
## 本季 S02 时本季税收尚未发生（税在 S06），只能用上一季的实收 × 4。
var _receipts_annualized: int = 0

## log.arrears 的本季写游标
var _log_n: int = 0
## 写日志行时填入的步骤号（JWResult._current_step 没有公开读取口，故各公开入口自报）
var _log_step: int = 0

## pay_line 的拆分结果缓冲（长度随档位的清单长度变化，容量复用，不新建对象）
var _pay_split: PackedInt64Array = PackedInt64Array()
## pay_line 的「按收款方 ID 升序」下标缓冲
var _pay_order: PackedInt64Array = PackedInt64Array()
## post_multi 的四腿缓冲（发债与还本各有 4 条有符号行）
var _legs_account: PackedInt64Array = PackedInt64Array()
var _legs_delta: PackedInt64Array = PackedInt64Array()

## _quote_financing 的输出（一次发行调用内有效，调用之间不携带任何含义）：
## 两段票息（docs/12 §2.6，写入批次后永不可改）与两段**本次可发**的剩余能力（INV-034）。
var _q_coupon_dom: int = 0
var _q_coupon_ext: int = 0
var _q_cap_dom: int = 0
var _q_cap_ext: int = 0

## 本季已定的两段票息（裁定 R-BONDCAP-01「同季票息相同」）：本季**第一笔实际发行**时按规则定价并封存，
## 本季此后的报价一律沿用，于是同季、同债权人、同到期季的发行可以并入同一批次而不重定价任何一笔。
## 只在真正动账时封存（_seal_quarter_price）：被拒的发行不定价，不让一条被拒命令左右本季利率。
## 私有：不进状态块、不进 state_hash；begin_quarter 与 allocate 撤销。存档只落在季末，读档后首笔发行重新定价。
var _px_armed: bool = false
var _px_q: int = 0
var _px_coupon_dom: int = 0
var _px_coupon_ext: int = 0

## 本季逐 cell 的**实缴**利润税（μU），长 CELL。私有 scratch：不进注册表、不进 state_hash、
## 不进存档——它只是 collect_profit_tax 内部那个局部 `paid` 的留痕。
## 为什么必须留：`flow.cell.tax_profit_paid_uu[]` 归 JWSectorModel（秩 7），treasury（秩 5）
## 不得反向引用它（§3.2 同秩／越秩禁引），只能由 JWTurnRunner 逐项转交；
## 而「按应税额事后摊回」既不精确（现金上限是逐 cell 的）又会在 split_lr_into 的
## `total × Σweights` 入口守卫处溢出（实测 3.175e8 × 4.3e10 = 1.37e19 > int64）。
var _profit_tax_paid_by_cell: PackedInt64Array = PackedInt64Array()


## 记录季初现金基准，供 S06 §6.9 的 INV-027 终检。
## 步骤：S01
## 前置：phase == S01
## 后置：_cash_at_quarter_start == accounts.cash_of(AGENT_GOV)
## 不变量：INV-027
## 失败：无
func begin_quarter(accounts: JWAccount) -> void:
	if accounts == null:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, JWIds.AGENT_GOV, 0)
		return
	_log_step = JWUnits.Phase.S01
	# R-RESERVE-01：上一季的预留窗口必须已在 S04 末关上并归零。带着残留进入新的一季，说明有一条
	# 预留路径既没执行也没释放——季末终检在窗口未关时不核归零，这一种情形由这里兜住。
	if reserved_memo != 0:
		JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, reserved_memo, 0)
	_reserve_open = 1
	# 本季尚未定价：本季第一笔实际发行时再封存（R-BONDCAP-01「同季票息相同」）。
	_px_armed = false
	# docs/12 §01.2：INV-027 的左端基准。S01 不过账，所以此刻的 gov.cash 就是「季初现金」。
	_cash_at_quarter_start = accounts.cash_of(JWIds.AGENT_GOV)
	# INV-030 的季初基准。arrears 是 S 类状态，不受 S01 的流量清零影响，
	# 此刻取值即「上季末欠付」。
	_arrears_at_quarter_start = arrears
	_cash_baseline_armed = 1
	# 债务基准在本季国库第一次触及债券簿时武装：本函数拿不到 JWBondBook（签名冻结）。
	# 期初值本身由 JWBondBook 在本季第一次改账之前取定（debt_at_quarter_start），
	# 所以即便 S02 的命令先于国库改过批次表，INV-028 的左端仍是真正的季初未偿本金。
	_debt_baseline_q = -1
	# deferral_flag 是「本季」标记，但 S01 不在它的写入者列（docs/10 §3.1 写入者 = S02,S04），
	# 因此清零放在 S02 的第一个入口 pay_debt_service 里，不在这里写。


## 预算预留（不是支付）：只减少可用额度，不产生任何现金移动。
## 步骤：S02 §2.2
## 前置：need_uu >= 0
## 后置：reserved_memo += need_uu 且 reserved_memo <= cash
## 不变量：INV-033（reserved_memo <= cash 且季末归零）
## 失败：可用额度不足 → 返回 Reject.BUDGET_INSUFFICIENT（**不写任何资金行**，
##       混记会让 INV-027 失衡）
func reserve(need_uu: int, accounts: JWAccount) -> int:
	if accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, JWIds.AGENT_GOV, 0)
	if need_uu < 0:
		# 负预留 == 凭空多出可用额度。它不是「释放」（释放走 release_reservations），
		# 放过去就等于给了一条绕开 INV-033 的路径。
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, need_uu, 0)
	if need_uu == 0:
		return JWResult.OK
	_log_step = JWUnits.Phase.S02
	# docs/12 §2.2：avail = gov.cash − gov.reserved_memo。
	var avail: int = accounts.cash_of(JWIds.AGENT_GOV) - reserved_memo
	if need_uu > avail:
		# 业务性拒绝：**不改任何状态、不写任何资金行**（docs/12 §0.6 的 REJECT 语义）。
		return JWResult.Reject.BUDGET_INSUFFICIENT
	reserved_memo = JWMath.check_amount(reserved_memo + need_uu)
	return JWResult.OK


## 释放本季未执行的预留（季末必须归零）。
## 步骤：S04 末
## 前置：无
## 后置：reserved_memo == 0；本季预留窗口关上（此后的终检核「季末归零」，R-RESERVE-01）
## 不变量：INV-033
## 失败：残留非零且无法解释 → Fault.LEDGER_IMBALANCE
func release_reservations() -> int:
	_log_step = JWUnits.Phase.S04
	if reserved_memo < 0:
		# 负的预留余额不是「可以归零了事」的残留：它意味着某处把预留当成了资金账来扣，
		# 归零会把这个缺陷抹掉。INV-033 的「季末归零」只适用于非负残留。
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, reserved_memo, 0)
	# 预留要么执行（S04 实际付款）要么释放，两者都不产生现金移动，因此这里只清 memo。
	reserved_memo = 0
	_reserve_open = 0
	return JWResult.OK


## S02 §2.5：按优先级支付到期利息与本金；短缺先显露。
## 步骤：S02 §2.5
## 前置：bonds.accrue_interest / schedule_principal 已跑完
## 后置：flow.gov.interest_paid / principal_paid 写入；未付部分登记 arrears 且批次转 DEFAULTED；
##       gov.cash 恒不为负
## 不变量：INV-016, INV-027, INV-028, INV-030, INV-035, INV-036, INV-037, INV-038, INV-039, INV-040
## 失败：现金将为负 → Fault.NEGATIVE_CASH；连续 params[DEFAULT_GRACE_Q] 季无法付第 1 档 →
##       返回信号让 S08 置 termination_reason = FISCAL_RESTRUCTURING_FAILED；**不得自动展期**
func pay_debt_service(bonds: JWBondBook, ledger: JWLedger, accounts: JWAccount,
		q: int, params: PackedInt64Array) -> int:
	if bonds == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q, 0)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	_log_step = JWUnits.Phase.S02
	# 本季的延期标记从这里开始重新计：pay_debt_service 是 S02 里 treasury 的第一个入口，
	# 而 deferral_flag 的写入者恰是 S02/S04（docs/10 §3.1），S01 不许碰它。
	if deferral_flag.size() != JWUnits.PAY_LINE_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				deferral_flag.size(), JWUnits.PAY_LINE_N)
	deferral_flag.fill(0)
	_arm_debt_baseline(bonds, q)

	var n: int = bonds.count
	if n < 0 or n > bonds.principal_outstanding.size() \
			or bonds.interest_due.size() < n or bonds.principal_due.size() < n \
			or bonds.status.size() < n or bonds.holder.size() < n:
		return JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, n,
				bonds.principal_outstanding.size())

	var gov_cash: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	var avail: int = accounts.cash_of(JWIds.AGENT_GOV)
	var interest_unpaid_total: int = 0
	var principal_unpaid_total: int = 0

	# ── 先利息（docs/12 §2.5「逐批次 post(gov -> holder, interest_due)」），批次下标升序 ──
	# 顺序是契约的一部分：同一笔现金在两个批次之间的分配完全由下标决定，不允许按金额排序，
	# 也不允许按比例摊——摊派会让「哪一笔违约了」变成一个不可追溯的模糊状态。
	var b: int = 0
	while b < n:
		var due_i: int = bonds.interest_due[b]
		if due_i > 0 and _bond_is_live(bonds, b):
			var pay_i: int = due_i
			if pay_i > avail:
				pay_i = avail
			if pay_i > 0:
				var rc: int = ledger.post(JWUnits.Kind.BOND_INTEREST, gov_cash,
						_holder_cash_account(bonds.holder[b]), pay_i, 0,
						PRODUCT_NONE, CAUSE_RULE, b)
				if rc != JWResult.OK:
					# post 内部已整笔回滚。现金已经先行截断过，走到这里说明账户层与
					# treasury 对「可用现金」的认知不一致 —— 那是缺陷，不是短缺。
					return rc
				avail -= pay_i
				f_interest_paid = JWMath.check_amount(f_interest_paid + pay_i)
			var short_i: int = due_i - pay_i
			if short_i > 0:
				# 违约：已计未付利息进批次账，同额进政府欠付，批次转 DEFAULTED。
				# **不展期、不重定价**（INV-036/INV-038）。
				var rcb: int = bonds.register_interest_arrears(b, short_i)
				if rcb != JWResult.OK:
					return rcb
				add_arrears(_holder_agent(bonds.holder[b]), short_i,
						JWUnits.PayLine.DEBT_SERVICE)
				interest_unpaid_total += short_i
		b += 1

	# ── 再本金（docs/12 §2.5），同样按批次下标升序 ──
	b = 0
	while b < n:
		var due_p: int = bonds.principal_due[b]
		if due_p > 0 and _bond_is_live(bonds, b):
			var outstanding: int = bonds.principal_outstanding[b]
			if due_p > outstanding:
				# 到期额超过未偿本金：分期表与未偿本金对不上（INV-037）。
				return JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, due_p, outstanding)
			var pay_p: int = due_p
			if pay_p > avail:
				pay_p = avail
			if pay_p > 0:
				# 还本是四条腿：gov 现金 −、gov 债务 −（负债减记为 +），
				# holder 现金 +、holder 持债 −。用两腿 post() 会把还本记成净值转移，
				# 逐主体资产负债恒等式（INV-020）当场破。
				var rcm: int = _post_bond_legs(ledger, JWUnits.Kind.BOND_PRINCIPAL,
						bonds.holder[b], pay_p, false, b)
				if rcm != JWResult.OK:
					return rcm
				var rcp: int = bonds.apply_principal_payment(b, pay_p)
				if rcp != JWResult.OK:
					return rcp
				avail -= pay_p
				f_principal_paid = JWMath.check_amount(f_principal_paid + pay_p)
			var short_p: int = due_p - pay_p
			if short_p > 0:
				# 本金未付：docs/12 §2.5 的「同上」——未付额同样进 accrued_unpaid、同样进
				# gov.arrears、批次同样转 DEFAULTED，并进入**由玩家在下一季用
				# debt_restructure 命令选择**的重组分支。**这里绝不自动展期**（INV-038）。
				var rcb2: int = bonds.register_interest_arrears(b, short_p)
				if rcb2 != JWResult.OK:
					return rcb2
				add_arrears(_holder_agent(bonds.holder[b]), short_p,
						JWUnits.PayLine.DEBT_SERVICE)
				principal_unpaid_total += short_p
		b += 1

	# ── 第 1 档的连续失败计数（INV-040） ──
	if interest_unpaid_total > 0 or principal_unpaid_total > 0:
		deferral_flag[JWUnits.PayLine.DEBT_SERVICE] = 1
		_default_streak_q += 1
	else:
		_default_streak_q = 0
	var grace: int = params[JWUnits.Param.DEFAULT_GRACE_Q]
	if grace > 0 and _default_streak_q >= grace:
		# 只返回信号，不在这里写 meta.termination_reason：那是 S08 的可写子集。
		return SIGNAL_FISCAL_RESTRUCTURING_FAILED
	return JWResult.OK


## S02 §2.6：按规则定价并发行新债（国内额度 + 外部额度两段），**全额发行或整笔拒绝**。
## 步骤：S02 §2.6
## 前置：need_uu > 0；市场利率由 dsr 与冲击共同决定；玩家不能设利率
## 后置：新批次入 SoA；post(kind=BOND_ISSUE) 完成；flow.gov.new_borrowing_uu 登记；
##       world.credit_used_uu 增加；last_issued_uu == 实发面值（被拒时为 0）
## 不变量：INV-034（两段能力见 _quote_financing：国内 ≤ min(本季剩余国内额度, 投资池本季认购余力)，
##          外部 ≤ min(credit_limit − credit_used, row.cash)）、INV-029（借款不进收入、不进 GDP）、INV-038
## 失败：能力不足或批次表已满 → **整笔**返回 Reject.CREDIT_LIMIT（一分钱都不发），需求回到 §2.5 的
##       排序／延期／重组分支。规则驱动的周转融资（R-FINANCE-01）要「能融多少融多少」，走 issue_debt_up_to。
##
## **全额发行或整笔拒绝**（docs/30 `T-S-D-11`）：被拒的发行 `gov.debt_uu` 增量必须 == 0、
## `state_hash` 逐位不变。docs/12 §2.6 的伪码把「差额」交回 02.5，但它没有授权「先发一半」——
## 而 T-S-D-11 的场景（能力 600 000 < 需求 2 000 000）恰恰要求此时增量为 0，两处合起来只有一个读法：
## 能力不够就**在动任何账之前**退出。因此本函数的全部拒绝判据（两段额度、批次上限、批次参数）
## 都排在第一笔写操作之前；此后只剩故障路径，而故障按 docs/12 §9 不回滚。
func issue_debt(need_uu: int, bonds: JWBondBook, world: JWWorldMarket, ledger: JWLedger,
		accounts: JWAccount, q: int, entity_seq: int, params: PackedInt64Array) -> int:
	last_issued_uu = 0
	if bonds == null or world == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q, 0)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	if need_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, need_uu, 0)
	if need_uu == 0:
		return JWResult.OK

	var rc_q: int = _quote_financing(bonds, world, accounts, q, params)
	if rc_q != JWResult.OK:
		return rc_q
	var issue_domestic: int = need_uu
	if _q_cap_dom < issue_domestic:
		issue_domestic = _q_cap_dom
	var issue_external: int = need_uu - issue_domestic
	if _q_cap_ext < issue_external:
		issue_external = _q_cap_ext

	# ── 拒绝闸门①：两段能力之和不够全额（INV-034 / docs/30 T-S-D-11） ──
	if issue_domestic + issue_external < need_uu:
		# 融资没有对手方能力就**整笔**拒绝：不缩减需求、不发半张、不自动展期。
		# 此处尚未写过任何一个字段，因此 gov.debt_uu 增量为 0、state_hash 逐位不变。
		# 差额由调用方回到 §2.5 的排序／延期／重组分支（记 arrears 或重组），不在这里悄悄补账。
		return JWResult.Reject.CREDIT_LIMIT

	var maturity: int = _new_issue_maturity(q, params)

	# ── 拒绝闸门②：批次上限（docs/12 §2.4：报警并 REJECT；旧批次一概不合并） ──
	# R-BONDCAP-01：与本季已有批次同债权人、同到期季、同票息的一段并入该批次，不占新格，
	# 只有要新开的格才核上限。一次调用最多两个新格（国内一笔、外部一笔），必须**按总数**核：
	# 只核单笔会让「国内发得下、外部发不下」的组合先落一半再被拒，又回到半张债券。
	var batch_cap: int = params[JWUnits.Param.BOND_BATCH_CAP]
	var tgt_dom: int = -1
	var tgt_ext: int = -1
	if issue_domestic > 0:
		tgt_dom = bonds.merge_target(q, maturity, JWUnits.Amortization.LEVEL_PRINCIPAL,
				JWUnits.Holder.INVPOOL, _q_coupon_dom)
	if issue_external > 0:
		tgt_ext = bonds.merge_target(q, maturity, JWUnits.Amortization.LEVEL_PRINCIPAL,
				JWUnits.Holder.ROW, _q_coupon_ext)
	var reserve_ext: int = 1 if (issue_external > 0 and tgt_ext < 0) else 0
	if issue_domestic > 0:
		var rc_pre: int = _segment_precheck(bonds, tgt_dom, batch_cap - reserve_ext, q,
				issue_domestic, _q_coupon_dom, maturity, JWUnits.Holder.INVPOOL)
		if rc_pre != JWResult.OK:
			return rc_pre
	if issue_external > 0:
		var rc_pre2: int = _segment_precheck(bonds, tgt_ext, batch_cap, q, issue_external,
				_q_coupon_ext, maturity, JWUnits.Holder.ROW)
		if rc_pre2 != JWResult.OK:
			return rc_pre2

	# ── 这里之后才动账：上面已排除全部业务性拒绝 ──
	_log_step = JWUnits.Phase.S02
	_arm_debt_baseline(bonds, q)
	return _issue_split(bonds, world, ledger, entity_seq, q, issue_domestic, issue_external, maturity)


## R-FINANCE-01：预算内支出的常设融资授权——在对手方能力之内**能融多少融多少**，超出部分不发。
## 步骤：S02（付本息之前）、S04（每条支付线付款之前）
## 前置：need_uu >= 0 是本次付款的现金缺口；票息与期限的规则同 issue_debt（玩家不能设利率）
## 后置：发出 min(need, 国内剩余能力) 的国内一段与 min(need − 国内, 外部剩余能力) 的外部一段；
##       每段并入本季同债权人、同到期季的已有批次（R-BONDCAP-01），没有才新开一格——
##       规则发行的期限相同，所以每季至多 2 批；余位不够时按 §2.6 的次序先国内后外部；
##       last_issued_uu == 实发面值
## 不变量：INV-034、INV-029、INV-035、INV-038——新批次按当季利率另行发行，到期批次照原条款结清；
##          这是再融资，不是展期（到期表、票息、未偿本金一个都不动）
## 失败：发不满 need → 返回 Reject.CREDIT_LIMIT。它是**业务码，不是命令拒绝**：能发的部分已经发出、
##       账目自洽，差额由调用方照常交给 pay_debt_service / pay_line 记违约或欠付（docs/12 §0.6 的 ARREARS）；
##       批次参数越界 → 与 issue_debt 同码的故障
##
## 与 issue_debt 的分工：玩家命令必须全有全无（T-S-D-11：被拒命令的 state_hash 逐位不变），
## 规则驱动的周转融资则必须允许部分成交——计划书 §07「无法融资时进入支出排序」、R-FINANCE-01
## 「融不到的部分才记欠付」：缺口 3 U 而能力 2 U 时整笔拒绝，会把本可融到的 2 U 也记成欠付。
func issue_debt_up_to(need_uu: int, bonds: JWBondBook, world: JWWorldMarket, ledger: JWLedger,
		accounts: JWAccount, q: int, entity_seq: int, params: PackedInt64Array) -> int:
	last_issued_uu = 0
	if bonds == null or world == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q, 0)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	if need_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, need_uu, 0)
	if need_uu == 0:
		return JWResult.OK

	var rc_q: int = _quote_financing(bonds, world, accounts, q, params)
	if rc_q != JWResult.OK:
		return rc_q
	var maturity: int = _new_issue_maturity(q, params)
	# 批次表余位（docs/12 §2.4：到上限就不再开新格；旧批次一概不合并）。R-BONDCAP-01 的同季
	# 同条件并入不占格；余位不够时按 §2.6 的次序先国内后外部——先定国内段，外部段按剩余需求再定。
	var batch_cap: int = params[JWUnits.Param.BOND_BATCH_CAP]
	if batch_cap > JWUnits.BOND_CAP0:
		batch_cap = JWUnits.BOND_CAP0
	var slots: int = batch_cap - bonds.count
	var issue_domestic: int = need_uu
	if _q_cap_dom < issue_domestic:
		issue_domestic = _q_cap_dom
	var tgt_dom: int = -1
	if issue_domestic > 0:
		tgt_dom = bonds.merge_target(q, maturity, JWUnits.Amortization.LEVEL_PRINCIPAL,
				JWUnits.Holder.INVPOOL, _q_coupon_dom)
		if tgt_dom < 0:
			if slots >= 1:
				slots -= 1
			else:
				issue_domestic = 0
	var issue_external: int = need_uu - issue_domestic
	if _q_cap_ext < issue_external:
		issue_external = _q_cap_ext
	var tgt_ext: int = -1
	if issue_external > 0:
		tgt_ext = bonds.merge_target(q, maturity, JWUnits.Amortization.LEVEL_PRINCIPAL,
				JWUnits.Holder.ROW, _q_coupon_ext)
		if tgt_ext < 0:
			if slots >= 1:
				slots -= 1
			else:
				issue_external = 0

	if issue_domestic + issue_external > 0:
		# 余位已按上面裁过，这里的预检只剩批次参数的故障判据（与 issue_debt 同一份）。
		var reserve_ext: int = 1 if (issue_external > 0 and tgt_ext < 0) else 0
		if issue_domestic > 0:
			var rc_pre: int = _segment_precheck(bonds, tgt_dom, batch_cap - reserve_ext, q,
					issue_domestic, _q_coupon_dom, maturity, JWUnits.Holder.INVPOOL)
			if rc_pre != JWResult.OK:
				return rc_pre
		if issue_external > 0:
			var rc_pre2: int = _segment_precheck(bonds, tgt_ext, batch_cap, q, issue_external,
					_q_coupon_ext, maturity, JWUnits.Holder.ROW)
			if rc_pre2 != JWResult.OK:
				return rc_pre2
		_arm_debt_baseline(bonds, q)
		var rc: int = _issue_split(bonds, world, ledger, entity_seq, q,
				issue_domestic, issue_external, maturity)
		if rc != JWResult.OK:
			return rc

	if last_issued_uu < need_uu:
		# 差额未融资：业务性短缺的显式信号，不是故障，也不回滚已经发出的部分。
		return JWResult.Reject.CREDIT_LIMIT
	return JWResult.OK


## R-ROLLOVER-01：到期本金对原持有人的续发（再融资，不是展期）。
## 步骤：S02 §2.5 之前（R-FINANCE-01 预融资之后、pay_debt_service 之前，由 JWTurnRunner 调用）
## 前置：schedule_principal 已写本季 principal_due；need_uu = 本季本息缺口中无法以现金与预融资覆盖的部分
## 后置：对本季到期、持有人为投资池或外部的批次（下标升序），按缺口把到期本金改由**同一持有人**的新批次承接：
##       旧批次按原条款结清该部分（apply_principal_payment，principal_due 同额减少），
##       新批次按本季封存票息、标准期限发行（R-BONDCAP-01 同条件并入）；
##       flow.gov.new_borrowing 与 flow.gov.principal_paid 同额增加（Δdebt == 0，INV-028 成立）
## 不变量：INV-028、INV-035（债务 == Σ 未偿本金，两边同额一增一减）、INV-107（外部持债科目不变）、
##         INV-036/038（旧债不重定价、不改期——旧批次照常结清；新批次按当季规则定价）
## 失败：票息已触 coupon_max（市场不再按价出清）→ 不续发，返回 OK，缺口照常在 pay_debt_service 显露为违约；
##       批次表已满 → 停止续发；bond_book 故障原样上抛
##
## 为什么没有现金腿：发行与还本对同一持有人同额同时发生，四个科目（政府现金、政府债务、持有人现金、
## 持有人持债）逐项相抵为 0。按两笔带现金腿的分录先后过账反而过不去——投资池在收到还本之前买不起新债，
## 政府在发债之前付不出还本（两边现金都不得为负）。续发不占 R-CREDIT-01 的增量额度：它不是新增借款。
func rollover_principal(need_uu: int, bonds: JWBondBook, world: JWWorldMarket,
		accounts: JWAccount, q: int, entity_seq: int, params: PackedInt64Array) -> int:
	last_issued_uu = 0
	if need_uu <= 0:
		return JWResult.OK
	if bonds == null or world == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q, 0)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	var rc_q: int = _quote_financing(bonds, world, accounts, q, params)
	if rc_q != JWResult.OK:
		return rc_q
	var coupon_max: int = params[JWUnits.Param.COUPON_MAX_PPM]
	var maturity: int = _new_issue_maturity(q, params)
	var batch_cap: int = mini(params[JWUnits.Param.BOND_BATCH_CAP], JWUnits.BOND_CAP0)
	_arm_debt_baseline(bonds, q)
	var n: int = bonds.count
	var n_before: int = bonds.count
	var left: int = need_uu
	var b: int = 0
	while b < n and left > 0:
		var due_p: int = bonds.principal_due[b]
		var h: int = bonds.holder[b]
		if due_p > 0 and _bond_is_live(bonds, b) \
				and (h == JWUnits.Holder.INVPOOL or h == JWUnits.Holder.ROW):
			var coupon: int = _q_coupon_dom if h == JWUnits.Holder.INVPOOL else _q_coupon_ext
			if coupon < coupon_max:
				var x: int = mini(due_p, left)
				var tgt: int = bonds.merge_target(q, maturity, JWUnits.Amortization.LEVEL_PRINCIPAL,
						h, coupon)
				var ok: bool = false
				if tgt >= 0:
					if bonds.can_merge(tgt, q, x) == JWResult.OK:
						var rcm: int = bonds.merge_issue(tgt, q, x)
						if rcm != JWResult.OK:
							return rcm
						ok = true
				elif bonds.count < batch_cap:
					var seq: int = entity_seq + (bonds.count - n_before)
					var nb: int = bonds.issue(seq, q, x, coupon, maturity,
							JWUnits.Amortization.LEVEL_PRINCIPAL, h)
					ok = nb >= 0
				if ok:
					# 本季第一笔实际发行封存票息（R-BONDCAP-01「同季票息相同」）。
					_seal_quarter_price(q)
					var rcp: int = bonds.apply_principal_payment(b, x)
					if rcp != JWResult.OK:
						return rcp
					bonds.principal_due[b] = due_p - x
					f_new_borrowing = JWMath.check_amount(f_new_borrowing + x)
					f_principal_paid = JWMath.check_amount(f_principal_paid + x)
					f_rollover = JWMath.check_amount(f_rollover + x)
					last_issued_uu = JWMath.check_amount(last_issued_uu + x)
					left -= x
		b += 1
	return JWResult.OK


## 玩家命令 issue_bond{amount_uu, tenor_q, holder}（docs/11 §6.1 kind 8）：向**玩家指定的债权人**、
## 按**玩家指定的期限**发行一个批次，全有全无；票息仍由规则给出（玩家不能设利率）。
## 步骤：S02 §2.1 / §2.6
## 前置：命令层已按 tenor_q 的合法区间与 holder 闭枚举校验过形状（本函数只再挡结构性越界）
## 后置：受理 ⇒ 本季该债权人、该到期季（q + tenor_q）的批次增加 amount_uu：已有则并入（R-BONDCAP-01，
##       票息同季相同），没有则新开一格（level_principal，与 issue_debt 同一摊还口径）；
##       post(kind=BOND_ISSUE)、flow.gov.new_borrowing_uu 登记，holder == row 时 world.credit_used_uu 同额增加；
##       last_issued_uu == amount_uu
## 不变量：INV-034（**该债权人**本次可发能力，见 _quote_financing）、INV-137（被拒时一个字段都不改）、
##          INV-010（新开一格才取用 entity_seq 一个序号，并入不取用）、INV-038（票息按当季规则定价）
## 失败：该债权人能力不足或批次表已满 → Reject.CREDIT_LIMIT（整笔，**不转投另一债权人**：
##       玩家指定 invpool 却悄悄变成外债，就是把国内额度闸门绕过去了——ADV-C03）；
##       金额 / 期限 / 持有人越界 → Reject.PARAM_RANGE
func issue_bond_to(amount_uu: int, tenor_q: int, holder_in: int, bonds: JWBondBook,
		world: JWWorldMarket, ledger: JWLedger, accounts: JWAccount, q: int, entity_seq: int,
		params: PackedInt64Array) -> int:
	last_issued_uu = 0
	if bonds == null or world == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q, 0)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	if amount_uu <= 0 or amount_uu > JWUnits.AMOUNT_MAX:
		return JWResult.Reject.PARAM_RANGE
	if holder_in != JWUnits.Holder.INVPOOL and holder_in != JWUnits.Holder.ROW:
		return JWResult.Reject.PARAM_RANGE
	# 结构性上界是分期表的相对期数槽位（JWBondBook.HORIZON_MAX）；业务区间由命令层校验。
	if tenor_q < 1 or tenor_q >= JWBondBook.HORIZON_MAX:
		return JWResult.Reject.PARAM_RANGE

	var rc_q: int = _quote_financing(bonds, world, accounts, q, params)
	if rc_q != JWResult.OK:
		return rc_q
	var capacity: int = _q_cap_dom
	var coupon: int = _q_coupon_dom
	if holder_in == JWUnits.Holder.ROW:
		capacity = _q_cap_ext
		coupon = _q_coupon_ext
	if amount_uu > capacity:
		return JWResult.Reject.CREDIT_LIMIT
	var maturity: int = q + tenor_q
	var tgt: int = bonds.merge_target(q, maturity, JWUnits.Amortization.LEVEL_PRINCIPAL,
			holder_in, coupon)
	var rc_pre: int = _segment_precheck(bonds, tgt, params[JWUnits.Param.BOND_BATCH_CAP], q,
			amount_uu, coupon, maturity, holder_in)
	if rc_pre != JWResult.OK:
		return rc_pre

	# ── 这里之后才动账 ──
	_arm_debt_baseline(bonds, q)
	_seal_quarter_price(q)
	if holder_in == JWUnits.Holder.ROW:
		var rcu: int = world.use_external_credit(amount_uu)
		if rcu != JWResult.OK:
			return rcu
	return _issue_one(bonds, ledger, entity_seq, q, amount_uu, coupon, maturity, holder_in)


## S04 §4.2：按 8 档优先级在可用现金内支付一档。
## 步骤：S04 §4.2
## 前置：line ∈ PayLine；due_by_payee 与 payee_agent 等长；payment_priority 是 8 类的全排列
## 后置：按收款方 ID 升序用 split_lr 拆分实付额并逐笔 post()；不足部分登记 arrears 与 deferral_flag
## 不变量：INV-003（拆分精确）、INV-015、INV-016、INV-030、INV-039（实际顺序与优先级一致）
## 失败：拆分和不等于原额 → Fault.SPLIT_MISMATCH（最严重的一类，立即停）
func pay_line(line: int, payee_agent: PackedInt64Array, due_by_payee: PackedInt64Array,
		kind: int, ledger: JWLedger, accounts: JWAccount) -> int:
	if ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, line, 0)
	if line < 0 or line >= JWUnits.PAY_LINE_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, line, JWUnits.PAY_LINE_N)
	if line == JWUnits.PayLine.DEBT_SERVICE:
		# 第 1 档只能走 pay_debt_service：利息与本金要逐批次落到 bond SoA 与
		# flow.gov.interest_paid/principal_paid，用通用支付路径会把它们记成基本支出，
		# INV-027 与 INV-028 同时错。
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, line, 0)
	if not JWUnits.kind_is_classified(kind):
		return JWResult.raise_fault(JWResult.Fault.LEDGER_KIND_UNCLASSIFIED, kind, 0)
	_log_step = JWUnits.Phase.S04

	var n: int = due_by_payee.size()
	if n != payee_agent.size() or n > JWMath.SPLIT_MAX_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, n, payee_agent.size())
	var rc_arity: int = _check_line_arity(line, n)
	if rc_arity != JWResult.OK:
		return rc_arity
	# 实付明细缓冲在这里就位并清零，而不是等到真的要拆分时：last_paid_of() 的语义是
	# 「**本次**调用的逐行实付额」，早退分支（n == 0 / due_total == 0）若不清零，
	# 调用方读到的会是上一档的拆分结果——那是最坏的一类静默串账。
	if _pay_split.size() != n:
		_pay_split.resize(n)
	_pay_split.fill(0)
	if n == 0:
		return JWResult.OK

	var due_total: int = 0
	var i: int = 0
	while i < n:
		var d: int = due_by_payee[i]
		if d < 0:
			# 负应付额会让最大余数法「余数最大者多得 1」反向生效，语义完全相反。
			return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, i, d)
		var a: int = payee_agent[i]
		if a < 0 or a >= JWUnits.AGENT_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, a, JWUnits.AGENT_N)
		due_total += d
		i += 1
	if due_total == 0:
		return JWResult.OK

	# INV-039 的两半：全排列由 set_state_array 在载入期验（state.gov.payment_priority
	# 必须是 8 档的一个全排列），「实际支付顺序与之一致」由 JWTurnRunner 按
	# payment_priority 的顺序逐档调用本函数落实。treasury 自己拿不到「本季还有哪些档没付」
	# 的全局视图，也就没有可执行的判据 —— 见 open_questions。
	#
	# docs/12 §4.2：pay = min(due, gov.cash)。**不扣 reserved_memo**：预留就是为了在本步
	# 执行的，再扣一次等于同一笔钱被两道闸各挡一次。
	var cash: int = accounts.cash_of(JWIds.AGENT_GOV)
	var pay: int = due_total
	if pay > cash:
		pay = cash
	# 拆分决胜键用收款方主体下标：同余数时由 ID 升序决胜，重放逐位可复现（INV-014）。
	var rc_split: int = JWMath.split_lr_into(pay, due_by_payee, payee_agent, _pay_split)
	if rc_split != JWResult.OK:
		# due_total > 0 ⇒ 权重和 > 0，「残差 == total」那条分支走不到这里，非 0 即故障。
		return rc_split

	_sort_payees(payee_agent, n)
	var paid_total: int = 0
	var gov_cash: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	var t: int = 0
	while t < n:
		var idx: int = _pay_order[t]
		var amt: int = _pay_split[idx]
		if amt > 0:
			var payee: int = payee_agent[idx]
			var rc: int = JWResult.OK
			if kind == JWUnits.Kind.PROJECT_PAYMENT:
				# docs/18 R-PROJECT-01 ①：项目付款是四腿分录（与 R-INVEST-01 的资本品购买同构）——
				# 收款方现金 +V（第 0 腿，承载 I 类分类）、政府现金 −V、政府在建工程 +V（docs/12 §4.4
				# 「gov.wip_uu += pay_uu」，INV-092）、收款方净值 −V（权益增记负：收款即收入）。
				# 政府是现金换在建工程，净值不因付款下降；两腿 post() 会把它记成政府净值转移，
				# wip 永远是 0，取消时的减记与投运时的结转都无账可动。
				if _legs_account.size() != BOND_LEG_N or _legs_delta.size() != BOND_LEG_N:
					return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
							_legs_account.size(), BOND_LEG_N)
				_legs_account[0] = JWIds.idx_account(payee, JWIds.ACC_CASH)
				_legs_delta[0] = amt
				_legs_account[1] = gov_cash
				_legs_delta[1] = -amt
				_legs_account[2] = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_WIP)
				_legs_delta[2] = amt
				_legs_account[3] = JWIds.idx_account(payee, JWIds.ACC_NW)
				_legs_delta[3] = -amt
				rc = ledger.post_multi(kind, _legs_account, _legs_delta, 0,
						PRODUCT_NONE, CAUSE_RULE, payee)
			else:
				rc = ledger.post(kind, gov_cash,
						JWIds.idx_account(payee, JWIds.ACC_CASH), amt, 0,
						PRODUCT_NONE, CAUSE_RULE, payee)
			if rc != JWResult.OK:
				return rc
			paid_total += amt
			if line != JWUnits.PayLine.PROJECT_CONTRACTS:
				# 项目档是例外：清单是「逐行」的（一个项目最多三行、各有不同收款方），
				# 行下标不是项目下标，treasury 无从归集到 flow.gov.pay_project_uu[project]。
				# 该档的分项归集由 JWProjectQueue.record_payment 经
				# record_line_attribution() 回写（它才知道行↔项目的对应）。
				var rcf: int = _record_line_flow(line, idx, amt)
				if rcf != JWResult.OK:
					return rcf
		t += 1
	# 基本支出实付（INV-027 的减项）。利息与本金不在此列，它们有各自的流量。
	f_primary_paid = JWMath.check_amount(f_primary_paid + paid_total)

	# 短缺：逐收款方登记，不是整档登记 —— 报告要能说出「谁没拿到、少了多少」。
	i = 0
	while i < n:
		var short: int = due_by_payee[i] - _pay_split[i]
		if short > 0:
			add_arrears(payee_agent[i], short, line)
			deferral_flag[line] = 1
		i += 1
	return JWResult.OK


## 本季某 cell 的**实缴**利润税（只读；骨架之外新增的输出口，签名只增不改）。
##
## 由 JWTurnRunner 在 S06 §6.6 之后逐 cell 读出并写进 `flow.cell.tax_profit_paid_uu[]`
## （那张数组归 JWSectorModel，本类不得引用它）。每次 collect_profit_tax 入口清零，不跨季累积。
## 步骤：S06（紧接 collect_profit_tax 之后）
## 前置：cell ∈ [0, CELL)
## 后置：不改状态
## 不变量：INV-031（Σ 本函数 == flow.gov.receipts_profit_tax_uu 的本季增量）
## 失败：越界 → 返回 0
func profit_tax_paid_of(cell: int) -> int:
	if cell < 0 or cell >= _profit_tax_paid_by_cell.size():
		return 0
	return _profit_tax_paid_by_cell[cell]


## 上一次 pay_line() 的**逐行实付额**（只读；骨架之外新增的输出口，签名只增不改）。
##
## 为什么必须有：JWLaborMarket.record_public_wage_paid 与 JWProjectQueue.record_payment
## 都要求「与 payee_agent 逐项对应的实付额」，而 pay_line 的拆分结果只存在私有的 _pay_split 里。
## 没有它，调用方只能拿 due 冒充 paid —— 欠付的那一部分就会被当成已付，INV-030 与 INV-079 同时错。
## 本函数不改任何状态，也不进状态块协议、不进 state_hash。
## 步骤：S04（紧接一次 pay_line 之后）
## 前置：row ∈ [0, last_paid_row_count())
## 后置：不改状态
## 不变量：INV-003（Σ last_paid_of == 本次实付总额）
## 失败：越界 → 返回 0（不登记故障：调用方用 row_count 自行界定范围）
func last_paid_of(row: int) -> int:
	if row < 0 or row >= _pay_split.size():
		return 0
	return _pay_split[row]


## 上一次 pay_line() 的拆分行数。
## 步骤：S04
## 前置：无
## 后置：不改状态
## 不变量：INV-003
## 失败：无
func last_paid_row_count() -> int:
	return _pay_split.size()


## 登记一笔欠付（唯一入口；别处不得直接写 arrears）。
## 步骤：S02, S04, S06
## 前置：amount_uu > 0
## 后置：arrears 与 arrears_by_payee 同步增加；flow.arrears_added 与 log.arrears 各增一条
## 不变量：INV-030（arrears == Σ arrears_by_payee >= 0）
## 失败：无（这是业务性短缺的登记点，不是故障）
func add_arrears(payee_agent: int, amount_uu: int, reason_line: int) -> void:
	if amount_uu <= 0:
		if amount_uu < 0:
			# 负欠付 == 凭空清偿。清偿有它自己的入口（clear_arrears），要过现金。
			JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, payee_agent, amount_uu)
		return
	if payee_agent < 0 or payee_agent >= JWUnits.AGENT_N \
			or arrears_by_payee.size() != JWUnits.AGENT_N \
			or f_arrears_added.size() != JWUnits.AGENT_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, payee_agent, JWUnits.AGENT_N)
		return
	arrears = JWMath.check_amount(arrears + amount_uu)
	arrears_by_payee[payee_agent] = arrears_by_payee[payee_agent] + amount_uu
	f_arrears_added[payee_agent] = f_arrears_added[payee_agent] + amount_uu
	_arrears_log_append(payee_agent, amount_uu, reason_line)


## 清偿历史欠付。
## 步骤：S02, S04
## 前置：amount_uu <= arrears_by_payee[payee]
## 后置：arrears 减少；flow.arrears_cleared 增加
## 不变量：INV-030
## 失败：超额清偿 → Fault.LEDGER_IMBALANCE
func clear_arrears(payee_agent: int, amount_uu: int, ledger: JWLedger, accounts: JWAccount) -> int:
	if ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, payee_agent, 0)
	if payee_agent < 0 or payee_agent >= JWUnits.AGENT_N \
			or arrears_by_payee.size() != JWUnits.AGENT_N \
			or f_arrears_cleared.size() != JWUnits.AGENT_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				payee_agent, JWUnits.AGENT_N)
	if amount_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, payee_agent, amount_uu)
	if amount_uu == 0:
		return JWResult.OK
	if amount_uu > arrears_by_payee[payee_agent]:
		# 超额清偿会让某个收款方的欠付变成负数，INV-030 的「>= 0」与求和式同时破。
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE,
				amount_uu, arrears_by_payee[payee_agent])
	if amount_uu > accounts.cash_of(JWIds.AGENT_GOV):
		# 现金不够就不是「清偿」，而是继续欠着：不部分清、不改账，交回调用方决定。
		return JWResult.Reject.NO_FUNDING
	_log_step = JWUnits.Phase.S04
	# kind 用 TRANSFER：欠付是上一次未完成支付的残留，补付时不能再算一次生产法／支出法
	# 口径（原始支出在发生时已经被它自己的 kind 分类过）。TRANSFER 的三口径全 none
	# （JWUnits.KIND_IS_REDISTRIBUTION），正好表达「只是资金再分配」。
	var rc: int = ledger.post(JWUnits.Kind.TRANSFER,
			JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH),
			JWIds.idx_account(payee_agent, JWIds.ACC_CASH), amount_uu, 0,
			PRODUCT_NONE, CAUSE_RULE, payee_agent)
	if rc != JWResult.OK:
		return rc
	arrears -= amount_uu
	arrears_by_payee[payee_agent] = arrears_by_payee[payee_agent] - amount_uu
	f_arrears_cleared[payee_agent] = f_arrears_cleared[payee_agent] + amount_uu
	# 清偿也是真金白银出库，必须进基本支出，否则 INV-027 的现金恒等式左右不等。
	f_primary_paid = JWMath.check_amount(f_primary_paid + amount_uu)
	return JWResult.OK


## 第三轮裁定（重组核销欠付）：债务重组了结的欠付备查额从 gov.arrears 中**非现金**注销。
## 步骤：S02（debt_restructure 命令受理后，由 JWTurnRunner._cmd_restructure 按
##       JWBondBook.last_writeoff_arrears_uu 调用）
## 前置：amount_uu >= 0；amount_uu <= arrears_by_payee[payee_agent]
## 后置：arrears 与 arrears_by_payee 同减；flow.gov.arrears_written_off_uu[payee] 同增；
##       **不过账、不动现金、不进基本支出**——欠付是备查额，从未进过任何科目，注销它也就没有分录
##       （债务本金的减记另走 WRITEOFF 分录与 recognized_writeoffs，二者不重叠）
## 不变量：INV-030 扩展式 arrears_end == start + 新增 − 清偿 − 核销，且 arrears == Σ arrears_by_payee ≥ 0
## 失败：超额 → Fault.LEDGER_IMBALANCE（批次上的已计未付与国库欠付脱钩，是缺陷不是短缺，不截断）
##
## 与 clear_arrears 的区别：清偿要过现金并计入基本支出（INV-027）；核销是债权人经重组放弃（减记 / 违约）
## 或把逾期本金挪回分期表（延期）后，这笔欠付不再以「欠付」的形式存在——同一个数不能既挂在欠付里、
## 又以减记或到期本金的形式再算一次。
func write_off_arrears(payee_agent: int, amount_uu: int) -> int:
	if payee_agent < 0 or payee_agent >= JWUnits.AGENT_N \
			or arrears_by_payee.size() != JWUnits.AGENT_N \
			or f_arrears_written_off.size() != JWUnits.AGENT_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				payee_agent, JWUnits.AGENT_N)
	if amount_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, payee_agent, amount_uu)
	if amount_uu == 0:
		return JWResult.OK
	if amount_uu > arrears_by_payee[payee_agent]:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE,
				amount_uu, arrears_by_payee[payee_agent])
	arrears -= amount_uu
	arrears_by_payee[payee_agent] = arrears_by_payee[payee_agent] - amount_uu
	f_arrears_written_off[payee_agent] = f_arrears_written_off[payee_agent] + amount_uu
	return JWResult.OK


## S06 §6.5：个人所得税（含征收能力 P11 与税基侵蚀）。
## 步骤：S06 §6.5
## 前置：税基只来自**已过账的收入分录**（wage_income + property_income）；转移收入不计税（OQ-212）
## 后置：collected 入账；(liability − collected) 进 tax_receivable，差额显式登记不消失
## 不变量：INV-031（tax_receivable 恒等式）、ADV-05（税率 10%→60% 的非线性曲线）
## 失败：群组现金不足 → 按现金上限征收，差额进应收；**不得把群组现金打成负数**
func collect_income_tax(pop: JWPopulation, policy_params: PackedInt64Array,
		ledger: JWLedger, accounts: JWAccount, params: PackedInt64Array) -> int:
	if pop == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, JWUnits.GROUP, 0)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	if policy_params.size() != JWUnits.POLICY_PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				policy_params.size(), JWUnits.POLICY_PARAM_N)
	if pop.f_wage_income.size() != JWUnits.GROUP or pop.f_property_income.size() != JWUnits.GROUP \
			or pop.f_income_tax_paid.size() != JWUnits.GROUP \
			or pop.base_real_income.size() != JWUnits.GROUP \
			or pop.population.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pop.f_wage_income.size(), JWUnits.GROUP)
	_log_step = JWUnits.Phase.S06

	var exempt_ppm: int = policy_params[JWIds.idx_policy_param(
			POLICY_INCOME_TAX, P01_SLOT_EXEMPTION_PPM)]
	var b2_ppm: int = policy_params[JWIds.idx_policy_param(
			POLICY_INCOME_TAX, P01_SLOT_BRACKET2_PPM)]
	var rate1: int = policy_params[JWIds.idx_policy_param(
			POLICY_INCOME_TAX, P01_SLOT_RATE1_PPM)]
	var rate2: int = policy_params[JWIds.idx_policy_param(
			POLICY_INCOME_TAX, P01_SLOT_RATE2_PPM)]
	var capacity: int = tax_capacity_ppm
	if capacity > JWUnits.PPM:
		capacity = JWUnits.PPM
	if capacity < 0:
		capacity = 0
	var evasion_slope: int = params[JWUnits.Param.TAX_EVASION_SLOPE_PPM]
	var base_rate: int = params[JWUnits.Param.TAX_BASE_RATE_PPM]
	var gov_cash: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)

	var g: int = 0
	while g < JWUnits.GROUP:
		# 税基只来自已过账的收入分录（ADV-05 的防线：不存在独立的「税收系数」字段）。
		# 转移收入不计税（OQ-212）。
		var base: int = pop.f_wage_income[g] + pop.f_property_income[g]
		if base > 0:
			# 级距的 μU 口径：P01 的四个 player_param 都是 ppm，分母是「该组基年应税收入」
			# ref_g_uu。运行期能拿到的唯一基年收入基准是 content.base_per_capita_real_income_uu，
			# 乘当期人口即该组的基年收入规模。见 open_questions：契约里的
			# param.income_tax_ref_base_uu_per_q 没有进运行期参数表。
			# R-PERIOD-01：base_real_income 是**年**人均（内容口径，4 位有效数字），税基是本季收入，
			# 级距基准必须折成季度——否则免征额被放大 4 倍，基年有效税率从约 19% 跌到约 2%。
			var ref_g: int = JWMath.floor_div(JWMath.mul(pop.base_real_income[g], pop.population[g]), 4)
			var lower1: int = JWMath.mul_ppm(ref_g, exempt_ppm)
			var lower2: int = JWMath.mul_ppm(ref_g, b2_ppm)
			if lower2 < lower1:
				# precondition.bracket_order（policy_P01.json）：第二级起征点不得低于免征额。
				# 载入期会拒掉倒挂的组合，这里再兜一次，保证级距函数单调。
				lower2 = lower1
			# 税基侵蚀：税率越高，实际可征税基越小（docs/12 §6.5）。
			var gross: int = _bracket_tax(base, lower1, lower2, rate1, rate2)
			var avg_rate_ppm: int = JWMath.mul_div_floor(gross, JWUnits.PPM, base)
			var over: int = avg_rate_ppm - base_rate
			if over < 0:
				over = 0
			var evasion_ppm: int = JWMath.clamp_i(
					JWMath.mul_ppm(evasion_slope, over), 0, JWUnits.PPM)
			var base_eff: int = base - JWMath.mul_ppm(base, evasion_ppm)
			var liability: int = _bracket_tax(base_eff, lower1, lower2, rate1, rate2)
			# 征收能力 P11：应纳不等于实收。
			var collected: int = JWMath.mul_ppm(liability, capacity)
			var group_agent: int = JWIds.agent_of_group(g)
			var group_cash: int = accounts.cash_of(group_agent)
			if collected > group_cash:
				# 现金上限：**不得把群组现金打成负数**，差额进应收，不消失。
				collected = group_cash
			if collected < 0:
				collected = 0
			if collected > 0:
				var rc: int = ledger.post(JWUnits.Kind.INCOME_TAX,
						JWIds.idx_account(group_agent, JWIds.ACC_CASH), gov_cash,
						collected, 0, PRODUCT_NONE, CAUSE_RULE, g)
				if rc != JWResult.OK:
					return rc
				f_receipts_income_tax = JWMath.check_amount(f_receipts_income_tax + collected)
				pop.f_income_tax_paid[g] = pop.f_income_tax_paid[g] + collected
			tax_receivable = JWMath.check_amount(tax_receivable + (liability - collected))
		g += 1
	return JWResult.OK


## R-PROCURE-01：年度计划「政府采购」档折成的每季预算（μU，内容常量，加载器写入，不进状态块）。
var procurement_budget_q_uu: int = 0
## flow.gov.procurement_budget_q_uu —— 本季核定的采购预算（μU）。S04 写、S05 读，S01 清零。
var f_procure_budget: int = 0
## flow.gov.rollover_uu —— 本季续发额（R-ROLLOVER-01），μU。S02 写，S01 清零。
var f_rollover: int = 0
## flow.gov.money_issued_uu —— 本季货币发行额（R-MONEY-01）。写入者 S04
var f_money_issued: int = 0


## R-PROCURE-01：核定本季政府采购预算（S04 采购档；此前已按 R-FINANCE-01 融资）。
## 步骤：S04 §4.2（2f）
## 前置：amount >= 0
## 后置：f_procure_budget == amount；不动现金（钱在 S05 成交时才流出）
## 不变量：INV-033（预算不是资产）
## 失败：负额 → Fault
func authorize_procurement(amount_uu: int) -> int:
	if amount_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, amount_uu, 0)
	f_procure_budget = JWMath.check_amount(amount_uu)
	return JWResult.OK


## R-FEE-01：登记一笔其它收入（公共服务收费等，docs/10 flow.gov.receipts_other_uu）。
## 步骤：S05、S06
## 前置：该笔已过账到 gov 现金
## 后置：f_receipts_other 增加；进四季审查窗口与下季偿债率分母
## 不变量：INV-027（收支恒等式的收入项）
## 失败：负额 → Fault
func record_other_receipt(amount_uu: int) -> int:
	if amount_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, amount_uu, 0)
	f_receipts_other = JWMath.check_amount(f_receipts_other + amount_uu)
	return JWResult.OK


## S06 §6.6：企业利润税（利润与现金严格分开）。
## 步骤：S06 §6.6
## 前置：taxable_by_cell 已由 JWSectorModel 算出（利润扣结转亏损后）并由 TurnRunner 传入
##       —— 不直接引用 JWSectorModel，避免同秩依赖（§3.2）
## 后置：paid = min(tax, cell.cash)；差额进 tax_receivable（**不是核销**）
## 不变量：INV-031、INV-116（营业盈余按残差定义）
## 失败：现金不足不是故障；应收登记缺失才是 → Fault.LEDGER_IMBALANCE
func collect_profit_tax(taxable_by_cell: PackedInt64Array, policy_params: PackedInt64Array,
		ledger: JWLedger, accounts: JWAccount, params: PackedInt64Array) -> int:
	if ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, JWUnits.CELL, 0)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	if policy_params.size() != JWUnits.POLICY_PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				policy_params.size(), JWUnits.POLICY_PARAM_N)
	if taxable_by_cell.size() != JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				taxable_by_cell.size(), JWUnits.CELL)
	_log_step = JWUnits.Phase.S06

	var rate: int = policy_params[JWIds.idx_policy_param(POLICY_PROFIT_TAX, P02_SLOT_RATE_PPM)]
	var capacity: int = tax_capacity_ppm
	if capacity > JWUnits.PPM:
		capacity = JWUnits.PPM
	if capacity < 0:
		capacity = 0
	var gov_cash: int = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	if _profit_tax_paid_by_cell.size() != JWUnits.CELL:
		_profit_tax_paid_by_cell.resize(JWUnits.CELL)
	_profit_tax_paid_by_cell.fill(0)

	var i: int = 0
	while i < JWUnits.CELL:
		# taxable 已由 JWSectorModel 扣过结转亏损；这里只保证不为负（亏损不产生负税）。
		var taxable: int = taxable_by_cell[i]
		if taxable > 0:
			# docs/12 §6.6 逐字：先按税率、再按征收能力，两次 mul_ppm。
			# （docs/10 的 M2「禁止连乘两个 ppm」要求合成后只取整一次；两份文件在此处不一致，
			#  按 docs/18 的优先级 docs/12 > docs/10，照 §6.6 的两步写法执行。）
			var tax: int = JWMath.mul_ppm(taxable, rate)
			tax = JWMath.mul_ppm(tax, capacity)
			var cell_agent: int = JWIds.agent_of_cell(i)
			var paid: int = tax
			var cell_cash: int = accounts.cash_of(cell_agent)
			if paid > cell_cash:
				# 利润 ≠ 现金：有利润没现金照样欠税，差额进应收，**不是核销**。
				paid = cell_cash
			if paid < 0:
				paid = 0
			if paid > 0:
				var rc: int = ledger.post(JWUnits.Kind.PROFIT_TAX,
						JWIds.idx_account(cell_agent, JWIds.ACC_CASH), gov_cash,
						paid, 0, PRODUCT_NONE, CAUSE_RULE, i)
				if rc != JWResult.OK:
					return rc
				f_receipts_profit_tax = JWMath.check_amount(f_receipts_profit_tax + paid)
				_profit_tax_paid_by_cell[i] = paid
			tax_receivable = JWMath.check_amount(tax_receivable + (tax - paid))
		i += 1

	# 年化收入改由 annualize_receipts() 在 S06 全部收入入账之后计算（R-TAXBASE-01 之后利润税先于个税）。
	return JWResult.OK


## R-DSR-01：本季经常性收入（个税、利润税、其它收入）× 4 → 下一季 §2.6 偿债率的分母。
## 步骤：S06（个税与公共服务收费之后）
## 前置：本季全部经常性收入已入账
## 后置：state.gov.receipts_annualized_uu 更新
## 不变量：INV-038
## 失败：溢出 → Fault
func annualize_receipts() -> int:
	_receipts_annualized = JWMath.check_amount(JWMath.mul(
			f_receipts_income_tax + f_receipts_profit_tax + f_receipts_other,
			QUARTERS_PER_YEAR))
	return JWResult.OK


## S06 §6.9：政府口径的恒等式终检（亦在 S02 步末与季末由调度层调用）。
## 步骤：S06 §6.9、S02 步末、季末
## 前置：本季全部分录已写
## 后置：不改状态
## 不变量：INV-027（现金恒等式残差恰为 0）、INV-028（债务恒等式）、INV-030（含核销项）、
##          INV-033（归零只在预留窗口关上后核，R-RESERVE-01）、INV-035（debt == Σ 未结清批次，R-INV035-01）
## 失败：Fault.LEDGER_IMBALANCE / Fault.BOND_MISMATCH，导出故障包，**不得自动修正**
func check_fiscal_identities(bonds: JWBondBook, accounts: JWAccount) -> int:
	if bonds == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, 0)

	# ── INV-035：debt == Σ 未结清批次的未偿本金 ──
	# 与 bonds.debt_outstanding() 对账而不是直接用它：两条路径算出同一个数，
	# 才能证明「状态位与金额没有各走各的」。已到期／已核销的批次必须余额为 0。
	var n: int = bonds.count
	if n < 0 or n > bonds.principal_outstanding.size() or bonds.status.size() < n:
		return JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, n,
				bonds.principal_outstanding.size())
	var live_sum: int = 0
	var b: int = 0
	while b < n:
		var out_b: int = bonds.principal_outstanding[b]
		if out_b < 0:
			return JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, b, out_b)
		var st: int = bonds.status[b]
		if st == JWUnits.BondStatus.MATURED or st == JWUnits.BondStatus.WRITTEN_OFF:
			if out_b != 0:
				return JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, b, out_b)
		else:
			live_sum += out_b
		b += 1
	var debt_end: int = bonds.debt_outstanding()
	if debt_end != live_sum:
		return JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, debt_end, live_sum)

	# ── INV-030：arrears == Σ arrears_by_payee >= 0，且季内变化被流量完全解释 ──
	if arrears < 0 or tax_receivable < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, arrears, tax_receivable)
	var by_payee_sum: int = JWMath.sum(arrears_by_payee)
	if by_payee_sum != arrears:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, arrears, by_payee_sum)
	var i: int = 0
	while i < arrears_by_payee.size():
		if arrears_by_payee[i] < 0:
			return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, i, arrears_by_payee[i])
		i += 1

	# ── INV-033：reserved_memo <= cash；INV-032：承诺额不得为负 ──
	var cash_end: int = accounts.cash_of(JWIds.AGENT_GOV)
	if reserved_memo < 0 or reserved_memo > cash_end:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, reserved_memo, cash_end)
	if committed_memo < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, committed_memo, 0)

	# 季初基准没武装（载入后直接终检、或本局还没跑过 S01）时，
	# 逐季恒等式没有左端，跳过比拿 0 当基准去报一个假故障更诚实。
	if _cash_baseline_armed == 0:
		if JWResult.has_pending():
			return JWResult.pending_code()
		return JWResult.OK

	# ── INV-033 的后半句：季末归零（预留要么执行要么释放） ──
	# 裁定 R-RESERVE-01：这是**季末**不变量。本函数也在 S02 步末被调用，那时预留窗口还开着
	# （S02 建立、S04/S05 执行或释放），合法非零，只核上面的 reserved_memo <= cash；
	# 窗口在 release_reservations 关上之后（S06 §6.9 与季末）才核归零。漏了释放的那一季，
	# 下一季 begin_quarter 会把残留报成故障，这条检查不会因窗口没关而永远跳过。
	if _reserve_open == 0 and reserved_memo != 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, reserved_memo, 0)

	# ── INV-027：cash_end == cash_start + 收入 + 新增借款 − 基本支出 − 利息 − 还本 ──
	var receipts: int = f_receipts_income_tax + f_receipts_profit_tax + f_receipts_other
	var expect_cash: int = _cash_at_quarter_start + receipts + f_new_borrowing + f_money_issued \
			- f_primary_paid - f_interest_paid - f_principal_paid
	if cash_end != expect_cash:
		# **不得自动修正，绝不用「平衡修正项」抹平**（docs/12 §6.10）。
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, cash_end, expect_cash)

	# ── INV-030 的流量解释（第三轮裁定扩展式：期末 = 期初 + 新增 − 清偿 − 核销） ──
	var expect_arrears: int = _arrears_at_quarter_start \
			+ JWMath.sum(f_arrears_added) - JWMath.sum(f_arrears_cleared) \
			- JWMath.sum(f_arrears_written_off)
	if arrears != expect_arrears:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, arrears, expect_arrears)

	# ── INV-028：debt_end == debt_start + 新增借款 − 还本 − 确认减记 ──
	if _debt_baseline_q >= 0:
		var expect_debt: int = _debt_at_quarter_start + f_new_borrowing \
				- f_principal_paid - f_writeoffs
		if debt_end != expect_debt:
			return JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, debt_end, expect_debt)

	if JWResult.has_pending():
		return JWResult.pending_code()
	return JWResult.OK


## 登记一笔**由调用方自己过账**的政府支付（docs/17 §4.12 未列，实现期新增）。
##
## 为什么必须有：补助（JWPolicyEngine.pay_subsidy）、政策开关成本（§2.1）与取消赔偿（§2.7）
## 都自己调 ledger.post()，而 flow.gov.pay_subsidies_uu[] 与 flow.gov.primary_paid_uu
## 归 treasury 所有。没有这个入口，那几笔钱就只有现金腿没有流量登记，
## INV-027 的「基本支出」一项会系统性少计 —— 那正是 §6.10 禁止的「静默」。
## 本函数**不过账**：钱已经由调用方过完了，这里只登记流量。
## 步骤：S02, S04, S05
## 前置：调用方已成功 post()；line != DEBT_SERVICE；同一笔钱不得既走 pay_line 又走本函数
## 后置：对应 flow.gov.pay_* 与 flow.gov.primary_paid_uu 增加
## 不变量：INV-027
## 失败：档位或实体下标越界 → INDEX_OUT_OF_RANGE
func record_line_payment(line: int, entity_idx: int, amount_uu: int) -> int:
	var rc: int = record_line_attribution(line, entity_idx, amount_uu)
	if rc != JWResult.OK:
		return rc
	f_primary_paid = JWMath.check_amount(f_primary_paid + amount_uu)
	return JWResult.OK


## 把一笔**已由 pay_line 付出**的钱归集到分项流量（docs/17 §4.12 未列，实现期新增）。
##
## 只有项目档需要它：pay_line 的清单是逐行的，行下标不是项目下标，
## 只有 JWProjectQueue 知道「第几行属于哪个项目」。**不动 primary_paid**——
## 那一笔在 pay_line 里已经计过，再计一次 INV-027 就会多减一遍。
## 步骤：S04 §4.4
## 前置：amount_uu 来自同一次 pay_line 的实付额；line != DEBT_SERVICE
## 后置：对应 flow.gov.pay_* 增加
## 不变量：INV-027（不重复计入基本支出）、INV-092
## 失败：档位或实体下标越界 → INDEX_OUT_OF_RANGE
func record_line_attribution(line: int, entity_idx: int, amount_uu: int) -> int:
	if line < 0 or line >= JWUnits.PAY_LINE_N or line == JWUnits.PayLine.DEBT_SERVICE:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, line, JWUnits.PAY_LINE_N)
	if amount_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, line, amount_uu)
	if amount_uu == 0:
		return JWResult.OK
	return _record_line_flow(line, entity_idx, amount_uu)


## 已签合同承诺的唯一变动入口（docs/17 §4.12 未列，实现期新增）。
##
## 为什么必须有：INV-032 规定 committed_memo 只由「新签合同 +」「履约付款 −」「取消 −」变动，
## 而新签在 JWPolicyEngine / JWProjectQueue，取消在 JWProjectQueue.cancel——它们都持有
## treasury 引用却没有可调的入口。留空就只能让别人直接改字段，「唯一入口」当场失效。
## 步骤：S02, S04, S07
## 前置：committed_memo + delta_uu >= 0
## 后置：committed_memo 变动；**不产生任何现金移动**（memo 不是资产）
## 不变量：INV-032
## 失败：结果为负 → Fault.LEDGER_IMBALANCE（承诺不能变成一笔负债权）
func record_commitment(delta_uu: int) -> int:
	var next: int = committed_memo + delta_uu
	if next < 0:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, committed_memo, delta_uu)
	committed_memo = JWMath.check_amount(next)
	return JWResult.OK


## §1.7 日志协议：每季 S01 重置本季游标（日志不进 state_hash）。
## 步骤：S01
## 前置：phase == S01
## 后置：log.arrears 的写游标归零
## 不变量：INV-011
## 失败：无
func log_reset_quarter() -> void:
	# 只移游标不清数组：上季的行在被覆盖前仍可读，故障包导出时不至于面对一张空表。
	_log_n = 0


## §1.7 日志协议：本季已写行数，供 INV-011 / INV-139 对账。
## 步骤：各步末
## 前置：无
## 后置：不改状态
## 不变量：INV-011, INV-139
## 失败：无
func log_row_count() -> int:
	return _log_n


## §1.7 日志协议：当前容量；写满时按 1.5 倍扩容并写一条告警行。
## 步骤：各步
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func log_capacity() -> int:
	return a_payee.size()


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：尚未 allocate 过
## 后置：全部状态与流量数组 resize 到契约长度，log.arrears resize 到 JWUnits.LOG_CAP0
## 不变量：INV-136
## 失败：无
func allocate() -> void:
	arrears_by_payee.resize(JWUnits.AGENT_N)
	arrears_by_payee.fill(0)
	payment_priority.resize(JWUnits.PAY_LINE_N)
	# 默认顺序即 docs/12 §2.2 的 8 档表：debt_service 在先、discretionary 在后，
	# 与 JWUnits.PayLine 的枚举值一一对应。fill(0) 会得到一个非全排列的非法初值，
	# 而 set_state_array 恰好要拒绝非全排列 —— 那样载入前的自检就永远是红的。
	var p: int = 0
	while p < JWUnits.PAY_LINE_N:
		payment_priority[p] = p
		p += 1
	deferral_flag.resize(JWUnits.PAY_LINE_N)
	deferral_flag.fill(0)

	f_pay_transfers.resize(JWUnits.GROUP)
	f_pay_transfers.fill(0)
	f_pay_subsidies.resize(JWUnits.CELL)
	f_pay_subsidies.fill(0)
	f_pay_project.resize(JWUnits.PROJECT_CAP0)
	f_pay_project.fill(0)
	f_pay_opex.resize(JWUnits.OPEX_N)
	f_pay_opex.fill(0)
	f_arrears_added.resize(JWUnits.AGENT_N)
	f_arrears_added.fill(0)
	f_arrears_cleared.resize(JWUnits.AGENT_N)
	f_arrears_cleared.fill(0)
	f_arrears_written_off.resize(JWUnits.AGENT_N)
	f_arrears_written_off.fill(0)
	f_nonmarket_output.resize(JWUnits.R)
	f_nonmarket_output.fill(0)

	a_payee.resize(JWUnits.LOG_CAP0)
	a_payee.fill(0)
	a_amount.resize(JWUnits.LOG_CAP0)
	a_amount.fill(0)
	a_reason.resize(JWUnits.LOG_CAP0)
	a_reason.fill(0)
	a_step.resize(JWUnits.LOG_CAP0)
	a_step.fill(0)

	# 私有 scratch：post_multi 的四条腿是定长的，支付拆分缓冲的长度随档位变化，
	# 由 pay_line 在长度不符时才 resize（容量复用，热路径不新建对象）。
	_legs_account.resize(BOND_LEG_N)
	_legs_account.fill(0)
	_legs_delta.resize(BOND_LEG_N)
	_legs_delta.fill(0)
	_pay_split.resize(0)
	_pay_order.resize(JWMath.SPLIT_MAX_N)
	_pay_order.fill(0)
	_profit_tax_paid_by_cell.resize(JWUnits.CELL)
	_profit_tax_paid_by_cell.fill(0)

	arrears = 0
	tax_receivable = 0
	committed_memo = 0
	reserved_memo = 0
	credit_limit_domestic = 0
	service_opex_committed = 0
	tax_capacity_ppm = 0
	tax_capacity_built_ppm = 0
	rounding_residual = 0
	_cash_at_quarter_start = 0
	_default_streak_q = 0
	_arrears_at_quarter_start = 0
	_debt_at_quarter_start = 0
	_debt_baseline_q = -1
	_cash_baseline_armed = 0
	_reserve_open = 0
	_receipts_annualized = 0
	_log_n = 0
	_log_step = 0
	last_issued_uu = 0
	_q_coupon_dom = 0
	_q_coupon_ext = 0
	_q_cap_dom = 0
	_q_cap_ext = 0
	_px_armed = false
	_px_q = 0
	_px_coupon_dom = 0
	_px_coupon_ext = 0
	reset_flows()


## §1.6 状态块协议：只读取用（返回引用，调用方不得写）。
## 步骤：全部
## 前置：i 在 [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136（顺序是 schema 的一部分）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return arrears_by_payee
	if i == 1:
		return payment_priority
	if i == 2:
		return deferral_flag
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：仅 LOAD / MIG（静态检查限定 systems/content_loader.gd 与 systems/saves.gd）。
## 步骤：LOAD / MIG
## 前置：v.size() 等于契约长度
## 后置：对应数组被整体替换
## 不变量：INV-136；payment_priority 必须是 8 类的全排列（Reject.PRIORITY_INCOMPLETE）
## 失败：长度不符或非全排列 → Load.FIN_LINES；越界 → INDEX_OUT_OF_RANGE
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != JWUnits.AGENT_N:
			return JWResult.Load.FIN_LINES
		var k: int = 0
		while k < v.size():
			if v[k] < 0:
				# 负欠付载不进来：INV-030 要求逐收款方 >= 0。
				return JWResult.Load.FIN_LINES
			k += 1
		arrears_by_payee = v
		return JWResult.OK
	if i == 1:
		if v.size() != JWUnits.PAY_LINE_N:
			return JWResult.Load.FIN_LINES
		if not _is_pay_line_permutation(v):
			# 非全排列意味着某一档没有位置、或某一档排了两次：INV-039 的「实际支付顺序
			# 与之一致」就无从谈起。用 Reject.PRIORITY_INCOMPLETE 精确说出是哪一类错。
			return JWResult.Reject.PRIORITY_INCOMPLETE
		payment_priority = v
		return JWResult.OK
	if i == 2:
		if v.size() != JWUnits.PAY_LINE_N:
			return JWResult.Load.FIN_LINES
		var j: int = 0
		while j < v.size():
			if v[j] != 0 and v[j] != 1:
				return JWResult.Load.FIN_LINES
			j += 1
		deferral_flag = v
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())


## §1.6 状态块协议：读标量状态（顺序见 STATE_SCALAR_IDS）。
## 步骤：全部
## 前置：i 在 [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func state_scalar(i: int) -> int:
	if i == 0:
		return arrears
	if i == 1:
		return tax_receivable
	if i == 2:
		return committed_memo
	if i == 3:
		return reserved_memo
	if i == 4:
		return credit_limit_domestic
	if i == 5:
		return service_opex_committed
	if i == 6:
		return tax_capacity_ppm
	if i == 7:
		return rounding_residual
	if i == 8:
		return _receipts_annualized
	if i == 9:
		return tax_capacity_built_ppm
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：仅 LOAD / MIG。
## 步骤：LOAD / MIG
## 前置：i 在 [0, STATE_SCALAR_IDS.size())
## 后置：对应标量被写
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE
func set_state_scalar(i: int, v: int) -> int:
	if i == 0:
		arrears = v
		return JWResult.OK
	if i == 1:
		tax_receivable = v
		return JWResult.OK
	if i == 2:
		committed_memo = v
		return JWResult.OK
	if i == 3:
		reserved_memo = v
		return JWResult.OK
	if i == 4:
		credit_limit_domestic = v
		return JWResult.OK
	if i == 5:
		service_opex_committed = v
		return JWResult.OK
	if i == 6:
		tax_capacity_ppm = v
		return JWResult.OK
	if i == 7:
		rounding_residual = v
		return JWResult.OK
	if i == 8:
		_receipts_annualized = v
		return JWResult.OK
	if i == 9:
		tax_capacity_built_ppm = v
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())


## §1.6 状态块协议：读流量数组（顺序见 FLOW_ARRAY_IDS）。
## 步骤：全部
## 前置：i 在 [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func flow_array(i: int) -> PackedInt64Array:
	if i == 0:
		return f_pay_transfers
	if i == 1:
		return f_pay_subsidies
	if i == 2:
		return f_pay_project
	if i == 3:
		return f_pay_opex
	if i == 4:
		return f_arrears_added
	if i == 5:
		return f_arrears_cleared
	if i == 6:
		return f_nonmarket_output
	if i == 7:
		return f_arrears_written_off
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：读流量标量（顺序见 FLOW_SCALAR_IDS）。
## 步骤：全部
## 前置：i 在 [0, FLOW_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func flow_scalar(i: int) -> int:
	if i == 0:
		return f_receipts_income_tax
	if i == 1:
		return f_receipts_profit_tax
	if i == 2:
		return f_receipts_other
	if i == 3:
		return f_new_borrowing
	if i == 4:
		return f_primary_paid
	if i == 5:
		return f_interest_paid
	if i == 6:
		return f_principal_paid
	if i == 7:
		return f_writeoffs
	if i == 8:
		return f_pay_public_wages
	if i == 9:
		return f_pay_procurement
	if i == 10:
		return f_final_consumption
	if i == 11:
		return f_gross_capital_formation
	if i == 12:
		return f_procure_budget
	if i == 13:
		return f_rollover
	if i == 14:
		return f_money_issued
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：仅 S01；全部 FLOW_* 归零。
## 步骤：S01
## 前置：phase == S01
## 后置：全部 flow.gov.* 数组与标量为 0
## 不变量：INV-009（流量整表清零）
## 失败：无
func reset_flows() -> void:
	f_pay_transfers.fill(0)
	f_pay_subsidies.fill(0)
	f_pay_project.fill(0)
	f_pay_opex.fill(0)
	f_arrears_added.fill(0)
	f_arrears_cleared.fill(0)
	f_arrears_written_off.fill(0)
	f_nonmarket_output.fill(0)
	f_receipts_income_tax = 0
	f_receipts_profit_tax = 0
	f_receipts_other = 0
	f_procure_budget = 0
	f_rollover = 0
	f_money_issued = 0
	f_new_borrowing = 0
	f_primary_paid = 0
	f_interest_paid = 0
	f_principal_paid = 0
	f_writeoffs = 0
	f_pay_public_wages = 0
	f_pay_procurement = 0
	f_final_consumption = 0
	f_gross_capital_formation = 0


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01
## 前置：reset_flows() 已调用
## 后置：不改状态
## 不变量：INV-009
## 失败：非 0 → 调用方 raise Fault.FLOW_NOT_RESET
func flow_abs_sum() -> int:
	var acc: int = JWMath.sum_abs(f_pay_transfers)
	acc += JWMath.sum_abs(f_pay_subsidies)
	acc += JWMath.sum_abs(f_pay_project)
	acc += JWMath.sum_abs(f_pay_opex)
	acc += JWMath.sum_abs(f_arrears_added)
	acc += JWMath.sum_abs(f_arrears_cleared)
	acc += JWMath.sum_abs(f_arrears_written_off)
	acc += JWMath.sum_abs(f_nonmarket_output)
	acc += JWMath.absi(f_receipts_income_tax)
	acc += JWMath.absi(f_receipts_profit_tax)
	acc += JWMath.absi(f_receipts_other)
	acc += JWMath.absi(f_new_borrowing)
	acc += JWMath.absi(f_primary_paid)
	acc += JWMath.absi(f_interest_paid)
	acc += JWMath.absi(f_principal_paid)
	acc += JWMath.absi(f_writeoffs)
	acc += JWMath.absi(f_pay_public_wages)
	acc += JWMath.absi(f_pay_procurement)
	acc += JWMath.absi(f_final_consumption)
	acc += JWMath.absi(f_gross_capital_formation)
	acc += JWMath.absi(f_procure_budget)
	acc += JWMath.absi(f_rollover)
	acc += JWMath.absi(f_money_issued)
	return acc

# ── 私有实现 ───────────────────────────────────────────────────────────────

## 分档累进税额：Σ_bracket mul_ppm(max(0, min(base, upper_b) − lower_b), rate_b_ppm)。
## 两档（docs/12 §6.5 与 policy_P01.json 的四个 player_param）：
##   (lower1, lower2] 适用 rate1；(lower2, +∞) 适用 rate2。
## rounding: floor, reason=docs/12 §6.5「少征优于多征」，逐档各取整一次。
func _bracket_tax(base: int, lower1: int, lower2: int, rate1: int, rate2: int) -> int:
	if base <= lower1:
		return 0
	var top1: int = base
	if top1 > lower2:
		top1 = lower2
	var band1: int = top1 - lower1
	var tax: int = 0
	if band1 > 0:
		tax = JWMath.mul_ppm(band1, rate1)
	if base > lower2:
		tax += JWMath.mul_ppm(base - lower2, rate2)
	return tax


## 批次是否还在「要付钱」的状态：已到期结清与已核销的批次不再计息也不再还本。
## 违约批次仍然欠着（它的未偿本金与已计未付利息都还在），所以算「live」。
func _bond_is_live(bonds: JWBondBook, b: int) -> bool:
	var st: int = bonds.status[b]
	if st == JWUnits.BondStatus.MATURED or st == JWUnits.BondStatus.WRITTEN_OFF:
		return false
	return true


## 债权人主体下标（docs/17 §2.3）。
func _holder_agent(holder: int) -> int:
	if holder == JWUnits.Holder.ROW:
		return JWIds.AGENT_ROW
	return JWIds.AGENT_INVPOOL


## 债权人现金科目下标。
func _holder_cash_account(holder: int) -> int:
	return JWIds.idx_account(_holder_agent(holder), JWIds.ACC_CASH)


## 发行与还本的四腿过账。
##
## 符号取 docs/10 §2.5 第 5 列的口径：**资产增 +、负债增 −**，四腿之和恒为 0，
## 逐主体之和也为 0（发债与还本都不改变任何一方的净值，只改变资产负债的构成）。
## 用两腿 post() 记这两类交易会把它们记成净值转移，INV-020 当场破。
## issue == true 表示发行（holder → gov），否则是还本（gov → holder）。
func _post_bond_legs(ledger: JWLedger, kind: int, holder: int, amount_uu: int,
		issue: bool, entity_ref: int) -> int:
	if amount_uu <= 0:
		return JWResult.OK
	if _legs_account.size() != BOND_LEG_N or _legs_delta.size() != BOND_LEG_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				_legs_account.size(), BOND_LEG_N)
	var holder_agent: int = _holder_agent(holder)
	var sign: int = 1 if issue else -1
	_legs_account[0] = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH)
	_legs_delta[0] = sign * amount_uu
	_legs_account[1] = JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_DEBT)
	_legs_delta[1] = -sign * amount_uu
	_legs_account[2] = JWIds.idx_account(holder_agent, JWIds.ACC_CASH)
	_legs_delta[2] = -sign * amount_uu
	_legs_account[3] = JWIds.idx_account(holder_agent, JWIds.ACC_BONDHOLD)
	_legs_delta[3] = sign * amount_uu
	return ledger.post_multi(kind, _legs_account, _legs_delta, 0,
			PRODUCT_NONE, CAUSE_RULE, entity_ref)


## 发行一个批次并过账（§2.6）。
func _issue_one(bonds: JWBondBook, ledger: JWLedger, entity_seq: int, q: int,
		principal_uu: int, coupon_ppm: int, maturity: int, holder: int) -> int:
	# R-BONDCAP-01：本季已有同债权人、同到期季、同票息的批次就并入它（面值相加、重算摊还表，
	# 不占新格、不消耗 entity_seq）；没有才新开一格。旧批次一概不并（INV-036「旧债不重定价」）。
	var b: int = bonds.merge_target(q, maturity, JWUnits.Amortization.LEVEL_PRINCIPAL, holder,
			coupon_ppm)
	if b >= 0:
		var rcm: int = bonds.merge_issue(b, q, principal_uu)
		if rcm != JWResult.OK:
			return rcm
	else:
		b = bonds.issue(entity_seq, q, principal_uu, coupon_ppm, maturity,
				JWUnits.Amortization.LEVEL_PRINCIPAL, holder)
		if b < 0:
			# 批次数超上限：报警并拒绝（docs/12 §2.4），不去合并任何旧批次。
			return JWResult.Reject.CREDIT_LIMIT
	var rc: int = _post_bond_legs(ledger, JWUnits.Kind.BOND_ISSUE, holder, principal_uu, true, b)
	if rc != JWResult.OK:
		return rc
	# 借款单独登记，**不进入收入构成，也不进入任何 GDP 口径**（INV-029）。
	f_new_borrowing = JWMath.check_amount(f_new_borrowing + principal_uu)
	last_issued_uu = JWMath.check_amount(last_issued_uu + principal_uu)
	return JWResult.OK


## 按已核准的两段额度发行（国内一段、外部一段，任一段为 0 则不发该段；每段或并入或新开一格）。
## 调用方必须已用 _quote_financing 报过价、并已核过两段能力与批次余位——本函数只动账。
func _issue_split(bonds: JWBondBook, world: JWWorldMarket, ledger: JWLedger, entity_seq: int,
		q: int, issue_domestic: int, issue_external: int, maturity: int) -> int:
	# 本季第一笔实际发行在此封存本季票息（R-BONDCAP-01「同季票息相同」）。
	_seal_quarter_price(q)
	if issue_external > 0:
		# 先占额度再发行：外部段已按 headroom 封顶，这一步不会再拒；
		# 万一拒了也没留下已过账却没占额度的批次。
		var rcu: int = world.use_external_credit(issue_external)
		if rcu != JWResult.OK:
			return rcu
	var n_before: int = bonds.count
	if issue_domestic > 0:
		var rc: int = _issue_one(bonds, ledger, entity_seq, q, issue_domestic, _q_coupon_dom,
				maturity, JWUnits.Holder.INVPOOL)
		if rc != JWResult.OK:
			return rc
	if issue_external > 0:
		# 每个**新开**的批次需要一个唯一 ID（INV-010）。序号按实际新开的批次依次取用：
		# 国内段没发、或并入了本季已有批次，都没有消耗序号，就轮到外部段用 entity_seq 本身。
		# 这样「调用方按批次数的实际增量推进 meta.entity_seq」与本函数的取号才严丝合缝，不会撞 ID。
		var seq_ext: int = entity_seq + (bonds.count - n_before)
		var rc2: int = _issue_one(bonds, ledger, seq_ext, q, issue_external, _q_coupon_ext,
				maturity, JWUnits.Holder.ROW)
		if rc2 != JWResult.OK:
			return rc2
	return JWResult.OK


## 一段发行的全部前置判据：命中本季可并入的批次（target ≥ 0）就核并入，否则核新开一格（含批次上限）。
## 不写任何字段；与 _issue_one 的「并入还是新开」取同一个 merge_target，两处不会分叉。
func _segment_precheck(bonds: JWBondBook, target: int, batch_cap: int, q: int, amount_uu: int,
		coupon_ppm: int, maturity: int, holder: int) -> int:
	if target >= 0:
		return bonds.can_merge(target, q, amount_uu)
	return bonds.can_issue(batch_cap, q, amount_uu, coupon_ppm, maturity,
			JWUnits.Amortization.LEVEL_PRINCIPAL, holder)


## 封存本季票息（R-BONDCAP-01）：本季第一笔实际发行时调用，以当次报价为本季利率；已封存则不动。
func _seal_quarter_price(q: int) -> void:
	if _px_armed and _px_q == q:
		return
	_px_coupon_dom = _q_coupon_dom
	_px_coupon_ext = _q_coupon_ext
	_px_q = q
	_px_armed = true


## 规则发行（issue_debt / issue_debt_up_to / 到期续发）的到期季。
## R-TENOR-01：期限取 param.rule_issue_tenor_q（按开局存量债的期限结构派生，32 季），摊还方式
## level_principal（还本沿期限摊平，不制造纯属实现选择的到期悬崖）。原先借用
## param.commitment_horizon_q（信任承诺窗口，16 季）：新债每年约一半本金落进四季窗口，
## 偿债率与票息自我强化，无命令基线利息十年翻倍。
func _new_issue_maturity(q: int, params: PackedInt64Array) -> int:
	var tenor: int = params[JWUnits.Param.RULE_ISSUE_TENOR_Q]
	if tenor < 1:
		tenor = 1
	if tenor >= JWBondBook.HORIZON_MAX:
		tenor = JWBondBook.HORIZON_MAX - 1
	return q + tenor


## 一次发行调用的报价：两段票息（docs/12 §2.6）与两段**本次可发**的剩余能力（INV-034），写进 _q_*。
##
## 国内段 —— 两个上限都按**本季累计**核：government_init.json `_note_gov` 写明 credit_limit_domestic
## 是「每季国内发行上限」，docs/10 §8.4 写明国内侧「每季重新求值」。R-FINANCE-01 之后一季内有多个
## 发行点（S02 付本息前、S04 每条支付线前、玩家命令），逐次各给满额就把「每季」换成了「每次」——
## ADV-C03 实测 q=0 向投资池新发 8.97 U，是 4 U 季度额度的两倍多。本季已发量由批次表推出
## （JWBondBook.issued_in_quarter），不另立「已用国内额度」存量字段（§8.4 不允许）：
##   额度余量 = credit_limit_domestic − 本季已向 invpool 发行的面值
##   认购余力 = mul_ppm(invpool.cash + 本季已认购, appetite) − 本季已认购
## 第二式是单一发行点时 `mul_ppm(invpool.cash, appetite)` 的逐次等价形：季内拆成几次发，合计仍是
## （季内流入之后的）投资池可支配现金的 appetite 份，不因拆分多认购；且恒不超过投资池现有现金。
##
## 外部段 —— credit_limit − credit_used（R-CREDIT-01 的增量额度，本身即累计口径），再以 agent.row 的
## **现有现金**封顶：额度是授信上限，不是对手方手里的钱。只看额度会让外部债权人付出它没有的现金，
## 过账时判 NEGATIVE_CASH，一次本该显露为欠付的融资短缺变成故障（实测：第 7 季再融资 6 U 到期外债时
## row 只有 3.97 U，全部空命令种子都在 S02 FAULT 20）。
##
## rounding: floor（mul_ppm），reason=少借优于多借——多出的 1 μU 没有对手方。
func _quote_financing(bonds: JWBondBook, world: JWWorldMarket, accounts: JWAccount, q: int,
		params: PackedInt64Array) -> int:
	# ── 定价（docs/12 §2.6）：玩家不能设利率，利率由 dsr 与外部冲击共同决定 ──
	if _px_armed and _px_q == q:
		# 本季已有实际发行：沿用本季封存的利率（R-BONDCAP-01「同季票息相同」）。季内新发会抬高
		# 未来四季偿债额，若逐次重算，同季各笔票息各不相同，同条件的发行就无法并入同一批次。
		_q_coupon_dom = _px_coupon_dom
		_q_coupon_ext = _px_coupon_ext
	else:
		# dsr_ppm = 未来 4 季（利息 + 本金） / 年化收入。分母用**上一季实收 × 4**：
		# 本季 S02 时本季税收还没发生（税在 S06），用本季的 0 当分母等于永远给最高档。
		var service4q: int = bonds.debt_service_next4q(q)
		var annual_income: int = _receipts_annualized
		if annual_income < 1:
			annual_income = 1
		var dsr_ppm: int = JWMath.mul_div_floor(service4q, JWUnits.PPM, annual_income)
		if dsr_ppm > DSR_CAP_PPM:
			dsr_ppm = DSR_CAP_PPM
		var market_base_ppm: int = params[JWUnits.Param.MARKET_RATE_BASE_PPM]
		var market_ppm: int = market_base_ppm \
				+ JWMath.mul_ppm(params[JWUnits.Param.MARKET_RATE_SLOPE_PPM], dsr_ppm)
		# 外部收紧冲击加成：S01 已把冲击落到 world.sovereign_rate_ppm_per_q
		# （== market_rate_base_ppm + mul_ppm(eff_ppm[S03], rate_sensitivity_ppm)，docs/12 §01.7），
		# 因此加成就是它高出基准利率的部分；不重新抽一次冲击，也不再乘一次敏感度。
		var external_add_ppm: int = world.sovereign_rate() - market_base_ppm
		if external_add_ppm < 0:
			external_add_ppm = 0
		var coupon_min: int = params[JWUnits.Param.COUPON_MIN_PPM]
		var coupon_max: int = params[JWUnits.Param.COUPON_MAX_PPM]
		if coupon_min > coupon_max:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, coupon_min, coupon_max)
		_q_coupon_dom = JWMath.clamp_i(market_ppm, coupon_min, coupon_max)
		_q_coupon_ext = JWMath.clamp_i(market_ppm + external_add_ppm, coupon_min, coupon_max)

	# ── 国内段（INV-034 前半）：本季累计 ──
	var dom_issued: int = bonds.issued_in_quarter(q, JWUnits.Holder.INVPOOL)
	var limit_left: int = credit_limit_domestic - dom_issued
	if limit_left < 0:
		limit_left = 0
	var pool_cash: int = accounts.cash_of(JWIds.AGENT_INVPOOL)
	if pool_cash < 0:
		pool_cash = 0
	var appetite_ppm: int = JWMath.clamp_i(params[JWUnits.Param.HOUSEHOLD_BOND_APPETITE_PPM],
			0, JWUnits.PPM)
	var pool_left: int = JWMath.mul_ppm(pool_cash + dom_issued, appetite_ppm) - dom_issued
	if pool_left > pool_cash:
		pool_left = pool_cash
	if pool_left < 0:
		pool_left = 0
	_q_cap_dom = limit_left
	if pool_left < _q_cap_dom:
		_q_cap_dom = pool_left

	# ── 外部段（INV-034 后半）：增量额度余量，且不超过对手方现有现金 ──
	var ext_cap: int = world.credit_headroom()
	var row_cash: int = accounts.cash_of(JWIds.AGENT_ROW)
	if row_cash < ext_cap:
		ext_cap = row_cash
	if ext_cap < 0:
		ext_cap = 0
	_q_cap_ext = ext_cap
	return JWResult.OK


## 武装 INV-028 的季初债务基准。基准由 JWBondBook 在本季第一次改账**之前**取定
## （debt_at_quarter_start）：S02 的命令——debt_restructure 的减记、issue_bond 的发行——
## 可能先于国库的任何入口改过批次表，国库「首次被调用时」再取就已经是改过的数。
func _arm_debt_baseline(bonds: JWBondBook, q: int) -> void:
	if _debt_baseline_q == q:
		return
	_debt_at_quarter_start = bonds.debt_at_quarter_start(q)
	_debt_baseline_q = q


## 各档清单长度的前置检查。
##
## 逐档的流量落点是「按域下标」的稠密数组（转移 → 群组、补助 → cell、运行费 → 地区×服务），
## 而 pay_line 只拿得到收款方主体下标。约定：**清单下标即该档的域下标**，长度必须等于域长度。
## 长度不符时不能「先付了再说、流量写不进去就算了」——那就是静默丢账。
func _check_line_arity(line: int, n: int) -> int:
	if line == JWUnits.PayLine.STATUTORY_TRANSFERS:
		if n != JWUnits.GROUP:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, n, JWUnits.GROUP)
		return JWResult.OK
	if line == JWUnits.PayLine.SUBSIDIES:
		if n != JWUnits.CELL:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, n, JWUnits.CELL)
		return JWResult.OK
	if line == JWUnits.PayLine.SERVICE_OPEX:
		if n != JWUnits.OPEX_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, n, JWUnits.OPEX_N)
		return JWResult.OK
	# public_wages / project_contracts / procurement / discretionary 的清单是「逐行」的
	# （一行一个收款方，行数由上游决定），它们的流量落点要么是标量，要么按实体下标由
	# record_line_payment 登记，因此不约束长度。
	return JWResult.OK


## 把一笔实付额登记到该档的流量落点。entity_idx 的含义随档位而定（见 _check_line_arity）。
func _record_line_flow(line: int, entity_idx: int, amount_uu: int) -> int:
	if line == JWUnits.PayLine.PUBLIC_WAGES:
		f_pay_public_wages = JWMath.check_amount(f_pay_public_wages + amount_uu)
		return JWResult.OK
	if line == JWUnits.PayLine.STATUTORY_TRANSFERS:
		if entity_idx < 0 or entity_idx >= f_pay_transfers.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					entity_idx, f_pay_transfers.size())
		f_pay_transfers[entity_idx] = f_pay_transfers[entity_idx] + amount_uu
		return JWResult.OK
	if line == JWUnits.PayLine.SERVICE_OPEX:
		if entity_idx < 0 or entity_idx >= f_pay_opex.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					entity_idx, f_pay_opex.size())
		f_pay_opex[entity_idx] = f_pay_opex[entity_idx] + amount_uu
		return JWResult.OK
	if line == JWUnits.PayLine.PROJECT_CONTRACTS:
		if entity_idx < 0 or entity_idx >= f_pay_project.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					entity_idx, f_pay_project.size())
		f_pay_project[entity_idx] = f_pay_project[entity_idx] + amount_uu
		return JWResult.OK
	if line == JWUnits.PayLine.SUBSIDIES:
		if entity_idx < 0 or entity_idx >= f_pay_subsidies.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					entity_idx, f_pay_subsidies.size())
		f_pay_subsidies[entity_idx] = f_pay_subsidies[entity_idx] + amount_uu
		return JWResult.OK
	if line == JWUnits.PayLine.PROCUREMENT:
		f_pay_procurement = JWMath.check_amount(f_pay_procurement + amount_uu)
		return JWResult.OK
	# discretionary 没有分项流量落点，只进 primary_paid。
	return JWResult.OK


## 「按收款方 ID 升序」的下标排序（插入排序，n <= 256，不新建对象）。
##
## 为什么要排：过账顺序决定 txn_seq，而 txn_seq 是状态。清单的行序由上游决定
## （项目按 spend_line、公共工资按地区×技能），不排序就等于把重放一致性交给上游的实现细节。
func _sort_payees(payee_agent: PackedInt64Array, n: int) -> void:
	if _pay_order.size() < n:
		_pay_order.resize(n)
	var i: int = 0
	while i < n:
		_pay_order[i] = i
		i += 1
	var s: int = 1
	while s < n:
		var key: int = _pay_order[s]
		var kv: int = payee_agent[key]
		var j: int = s - 1
		while j >= 0 and payee_agent[_pay_order[j]] > kv:
			_pay_order[j + 1] = _pay_order[j]
			j -= 1
		_pay_order[j + 1] = key
		s += 1


## payment_priority 是否为 8 档的全排列（INV-039）。
func _is_pay_line_permutation(v: PackedInt64Array) -> bool:
	var seen: int = 0
	var i: int = 0
	while i < v.size():
		var x: int = v[i]
		if x < 0 or x >= JWUnits.PAY_LINE_N:
			return false
		var bit: int = 1 << x
		if (seen & bit) != 0:
			return false
		seen |= bit
		i += 1
	return seen == (1 << JWUnits.PAY_LINE_N) - 1


## 追加一行 log.arrears；写满时按 1.5 倍扩容并写一条告警行（docs/17 §1.7）。
func _arrears_log_append(payee: int, amount_uu: int, reason_line: int) -> void:
	var cap: int = a_payee.size()
	if _log_n >= cap:
		var grown: int = JWMath.floor_div(JWMath.mul(cap, LOG_GROW_NUM), LOG_GROW_DEN)
		if grown <= cap:
			grown = cap + 1
		a_payee.resize(grown)
		a_amount.resize(grown)
		a_reason.resize(grown)
		a_step.resize(grown)
		# 告警行：容量被动过这件事本身要留痕，否则「日志为什么变长了」无从追溯。
		a_payee[_log_n] = LOG_MARK_NONE
		a_amount[_log_n] = cap
		a_reason[_log_n] = LOG_MARK_NONE
		a_step[_log_n] = _log_step
		_log_n += 1
	if _log_n >= a_payee.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, _log_n, a_payee.size())
		return
	a_payee[_log_n] = payee
	a_amount[_log_n] = amount_uu
	a_reason[_log_n] = reason_line
	a_step[_log_n] = _log_step
	_log_n += 1


## §1.6 状态块协议：读档时写回流量数组（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_array 逐项对称生成）。
## 步骤：LOAD（JWSaves 经 JWSimState 调用）
## 前置：v 的长度与本块当前分配的长度一致（长度是 schema 的一部分，INV-136）
## 后置：对应成员被整体替换
## 不变量：INV-133（读档后与原进程逐位相同）
## 失败：下标越界或长度不符 → INDEX_OUT_OF_RANGE
func set_flow_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != f_pay_transfers.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_pay_transfers = v.duplicate()
		return JWResult.OK
	if i == 1:
		if v.size() != f_pay_subsidies.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_pay_subsidies = v.duplicate()
		return JWResult.OK
	if i == 2:
		if v.size() != f_pay_project.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_pay_project = v.duplicate()
		return JWResult.OK
	if i == 3:
		if v.size() != f_pay_opex.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_pay_opex = v.duplicate()
		return JWResult.OK
	if i == 4:
		if v.size() != f_arrears_added.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_arrears_added = v.duplicate()
		return JWResult.OK
	if i == 5:
		if v.size() != f_arrears_cleared.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_arrears_cleared = v.duplicate()
		return JWResult.OK
	if i == 6:
		if v.size() != f_nonmarket_output.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_nonmarket_output = v.duplicate()
		return JWResult.OK
	if i == 7:
		if v.size() != f_arrears_written_off.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		f_arrears_written_off = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())


## §1.6 状态块协议：读档时写回流量标量（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_scalar 逐项对称生成）。
## 步骤：LOAD
## 前置：无
## 后置：对应成员被赋值
## 不变量：INV-133
## 失败：下标越界 → INDEX_OUT_OF_RANGE
func set_flow_scalar(i: int, v: int) -> int:
	if i == 0:
		f_receipts_income_tax = v
		return JWResult.OK
	if i == 1:
		f_receipts_profit_tax = v
		return JWResult.OK
	if i == 2:
		f_receipts_other = v
		return JWResult.OK
	if i == 3:
		f_new_borrowing = v
		return JWResult.OK
	if i == 4:
		f_primary_paid = v
		return JWResult.OK
	if i == 5:
		f_interest_paid = v
		return JWResult.OK
	if i == 6:
		f_principal_paid = v
		return JWResult.OK
	if i == 7:
		f_writeoffs = v
		return JWResult.OK
	if i == 8:
		f_pay_public_wages = v
		return JWResult.OK
	if i == 9:
		f_pay_procurement = v
		return JWResult.OK
	if i == 10:
		f_final_consumption = v
		return JWResult.OK
	if i == 11:
		f_gross_capital_formation = v
		return JWResult.OK
	if i == 12:
		f_procure_budget = v
		return JWResult.OK
	if i == 13:
		f_rollover = v
		return JWResult.OK
	if i == 14:
		f_money_issued = v
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
