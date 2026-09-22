class_name JWBondBook
extends RefCounted

## 债券批次 SoA（docs/10 §3.3）。**只增不删**：结清批次改状态位，下标永久稳定。
## **逐批次计息**，禁止「求和后乘平均利率」（INV-036）。
## 容量 JWUnits.BOND_CAP0，实际长度 count。

## §1.6 状态块协议：本块各数组所属子系统（与 STATE_ARRAY_IDS 等长）。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_BOND, JWUnits.SUBSYS_BOND, JWUnits.SUBSYS_BOND, JWUnits.SUBSYS_BOND,
	JWUnits.SUBSYS_BOND, JWUnits.SUBSYS_BOND, JWUnits.SUBSYS_BOND, JWUnits.SUBSYS_BOND,
	JWUnits.SUBSYS_BOND, JWUnits.SUBSYS_BOND, JWUnits.SUBSYS_BOND, JWUnits.SUBSYS_BOND,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
## SoA 的 ids[] 在存档中单列（docs/11 §6.4 的 "soa" 段），因此不出现在本表里。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.bond.issue_q",
	"state.bond.principal_initial_uu",
	"state.bond.principal_outstanding_uu",
	"state.bond.coupon_ppm_per_q",
	"state.bond.maturity_q",
	"state.bond.amortization",
	"state.bond.holder",
	"state.bond.status",
	"state.bond.accrued_unpaid_interest_uu",
	"state.bond.interest_remainder_ppmuu",
	"state.bond.writeoff_uu",
	"state.bond.amort_schedule",
]
const STATE_SCALAR_IDS: PackedStringArray = ["state.bond.count"]
const FLOW_ARRAY_IDS: PackedStringArray = [
	"flow.bond.interest_due_uu",
	"flow.bond.principal_due_uu",
]
const FLOW_SCALAR_IDS: PackedStringArray = []

## 每个批次的分期表槽位数。下标 `batch * HORIZON_MAX + k`，其中 **k 是相对期数 `q − issue_q`**
## （docs/17 §4.11 的表格写作 `batch*HORIZON_MAX + q`）。取相对期数的理由有二，都是硬事实：
## ① 开局存量债的 `issue_q` 为负（剧本里到 −20），绝对季做下标会落到负数；
## ② 绝对季没有上界（压力测试 horizon_q == 120，再加 tenor 就越过任何固定表长），
##    而相对期数的上界就是 tenor，由 ADV-C07 的 `valid_range` 锁在 [4, 40]。
## 64 == 40（tenor 上限）+ 24（重组延期的余量）；k ∈ [1, HORIZON_MAX)，k == 0 永不使用
## （分期从 issue_q+1 开始，当季发当季还是 ADV-C07 明令拒绝的形态）。
const HORIZON_MAX: int = 64

## 分期表总长度（= BOND_CAP0 * HORIZON_MAX），set_state_array 的契约长度。
const AMORT_LEN: int = JWUnits.BOND_CAP0 * HORIZON_MAX

## 票息率上界（docs/10 §3.3 的区间 0..100 000 ppm/季，V-FIN-07）。
const COUPON_PPM_MAX: int = 100_000

## 重组模式（docs/11 §6.1 命令 9 的 `mode` 字段：defer / writedown / default）。
## 首版契约只给了这三个名字，没有给数值码；此处定义即本项目的唯一数值码，
## 由 systems/commands.gd 在校验期把字符串映射到本枚举。
enum RestructureMode { DEFER = 0, WRITEDOWN = 1, DEFAULT = 2 }

## state.bond.id[] —— `bond.q<qqq>_<nn>`，写入者 LOAD, S02。存档中单列（docs/11 §6.4 "soa" 段）
var id: PackedStringArray = PackedStringArray()

## state.bond.issue_q[] —— 季（开局存量债为负），写入者 LOAD, S02
var issue_q: PackedInt64Array = PackedInt64Array()

## state.bond.principal_initial_uu[] —— μU，写入者 LOAD, S02
var principal_initial: PackedInt64Array = PackedInt64Array()

## state.bond.principal_outstanding_uu[] —— μU，写入者 S02
var principal_outstanding: PackedInt64Array = PackedInt64Array()

## state.bond.coupon_ppm_per_q[] —— ppm/季，**仅发行时**写入（INV-036：旧债不重定价）
var coupon_ppm: PackedInt64Array = PackedInt64Array()

## state.bond.maturity_q[] —— 季，写入者 LOAD, S02
var maturity_q: PackedInt64Array = PackedInt64Array()

## state.bond.amortization[] —— JWUnits.Amortization，写入者 LOAD, S02
var amortization: PackedInt64Array = PackedInt64Array()

## state.bond.holder[] —— JWUnits.Holder，写入者 LOAD, S02
var holder: PackedInt64Array = PackedInt64Array()

## state.bond.status[] —— JWUnits.BondStatus，初值 ACTIVE，写入者 S02
var status: PackedInt64Array = PackedInt64Array()

## state.bond.accrued_unpaid_interest_uu[] —— μU，初值 0，写入者 S02
var accrued_unpaid: PackedInt64Array = PackedInt64Array()

## state.bond.interest_remainder_ppmuu[] —— μU·ppm，0..999 999，初值 0，写入者 S02
var interest_remainder: PackedInt64Array = PackedInt64Array()

## state.bond.writeoff_uu[] —— μU，初值 0，写入者 S02
var writeoff: PackedInt64Array = PackedInt64Array()

## state.bond.amort_schedule[] —— μU，按 `batch * HORIZON_MAX + q` 稀疏存，发行时预生成
var amort_schedule: PackedInt64Array = PackedInt64Array()

## flow.bond.interest_due_uu[] —— μU，初值 0，写入者 S02
var interest_due: PackedInt64Array = PackedInt64Array()

## flow.bond.principal_due_uu[] —— μU，初值 0，写入者 S02
var principal_due: PackedInt64Array = PackedInt64Array()

## 批次数，初值 0，写入者 LOAD, S02
var count: int = 0

## 最近一次 restructure() 确认减记的**本金**（μU），供调用方 post(kind=WRITEOFF) 并计入
## flow.gov.recognized_writeoffs_uu。它恰等于该次重组使 Σ principal_outstanding 减少的量——
## INV-028（debt_end == debt_start + 借款 − 还本 − 确认减记）里的「确认减记」只能是这个数，
## 债权人的持债腿（bondhold，面值口径）与政府的 debt 腿也只能按它冲减（INV-025）。
## 只读输出口：每次 restructure() 入口清零，不跨调用累积；不进 state_hash（它是返回值的延长线）。
var last_writeoff_uu: int = 0

