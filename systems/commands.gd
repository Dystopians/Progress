## 命令定义、序列化（JSON Lines）、**形状与范围校验**，以及命令缓冲与 `log.rejections`。
## **语义校验（权限、冷却、资金）不在这里** —— 那是 S02 的 `JWPolicyEngine`。
## 唯一的提交期投影：撤销命令的冷却（docs/11 §6.1 命令 3），只读本缓冲里已结算的开关命令与内容包，
## 见 `_repeal_in_cooldown`；S02 的冷却闸门不变，仍是权威判定。
## 命令是玩家意图，不是状态变更；它是重放的唯一输入（除 `root_seed` 与内容包外）。
##
## 骨架依据：docs/17_api_skeleton.md §4.28（秩 A0；只允许引用秩 ≤1 与 `JWPolicyDef`）。
class_name JWCommands
extends RefCounted


## 命令缓冲容量（自开局起全量保留，写满按 1.5 倍扩容）。
const CMD_CAP: int = 4096

## 每条命令的整数参数槽数量（docs/17 §4.28 的 `c_arg` 长度 == CMD_CAP * ARG_SLOTS）。
const ARG_SLOTS: int = 6


## 命令码（docs/11 §6.1，值不得改）。
enum Kind {
	POLICY_ENACT = 1,
	POLICY_SET_PARAMS = 2,
	POLICY_REPEAL = 3,
	PROJECT_LAUNCH = 4,
	PROJECT_CANCEL = 5,
	PROJECT_DEFER = 6,
	BUDGET_REALLOCATE = 7,
	ISSUE_BOND = 8,
	DEBT_RESTRUCTURE = 9,
	SET_PAYMENT_PRIORITY = 10,
	SET_STANDING_RULE = 11,
	SELECT_MANDATE_GOAL = 12,
	ADVANCE_QUARTER = 99,
}


# ── 参数槽布局（本文件是其唯一定义处） ──────────────────────────────────────
#
# docs/11 §6.1 只给了每种命令的**参数名**（`policy_id`、`amount_uu`、`order[]` …），
# docs/17 §4.28 只规定「参数一律是整数槽，ID 在 LOAD 期已解析成下标」，
# 二者都没有规定哪个名字落在第几槽。槽位布局是重放协议的一部分（改它等于改 replay_hash），
# 因此此处定义即本项目的唯一布局，与 `JWBondBook.RestructureMode` 的处理方式相同。
#
# 约定：每种命令的参数占**前 arity 个槽**（连续，无空洞），其余槽必须为 0。
# 「其余槽必须为 0」不是洁癖：整数槽没有字段名，INV-138「命令不得携带任何直接状态值」
# 在这一层唯一可机器检查的形态就是「schema 之外的槽位不得有载荷」——
# 非零即 `Reject.DIRECT_STATE_WRITE`。
#
# 1  policy_enact        [policy, param0, param1, param2, param3, funding_source]
# 2  policy_set_params   [policy, param0, param1, param2, param3]
# 3  policy_repeal       [policy]
# 4  project_launch      [policy, region, scale_ppm, funding_source]
# 5  project_cancel      [project]
# 6  project_defer       [project, quarters]
# 7  budget_reallocate   [from_line, to_line, amount_uu]
# 8  issue_bond          [amount_uu, tenor_q, holder]
# 9  debt_restructure    [bond, mode]
# 10 set_payment_priority[packed_order]
# 11 set_standing_rule   [rule, value]
# 12 select_mandate_goal [goal]
# 99 advance_quarter     []

## 政策下标槽（kind 1/2/3/4）。
const SLOT_POLICY: int = 0
## 玩家参数首槽（kind 1/2）：槽 1..4 依次是 `player_params` 的 j = 0..3
## （`JWPolicyDef.PARAM_SLOT_PRIMARY` 的约定：j=0 对 rate/transfer 是主速率，其余 kind 是 region_mask）。
const SLOT_PARAM_BASE: int = 1
## kind 1 的资金来源槽（排在 4 个玩家参数之后）。
const SLOT_ENACT_FUNDING: int = 5
## kind 4 的地区 / 规模 / 资金来源槽。
const SLOT_LAUNCH_REGION: int = 1
const SLOT_LAUNCH_SCALE: int = 2
const SLOT_LAUNCH_FUNDING: int = 3
## kind 5/6 的项目下标槽与延期季数槽。
const SLOT_PROJECT: int = 0
const SLOT_DEFER_QUARTERS: int = 1
## kind 7 的三个槽。
const SLOT_FROM_LINE: int = 0
const SLOT_TO_LINE: int = 1
const SLOT_REALLOC_AMOUNT: int = 2
## kind 8 的三个槽。
const SLOT_BOND_AMOUNT: int = 0
const SLOT_BOND_TENOR: int = 1
const SLOT_BOND_HOLDER: int = 2
## kind 9 的两个槽。
const SLOT_BOND: int = 0
const SLOT_RESTRUCTURE_MODE: int = 1
## kind 10 的打包优先级槽。
const SLOT_PRIORITY_PACKED: int = 0
## kind 11 的两个槽。
const SLOT_RULE: int = 0
const SLOT_RULE_VALUE: int = 1
## kind 12 的施政目标槽。
const SLOT_GOAL: int = 0


## 资金来源码。docs/11 §5.12 的 `funding_source` 枚举顺序 `["cash", "bond", "reallocation"]`
## 即此处的数值码（契约只给了名字，没给数值；此处定义即本项目的唯一数值码）。
enum FundingSource { CASH = 0, BOND = 1, REALLOCATION = 2 }
const FUNDING_SOURCE_N: int = 3

## 常设指令的规则码。docs/20 §8.6 的覆盖范围「运行费自动拨付、库存补库、失业保障」即这三条。
## 常设指令进不进首版命令流仍是 docs/20 §18 待决 11，本文件只保证**形状**可校验：
## 规则码越界即 `Reject.PARAM_RANGE`，语义（能不能建、每季拨多少）归 S02。
enum StandingRule { SERVICE_OPEX_AUTOPAY = 0, INVENTORY_RESTOCK = 1, UNEMPLOYMENT_SUPPORT = 2 }
const STANDING_RULE_N: int = 3

## 重组模式的取值个数（`defer / writedown / default`，与 `JWBondBook.RestructureMode` 同一套数值码）。
## 这里只写个数不引用那个枚举：JWBondBook 是秩 4，本文件只允许依赖秩 ≤1 与 JWPolicyDef（docs/17 §7）。
const RESTRUCTURE_MODE_N: int = 3

## `tenor_q` 的合法区间。docs/31 `Q-ADV-05` 暂定 `[4, 40]`，`ADV-C07` 把
## `tenor_q ∈ {-1, 0, 1, 200, 2^40}` 全部钉为 `REJECT(E_PARAM_RANGE)` —— 下界必须排除 0 与 1。
const TENOR_MIN: int = 4
const TENOR_MAX: int = 40

## `project_defer` 的延期季数上界 == docs/11 §5.16 `param.commitment_horizon_q`（承诺表滚动窗口，16 季）。
## 超过滚动窗口的延期无法登记进承诺表，故在形状层就拒；「合同允不允许延期」仍归 S02。
const DEFER_QUARTERS_MAX: int = 16

## 支付优先级打包：8 档 × 3 位，第 i 档占 `3*i` 位（i 升序）。
## 6 个整数槽装不下 8 个独立值，打包是唯一不破坏槽位契约的表达方式；
## 3 位恰好覆盖 0..7，`PRIORITY_PACKED_MAX` 是 8^8 − 1。
const PRIORITY_BITS: int = 3
const PRIORITY_MASK: int = 7
const PRIORITY_PACKED_MAX: int = 16_777_215
## 8 档齐全时的位集合（1<<0 | … | 1<<7）。
const PRIORITY_FULL_SET: int = 255

## `log.rejections.detail` 的编码：`kind * DETAIL_STRIDE + (slot + 1)`，
## slot == -1（非槽位相关）时低位为 0。Presentation 据此给出「第几个参数不合法」的可展示原因。
const DETAIL_STRIDE: int = 8

## 日志与命令缓冲的扩容倍率（1.5 倍，docs/10 §12）。
const GROWTH_NUM: int = 3
const GROWTH_DEN: int = 2

## JSON 数字在 IEEE-754 双精度下仍然精确的整数上界（2^53）。
## Godot 4 的 `JSON.parse` 把**全部**数字解析成 float（已实测），超过这个量级即有精度损失，
## 因此解析期一律按 `Load.FILE_FORMAT` 拒。契约上界 `AMOUNT_MAX == 4e15` 在此界内。
const SAFE_JSON_INT_MAX: int = 9_007_199_254_740_992

## 规范化编码的类型标签，与 `JWSimState.TAG_*` 同值（docs/11 §6.4 第 2 条）。
## 本文件不能引用 JWSimState（秩 10），故在此复制常量；数值一经发布即进哈希口径。
const TAG_INT: int = 1
const TAG_ARRAY: int = 2
const ID_BYTES_MAX: int = 65535

