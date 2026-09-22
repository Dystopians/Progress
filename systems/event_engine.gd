## 12 个事件模板的**条件求值**（不是随机弹窗）。用 `rng.event` 流，与 `rng.shock` 完全独立。
## **事件只能写 6 个白名单字段的 ppm 增量，首版没有任何账本效应**（INV-130）。
##
## 骨架依据：docs/17_api_skeleton.md §4.30（秩 A2；只允许引用秩 ≤10）。
##
## 「存档重载不得重抽已确定事件」的落地方式（与 §5.14 冲击的 `shock_log` 先查后抽不同）：
## 事件没有跨季悬挂的待定结果——每季的触发在本季当场定案，结果写进 `fire_count` /
## `last_fire_q` 两个 **S 类**字段，随存档一起走。重放同一季时，计数器式 RNG 以
## `(stream, q, draw_index)` 为唯一输入，`draw_count` 又整体入档（INV-131），
## 因此同一季的同一次抽样必然复现同一个值。**不需要也不存在第二份事件日志**。
class_name JWEventEngine
extends RefCounted


## 每个事件的触发条件槽位与效应槽位数量。
##
## docs/17 §4.30 写的是 12×4，但 `content/events/*.json` 的实测用量是
## 触发条件最多 10 条（E06）、效应最多 7 条（E07/E11）、证据引用最多 19 条（E07）。
## 按 4 装载会**静默丢掉**多出来的条件——那等于把 E06 的 10 条门槛降成 4 条，
## 是最难被发现的一类事实伪造。故槽宽取 20（≥ 19），12×20 的形状与契约一致，
## 只是把常数放宽；已登记为契约同步项（见本波 open_questions）。
const SLOT_N: int = 20

## `last_fire_q` 的「从未触发」初值（docs/17 §4.30 成员表）。
## 取 −999 而不是 −cooldown：任何合法 `cooldown_q`（≤ 8）加上它都远小于 0 ≤ q，
## 于是「首次触发不受冷却限制」不靠特例分支，靠数值本身成立。
const NEVER_FIRED_Q: int = -999


# ── 触发条件比较算子（docs/11 §5.13 的 V-EV-03 闭集合，**没有表达式求值器**） ──
#
# 值即稠密下标，顺序逐字照抄契约里的 `{lt, le, eq, ne, ge, gt}`，不得重排。

const OP_LT: int = 0
const OP_LE: int = 1
const OP_EQ: int = 2
const OP_NE: int = 3
const OP_GE: int = 4
const OP_GT: int = 5
const OP_N: int = 6


# ── 效应落点码（docs/11 §5.13 的事件可写白名单，唯一的 6 项，INV-130） ──────
#
# 与 `JWPolitics.EVT_*` / `JWInterestGroups.EVT_*` 是**同一套码**：那两个类各自声明
# 自己负责的那几项，本类声明全部六项并在 validate() 里逐项比对两边的常量值。
# 比对不是装饰：三处各写一遍数字，只要有人改了一处而没改另外两处，
# 事件就会静默落到错误的字段上，而单元测试未必覆盖得到那一条事件卡。

const TARGET_NONE: int = -1
const TARGET_EXPECTATION_PPM: int = 0
const TARGET_TRUST_PPM: int = 1
const TARGET_SUPPORT_PPM: int = 2
const TARGET_ORG_POWER_PPM: int = 3
const TARGET_STANCE_PPM: int = 4
const TARGET_ADMIN_CAPACITY_PPM: int = 5
const TARGET_N: int = 6

## 单条效应的 ppm 增量绝对值上界（内容实测最大 120 000）。
## 越界即 `Load.EVENT_FIELD`：事件是「推一把」，不是「一步归零」。
const DELTA_PPM_MAX: int = 1_000_000


# ── metric / evidence 槽位哨兵 ──────────────────────────────────────────────

## 空槽（该事件没有用满 SLOT_N 个槽位）。
const METRIC_NONE: int = -1

## 加载期解析不出该稳定 ID（V-EV-02 的登记方式）。validate() 见到即 `Load.METRIC_UNKNOWN`。
const METRIC_UNRESOLVED: int = -2

## 证据引用的空槽。
const EVIDENCE_NONE: int = -1


# ── scope 编码（docs/11 §5.13 的 `scope` 字符串在 LOAD 期解析成本编码） ──────
#
# `scope_code == SCOPE_NONE` 表示 JSON 里根本没有 `scope` 键（全国口径）；
# 其余一律 `kind * SCOPE_STRIDE + idx`，`idx` 是该 kind 的稠密下标。
# 步长取 100 是因为全部 kind 的基数都 < 100（GROUP 36、STANCE 36、CELL 16 是最大的三个），
# 于是编码与解码都只是一次乘加，结算期不碰字符串、不查字典。
#
# 效应侧的语义由内容包 `_note_scope_semantics_note_zh` 钉死：
# `state.group.*` 写 `region.<r>` 表示**对该地区的 9 个群组各施加同一 delta**，
# 不是对地区做一次加总写入；`state.bloc.*` 写 `bloc.<id>` 表示该集团本身。

const SCOPE_NONE: int = -1
const SCOPE_STRIDE: int = 100
const SCOPE_KIND_REGION: int = 0
const SCOPE_KIND_SECTOR: int = 1
const SCOPE_KIND_CELL: int = 2
const SCOPE_KIND_PUBSERV: int = 3
const SCOPE_KIND_GROUP: int = 4
const SCOPE_KIND_BLOC: int = 5
const SCOPE_KIND_STANCE: int = 6
const SCOPE_KIND_POLICY: int = 7
## R-EVENT-01：`state.group.*` / `flow.group.*` 这类按群组的数组配 `region.<r>` 范围：取该地区 9 个群组之和。
const SCOPE_KIND_REGION_GROUPS: int = 8
const SCOPE_KIND_N: int = 9