## 最近一次 restructure() 从该批次 accrued_unpaid 中移出的「已计未付」额（μU）：
## 减记 / 违约 —— accrued_unpaid 的全部余额（违约时登记的未付利息，加上 docs/12 §2.5「本金未付 → 同上」
## 登记的未付本金），随批次一并了结；延期 —— 顺延回分期表的逾期本金（未付利息照旧挂着）。
## 它**不是**债务余额的一部分（未付本金仍在 principal_outstanding 里，由 last_writeoff_uu 计量），
## 所以既不进 last_writeoff_uu 也不进 recognized_writeoffs；调用方据此经 JWTreasury.write_off_arrears
## 注销 gov.arrears 里对该债权人的同额欠付备查（第三轮裁定：INV-030 的「核销」项）。
## 只读输出口：每次 restructure() 入口清零；不进 state_hash。
var last_writeoff_arrears_uu: int = 0

# ── 私有缓冲（不进状态块协议、不进 state_hash） ─────────────────────────────

## INV-028 的季初债务基准：本季**第一次改动债券簿之前**的未偿本金合计。
## 由每个带季号的改账入口（accrue_interest / schedule_principal / issue / restructure）
## 在写第一个字段之前武装一次；JWTreasury 的终检经 debt_at_quarter_start() 取它。
## 为什么在本类武装而不是等国库首次被调用：S02 的命令（debt_restructure 的减记、issue_bond 的发行）
## 先于国库的任何入口改账，国库那时再取的「期初」已经是改过的数，INV-028 会拿一个
## 少了本季减记的期初去对账，把一笔合法的重组报成 BOND_MISMATCH。
## 载入（set_state_*）与 allocate 之后撤销武装：旧基准对新状态没有意义。
var _base_armed: bool = false
var _base_q: int = 0
var _base_debt: int = 0

## 发行时封存的票息率副本。INV-036 的检查手段：coupon_ppm 一旦与它不符，
## 说明有人在发行之后改写了票息（旧债被重定价），accrue_interest 立即 BOND_MISMATCH。
## 由 allocate / issue / set_state_array(3) 三处同步，别处只读。
var _coupon_seal: PackedInt64Array = PackedInt64Array()

## split_lr_into 的三条预分配缓冲（等权重、决胜键、结果），长度按需 resize 到期数 n。
## 预分配的理由：发行在 S02 热路径上，禁止新建对象（docs/17 §1.4）。
var _sched_w: PackedInt64Array = PackedInt64Array()
var _sched_tb: PackedInt64Array = PackedInt64Array()
var _sched_out: PackedInt64Array = PackedInt64Array()


## 逐批次计提本季应付利息，余数进累加器满 1e6 结转 1 μU。
## 步骤：S02 §2.3
## 前置：status == ACTIVE 且 principal_outstanding > 0；coupon_ppm 发行后未被改写
## 后置：flow.bond.interest_due_uu 被填满；interest_remainder ∈ [0, 999_999]
## 不变量：INV-036（逐批次 floor 计提）、INV-004（余数累加器）、INV-041（120 季漂移 ≤ 1 μU/批次）
## 失败：coupon_ppm 被改写过 → Fault.BOND_MISMATCH；不产生业务失败（计提不需要现金）
func accrue_interest(q: int) -> int:
	# 票息按存量计提，与绝对季无关（利率固定，不重定价）；q 只用来武装本季的 INV-028 基准。
	_arm_quarter_baseline(q)
	var rc: int = JWResult.OK
	var b: int = 0
	while b < count:
		var due: int = 0
		var cp: int = coupon_ppm[b]
		# INV-036 的封印检查：票息在发行后被改写即 FAULT，不是「以新值继续算」。
		if cp != _coupon_seal[b]:
			rc = JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, b, cp)
		else:
			var out_uu: int = principal_outstanding[b]
			if status[b] == JWUnits.BondStatus.ACTIVE and out_uu > 0 and cp > 0:
				# rounding: floor, reason=docs/12 §2.3「少付优于多付」；
				# 新刻度下 out_uu * cp 真的溢出 int64，必须走 mul_div_floor（裁定 R-SCALE-01）。
				due = JWMath.mul_div_floor(out_uu, cp, JWUnits.PPM)
				# 余数 = (out_uu * cp) mod PPM，同样不能先乘：
				# (out_uu mod PPM) * cp <= 1e6 * 1e5 = 1e11，安全。
				var lo: int = out_uu - JWMath.mul(JWMath.floor_div(out_uu, JWUnits.PPM), JWUnits.PPM)
				var t: int = JWMath.mul(lo, cp)
				var rem: int = t - JWMath.mul(JWMath.floor_div(t, JWUnits.PPM), JWUnits.PPM)
				var acc: int = interest_remainder[b] + rem
				# acc < 2e6：入口 acc <= 999 999，rem <= 999 999，故至多进一位。
				if acc >= JWUnits.PPM:
					due += 1
					acc -= JWUnits.PPM
				if acc < 0 or acc >= JWUnits.PPM:
					# 累加器越界说明存档里的余数本来就非法，不允许带病继续计息。
					rc = JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, b, acc)
					acc = 0
				interest_remainder[b] = acc
				JWMath.check_amount(due)
		interest_due[b] = due
		b += 1
	return rc


## 计算本季应还本金：bullet 到期一次还清；level_principal 查预生成的分期表。
## 步骤：S02 §2.4
## 前置：amort_schedule 在发行时已由 split_lr 预生成，Σ == 面值
## 后置：flow.bond.principal_due_uu 被填满
## 不变量：INV-037（Σ_{q'>=q} scheduled == outstanding）
## 失败：分期表和不等于面值 → Fault.BOND_MISMATCH
func schedule_principal(q: int) -> int:
	_arm_quarter_baseline(q)
	var rc: int = JWResult.OK
	var b: int = 0
	while b < count:
		var due: int = 0
		var out_uu: int = principal_outstanding[b]
		var st: int = status[b]
		# MATURED / WRITTEN_OFF 的未偿本金恒为 0，没有任何待还项；其余状态仍欠本金
		# （DEFAULTED 的批次照样到期，欠付只改支付结果，不改合同）。
		if out_uu > 0 and st != JWUnits.BondStatus.MATURED \
				and st != JWUnits.BondStatus.WRITTEN_OFF:
			if amortization[b] == JWUnits.Amortization.BULLET:
				if q == maturity_q[b]:
					due = out_uu
			else:
				due = _sched_at(b, q)
				# INV-037：剩余计划（含本季）不得超过未偿本金。少于是合法的——那正是
				# 前季欠付留下的逾期额，由 restructure() 显式处理；多于则是分期表算错了。
				var plan_from_q: int = _scheduled_from(b, q)
				if plan_from_q > out_uu:
					rc = JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, b, plan_from_q)
					due = 0
				elif due > out_uu:
					rc = JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, b, due)
					due = 0
		principal_due[b] = due
		b += 1
	return rc