## `command_log_hash()` 的条目稳定 ID，**已按字节序升序**排列（docs/11 §6.4 第 1 条）。
## 顺序是哈希口径的一部分，重排即破坏性变更。
const HASH_ARRAY_IDS: PackedStringArray = [
	"command_log.accepted",
	"command_log.arg",
	"command_log.command_id",
]
const HASH_COUNT_ID: String = "command_log.count"
const HASH_TAIL_IDS: PackedStringArray = [
	"command_log.issued_q",
	"command_log.kind",
	"command_log.reject_code",
]

## 命令码 ↔ JSON 的 `kind` 名（docs/11 §6.1 的示例用名字不用数字）。两表等长且同序。
const KIND_CODES: PackedInt64Array = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 99]
const KIND_NAMES: PackedStringArray = [
	"policy_enact", "policy_set_params", "policy_repeal", "project_launch",
	"project_cancel", "project_defer", "budget_reallocate", "issue_bond",
	"debt_restructure", "set_payment_priority", "set_standing_rule",
	"select_mandate_goal", "advance_quarter",
]

## JSON 行的字段名（顺序固定：docs/11 §6.1 的示例序 + 规则 2 要求的 accepted / reject_code）。
const JSON_KEY_COMMAND_ID: String = "command_id"
const JSON_KEY_ISSUED_Q: String = "issued_q"
const JSON_KEY_KIND: String = "kind"
const JSON_KEY_ARGS: String = "args"
const JSON_KEY_ACCEPTED: String = "accepted"
const JSON_KEY_REJECT_CODE: String = "reject_code"


# ── §1.6 状态块协议的注册表 ──────────────────────────────────────────────
# **注意**：命令缓冲本身**不进 `state_hash`** —— 它单独序列化为 `commands.jsonl`
# （docs/11 §6.2），进 `replay_hash`；进 `state_hash` 的只有 `JWSimState.command_seq`。
# `log.rejections` 同样在 docs/10 §11 的哈希排除清单里。
# 因此本块登记的状态条目为空集，协议方法仍需齐全（遍历式哈希/存档对它是空遍历）。

## 本块各数组所属子系统（与 STATE_ARRAY_IDS 等长），用于 subsystem_hash 与 WriteGuard。
const STATE_ARRAY_SUBSYS: PackedInt64Array = []

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
const STATE_ARRAY_IDS: PackedStringArray = []
const STATE_SCALAR_IDS: PackedStringArray = []
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = []


# ── 成员变量（列式命令缓冲，自开局起全量保留） ───────────────────────────

## 单调递增、不跳号的命令序号。写入者：CMD。
var c_command_id: PackedInt64Array = PackedInt64Array()

## 提交季。写入者：CMD。
var c_issued_q: PackedInt64Array = PackedInt64Array()

## 命令码 1..12, 99。写入者：CMD。
var c_kind: PackedInt64Array = PackedInt64Array()

## 6 个整数参数槽（长度 == CMD_CAP * ARG_SLOTS）。写入者：CMD。
var c_arg: PackedInt64Array = PackedInt64Array()

## 0/1。写入者：CMD, S01, S02。
var c_accepted: PackedInt64Array = PackedInt64Array()

## `JWResult.Reject`。写入者：CMD, S01, S02。
var c_reject_code: PackedInt64Array = PackedInt64Array()

## 命令条数。写入者：CMD。
var count: int = 0

## `log.rejections.*`（不进 state_hash）。写入者：CMD, S01, S02。
var r_command_id: PackedInt64Array = PackedInt64Array()
var r_code: PackedInt64Array = PackedInt64Array()
var r_detail: PackedInt64Array = PackedInt64Array()

## 本季日志游标与容量（§1.7 日志通道协议）。
var _log_rows: int = 0
var _log_capacity: int = 0

## 最近一次校验判定的出错槽位（-1 == 与槽位无关）。只服务于 `log.rejections.detail` 的编码，
## 不进任何哈希，也不跨命令保留语义。
var _last_reject_slot: int = -1

## 规范化编码的复用缓冲与 sha256 上下文（冷路径，避免每次哈希新建对象）。
var _hash_buf: PackedByteArray = PackedByteArray()
var _hash_slice: PackedInt64Array = PackedInt64Array()
static var _sha_ctx: HashingContext = null


## 提交一条命令（UI → 应用层的唯一入口，经 JWGame 转发）。
## 步骤：CMD（季度推进之外）
## 前置：kind 合法；参数槽数量匹配；**命令不得携带任何直接状态值**
## 后置：无论接受还是拒绝都进缓冲并消耗序号；被拒时写 log.rejections 且**状态哈希完全不变**
## 不变量：INV-137（被拒命令仍入档并记原因码）、INV-138（无 set_cash/set_gdp/set_support 之类字段）、
##          docs/11 §6.1 规则 1（(issued_q, command_id) 是全序主键，不跳号）
## 失败：Reject.DIRECT_STATE_WRITE / PARAM_RANGE / COMMAND_ORDER；
##       冷却期内的撤销 → Reject.POLICY_COOLDOWN（见 _repeal_in_cooldown）；缓冲满 → 扩容
##
## 本函数**不看 phase**：`submit` 的签名里没有 phase，而 ADV-B02 要求
## 「命令受理只发生在 PHASE_IDLE 与 S02」⇒ 该道闸在 `JWGame.submit_command`（它持有 `_st.phase`），
## 这里只做形状与范围。两处职责不重叠，也不互相兜底。
func submit(kind: int, args: PackedInt64Array, issued_q: int, defs: JWPolicyDef) -> JWResult:
	# 形状先判：它决定「这条命令的载荷是否合法」，与缓冲状态无关。
	var reject: int = _check_shape(kind, args)
	var slot: int = _last_reject_slot

	# 无论接受还是拒绝都入档并消耗序号（docs/11 §6.1 规则 1/2、INV-137）。
	var i: int = _append_row(kind, args, issued_q)
	if i < 0:
		# 扩容失败是工程故障，不是玩家的错：不消耗序号，也不入档，按故障登记。
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, count, c_kind.size())
		return JWResult.make_err(JWResult.Fault.INDEX_OUT_OF_RANGE, count, c_kind.size())

	if reject == JWResult.OK:
		# 提交期没有「本季已扫描到哪」的上下文，只能现扫一遍前面的行求出这两个量。
		# 这是冷路径（一次玩家操作一次调用），S01 的批量校验走 validate_batch 的单遍版本。
		reject = _order_reject(i, _max_issued_q_before(i), _live_marker_before(i, issued_q))
		slot = _last_reject_slot
	if reject == JWResult.OK:
		reject = _validate_row(i, defs)
		slot = _last_reject_slot

	var detail: int = _detail_code(kind, slot)
	c_accepted[i] = 1 if reject == JWResult.OK else 0
	c_reject_code[i] = reject
	if reject != JWResult.OK:
		_log_rejection(c_command_id[i], reject, detail)
		return JWResult.make_err(reject, c_command_id[i], detail, kind)
	return JWResult.make_ok()


## S01 §01.5：按 (issued_q, command_id) 升序做只判定不执行的校验。
## 步骤：S01 §01.5
## 前置：本季命令已全部提交
## 后置：c_accepted 与 c_reject_code 写好；被拒命令不进执行队列但仍在命令流里
## 不变量：INV-137、INV-008（遍历顺序确定）
## 失败：不返回业务失败；格式非法的命令逐条 REJECT 并继续
##
## 为什么提交期校过还要再校一遍：`load_jsonl` 可以绕过 `submit` 把整条命令流灌进缓冲
## （`commands_only` 重放就是这么跑的）。重放必须复现「玩家试过但被挡住」这一事实，
## 所以判定逻辑只有一份（`_validate_row`），提交期与 S01 期各跑一次。
## **本函数只会把命令判得更严，绝不会把已被拒的命令翻成受理**——
## 那会让同一条命令流在两次运行里走出不同路径（INV-137 的反面）。
func validate_batch(q: int, defs: JWPolicyDef) -> int:
	# 单遍扫描，边走边维护次序校验需要的两个量（前缀最大季号、本季第一条未被拒的推进标记），
	# 否则「每行再回头扫一遍前缀」会让 S01 变成 O(n²)，而命令缓冲是自开局起全量保留的。
	var max_prev_q: int = -1
	var marker_before: int = -1
	var i: int = 0
	while i < count:
		if c_issued_q[i] != q:
			if c_issued_q[i] > max_prev_q:
				max_prev_q = c_issued_q[i]
			i += 1
			continue
		var reject: int = c_reject_code[i]
		if reject == JWResult.OK:
			reject = _order_reject(i, max_prev_q, marker_before)
			var slot_order: int = _last_reject_slot
			if reject == JWResult.OK:
				reject = _validate_row(i, defs)
			else:
				_last_reject_slot = slot_order
		else:
			# 已经带着原因码进来的行（提交期被拒或从存档读入）：原因码原样保留，
			# 只补写本季的 log.rejections —— S01 §01.1 刚把日志游标清零，
			# 不补写等于让本季的拒绝记录凭空消失（INV-139 的行数对账会立刻发现）。
			_last_reject_slot = -1
		c_accepted[i] = 1 if reject == JWResult.OK else 0
		c_reject_code[i] = reject
		if reject != JWResult.OK:
			_log_rejection(c_command_id[i], reject, _detail_code(c_kind[i], _last_reject_slot))
		elif c_kind[i] == Kind.ADVANCE_QUARTER and marker_before < 0:
			marker_before = i
		if c_issued_q[i] > max_prev_q:
			max_prev_q = c_issued_q[i]
		i += 1
	return JWResult.OK


