## 政策的「资格 → 预算预留 → 生效 → 运行费 → 退出」全链路，以及补助的幂等台账。
## 持有 state.policy.* 的运行时状态。
##
## 骨架依据：docs/17_api_skeleton.md §4.21。
class_name JWPolicyEngine
extends RefCounted

# ───────────────────────── 常量 ─────────────────────────

## 补助幂等台账容量（由 40/120 季规模上界推出，docs/17 §4.21）。
const CLAIM_CAP: int = 2048


## log.ledger.cause 的政策段基址：一笔由政策 p 引起的交易写 CAUSE_POLICY_BASE + p。
## docs/10 §2.5 只规定 cause 是「来源操作码（政策／项目／事件／冲击／规则）」，
## 尚无全局码表；本段基址是政策段的约定起点，占用 [5000, 5012)。
const CAUSE_POLICY_BASE: int = 5000

## claim_key 的位域布局（docs/12 §4.3 的 hash64 用**精确位打包**实现）。
## 打包优于哈希：同键「至多一条、至多付一次」是 INV-097 的字面要求，
## 哈希只能给出概率保证，而位打包在契约值域内是**无碰撞的单射**，且可逆、可读、无乘法溢出。
const CLAIM_KEY_POLICY_BITS: int = 4
const CLAIM_KEY_CELL_SHIFT: int = 4
const CLAIM_KEY_CELL_BITS: int = 5
const CLAIM_KEY_Q_SHIFT: int = 9
const CLAIM_KEY_Q_BITS: int = 12
const CLAIM_KEY_EVENT_SHIFT: int = 21
const CLAIM_KEY_EVENT_BITS: int = 26
## 恒置位，保证任何合法键都不等于 0（0 是台账未使用行的初值）
const CLAIM_KEY_TAG_SHIFT: int = 47

# ───────────────── §1.6 状态块协议的注册表（SUBSYS_POLICY） ─────────────────

## 本块各数组所属子系统（与 STATE_ARRAY_IDS 等长），用于 subsystem_hash 与 WriteGuard。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY,
	JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY,
	JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY,
	JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY,
	JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_POLICY,
	JWUnits.SUBSYS_POLICY,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
## 注：state.policy.claim_ledger[] 在运行期落成两条等长数组（键与金额），占两个槽位。
## R-BASELINE-01：开局前已通过的现行制度（个税、企业税、失业保障）的 enacted_q 哨兵。
## 与「未通过」的 −1 区分；远小于任何合法季号，且满足 INV-095：0 ≥ ENACTED_BEFORE_START + lag。
const ENACTED_BEFORE_START: int = -1000

## E17（policy_P12.json /effect/_note_formula_steps）：采购透明通道每季写进 log.explanations（kind = accounted）
## 的 8 个中间量，cause == EXPLAIN_P12_BASE + 下标；这些中间量不是状态字段，不进 state_hash。
const EXPLAIN_P12_BASE: int = 1200
const EXPLAIN_P12_KEYS: PackedStringArray = ["coverage", "audit", "progress", "ramp", "avail", "load", "gain", "delta"]

const STATE_ARRAY_IDS: PackedStringArray = [
	"state.policy.enabled",
	"state.policy.enacted_q",
	"state.policy.effective_from_q",
	"state.policy.params_ppm",
	"state.policy.params_uu",
	"state.policy.pending_params",
	"state.policy.region_mask",
	"state.policy.budget_committed_uu",
	"state.policy.budget_spent_uu",
	"state.policy.toggle_count",
	"state.policy.cooldown_until_q",
	"state.policy.claim_ledger.key",
	"state.policy.claim_ledger.amount",
	"state.policy.exit_pending_q",
	# R-PARAMS-01：执行中政策的改参数按时滞排期——排期值与生效季（−1 == 无排期）。
	"state.policy.scheduled_params",
	"state.policy.params_due_q",
	# R-P10-01：能力 / 行政类政策在落点季并入长期运行费义务的每季额（累计）。
	"state.policy.opex_landed_uu",
]
const STATE_SCALAR_IDS: PackedStringArray = [
	"state.policy.claim_count",
]
const FLOW_ARRAY_SUBSYS: PackedInt64Array = []
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = []

## 每个槽位的契约长度（与 STATE_ARRAY_IDS 等长）。长度是 schema 的一部分（INV-136）。
const STATE_ARRAY_LEN: PackedInt64Array = [
	12, 12, 12, 48, 48, 48, 12, 12, 12, 12, 12, CLAIM_CAP, CLAIM_CAP, 12,
	48, 12, 12,
]

# ───────────────────────── 成员变量 ─────────────────────────

## state.policy.enabled[]：0/1，长度 12，初值 0，写入者 S02
var enabled: PackedInt64Array = PackedInt64Array()
## state.policy.enacted_q[]：季，长度 12，初值 −1，写入者 S02
var enacted_q: PackedInt64Array = PackedInt64Array()
## state.policy.effective_from_q[]：季，长度 12，初值 −1，写入者 S02（只能向前）
var effective_from_q: PackedInt64Array = PackedInt64Array()
## state.policy.params_ppm[]：ppm，长度 48，初值为默认值，写入者 S02
var params_ppm: PackedInt64Array = PackedInt64Array()
## state.policy.params_uu[]：μU，长度 48，初值为默认值，写入者 S02
var params_uu: PackedInt64Array = PackedInt64Array()
## state.policy.pending_params[]：长度 48，写入者 CMD
var pending_params: PackedInt64Array = PackedInt64Array()
## state.policy.region_mask[]：位掩码 0..15，长度 12，初值 0，写入者 S02
var region_mask: PackedInt64Array = PackedInt64Array()
## state.policy.budget_committed_uu[]：μU，长度 12，初值 0，写入者 S02
var budget_committed: PackedInt64Array = PackedInt64Array()
## state.policy.budget_spent_uu[]：μU，长度 12，初值 0，写入者 S04
var budget_spent: PackedInt64Array = PackedInt64Array()
## state.policy.toggle_count[]：计数，长度 12，初值 0，写入者 S02（单调递增）
var toggle_count: PackedInt64Array = PackedInt64Array()
## state.policy.cooldown_until_q[]：季，长度 12，初值 0，写入者 S02
var cooldown_until_q: PackedInt64Array = PackedInt64Array()
## state.policy.claim_ledger[] 的键列：长度 CLAIM_CAP，初值 0，写入者 S04（只增不减）
var claim_key: PackedInt64Array = PackedInt64Array()
## state.policy.claim_ledger[] 的金额列：μU，长度 CLAIM_CAP，初值 0，写入者 S04
var claim_amount: PackedInt64Array = PackedInt64Array()
## state.policy.exit_pending_q[]：季，长度 12，初值 −1，写入者 S02
var exit_pending_q: PackedInt64Array = PackedInt64Array()
## state.policy.scheduled_params[]：长度 48，写入者 S02。执行中政策改参数的排期值（R-PARAMS-01）。
var scheduled_params: PackedInt64Array = PackedInt64Array()
## state.policy.params_due_q[]：季，长度 12，初值 −1，写入者 S02。排期值生效季；−1 == 无排期。
var params_due_q: PackedInt64Array = PackedInt64Array()
## state.policy.opex_landed_uu[]：μU/季，长度 12，初值 0，写入者 S07（落点季）。R-P10-01。
var opex_landed: PackedInt64Array = PackedInt64Array()

## 派生量（类 = D）：JWUnits.BlockedReason，长度 12，初值 0，S02 每季重算，不进 state_hash
var _blocked_reason: PackedInt64Array = PackedInt64Array()
## 台账行数（只增不减），写入者 S04
var _claim_count: int = 0

## state.bloc.stance_ppm 的只读视图（长度 STANCE_N），由 JWTurnRunner 在 S02 前注入。
## 存在的理由：冻结的 try_enact 签名里没有 JWInterestGroups，而 02.1 的第 1 项资格检查
## （集团否决）必须读立场。空视图会让否决检查失去依据，故默认长度为 STANCE_N 的全零数组，
## 并由 set_bloc_stance_view() 注入真值。
var _bloc_stance_view: PackedInt64Array = PackedInt64Array()
## R-AUTHORITY-01：每条政策的「按域持有否决资格的集团」位掩码（长度 POLICY_N），S02 前注入。
var _bloc_veto_view: PackedInt64Array = PackedInt64Array()
## R-ENACT-01：通过命令受理前的参数槽快照（pending / ppm / uu 各 POLICY_PARAM_STRIDE 格）。不是状态。
var _param_snap: PackedInt64Array = PackedInt64Array()

## 区域拆分用的预分配缓冲（长度 R），热路径不新建对象（docs/17 §1.4）
var _r_weight: PackedInt64Array = PackedInt64Array()
var _r_tiebreak: PackedInt64Array = PackedInt64Array()
var _r_out: PackedInt64Array = PackedInt64Array()
## 群组拆分用的预分配缓冲（长度 GROUP）
var _g_weight: PackedInt64Array = PackedInt64Array()
var _g_tiebreak: PackedInt64Array = PackedInt64Array()
var _g_out: PackedInt64Array = PackedInt64Array()

# ───────────────────────── 方法 ─────────────────────────

## S02 §2.1：命令受理的资格检查链（任一失败即 REJECT，命令仍入档）。
## 步骤：S02 §2.1
## 前置：命令已通过 S01 的格式校验
## 后置：通过 → enacted_q = q，effective_from_q = q + lag（只能向前），toggle_count += 1，
##       cooldown_until_q = q + cooldown_q，并 post(kind=POLICY_TOGGLE_COST)；
##       未通过 → 状态完全不变，写 log.rejections
## 不变量：INV-095, INV-098（冷却与单调不回溯）、INV-099、INV-100（blocked_reason != none）、INV-137
## 失败：Reject.AUTHORITY / SEATS_SHORT / BLOC_VETO / POLICY_COOLDOWN / PRECONDITION /
##       NO_SLOT / NO_FUNDING / BUDGET_INSUFFICIENT
##
## 顺序上的一处硬性安排：资金充足性是**先判后动**（只读 cash 与 reserved_memo），
## 开关成本过账排在预留之前，预留之前的每一步都不改任何状态。
## 这样「未通过 → 状态完全不变」是由执行顺序保证的，不需要任何回滚补丁。
func try_enact(p: int, defs: JWPolicyDef, politics: JWPolitics, treasury: JWTreasury,
		pq: JWProjectQueue, capital: JWCapital, ledger: JWLedger, accounts: JWAccount,
		q: int, params: PackedInt64Array) -> int:
	if not _valid_policy(p):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, JWUnits.POLICY_N)
	if politics == null or treasury == null or pq == null \
			or capital == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, -1)
	if not _defs_ready(defs):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, -2)
	if params.size() < JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)

	# 已经在生效中的政策不能再次通过：重复受理会让 toggle_count 与冷却失去意义（INV-098）。
	if enabled[p] == 1:
		_blocked_reason[p] = JWUnits.BlockedReason.NONE
		return JWResult.Reject.ALREADY_ENACTED

	# 整条资格链是只读的，判完再动手：这样「未通过 → 状态完全不变」由执行顺序保证。
	var rc_chain: int = check_eligibility(p, defs, politics, treasury, pq, capital,
			accounts, q, params)
	_blocked_reason[p] = reason_of_reject(rc_chain)
	if rc_chain != JWResult.OK:
		return rc_chain

	var need: int = defs.cost_per_quarter(p)
	var commit: int = defs.cost_one_off_uu[p]
	var toggle: int = _toggle_cost(p, defs, params)
	var avail: int = accounts.cash_of(JWIds.AGENT_GOV) - treasury.reserved_memo

	# 开关有真实成本（INV-098），过账同时计入基本支出实付（INV-027）。
	# 资金充足性已在资格链第 5 档判过（avail >= need + toggle），这里再失败只能是结构性故障
	# （post / 流量登记已登记第一现场）：原样上抛为 FAULT，不降级成业务拒绝。
	var rc_cost: int = _post_toggle_cost(p, toggle, treasury, ledger,
			JWUnits.Kind.POLICY_TOGGLE_COST)
	if rc_cost != JWResult.OK:
		_blocked_reason[p] = JWUnits.BlockedReason.BUDGET
		return rc_cost

	var rc_res: int = treasury.reserve(need, accounts)
	if rc_res != JWResult.OK:
		# 上面刚判过 avail >= need + toggle，预留仍失败说明国库的可用额度口径与本处不一致。
		# 这是结构性矛盾，不是业务性短缺：登记故障，不静默改账。
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, need, avail)

	# 签约即占用未来全部季的预算承诺（计划书 §07；docs/12 §2.2）。走 treasury 的唯一入口（INV-032）。
	var rc_commit: int = treasury.record_commitment(commit)
	if rc_commit != JWResult.OK:
		return rc_commit
	budget_committed[p] += commit
	JWMath.check_amount(budget_committed[p])

	enabled[p] = 1
	enacted_q[p] = q
	# effective_from_q 只能向前，不得回溯（INV-098）。
	var ef: int = q + defs.lag_enact_to_effect_q[p]
	if ef > effective_from_q[p]:
		effective_from_q[p] = ef
	toggle_count[p] += 1
	cooldown_until_q[p] = q + defs.cooldown_q[p]
	exit_pending_q[p] = -1
	_blocked_reason[p] = JWUnits.BlockedReason.NONE
	return JWResult.OK


