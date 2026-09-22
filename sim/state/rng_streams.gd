## 计数器式确定性抽样（docs/12 §0.4）。
##
## 6 条流结构性独立：任一流多抽一次，其它流的取值完全不变（INV-009）。持有 log.rng。
## root_seed + 6 个 draw_count 就是完整的随机流状态（docs/11 §6.3），存档不存内部状态。
## salt 一经发布不得更改（否则全部存档重放失效，INV-136）。
## 依赖秩 2：只允许引用 JWUnits / JWResult / JWMath / JWIds。
class_name JWRngStreams
extends RefCounted

# ── 状态块协议的注册表（docs/17 §1.6；顺序是 schema 的一部分，重排即破坏性变更 INV-136） ──

## 本块各数组所属子系统（与 STATE_ARRAY_IDS 等长），用于 subsystem_hash 与 WriteGuard。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [JWUnits.SUBSYS_RNG]

## 本块各标量所属子系统（与 STATE_SCALAR_IDS 等长）。
const STATE_SCALAR_SUBSYS: PackedInt64Array = [JWUnits.SUBSYS_RNG]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
const STATE_ARRAY_IDS: PackedStringArray = ["state.rng.draw_count"]
const STATE_SCALAR_IDS: PackedStringArray = ["state.rng.root_seed"]
## 随机流没有流量。
const FLOW_ARRAY_SUBSYS: PackedInt64Array = []
const FLOW_SCALAR_SUBSYS: PackedInt64Array = []
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = []

# ── splitmix64 常量（docs/12 §0.4） ────────────────────────────────────────
#
# GDScript 的 int 是有符号 int64，而 splitmix64 的三个常量都 > INT64_MAX，
# 写成无符号十六进制字面量会落在 int64 之外。这里写它们的**有符号等值**
# （x_signed == x_unsigned − 2^64），位型完全相同，注释给出原始无符号值。

## 0x9E3779B97F4A7C15（黄金分割增量）
const GOLDEN_GAMMA: int = -0x61C8864680B583EB
## 0xBF58476D1CE4E5B9（第一轮乘数）
const MIX_A: int = -0x40A7B892E31B1A47
## 0x94D049BB133111EB（第二轮乘数）
const MIX_B: int = -0x6B2FB644ECCEEE15

## 逻辑右移 30 位后的有效位掩码（(1 << 34) − 1）。
## GDScript 的 `>>` 对负数是**算术**右移，会把符号位铺满高位；
## 与掩码相与之后才等价于 C 的 `uint64_t >> 30`。
const MASK_SHR30: int = (1 << 34) - 1
## 逻辑右移 27 位后的有效位掩码（(1 << 37) − 1）
const MASK_SHR27: int = (1 << 37) - 1
## 逻辑右移 31 位后的有效位掩码（(1 << 33) − 1）
const MASK_SHR31: int = (1 << 33) - 1

# ── 抽样常量 ───────────────────────────────────────────────────────────────

## 原始抽样取低 62 位后参与拒绝采样。
## 取 62 而不是 64：GDScript 没有无符号整数，留两位保证 raw ∈ [0, 2^62) 恒为非负，
## 于是 `r < limit` 与 `r mod n` 都不必再讨论符号。62 位的取模偏差本就要被拒绝采样消掉。
const DRAW_BITS: int = 62
## (1 << 62) − 1
const DRAW_MASK: int = (1 << DRAW_BITS) - 1
## 拒绝采样的样本空间大小 2^62
const DRAW_SPACE: int = 1 << DRAW_BITS

## 被拒那次抽样在 log.rng.mapped 里的取值。
## 不能写 0：0 是一个合法的映射值，写 0 会让「这次被拒了」和「这次抽到 0」无法区分。
const MAPPED_REJECTED: int = -1

## 种子拼接的合法定义域：`(q << 32) ^ index` 只有在 q 与 index 各自落在自己的位域内
## 才是**单射**的（docs/12 §0.4 的拼接式；docs/31 `ADV-J01` 失败诊断明写「缺上界校验 ⇒
## 与季度号发生位重叠」——补的是上界校验，不是换一个拼接式）。
## q 占高 31 位：`q << 32` 必须不冲掉符号位，否则两个不同的 q 得到同一个种子。
const Q_MAX_EXCL: int = 1 << 31
## index 占低 32 位：index ≥ 2^32 会爬进 q 的位域，于是 (q=1,index=0) 与 (q=0,index=2^32)
## 撞成同一个种子，同一条流在不同季复现同一序列。合法域内两者不可能相等。
## 2^32 次抽样在单条流上不可能出现（120 季 × 每季数千次抽样 ≪ 4.3e9），
## 真到了就是工程缺陷，必须报 FAULT 而不是悄悄拼出一个重叠的种子。
const INDEX_MAX_EXCL: int = 1 << 32