## 取本季待执行命令（S02 受理时按同一顺序遍历）。
## 步骤：S02 §2.1
## 前置：validate_batch 已完成
## 后置：out_idx 按 (issued_q, command_id) 升序填充
## 不变量：INV-008
## 失败：无
##
## 缓冲是追加写的，所以「下标升序」就是「command_id 升序」（command_id 逐条 +1，不跳号）；
## 本季的行按下标升序过滤出来即满足 (issued_q, command_id) 全序。
## 不做二分：被拒的乱序命令也在缓冲里（INV-137），`issued_q` 列因此不保证单调。
## **不含 `ADVANCE_QUARTER`**：它是季度边界标记不是待执行命令，位置约束由 `check_advance_marker`
## 单独判（docs/17 §5.1 第 8 行把两者列为并列的两次调用）。S02 因此不必逐条跳过 kind 99。
func accepted_this_quarter_into(out_idx: PackedInt64Array, q: int) -> int:
	var rows: int = 0
	var i: int = 0
	while i < count:
		if c_issued_q[i] == q and c_accepted[i] == 1 and c_kind[i] != Kind.ADVANCE_QUARTER:
			if rows >= out_idx.size():
				# 容量不足就整体失败，不截断：悄悄少执行几条命令会让重放分歧。
				JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, rows, out_idx.size())
				return 0
			out_idx[rows] = i
			rows += 1
		i += 1
	return rows


## `advance_quarter` 的位置约束：每季恰好一条且为该季最后一条。
## 步骤：CMD / S01
## 前置：无
## 后置：不改状态
## 不变量：docs/11 §6.1 的 kind 99 校验
## 失败：多于一条或不在末尾 → Reject.COMMAND_ORDER
##
## 「不改状态」成立：命令缓冲与 log.rejections 都在 state_hash 的排除清单里（docs/17 §4.28）。
## 违规的行在这里被**显式拒绝并登记原因码**，不是丢弃——否则重放时它们会重新出现。
func check_advance_marker(q: int) -> int:
	var last_row: int = -1
	var first_marker: int = -1
	var live_markers: int = 0
	var i: int = 0
	while i < count:
		if c_issued_q[i] == q and c_reject_code[i] == JWResult.OK:
			last_row = i
			if c_kind[i] == Kind.ADVANCE_QUARTER:
				live_markers += 1
				if first_marker < 0:
					first_marker = i
		i += 1

	if live_markers == 0:
		# 本季没有推进标记：不是某一条命令的错，无从归因，故不写 log.rejections。
		return JWResult.Reject.COMMAND_ORDER

	var violated: bool = false
	i = 0
	while i < count:
		if c_issued_q[i] == q and c_reject_code[i] == JWResult.OK:
			var bad: bool = false
			if c_kind[i] == Kind.ADVANCE_QUARTER:
				# 每季恰好一条：只有本季最后一行的标记算数，其余一律拒。
				bad = i != last_row
			else:
				# 推进标记之后不得再有命令（docs/11 §6.1 kind 99）。
				bad = first_marker >= 0 and i > first_marker
			if bad:
				c_accepted[i] = 0
				c_reject_code[i] = JWResult.Reject.COMMAND_ORDER
				_log_rejection(c_command_id[i], JWResult.Reject.COMMAND_ORDER,
						_detail_code(c_kind[i], -1))
				violated = true
		i += 1
	if violated:
		return JWResult.Reject.COMMAND_ORDER
	return JWResult.OK


## JSON Lines 写出（冷路径；**追加写，自动保存 O(1)**）。
## 步骤：存档 / 读档
## 前置：路径可写；单行损坏只丢一条
## 后置：格式逐字符合 docs/11 §6.1 的示例
## 不变量：INV-131（存档含完整命令流，含被拒命令）
## 失败：Load.FILE_FORMAT / Load.SAVE_CORRUPT
##
## 与 §6.1 示例的两处差异，都是**契约自身的要求**而不是简化：
## ① `args` 的值是整数下标不是 ID 字符串 —— 缓冲里存的就是下标（docs/17 §4.28
##    「ID 在 LOAD 期已解析成下标」），而本函数的签名里没有 `JWIds`，反查不出字符串。
##    `load_jsonl` 两种形态都认（它有 `ids`），所以手写的示例行仍然读得进来。
## ② 不写 `client_build_id` —— 它在 docs/11 §6.4 第 5 条的哈希排除集合里，
##    且本类没有 build_id 入参；写一个由构建决定的字段进逐行文本，只会让存档文件不可比对。
## 行内不做 JSON.stringify：Dictionary 的迭代序不是协议，手工拼串才保证逐字节稳定可重放。
func append_jsonl(path: String, index: int) -> JWResult:
	if index < 0 or index >= count:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, index, count)
	var f: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, FileAccess.get_open_error(), 0)
	f.seek_end()
	f.store_line(_line_of(index))
	f.close()
	return JWResult.make_ok()


## 整条命令流的 JSON Lines 文本（每行一条，末尾换行）。存档一次写入用，逐行开关文件在长局里是 O(n) 次 I/O
## （1600 季实测写一份存档 49 s，docs/53 M1-9）。行格式与 append_jsonl 逐字相同。
func jsonl_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in count:
		parts.append(_line_of(i))
	if parts.is_empty():
		return ""
	return "\n".join(parts) + "\n"


## JSON Lines 读入（冷路径）。
## 步骤：存档 / 读档
## 前置：路径存在；ID 在 LOAD 期经 JWIds 解析成下标
## 后置：缓冲复原为写出时的逐位相同内容
## 不变量：INV-131
## 失败：Load.FILE_FORMAT / Load.SAVE_CORRUPT
##
## 失败分两级，因为两种坏法的后果不同：
## 单行解析不了 → 丢这一行并记 `Load.FILE_FORMAT`（§6.1 选 JSONL 的理由就是「单行损坏只丢一条」）；
## `command_id` 跳号 / 倒序 / 重复 → 整条命令流不可信，记 `Load.SAVE_CORRUPT`
## （不跳号是 §6.1 规则 1 的主键约定，破了它 (issued_q, command_id) 就不再是全序）。
## 两者都不静默：调用方 `JWSaves` 还会再用 `command_log_hash` 与 manifest 交叉验证（ADV-H06）。
func load_jsonl(path: String, ids: JWIds) -> JWResult:
	if not FileAccess.file_exists(path):
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, FileAccess.get_open_error(), 0)
	var text: String = FileAccess.get_file_as_string(path)
	count = 0
	var lines: PackedStringArray = text.split("\n", false)
	var parser: JSON = JSON.new()
	var bad_lines: int = 0
	var first_bad: int = -1
	var corrupt: int = 0
	var ln: int = 0
	while ln < lines.size():
		var raw: String = lines[ln].strip_edges()
		ln += 1
		if raw.is_empty():
			continue
		if parser.parse(raw) != OK or typeof(parser.data) != TYPE_DICTIONARY:
			bad_lines += 1
			if first_bad < 0:
				first_bad = ln
			continue
		var row: Dictionary = parser.data
		if _append_parsed_row(row, ids) != JWResult.OK:
			bad_lines += 1
			if first_bad < 0:
				first_bad = ln
			continue
		var i: int = count - 1
		var want_id: int = 1 if i == 0 else c_command_id[i - 1] + 1
		if c_command_id[i] != want_id:
			corrupt += 1
	if corrupt > 0:
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, corrupt, count)
	if bad_lines > 0:
		return JWResult.make_err(JWResult.Load.FILE_FORMAT, first_bad, bad_lines)
	return JWResult.make_ok()


## 命令流哈希（replay_hash，供 manifest 与重放交叉验证）。
## 步骤：存档
## 前置：无
## 后置：不改状态
## 不变量：INV-133
## 失败：无
##
## 口径与 docs/11 §6.4 的规范化编码一致（条目按稳定 ID 字节序升序；
## `uint16 len(id) + id + uint8 tag + 值`），但**不能**走 `JWSimState.canon_*`：
## JWSimState 是秩 10，本文件只允许依赖秩 ≤1（docs/17 §7 依赖表），所以在此重实现同一套字节布局。
## 只哈希前 `count` 个元素，不哈希容量：否则一次 1.5 倍扩容就会改变 replay_hash。
func command_log_hash() -> String:
	_hash_buf.clear()
	_canon_array(HASH_ARRAY_IDS[0], c_accepted, count)
	_canon_array(HASH_ARRAY_IDS[1], c_arg, JWMath.mul(count, ARG_SLOTS))
	_canon_array(HASH_ARRAY_IDS[2], c_command_id, count)
	_canon_scalar(HASH_COUNT_ID, count)
	_canon_array(HASH_TAIL_IDS[0], c_issued_q, count)
	_canon_array(HASH_TAIL_IDS[1], c_kind, count)
	_canon_array(HASH_TAIL_IDS[2], c_reject_code, count)
	if _sha_ctx == null:
		_sha_ctx = HashingContext.new()
	_sha_ctx.start(HashingContext.HASH_SHA256)
	_sha_ctx.update(_hash_buf)
	return _sha_ctx.finish().hex_encode()


# ── 公开取值助手（供 S02 按槽位布局读命令，不重复发明布局） ───────────────