## S02 §2.1 的资格检查链本体：**只读**，一次判完五档，返回第一个不满足的 Reject 码。
## 步骤：S02 §2.1
## 前置：p 合法；defs 已装填；params.size() >= PARAM_N
## 后置：不改任何状态（这是 try_enact「未通过即完全不变」的依据，也让 UI 能预判）
## 不变量：INV-094, INV-095, INV-098, INV-099, INV-100
## 失败：Reject.AUTHORITY / SEATS_SHORT / BLOC_VETO / POLICY_COOLDOWN / PRECONDITION /
##       NO_SLOT / BUDGET_INSUFFICIENT；全部通过返回 JWResult.OK
func check_eligibility(p: int, defs: JWPolicyDef, politics: JWPolitics, treasury: JWTreasury,
		pq: JWProjectQueue, capital: JWCapital, accounts: JWAccount,
		q: int, params: PackedInt64Array) -> int:
	# 1 legal_authority / min_seats / bloc veto —— 判定在 JWPolitics，本类不复制那套规则。
	# 否决集团取并集：政策自己声明的 requires_bloc_support，加上按改革域持有否决资格的集团（R-AUTHORITY-01）。
	var veto_mask: int = defs.requires_bloc_mask[p]
	if _bloc_veto_view.size() == JWUnits.POLICY_N:
		veto_mask = veto_mask | _bloc_veto_view[p]
	var rc_auth: int = politics.check_authority(defs.authority_bit[p], defs.min_seats_ppm[p],
			veto_mask, _bloc_stance_view, p)
	if rc_auth != JWResult.OK:
		return rc_auth

	# 2 cooldown（INV-098）
	if q < cooldown_until_q[p]:
		return JWResult.Reject.POLICY_COOLDOWN

	# 3 precondition：运行时 SoA 里可判定的前置条件只有「预算审查窗口」一条
	# （legal_authority 是第 1 项，construction_slot 是第 4 项，budget_reservation 是第 5 项，
	# 三者都已各自成档，不在这里重复判）。
	if defs.requires_budget_review[p] == 1 and politics.f_budget_review_due != 1:
		return JWResult.Reject.PRECONDITION

	# 4 queue slot：只有项目类政策占施工槽位（INV-094）
	var mask: int = region_mask[p] & JWUnits.REGION_MASK_ALL
	if defs.kind[p] == JWPolicyDef.POLICY_KIND_PROJECT:
		if mask == 0:
			# 项目类必须选定地区；掩码为空时无处落槽，按前置条件不满足处理，
			# 绝不默认「全国开工」——那是凭空发放效果。
			return JWResult.Reject.PRECONDITION
		for r: int in JWUnits.R:
			if ((mask >> r) & 1) == 0:
				continue
			if pq.slots_used(r) >= capital.slots_total(r):
				return JWResult.Reject.NO_SLOT

	# 5 funding（02.2 预算预留，不是支付）
	var need: int = defs.cost_per_quarter(p)
	var commit: int = defs.cost_one_off_uu[p]
	var toggle: int = _toggle_cost(p, defs, params)
	if need < 0 or commit < 0:
		return JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, need, commit)
	JWMath.check_amount(need)
	JWMath.check_amount(commit)
	# 可用额度 = 现金 − 已预留（docs/12 §2.2）。开关成本与本季预留必须同时装得下：
	# 先扣开关成本再预留，若只按 need 判会在过账后把 reserved_memo 推到超过现金（INV-033）。
	var avail: int = accounts.cash_of(JWIds.AGENT_GOV) - treasury.reserved_memo
	if avail < need + toggle:
		return JWResult.Reject.BUDGET_INSUFFICIENT
	return JWResult.OK


## R-LAUNCH-01：立项命令的资格检查——政策资格链中与地区、资金无关的两档：
## 法定权限 / 席位 / 集团否决（否决集团取并集，R-AUTHORITY-01），以及预算审议窗口（requires_budget_review）。
## 原先立项只查施工槽位与规模，项目类政策的授权、否决与窗口一概不查（界面子代理报告）。
## 施工槽位由 JWProjectQueue.launch 判，资金由项目逐季融资与欠付规则处理，这里不重复。
## 步骤：S02 §2.1（立项命令受理）
## 前置：p 合法；S02 已注入集团立场与否决视图
## 后置：不改状态
## 不变量：INV-099、INV-127
## 失败：Reject.AUTHORITY / SEATS_SHORT / BLOC_VETO / PRECONDITION
func check_launch_eligibility(p: int, defs: JWPolicyDef, politics: JWPolitics) -> int:
	if not _valid_policy(p) or not _defs_ready(defs) or politics == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, JWUnits.POLICY_N)
	var veto_mask: int = defs.requires_bloc_mask[p]
	if _bloc_veto_view.size() == JWUnits.POLICY_N:
		veto_mask = veto_mask | _bloc_veto_view[p]
	var rc: int = politics.check_authority(defs.authority_bit[p], defs.min_seats_ppm[p],
			veto_mask, _bloc_stance_view, p)
	if rc != JWResult.OK:
		return rc
	if defs.requires_budget_review[p] == 1 and politics.f_budget_review_due != 1:
		return JWResult.Reject.PRECONDITION
	return JWResult.OK


## Reject 码 → derived.policy.blocked_reason 的原因码（docs/10 §8.2 的七值枚举）。
## 步骤：S02
## 前置：无
## 后置：不改状态
## 不变量：INV-100（本地化表按原因码建条目，故映射必须是全函数，没有「其它」出口）
## 失败：无
static func reason_of_reject(code: int) -> int:
	match code:
		JWResult.OK:
			return JWUnits.BlockedReason.NONE
		JWResult.Reject.AUTHORITY, JWResult.Reject.SEATS_SHORT, JWResult.Reject.BLOC_VETO:
			return JWUnits.BlockedReason.AUTHORITY
		JWResult.Reject.POLICY_COOLDOWN:
			return JWUnits.BlockedReason.COOLDOWN
		JWResult.Reject.PRECONDITION:
			return JWUnits.BlockedReason.PRECONDITION
		JWResult.Reject.NO_SLOT:
			return JWUnits.BlockedReason.QUEUE
		JWResult.Reject.BUDGET_INSUFFICIENT, JWResult.Reject.NO_FUNDING, \
				JWResult.Reject.CREDIT_LIMIT:
			return JWUnits.BlockedReason.BUDGET
	# 其余一律按「前置条件不满足」呈现：宁可给一个偏保守的原因，也不给玩家一个空原因（INV-100）。
	return JWUnits.BlockedReason.PRECONDITION


## S02 末：对全部 12 项政策重算 blocked_reason（INV-100 的落地点）。
## 步骤：S02 末
## 前置：本季的席位、现金、槽位都已定形
## 后置：每个 enabled == 0 的政策都带一个非空原因码（真正可执行的那些除外）
## 不变量：INV-100
## 失败：入参不完整 → INDEX_OUT_OF_RANGE
##
## 为什么需要它：try_enact 只会被「玩家确实提交了命令」的那一项调用，而政策页要对**没提交**
## 的十一项也说清为什么不能点。没有这一遍扫描，INV-100 对未提交的政策永远落空。
func refresh_blocked_reasons(defs: JWPolicyDef, politics: JWPolitics, treasury: JWTreasury,
		pq: JWProjectQueue, capital: JWCapital, accounts: JWAccount,
		q: int, params: PackedInt64Array) -> int:
	if politics == null or treasury == null or pq == null or capital == null \
			or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, -1)
	if not _defs_ready(defs):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, -2)
	if params.size() < JWUnits.PARAM_N or enabled.size() != JWUnits.POLICY_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)
	for p: int in JWUnits.POLICY_N:
		if enabled[p] == 1:
			_blocked_reason[p] = JWUnits.BlockedReason.NONE
			continue
		var rc: int = check_eligibility(p, defs, politics, treasury, pq, capital,
				accounts, q, params)
		if rc == JWResult.OK and exit_pending_q[p] >= 0:
			# 资格都在，只是玩家自己退出过：EXITED 比 NONE 更能解释「为什么它现在是关的」。
			_blocked_reason[p] = JWUnits.BlockedReason.EXITED
			continue
		_blocked_reason[p] = reason_of_reject(rc)
	return JWResult.OK