## R-EVENT-01：`derived.*` 不进状态注册表（读时计算）。事件条件用到的 7 个在加载期编成
## DERIVED_BASE + 下标，由 _read_derived 按同一口径从状态直接算出。
const DERIVED_BASE: int = 1_000_000
const DERIVED_IDS: PackedStringArray = [
	"derived.fiscal.next4q_debt_service_uu",
	"derived.gov.debt_uu",
	"derived.group.housing_burden_ppm",
	"derived.labor.unemployment_ppm",
	"derived.politics.support_national_ppm",
	"derived.region.electricity_availability_ppm",
	"derived.region.housing_occupied_units",
	# 账户表的视图（docs/10：state.gov.cash_uu 是 JWAccount 的视图，不单独进注册表）。
	"state.gov.cash_uu",
	"state.gov.wip_uu",
]


# ── log.rng 的 purpose 码（沿用 sim/world/shocks.gd 立下的 SUBSYS*1000 惯例） ─
#
# 本块归属 SUBSYS_POLITICS，故基址 10 000。留出 10 001…10 099 给 JWPolitics 自己的抽样，
# 事件从 +100 起按 event 下标展开（10 100…10 111），日志一眼能看出是哪张事件卡在抽。

const PURPOSE_BASE: int = JWUnits.SUBSYS_POLITICS * 1000
const PURPOSE_EVENT_BASE: int = PURPOSE_BASE + 100


# ── §1.6 状态块协议的注册表（本块归属 SUBSYS_POLITICS） ──────────────────

## 本块各数组所属子系统（与 STATE_ARRAY_IDS 等长），用于 subsystem_hash 与 WriteGuard。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_POLITICS,
	JWUnits.SUBSYS_POLITICS,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.event.fire_count",
	"state.event.last_fire_q",
]
const STATE_SCALAR_IDS: PackedStringArray = []
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = []


# ── 状态（写入者：S08） ──────────────────────────────────────────────────

## `state.event.fire_count[]`，长 EVENT_N，初值 0。
var fire_count: PackedInt64Array = PackedInt64Array()

## `state.event.last_fire_q[]`，长 EVENT_N，初值 −999。
var last_fire_q: PackedInt64Array = PackedInt64Array()


# ── 内容（写入者：LOAD） ────────────────────────────────────────────────

## `content.event.trigger_metric[]`，长 EVENT_N × SLOT_N。
var trigger_metric: PackedInt64Array = PackedInt64Array()

## `content.event.trigger_scope[]`，长 EVENT_N × SLOT_N。
var trigger_scope: PackedInt64Array = PackedInt64Array()

## `content.event.trigger_op[]`，长 EVENT_N × SLOT_N；op ∈ {lt, le, eq, ne, ge, gt}。
var trigger_op: PackedInt64Array = PackedInt64Array()

## `content.event.trigger_value[]`，长 EVENT_N × SLOT_N。
var trigger_value: PackedInt64Array = PackedInt64Array()

## `content.event.probability_ppm[]`，长 EVENT_N。
var probability_ppm: PackedInt64Array = PackedInt64Array()

## `content.event.cooldown_q[]`，长 EVENT_N。
var cooldown_q: PackedInt64Array = PackedInt64Array()

## `content.event.max_occurrences[]`，长 EVENT_N。
var max_occurrences: PackedInt64Array = PackedInt64Array()

## `content.event.effect_target[]`，长 EVENT_N × SLOT_N；只能落在 6 个白名单字段上。
var effect_target: PackedInt64Array = PackedInt64Array()

## `content.event.effect_scope[]`，长 EVENT_N × SLOT_N。
var effect_scope: PackedInt64Array = PackedInt64Array()

## `content.event.effect_delta_ppm[]`，长 EVENT_N × SLOT_N。
var effect_delta_ppm: PackedInt64Array = PackedInt64Array()

## `content.event.evidence_ref[]`，长 EVENT_N × SLOT_N；供报告追溯实际取值。
var evidence_ref: PackedInt64Array = PackedInt64Array()

## `content.event.rng_stream[]`，长 EVENT_N，取值必须恒为 `JWUnits.RngStream.EVENT`。
##
## 骨架成员表里没有这一项，但 V-EV-04（不得借用 `rng.shock`）是契约点名要 validate() 报的
## `Load.EVENT_STREAM`。若不把 JSON 的 `rng_stream` 落成一个数组，这条校验在加载之后
## 就**没有任何机器可读的依据**，只能写成永远通过的空检查——那正是「空实现假装完成」。
## 已登记为接口变更请求（见本波 interface_requests）。
var rng_stream: PackedInt64Array = PackedInt64Array()

## 每张事件卡里 `ledger_effects` 条目的条数，长 EVENT_N，**必须恒为 0**。
##
## 同上：V-EV-06 的「首版不存在 `ledger_effects` 字段，出现即失败」是 JSON 形状的断言，
## 加载后已无痕迹。让加载器把「数到几条」原样记下来，validate() 才谈得上 `Load.EVENT_LEDGER`。
var ledger_effect_count: PackedInt64Array = PackedInt64Array()


# ── 本季诊断缓冲（class L，不进 state_hash、不进存档，加载期一次性预分配） ──
#
# docs/12 §8 的日志要求：「每次事件触发的条件取值」。
# 这些缓冲**不是状态**：每季 fire_events() 入口整表重置，只供本季报告读取。

## 本季是否触发，长 EVENT_N，取值 0/1。
var _fired: PackedInt64Array = PackedInt64Array()

## 本季逐槽位求值到的**实际** metric 取值，长 EVENT_N × SLOT_N。
var _cond_actual: PackedInt64Array = PackedInt64Array()

## 对应槽位本季是否真的被求值过（短路会让后面的槽位没被读），长 EVENT_N × SLOT_N，取值 0/1。
var _cond_read: PackedInt64Array = PackedInt64Array()