## 读第 index 条命令的第 slot 个参数槽。
## 步骤：S02 §2.1
## 前置：index ∈ [0, count)；slot ∈ [0, ARG_SLOTS)
## 后置：不改状态
## 不变量：INV-136（槽位布局是 schema 的一部分）
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回 0
func arg_at(index: int, slot: int) -> int:
	if index < 0 or index >= count or slot < 0 or slot >= ARG_SLOTS:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, index, slot)
		return 0
	return c_arg[index * ARG_SLOTS + slot]


## 把 8 档支付优先级打包成一个整数槽（UI / 测试构造 kind 10 时用）。
## 步骤：CMD
## 前置：order 是 JWUnits.PayLine 的 8 元全排列
## 后置：不改状态
## 不变量：docs/11 §6.1 命令 10（8 类的全排列）
## 失败：不是全排列 → 返回 -1（调用方提交它即得 Reject.PRIORITY_INCOMPLETE）
static func pack_payment_priority(order: PackedInt64Array) -> int:
	if order.size() != JWUnits.PAY_LINE_N:
		return -1
	var packed: int = 0
	var seen: int = 0
	var i: int = 0
	while i < JWUnits.PAY_LINE_N:
		var v: int = order[i]
		if v < 0 or v >= JWUnits.PAY_LINE_N:
			return -1
		seen = seen | (1 << v)
		packed = packed | (v << (PRIORITY_BITS * i))
		i += 1
	if seen != PRIORITY_FULL_SET:
		return -1
	return packed


## 把打包的优先级还原成 8 档顺序（S02 写 `state.gov.payment_priority` 时用）。
## 步骤：S02 §2.2
## 前置：out.size() == JWUnits.PAY_LINE_N；packed 由已受理的 kind 10 命令而来
## 后置：out[i] == 第 i 顺位的 PayLine
## 不变量：docs/11 §6.1 命令 10
## 失败：out 长度不符或 packed 不是全排列 → Reject.PRIORITY_INCOMPLETE，out 不变
static func unpack_payment_priority_into(out: PackedInt64Array, packed: int) -> int:
	if out.size() != JWUnits.PAY_LINE_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, out.size(), JWUnits.PAY_LINE_N)
		return JWResult.Reject.PRIORITY_INCOMPLETE
	if _priority_seen_set(packed) != PRIORITY_FULL_SET:
		return JWResult.Reject.PRIORITY_INCOMPLETE
	var i: int = 0
	while i < JWUnits.PAY_LINE_N:
		out[i] = (packed >> (PRIORITY_BITS * i)) & PRIORITY_MASK
		i += 1
	return JWResult.OK


# ── §1.6 状态块协议 ──────────────────────────────────────────────────────

## LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：维度常量已确定
## 后置：命令缓冲与 log.rejections 各数组就位；此后不再 resize（写满才按 1.5 倍扩容）
## 不变量：docs/10 §0.6（加载期一次性 resize）
## 失败：无
func allocate() -> void:
	c_command_id.resize(CMD_CAP)
	c_command_id.fill(0)
	c_issued_q.resize(CMD_CAP)
	c_issued_q.fill(0)
	c_kind.resize(CMD_CAP)
	c_kind.fill(0)
	c_arg.resize(CMD_CAP * ARG_SLOTS)
	c_arg.fill(0)
	c_accepted.resize(CMD_CAP)
	c_accepted.fill(0)
	c_reject_code.resize(CMD_CAP)
	c_reject_code.fill(0)
	count = 0
	r_command_id.resize(JWUnits.LOG_CAP0)
	r_command_id.fill(0)
	r_code.resize(JWUnits.LOG_CAP0)
	r_code.fill(0)
	r_detail.resize(JWUnits.LOG_CAP0)
	r_detail.fill(0)
	_log_rows = 0
	_log_capacity = JWUnits.LOG_CAP0


## 只读取用（返回引用，调用方不得写）。
## 步骤：哈希 / 存档
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136（下标顺序是 schema 的一部分）
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func state_array(i: int) -> PackedInt64Array:
	# 本块状态条目为空集（命令缓冲进 replay_hash，不进 state_hash），任何下标都越界。
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## 仅 LOAD / MIG 可调（静态检查：调用点必须在 systems/content_loader.gd 或 systems/saves.gd）。
## 步骤：LOAD / MIG
## 前置：!frozen；v.size() 等于契约长度
## 后置：state_array(i) == v
## 不变量：INV-136
## 失败：越界或长度不符 → Fault.INDEX_OUT_OF_RANGE
func set_state_array(i: int, v: PackedInt64Array) -> int:
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())


## 标量读取。
## 步骤：哈希 / 存档
## 前置：i ∈ [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回 0
func state_scalar(i: int) -> int:
	# command_seq 由 JWSimState 持有并进 state_hash；本块没有进哈希的标量。
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## 仅 LOAD / MIG。
## 步骤：LOAD / MIG
## 前置：i 合法
## 后置：state_scalar(i) == v
## 不变量：INV-136
## 失败：越界 → Fault.INDEX_OUT_OF_RANGE
func set_state_scalar(i: int, v: int) -> int:
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())


## 流量数组读取。
## 步骤：哈希 / 存档
## 前置：i ∈ [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回空数组
func flow_array(i: int) -> PackedInt64Array:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## 流量标量读取。
## 步骤：哈希 / 存档
## 前置：i ∈ [0, FLOW_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回 0
func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## 仅 S01；全部 FLOW_* 归零（静态检查：调用点必须在 turn_runner._step_s01 内）。
## 步骤：S01 §01.3
## 前置：phase == S01
## 后置：全部 flow.* 为 0
## 不变量：INV-013
## 失败：无（清零后非零由 flow_abs_sum 报 FLOW_NOT_RESET）
func reset_flows() -> void:
	# 空遍历：命令缓冲是跨季保留的状态，不是流量（docs/17 §4.28）。
	pass


## S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 已执行
## 后置：不改状态
## 不变量：INV-013
## 失败：调用方按非 0 返回 Fault.FLOW_NOT_RESET
func flow_abs_sum() -> int:
	return 0


# ── §1.7 日志通道协议 ────────────────────────────────────────────────────

## 每季 S01 重置本季游标（日志不进 state_hash）。
## 步骤：S01 §01.1
## 前置：phase == S01
## 后置：_log_rows == 0
## 不变量：INV-011 / INV-139 的对账基准
## 失败：无
func log_reset_quarter() -> void:
	_log_rows = 0


## 本季已写行数，供 INV-011 / INV-139 对账。
## 步骤：每季末
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func log_row_count() -> int:
	return _log_rows


## 当前容量；写满时按 1.5 倍扩容并写一条告警行。
## 步骤：任意
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func log_capacity() -> int:
	return _log_capacity


# ── 私有：缓冲写入 ────────────────────────────────────────────────────────

## 追加一行到命令缓冲并消耗一个序号，返回行下标（失败返回 -1）。
## 步骤：CMD / LOAD
## 前置：无
## 后置：count += 1；c_command_id[i] == 上一条 + 1（不跳号）；多余槽位为 0
## 不变量：docs/11 §6.1 规则 1（被拒命令也消耗序号）
## 失败：扩容失败 → 返回 -1
func _append_row(kind: int, args: PackedInt64Array, issued_q: int) -> int:
	if not _ensure_cmd_capacity():
		return -1
	var i: int = count
	c_command_id[i] = 1 if i == 0 else c_command_id[i - 1] + 1
	c_issued_q[i] = issued_q
	c_kind[i] = kind
	var base: int = i * ARG_SLOTS
	# schema 之外的槽位一律落 0：它们已经被 _check_shape 判成 DIRECT_STATE_WRITE，
	# 把夹带的数值真的存进权威缓冲，等于让 INV-138 的违例在存档里留了个可用的载荷位。
	# 「玩家试过什么」由 reject_code + log.rejections.detail（带槽位号）如实记录，不靠保留数值。
	var arity: int = _arity_of(kind)
	if arity < 0:
		arity = 0
	var j: int = 0
	while j < ARG_SLOTS:
		c_arg[base + j] = args[j] if j < args.size() and j < arity else 0
		j += 1
	c_accepted[i] = 0
	c_reject_code[i] = JWResult.OK
	count = i + 1
	return i


## 命令缓冲写满则按 1.5 倍扩容（自开局起全量保留，docs/17 §4.28）。
## 步骤：CMD / LOAD
## 前置：无
## 后置：count < c_kind.size() 且六张表长度自洽
## 不变量：INV-136（c_arg 的行宽恒为 ARG_SLOTS）
## 失败：扩不动 → 返回 false
func _ensure_cmd_capacity() -> bool:
	var cap: int = c_kind.size()
	if count < cap:
		return true
	var next_cap: int = CMD_CAP
	if cap > 0:
		# rounding: ceil, reason=扩容宁可多要一行，也不能因取整停在原容量上
		next_cap = JWMath.ceil_div(JWMath.mul(cap, GROWTH_NUM), GROWTH_DEN)
	if next_cap <= cap:
		next_cap = cap + 1
	c_command_id.resize(next_cap)
	c_issued_q.resize(next_cap)
	c_kind.resize(next_cap)
	c_accepted.resize(next_cap)
	c_reject_code.resize(next_cap)
	c_arg.resize(JWMath.mul(next_cap, ARG_SLOTS))
	return count < c_kind.size()