## 预检一次发行会不会被 issue() 拒掉，**不写任何字段**。
## 步骤：S02 §2.6
## 前置：无
## 后置：不改状态（批次表已满这一路连故障都不登记——那是业务性拒绝，不是故障）
## 不变量：INV-034（docs/30 `T-S-D-11`：被拒的发行 `gov.debt_uu` 增量 == 0、state_hash 逐位不变，
##          因此调用方必须在**动任何账之前**问清楚，而不是发了一半再回滚）
## 失败：批次表已满（count + 1 > batch_cap）→ Reject.CREDIT_LIMIT；
##       参数越界 → 与 issue() 同码的 Fault（故障按 docs/12 §9 照常登记，不回滚）
##
## batch_cap 由调用方给（param.bond_batch_cap，docs/12 §2.4），本类内部另有 BOND_CAP0 的硬边界；
## 两者取严。**不合并旧批次**（那会破坏 INV-036 的「旧债不重定价」）；裁定 R-BONDCAP-01 允许的
## 「同季、同债权人、同到期季、同票息」并入走 merge_target / can_merge / merge_issue，不占新格。
func can_issue(batch_cap: int, q: int, principal_uu: int, coupon_ppm_per_q: int,
		maturity_q_in: int, amortization_in: int, holder_in: int) -> int:
	var cap: int = batch_cap
	if cap > JWUnits.BOND_CAP0:
		cap = JWUnits.BOND_CAP0
	return _issue_guard(cap, q, principal_uu, coupon_ppm_per_q,
			maturity_q_in, amortization_in, holder_in, false)


## 发行一个新批次（票息由规则给出，玩家不能设）。
## 步骤：S02 §2.6
## 前置：coupon_ppm >= market_rate_ppm(q)；holder 额度已由调用方（JWTreasury）核过；
##       count < params[BOND_BATCH_CAP]（调用方先用 can_issue 问过）
## 后置：新批次写入 SoA 末尾；amort_schedule 预生成；调用方负责 post(kind=BOND_ISSUE)
## 不变量：INV-034（融资不超对手方能力）、INV-037、INV-038（不允许自动展期）、INV-010（ID 来自 entity_seq）
## 失败：超批次上限 → 返回 -1 并由调用方 REJECT(Reject.CREDIT_LIMIT)；
##       本函数**总是新开一格**、从不合并；R-BONDCAP-01 的同季同条件并入由调用方先问 merge_target，
##       命中则改走 merge_issue（旧批次一概不并：合并旧债会破坏 INV-036 的「旧债不重定价」）
func issue(entity_seq: int, q: int, principal_uu: int, coupon_ppm_per_q: int,
		maturity_q_in: int, amortization_in: int, holder_in: int) -> int:
	# 全部前置检查在这里一次做完（与 can_issue 共用同一份判据，二者不得漂移）：
	# 本函数从下一行起就开始写 SoA，所以「能不能发」必须在写第一个字段之前有答案。
	if _issue_guard(JWUnits.BOND_CAP0, q, principal_uu, coupon_ppm_per_q,
			maturity_q_in, amortization_in, holder_in, true) != JWResult.OK:
		return -1

	# 写第一个字段之前武装本季 INV-028 基准（本季已武装则不动）。
	_arm_quarter_baseline(q)
	var b: int = count
	issue_q[b] = q
	principal_initial[b] = principal_uu
	principal_outstanding[b] = principal_uu
	coupon_ppm[b] = coupon_ppm_per_q
	_coupon_seal[b] = coupon_ppm_per_q
	maturity_q[b] = maturity_q_in
	amortization[b] = amortization_in
	holder[b] = holder_in
	status[b] = JWUnits.BondStatus.ACTIVE
	accrued_unpaid[b] = 0
	interest_remainder[b] = 0
	writeoff[b] = 0
	interest_due[b] = 0
	principal_due[b] = 0

	var base: int = JWMath.mul(b, HORIZON_MAX)
	var k: int = 0
	while k < HORIZON_MAX:
		amort_schedule[base + k] = 0
		k += 1
	if amortization_in == JWUnits.Amortization.LEVEL_PRINCIPAL:
		# 分期表覆盖 issue_q+1 … maturity_q，等权重最大余数法，Σ 精确等于面值（INV-037）。
		# tenor ∈ [1, HORIZON_MAX) 由 _issue_guard 已核过。
		if _fill_level_schedule(b, principal_uu, maturity_q_in - q) != JWResult.OK:
			return -1

	# INV-010：运行期 ID 只来自单调计数器 entity_seq，禁止时间戳 / 指针 / 哈希。
	if id.size() < JWUnits.BOND_CAP0:
		id.resize(JWUnits.BOND_CAP0)
	id[b] = "bond.q" + _q_tag(q) + "_" + _pad(entity_seq, 2)

	count = b + 1
	return b


## 裁定 R-BONDCAP-01：本季可并入的批次下标（没有则返回 −1），**不写任何字段**。
## 步骤：S02 §2.6、S04（R-FINANCE-01 的付款前融资）
## 前置：无
## 后置：不改状态
## 不变量：INV-036（只认票息与发行封印都等于 coupon 的批次——并入不给任何一笔债重定价）、
##          INV-037（只认本季新发、一分本金都还没还过的批次——重算摊还表不改动任何已发生的现金流）
## 失败：无
##
## 可并入 ⇔ 同发行季、同债权人、同到期季、同摊还方式、同票息，且批次仍是刚发出的原样：
## ACTIVE、未偿 == 面值、无减记、无已计未付。分期表第一期在 issue_q + 1，发行季内不会有任何还本，
## 满足前五项的批次必然满足后几项；后几项是防御性核对，不构成业务分支。
## 批次表只增不删：本季批次都在表尾，但开局存量与夹具的发行季次序不作保证，因此整表倒序扫描。
func merge_target(q: int, maturity_q_in: int, amortization_in: int, holder_in: int,
		coupon_ppm_per_q: int) -> int:
	var b: int = count - 1
	while b >= 0:
		if issue_q[b] == q and holder[b] == holder_in and maturity_q[b] == maturity_q_in \
				and amortization[b] == amortization_in and coupon_ppm[b] == coupon_ppm_per_q \
				and _merge_guard(b, q, 1, false) == JWResult.OK:
			return b
		b -= 1
	return -1