## 本季各证据引用的实际取值，长 EVENT_N × SLOT_N。
var _evidence_value: PackedInt64Array = PackedInt64Array()

## 对应证据槽位的取值是否可得，长 EVENT_N × SLOT_N，取值 0/1。
var _evidence_known: PackedInt64Array = PackedInt64Array()

## 本季触发的事件数。
var _fired_count: int = 0

## `_eval_condition` 在本次 fire_events 内是否遇到未知 metric。
var _eval_metric_unknown: bool = false


# ── 静态小工具（scope 编解码；无除法，floor_div 走 JWMath） ─────────────────

## 把 (kind, idx) 编成一个 scope 码。加载期用；结算期只解码。
## 步骤：LOAD
## 前置：kind ∈ [0, SCOPE_KIND_N)；idx ∈ [0, SCOPE_STRIDE)
## 后置：不改状态
## 不变量：无（纯函数）
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 并返回 SCOPE_NONE
static func scope_code(kind: int, idx: int) -> int:
	if kind < 0 or kind >= SCOPE_KIND_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, kind, SCOPE_KIND_N)
		return SCOPE_NONE
	if idx < 0 or idx >= SCOPE_STRIDE:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idx, SCOPE_STRIDE)
		return SCOPE_NONE
	return kind * SCOPE_STRIDE + idx


## scope 码 → kind。`SCOPE_NONE` 返回 −1。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：无（纯函数）
## 失败：无
static func scope_kind_of(code: int) -> int:
	if code < 0:
		return -1
	return JWMath.floor_div(code, SCOPE_STRIDE)


## scope 码 → 该 kind 内的稠密下标。`SCOPE_NONE` 返回 −1。
## 步骤：全部
## 前置：无
## 后置：不改状态
## 不变量：无（纯函数）
## 失败：无
static func scope_index_of(code: int) -> int:
	if code < 0:
		return -1
	return code - JWMath.mul(JWMath.floor_div(code, SCOPE_STRIDE), SCOPE_STRIDE)


## S08 §8.4：按 event_id 升序求值并触发。
## 步骤：S08 §8.4
## 前置：冷却未到 / 次数用尽 / 条件不成立 → 跳过；`op ∈ {lt, le, eq, ne, ge, gt}`（**没有表达式求值器**）
## 后置：应用 effects（只能是白名单内的 ppm 增量）；记录 evidence_refs 的实际取值供报告追溯；
##       fire_count += 1；last_fire_q = q
## 不变量：INV-009（即使这里多抽 100 次，rng.shock 取值完全不变）、INV-130（事件无账本效应）、
##          INV-011（每次抽样写 log.rng）
## 失败：条件引用不存在的字段 → Fault.METRIC_UNKNOWN（加载期 V-EV-02 已拦截，运行期是兜底）
##
## 事件下标 e 就是 event_id 的升序位次（LOAD 期按 `event.E01`…`event.E12` 登记），
## 所以「按 event_id 升序」在这里等价于「按 e 升序」，不需要再排一次序。
func fire_events(st: JWSimState, q: int) -> int:
	if st == null or st.rng == null or st.politics == null or st.blocs == null:
		# 缺块不是「跳过事件」，是流水线装配错了：不能让一局悄悄在没有政治块的情况下跑下去。
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, JWUnits.Phase.S08, 0)
	# R-EVENT-01：两个跨季计数住在政治块里（进存档与哈希），不再用本类自己的数组。
	if st.politics.event_fire_count.size() != JWUnits.EVENT_N \
			or st.politics.event_last_fire_q.size() != JWUnits.EVENT_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				st.politics.event_fire_count.size(), JWUnits.EVENT_N)
	if probability_ppm.size() != JWUnits.EVENT_N or cooldown_q.size() != JWUnits.EVENT_N \
			or max_occurrences.size() != JWUnits.EVENT_N or _fired.size() != JWUnits.EVENT_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				probability_ppm.size(), JWUnits.EVENT_N)
	var wide: int = JWUnits.EVENT_N * SLOT_N
	if trigger_metric.size() != wide or trigger_scope.size() != wide \
			or trigger_op.size() != wide or trigger_value.size() != wide \
			or effect_target.size() != wide or effect_scope.size() != wide \
			or effect_delta_ppm.size() != wide or evidence_ref.size() != wide \
			or _cond_actual.size() != wide or _cond_read.size() != wide \
			or _evidence_value.size() != wide or _evidence_known.size() != wide:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				trigger_metric.size(), wide)
	# 本季已经有故障时不再抽样：抽样会推进 draw_count，而故障局面下的推进无法重放对账
	# （docs/12 §9「有故障即中止推进」）。同时这保证了下面「pending 由 0 变非 0」这个
	# 未知 metric 的探测判据是精确的——否则先前的故障会把 read_metric 的登记吞掉。
	if JWResult.has_pending():
		return JWResult.pending_code()

	_reset_quarter_buffers()
	_eval_metric_unknown = false

	var e: int = 0
	while e < JWUnits.EVENT_N:
		var base: int = e * SLOT_N
		# ── 冷却与次数（docs/12 §8.4 第 1 行，逐字照抄） ──
		if q < st.politics.event_last_fire_q[e] + cooldown_q[e]:
			e += 1
			continue
		if st.politics.event_fire_count[e] >= max_occurrences[e]:
			e += 1
			continue

		# ── 条件：all_of，一条不成立即整张卡不触发 ──
		var all_ok: bool = true
		var has_condition: bool = false
		var slot: int = 0
		while slot < SLOT_N:
			if trigger_metric[base + slot] == METRIC_NONE:
				slot += 1
				continue
			has_condition = true
			if not _eval_condition(st, e, slot):
				all_ok = false
				break
			slot += 1
		if _eval_metric_unknown:
			# 条件引用了不存在的字段。加载期 V-EV-02 本该拦住，跑到这里说明内容与码表脱节：
			# 按契约上报，不猜一个「大概为假」的结论继续往下走。
			return JWResult.Fault.METRIC_UNKNOWN
		if not all_ok:
			e += 1
			continue
		if not has_condition:
			# 一条触发条件都没有的事件卡就是随机弹窗。加载期 validate() 已判 Load.EVENT_COUNT；
			# 运行期兜底：不抽样、不触发，并按「条件引用不存在的字段」同等对待。
			JWResult.raise_fault(JWResult.Fault.METRIC_UNKNOWN, e, 0)
			return JWResult.Fault.METRIC_UNKNOWN

		# ── 概率（rng.event 流，与 rng.shock 完全独立，INV-009） ──
		var roll: int = st.rng.draw_ppm(JWUnits.RngStream.EVENT, PURPOSE_EVENT_BASE + e)
		if roll >= probability_ppm[e]:
			e += 1
			continue

		# ── 触发：先落效应，再记证据，最后推进两个 S 类字段 ──
		var rc: int = _apply_effects(st, e)
		if rc != JWResult.OK:
			return rc
		_record_evidence(e)
		st.politics.event_fire_count[e] = st.politics.event_fire_count[e] + 1
		st.politics.event_last_fire_q[e] = q
		_fired[e] = 1
		_fired_count += 1
		e += 1

	return JWResult.OK