## 写一行 log.rejections（不进 state_hash；写满按 1.5 倍扩容）。
## 步骤：CMD / S01 / S02
## 前置：无
## 后置：log_row_count() += 1
## 不变量：INV-137（被拒必须留下可展示的原因码）、INV-139
## 失败：无（扩容失败也不丢行，直接放弃写入并登记越界故障）
func _log_rejection(command_id: int, code: int, detail: int) -> void:
	if _log_rows >= r_code.size():
		_log_grow()
	if _log_rows >= r_code.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, _log_rows, r_code.size())
		return
	r_command_id[_log_rows] = command_id
	r_code[_log_rows] = code
	r_detail[_log_rows] = detail
	_log_rows += 1


## 三张 log.rejections 数组按 1.5 倍同步扩容（docs/10 §12）。
## 步骤：写日志时容量耗尽
## 前置：无
## 后置：三张数组等长且 > 原长；log_capacity() 更新
## 不变量：INV-139
## 失败：无
func _log_grow() -> void:
	var cap: int = r_code.size()
	var next_cap: int = JWUnits.LOG_CAP0
	if cap > 0:
		# rounding: ceil, reason=扩容宁可多要一行，也不能因取整停在原容量上
		next_cap = JWMath.ceil_div(JWMath.mul(cap, GROWTH_NUM), GROWTH_DEN)
	if next_cap <= cap:
		next_cap = cap + 1
	r_command_id.resize(next_cap)
	r_code.resize(next_cap)
	r_detail.resize(next_cap)
	_log_capacity = next_cap


## `log.rejections.detail` 的编码。
## 步骤：CMD / S01
## 前置：slot ∈ [-1, ARG_SLOTS)
## 后置：不改状态
## 不变量：docs/10 §2.5（日志只有整数，文案由 Presentation 查表）
## 失败：无
func _detail_code(kind: int, slot: int) -> int:
	var s: int = slot + 1
	if s < 0 or s > ARG_SLOTS:
		s = 0
	return JWMath.mul(kind, DETAIL_STRIDE) + s


# ── 私有：校验 ────────────────────────────────────────────────────────────

## 形状校验：命令码合法、槽位数量匹配、schema 之外的槽位不得有载荷。
## 步骤：CMD
## 前置：无
## 后置：不改状态；_last_reject_slot 写好
## 不变量：INV-138（命令不得携带任何直接状态值）
## 失败：Reject.PARAM_RANGE（码非法 / 槽位不足）、Reject.DIRECT_STATE_WRITE（多余槽位有载荷）
func _check_shape(kind: int, args: PackedInt64Array) -> int:
	_last_reject_slot = -1
	var arity: int = _arity_of(kind)
	if arity < 0:
		return JWResult.Reject.PARAM_RANGE
	if args.size() > ARG_SLOTS:
		# 槽位是 schema 的一部分：多给的整数没有任何字段可以落脚，只能是夹带。
		_last_reject_slot = ARG_SLOTS - 1
		return JWResult.Reject.DIRECT_STATE_WRITE
	if args.size() < arity:
		_last_reject_slot = args.size()
		return JWResult.Reject.PARAM_RANGE
	var j: int = arity
	while j < args.size():
		if args[j] != 0:
			_last_reject_slot = j
			return JWResult.Reject.DIRECT_STATE_WRITE
		j += 1
	return JWResult.OK


## 次序校验：季号不得为负、不得倒退；本季推进标记之后不得再有命令。
## 步骤：CMD / S01 §01.5
## 前置：行 i 已在缓冲里；max_prev_q 是前缀最大季号，marker_before 是本季在 i 之前
##       第一条未被拒的 ADVANCE_QUARTER 行下标（没有则 -1）
## 后置：不改状态；_last_reject_slot == -1
## 不变量：docs/11 §6.1 规则 1（(issued_q, command_id) 全序主键）与 kind 99 的位置约束
## 失败：Reject.COMMAND_ORDER
func _order_reject(i: int, max_prev_q: int, marker_before: int) -> int:
	_last_reject_slot = -1
	if c_issued_q[i] < 0:
		return JWResult.Reject.COMMAND_ORDER
	if max_prev_q > c_issued_q[i]:
		# command_id 递增而季号倒退即破坏 (issued_q, command_id) 的全序。
		return JWResult.Reject.COMMAND_ORDER
	if marker_before >= 0 and marker_before < i:
		return JWResult.Reject.COMMAND_ORDER
	return JWResult.OK


## 行 i 之前的最大季号（提交期用；没有前序行返回 -1）。
## 步骤：CMD
## 前置：i ∈ [0, count)
## 后置：不改状态
## 不变量：docs/11 §6.1 规则 1
## 失败：无
func _max_issued_q_before(i: int) -> int:
	var m: int = -1
	var j: int = 0
	while j < i:
		if c_issued_q[j] > m:
			m = c_issued_q[j]
		j += 1
	return m


## 行 i 之前、季 q 内第一条未被拒的推进标记行下标（没有返回 -1）。
## 步骤：CMD
## 前置：i ∈ [0, count)
## 后置：不改状态
## 不变量：docs/11 §6.1 kind 99 的位置约束
## 失败：无
func _live_marker_before(i: int, q: int) -> int:
	var j: int = 0
	while j < i:
		if c_issued_q[j] == q and c_kind[j] == Kind.ADVANCE_QUARTER \
				and c_reject_code[j] == JWResult.OK:
			return j
		j += 1
	return -1