## 预检一次并入会不会被 merge_issue() 拒掉，**不写任何字段**（与 merge_issue 共用同一份判据）。
## 步骤：S02 §2.6、S04
## 前置：无
## 后置：不改状态
## 不变量：INV-034 的全有全无（调用方在动账之前问清楚）
## 失败：判据不满足 → 与 merge_issue 同码（不登记故障）
func can_merge(b: int, q: int, principal_uu: int) -> int:
	return _merge_guard(b, q, principal_uu, false)


## 裁定 R-BONDCAP-01：把一笔同条件的新发行并入本季已有批次——面值相加，按等额本金重算摊还表。
## 步骤：S02 §2.6、S04
## 前置：b 是 merge_target(q, …) 的返回值；principal_uu > 0；并入后面值 ≤ AMOUNT_MAX
## 后置：principal_initial 与 principal_outstanding 同增 principal_uu；level_principal 的分期表按新面值、
##       原期数（issue_q+1 … maturity_q）重新生成，Σ == 新面值（INV-037）；
##       票息、封印、到期季、债权人、ID 一字不改（INV-036、INV-010：并入不消耗 entity_seq）；
##       调用方负责 post(kind=BOND_ISSUE) 与登记新增借款
## 不变量：INV-028（debt 增量 == 并入面值）、INV-036、INV-037
## 失败：判据不满足 → Fault.BOND_MISMATCH / INT_OVERFLOW / INDEX_OUT_OF_RANGE，不写任何字段
func merge_issue(b: int, q: int, principal_uu: int) -> int:
	var rc: int = _merge_guard(b, q, principal_uu, true)
	if rc != JWResult.OK:
		return rc
	# 写第一个字段之前武装本季 INV-028 基准（本季已武装则不动）。
	_arm_quarter_baseline(q)
	var total: int = principal_initial[b] + principal_uu
	principal_initial[b] = total
	principal_outstanding[b] = total
	if amortization[b] == JWUnits.Amortization.LEVEL_PRINCIPAL:
		# 发行季内尚无任何一期到期，整张表按新面值重生成等价于「合并后重算等额本金摊还表」。
		var base: int = JWMath.mul(b, HORIZON_MAX)
		var k: int = 0
		while k < HORIZON_MAX:
			amort_schedule[base + k] = 0
			k += 1
		var rc_s: int = _fill_level_schedule(b, total, maturity_q[b] - issue_q[b])
		if rc_s != JWResult.OK:
			return rc_s
	return JWResult.OK


## 登记一次还本（由 JWTreasury 在 post 成功后调用）。
## 步骤：S02 §2.5
## 前置：amount <= principal_outstanding[b]
## 后置：principal_outstanding 减少；归 0 则 status = MATURED
## 不变量：INV-028, INV-035
## 失败：超额 → Fault.BOND_MISMATCH
func apply_principal_payment(b: int, amount_uu: int) -> int:
	if b < 0 or b >= count:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, b, count)
	if amount_uu < 0:
		return JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, b, amount_uu)
	var out_uu: int = principal_outstanding[b]
	if amount_uu > out_uu:
		# 超额还本会把未偿本金打成负数，等于凭空消灭负债；不截断、不静默改账。
		return JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, b, amount_uu - out_uu)
	out_uu -= amount_uu
	principal_outstanding[b] = out_uu
	if out_uu == 0 and status[b] != JWUnits.BondStatus.WRITTEN_OFF:
		status[b] = JWUnits.BondStatus.MATURED
	return JWResult.OK


## 登记一次利息欠付（违约）。
## 步骤：S02 §2.5
## 前置：本季该批次的 interest_due 未足额支付
## 后置：accrued_unpaid += 未付额；status = DEFAULTED
## 不变量：INV-030（欠付登记）、INV-038/INV-040（不得自动展期）
## 失败：不失败——这是业务性短缺（ARREARS 语义）
func register_interest_arrears(b: int, unpaid_uu: int) -> int:
	if b < 0 or b >= count:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, b, count)
	if unpaid_uu <= 0:
		# 0 不是欠付：不改状态位，免得把「全额付清」记成违约。
		return JWResult.OK
	var acc: int = accrued_unpaid[b] + unpaid_uu
	JWMath.check_amount(acc)
	accrued_unpaid[b] = acc
	# 已减记 / 已清偿的批次不再回到 DEFAULTED：那会让状态位来回跳，破坏重组分支的可判定性。
	if status[b] == JWUnits.BondStatus.ACTIVE:
		status[b] = JWUnits.BondStatus.DEFAULTED
	return JWResult.OK