## S02：撤销政策（退出规则）。
## 步骤：S02 §2.1
## 前置：冷却已过；退出规则可执行
## 后置：enabled = 0；exit_pending_q 设置；已交付资产保留（delivered_assets: retain）
## 不变量：INV-098（toggle_count 单调递增，每次开关有真实成本）、INV-032
## 失败：Reject.POLICY_COOLDOWN
##
## 分工：项目类政策的剩余合同额、残值与违约金由 JWProjectQueue.cancel 收口（docs/12 §2.7），
## 本函数对项目类**不碰** committed_memo，否则同一笔承诺会被冲减两次。
func try_repeal(p: int, defs: JWPolicyDef, treasury: JWTreasury, ledger: JWLedger,
		accounts: JWAccount, q: int) -> int:
	if not _valid_policy(p):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, JWUnits.POLICY_N)
	if treasury == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, -1)
	if not _defs_ready(defs):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, -2)
	if enabled[p] != 1:
		return JWResult.Reject.NOT_FOUND
	if q < cooldown_until_q[p]:
		_blocked_reason[p] = JWUnits.BlockedReason.COOLDOWN
		return JWResult.Reject.POLICY_COOLDOWN

	# 退出的两笔真实成本：一次性开关成本，以及按剩余合同额计的违约金（沉没成本不退）。
	var toggle: int = defs.toggle_cost_uu[p]
	if toggle < 0:
		toggle = 0
	# 口径一律取**本次开启**（enacted_q[p] 那一次 try_enact）：budget_committed / budget_spent 是
	# 跨越多次开关的历史累计（docs/10 §8.2），用它们相减会把此前各次撤销已释放的承诺再释放一遍——
	# 第二次撤销时要释放的额度是 memo 里本政策份额的两倍，record_commitment 登记 LEDGER_IMBALANCE
	# （ADV-A01 交替开关 P09 在第二次成功撤销那一季撞出的码 22）。
	var release: int = 0
	var penalty: int = 0
	if defs.kind[p] != JWPolicyDef.POLICY_KIND_PROJECT:
		var commit_cur: int = _commit_of_current_enactment(p, defs)
		var unexecuted: int = commit_cur - _spent_in_current_enactment(p)
		if unexecuted < 0:
			# 本次开启的实付超过了本次签入的承诺：pay_subsidy 的额度闸按同一口径把关，走不到这里；
			# 走到即额度闸被绕过（INV-096），登记故障，不夹逼。
			return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE, commit_cur, unexecuted)
		# rounding: floor, reason=违约金按未执行额比例折算，少付 1 μU 优于凭空多付
		penalty = JWMath.mul_ppm(unexecuted, defs.exit_compensation_ppm[p])
		# memo 里本政策的份额 == 本次开启签入的全额：补助实付（pay_subsidy）不经 record_commitment
		# 冲减（见其注释），已执行的那部分也还挂在 memo 上。撤销后本政策再无未来应付，
		# 份额须整笔移出，memo 才回到开启前的值（INV-032：memo == 未来应付）。
		release = commit_cur

	var cash: int = accounts.cash_of(JWIds.AGENT_GOV)
	if cash < toggle + penalty:
		# 付不起就整笔显式欠付，不缩规模也不免除：违约金是退出的代价，不能因为没钱就消失。
		# 收款方与正常过账时相同（中州服务 cell，R-PUBSERV-01，见 _post_toggle_cost）：
		# 欠付是日后以现金清偿的债务，挂在不持现金的 pubserv 名下就是一笔永远清不掉的「政府欠自己」。
		# 欠付登记的档位与付得起时的流量登记同为 DISCRETIONARY（见 _post_toggle_cost）。
		if toggle + penalty > 0:
			treasury.add_arrears(toggle_payee_agent(), toggle + penalty,
					JWUnits.PayLine.DISCRETIONARY)
			if JWResult.has_pending():
				return JWResult.pending_code()
	else:
		var rc_cost: int = _post_toggle_cost(p, toggle, treasury, ledger,
				JWUnits.Kind.POLICY_TOGGLE_COST)
		if rc_cost != JWResult.OK:
			return rc_cost
		if penalty > 0:
			var rc_pen: int = _post_toggle_cost(p, penalty, treasury, ledger,
					JWUnits.Kind.CANCEL_PENALTY)
			if rc_pen != JWResult.OK:
				return rc_pen

	# 本次开启签入的承诺从政府的承诺备查额里释放（INV-032「取消 −」）；累计已承诺 budget_committed 是
	# **历史累计口径**，不回冲——回冲会把「曾经承诺过多少」这条审计线索抹掉。
	# 走 treasury 的唯一入口：memo 装不下要释放的额度说明开启时的承诺没登记，
	# 那是上游缺陷，登记 LEDGER_IMBALANCE，**不截到 0**（原写法把差额静默抹掉了）。
	if release > 0:
		var rc_c: int = treasury.record_commitment(-release)
		if rc_c != JWResult.OK:
			return rc_c

	# R-EXIT-OPEX-01：行政类政策（P11 / P12）撤回即解除已并入的运行费义务（两份 exit_rule 原文）；
	# 能力类（P05 / P10）已交付的设施照常要养，义务保留（P10 拨不拨由拨款旋钮决定，R-P10-01）。
	if defs.kind[p] == JWPolicyDef.POLICY_KIND_ADMIN and opex_landed[p] > 0:
		treasury.service_opex_committed = maxi(treasury.service_opex_committed - opex_landed[p], 0)
		opex_landed[p] = 0
	enabled[p] = 0
	exit_pending_q[p] = q
	toggle_count[p] += 1
	cooldown_until_q[p] = q + defs.cooldown_q[p]
	_blocked_reason[p] = JWUnits.BlockedReason.EXITED
	# 已交付资产保留：effective_from_q 与已落点的产能一概不回收（exit_rule.delivered_assets）。
	# is_effective 靠 enabled == 0 归零效应，不需要也不允许倒推历史。
	return JWResult.OK


## S02：把玩家提交的 pending_params 落到 params（只在允许修改的窗口内）。
## 步骤：S02 §2.1
## 前置：每项在 valid_range 内（V-PD-09）
## 后置：params_ppm / params_uu 更新；pending_params 清回同值
## 不变量：INV-138（命令不得携带任何直接状态值）、INV-099
## 失败：Reject.PARAM_RANGE
##
## 两个数组写同一个整数：运行期 SoA 里没有参数单位列，params_ppm 与 params_uu 是同一组
## 玩家参数的两个**单位视图**，消费方按自己需要的量纲取用（税率取 ppm 视图、额度取 μU 视图）。
func apply_pending_params(p: int, defs: JWPolicyDef, q: int) -> int:
	if not _valid_policy(p):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, JWUnits.POLICY_N)
	if defs == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, -1)
	# 修改窗口：已生效的政策在冷却期内不许改参数，否则「冷却」可以被「改参数」绕过，
	# 玩家每季免费重调一次税率，INV-098 的成本约束形同虚设。
	if enabled[p] == 1 and q < cooldown_until_q[p]:
		_blocked_reason[p] = JWUnits.BlockedReason.COOLDOWN
		return JWResult.Reject.POLICY_COOLDOWN

	# 先整体校验再整体写入：任一项越界即全部不改（不允许「改一半」的部分生效）。
	for j: int in JWIds.POLICY_PARAM_STRIDE:
		var idx: int = JWIds.idx_policy_param(p, j)
		var rng: Vector2i = defs.param_range(p, j)
		var v: int = pending_params[idx]
		if v < rng.x or v > rng.y:
			return JWResult.Reject.PARAM_RANGE
	# R-PARAMS-01：已在执行的政策改参数不当季生效——按 enact_to_effect 时滞排期，
	# 到期季 S02 开头由 commit_due_params 落到 params（与新通过政策同一条时滞纪律，INV-095/098）。
	# 排期期间再次修改以最后一次为准（重新排期）。尚未执行的政策照旧直接写入（它的效应另由生效季闸门管）。
	if enabled[p] == 1 and effective_from_q[p] >= 0 and effective_from_q[p] <= q:
		for j3: int in JWIds.POLICY_PARAM_STRIDE:
			var idx3: int = JWIds.idx_policy_param(p, j3)
			scheduled_params[idx3] = pending_params[idx3]
		params_due_q[p] = q + maxi(1, defs.lag_enact_to_effect_q[p])
		return JWResult.OK
	for j: int in JWIds.POLICY_PARAM_STRIDE:
		var idx2: int = JWIds.idx_policy_param(p, j)
		var v2: int = pending_params[idx2]
		params_ppm[idx2] = v2
		params_uu[idx2] = v2
	_sync_region_mask(p, defs)
	return JWResult.OK


## R-PSLOT-01：region_mask 取自类型为 mask 的玩家参数槽（没有该旋钮的政策保持原值）。
## 原先没有任何调用方写 region_mask，所有按地区落地的效果都退化为「全国」（掩码 0 被当作全选）。
func _sync_region_mask(p: int, defs: JWPolicyDef) -> void:
	if defs == null or defs.mask_slot.size() != JWUnits.POLICY_N:
		return
	var ms: int = defs.mask_slot[p]
	if ms < 0:
		return
	region_mask[p] = params_ppm[JWIds.idx_policy_param(p, ms)] & JWUnits.REGION_MASK_ALL


## R-PSLOT-01：加载期对全部政策按当前参数槽同步一次 region_mask。
## 步骤：LOAD
## 前置：params_ppm 已装填默认值
## 后置：有 mask 旋钮的政策 region_mask == 该槽 & 15
## 不变量：无
## 失败：无
func sync_all_region_masks(defs: JWPolicyDef) -> void:
	for p: int in JWUnits.POLICY_N:
		_sync_region_mask(p, defs)


## R-PARAMS-01：把到期的排期参数落到 params（每季 S02 开头、受理命令之前调用一次）。
## 步骤：S02 §2.1 之前
## 前置：无
## 后置：params_due_q[p] <= q 的政策 params == scheduled_params，其 params_due_q 置 −1
## 不变量：INV-095（参数只在生效季起作用）
## 失败：无
func commit_due_params(q: int, defs: JWPolicyDef = null) -> void:
	for p: int in JWUnits.POLICY_N:
		var due: int = params_due_q[p]
		if due < 0 or q < due:
			continue
		for j: int in JWIds.POLICY_PARAM_STRIDE:
			var idx: int = JWIds.idx_policy_param(p, j)
			params_ppm[idx] = scheduled_params[idx]
			params_uu[idx] = scheduled_params[idx]
		params_due_q[p] = -1
		_sync_region_mask(p, defs)


## 政策效应的统一闸门：任何政策效应函数都必须先过这一关。
## 步骤：全部八步
## 前置：无
## 后置：q < effective_from_q 或 enabled == 0 → 返回 false（零效应）
## 不变量：INV-095（这是它的唯一实现点；静态检查：任何读 policy params 的地方
##          必须在同一函数内先调用本函数）
## 失败：无
func is_effective(p: int, q: int) -> bool:
	if not _valid_policy(p):
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, JWUnits.POLICY_N)
		return false
	if enabled[p] != 1:
		return false
	var ef: int = effective_from_q[p]
	if ef < 0:
		return false
	return q >= ef


## 读取生效中的 ppm 参数；未生效时恒返回 0（零效应）。
## 步骤：全部八步
## 前置：p ∈ [0,12)，j ∈ [0,4)
## 后置：不改状态
## 不变量：INV-095
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func effective_param_ppm(p: int, j: int, q: int) -> int:
	if not _valid_policy(p) or j < 0 or j >= JWIds.POLICY_PARAM_STRIDE:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, j)
		return 0
	if not is_effective(p, q):
		return 0
	return params_ppm[JWIds.idx_policy_param(p, j)]