## 单条条件求值（只有比较）。
## 步骤：S08 §8.4
## 前置：metric_code 已在加载期解析
## 后置：不改状态
## 不变量：V-EV-03（op 闭集合）
## 失败：未知 metric → Fault.METRIC_UNKNOWN
func _eval_condition(st: JWSimState, e: int, slot: int) -> bool:
	var i: int = e * SLOT_N + slot
	var metric: int = trigger_metric[i]
	if metric < 0:
		# METRIC_UNRESOLVED（或任何负码）：加载期没能把稳定 ID 解析成整数码。
		JWResult.raise_fault(JWResult.Fault.METRIC_UNKNOWN, metric, e)
		_eval_metric_unknown = true
		return false

	# read_metric 只能用「登记了故障没有」来报未知 metric（它的返回值是 int，没有第二条通道）。
	# 入口已经保证 pending == 0，所以这里的「由 0 变非 0」精确对应本次调用的失败。
	var before: int = JWResult.pending_code()
	var actual: int = _read_metric(st, metric, trigger_scope[i])
	if JWResult.pending_code() != before:
		_eval_metric_unknown = true
		return false

	_cond_actual[i] = actual
	_cond_read[i] = 1

	var want: int = trigger_value[i]
	var op: int = trigger_op[i]
	if op == OP_LT:
		return actual < want
	if op == OP_LE:
		return actual <= want
	if op == OP_EQ:
		return actual == want
	if op == OP_NE:
		return actual != want
	if op == OP_GE:
		return actual >= want
	if op == OP_GT:
		return actual > want
	# 闭集合之外的算子在加载期就是 Load.EVENT_OP。运行期兜底同样按「这条卡不可求值」处理，
	# 而不是默默当成 false —— 否则一张写错 op 的卡会永远安静地不触发，没人发现。
	JWResult.raise_fault(JWResult.Fault.METRIC_UNKNOWN, op, e)
	_eval_metric_unknown = true
	return false


## R-EVENT-01：按条件槽的 metric 码与 scope 码取值。
## scope 码是 kind × SCOPE_STRIDE + 下标，read_metric 要的是**稠密下标**：原先把整个编码当下标传入，
## 只有 region（kind 0）碰巧对得上，cell / group / sector / bloc 等一律越界。
## 步骤：S08 §8.4
## 前置：metric 已在加载期解析（注册表下标或 DERIVED_BASE + k）
## 后置：不改状态
## 不变量：INV-130（只读）
## 失败：未知 metric → Fault.METRIC_UNKNOWN 返回 0
func _read_metric(st: JWSimState, metric: int, scope: int) -> int:
	var kind: int = -1
	var idx: int = 0
	if scope != SCOPE_NONE:
		kind = scope_kind_of(scope)
		idx = scope_index_of(scope)
	if metric >= DERIVED_BASE:
		return _read_derived(st, metric - DERIVED_BASE, kind, idx)
	if kind == SCOPE_KIND_REGION_GROUPS:
		if idx < 0 or idx >= JWUnits.R:
			JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idx, JWUnits.R)
			return 0
		var acc: int = 0
		var g0: int = JWIds.idx_group(idx, 0, 0)
		var g: int = g0
		while g < g0 + JWUnits.A * JWUnits.K:
			acc += st.read_metric(metric, g)
			g += 1
		return acc
	return st.read_metric(metric, idx)