## 拒绝采样的重抽次数上限。
## 期望重抽次数 < 1e-12 次/抽样（docs/12 §0.4），跑满 1024 次只可能是
## limit 算错或 draw_raw 退化成常量，属于工程缺陷，宁可报 FAULT 也不能挂死结算线程。
const MAX_REJECT_TRIES: int = 1024

## 日志扩容倍率的分子与分母（docs/10 §12 的「1.5 倍」）
const LOG_GROWTH_NUM: int = 3
const LOG_GROWTH_DEN: int = 2

# ── 盐值（content.rng.salt[6] 的 schema 常量） ──────────────────────────────

## 六条流的盐值，按 JWUnits.RngStream 的枚举顺序排列
## （0 SHOCK / 1 EVENT / 2 DEMOGRAPHY / 3 MARKET / 4 POLITICS / 5 RESERVED）。
##
## **为什么写死在这里而不是等 LOAD 填**：salt 是 class C 不假，但它「属 schema，
## 发布后不得更改」（docs/11 §5.15.2、docs/17 §4.5、INV-136）——它是一张常量表，
## 不是可调参数。allocate() 从前填 0，于是任何没走完整内容包加载的路径（单元测试夹具、
## 工具、迁移期的半截状态）都会拿到一张全 0 的盐表：六条流退化成同一条，而且悄无声息。
## draw_raw() 只就 salt 的**长度**设防，长度是对的，值全相同它看不出来。
## 把已发布的常量作为初值写在这里，等于让「未加载」与「已加载」在盐值上完全一致，
## 退化路径从此不存在。
##
## **两处事实来源的处理**：内容包 `content/parameters/params_core.json` 的
## `param.rng_salt` 卡仍是发布口径的登记处，systems/content_loader.gd 的 `_read_rng_salt()`
## 逐位比对卡值与本常量，不一致即 `Load.UNIT_MISMATCH` 拒绝启动——与该加载器对
## `amount_max_uu` / `qty_max_uqs` 的处置同形（「故意冗余，防止参数包与代码各说各的」）。
## 所以这不是第二份可以各说各话的数据，而是一份被机器对账的冗余登记。
##
## 取值可逐位复算（卡上的 derivation_expr，已按此式复核过）：
##   salt[i] = int.from_bytes(sha256(utf8(rng_id[i])).digest()[0:8], 'big') & 0x1FFFFFFFFFFFFF
##   rng_id  = ["rng.shock", "rng.event", "rng.demography", "rng.market",
##              "rng.politics", "rng.reserved"]
## 掩码取 53 位而不是 63 位：docs/11 §1.2 规定内容包里一切整数的绝对值 ≤ 2^53
## （JSON 互操作安全区），而混合强度由 splitmix64 提供、不由盐值位宽提供，
## 截到 53 位不削弱流隔离。六个值两两不等、均 > 0、均 ≤ 2^53。
const DEFAULT_SALT: PackedInt64Array = [
	8566354709439740,   # rng.shock
	1697037501250966,   # rng.event
	774310021412516,    # rng.demography
	3441291724144371,   # rng.market
	8107072018497657,   # rng.politics
	1103520599060817,   # rng.reserved
]

# ── 成员变量（docs/17 §4.5） ───────────────────────────────────────────────

## state.rng.root_seed —— uint64 位型。写入者：LOAD
var root_seed: int = 0
## state.rng.draw_count[] —— 长 RNG_STREAM_N，计数。写入者：S01,S03,S07,S08
var draw_count: PackedInt64Array = PackedInt64Array()
## content.rng.salt[] —— 长 RNG_STREAM_N，内容包常量。写入者：LOAD
var salt: PackedInt64Array = PackedInt64Array()