## S04 §4.2：法定转移（P03 等）的应付清单。
## 步骤：S04 §4.2 的 statutory_transfers 档
## 前置：eligible_persons 按 P03 的 eligibility/duration 判定
## 后置：out_due[g] = eligible × benefit_per_person；不得少算人数装作没人符合资格
## 不变量：INV-095、INV-003
## 失败：无（现金不足由 treasury 走部分支付 + 欠付）
##
## 资格口径：作用地区内、劳动年龄、未就业的全部人口。
## 「少算人数装作没人符合资格」是被点名禁止的，所以两处默认都取**不少算**的方向：
## region_mask == 0 视为全国（而不是无人），失业人数取 labor_force − employed 的全额。
func transfer_due_into(out_payee_agent: PackedInt64Array, out_due: PackedInt64Array,
		pop: JWPopulation, labor: JWLaborMarket, defs: JWPolicyDef,
		q: int, params: PackedInt64Array) -> int:
	if out_payee_agent.size() != JWUnits.GROUP or out_due.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				out_due.size(), JWUnits.GROUP)
	if pop == null or labor == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, -1)
	if not _defs_ready(defs):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, -2)
	if params.size() < JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)

	for g: int in JWUnits.GROUP:
		out_payee_agent[g] = JWIds.agent_of_group(g)
		out_due[g] = 0

	# 替代率的计价基准：法定最低工资（μU/人/季）。docs/12 §4.2 写的是 ref_wage_uu，
	# 而本函数的冻结签名里没有 JWPricing；param.wage_floor_uu 是唯一到得了这里的工资口径，
	# 且法定转移对标法定工资下限本身就是一致的口径。
	var ref_wage: int = params[JWUnits.Param.WAGE_FLOOR_UU]
	if ref_wage <= 0:
		return JWResult.OK

	for p: int in JWUnits.POLICY_N:
		if defs.kind[p] != JWPolicyDef.POLICY_KIND_TRANSFER:
			continue
		# INV-095 的闸门：未生效的转移政策一分钱都不产生应付额。
		if not is_effective(p, q):
			continue
		var replacement_ppm: int = params_ppm[
				JWIds.idx_policy_param(p, JWPolicyDef.PARAM_SLOT_PRIMARY)]
		if replacement_ppm <= 0:
			continue
		var benefit: int = JWMath.mul_ppm(ref_wage, replacement_ppm)
		if benefit <= 0:
			continue
		var mask: int = region_mask[p] & JWUnits.REGION_MASK_ALL
		if mask == 0:
			mask = JWUnits.REGION_MASK_ALL
		for g: int in JWUnits.GROUP:
			if JWIds.age_of_group(g) != JWUnits.Age.WORKING:
				continue
			if ((mask >> JWIds.region_of_group(g)) & 1) == 0:
				continue
			var unemployed: int = pop.labor_force(g) - pop.employed_total(g)
			if unemployed <= 0:
				continue
			out_due[g] += JWMath.mul(unemployed, benefit)
			JWMath.check_amount(out_due[g])
	return JWResult.OK


## S04 §4.3：补助的幂等发放（恶意玩家测试 ADV-01 的主防线）。
## 步骤：S04 §4.3
## 前置：claim_key = hash64(policy_id, beneficiary_cell, q, qualifying_investment_id)；
##       前置是「已发生的实际投资」（上季 flow.cell.investment_uu > 0 且已付款），
##       不是「政策已开启」
## 后置：同键至多付一次；台账只增不减，政策退出也不清零；关停再开启不补发历史季
## 不变量：INV-097（幂等）、INV-096（budget_spent <= budget_committed）、INV-113（补助不进 GDP）
## 失败：重复申领 → 记 duplicate_claim_blocked 并跳过（不是故障）；
##       台账写满 → Fault.INDEX_OUT_OF_RANGE（CLAIM_CAP 由 40/120 季规模上界推出）
func pay_subsidy(p: int, cell: int, requested_uu: int, qualifying_event_id: int,
		investment_prev_uu: int, defs: JWPolicyDef, treasury: JWTreasury,
		ledger: JWLedger, accounts: JWAccount, q: int) -> int:
	if not _valid_policy(p) or cell < 0 or cell >= JWUnits.CELL:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, cell)
	if treasury == null or ledger == null or accounts == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, -1)
	if not _defs_ready(defs):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, -2)
	# 只有 subsidy 类政策能走补助台账：别的 kind 走到这里说明调用方接错了机制
	# （mech.investment_subsidy 只登记在补助类政策上，V-PD-08）。
	if defs.kind[p] != JWPolicyDef.POLICY_KIND_SUBSIDY:
		return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, p, defs.kind[p])

	# 两道前置，缺一不可：政策已生效（INV-095），且**上季确有已付款的实际投资**。
	# 顺序上把投资前置写在这里而不是调用方，是因为 ADV-01 攻击的正是「开了政策就领钱」。
	if not is_effective(p, q):
		_blocked_reason[p] = JWUnits.BlockedReason.PRECONDITION
		return JWResult.Reject.PRECONDITION
	if investment_prev_uu <= 0:
		return JWResult.Reject.PRECONDITION
	if requested_uu <= 0:
		return JWResult.Reject.PRECONDITION

	var key: int = claim_key_of(p, cell, q, qualifying_event_id)
	if key == 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, qualifying_event_id, 0)
	for i: int in _claim_count:
		if claim_key[i] == key:
			# duplicate_claim_blocked：拒绝并留痕，不是故障（docs/12 §4.3 的失败行为表）。
			return JWResult.Reject.OVERPAY

	# INV-096：已支出不得超过已预留，超了必须重新审核，不得就地放行。
	# 额度取两道闸的较小者：累计口径（budget_committed − budget_spent，INV-096 原文），以及
	# **本次开启**口径（本次签入的承诺 − 本次开启以来的实付）。上一次开启的余额已在撤销时从
	# committed_memo 释放，只按累计口径放行的话，重开之后就能花掉一笔已不在承诺里的钱，
	# 撤销时的违约金基数也随之变成负数。首次开启时两道闸逐位相同。
	var remaining: int = budget_committed[p] - budget_spent[p]
	var remaining_cur: int = _commit_of_current_enactment(p, defs) - _spent_in_current_enactment(p)
	if remaining_cur < remaining:
		remaining = remaining_cur
	if remaining <= 0:
		_blocked_reason[p] = JWUnits.BlockedReason.BUDGET
		return JWResult.Reject.BUDGET_INSUFFICIENT

	var amount: int = requested_uu
	if amount > remaining:
		amount = remaining
	# 补助不得超过它所补的那笔实际投资：否则「补助」就成了与投资无关的现金发放。
	if amount > investment_prev_uu:
		amount = investment_prev_uu
	JWMath.check_amount(amount)
	if amount <= 0:
		return JWResult.Reject.BUDGET_INSUFFICIENT

	if _claim_count >= CLAIM_CAP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, _claim_count, CLAIM_CAP)

	# 现金不足：登记欠付，**不写台账**——本季本键未获支付，下一季是另一个键，
	# 不会因为这次欠付而永久失去领取资格，也不会凭空补发。
	if accounts.cash_of(JWIds.AGENT_GOV) < amount:
		treasury.add_arrears(JWIds.agent_of_cell(cell), amount, JWUnits.PayLine.SUBSIDIES)
		return JWResult.Reject.NO_FUNDING

	var rc: int = ledger.post(JWUnits.Kind.SUBSIDY,
			JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH),
			JWIds.idx_account(JWIds.agent_of_cell(cell), JWIds.ACC_CASH),
			amount, 0, -1, CAUSE_POLICY_BASE + p, p)
	if rc != JWResult.OK:
		treasury.add_arrears(JWIds.agent_of_cell(cell), amount, JWUnits.PayLine.SUBSIDIES)
		return rc

	budget_spent[p] += amount
	if budget_spent[p] > budget_committed[p]:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE,
				budget_spent[p], budget_committed[p])
	# 补助实付**不**冲减 committed_memo：本政策在 memo 里的份额（本次开启签入的全额）由撤销时
	# try_repeal 整笔释放。若要按 INV-032 的「履约付款 −」在这里逐笔冲减，撤销就只能释放未执行部分——
	# 两处必须一起改（见返回的 interface_requests），只改一处会让 memo 被多减或永远挂着已执行额。
	claim_key[_claim_count] = key
	claim_amount[_claim_count] = amount
	_claim_count += 1
	# flow.gov.pay_subsidies_uu[cell] 与 primary_paid 由调用方（S04 的补助档）按实付额经
	# treasury.record_line_payment 一次登记；这里再直接写一遍 f_pay_subsidies 就是同一笔记两次。
	return JWResult.OK


## 补助台账键：政策、受益 cell、季、合格事件的**无碰撞位打包**。
## 步骤：S04 §4.3
## 前置：p ∈ [0,12)；cell ∈ [0,16)；q ∈ [0, 4096)；event_id ∈ [0, 2^26)
## 后置：返回值恒非 0，且四元组 → 键是单射
## 不变量：INV-097
## 失败：任一分量越界 → 返回 0，调用方登记 INDEX_OUT_OF_RANGE
static func claim_key_of(p: int, cell: int, q: int, event_id: int) -> int:
	if p < 0 or p >= (1 << CLAIM_KEY_POLICY_BITS):
		return 0
	if cell < 0 or cell >= (1 << CLAIM_KEY_CELL_BITS):
		return 0
	if q < 0 or q >= (1 << CLAIM_KEY_Q_BITS):
		return 0
	if event_id < 0 or event_id >= (1 << CLAIM_KEY_EVENT_BITS):
		return 0
	return (1 << CLAIM_KEY_TAG_SHIFT) | (event_id << CLAIM_KEY_EVENT_SHIFT) \
			| (q << CLAIM_KEY_Q_SHIFT) | (cell << CLAIM_KEY_CELL_SHIFT) | p