## 重组（延期 / 减记 / 违约），只能由玩家命令 debt_restructure 触发。
## 步骤：S02（受理命令后）
## 前置：mode ∈ {defer, writedown, default}；必须登记债权人损失
## 后置：writeoff 增加、status = RESTRUCTURED/WRITTEN_OFF；调用方按 last_writeoff_uu post(kind=WRITEOFF)，
##       并按 last_writeoff_arrears_uu 注销对该债权人的欠付备查
## 不变量：INV-028（debt_end == start + 借款 − 还本 − 确认减记）、INV-025（Σ bondhold == debt）
## 失败：模式非法 → Reject.NOT_FOUND；**不允许静默展期**
##
## 三种模式的额度都由合同本身推出，没有任何新参数（契约没给数值，发明一个就是发明经济规则）：
##   defer     —— 把**逾期本金**顺延一季（分期表挪到 q+1，必要时 maturity_q 顺延），损失 0；
##                顺延的本金同时移出 accrued_unpaid（last_writeoff_arrears_uu 报出同额），不在欠付里重复挂账；
##   writedown —— 把**逾期本金**减记（确认减记 == 本金减少量），未逾期部分按原条款继续；
##   default   —— 把**全部未偿本金**减记，批次终结。
## 后两种同时了结该批次的全部已计未付（accrued_unpaid）：它记的是违约时的未付利息与未付本金
## （docs/12 §2.5「同上」），**不是**债务余额——未付本金本来就还在 outstanding 里，由减记计量一次；
## 若再把 accrued_unpaid 加进确认减记，未付本金会被减两次，INV-028 与 INV-025 当场各差一截。
## 逾期本金 == outstanding − Σ_{q' >= q} scheduled，正是 INV-037 的残差，不需要额外记账。
## 三种模式都要求该批次确有逾期或欠息，否则 REJECT(PRECONDITION)：
## 「没违约也能延期」就是 ADV-02 的无成本借新还旧。
func restructure(b: int, mode: int, q: int) -> int:
	last_writeoff_uu = 0
	last_writeoff_arrears_uu = 0
	if b < 0 or b >= count:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, b, count)
	if mode != RestructureMode.DEFER and mode != RestructureMode.WRITEDOWN \
			and mode != RestructureMode.DEFAULT:
		return JWResult.Reject.NOT_FOUND
	var st: int = status[b]
	if st == JWUnits.BondStatus.MATURED or st == JWUnits.BondStatus.WRITTEN_OFF:
		# 已结清 / 已核销的批次没有可重组的债权债务。
		return JWResult.Reject.NOT_FOUND
	var out_uu: int = principal_outstanding[b]
	var overdue: int = _overdue_principal(b, q)
	var unpaid_int: int = accrued_unpaid[b]
	if overdue <= 0 and unpaid_int <= 0:
		return JWResult.Reject.PRECONDITION

	# 过了全部拒绝判据才武装本季 INV-028 基准：下面开始写字段。
	_arm_quarter_baseline(q)
	if mode == RestructureMode.DEFER:
		# 顺延一季：期限是模型的最小时间粒度，不是凭空取的「延 N 年」。
		# 玩家要延更久，必须逐季重新提交命令，每次都在报告里留痕（INV-038 不得自动展期）。
		var target_q: int = q + 1
		if amortization[b] == JWUnits.Amortization.BULLET:
			if maturity_q[b] < target_q:
				maturity_q[b] = target_q
		else:
			var k: int = target_q - issue_q[b]
			if k < 1 or k >= HORIZON_MAX:
				return JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, b, k)
			if overdue > 0:
				var base: int = JWMath.mul(b, HORIZON_MAX)
				amort_schedule[base + k] = amort_schedule[base + k] + overdue
			if maturity_q[b] < target_q:
				maturity_q[b] = target_q
		status[b] = JWUnits.BondStatus.RESTRUCTURED
		# 第三轮裁定（重组核销欠付）：顺延的逾期本金回到了分期表，就不再是「已计未付」——
		# 从 accrued_unpaid 里拿掉同额，并经 last_writeoff_arrears_uu 交调用方从 gov.arrears 注销；
		# 否则它下季到期时若再欠一次，同一笔本金会在欠付里挂两遍。未付利息不顺延，照旧挂着。
		# accrued_unpaid 里的本金部分恰是逾期本金（违约时按短缺额登记，docs/12 §2.5「同上」），
		# 取 min 只是防御：已计未付不足逾期额说明两边早已脱钩，不能借注销去掩盖。
		var released: int = overdue
		if released > unpaid_int:
			released = unpaid_int
		accrued_unpaid[b] = unpaid_int - released
		last_writeoff_uu = 0
		last_writeoff_arrears_uu = released
		return JWResult.OK

	# 确认减记 == 本金减少量，一分不多：INV-028 的「确认减记」与 INV-025 的持债腿都只认本金。
	var loss_principal: int = 0
	if mode == RestructureMode.WRITEDOWN:
		loss_principal = overdue
		principal_outstanding[b] = out_uu - overdue
	else:
		loss_principal = out_uu
		principal_outstanding[b] = 0
		_clear_schedule_from(b, q)
	JWMath.check_amount(loss_principal)
	accrued_unpaid[b] = 0
	writeoff[b] = writeoff[b] + loss_principal
	JWMath.check_amount(writeoff[b])
	if principal_outstanding[b] == 0:
		status[b] = JWUnits.BondStatus.WRITTEN_OFF
	else:
		status[b] = JWUnits.BondStatus.RESTRUCTURED
	last_writeoff_uu = loss_principal
	last_writeoff_arrears_uu = unpaid_int
	return JWResult.OK


## 未偿本金合计（derived.gov.debt_uu 的唯一来源，纯函数）。
## 步骤：S02 末、S06 末、报告
## 前置：无
## 后置：不改状态
## 不变量：INV-035（debt == Σ 活跃批次未偿本金；裁定 R-INV035-01：活跃 = 尚未结清，含违约与延期中的批次）、
##          INV-107（外债 == Σ holder==row）
## 失败：无
func debt_outstanding() -> int:
	var acc: int = 0
	var b: int = 0
	while b < count:
		# MATURED / WRITTEN_OFF 的未偿本金已在结清时归 0，直接累加即等于「Σ 未结清批次」。
		acc += principal_outstanding[b]
		b += 1
	return JWMath.check_amount(acc)


## 按持有人分组的未偿本金合计（INV-107 的外债口径）。
## 步骤：S02 末、S06 末、报告
## 前置：holder ∈ JWUnits.Holder
## 后置：不改状态
## 不变量：INV-035、INV-107
## 失败：无
func debt_outstanding_of_holder(holder_in: int) -> int:
	var acc: int = 0
	var b: int = 0
	while b < count:
		if holder[b] == holder_in:
			acc += principal_outstanding[b]
		b += 1
	return JWMath.check_amount(acc)


## 季 q 内已向某债权人发行的面值合计（**发行流量**，与批次此后的状态无关）。
## 步骤：S02 §2.6、S04（R-FINANCE-01 的融资前）
## 前置：无
## 后置：不改状态
## 不变量：INV-034 的国内侧——`credit_limit_domestic_memo_uu` 是**每季**的国内新增发行上限
##         （government_init.json `_note_gov`），季内无论经由几次发行都合计计算。
##         docs/10 §8.4 不允许为国内额度另立「已用额度」存量字段；本函数从只增不删的批次表
##         （issue_q / holder / principal_initial）直接推出本季已用量，不新增任何状态。
## 失败：无
func issued_in_quarter(q: int, holder_in: int) -> int:
	var acc: int = 0
	var b: int = 0
	while b < count:
		if issue_q[b] == q and holder[b] == holder_in:
			acc += principal_initial[b]
		b += 1
	return JWMath.check_amount(acc)