## R-EVENT-01：7 个事件条件用到的 derived.* 取值（与 docs/10 的定义同口径，直接从状态算）。
func _read_derived(st: JWSimState, k: int, kind: int, idx: int) -> int:
	match k:
		0:
			return st.bonds.debt_service_next4q(st.q + 1)
		1:
			return st.bonds.debt_outstanding()
		2:
			# 住房负担 = 本季住房支出 / 本季到手收入（工资 + 财产 + 转移），ppm。
			if kind != SCOPE_KIND_GROUP or idx < 0 or idx >= JWUnits.GROUP:
				JWResult.raise_fault(JWResult.Fault.METRIC_UNKNOWN, k, kind)
				return 0
			var inc: int = st.pop.f_wage_income[idx] + st.pop.f_property_income[idx] \
					+ st.pop.f_transfer_income[idx]
			if inc <= 0:
				return JWUnits.PPM
			return JWMath.clamp_i(JWMath.mul_div_floor(st.pop.f_housing_cost[idx], JWUnits.PPM, inc),
					0, JWUnits.PPM * 10)
		3:
			return st.labor.unemployment_ppm()
		4:
			return st.politics.support_national_ppm(st.pop)
		5:
			# 供电可得率 = (本地用电需求 − 输电之后仍未满足的量) / 需求，ppm；无需求记满格。
			if kind != SCOPE_KIND_REGION or idx < 0 or idx >= JWUnits.R:
				JWResult.raise_fault(JWResult.Fault.METRIC_UNKNOWN, k, kind)
				return 0
			var dem: int = st.sectors.f_elec_demand[idx]
			if dem <= 0:
				return JWUnits.PPM
			var unmet: int = mini(maxi(st.sectors.f_elec_unmet[idx], 0), dem)
			return JWMath.mul_div_floor(dem - unmet, JWUnits.PPM, dem)
		6:
			if kind != SCOPE_KIND_REGION or idx < 0 or idx >= JWUnits.R:
				JWResult.raise_fault(JWResult.Fault.METRIC_UNKNOWN, k, kind)
				return 0
			var occ: int = 0
			var g1: int = JWIds.idx_group(idx, 0, 0)
			var g2: int = g1
			while g2 < g1 + JWUnits.A * JWUnits.K:
				occ += st.pop.housing_occupied[g2]
				g2 += 1
			return occ
		7:
			return st.accounts.cash_of(JWIds.AGENT_GOV)
		8:
			return st.accounts.get_balance(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_WIP))
	JWResult.raise_fault(JWResult.Fault.METRIC_UNKNOWN, k, DERIVED_IDS.size())
	return 0


## 落地一张事件卡的全部 effects（只能是白名单内的 ppm 增量，INV-130）。
## 步骤：S08 §8.4
## 前置：该事件本季已判定触发
## 后置：对应字段加 delta 后由各自的块 clamp；本函数不碰任何账本、现金、库存、人口
## 不变量：INV-130
## 失败：落点或范围不合法 → Fault.WRITE_OUT_OF_SCOPE
func _apply_effects(st: JWSimState, e: int) -> int:
	var base: int = e * SLOT_N
	var slot: int = 0
	while slot < SLOT_N:
		var i: int = base + slot
		var target: int = effect_target[i]
		if target == TARGET_NONE:
			slot += 1
			continue
		var code: int = effect_scope[i]
		var kind: int = scope_kind_of(code)
		var idx: int = scope_index_of(code)
		var delta: int = effect_delta_ppm[i]

		if target == TARGET_EXPECTATION_PPM or target == TARGET_TRUST_PPM \
				or target == TARGET_SUPPORT_PPM:
			# 群组三件套。region.<r> 是「该地区 9 个群组各加同一 delta」
			# （内容包 _note_scope_semantics_note_zh 钉死的口径），不是对地区加总一次。
			if kind == SCOPE_KIND_REGION:
				if idx < 0 or idx >= JWUnits.R:
					return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idx, JWUnits.R)
				var g0: int = JWIds.idx_group(idx, 0, 0)
				var g: int = g0
				while g < g0 + JWUnits.A * JWUnits.K:
					var rc_g: int = st.politics.apply_event_delta(target, g, delta)
					if rc_g != JWResult.OK:
						return rc_g
					g += 1
			elif kind == SCOPE_KIND_GROUP:
				var rc_one: int = st.politics.apply_event_delta(target, idx, delta)
				if rc_one != JWResult.OK:
					return rc_one
			elif code == SCOPE_NONE:
				var gn: int = 0
				while gn < JWUnits.GROUP:
					var rc_n: int = st.politics.apply_event_delta(target, gn, delta)
					if rc_n != JWResult.OK:
						return rc_n
					gn += 1
			else:
				return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, target, code)

		elif target == TARGET_ORG_POWER_PPM:
			if kind != SCOPE_KIND_BLOC:
				return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, target, code)
			var rc_b: int = st.blocs.apply_event_delta(target, idx, delta)
			if rc_b != JWResult.OK:
				return rc_b

		elif target == TARGET_STANCE_PPM:
			# stance 的 scope 是 `bloc.<b>.policy.<p>`，加载期已经折成稠密下标 idx_stance(b, p)：
			# 结算期不碰 String，也不在这里做第二次 id → 下标 的解析。
			if kind != SCOPE_KIND_STANCE:
				return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, target, code)
			var rc_s: int = st.blocs.apply_event_delta(target, idx, delta)
			if rc_s != JWResult.OK:
				return rc_s

		elif target == TARGET_ADMIN_CAPACITY_PPM:
			# 全国唯一的标量，没有范围可言：带 scope 的写法一律拒绝，不做「宽容解释」。
			if code != SCOPE_NONE:
				return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, target, code)
			var rc_a: int = st.politics.apply_event_delta(target, 0, delta)
			if rc_a != JWResult.OK:
				return rc_a

		else:
			# 现金、库存、产能、人口都在这里被挡住（INV-130）。
			return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, target, code)

		slot += 1
	return JWResult.OK