## log.rng.stream[] —— 长 LOG_CAP0。写入者：S01,S03,S07,S08
var log_stream: PackedInt64Array = PackedInt64Array()
## log.rng.draw_index[]
var log_draw_index: PackedInt64Array = PackedInt64Array()
## log.rng.purpose[]
var log_purpose: PackedInt64Array = PackedInt64Array()
## log.rng.raw_u64[]
var log_raw: PackedInt64Array = PackedInt64Array()
## log.rng.mapped[]
var log_mapped: PackedInt64Array = PackedInt64Array()
## 本季日志游标
var _log_cursor: int = 0
## 当季索引，由 begin_quarter() 写入。写入者：S01
var _q: int = 0

## 本季季初各流的 draw_count 快照，长 RNG_STREAM_N。
## 不是状态：它由 begin_quarter() 每季重建，不进 state_hash 也不进存档
## （存档只需 root_seed + 6 个 draw_count，docs/11 §6.3）。
var _draw_base: PackedInt64Array = PackedInt64Array()

## 日志扩容发生的次数（docs/10 §12 的「写一条告警行」在本通道的等价物）。
##
## log.rng 不能靠「写一条告警行」来告警：INV-011 要求本季 log.rng 行数精确等于
## Σ Δdraw_count，多插一行告警就会让这条不变量误报。改为计数器登记，
## 由 JWDiagnostics 在季末读取。
var _log_grow_count: int = 0

# ── 抽样 ───────────────────────────────────────────────────────────────────

## splitmix64。纯 int64 环绕算术；右移必须逻辑右移（(x >> n) & mask），
## 因为 GDScript 的 >> 对负数是算术右移。必须有已知测试向量的单元测试。
## 步骤：全部抽样的底座
## 前置：无
## 后置：同一 x 恒返回同一值；与引擎 RNG 无关
## 不变量：INV-010（抽样可复算）
## 失败：无（纯函数）
##
## 测试向量（tests/replay/rng_streams_test.gd，与 xoshiro 播种参考实现一致）：
##   splitmix64(0)                      == 0xE220A8397B1DCDAF
##   splitmix64(GOLDEN_GAMMA)           == 0x6E789E6AA1B965F4
##   splitmix64(GOLDEN_GAMMA * 2)       == 0x06C45D188009454F
## 这里的加法与乘法都必须环绕（不走 JWMath.mul）：JWMath.mul 会把环绕判成
## INT_OVERFLOW 并登记故障，而位混合函数的语义恰恰就是环绕算术。
static func splitmix64(x: int) -> int:
	var z: int = x + GOLDEN_GAMMA
	z = (z ^ ((z >> 30) & MASK_SHR30)) * MIX_A
	z = (z ^ ((z >> 27) & MASK_SHR27)) * MIX_B
	return z ^ ((z >> 31) & MASK_SHR31)


## 原始抽样：f(root_seed, salt[stream], q, index)。不推进计数器、不写日志。
## 步骤：全部；也是重放二分定位时「从任意季重算任意一次抽样」的入口
## 前置：stream ∈ [0,5]；q ∈ [0, 2^31)；index ∈ [0, 2^32)
## 后置：无副作用
## 不变量：INV-009（流隔离）、INV-010
## 失败：stream / q / index 越界 → INDEX_OUT_OF_RANGE 返回 0
##
## 流隔离就落在这一行上：stream 只经 salt[stream] 进入混合，index 只来自本流自己的
## draw_count[stream]，两者与别的流没有任何数据通路 —— 所以别的流多抽一万次，
## 本流的第 k 次取值一个比特都不会变（INV-009）。
func draw_raw(stream: int, q: int, index: int) -> int:
	if stream < 0 or stream >= JWUnits.RNG_STREAM_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, stream, JWUnits.RNG_STREAM_N)
		return 0
	if salt.size() != JWUnits.RNG_STREAM_N:
		# allocate() 没跑过。宁可报越界也不能拿一张空盐表去抽样：
		# 那会让全部 6 条流退化成同一条（salt 全 0），而且悄无声息。
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, salt.size(), JWUnits.RNG_STREAM_N)
		return 0
	if q < 0 or q >= Q_MAX_EXCL:
		# q << 32 要求 q 落在 31 位内，否则会冲掉符号位，让两个不同的 q 得到同一个种子。
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, q, Q_MAX_EXCL)
		return 0
	if index < 0 or index >= INDEX_MAX_EXCL:
		# index 必须留在低 32 位内，否则它会爬进 q 的位域：(q=1, index=0) 与
		# (q=0, index=2^32) 会拼出同一个种子，同一条流在不同季复现同一序列。
		# docs/31 ADV-J01 的失败诊断把这一类重叠归因于「缺 INV-007 的上界校验」，
		# 补的就是这一条——拼接式本身由 docs/12 §0.4 钉死，不得改。
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, index, INDEX_MAX_EXCL)
		return 0
	return splitmix64(root_seed ^ salt[stream] ^ (q << 32) ^ index)