## 范围校验：逐种命令按 docs/11 §6.1 的参数表判定取值区间。
## 步骤：CMD / S01 §01.5
## 前置：行 i 已在缓冲里；形状已通过
## 后置：不改状态；_last_reject_slot 指向出错槽位
## 不变量：INV-137；docs/11 §6.1 各行「主要校验」中与**取值范围**有关的部分
## 失败：Reject.PARAM_RANGE / UNKNOWN_POLICY / PRECONDITION / PRIORITY_INCOMPLETE
##
## 这里**只判范围与内容包（加上本缓冲里已结算的命令）能独立回答的前置条件**。权限（席位、集团否决）、
## 资金都要读 JWPolitics / JWTreasury，而本文件的依赖上限是秩 ≤1 + JWPolicyDef（docs/17 §7 依赖表），
## 物理上够不着——它们归 S02 的 JWPolicyEngine（docs/17 §4.28 的职责分工）。
## 唯一的例外是撤销命令的冷却：它可以从已结算的开关命令与内容包的 cooldown_q 推出（见 _repeal_in_cooldown），
## docs/11 §6.1 要求它在提交时就 REJECT；S02 的同名闸门保留，仍是权威判定。
func _validate_row(i: int, defs: JWPolicyDef) -> int:
	_last_reject_slot = -1
	var kind: int = c_kind[i]
	var base: int = i * ARG_SLOTS

	if kind == Kind.ADVANCE_QUARTER:
		return JWResult.OK

	if kind == Kind.POLICY_ENACT or kind == Kind.POLICY_SET_PARAMS:
		if not _defs_ready(defs):
			_last_reject_slot = SLOT_POLICY
			return JWResult.Reject.UNKNOWN_POLICY
		var p: int = c_arg[base + SLOT_POLICY]
		if p < 0 or p >= JWUnits.POLICY_N:
			_last_reject_slot = SLOT_POLICY
			return JWResult.Reject.UNKNOWN_POLICY
		var j: int = 0
		while j < JWIds.POLICY_PARAM_STRIDE:
			var v: int = c_arg[base + SLOT_PARAM_BASE + j]
			var rng: Vector2i = defs.param_range(p, j)
			if v < rng.x or v > rng.y:
				_last_reject_slot = SLOT_PARAM_BASE + j
				return JWResult.Reject.PARAM_RANGE
			j += 1
		if kind == Kind.POLICY_ENACT:
			var fs: int = c_arg[base + SLOT_ENACT_FUNDING]
			if fs < 0 or fs >= FUNDING_SOURCE_N:
				_last_reject_slot = SLOT_ENACT_FUNDING
				return JWResult.Reject.PARAM_RANGE
		return JWResult.OK

	if kind == Kind.POLICY_REPEAL:
		var pr: int = c_arg[base + SLOT_POLICY]
		if pr < 0 or pr >= JWUnits.POLICY_N:
			_last_reject_slot = SLOT_POLICY
			return JWResult.Reject.UNKNOWN_POLICY
		# docs/11 §6.1 命令 3 的「冷却」（INV-098）：冷却期内的撤销在提交期就 REJECT，状态哈希不变（规则 3）。
		if _repeal_in_cooldown(i, pr, defs):
			_last_reject_slot = SLOT_POLICY
			return JWResult.Reject.POLICY_COOLDOWN
		return JWResult.OK

	if kind == Kind.PROJECT_LAUNCH:
		if not _defs_ready(defs):
			_last_reject_slot = SLOT_POLICY
			return JWResult.Reject.UNKNOWN_POLICY
		var pl: int = c_arg[base + SLOT_POLICY]
		if pl < 0 or pl >= JWUnits.POLICY_N:
			_last_reject_slot = SLOT_POLICY
			return JWResult.Reject.UNKNOWN_POLICY
		# 范围先于语义（docs/17 §4.28：本文件的职责是形状与范围，语义归 S02）。
		# 顺序不是风格问题：若「非工程类政策」这条语义前置条件排在范围之前，
		# 越界的 scale_ppm 与合法的 scale_ppm 会拿到同一个拒绝码，
		# 范围这一关就从未被执行到过，而这是**观察不到**的——
		# 两条命令都被拒，看上去一样安全（ADV-B04 的对照组就是用来暴露这一点的）。
		var rg: int = c_arg[base + SLOT_LAUNCH_REGION]
		if rg < 0 or rg >= JWUnits.R:
			_last_reject_slot = SLOT_LAUNCH_REGION
			return JWResult.Reject.PARAM_RANGE
		var scale: int = c_arg[base + SLOT_LAUNCH_SCALE]
		if scale < 0 or scale > JWUnits.PPM:
			# scale_ppm 是比率，闭区间 [0, PPM]。负值是越界，不是「规模为 0」（docs/10 §0.8）。
			_last_reject_slot = SLOT_LAUNCH_SCALE
			return JWResult.Reject.PARAM_RANGE
		var fs2: int = c_arg[base + SLOT_LAUNCH_FUNDING]
		if fs2 < 0 or fs2 >= FUNDING_SOURCE_N:
			_last_reject_slot = SLOT_LAUNCH_FUNDING
			return JWResult.Reject.PARAM_RANGE
		if defs.kind[pl] != JWPolicyDef.POLICY_KIND_PROJECT:
			# 非工程类政策没有施工槽位、没有 planned_quarters，立不出项目来。
			# 这条前置条件内容包自己就能回答，故留在 §01.5；槽位／资金仍归 S02。
			_last_reject_slot = SLOT_POLICY
			return JWResult.Reject.PRECONDITION
		return JWResult.OK

	if kind == Kind.PROJECT_CANCEL or kind == Kind.PROJECT_DEFER:
		var pj: int = c_arg[base + SLOT_PROJECT]
		if pj < 0:
			# R-CAP-01：参数是项目的稳定实体号（非负）；「这个项目存不存在、完没完工」是 S02 的 Reject.NOT_FOUND。
			_last_reject_slot = SLOT_PROJECT
			return JWResult.Reject.PARAM_RANGE
		if kind == Kind.PROJECT_DEFER:
			var dq: int = c_arg[base + SLOT_DEFER_QUARTERS]
			if dq < 1 or dq > DEFER_QUARTERS_MAX:
				_last_reject_slot = SLOT_DEFER_QUARTERS
				return JWResult.Reject.PARAM_RANGE
		return JWResult.OK

	if kind == Kind.BUDGET_REALLOCATE:
		var fl: int = c_arg[base + SLOT_FROM_LINE]
		if fl < 0 or fl >= JWUnits.PAY_LINE_N:
			_last_reject_slot = SLOT_FROM_LINE
			return JWResult.Reject.PARAM_RANGE
		var tl: int = c_arg[base + SLOT_TO_LINE]
		if tl < 0 or tl >= JWUnits.PAY_LINE_N:
			_last_reject_slot = SLOT_TO_LINE
			return JWResult.Reject.PARAM_RANGE
		if fl == tl:
			# 自己划给自己：额度不变而账面多一条调整记录，是纯噪声，不是合法意图。
			_last_reject_slot = SLOT_TO_LINE
			return JWResult.Reject.PARAM_RANGE
		var amt: int = c_arg[base + SLOT_REALLOC_AMOUNT]
		if amt < 1 or amt > JWUnits.AMOUNT_MAX:
			_last_reject_slot = SLOT_REALLOC_AMOUNT
			return JWResult.Reject.PARAM_RANGE
		return JWResult.OK

	if kind == Kind.ISSUE_BOND:
		var ba: int = c_arg[base + SLOT_BOND_AMOUNT]
		if ba < 1 or ba > JWUnits.AMOUNT_MAX:
			_last_reject_slot = SLOT_BOND_AMOUNT
			return JWResult.Reject.PARAM_RANGE
		var tn: int = c_arg[base + SLOT_BOND_TENOR]
		if tn < TENOR_MIN or tn > TENOR_MAX:
			# ADV-C07：tenor 0 会让到期表为空而 outstanding > 0，直接破坏 INV-037。
			_last_reject_slot = SLOT_BOND_TENOR
			return JWResult.Reject.PARAM_RANGE
		var hd: int = c_arg[base + SLOT_BOND_HOLDER]
		if hd != JWUnits.Holder.INVPOOL and hd != JWUnits.Holder.ROW:
			_last_reject_slot = SLOT_BOND_HOLDER
			return JWResult.Reject.PARAM_RANGE
		return JWResult.OK

	if kind == Kind.DEBT_RESTRUCTURE:
		# R-CAP-01：参数是批次的稳定实体号（开局存量债为负数），存在与否由 S02 判 NOT_FOUND，这里不判形状。
		var md: int = c_arg[base + SLOT_RESTRUCTURE_MODE]
		if md < 0 or md >= RESTRUCTURE_MODE_N:
			_last_reject_slot = SLOT_RESTRUCTURE_MODE
			return JWResult.Reject.PARAM_RANGE
		return JWResult.OK

	if kind == Kind.SET_PAYMENT_PRIORITY:
		var pk: int = c_arg[base + SLOT_PRIORITY_PACKED]
		if pk < 0 or pk > PRIORITY_PACKED_MAX:
			_last_reject_slot = SLOT_PRIORITY_PACKED
			return JWResult.Reject.PRIORITY_INCOMPLETE
		if _priority_seen_set(pk) != PRIORITY_FULL_SET:
			# 8 档必须是全排列：少一档就等于「这档永不支付」，欠付会被静默藏起来。
			_last_reject_slot = SLOT_PRIORITY_PACKED
			return JWResult.Reject.PRIORITY_INCOMPLETE
		return JWResult.OK

	if kind == Kind.SET_STANDING_RULE:
		var rl: int = c_arg[base + SLOT_RULE]
		if rl < 0 or rl >= STANDING_RULE_N:
			_last_reject_slot = SLOT_RULE
			return JWResult.Reject.PARAM_RANGE
		var rv: int = c_arg[base + SLOT_RULE_VALUE]
		if rv < 0 or rv > JWUnits.AMOUNT_MAX:
			_last_reject_slot = SLOT_RULE_VALUE
			return JWResult.Reject.PARAM_RANGE
		return JWResult.OK

	if kind == Kind.SELECT_MANDATE_GOAL:
		var gl: int = c_arg[base + SLOT_GOAL]
		if gl < JWUnits.MandateGoal.INDUSTRY or gl > JWUnits.MandateGoal.FISCAL:
			_last_reject_slot = SLOT_GOAL
			return JWResult.Reject.PARAM_RANGE
		if c_issued_q[i] != 0:
			# docs/11 §6.1 命令 12：仅 q == 0 可用。开局之后改目标等于改考核口径。
			return JWResult.Reject.PRECONDITION
		return JWResult.OK

	# _check_shape 已经挡掉未知命令码，走到这里说明 _arity_of 与本表不同步。
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, kind, 0)


## 撤销命令的冷却判定（docs/11 §6.1 命令 3「冷却」；docs/12 §2.1 第 2 道闸；INV-098）的提交期投影。
## 步骤：CMD / S01 §01.5（经 _validate_row）
## 前置：行 i 已在缓冲里，kind == POLICY_REPEAL，pr ∈ [0, POLICY_N)
## 后置：不改状态
## 不变量：INV-098、INV-137（判定只读命令缓冲与内容包，被拒时状态哈希不变）
## 失败：无（内容包未装填时返回 false，交给 S02 判）
##
## 为什么放得进形状层：冷却截止季 `cooldown_until_q` 只由 S02 受理成功的开关命令写成 `q + cooldown_q`
## （JWPolicyEngine.try_enact / try_repeal），而「哪条开关命令在 S02 受理成功」就记在本缓冲里——
## S02 把被拒的命令改写成 accepted == 0（JWTurnRunner._apply_command）。所以只用**已结算**的命令
## （issued_q 早于本行）与内容包的 cooldown_q 就能得出 S02 此刻的冷却截止季，不读任何 SimCore 状态，
## 依赖秩仍是「≤1 + JWPolicyDef」。权威判定仍在 S02（try_repeal 的冷却闸不删），这里只是让冷却期内的
## 撤销在提交时就拿到 E_POLICY_COOLDOWN，而不是先被接受、再在结算里被改判。
##
## 只在「最近一次成功开关是开启」时判冷却：那说明政策此刻处于开启状态，S02 的 try_repeal
## 过得了「未开启 ⇒ NOT_FOUND」那一道，下一道正是冷却；最近一次是撤销时政策已关，S02 给的是 NOT_FOUND，
## 这里不替它改判成冷却。同季尚未结算的命令一律不看——它们可能在 S02 被拒，按它们预判就是替 S02 做决定。
func _repeal_in_cooldown(i: int, pr: int, defs: JWPolicyDef) -> bool:
	if defs == null or defs.cooldown_q.size() != JWUnits.POLICY_N:
		return false
	var q_now: int = c_issued_q[i]
	# 追加写的缓冲里，已受理的行季号单调不减（乱序的行已被判 COMMAND_ORDER），
	# 所以倒序扫到的第一条已结算开关命令就是最近一次成功开关。
	var j: int = i - 1
	while j >= 0:
		var kj: int = c_kind[j]
		if c_issued_q[j] < q_now and c_accepted[j] == 1 and c_reject_code[j] == JWResult.OK \
				and (kj == Kind.POLICY_ENACT or kj == Kind.POLICY_REPEAL) \
				and c_arg[j * ARG_SLOTS + SLOT_POLICY] == pr:
			if kj == Kind.POLICY_REPEAL:
				return false
			return q_now < c_issued_q[j] + defs.cooldown_q[pr]
		j -= 1
	return false