## 记录 evidence_refs 的实际取值，供报告逐条追溯（docs/12 §8 的日志要求）。
## 步骤：S08 §8.4（仅在事件触发后）
## 前置：本事件的条件已全部求值完毕
## 后置：只写本季诊断缓冲，不改任何状态、不做任何抽样
## 不变量：INV-130（证据是只读回看，不得回写状态）
## 失败：无
##
## `evidence_refs` 在 docs/11 §5.13 里只有 metric 稳定 ID，**没有配套的 scope**，
## 因此大多数逐地区／逐 cell 的证据项没有可读的下标。这里**只**记录那些同时也出现在本卡
## 触发条件里的证据项——它们的 scope 由对应的条件槽给出，取值就是刚刚求值到的那个数，
## 不需要第二次 read_metric，也就不会因为证据记账而凭空制造一次 METRIC_UNKNOWN。
## 其余证据项标记为「取值不可得」（`_evidence_known == 0`），由报告层显示为未取值，
## **不填一个看起来合理的 0**。补 `content.event.evidence_scope[]` 已登记为接口变更请求。
func _record_evidence(e: int) -> void:
	var base: int = e * SLOT_N
	var j: int = 0
	while j < SLOT_N:
		var ref: int = evidence_ref[base + j]
		if ref == EVIDENCE_NONE:
			j += 1
			continue
		var slot: int = 0
		while slot < SLOT_N:
			if _cond_read[base + slot] == 1 and trigger_metric[base + slot] == ref:
				_evidence_value[base + j] = _cond_actual[base + slot]
				_evidence_known[base + j] = 1
				break
			slot += 1
		j += 1


## 每季入口整表重置本季诊断缓冲。
## 步骤：S08 §8.4 入口
## 前置：allocate() 已跑过
## 后置：四张缓冲全 0，_fired_count == 0
## 不变量：docs/17 §1.4（热路径不新建对象；fill 是原地写）
## 失败：无
func _reset_quarter_buffers() -> void:
	_fired.fill(0)
	_cond_actual.fill(0)
	_cond_read.fill(0)
	_evidence_value.fill(0)
	_evidence_known.fill(0)
	_fired_count = 0


# ── 本季诊断读口（class L，只读；报告层用，结算路径不依赖） ────────────────

## 本季触发的事件数。
## 步骤：S08 之后
## 前置：fire_events 已跑过
## 后置：不改状态
## 不变量：无
## 失败：无
func fired_count_this_quarter() -> int:
	return _fired_count


## 某张事件卡本季是否触发。
## 步骤：S08 之后
## 前置：e ∈ [0, EVENT_N)
## 后置：不改状态
## 不变量：无
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回 false
func fired_this_quarter(e: int) -> bool:
	if e < 0 or e >= JWUnits.EVENT_N or _fired.size() != JWUnits.EVENT_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, e, JWUnits.EVENT_N)
		return false
	return _fired[e] == 1


## 某个触发条件槽位本季求值到的实际取值（`_cond_read == 0` 时无意义）。
## 步骤：S08 之后
## 前置：e、slot 在范围内
## 后置：不改状态
## 不变量：docs/12 §8「每次事件触发的条件取值」要进日志
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回 0
func condition_actual(e: int, slot: int) -> int:
	var i: int = e * SLOT_N + slot
	if e < 0 or e >= JWUnits.EVENT_N or slot < 0 or slot >= SLOT_N \
			or _cond_actual.size() != JWUnits.EVENT_N * SLOT_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, JWUnits.EVENT_N * SLOT_N)
		return 0
	return _cond_actual[i]


## 该触发条件槽位本季是否真的被读过（all_of 短路会让后面的槽位没被读）。
## 步骤：S08 之后
## 前置：e、slot 在范围内
## 后置：不改状态
## 不变量：无
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回 false
func condition_was_read(e: int, slot: int) -> bool:
	var i: int = e * SLOT_N + slot
	if e < 0 or e >= JWUnits.EVENT_N or slot < 0 or slot >= SLOT_N \
			or _cond_read.size() != JWUnits.EVENT_N * SLOT_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, JWUnits.EVENT_N * SLOT_N)
		return false
	return _cond_read[i] == 1


## 某条证据引用本季的实际取值（`evidence_was_read == false` 时无意义）。
## 步骤：S08 之后
## 前置：e、slot 在范围内
## 后置：不改状态
## 不变量：计划书 §13「每条变化附带实体 ID」
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回 0
func evidence_actual(e: int, slot: int) -> int:
	var i: int = e * SLOT_N + slot
	if e < 0 or e >= JWUnits.EVENT_N or slot < 0 or slot >= SLOT_N \
			or _evidence_value.size() != JWUnits.EVENT_N * SLOT_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, JWUnits.EVENT_N * SLOT_N)
		return 0
	return _evidence_value[i]


## 该证据槽位的取值本季是否可得。
## 步骤：S08 之后
## 前置：e、slot 在范围内
## 后置：不改状态
## 不变量：无
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回 false
func evidence_was_read(e: int, slot: int) -> bool:
	var i: int = e * SLOT_N + slot
	if e < 0 or e >= JWUnits.EVENT_N or slot < 0 or slot >= SLOT_N \
			or _evidence_known.size() != JWUnits.EVENT_N * SLOT_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, JWUnits.EVENT_N * SLOT_N)
		return false
	return _evidence_known[i] == 1