## S07：把生效政策的效果落到白名单落点（一切能力类只能落在 *_pending_*）。
## 步骤：S07 §7.1 之后
## 前置：is_effective(p, q) 为真
## 后置：按 effect_target 调 JWCapital.add_pending / JWTreasury.tax_capacity /
##       JWPolitics.admin_capacity / JWPopulation.education_cohort
## 不变量：INV-091、INV-095、V-PD-10/11
## 失败：落点不在白名单 → Fault.WRITE_OUT_OF_SCOPE
##
## 两条不写的规则，都是为了不重复发放：
## 1) 项目类政策在这里**完全跳过**——它的产能由 JWProjectQueue 在完工时写 pending
##    （docs/12 §7.1：`目标数组的 *_pending_* += capacity_effect_uqs_per_q`；该值由 S02 入队时
##    从 defs.effect_magnitude 抄进 state.project.capacity_effect_uqs_per_q，docs/10）。
##    在这里再落一次就是凭空翻倍：docs/30 的三条 P0 场景断言会同时不成立——
##    `T-S-P04-PAY-NO-PROGRESS`（施工进度恒 0 ⇒ grid_capacity_pending 增量 == 0）、
##    `T-S-P04-NO-EARLY-COMMISSION`（交付未齐 ⇒ pending 增量 == 0）、`T-S-D-07` ⑤（取消 ⇒ 增量 == 0），
##    而 `T-S-P04-CHAIN` ④⑤ 的 10 000 000 会变成 20 000 000。
## 2) 其余政策只落**一次**，落点季 == effective_from_q + commission_delay_q。效果是存量性的：
##    每季重复加一遍会让一项政策在 40 季里发放 40 倍效果，而退出时又按「已交付资产保留」不回收；
##    税收能力／行政能力那类落点更会在几季内被推到 1e6 的天花板。
##    落点季为什么再加 commission_delay_q：V-PD-04 要求每个政策 `commission_delay_q >= 1`，
##    docs/30 `T-U-C-02` 写明这条门槛的用途是「政策不得绕过『完工资产下一季才供能』的时滞」
##    （INV-091）。项目类政策的这段时滞由施工与交付进度天然给出；非项目类政策不进项目队列，
##    唯一能兑现该时滞的地方就是本函数的落点季。commission_delay_q < 1 的残缺定义按 1 处理，
##    宁可晚一季也不给任何政策提前供能的机会。
func apply_effects(defs: JWPolicyDef, capital: JWCapital, treasury: JWTreasury,
		politics: JWPolitics, pop: JWPopulation, q: int,
		params: PackedInt64Array = PackedInt64Array(), diag: JWDiagnostics = null) -> int:
	if capital == null or treasury == null or politics == null or pop == null:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, -1)
	if not _defs_ready(defs):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, -2)
	var first_fault: int = JWResult.OK
	for p: int in JWUnits.POLICY_N:
		if not is_effective(p, q):
			continue
		if defs.kind[p] == JWPolicyDef.POLICY_KIND_PROJECT:
			continue
		# R-P12-01：采购透明度（落点 admin_capacity）在生效期内**逐季**按 E1—E16 更新，不只在落点季落一次。
		if defs.effect_target_of(p) == JWPolicyDef.TARGET_POLITICS_ADMIN_CAPACITY_PPM \
				and params.size() == JWUnits.PARAM_N and defs.disclosure_slot[p] >= 0:
			var rc_t: int = _apply_transparency(p, defs, capital, treasury, politics, pop, q, params, diag)
			if rc_t != JWResult.OK and first_fault == JWResult.OK:
				first_fault = rc_t
		if q != _effect_landing_q(p, defs):
			continue
		# R-POLSPEND-01：能力类与行政类政策在效果落点季投运，其每季运行费进入长期运行费义务
		# （与项目完工时 asset_commissioning 同一口径；退出不回收——已交付的资产与人员照常要养）。
		var kd: int = defs.kind[p]
		if (kd == JWPolicyDef.POLICY_KIND_CAPACITY or kd == JWPolicyDef.POLICY_KIND_ADMIN) \
				and defs.opex_per_q_uu[p] > 0:
			treasury.service_opex_committed = JWMath.check_amount(
					treasury.service_opex_committed + defs.opex_per_q_uu[p])
			opex_landed[p] = JWMath.check_amount(opex_landed[p] + defs.opex_per_q_uu[p])
		var magnitude: int = defs.effect_magnitude[p]
		if magnitude == 0:
			continue
		var rc: int = _apply_one_effect(p, defs, capital, treasury, politics, pop, magnitude, params)
		if rc != JWResult.OK and first_fault == JWResult.OK:
			first_fault = rc
	return first_fault


## R-P11-02 / R-P12-02：已投运行政类效果的维持与衰减（S07，紧随 apply_effects）。
## P11（落点征收能力）：建成水平高于地板时——义务在身（执行中且已投运）按中州公共服务到位率判断供，
##   否则（未投运的重开、退出后）按完全断供；断供 ⇒ tax = max(地板, tax − decay × shortfall)，
##   足额 ⇒ tax = min(建成水平, tax + recover)。恢复慢于下降（加载期校验）。
## P12（落点行政能力，采购透明）：撤回后 decay_q 季内（从撤回季起）每季
##   admin −= clamp(mul_ppm(decay_ppm, admin), 0, step_max)；撤回时尚未生效则没有回落；期满静默。
##   回落期按撤回季 exit_pending_q + decay_q 计算（exit_pending_q 保持「撤回季」的原义）。
## 步骤：S07（apply_effects 之后、可用率更新之前）
## 前置：本季 funding_ratio 已写（S04）；params 长 PARAM_N
## 后置：只写 treasury.tax_capacity_ppm 与 politics.admin_capacity_ppm
## 不变量：INV-102 同构（只降能力、不删资产）、INV-122 同构（恢复慢于下降）、INV-125
## 失败：写入失败 → 其错误码
func upkeep_effects(defs: JWPolicyDef, capital: JWCapital, treasury: JWTreasury,
		politics: JWPolitics, q: int, params: PackedInt64Array) -> int:
	if defs == null or capital == null or treasury == null or politics == null \
			or params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, params.size())
	if not _defs_ready(defs):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, 0, -2)
	for p: int in JWUnits.POLICY_N:
		var tgt: int = defs.effect_target_of(p)
		var rc: int = JWResult.OK
		if tgt == JWPolicyDef.TARGET_GOV_TAX_CAPACITY_PPM and defs.staff_slot[p] >= 0:
			rc = _tax_capacity_upkeep(p, capital, treasury, params)
		elif tgt == JWPolicyDef.TARGET_POLITICS_ADMIN_CAPACITY_PPM and defs.disclosure_slot[p] >= 0:
			rc = _transparency_exit_decay(p, politics, q, params)
		if rc != JWResult.OK:
			return rc
	return JWResult.OK


func _tax_capacity_upkeep(p: int, capital: JWCapital, treasury: JWTreasury, params: PackedInt64Array) -> int:
	var floor_ppm: int = params[JWUnits.Param.P11_CAPACITY_FLOOR_PPM]
	var built: int = treasury.tax_capacity_built_ppm
	if built <= floor_ppm:
		return JWResult.OK
	var shortfall: int = JWUnits.PPM
	if enabled[p] == 1 and opex_landed[p] > 0:
		# 首版没有独立的税务机关主体：运行费与中州公共服务共用拨款到位率（policy_P11.json coupling_note_zh，OQ-248）。
		shortfall = JWMath.clamp_i(JWUnits.PPM - capital.f_pub_funding_ratio[JWUnits.Region.ZHONGZHOU],
				0, JWUnits.PPM)
	var cur: int = treasury.tax_capacity_ppm
	if shortfall > 0:
		# rounding: floor, reason=衰减量只取整一次（M1）
		cur = maxi(floor_ppm, cur - JWMath.mul_ppm(params[JWUnits.Param.P11_CAPACITY_DECAY_PPM], shortfall))
	else:
		cur = mini(built, cur + params[JWUnits.Param.P11_CAPACITY_RECOVER_PPM])
	treasury.tax_capacity_ppm = JWMath.clamp_i(cur, 0, JWUnits.PPM)
	return JWResult.OK


func _transparency_exit_decay(p: int, politics: JWPolitics, q: int, params: PackedInt64Array) -> int:
	if enabled[p] == 1 or exit_pending_q[p] < 0:
		return JWResult.OK
	var q_exit: int = exit_pending_q[p]
	if q < q_exit or q >= q_exit + params[JWUnits.Param.PROC_TRANSPARENCY_DECAY_Q]:
		return JWResult.OK
	if effective_from_q[p] > q_exit:
		return JWResult.OK
	var admin: int = politics.admin_capacity_ppm
	# rounding: floor, reason=回落量只取整一次（M1）
	var drop: int = JWMath.clamp_i(JWMath.mul_ppm(params[JWUnits.Param.PROC_TRANSPARENCY_DECAY_PPM], admin),
			0, params[JWUnits.Param.PROC_TRANSPARENCY_STEP_MAX_PPM])
	return politics.set_admin_capacity(JWMath.clamp_i(admin - drop, 0, JWUnits.PPM))


## R-P10-01：带「每季拨款」旋钮的政策，其并入运行费义务的部分超出拨款的差额（μU/季，≥ 0）。
## 拨款 = 执行中取 grant 槽的当前值，未执行（含退出之后）取 0——退出只是不再拨款，义务仍在
## （policy_P10.json exit_rule），可用率由此按断供规则衰减。
## 步骤：S04（JWTurnRunner._pay_service_opex）
## 前置：defs 已装载
## 后置：不改状态
## 失败：无（无拨款槽或尚未投运返回 0）
func grant_shortfall(p: int, defs: JWPolicyDef) -> int:
	if p < 0 or p >= JWUnits.POLICY_N or defs == null or p >= defs.grant_slot.size():
		return 0
	var gs: int = defs.grant_slot[p]
	if gs < 0 or opex_landed[p] <= 0:
		return 0
	var grant: int = 0
	if enabled[p] == 1:
		grant = maxi(params_ppm[JWIds.idx_policy_param(p, gs)], 0)
	return maxi(opex_landed[p] - grant, 0)


## R-P11-01：征收能力增量 = min(人员上限, 系统上限) × 覆盖率，再以上限夹住（policy_P11.json /effect/delta_rule_zh）。
## 人员上限 = mul_ppm(param.p11_staff_gain_full_ppm, staffing_scale_ppm)；系统上限同理；
## 覆盖率 = Σ_{r ∈ region_mask} param.p11_region_base_share_ppm[r]（掩码 0 == 全国）。
## 步骤：S07（落点季一次）
## 前置：params 长 PARAM_N；defs 的人员与系统槽位已解析
## 后置：返回本次增量（>= 0）；不改状态
## 不变量：INV-095
## 失败：无
func _p11_gain(p: int, defs: JWPolicyDef, params: PackedInt64Array) -> int:
	var staff: int = params_ppm[JWIds.idx_policy_param(p, defs.staff_slot[p])]
	var system: int = params_ppm[JWIds.idx_policy_param(p, defs.system_slot[p])]
	# rounding: floor ×2，reason=两侧各自只取整一次，取 min 不相乘（M2）
	var staff_cap: int = JWMath.mul_ppm(params[JWUnits.Param.P11_STAFF_GAIN_FULL_PPM], staff)
	var system_cap: int = JWMath.mul_ppm(params[JWUnits.Param.P11_SYSTEM_GAIN_FULL_PPM], system)
	var full: int = mini(staff_cap, system_cap)
	var mask: int = region_mask[p] & JWUnits.REGION_MASK_ALL
	if mask == 0:
		mask = JWUnits.REGION_MASK_ALL
	var coverage: int = 0
	for r: int in JWUnits.R:
		if ((mask >> r) & 1) == 1:
			coverage += params[JWUnits.Param.P11_REGION_BASE_SHARE_PPM_0 + r]
	coverage = JWMath.clamp_i(coverage, 0, JWUnits.PPM)
	# rounding: floor，reason=覆盖率折算只取整一次
	return maxi(0, JWMath.mul_ppm(full, coverage))