## INV-028 的季初未偿本金：本季第一次改动债券簿之前的 Σ outstanding。
## 步骤：S02、S04（JWTreasury 武装终检基准时读）
## 前置：q 是当季
## 后置：若本季尚未武装，则以当前未偿本金武装（调用方必须保证此前本季尚未改账——
##       国库的每个改账入口都在动账之前调用本函数）
## 不变量：INV-028
## 失败：无
func debt_at_quarter_start(q: int) -> int:
	_arm_quarter_baseline(q)
	return _base_debt


## 未来四季到期本金 + 利息（财政页必须展示，derived.fiscal.next4q_debt_service_uu）。
## 步骤：S02 §2.6（算 dsr）、S06（报告）
## 前置：q >= 0
## 后置：不改状态
## 不变量：INV-038（dsr 单调性的输入）
## 失败：无
func debt_service_next4q(q: int) -> int:
	var acc: int = 0
	var b: int = 0
	while b < count:
		var bal: int = principal_outstanding[b]
		var st: int = status[b]
		if bal > 0 and st != JWUnits.BondStatus.MATURED \
				and st != JWUnits.BondStatus.WRITTEN_OFF:
			var cp: int = coupon_ppm[b]
			var is_bullet: bool = amortization[b] == JWUnits.Amortization.BULLET
			var t: int = 0
			while t < 4:
				var qq: int = q + t
				# 利息与 §2.3 同口径：只有 ACTIVE 的批次计提（欠付不计息，docs/10 §3.1）。
				if st == JWUnits.BondStatus.ACTIVE and cp > 0:
					acc += JWMath.mul_div_floor(bal, cp, JWUnits.PPM)
				var due: int = 0
				if is_bullet:
					if qq == maturity_q[b]:
						due = bal
				else:
					due = _sched_at(b, qq)
					if due > bal:
						due = bal
				acc += due
				# 本金还掉后利息基数随之下降——这是合同现金流的真值，不是近似。
				bal -= due
				t += 1
		b += 1
	return JWMath.check_amount(acc)


## 未来 n 季（含 q）逐季的合同还本与利息，分两列写出（承诺时间轴用，docs/20 D-02）。
## 口径与 debt_service_next4q 逐位相同：只有 ACTIVE 批次计息；子弹式到期一次还本，等额本金按计划表；
## 本金还掉后利息基数随之下降。不含未来新发的债。
## 步骤：冷路径（界面读）
## 前置：q >= 0；两个输出数组长度 >= n
## 后置：不改状态；out_principal[t] / out_interest[t] 为第 q + t 季的应付
## 失败：输出数组过短 → 返回 INDEX_OUT_OF_RANGE（不登记故障，冷路径）
func debt_service_schedule_into(q: int, n: int, out_principal: PackedInt64Array,
		out_interest: PackedInt64Array) -> int:
	if n < 0 or out_principal.size() < n or out_interest.size() < n:
		return JWResult.Fault.INDEX_OUT_OF_RANGE
	for t0: int in n:
		out_principal[t0] = 0
		out_interest[t0] = 0
	var b: int = 0
	while b < count:
		var bal: int = principal_outstanding[b]
		var st: int = status[b]
		if bal > 0 and st != JWUnits.BondStatus.MATURED and st != JWUnits.BondStatus.WRITTEN_OFF:
			var cp: int = coupon_ppm[b]
			var is_bullet: bool = amortization[b] == JWUnits.Amortization.BULLET
			var t: int = 0
			while t < n and bal > 0:
				var qq: int = q + t
				if st == JWUnits.BondStatus.ACTIVE and cp > 0:
					out_interest[t] += JWMath.mul_div_floor(bal, cp, JWUnits.PPM)
				var due: int = 0
				if is_bullet:
					if qq == maturity_q[b]:
						due = bal
				else:
					due = mini(_sched_at(b, qq), bal)
				out_principal[t] += due
				bal -= due
				t += 1
		b += 1
	return JWResult.OK


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：尚未 allocate 过
## 后置：全部 SoA 数组 resize 到 JWUnits.BOND_CAP0（amort_schedule 为 BOND_CAP0 * HORIZON_MAX）
## 不变量：INV-136
## 失败：无
func allocate() -> void:
	var n: int = JWUnits.BOND_CAP0
	id.resize(n)
	issue_q.resize(n)
	issue_q.fill(0)
	principal_initial.resize(n)
	principal_initial.fill(0)
	principal_outstanding.resize(n)
	principal_outstanding.fill(0)
	coupon_ppm.resize(n)
	coupon_ppm.fill(0)
	maturity_q.resize(n)
	maturity_q.fill(0)
	amortization.resize(n)
	amortization.fill(0)
	holder.resize(n)
	holder.fill(0)
	status.resize(n)
	status.fill(JWUnits.BondStatus.ACTIVE)
	accrued_unpaid.resize(n)
	accrued_unpaid.fill(0)
	interest_remainder.resize(n)
	interest_remainder.fill(0)
	writeoff.resize(n)
	writeoff.fill(0)
	amort_schedule.resize(AMORT_LEN)
	amort_schedule.fill(0)
	interest_due.resize(n)
	interest_due.fill(0)
	principal_due.resize(n)
	principal_due.fill(0)
	_coupon_seal.resize(n)
	_coupon_seal.fill(0)
	_sched_w.resize(HORIZON_MAX)
	_sched_tb.resize(HORIZON_MAX)
	_sched_out.resize(HORIZON_MAX)
	count = 0
	last_writeoff_uu = 0
	last_writeoff_arrears_uu = 0
	_base_armed = false
	_base_q = 0
	_base_debt = 0