## 命令码 → 参数个数（占前 arity 个槽）。未知命令码返回 -1。
## 步骤：CMD / S01
## 前置：无
## 后置：不改状态
## 不变量：docs/11 §6.1 的 args 列
## 失败：无
static func _arity_of(kind: int) -> int:
	if kind == Kind.POLICY_ENACT:
		return 6
	if kind == Kind.POLICY_SET_PARAMS:
		return 5
	if kind == Kind.POLICY_REPEAL:
		return 1
	if kind == Kind.PROJECT_LAUNCH:
		return 4
	if kind == Kind.PROJECT_CANCEL:
		return 1
	if kind == Kind.PROJECT_DEFER:
		return 2
	if kind == Kind.BUDGET_REALLOCATE:
		return 3
	if kind == Kind.ISSUE_BOND:
		return 3
	if kind == Kind.DEBT_RESTRUCTURE:
		return 2
	if kind == Kind.SET_PAYMENT_PRIORITY:
		return 1
	if kind == Kind.SET_STANDING_RULE:
		return 2
	if kind == Kind.SELECT_MANDATE_GOAL:
		return 1
	if kind == Kind.ADVANCE_QUARTER:
		return 0
	return -1


## 内容包是否已经能回答政策相关的判定（未加载时一律 UNKNOWN_POLICY，不猜）。
## 步骤：CMD / S01
## 前置：无
## 后置：不改状态
## 不变量：INV-099
## 失败：无
static func _defs_ready(defs: JWPolicyDef) -> bool:
	if defs == null:
		return false
	if defs.kind.size() != JWUnits.POLICY_N:
		return false
	if defs.param_min_ppm.size() != JWUnits.POLICY_PARAM_N:
		return false
	if defs.param_max_ppm.size() != JWUnits.POLICY_PARAM_N:
		return false
	return true


## 按位打包 8 个档位值，**不判全排列**（读档复原专用）。
## 步骤：读档
## 前置：order.size() == JWUnits.PAY_LINE_N
## 后置：不改状态
## 不变量：INV-131（含被拒命令的逐位复原）
## 失败：出现 0..7 之外的档位值（只可能来自手改的存档）→ 返回 -1，
##       它不是任何合法 packed 值，validate_batch 必判 PRIORITY_INCOMPLETE
static func _pack_digits(order: PackedInt64Array) -> int:
	if order.size() != JWUnits.PAY_LINE_N:
		return -1
	var packed: int = 0
	var i: int = 0
	while i < JWUnits.PAY_LINE_N:
		var v: int = order[i]
		if v < 0 or v > PRIORITY_MASK:
			return -1
		packed = packed | (v << (PRIORITY_BITS * i))
		i += 1
	return packed


## 打包的优先级里出现过哪些档（位集合）。全排列当且仅当返回 PRIORITY_FULL_SET。
## 步骤：CMD / S02
## 前置：packed ∈ [0, PRIORITY_PACKED_MAX]
## 后置：不改状态
## 不变量：docs/11 §6.1 命令 10
## 失败：无
static func _priority_seen_set(packed: int) -> int:
	if packed < 0 or packed > PRIORITY_PACKED_MAX:
		return 0
	var seen: int = 0
	var i: int = 0
	while i < JWUnits.PAY_LINE_N:
		seen = seen | (1 << ((packed >> (PRIORITY_BITS * i)) & PRIORITY_MASK))
		i += 1
	return seen


# ── 私有：JSON Lines ─────────────────────────────────────────────────────

## 拼一条 JSON 行（字段顺序固定，逐字节稳定）。
## 步骤：存档
## 前置：index ∈ [0, count)
## 后置：不改状态
## 不变量：INV-131；docs/11 §6.1 的行格式
## 失败：无
func _line_of(index: int) -> String:
	var s: String = "{\"" + JSON_KEY_COMMAND_ID + "\":" + str(c_command_id[index])
	s += ",\"" + JSON_KEY_ISSUED_Q + "\":" + str(c_issued_q[index])
	s += ",\"" + JSON_KEY_KIND + "\":\"" + _kind_name(c_kind[index]) + "\""
	s += ",\"" + JSON_KEY_ARGS + "\":" + _args_json(index)
	s += ",\"" + JSON_KEY_ACCEPTED + "\":" + str(c_accepted[index])
	s += ",\"" + JSON_KEY_REJECT_CODE + "\":" + str(c_reject_code[index])
	s += "}"
	return s


## 命令码 → JSON 的 kind 名（未知码退回十进制数字串，保证坏行仍可读回并被判定）。
## 步骤：存档
## 前置：无
## 后置：不改状态
## 不变量：docs/11 §6.1 的命令码表
## 失败：无
static func _kind_name(kind: int) -> String:
	var i: int = 0
	while i < KIND_CODES.size():
		if KIND_CODES[i] == kind:
			return KIND_NAMES[i]
		i += 1
	return str(kind)


## JSON 的 kind 名 → 命令码（认名字也认十进制数字串）。未知返回 -1。
## 步骤：读档
## 前置：无
## 后置：不改状态
## 不变量：docs/11 §6.1 的命令码表
## 失败：无
static func _kind_code(name: String) -> int:
	var i: int = 0
	while i < KIND_NAMES.size():
		if KIND_NAMES[i] == name:
			return KIND_CODES[i]
		i += 1
	if name.is_valid_int():
		return name.to_int()
	return -1


## 某种命令的参数键名表（下标 == 槽位；长度 == arity）。
## 步骤：存档 / 读档
## 前置：kind 合法
## 后置：不改状态
## 不变量：docs/11 §6.1 的 args 列（键名逐字取自契约）
## 失败：未知命令码 → 空表
static func _arg_keys(kind: int) -> PackedStringArray:
	if kind == Kind.POLICY_ENACT:
		return PackedStringArray(["policy_id", "param_0", "param_1", "param_2", "param_3",
				"funding_source"])
	if kind == Kind.POLICY_SET_PARAMS:
		return PackedStringArray(["policy_id", "param_0", "param_1", "param_2", "param_3"])
	if kind == Kind.POLICY_REPEAL:
		return PackedStringArray(["policy_id"])
	if kind == Kind.PROJECT_LAUNCH:
		return PackedStringArray(["policy_id", "region_id", "scale_ppm", "funding_source"])
	if kind == Kind.PROJECT_CANCEL:
		return PackedStringArray(["project_id"])
	if kind == Kind.PROJECT_DEFER:
		return PackedStringArray(["project_id", "quarters"])
	if kind == Kind.BUDGET_REALLOCATE:
		return PackedStringArray(["from_line", "to_line", "amount_uu"])
	if kind == Kind.ISSUE_BOND:
		return PackedStringArray(["amount_uu", "tenor_q", "holder"])
	if kind == Kind.DEBT_RESTRUCTURE:
		return PackedStringArray(["bond_id", "mode"])
	if kind == Kind.SET_STANDING_RULE:
		return PackedStringArray(["rule", "value"])
	if kind == Kind.SELECT_MANDATE_GOAL:
		return PackedStringArray(["goal"])
	# kind 10 的 order[] 是数组形态，不走键名表；kind 99 无参数。
	return PackedStringArray()


## 某个参数槽装的是不是稳定 ID 下标（读档时才可能遇到字符串形态）。
## 步骤：读档
## 前置：kind 合法
## 后置：不改状态
## 不变量：docs/17 §4.28（ID 在 LOAD 期解析成下标）
## 失败：无：非 ID 槽返回 -1
static func _id_kind_of_slot(kind: int, slot: int) -> int:
	if slot == SLOT_POLICY and (kind == Kind.POLICY_ENACT or kind == Kind.POLICY_SET_PARAMS
			or kind == Kind.POLICY_REPEAL or kind == Kind.PROJECT_LAUNCH):
		return JWIds.IdKind.POLICY
	if slot == SLOT_PROJECT and (kind == Kind.PROJECT_CANCEL or kind == Kind.PROJECT_DEFER):
		return JWIds.IdKind.PROJECT
	if slot == SLOT_BOND and kind == Kind.DEBT_RESTRUCTURE:
		return JWIds.IdKind.BOND
	if slot == SLOT_LAUNCH_REGION and kind == Kind.PROJECT_LAUNCH:
		return JWIds.IdKind.REGION
	return -1