## R-P12-01：采购透明度对行政执行能力的逐季更新（policy_P12.json /effect/_note_formula_steps E1—E16）。
## E17：diag 非空时把 8 个中间量逐项写进 log.explanations（kind = accounted，cause = EXPLAIN_P12_BASE + k）。
## 步骤：S07（生效期内每季）
## 前置：is_effective(p, q)；params 长 PARAM_N；三个杠杆槽位已解析
## 后置：politics.admin_capacity_ppm += clamp(gain − load, −step_max, step_max)，并夹在 [0, 1e6]
## 不变量：INV-095、INV-125（只写 admin_capacity_ppm）
## 失败：写入失败 → 其错误码
func _apply_transparency(p: int, defs: JWPolicyDef, capital: JWCapital, treasury: JWTreasury,
		politics: JWPolitics, pop: JWPopulation, q: int, params: PackedInt64Array,
		diag: JWDiagnostics = null) -> int:
	var disclosure: int = params_ppm[JWIds.idx_policy_param(p, defs.disclosure_slot[p])]
	var audit: int = 0
	if defs.audit_slot[p] >= 0:
		audit = params_ppm[JWIds.idx_policy_param(p, defs.audit_slot[p])]
	var appeal: int = 0
	if defs.appeal_slot[p] >= 0:
		appeal = params_ppm[JWIds.idx_policy_param(p, defs.appeal_slot[p])]
	# E1 披露门槛。
	var threshold: int = JWMath.mul_ppm(params[JWUnits.Param.PROCUREMENT_DISCLOSURE_REF_UU], disclosure)
	# E2—E3 支出元素：项目款、采购、补助、运行费，逐元素判是否达到门槛。
	var total: int = 0
	var covered: int = 0
	for e: int in treasury.f_pay_project:
		total += e
		if e >= threshold:
			covered += e
	total += treasury.f_pay_procurement
	if treasury.f_pay_procurement >= threshold:
		covered += treasury.f_pay_procurement
	for e2: int in treasury.f_pay_subsidies:
		total += e2
		if e2 >= threshold:
			covered += e2
	for e3: int in treasury.f_pay_opex:
		total += e3
		if e3 >= threshold:
			covered += e3
	# E4 覆盖率。
	var coverage: int = 0
	if total > 0:
		# rounding: floor，reason=覆盖率宁低勿高
		coverage = JWMath.clamp_i(JWMath.mul_div_floor(covered, JWUnits.PPM, total), 0, JWUnits.PPM)
	# E5 运行费到位率与 E11 可用率（按地区人口加权）。
	var pop_sum: int = 0
	var ok_num: int = 0
	var av_num: int = 0
	for r: int in JWUnits.R:
		var pr: int = pop.region_population(r)
		pop_sum += pr
		ok_num += JWMath.mul(capital.f_pub_funding_ratio[r], pr)
		av_num += JWMath.mul(capital.pub_availability[r], pr)
	var opex_ok: int = JWMath.floor_div(ok_num, maxi(pop_sum, 1))
	var avail_nat: int = JWMath.floor_div(av_num, maxi(pop_sum, 1))
	# E6 审核产能；E7 实际审核额；E8 实际审核比例。
	var review_cap: int = JWMath.mul_ppm_2(defs.opex_per_q_uu[p], opex_ok,
			params[JWUnits.Param.PROC_REVIEW_UU_PER_OPEX_PPM])
	var audited: int = mini(JWMath.mul_ppm(covered, audit), review_cap)
	var audit_real: int = 0
	if covered > 0:
		audit_real = JWMath.clamp_i(JWMath.mul_div_floor(audited, JWUnits.PPM, covered), 0, JWUnits.PPM)
	# E9 建设进度；E10 爬坡。
	var progress: int = JWMath.clamp_i(JWMath.mul_div_floor(budget_spent[p], JWUnits.PPM,
			maxi(budget_committed[p], 1)), 0, JWUnits.PPM)
	var ramp_total: int = params[JWUnits.Param.PROC_TRANSPARENCY_RAMP_Q] + JWMath.floor_div(appeal, 500000)
	var ramp: int = JWMath.clamp_i(JWMath.mul_div_floor(q - effective_from_q[p] + 1, JWUnits.PPM,
			maxi(ramp_total, 1)), 0, JWUnits.PPM)
	# E12 有效审核强度（两个 ppm 先合并再取整一次，M2）。
	var eff_a: int = JWMath.mul_ppm_2(coverage, audit_real, avail_nat)
	var effective_audit: int = JWMath.mul_ppm_2(eff_a, progress, ramp)
	# E13 流程负荷；E14 收益；E15 净变动。
	var load: int = JWMath.mul_ppm(params[JWUnits.Param.PROC_TRANSPARENCY_LOAD_PPM], coverage) \
			+ JWMath.mul_ppm_2(params[JWUnits.Param.PROC_TRANSPARENCY_APPEAL_LOAD_PPM], appeal, coverage)
	var gain: int = JWMath.mul_ppm(params[JWUnits.Param.PROC_TRANSPARENCY_GAIN_PPM], effective_audit)
	var step_max: int = params[JWUnits.Param.PROC_TRANSPARENCY_STEP_MAX_PPM]
	var delta: int = JWMath.clamp_i(gain - load, -step_max, step_max)
	# E17 解释：逐项写日志（只写日志，不写任何状态）。
	if diag != null:
		var vals: PackedInt64Array = PackedInt64Array([coverage, audit_real, progress, ramp, avail_nat, load, gain, delta])
		for k: int in vals.size():
			diag.add_explanation(JWUnits.ExplainKind.ACCOUNTED, p, EXPLAIN_P12_BASE + k, vals[k], 0, 0, q)
	# E16 落账。
	return politics.set_admin_capacity(JWMath.clamp_i(politics.admin_capacity_ppm + delta, 0, JWUnits.PPM))


## R-POLSPEND-01：能力类与行政类政策本季的项目期应付额（μU）。
## 项目期 = 从生效季起 planned_quarters 季，每季 cost.per_quarter_uu（内容层 V-PD-03 保证
## per_quarter × planned_quarters == one_off，故项目期满恰好花完本次开启签入的承诺）。
## 步骤：S04（公共服务运行费档之前）
## 前置：defs 就绪
## 后置：不改状态
## 不变量：INV-095（未生效零支出）、INV-096（累计不超过承诺，由 record_program_spend 再判）
## 失败：无
func program_due(p: int, defs: JWPolicyDef, q: int) -> int:
	if not _valid_policy(p) or not _defs_ready(defs):
		return 0
	var k: int = defs.kind[p]
	if k != JWPolicyDef.POLICY_KIND_CAPACITY and k != JWPolicyDef.POLICY_KIND_ADMIN:
		return 0
	if not in_program(p, defs, q):
		return 0
	var due: int = defs.cost_per_quarter(p)
	var room: int = budget_committed[p] - budget_spent[p]
	if room < due:
		due = room
	return maxi(0, due)


## R-POLSPEND-01：本季是否处于政策的项目期（生效且 q < 生效季 + planned_quarters）。
## 步骤：S04、S07
## 前置：defs 就绪
## 后置：不改状态
## 不变量：INV-095
## 失败：无
func in_program(p: int, defs: JWPolicyDef, q: int) -> bool:
	if not _valid_policy(p) or not _defs_ready(defs):
		return false
	if not is_effective(p, q):
		return false
	return q < effective_from_q[p] + defs.planned_quarters[p]


## R-POLSPEND-01：登记项目期实付（进 budget_spent，INV-096）。
## 步骤：S04
## 前置：amount >= 0
## 后置：budget_spent[p] += amount，且 <= budget_committed[p]
## 不变量：INV-096
## 失败：越过承诺 → LEDGER_IMBALANCE
func record_program_spend(p: int, amount: int) -> int:
	if not _valid_policy(p) or amount < 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, amount)
	budget_spent[p] += amount
	if budget_spent[p] > budget_committed[p]:
		return JWResult.raise_fault(JWResult.Fault.LEDGER_IMBALANCE,
				budget_spent[p], budget_committed[p])
	return JWResult.OK


## 一条政策的效果落点季：生效季再推 commission_delay_q 季（至少 1 季）。
## 步骤：S07
## 前置：defs 已过 _defs_ready（commission_delay_q 长度 == POLICY_N）
## 后置：不改状态；返回值即 apply_effects 唯一允许落地的那一季
## 不变量：INV-091（任何政策都不得绕过投运时滞）、INV-095
## 失败：无
func _effect_landing_q(p: int, defs: JWPolicyDef) -> int:
	var delay: int = defs.commission_delay_q[p]
	if delay < 1:
		# V-PD-04 在加载期就该拦下 < 1 的定义；运行期再兜一次，缺省取最小的一季。
		delay = 1
	return effective_from_q[p] + delay


## 单条政策效果的落点分派。
## 步骤：S07
## 前置：p 已过 is_effective 闸门且不是项目类
## 后置：按落点码写对应的 *_pending_* 或能力标量
## 不变量：INV-091、V-PD-10/11
## 失败：落点码越界或本版无法解析落点 → Fault.WRITE_OUT_OF_SCOPE
func _apply_one_effect(p: int, defs: JWPolicyDef, capital: JWCapital, treasury: JWTreasury,
		politics: JWPolitics, pop: JWPopulation, magnitude: int,
		params: PackedInt64Array = PackedInt64Array()) -> int:
	var target: int = defs.effect_target_of(p)
	if target < 0 or target >= JWPolicyDef.TARGET_N:
		return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, p, target)
	match target:
		JWPolicyDef.TARGET_POLICY_PARAMS_PPM, JWPolicyDef.TARGET_POLICY_PARAMS_UU:
			# 落点就是政策自己的参数数组，而参数由玩家在 S02 经 apply_pending_params 写定
			# （区间已按 valid_range 校验）。在这里再按 effect_magnitude 覆盖一次，
			# 等于把玩家设定的税率／替代率抹掉——那不是「落点」，是越权改档。
			return JWResult.OK
		JWPolicyDef.TARGET_GOV_TAX_CAPACITY_PPM:
			# R-P11-01：有参数与槽位时按人员/系统规模与覆盖率缩放，并以上限夹住；否则退回满额增量（旧夹具口径）。
			if params.size() == JWUnits.PARAM_N and defs.staff_slot[p] >= 0 and defs.system_slot[p] >= 0:
				var ceiling: int = params[JWUnits.Param.P11_TAX_CAPACITY_CEILING_PPM]
				var gain: int = _p11_gain(p, defs, params)
				treasury.tax_capacity_ppm = JWMath.clamp_i(
						mini(treasury.tax_capacity_ppm + gain, maxi(ceiling, treasury.tax_capacity_ppm)),
						0, JWUnits.PPM)
				# R-P11-02：建成水平只升不降（断供后回升以它为上限）。
				treasury.tax_capacity_built_ppm = maxi(treasury.tax_capacity_built_ppm, treasury.tax_capacity_ppm)
				return JWResult.OK
			treasury.tax_capacity_ppm = JWMath.clamp_i(
					treasury.tax_capacity_ppm + magnitude, 0, JWUnits.PPM)
			return JWResult.OK
		JWPolicyDef.TARGET_POLITICS_ADMIN_CAPACITY_PPM:
			return politics.set_admin_capacity(JWMath.clamp_i(
					politics.admin_capacity_ppm + magnitude, 0, JWUnits.PPM))
		JWPolicyDef.TARGET_GROUP_EDUCATION_COHORT:
			# R-P05-01：培训席位不在这里一次性落地——它按项目期逐季经 JWPopulation.update_education
			# 入队（教师 × 师生比的硬上限、技能档与培训滞后都在那里判，ADV-03）。这里直接入队会绕过上限。
			return JWResult.OK
		JWPolicyDef.TARGET_CELL_CAPACITY_PENDING:
			# 运行期 SoA 没有部门选择列（content 的 capacity_unit_ref 没有落成数组），
			# 无法确定 16 个 cell 中的哪一个。宁可显式失败，也不猜一个部门写进去。
			return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, p, target)
	# 其余落点都按地区（或地区对应的公共服务单元）分派到 JWCapital。
	return _apply_region_effect(p, capital, target, magnitude)