## §1.6 状态块协议：只读取用（返回引用，调用方不得写）。
## 步骤：全部
## 前置：i 在 [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136（顺序是 schema 的一部分）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return issue_q
	if i == 1:
		return principal_initial
	if i == 2:
		return principal_outstanding
	if i == 3:
		return coupon_ppm
	if i == 4:
		return maturity_q
	if i == 5:
		return amortization
	if i == 6:
		return holder
	if i == 7:
		return status
	if i == 8:
		return accrued_unpaid
	if i == 9:
		return interest_remainder
	if i == 10:
		return writeoff
	if i == 11:
		return amort_schedule
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：仅 LOAD / MIG（静态检查限定 systems/content_loader.gd 与 systems/saves.gd）。
## 步骤：LOAD / MIG
## 前置：v.size() 等于契约长度
## 后置：对应 SoA 列被整体替换
## 不变量：INV-136
## 失败：长度不符 → Load.BOND_FIELD；越界 → INDEX_OUT_OF_RANGE
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	var want: int = JWUnits.BOND_CAP0
	if i == 11:
		want = AMORT_LEN
	if v.size() != want:
		# 长度不符是内容 / 存档的字段错误（E_BOND_FIELD），不是运行期故障，不进故障包。
		return JWResult.Load.BOND_FIELD
	# 载入换掉了批次表：旧的 INV-028 季初基准对新状态没有意义，下一次改账入口重新武装。
	_base_armed = false
	# duplicate()：Packed*Array 是引用语义，直接赋值会让权威状态与调用方的临时数组共用内存。
	var c: PackedInt64Array = v.duplicate()
	if i == 0:
		issue_q = c
	elif i == 1:
		principal_initial = c
	elif i == 2:
		principal_outstanding = c
	elif i == 3:
		coupon_ppm = c
		# 载入的票息就是「发行时写入的值」，重新封印；此后任何改写都会被 INV-036 抓到。
		_coupon_seal = v.duplicate()
	elif i == 4:
		maturity_q = c
	elif i == 5:
		amortization = c
	elif i == 6:
		holder = c
	elif i == 7:
		status = c
	elif i == 8:
		accrued_unpaid = c
	elif i == 9:
		interest_remainder = c
	elif i == 10:
		writeoff = c
	else:
		amort_schedule = c
	return JWResult.OK


## §1.6 状态块协议：读标量状态（0 == state.bond.count）。
## 步骤：全部
## 前置：i 在 [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func state_scalar(i: int) -> int:
	if i == 0:
		return count
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：仅 LOAD / MIG。
## 步骤：LOAD / MIG
## 前置：i 在 [0, STATE_SCALAR_IDS.size())
## 后置：count 被写
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE
func set_state_scalar(i: int, v: int) -> int:
	if i != 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	if v < 0 or v > JWUnits.BOND_CAP0:
		return JWResult.Load.BOND_FIELD
	count = v
	_base_armed = false
	return JWResult.OK


## §1.6 状态块协议：读流量数组。
## 步骤：全部
## 前置：i 在 [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func flow_array(i: int) -> PackedInt64Array:
	if i == 0:
		return interest_due
	if i == 1:
		return principal_due
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：本类无流量标量。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：仅 S01；全部 FLOW_* 归零。
## 步骤：S01
## 前置：phase == S01
## 后置：interest_due 与 principal_due 全为 0
## 不变量：INV-009（流量整表清零）
## 失败：无
func reset_flows() -> void:
	interest_due.fill(0)
	principal_due.fill(0)


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01
## 前置：reset_flows() 已调用
## 后置：不改状态
## 不变量：INV-009
## 失败：非 0 → 调用方 raise Fault.FLOW_NOT_RESET
func flow_abs_sum() -> int:
	return JWMath.sum_abs(interest_due) + JWMath.sum_abs(principal_due)

# ── 私有工具 ───────────────────────────────────────────────────────────────

## 武装季 q 的 INV-028 基准（本季已武装则不动）。必须在本季第一次写字段之前调用。
func _arm_quarter_baseline(q: int) -> void:
	if _base_armed and _base_q == q:
		return
	_base_debt = debt_outstanding()
	_base_q = q
	_base_armed = true


## 批次 b 在绝对季 q 的计划还本额（level_principal 专用；越界返回 0）。
## 步骤：S02 §2.4、§2.6
## 前置：b ∈ [0, count)
## 后置：不改状态
## 不变量：INV-037
## 失败：无（越界即「该季无计划」，不是故障）
func _sched_at(b: int, q: int) -> int:
	var k: int = q - issue_q[b]
	if k < 1 or k >= HORIZON_MAX:
		return 0
	return amort_schedule[JWMath.mul(b, HORIZON_MAX) + k]


## 批次 b 在季 q（含）之后尚未计划的还本合计，即 Σ_{q' >= q} scheduled。
## 步骤：S02 §2.4
## 前置：b ∈ [0, count)
## 后置：不改状态
## 不变量：INV-037
## 失败：无
func _scheduled_from(b: int, q: int) -> int:
	var k: int = q - issue_q[b]
	if k < 1:
		k = 1
	var base: int = JWMath.mul(b, HORIZON_MAX)
	var acc: int = 0
	while k < HORIZON_MAX:
		acc += amort_schedule[base + k]
		k += 1
	return acc


## 逾期本金：未偿本金中已经过了计划还款季、却仍未偿还的部分。
## 步骤：S02 重组分支
## 前置：b ∈ [0, count)
## 后置：不改状态
## 不变量：INV-037（overdue == outstanding − Σ_{q' >= q} scheduled，即 INV-037 的残差本身）
## 失败：无
##
## **本季的分期不算逾期**：docs/12 §2.5 规定重组命令由玩家在**下一季**提交，
## 因此调用时 q 已经越过欠付发生的那一季。若把本季应还额也算进来，
## 玩家就能在付款之前先「延期」——那正是 ADV-02 要抓的无成本借新还旧。
func _overdue_principal(b: int, q: int) -> int:
	var out_uu: int = principal_outstanding[b]
	if amortization[b] == JWUnits.Amortization.BULLET:
		if q > maturity_q[b]:
			return out_uu
		return 0
	var od: int = out_uu - _scheduled_from(b, q)
	if od < 0:
		od = 0
	return od


## 清空批次 b 在季 q（含）之后的全部计划还本（违约核销后没有未来现金流）。
## 步骤：S02 重组分支
## 前置：b ∈ [0, count)
## 后置：Σ_{q' >= q} scheduled == 0
## 不变量：INV-037
## 失败：无
func _clear_schedule_from(b: int, q: int) -> void:
	var k: int = q - issue_q[b]
	if k < 1:
		k = 1
	var base: int = JWMath.mul(b, HORIZON_MAX)
	while k < HORIZON_MAX:
		amort_schedule[base + k] = 0
		k += 1