## 拼 `args` 对象（键名顺序 == 槽位顺序）。
## 步骤：存档
## 前置：index ∈ [0, count)
## 后置：不改状态
## 不变量：docs/11 §6.1
## 失败：无
func _args_json(index: int) -> String:
	var kind: int = c_kind[index]
	var base: int = index * ARG_SLOTS
	if kind == Kind.SET_PAYMENT_PRIORITY:
		# order[] 按契约写成数组：它是 8 个值，读回来再打包，逐位可还原。
		var s: String = "{\"order\":["
		var packed: int = c_arg[base + SLOT_PRIORITY_PACKED]
		var i: int = 0
		while i < JWUnits.PAY_LINE_N:
			if i > 0:
				s += ","
			s += str((packed >> (PRIORITY_BITS * i)) & PRIORITY_MASK)
			i += 1
		return s + "]}"
	var keys: PackedStringArray = _arg_keys(kind)
	if keys.is_empty():
		return "{}"
	var out: String = "{"
	var j: int = 0
	while j < keys.size():
		if j > 0:
			out += ","
		out += "\"" + keys[j] + "\":" + str(c_arg[base + j])
		j += 1
	return out + "}"


## 把一行已解析的 JSON 追加进缓冲（读档专用）。
## 步骤：读档
## 前置：row 是 JSON 对象
## 后置：成功则 count += 1，且该行的 accepted / reject_code 逐位复原
## 不变量：INV-131（含被拒命令）
## 失败：字段缺失 / 非整数 / 超出双精度精确区间 → Load.FILE_FORMAT（调用方丢这一行）
func _append_parsed_row(row: Dictionary, ids: JWIds) -> int:
	if not row.has(JSON_KEY_COMMAND_ID) or not row.has(JSON_KEY_ISSUED_Q) \
			or not row.has(JSON_KEY_KIND) or not row.has(JSON_KEY_ARGS):
		return JWResult.Load.FILE_FORMAT
	var cid: int = _to_int(row[JSON_KEY_COMMAND_ID])
	if cid == SAFE_JSON_INT_MAX or cid < 1:
		return JWResult.Load.FILE_FORMAT
	var iq: int = _to_int(row[JSON_KEY_ISSUED_Q])
	if iq == SAFE_JSON_INT_MAX:
		return JWResult.Load.FILE_FORMAT
	if typeof(row[JSON_KEY_KIND]) != TYPE_STRING:
		return JWResult.Load.FILE_FORMAT
	var kind: int = _kind_code(row[JSON_KEY_KIND])
	if kind == -1 and row[JSON_KEY_KIND] != "-1":
		# 连数字都不是的 kind：这一行读不成命令，按坏行丢。
		return JWResult.Load.FILE_FORMAT
	# 命令码本身非法（未来版本的码、或被篡改的码）仍然读进来：被拒命令必须留在命令流里
	# （INV-131/137），判定交给 validate_batch，那里会给出 Reject.PARAM_RANGE。
	if typeof(row[JSON_KEY_ARGS]) != TYPE_DICTIONARY:
		return JWResult.Load.FILE_FORMAT
	var args_in: Dictionary = row[JSON_KEY_ARGS]

	var slots: PackedInt64Array = PackedInt64Array()
	slots.resize(ARG_SLOTS)
	slots.fill(0)
	if kind == Kind.SET_PAYMENT_PRIORITY:
		if not args_in.has("order") or typeof(args_in["order"]) != TYPE_ARRAY:
			return JWResult.Load.FILE_FORMAT
		var order_in: Array = args_in["order"]
		if order_in.size() != JWUnits.PAY_LINE_N:
			return JWResult.Load.FILE_FORMAT
		var order: PackedInt64Array = PackedInt64Array()
		order.resize(JWUnits.PAY_LINE_N)
		var k: int = 0
		while k < JWUnits.PAY_LINE_N:
			var ov: int = _to_int(order_in[k])
			if ov == SAFE_JSON_INT_MAX:
				return JWResult.Load.FILE_FORMAT
			order[k] = ov
			k += 1
		# 不走 pack_payment_priority：那是带全排列判定的入口，会把「被拒的 order」压成 -1，
		# 于是写出去再读回来就不再逐位相同了。被拒的命令必须原样留在命令流里（INV-137），
		# 判定由 validate_batch 统一做，这里只负责「读得进、还原得回」。
		slots[SLOT_PRIORITY_PACKED] = _pack_digits(order)
	else:
		var keys: PackedStringArray = _arg_keys(kind)
		var j: int = 0
		while j < keys.size():
			if not args_in.has(keys[j]):
				return JWResult.Load.FILE_FORMAT
			var raw: Variant = args_in[keys[j]]
			var v: int = 0
			if typeof(raw) == TYPE_STRING:
				# 手写的 §6.1 示例行用稳定 ID 字符串；LOAD 期经 JWIds 解析成下标。
				var idk: int = _id_kind_of_slot(kind, j)
				if idk < 0 or ids == null:
					return JWResult.Load.FILE_FORMAT
				var sid: String = raw
				v = ids.resolve(idk, sid)
				if v < 0:
					return JWResult.Load.FILE_FORMAT
			else:
				v = _to_int(raw)
				if v == SAFE_JSON_INT_MAX:
					return JWResult.Load.FILE_FORMAT
			slots[j] = v
			j += 1

	var i: int = _append_row(kind, slots, iq)
	if i < 0:
		return JWResult.Load.SAVE_CORRUPT
	c_command_id[i] = cid
	if row.has(JSON_KEY_ACCEPTED):
		var acc: int = _to_int(row[JSON_KEY_ACCEPTED])
		c_accepted[i] = 1 if acc == 1 else 0
	if row.has(JSON_KEY_REJECT_CODE):
		var rc: int = _to_int(row[JSON_KEY_REJECT_CODE])
		c_reject_code[i] = rc if rc != SAFE_JSON_INT_MAX else 0
	return JWResult.OK


## JSON 数值 → 整数。非整数、非数字、或超出双精度精确区间都返回哨兵 SAFE_JSON_INT_MAX。
## 步骤：读档
## 前置：无
## 后置：不改状态
## 不变量：INV-001（读档是唯一可能把 float 混进状态的入口，必须在这里挡住）
## 失败：返回哨兵，由调用方转 Load.FILE_FORMAT
##
## Godot 4 的 JSON 把**全部**数字解析成 float（实测 `137` → `137.0`），所以不能只看类型：
## 先取整再与原值比对，`1.5` 这种带小数的立刻现形；量级超过 2^53 的则精度已失，一律拒。
static func _to_int(v: Variant) -> int:
	var t: int = typeof(v)
	if t != TYPE_INT and t != TYPE_FLOAT:
		return SAFE_JSON_INT_MAX
	var iv: int = int(v)
	if v != iv:
		return SAFE_JSON_INT_MAX
	if iv >= SAFE_JSON_INT_MAX or iv <= -SAFE_JSON_INT_MAX:
		return SAFE_JSON_INT_MAX
	return iv


# ── 私有：规范化编码（docs/11 §6.4 的字节布局） ───────────────────────────

## 追加一个整数标量条目：uint16 len(id) + id 的 UTF-8 + uint8 tag + int64 小端。
## 步骤：存档
## 前置：无
## 后置：_hash_buf 变长
## 不变量：INV-133（replay_hash 的口径）
## 失败：id 过长 → Fault.INDEX_OUT_OF_RANGE
func _canon_scalar(id: String, v: int) -> void:
	var idb: PackedByteArray = id.to_utf8_buffer()
	var idn: int = idb.size()
	if idn > ID_BYTES_MAX:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idn, ID_BYTES_MAX)
		return
	var base: int = _hash_buf.size()
	_hash_buf.resize(base + 2 + idn + 1 + 8)
	_hash_buf.encode_u16(base, idn)
	_blit(base + 2, idb)
	_hash_buf.encode_u8(base + 2 + idn, TAG_INT)
	_hash_buf.encode_s64(base + 3 + idn, v)


## 追加一个整数数组条目（**只取前 used 个元素**，容量不进哈希）。
## 步骤：存档
## 前置：used <= a.size()
## 后置：_hash_buf 变长
## 不变量：INV-133（容量随扩容变化，进哈希会让 replay_hash 依赖历史分配路径）
## 失败：id 过长 → Fault.INDEX_OUT_OF_RANGE；used 越界 → 截到 a.size()
func _canon_array(id: String, a: PackedInt64Array, used: int) -> void:
	var n: int = used
	if n > a.size():
		n = a.size()
	if n < 0:
		n = 0
	var idb: PackedByteArray = id.to_utf8_buffer()
	var idn: int = idb.size()
	if idn > ID_BYTES_MAX:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idn, ID_BYTES_MAX)
		return
	var base: int = _hash_buf.size()
	_hash_buf.resize(base + 2 + idn + 1 + 4 + 8 * n)
	_hash_buf.encode_u16(base, idn)
	_blit(base + 2, idb)
	_hash_buf.encode_u8(base + 2 + idn, TAG_ARRAY)
	_hash_buf.encode_u32(base + 3 + idn, n)
	var off: int = base + 3 + idn + 4
	var i: int = 0
	while i < n:
		_hash_buf.encode_s64(off + 8 * i, a[i])
		i += 1


## 把 src 的全部字节拷到 _hash_buf 的 offset 处（_hash_buf 必须已经够长）。
## 步骤：规范化编码内部
## 前置：_hash_buf.size() >= offset + src.size()
## 后置：_hash_buf[offset + i] == src[i]
## 不变量：INV-133
## 失败：无
func _blit(offset: int, src: PackedByteArray) -> void:
	var n: int = src.size()
	var i: int = 0
	while i < n:
		_hash_buf[offset + i] = src[i]
		i += 1