## 按 region_mask 把一条效果落到各地区（或各地区的公共服务单元）。
## 步骤：S07
## 前置：target 是 JWCapital.add_pending 受理的落点码
## 后置：强度量逐地区取同值；外延量用 split_lr_into 拆分，Σ 精确等于 magnitude
## 不变量：INV-003（拆分精确）、INV-091
## 失败：拆分失败或 add_pending 拒绝 → 返回其错误码
func _apply_region_effect(p: int, capital: JWCapital, target: int, magnitude: int) -> int:
	var mask: int = region_mask[p] & JWUnits.REGION_MASK_ALL
	if mask == 0:
		mask = JWUnits.REGION_MASK_ALL
	if _r_weight.size() != JWUnits.R:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, _r_weight.size(),
				JWUnits.R)
	var is_ratio: bool = JWPolicyDef.TARGET_IS_RATIO[target] == 1
	if is_ratio:
		# 强度量（ppm 指数）：拆分没有意义——半个灌溉指数不是半个灌溉指数。
		var first: int = JWResult.OK
		for r: int in JWUnits.R:
			if ((mask >> r) & 1) == 0:
				continue
			var rc_r: int = capital.add_pending(target, r, magnitude)
			if rc_r != JWResult.OK and first == JWResult.OK:
				first = rc_r
		return first
	for r: int in JWUnits.R:
		_r_weight[r] = 1 if ((mask >> r) & 1) == 1 else 0
		_r_tiebreak[r] = r
	var rc_split: int = JWMath.split_lr_into(magnitude, _r_weight, _r_tiebreak, _r_out)
	if rc_split != JWResult.OK:
		return rc_split
	var first_err: int = JWResult.OK
	for r: int in JWUnits.R:
		if _r_out[r] == 0:
			continue
		var rc: int = capital.add_pending(target, r, _r_out[r])
		if rc != JWResult.OK and first_err == JWResult.OK:
			first_err = rc
	return first_err


## 培训席位落入教育队列（P05 的 cohort_enrollment）。
## 步骤：S07
## 前置：magnitude 是本季新增席位（人）
## 后置：按作用地区内劳动年龄各组人口拆分席位，落在结业槽位 commission_delay_q 上
## 不变量：INV-003（Σ 席位精确等于 magnitude）
## 失败：拆分失败 → 返回其错误码
func _enroll_education(p: int, defs: JWPolicyDef, pop: JWPopulation, magnitude: int) -> int:
	if _g_weight.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, _g_weight.size(),
				JWUnits.GROUP)
	if pop.population.size() != JWUnits.GROUP:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pop.population.size(), JWUnits.GROUP)
	var mask: int = region_mask[p] & JWUnits.REGION_MASK_ALL
	if mask == 0:
		mask = JWUnits.REGION_MASK_ALL
	var total_weight: int = 0
	for g: int in JWUnits.GROUP:
		_g_tiebreak[g] = g
		_g_weight[g] = 0
		if JWIds.age_of_group(g) != JWUnits.Age.WORKING:
			continue
		if ((mask >> JWIds.region_of_group(g)) & 1) == 0:
			continue
		var w: int = pop.population[g]
		if w < 0:
			w = 0
		_g_weight[g] = w
		total_weight += w
	if total_weight == 0:
		# 作用地区内没有劳动年龄人口：席位无处安放。既不静默丢弃，也不升级成故障
		# （人口分布是业务状态，不是结构缺陷）——按前置条件不满足显式返回。
		return JWResult.Reject.PRECONDITION
	var rc_split: int = JWMath.split_lr_into(magnitude, _g_weight, _g_tiebreak, _g_out)
	if rc_split != JWResult.OK:
		return rc_split
	# 结业槽位：政策自己的交付滞后（>= 1，V-PD-04 保证），上限是队列槽位数。
	var slot: int = JWMath.clamp_i(defs.commission_delay_q[p], 1, JWUnits.EDU_SLOT - 1)
	if pop.education_cohort.size() != JWUnits.EDU_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				pop.education_cohort.size(), JWUnits.EDU_N)
	for g: int in JWUnits.GROUP:
		if _g_out[g] == 0:
			continue
		var idx: int = JWIds.idx_edu(g, slot)
		pop.education_cohort[idx] += _g_out[g]
	return JWResult.OK


## 政策参数的只读导出（S06 的税率等要用；导出的是引用，调用方不得写）。
## 步骤：S06 §6.5/§6.6
## 前置：无
## 后置：不改状态
## 不变量：INV-095（调用方必须先调 is_effective 才能使用某项参数）
## 失败：无
func params_ppm_array() -> PackedInt64Array:
	return params_ppm


## 政策参数的只读导出（μU 口径）。
## 步骤：S06 §6.5/§6.6
## 前置：无
## 后置：不改状态
## 不变量：INV-095
## 失败：无
func params_uu_array() -> PackedInt64Array:
	return params_uu


## 无法执行的原因码（政策页必须告诉玩家为什么不能执行）。
## 步骤：S02 末重算
## 前置：无
## 后置：enabled == 0 且玩家可见 ⇒ blocked_reason != NONE
## 不变量：INV-100（且本地化表必须存在对应条目，test_u_blocked_reason_text）
## 失败：无
func blocked_reason(p: int) -> int:
	if not _valid_policy(p):
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, JWUnits.POLICY_N)
		return JWUnits.BlockedReason.NONE
	return _blocked_reason[p]


## 注入 state.bloc.stance_ppm 的只读视图（S02 前由 JWTurnRunner 调用一次）。
## 步骤：S02 之前
## 前置：v.size() == JWUnits.STANCE_N
## 后置：_bloc_stance_view == v；资格链的集团否决判定从此有真实依据
## 不变量：INV-125（本类不持有 JWInterestGroups，只读它导出的数组）
## 失败：长度不符 → INDEX_OUT_OF_RANGE，视图保持原值
func set_bloc_stance_view(v: PackedInt64Array) -> int:
	if v.size() != JWUnits.STANCE_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				v.size(), JWUnits.STANCE_N)
	_bloc_stance_view = v
	return JWResult.OK


## R-ENACT-01：记下政策 p 的参数槽（通过命令被拒时由 restore_params 还原，INV-137）。
## 步骤：S02 §2.1
## 前置：p 合法
## 后置：_param_snap 持有 p 的 pending / ppm / uu 三组参数
## 不变量：INV-137
## 失败：越界 → INDEX_OUT_OF_RANGE
func snapshot_params(p: int) -> int:
	if not _valid_policy(p):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, JWUnits.POLICY_N)
	var n: int = JWIds.POLICY_PARAM_STRIDE
	if _param_snap.size() != 3 * n + 1:
		_param_snap.resize(3 * n + 1)
	for j: int in n:
		var idx: int = JWIds.idx_policy_param(p, j)
		_param_snap[j] = pending_params[idx]
		_param_snap[n + j] = params_ppm[idx]
		_param_snap[2 * n + j] = params_uu[idx]
	_param_snap[3 * n] = region_mask[p]
	return JWResult.OK


## R-ENACT-01：把政策 p 的参数槽还原到 snapshot_params 时的值。
## 步骤：S02 §2.1
## 前置：本季刚对 p 调用过 snapshot_params
## 后置：p 的 pending / ppm / uu 与快照逐位相同
## 不变量：INV-137
## 失败：越界或未快照 → INDEX_OUT_OF_RANGE
func restore_params(p: int) -> int:
	var n: int = JWIds.POLICY_PARAM_STRIDE
	if not _valid_policy(p) or _param_snap.size() != 3 * n + 1:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, _param_snap.size())
	for j: int in n:
		var idx: int = JWIds.idx_policy_param(p, j)
		pending_params[idx] = _param_snap[j]
		params_ppm[idx] = _param_snap[n + j]
		params_uu[idx] = _param_snap[2 * n + j]
	region_mask[p] = _param_snap[3 * n]
	return JWResult.OK


## 注入按域否决的集团位掩码（S02 前由 JWTurnRunner 调用，R-AUTHORITY-01）。
## 步骤：S02 之前
## 前置：v.size() == JWUnits.POLICY_N
## 后置：_bloc_veto_view == v
## 不变量：INV-125
## 失败：长度不符 → INDEX_OUT_OF_RANGE，视图保持原值
func set_bloc_veto_view(v: PackedInt64Array) -> int:
	if v.size() != JWUnits.POLICY_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(), JWUnits.POLICY_N)
	_bloc_veto_view = v
	return JWResult.OK


## 设定政策的作用地区掩码（state.policy.region_mask，写入者 S02）。
## 步骤：S02 §2.1（命令受理，在 try_enact 之前）
## 前置：mask ∈ [0, 15]
## 后置：region_mask[p] == mask
## 不变量：INV-138（命令只带参数，不带状态值；掩码本身就是玩家参数）
## 失败：越界 → Reject.PARAM_RANGE，状态不变
func set_region_mask(p: int, mask: int) -> int:
	if not _valid_policy(p):
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, p, JWUnits.POLICY_N)
	if mask < 0 or mask > JWUnits.REGION_MASK_ALL:
		return JWResult.Reject.PARAM_RANGE
	region_mask[p] = mask
	return JWResult.OK


## 台账已用行数（只增不减，INV-097 的可观测量）。
## 步骤：S04、报告
## 前置：无
## 后置：不改状态
## 不变量：INV-097
## 失败：无
func claim_count() -> int:
	return _claim_count


## 下标合法性（本类内部统一入口，顺带挡住未 allocate 的情形）。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：INV-008（越界只有三种行为，静默截断不在其中）
## 失败：无（调用方据返回值登记 INDEX_OUT_OF_RANGE）
func _valid_policy(p: int) -> bool:
	if p < 0 or p >= JWUnits.POLICY_N:
		return false
	return enabled.size() == JWUnits.POLICY_N


## 内容包是否已装填到契约长度（读 defs 的裸下标前必过这一关）。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：INV-136（长度是 schema 的一部分）
## 失败：无（调用方据返回值登记 INDEX_OUT_OF_RANGE）
##
## 存在的理由：JWPolicyDef 的读取访问器只覆盖了四个字段，其余列本类要按下标直读。
## 未加载的内容包在 Godot 里是长度 0 的数组，直读会抛运行时错误——那是一个与真实故障
## 无关的现场，会把「内容包没装」误报成结算缺陷。
func _defs_ready(defs: JWPolicyDef) -> bool:
	if defs == null:
		return false
	if defs.kind.size() != JWUnits.POLICY_N:
		return false
	if defs.authority_bit.size() != JWUnits.POLICY_N:
		return false
	if defs.min_seats_ppm.size() != JWUnits.POLICY_N:
		return false
	if defs.requires_bloc_mask.size() != JWUnits.POLICY_N:
		return false
	if defs.requires_budget_review.size() != JWUnits.POLICY_N:
		return false
	if defs.cost_one_off_uu.size() != JWUnits.POLICY_N:
		return false
	if defs.lag_enact_to_effect_q.size() != JWUnits.POLICY_N:
		return false
	if defs.commission_delay_q.size() != JWUnits.POLICY_N:
		return false
	if defs.cooldown_q.size() != JWUnits.POLICY_N:
		return false
	if defs.toggle_cost_uu.size() != JWUnits.POLICY_N:
		return false
	if defs.exit_compensation_ppm.size() != JWUnits.POLICY_N:
		return false
	if defs.effect_magnitude.size() != JWUnits.POLICY_N:
		return false
	return true


## 本次开启（enacted_q[p] 那一次 try_enact）签入 committed_memo 的承诺额。
## 开局现行制度（enacted_q == ENACTED_BEFORE_START）没有经过 try_enact，没有签入任何承诺；
## 未通过的政策（enacted_q == −1）同理。try_enact 每次签入的都是 defs.cost_one_off_uu[p]（内容常量）。
func _commit_of_current_enactment(p: int, defs: JWPolicyDef) -> int:
	if enacted_q[p] < 0:
		return 0
	var c: int = defs.cost_one_off_uu[p]
	return c if c > 0 else 0