## 无偏的 [0, n) 均匀整数：拒绝采样消除取模偏差。
## 步骤：S01 冲击、S03/S05 市场、S07 人口、S08 事件与政治
## 前置：n > 0；stream ∈ [0,5]
## 后置：draw_count[stream] 推进（含被拒的那次）；每次抽样写一条 log.rng（含被拒的那次）
## 不变量：INV-009, INV-010, INV-011（log.rng 条数 == Σ Δdraw_count）
## 失败：n <= 0 → DIV_ZERO 返回 0
##
## limit == floor(2^62 / n) * n 是 2^62 内 n 的最大整倍数。落在 [limit, 2^62) 的原始值
## 被丢弃 —— 正是这一小段尾巴造成取模偏差。被丢弃的那次**同样推进计数器、同样写日志**，
## 否则重放时计数器对不上（docs/12 §0.4 明文要求）。
func draw_below(stream: int, n: int, purpose: int) -> int:
	if stream < 0 or stream >= JWUnits.RNG_STREAM_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, stream, JWUnits.RNG_STREAM_N)
		return 0
	if draw_count.size() != JWUnits.RNG_STREAM_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				draw_count.size(), JWUnits.RNG_STREAM_N)
		return 0
	if n <= 0:
		JWResult.raise_fault(JWResult.Fault.DIV_ZERO, n, 0)
		return 0
	if n > DRAW_SPACE:
		# n 超过样本空间时 limit 会算成 0，循环里每一次都被拒。
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, n, DRAW_SPACE)
		return 0
	# rounding: floor, reason=拒绝阈取 n 在 2^62 内的最大整倍数，多一个都会带回取模偏差
	var limit: int = JWMath.mul(JWMath.floor_div(DRAW_SPACE, n), n)
	var tries: int = 0
	while tries < MAX_REJECT_TRIES:
		tries += 1
		var index: int = draw_count[stream]
		var r: int = draw_raw(stream, _q, index) & DRAW_MASK
		draw_count[stream] = index + 1
		if r < limit:
			# rounding: floor, reason=r mod n；JWMath 不提供裸 %，用 r − floor(r/n)·n 等价展开
			var mapped: int = r - JWMath.mul(JWMath.floor_div(r, n), n)
			_log_write(stream, index, purpose, r, mapped)
			return mapped
		_log_write(stream, index, purpose, r, MAPPED_REJECTED)
	JWResult.raise_fault(JWResult.Fault.RNG_LOG_MISMATCH, stream, n)
	return 0


## [0, 1_000_000) 的 ppm 抽样。
## 步骤：同 draw_below
## 前置：stream ∈ [0,5]
## 后置：同 draw_below
## 不变量：INV-009, INV-010, INV-011
## 失败：同 draw_below
func draw_ppm(stream: int, purpose: int) -> int:
	return draw_below(stream, JWUnits.PPM, purpose)


## [lo, hi] 闭区间抽样。
## 步骤：同 draw_below
## 前置：lo <= hi；stream ∈ [0,5]
## 后置：同 draw_below
## 不变量：INV-009, INV-010, INV-011
## 失败：lo > hi → INDEX_OUT_OF_RANGE 返回 lo
func draw_range(stream: int, lo: int, hi: int, purpose: int) -> int:
	if lo > hi:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, lo, hi)
		return lo
	if lo < 0 and hi > JWUnits.INT64_MAX + lo:
		# hi − lo 会溢出。不做饱和截断：区间本身就不合法，交给调用方走失败路径。
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, lo, hi)
		return lo
	var span: int = hi - lo
	if span == JWUnits.INT64_MAX:
		JWResult.raise_fault(JWResult.Fault.INT_OVERFLOW, lo, hi)
		return lo
	return lo + draw_below(stream, span + 1, purpose)