## 加载期校验。
## 步骤：LOAD
## 前置：12 个 JSON 已解析
## 后置：不改状态
## 不变量：INV-130
## 失败：Load.EVENT_COUNT / METRIC_UNKNOWN / EVENT_OP / EVENT_STREAM / EVENT_TARGET /
##       EVENT_LEDGER（**首版不存在 ledger_effects 字段，出现即失败**）/ EVENT_FIELD / EVENT_EVIDENCE
##
## 校验的是**加载后的稠密数组**，不是 JSON 文本：V-EV-01…08 中凡是能在数组上表达的
## 全部在这里逐条判死。`rng_stream[]` 与 `ledger_effect_count[]` 就是为了让
## V-EV-04 / V-EV-06 不至于退化成空检查而存在的两条「JSON 形状的留痕」。
func validate() -> JWResult:
	# ── 常量自检：三处白名单码必须是同一套（见 TARGET_* 的说明） ──
	if TARGET_EXPECTATION_PPM != JWPolitics.EVT_EXPECTATION_PPM \
			or TARGET_TRUST_PPM != JWPolitics.EVT_TRUST_PPM \
			or TARGET_SUPPORT_PPM != JWPolitics.EVT_SUPPORT_PPM \
			or TARGET_ADMIN_CAPACITY_PPM != JWPolitics.EVT_ADMIN_CAPACITY_PPM \
			or TARGET_ORG_POWER_PPM != JWInterestGroups.EVT_ORG_POWER_PPM \
			or TARGET_STANCE_PPM != JWInterestGroups.EVT_STANCE_PPM:
		return JWResult.make_err(JWResult.Load.EVENT_TARGET, TARGET_N, 0)

	# ── V-EV-01：12 张卡齐全，且全部数组是契约长度 ──
	var n: int = JWUnits.EVENT_N
	var wide: int = n * SLOT_N
	if fire_count.size() != n or last_fire_q.size() != n:
		return JWResult.make_err(JWResult.Load.EVENT_COUNT, n, fire_count.size())
	if probability_ppm.size() != n or cooldown_q.size() != n or max_occurrences.size() != n:
		return JWResult.make_err(JWResult.Load.EVENT_COUNT, n, probability_ppm.size())
	if rng_stream.size() != n or ledger_effect_count.size() != n:
		return JWResult.make_err(JWResult.Load.EVENT_COUNT, n, rng_stream.size())
	if trigger_metric.size() != wide or trigger_scope.size() != wide \
			or trigger_op.size() != wide or trigger_value.size() != wide:
		return JWResult.make_err(JWResult.Load.EVENT_COUNT, wide, trigger_metric.size())
	if effect_target.size() != wide or effect_scope.size() != wide \
			or effect_delta_ppm.size() != wide or evidence_ref.size() != wide:
		return JWResult.make_err(JWResult.Load.EVENT_COUNT, wide, effect_target.size())

	var e: int = 0
	while e < n:
		var base: int = e * SLOT_N

		# ── V-EV-06：首版不存在 ledger_effects ──
		if ledger_effect_count[e] != 0:
			return JWResult.make_err(JWResult.Load.EVENT_LEDGER, e, ledger_effect_count[e])

		# ── V-EV-04：只能用 rng.event，不得借用 rng.shock ──
		if rng_stream[e] != JWUnits.RngStream.EVENT:
			return JWResult.make_err(JWResult.Load.EVENT_STREAM, e, rng_stream[e])

		# ── V-EV-07：三个数值字段的区间 ──
		if probability_ppm[e] < 0 or probability_ppm[e] > JWUnits.PPM:
			return JWResult.make_err(JWResult.Load.EVENT_FIELD, e, probability_ppm[e])
		if cooldown_q[e] < 0:
			return JWResult.make_err(JWResult.Load.EVENT_FIELD, e, cooldown_q[e])
		if max_occurrences[e] < 1:
			return JWResult.make_err(JWResult.Load.EVENT_FIELD, e, max_occurrences[e])

		# ── 触发条件逐槽 ──
		var cond_n: int = 0
		var slot: int = 0
		while slot < SLOT_N:
			var i: int = base + slot
			var metric: int = trigger_metric[i]
			if metric == METRIC_NONE:
				slot += 1
				continue
			# V-EV-02：稳定 ID 必须在加载期解析成了真实的 metric 码
			if metric < 0:
				return JWResult.make_err(JWResult.Load.METRIC_UNKNOWN, e, metric)
			# V-EV-03：op 闭集合
			if trigger_op[i] < 0 or trigger_op[i] >= OP_N:
				return JWResult.make_err(JWResult.Load.EVENT_OP, e, trigger_op[i])
			var sc: int = trigger_scope[i]
			if sc != SCOPE_NONE and (sc < 0 or scope_kind_of(sc) >= SCOPE_KIND_N):
				return JWResult.make_err(JWResult.Load.METRIC_UNKNOWN, e, sc)
			cond_n += 1
			slot += 1
		# 没有任何条件的事件卡就是随机弹窗，与「事件由可机器求值的状态条件触发」直接冲突。
		if cond_n == 0:
			return JWResult.make_err(JWResult.Load.EVENT_COUNT, e, 0)

		# ── 效应逐槽（V-EV-05 + INV-130） ──
		var eff_n: int = 0
		slot = 0
		while slot < SLOT_N:
			var j: int = base + slot
			var target: int = effect_target[j]
			if target == TARGET_NONE:
				slot += 1
				continue
			if target < 0 or target >= TARGET_N:
				return JWResult.make_err(JWResult.Load.EVENT_TARGET, e, target)
			var code: int = effect_scope[j]
			if not _scope_fits_target(target, code):
				return JWResult.make_err(JWResult.Load.EVENT_TARGET, e, code)
			var d: int = effect_delta_ppm[j]
			if d < -DELTA_PPM_MAX or d > DELTA_PPM_MAX:
				return JWResult.make_err(JWResult.Load.EVENT_FIELD, e, d)
			eff_n += 1
			slot += 1
		if eff_n == 0:
			# 没有任何效应的事件卡在首版没有别的表达通道（没有账本效应），等于什么都不做。
			return JWResult.make_err(JWResult.Load.EVENT_TARGET, e, TARGET_NONE)

		# ── V-EV-08：evidence_refs 非空 ──
		var ev_n: int = 0
		slot = 0
		while slot < SLOT_N:
			if evidence_ref[base + slot] != EVIDENCE_NONE:
				if evidence_ref[base + slot] < 0:
					return JWResult.make_err(JWResult.Load.METRIC_UNKNOWN, e,
							evidence_ref[base + slot])
				ev_n += 1
			slot += 1
		if ev_n == 0:
			return JWResult.make_err(JWResult.Load.EVENT_EVIDENCE, e, 0)

		e += 1

	return JWResult.make_ok()