## 本次开启以来本政策的实付补助：claim_ledger 中政策号 == p、季号 >= enacted_q[p] 的行之和。
## 台账只增不减、键里无碰撞地打包了政策号与季号（claim_key_of），所以这是可逐位复算的纯函数；
## 补助只在政策生效期间发放，而再开启必在撤销之后（冷却），上一次开启的申领季号必小于本次 enacted_q。
func _spent_in_current_enactment(p: int) -> int:
	var q0: int = enacted_q[p]
	var pol_mask: int = (1 << CLAIM_KEY_POLICY_BITS) - 1
	var q_mask: int = (1 << CLAIM_KEY_Q_BITS) - 1
	var acc: int = 0
	for i: int in _claim_count:
		var key: int = claim_key[i]
		if (key & pol_mask) != p:
			continue
		if ((key >> CLAIM_KEY_Q_SHIFT) & q_mask) < q0:
			continue
		acc += claim_amount[i]
	return acc


## 本次开关的一次性行政成本。
## 步骤：S02 §2.1
## 前置：params.size() >= JWUnits.PARAM_N
## 后置：不改状态
## 不变量：INV-098（每次开关都有真实成本）
## 失败：无
##
## 取值口径：政策卡上的 toggle_cost_uu 优先，为 0 时回落到 param.policy_toggle_cost_uu。
## 理由：try_repeal 的冻结签名里根本没有 params，撤销时唯一到得了的成本就是政策卡上的那个；
## 两条路径必须同源，否则「开一次收 A、关一次收 B」会让 INV-098 的成本约束不对称。
func _toggle_cost(p: int, defs: JWPolicyDef, params: PackedInt64Array) -> int:
	var cost: int = defs.toggle_cost_uu[p]
	if cost <= 0:
		cost = params[JWUnits.Param.POLICY_TOGGLE_COST_UU]
	if cost < 0:
		return 0
	return cost


## 开关成本与退出违约金的收款方：中州服务部门 cell（行政中心）。
## docs/18 R-PUBSERV-01：pubserv 不持现金（docs/10 §2.1）；开关成本是政府为公共服务购买的中间投入，
## 付给中州服务 cell，由卖方记销售收入、计入中州 pubserv 的中间消耗（S06 销售归集时落账）。
static func toggle_payee_agent() -> int:
	return JWIds.agent_of_cell(JWIds.idx_cell(JWUnits.Region.ZHONGZHOU, JWUnits.Sector.SERVICES))


## 把一笔政策行政成本（或退出违约金）过账给中州服务部门 cell（gov → cell.中州.services），
## 并登记为基本支出实付。
## 步骤：S02 §2.1
## 前置：amount >= 0；ledger 与 treasury 非空；调用方已确认 gov 现金足以支付 amount
## 后置：一笔 post()，金额 == amount；计入 flow.gov.primary_paid_uu
## 不变量：INV-015、INV-016、INV-027
## 失败：现金不足 → ledger.post 的 NEGATIVE_CASH 原样返回
##
## 流量登记为什么在这里而不是调用方：过账的是本函数，现金减少的第一现场也在本函数。
## 原实现只过现金腿、不登记流量，S02 步末的 INV-027（cash_end == cash_start + 收入 + 借款 − 基本支出
## − 利息 − 还本）因此恰好差一笔开关成本 —— 任何一次开关（含撤销开局现行制度）都会撞 LEDGER_IMBALANCE。
## 档位取 DISCRETIONARY：开关与退出的行政成本不属于其余七档中任何一档的应付清单，
## 且该档没有分项流量落点（只进 primary_paid），不会与 S04 的逐项归集相互污染。
## **调用方不得再为同一笔调用 record_line_payment**（否则 primary_paid 记两次）。
##
## 收款方（R-PUBSERV-01）：原实现按作用地区拆给各地区的 pubserv 现金户，而 pubserv 不持现金，
## S04 步末的现金闭合检查因此必报 22。现改为单一收款方中州服务 cell：kind 26 的收款在 S06 被归集为
## 该 cell 的销售、并计入中州 pubserv 的中间消耗（以成本计的 G），GDP 三法恒等式两侧同增同额；
## 不再经市场重复购买（S05 公共服务买方类只以 flow.gov.pay_opex_uu 为预算，与本笔无关）。
## 退出违约金（kind 27，三口径全 none）付给同一收款方：它是转移，不进销售、不进中间消耗。
func _post_toggle_cost(p: int, amount: int, treasury: JWTreasury, ledger: JWLedger,
		kind: int) -> int:
	if amount <= 0:
		return JWResult.OK
	var rc: int = ledger.post(kind,
			JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH),
			JWIds.idx_account(toggle_payee_agent(), JWIds.ACC_CASH),
			amount, 0, -1, CAUSE_POLICY_BASE + p, p)
	if rc != JWResult.OK:
		return rc
	return treasury.record_line_payment(JWUnits.PayLine.DISCRETIONARY, 0, amount)


# ───────────── §1.6 状态块协议全部方法（SUBSYS_POLICY） ─────────────

## LOAD 期一次性 resize 到 §2.1 的契约长度。
## 步骤：LOAD
## 前置：JWPolicyDef 已加载（初值取 param_default）
## 后置：12 / 48 / CLAIM_CAP 长度到位；enacted_q、effective_from_q、exit_pending_q 填 −1
## 不变量：INV-136；§1.4（热路径不再分配）
## 失败：无
##
## 注：param_default 的装填由 JWContentLoader 经 set_state_array 完成——本函数的签名里
## 没有 JWPolicyDef，不能也不该去猜默认值。
func allocate() -> void:
	var n: int = JWUnits.POLICY_N
	var np: int = JWUnits.POLICY_PARAM_N
	enabled.resize(n)
	enabled.fill(0)
	enacted_q.resize(n)
	enacted_q.fill(-1)
	effective_from_q.resize(n)
	effective_from_q.fill(-1)
	params_ppm.resize(np)
	params_ppm.fill(0)
	params_uu.resize(np)
	params_uu.fill(0)
	pending_params.resize(np)
	pending_params.fill(0)
	region_mask.resize(n)
	region_mask.fill(0)
	budget_committed.resize(n)
	budget_committed.fill(0)
	budget_spent.resize(n)
	budget_spent.fill(0)
	toggle_count.resize(n)
	toggle_count.fill(0)
	cooldown_until_q.resize(n)
	cooldown_until_q.fill(0)
	claim_key.resize(CLAIM_CAP)
	claim_key.fill(0)
	claim_amount.resize(CLAIM_CAP)
	claim_amount.fill(0)
	exit_pending_q.resize(n)
	exit_pending_q.fill(-1)
	scheduled_params.resize(JWUnits.POLICY_N * JWIds.POLICY_PARAM_STRIDE)
	scheduled_params.fill(0)
	params_due_q.resize(n)
	params_due_q.fill(-1)
	opex_landed.resize(n)
	opex_landed.fill(0)
	_blocked_reason.resize(n)
	_blocked_reason.fill(JWUnits.BlockedReason.NONE)
	_claim_count = 0
	_bloc_stance_view.resize(JWUnits.STANCE_N)
	_bloc_stance_view.fill(0)
	_bloc_veto_view.resize(JWUnits.POLICY_N)
	_bloc_veto_view.fill(0)
	_r_weight.resize(JWUnits.R)
	_r_weight.fill(0)
	_r_tiebreak.resize(JWUnits.R)
	_r_tiebreak.fill(0)
	_r_out.resize(JWUnits.R)
	_r_out.fill(0)
	_g_weight.resize(JWUnits.GROUP)
	_g_weight.fill(0)
	_g_tiebreak.resize(JWUnits.GROUP)
	_g_tiebreak.fill(0)
	_g_out.resize(JWUnits.GROUP)
	_g_out.fill(0)


## 只读取用（返回引用，调用方不得写）。
## 步骤：存档 / 哈希
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func state_array(i: int) -> PackedInt64Array:
	match i:
		0: return enabled
		1: return enacted_q
		2: return effective_from_q
		3: return params_ppm
		4: return params_uu
		5: return pending_params
		6: return region_mask
		7: return budget_committed
		8: return budget_spent
		9: return toggle_count
		10: return cooldown_until_q
		11: return claim_key
		12: return claim_amount
		13: return exit_pending_q
		14: return scheduled_params
		15: return params_due_q
		16: return opex_landed
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## 仅 LOAD / MIG。
## 步骤：LOAD / MIG
## 前置：i 合法；v 长度符合契约
## 后置：对应成员数组 == v
## 不变量：INV-136
## 失败：长度或下标不符 → 返回非 0 错误码
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.Load.POLICY_FIELDS
	if v.size() != STATE_ARRAY_LEN[i]:
		return JWResult.Load.POLICY_FIELDS
	match i:
		0: enabled = v
		1: enacted_q = v
		2: effective_from_q = v
		3: params_ppm = v
		4: params_uu = v
		5: pending_params = v
		6: region_mask = v
		7: budget_committed = v
		8: budget_spent = v
		9: toggle_count = v
		10: cooldown_until_q = v
		11: claim_key = v
		12: claim_amount = v
		13: exit_pending_q = v
		14: scheduled_params = v
		15: params_due_q = v
		16: opex_landed = v
		_: return JWResult.Load.POLICY_FIELDS
	return JWResult.OK


## 读取标量状态（0 == state.policy.claim_count）。
## 步骤：存档 / 哈希
## 前置：i ∈ [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-097（台账只增不减）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func state_scalar(i: int) -> int:
	if i == 0:
		return _claim_count
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## 仅 LOAD / MIG。
## 步骤：LOAD / MIG
## 前置：i 合法；0 <= v <= CLAIM_CAP
## 后置：_claim_count == v
## 不变量：INV-097
## 失败：越界 → 返回非 0 错误码
func set_state_scalar(i: int, v: int) -> int:
	if i != 0:
		return JWResult.Load.POLICY_FIELDS
	if v < 0 or v > CLAIM_CAP:
		return JWResult.Load.POLICY_FIELDS
	_claim_count = v
	return JWResult.OK


## 本类无流量数组。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：docs/12 §01.3
## 失败：无
func flow_array(i: int) -> PackedInt64Array:
	return PackedInt64Array()


## 本类无标量流量。
## 步骤：—
## 前置：无
## 后置：不改状态
## 不变量：docs/12 §01.3
## 失败：无
func flow_scalar(i: int) -> int:
	return 0


## 仅 S01；本类无流量，空实现（budget_spent 的跨季重置属 S02 的预算预留，不在这里）。
## 步骤：S01 §01.3
## 前置：无
## 后置：不改状态
## 不变量：docs/12 §01.3
## 失败：无
func reset_flows() -> void:
	# budget_spent、claim_ledger 都是**存量**：按季清零会让「关停再开启不补发历史季」
	# 与「台账只增不减」同时失效（INV-097）。这里什么都不做是契约要求，不是遗漏。
	pass


## S01 清零后的自检，非 0 即 FLOW_NOT_RESET。本类无流量，恒 0。
## 步骤：S01 §01.3
## 前置：reset_flows() 已执行
## 后置：不改状态
## 不变量：docs/12 §01.3
## 失败：无
func flow_abs_sum() -> int:
	return 0