## 设定本季 q（抽样公式里的 q 项）。只由 S01 调用一次。
## 步骤：S01
## 前置：q >= 0
## 后置：_q == q；日志游标重置
## 不变量：INV-011
## 失败：无
func begin_quarter(q: int) -> void:
	_q = q
	if _draw_base.size() != JWUnits.RNG_STREAM_N:
		_draw_base.resize(JWUnits.RNG_STREAM_N)
	if draw_count.size() == JWUnits.RNG_STREAM_N:
		for s: int in JWUnits.RNG_STREAM_N:
			_draw_base[s] = draw_count[s]
	log_reset_quarter()


## 本季各流的抽样增量之和（供 INV-011 对账）。
## 步骤：每季末
## 前置：无
## 后置：不改状态
## 不变量：INV-011
## 失败：无
func draws_this_quarter() -> int:
	if draw_count.size() != JWUnits.RNG_STREAM_N or _draw_base.size() != JWUnits.RNG_STREAM_N:
		return 0
	var acc: int = 0
	for s: int in JWUnits.RNG_STREAM_N:
		acc += draw_count[s] - _draw_base[s]
	return acc


## 某条流的累计抽样次数。
## 步骤：每季末 / 存档
## 前置：stream ∈ [0,5]
## 后置：不改状态
## 不变量：INV-011
## 失败：stream 越界 → INDEX_OUT_OF_RANGE 返回 0
func draw_count_of(stream: int) -> int:
	if stream < 0 or stream >= JWUnits.RNG_STREAM_N or draw_count.size() != JWUnits.RNG_STREAM_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, stream, JWUnits.RNG_STREAM_N)
		return 0
	return draw_count[stream]


## 本季某条流的抽样增量。
## 步骤：每季末
## 前置：stream ∈ [0,5]
## 后置：不改状态
## 不变量：INV-011
## 失败：stream 越界 → INDEX_OUT_OF_RANGE 返回 0
func draws_this_quarter_of(stream: int) -> int:
	if stream < 0 or stream >= JWUnits.RNG_STREAM_N \
			or draw_count.size() != JWUnits.RNG_STREAM_N \
			or _draw_base.size() != JWUnits.RNG_STREAM_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, stream, JWUnits.RNG_STREAM_N)
		return 0
	return draw_count[stream] - _draw_base[stream]

# ── 状态块协议（docs/17 §1.6） ─────────────────────────────────────────────

## LOAD 期一次性 resize 到 docs/17 §2 的契约长度。
## 步骤：LOAD
## 前置：维度常量已确定
## 后置：draw_count 长 RNG_STREAM_N；五张 log 数组长 LOG_CAP0；此后长度不再变
## 不变量：docs/10 §0.6（加载期一次性 resize）
## 失败：无
func allocate() -> void:
	draw_count.resize(JWUnits.RNG_STREAM_N)
	draw_count.fill(0)
	# 盐值填 schema 常量而不是 0：全 0 会让六条流退化成同一条且悄无声息（INV-009）。
	# LOAD 随后写入的内容包卡值与本常量逐位相同（content_loader._read_rng_salt 强制对账），
	# 所以「加载前」与「加载后」的抽样序列完全一致，不存在两套随机流。
	salt = DEFAULT_SALT.duplicate()
	_draw_base.resize(JWUnits.RNG_STREAM_N)
	_draw_base.fill(0)
	log_stream.resize(JWUnits.LOG_CAP0)
	log_draw_index.resize(JWUnits.LOG_CAP0)
	log_purpose.resize(JWUnits.LOG_CAP0)
	log_raw.resize(JWUnits.LOG_CAP0)
	log_mapped.resize(JWUnits.LOG_CAP0)
	_log_cursor = 0
	_log_grow_count = 0


## 只读取用（返回引用，调用方不得写）。
## 步骤：哈希 / 存档 / 报告
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136（下标顺序是 schema 的一部分）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return draw_count
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## 仅 LOAD / MIG（静态检查：调用点必须在 systems/content_loader.gd 或 systems/saves.gd）。
## 步骤：LOAD / MIG
## 前置：i 合法；v 的长度等于契约长度
## 后置：对应数组被整体替换
## 不变量：INV-136
## 失败：越界或长度不符 → INDEX_OUT_OF_RANGE
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i != 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	if v.size() != JWUnits.RNG_STREAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				v.size(), JWUnits.RNG_STREAM_N)
	# duplicate()：Godot 4 的 Packed*Array 传参是引用语义，直接赋值会让本块的状态
	# 与调用方的临时数组共用同一块内存，此后调用方改一位就等于偷改了权威状态。
	draw_count = v.duplicate()
	return JWResult.OK