## issue() 与 can_issue() 共用的全部前置判据（**唯一一份**，避免预检与实发漂移）。
## 步骤：S02 §2.6
## 前置：无
## 后置：不改状态；register_fault 为 true 时按 docs/12 §9 登记故障
## 不变量：INV-034、INV-037、INV-038、INV-010
## 失败：批次表已满 → Reject.CREDIT_LIMIT（业务性拒绝，不登记故障）；
##       其余越界 → 对应的 Fault 码
func _issue_guard(cap: int, q: int, principal_uu: int, coupon_ppm_per_q: int,
		maturity_q_in: int, amortization_in: int, holder_in: int, register_fault: bool) -> int:
	if count + 1 > cap:
		# 批次上限是硬边界：不合并、不复用已结清的下标（下标必须永久稳定）。
		return JWResult.Reject.CREDIT_LIMIT
	if principal_uu <= 0 or principal_uu > JWUnits.AMOUNT_MAX:
		if register_fault:
			JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, principal_uu, JWUnits.AMOUNT_MAX)
		return JWResult.Fault.INT_OVERFLOW
	if coupon_ppm_per_q < 0 or coupon_ppm_per_q > COUPON_PPM_MAX:
		if register_fault:
			JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, coupon_ppm_per_q, COUPON_PPM_MAX)
		return JWResult.Fault.BOND_MISMATCH
	if amortization_in != JWUnits.Amortization.BULLET \
			and amortization_in != JWUnits.Amortization.LEVEL_PRINCIPAL:
		if register_fault:
			JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, amortization_in, 0)
		return JWResult.Fault.BOND_MISMATCH
	if holder_in != JWUnits.Holder.INVPOOL and holder_in != JWUnits.Holder.ROW:
		if register_fault:
			JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, holder_in, 0)
		return JWResult.Fault.BOND_MISMATCH
	# tenor == 0 会让到期表为空而 outstanding > 0，直接破坏 INV-037（ADV-C07）。
	var tenor: int = maturity_q_in - q
	if tenor <= 0 or tenor >= HORIZON_MAX:
		if register_fault:
			JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, tenor, HORIZON_MAX)
		return JWResult.Fault.BOND_MISMATCH
	return JWResult.OK


## merge_target / can_merge / merge_issue 共用的全部判据（**唯一一份**，预检与实并不得漂移）。
## 步骤：S02 §2.6、S04
## 前置：无
## 后置：不改状态；register_fault 为 true 时按 docs/12 §9 登记故障
## 不变量：INV-036、INV-037（见 merge_target 的说明）
## 失败：下标越界 → INDEX_OUT_OF_RANGE；面值越界 → INT_OVERFLOW；批次不是「本季刚发出的原样」→ BOND_MISMATCH
func _merge_guard(b: int, q: int, principal_uu: int, register_fault: bool) -> int:
	if b < 0 or b >= count:
		if register_fault:
			JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, b, count)
		return JWResult.Fault.INDEX_OUT_OF_RANGE
	if principal_uu <= 0 or principal_uu > JWUnits.AMOUNT_MAX \
			or principal_initial[b] + principal_uu > JWUnits.AMOUNT_MAX:
		if register_fault:
			JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, principal_uu, principal_initial[b])
		return JWResult.Fault.INT_OVERFLOW
	var tenor: int = maturity_q[b] - issue_q[b]
	if issue_q[b] != q or status[b] != JWUnits.BondStatus.ACTIVE \
			or principal_outstanding[b] != principal_initial[b] \
			or writeoff[b] != 0 or accrued_unpaid[b] != 0 \
			or coupon_ppm[b] != _coupon_seal[b] or tenor <= 0 or tenor >= HORIZON_MAX:
		if register_fault:
			JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, b, q)
		return JWResult.Fault.BOND_MISMATCH
	return JWResult.OK


## 预生成等额本金分期表：issue_q+1 … maturity_q 共 tenor 期，等权重最大余数法。
## 步骤：S02 §2.6
## 前置：tenor ∈ [1, HORIZON_MAX)
## 后置：Σ_{k=1..tenor} amort_schedule[b*HORIZON_MAX+k] == principal_uu（INV-037）
## 不变量：INV-003（拆分精确）、INV-037
## 失败：拆分失败 → Fault.SPLIT_MISMATCH（由 split_lr_into 登记）
func _fill_level_schedule(b: int, principal_uu: int, tenor: int) -> int:
	# 预分配缓冲按期数取长度：split_lr_into 要求三条数组等长，且不在其内部分配。
	if _sched_w.size() != tenor:
		_sched_w.resize(tenor)
		_sched_tb.resize(tenor)
		_sched_out.resize(tenor)
	var i: int = 0
	while i < tenor:
		_sched_w[i] = 1
		# 决胜键 == 期序：等权重下余数全相等，多出的 1 μU 一律落在最早的几期，
		# 结果唯一且可重放（INV-014）。
		_sched_tb[i] = i
		i += 1
	var rc: int = JWMath.split_lr_into(principal_uu, _sched_w, _sched_tb, _sched_out)
	if rc != 0:
		return JWResult.raise_fault(JWResult.Fault.BOND_MISMATCH, b, rc)
	var base: int = JWMath.mul(b, HORIZON_MAX)
	var k: int = 0
	var back: int = 0
	while k < tenor:
		var v: int = _sched_out[k]
		amort_schedule[base + k + 1] = v
		back += v
		k += 1
	if back != principal_uu:
		return JWResult.raise_fault(JWResult.Fault.SPLIT_MISMATCH, principal_uu, back)
	return JWResult.OK


## ID 里的季标记：非负季补零到三位（`q007`），负季原样带符号（`q-20`，与剧本一致）。
## 步骤：S02 §2.6（冷路径，结算期只调用寥寥数次）
## 前置：无
## 后置：不改状态
## 不变量：INV-010
## 失败：无
func _q_tag(q: int) -> String:
	if q < 0:
		return str(q)
	return _pad(q, 3)


## 十进制左补零到 width 位（不用 String 的格式化算符，避免 sim/ 内出现裸 `%`）。
## 步骤：S02 §2.6
## 前置：v >= 0
## 后置：返回长度 >= width 的十进制串
## 不变量：INV-010
## 失败：无
func _pad(v: int, width: int) -> String:
	var s: String = str(v)
	while s.length() < width:
		s = "0" + s
	return s


## §1.6 状态块协议：读档时写回流量数组（R-SAVE-01，由 tools/gen_flow_setters.py 按 flow_array 逐项对称生成）。
## 步骤：LOAD（JWSaves 经 JWSimState 调用）
## 前置：v 的长度与本块当前分配的长度一致（长度是 schema 的一部分，INV-136）
## 后置：对应成员被整体替换
## 不变量：INV-133（读档后与原进程逐位相同）
## 失败：下标越界或长度不符 → INDEX_OUT_OF_RANGE
func set_flow_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != interest_due.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		interest_due = v.duplicate()
		return JWResult.OK
	if i == 1:
		if v.size() != principal_due.size():
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v.size())
		principal_due = v.duplicate()
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