## 效应落点与 scope 的配型（白名单六项各自只接受一种范围口径）。
## 步骤：LOAD
## 前置：target ∈ [0, TARGET_N)
## 后置：不改状态
## 不变量：INV-130
## 失败：无（返回 false 由调用方转 Load.EVENT_TARGET）
func _scope_fits_target(target: int, code: int) -> bool:
	var kind: int = scope_kind_of(code)
	var idx: int = scope_index_of(code)
	if target == TARGET_EXPECTATION_PPM or target == TARGET_TRUST_PPM \
			or target == TARGET_SUPPORT_PPM:
		if code == SCOPE_NONE:
			return true
		if kind == SCOPE_KIND_REGION:
			return idx >= 0 and idx < JWUnits.R
		if kind == SCOPE_KIND_GROUP:
			return idx >= 0 and idx < JWUnits.GROUP
		return false
	if target == TARGET_ORG_POWER_PPM:
		return kind == SCOPE_KIND_BLOC and idx >= 0 and idx < JWUnits.BLOC_N
	if target == TARGET_STANCE_PPM:
		return kind == SCOPE_KIND_STANCE and idx >= 0 and idx < JWUnits.STANCE_N
	if target == TARGET_ADMIN_CAPACITY_PPM:
		return code == SCOPE_NONE
	return false


# ── §1.6 状态块协议 ──────────────────────────────────────────────────────

## LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：维度常量已确定
## 后置：状态数组长 EVENT_N，内容数组长 EVENT_N × SLOT_N；此后不再 resize
## 不变量：docs/10 §0.6（加载期一次性 resize）
## 失败：无
func allocate() -> void:
	var n: int = JWUnits.EVENT_N
	var wide: int = n * SLOT_N

	fire_count.resize(n)
	fire_count.fill(0)
	last_fire_q.resize(n)
	last_fire_q.fill(NEVER_FIRED_Q)

	probability_ppm.resize(n)
	probability_ppm.fill(0)
	cooldown_q.resize(n)
	cooldown_q.fill(0)
	max_occurrences.resize(n)
	max_occurrences.fill(0)
	rng_stream.resize(n)
	rng_stream.fill(JWUnits.RngStream.EVENT)
	ledger_effect_count.resize(n)
	ledger_effect_count.fill(0)

	# 内容槽位的空值是哨兵而不是 0：0 是一个合法的 metric 码 / 落点码，
	# 拿 0 当「空」会让没被加载器填满的尾部槽位看起来像一堆指向 0 号字段的真条件。
	trigger_metric.resize(wide)
	trigger_metric.fill(METRIC_NONE)
	trigger_scope.resize(wide)
	trigger_scope.fill(SCOPE_NONE)
	trigger_op.resize(wide)
	trigger_op.fill(OP_EQ)
	trigger_value.resize(wide)
	trigger_value.fill(0)
	effect_target.resize(wide)
	effect_target.fill(TARGET_NONE)
	effect_scope.resize(wide)
	effect_scope.fill(SCOPE_NONE)
	effect_delta_ppm.resize(wide)
	effect_delta_ppm.fill(0)
	evidence_ref.resize(wide)
	evidence_ref.fill(EVIDENCE_NONE)

	_fired.resize(n)
	_fired.fill(0)
	_cond_actual.resize(wide)
	_cond_actual.fill(0)
	_cond_read.resize(wide)
	_cond_read.fill(0)
	_evidence_value.resize(wide)
	_evidence_value.fill(0)
	_evidence_known.resize(wide)
	_evidence_known.fill(0)
	_fired_count = 0
	_eval_metric_unknown = false


## 只读取用（返回引用，调用方不得写）。
## 步骤：哈希 / 存档
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136（下标顺序是 schema 的一部分）
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return fire_count
	if i == 1:
		return last_fire_q
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## 仅 LOAD / MIG（静态检查：调用点必须在 systems/content_loader.gd 或 systems/saves.gd）。
## 步骤：LOAD / MIG
## 前置：v.size() == EVENT_N
## 后置：state_array(i) == v
## 不变量：INV-136
## 失败：越界或长度不符 → Fault.INDEX_OUT_OF_RANGE
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i < 0 or i >= STATE_ARRAY_IDS.size():
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i,
				STATE_ARRAY_IDS.size())
	if v.size() != JWUnits.EVENT_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, v.size(),
				JWUnits.EVENT_N)
	# duplicate()：Godot 4 的 Packed*Array 传参是引用语义，直接赋值会让本块的权威状态
	# 与调用方的临时数组共用同一块内存，此后调用方改一位就等于偷改了存档。
	if i == 0:
		fire_count = v.duplicate()
	else:
		last_fire_q = v.duplicate()
	return JWResult.OK


## 标量读取。
## 步骤：哈希 / 存档
## 前置：i ∈ [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → raise_fault(INDEX_OUT_OF_RANGE) 返回 0
func state_scalar(i: int) -> int:
	# 本块没有进哈希的标量（docs/17 §4.30 的成员表只有两条 S 类数组）：
	# 任何下标都是越界，保留签名只为满足 §1.6 的统一遍历协议。
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## 仅 LOAD / MIG。
## 步骤：LOAD / MIG
## 前置：i 合法
## 后置：state_scalar(i) == v
## 不变量：INV-136
## 失败：越界 → Fault.INDEX_OUT_OF_RANGE
func set_state_scalar(i: int, v: int) -> int:
	# 同 state_scalar：本块无标量条目，写入一律越界，不悄悄吞掉。
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v)


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
## 失败：无
func reset_flows() -> void:
	# 本块没有 flow.* 条目（fire_count / last_fire_q 都是跨季的 S 类），故为空操作。
	# 本季诊断缓冲**不在这里**清：它要活到 S08 之后给报告读，清零点在 fire_events 入口。
	pass


## S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 已执行
## 后置：不改状态
## 不变量：INV-013
## 失败：调用方按非 0 返回 Fault.FLOW_NOT_RESET
func flow_abs_sum() -> int:
	return 0