## 标量只读取用。
## 步骤：哈希 / 存档 / 报告
## 前置：i ∈ [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func state_scalar(i: int) -> int:
	if i == 0:
		return root_seed
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## 仅 LOAD / MIG。
## 步骤：LOAD / MIG
## 前置：i 合法
## 后置：对应标量被写
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE
func set_state_scalar(i: int, v: int) -> int:
	if i != 0:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	root_seed = v
	return JWResult.OK


## 流量数组只读取用。随机流没有流量，FLOW_ARRAY_IDS 为空。
## 步骤：S01 清零自检
## 前置：i ∈ [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func flow_array(i: int) -> PackedInt64Array:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## 流量标量只读取用。随机流没有流量，FLOW_SCALAR_IDS 为空。
## 步骤：S01 清零自检
## 前置：i ∈ [0, FLOW_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## 仅 S01；全部 FLOW_* 归零。本块无流量，故为空操作。
## 步骤：S01 §01.3
## 前置：phase == S01
## 后置：flow_abs_sum() == 0
## 不变量：INV-013
## 失败：无
func reset_flows() -> void:
	pass


## S01 清零后的自检，非 0 即 FLOW_NOT_RESET。
## 步骤：S01 §01.3
## 前置：reset_flows() 已跑过
## 后置：不改状态
## 不变量：INV-013
## 失败：无（调用方按返回值判 Fault.FLOW_NOT_RESET）
func flow_abs_sum() -> int:
	return 0

# ── 日志通道协议（docs/17 §1.7；日志只有整数，不进 state_hash） ─────────────

## 每季 S01 重置本季游标。
## 步骤：S01
## 前置：无
## 后置：_log_cursor == 0
## 不变量：INV-011
## 失败：无
func log_reset_quarter() -> void:
	_log_cursor = 0


## 本季已写行数，供 INV-011 / INV-139 对账。
## 步骤：每季末
## 前置：无
## 后置：不改状态
## 不变量：INV-011（log.rng 条数 == Σ Δdraw_count）、INV-139
## 失败：无
func log_row_count() -> int:
	return _log_cursor


## 当前容量；写满时按 1.5 倍扩容并写一条告警行。
## 步骤：写日志时
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func log_capacity() -> int:
	return log_stream.size()


## 本局日志扩容发生的次数（本通道以计数器代替告警行，理由见 _log_grow_count 的说明）。
## 步骤：每季末 / 诊断
## 前置：无
## 后置：不改状态
## 不变量：INV-139
## 失败：无
func log_grow_count() -> int:
	return _log_grow_count


## 写一行 log.rng。每次抽样恰好一行，含被拒的那次（INV-011）。
## 步骤：S01, S03, S07, S08
## 前置：无
## 后置：_log_cursor += 1；必要时先扩容
## 不变量：INV-011（行数 == Σ Δdraw_count）、INV-139
## 失败：无（扩容失败不可能发生；容量不足时先扩容再写）
func _log_write(stream: int, index: int, purpose: int, raw: int, mapped: int) -> void:
	if _log_cursor >= log_stream.size():
		_log_grow()
	log_stream[_log_cursor] = stream
	log_draw_index[_log_cursor] = index
	log_purpose[_log_cursor] = purpose
	log_raw[_log_cursor] = raw
	log_mapped[_log_cursor] = mapped
	_log_cursor += 1


## 五张 log 数组按 1.5 倍同步扩容（docs/10 §12）。
## 步骤：写日志时容量耗尽
## 前置：无
## 后置：五张数组等长且 > 原长
## 不变量：INV-139
## 失败：无
func _log_grow() -> void:
	var cap: int = log_stream.size()
	var next_cap: int = JWUnits.LOG_CAP0
	if cap > 0:
		# rounding: ceil, reason=1.5 倍扩容宁可多要一行也不能因取整停在原容量上
		next_cap = JWMath.ceil_div(JWMath.mul(cap, LOG_GROWTH_NUM), LOG_GROWTH_DEN)
	if next_cap <= cap:
		next_cap = cap + 1
	log_stream.resize(next_cap)
	log_draw_index.resize(next_cap)
	log_purpose.resize(next_cap)
	log_raw.resize(next_cap)
	log_mapped.resize(next_cap)
	_log_grow_count += 1
