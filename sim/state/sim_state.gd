## 权威状态根。
##
## 持有全部域类实例、state.meta.* 与 state.time.*、参数数组，并实现规范化编码、
## state_hash / subsystem_hash、流量整表清零、to_dict / from_dict。
## 它是 sim/ 里唯一认识其它全部域类的文件；反过来没有任何域类认识它（docs/17 §3.1 规则 R-B）。
## 依赖秩 10。
class_name JWSimState
extends RefCounted

# ── schema 常量 ────────────────────────────────────────────────────────────

## state.meta.schema_version 的代码常量（docs/11 §6.7 的 save.schema_version）。
## 数组长度、下标顺序、单位、盐值、新增必填状态字段的任何改动都必须 +1 并写迁移函数（INV-136）。
const SCHEMA_VERSION: int = 2

## 规范化编码的类型标签（docs/10 §11 的 `uint8 type_tag`）。
## 契约只规定「有一个 uint8 类型标签」，没有钉死取值；这三个数一经发布即进哈希，
## 改动等同于改哈希口径，属破坏性变更（INV-136）。
const TAG_INT: int = 1
const TAG_ARRAY: int = 2
const TAG_STRING: int = 3

## 条目 id 的字节长度上界：规范化编码用 uint16 存 id 长度（docs/10 §11）。
const ID_BYTES_MAX: int = 65535

# ── 注册表条目的种类 ───────────────────────────────────────────────────────

const ENTRY_STATE_SCALAR: int = 0
const ENTRY_STATE_ARRAY: int = 1
const ENTRY_FLOW_SCALAR: int = 2
const ENTRY_FLOW_ARRAY: int = 3
## SoA 的 ids[]（字符串数组，docs/11 §6.4 第 4 条唯一允许的字符串条目）
const ENTRY_SOA_IDS: int = 4

## _reg_block 中代表「本对象自己持有的字段」的哨兵
const SELF_BLOCK: int = -1
## _encode_into 的「不按子系统过滤」哨兵
const SUBSYS_ALL: int = -1

# ── 域类实例在 _blocks 中的下标（顺序 == docs/17 §4.27 成员表，不得重排） ──

const BLK_RNG: int = 0
const BLK_ACCOUNTS: int = 1
const BLK_LEDGER: int = 2
const BLK_IO: int = 3
const BLK_POLICY_DEFS: int = 4
const BLK_PRICING: int = 5
const BLK_BONDS: int = 6
const BLK_CAPITAL: int = 7
const BLK_POP: int = 8
const BLK_WORLD: int = 9
const BLK_TREASURY: int = 10
const BLK_LABOR: int = 11
const BLK_SHOCKS: int = 12
const BLK_INVENTORY: int = 13
const BLK_PROJECTS: int = 14
const BLK_MIGRATION: int = 15
const BLK_POLITICS: int = 16
const BLK_SECTORS: int = 17
const BLK_COMMISSIONING: int = 18
const BLK_POLICY: int = 19
const BLK_BLOCS: int = 20
const BLK_DIAG: int = 21
## R-MONEY-01：长期货币与价格水平（四百年重构新增，追加在末尾）。
const BLK_MONEY: int = 22
## R-BUILDING-01：建筑堆（生产单元产能与资本的唯一来源）。
const BLK_BUILDINGS: int = 23
## R-REGIME-01 / R-CRISIS-01：战役模式的政府更替与危机状态机。
const BLK_CRISIS: int = 24
## R-RESEARCH-01：研究与科技（战役模式）。
const BLK_RESEARCH: int = 25
## R-TRADE-01：贸易伙伴分账（战役模式）。
const BLK_PARTNERS: int = 26
## R-INVCREDIT-01：投资池对生产单元的资本放贷（战役模式；储蓄回到实体经济的唯一渠道）。
const BLK_CREDIT: int = 27
const BLOCK_N: int = 28

## 各块缺省子系统归属，下标 == BLK_*。
##
## 仅在该块**没有**声明对应的 `*_SUBSYS` 常量时兜底（docs/17 §1.6 只强制要求
## `STATE_ARRAY_SUBSYS` 一条）。已声明的块以它自己声明的为准，本表不参与。
## 待全部块补齐四条 `*_SUBSYS` 后，本表连同 _subsys_of() 的兜底分支一并删除。
const BLOCK_DEFAULT_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_RNG, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_META, JWUnits.SUBSYS_META,
	JWUnits.SUBSYS_POLICY, JWUnits.SUBSYS_PRICE, JWUnits.SUBSYS_BOND, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_GROUP, JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_GROUP,
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_CELL, JWUnits.SUBSYS_PROJECT, JWUnits.SUBSYS_POLICY,
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_META, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_CELL,
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_GOV, JWUnits.SUBSYS_WORLD, JWUnits.SUBSYS_CELL,
]

# ── 两个 SoA（docs/11 §6.4 的 soa 段只有这两个） ───────────────────────────

const SOA_BLOCK: PackedInt64Array = [BLK_BONDS, BLK_PROJECTS]
const SOA_NAMES: PackedStringArray = ["bond", "project"]
const SOA_ID_KEYS: PackedStringArray = ["state.bond.id", "state.project.id"]
const SOA_SUBSYS: PackedInt64Array = [JWUnits.SUBSYS_BOND, JWUnits.SUBSYS_PROJECT]

# ── 本对象自己持有的整数状态标量（下标即 _self_scalar 的分派序号，不得重排） ──

const SELF_STATE_SCALAR_IDS: PackedStringArray = [
	"state.meta.schema_version",
	"state.meta.param_set_version",
	"state.meta.replay_unreliable",
	"state.meta.command_seq",
	"state.meta.entity_seq",
	"state.time.q",
	"state.time.horizon_q",
	"state.time.phase",
	"state.meta.mode",
	"state.time.start_year",
]
const SELF_STATE_SCALAR_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_META, JWUnits.SUBSYS_META, JWUnits.SUBSYS_META, JWUnits.SUBSYS_META,
	JWUnits.SUBSYS_META, JWUnits.SUBSYS_TIME, JWUnits.SUBSYS_TIME, JWUnits.SUBSYS_TIME,
	JWUnits.SUBSYS_META, JWUnits.SUBSYS_TIME,
]

## 本对象自己持有的字符串状态标量（下标即 _self_string 的分派序号，不得重排）。
##
## **四项都不进 state_hash**，理由逐条：
## - `state.meta.state_hash_prev`：契约的排除清单第一项（docs/10 §11），自指会让哈希无法定义。
## - `state.meta.build_id`：INV-014 把「同 build_id」写成哈希相等的**前提**而不是输入；
##   且 INV-134 要求 build_id 不符时仍能读档继续游玩，若它进哈希，换构建即 E_SAVE_CORRUPT。
## - `state.meta.content_hash`：同理，INV-134 要求它不符时进只读检视而**不是**判存档损坏。
## - `state.meta.scenario_id`：剧本身份由 manifest 的 scenario_hash 负责（docs/11 §6.3）。
## 另有结构性理由：docs/11 §6.4 第 4 条把字符串条目限定为「仅用于 SoA 的 ids[]」。
## 四项仍然**全部进存档**（INV-131 的「全部跨季状态」）。
const SELF_STRING_IDS: PackedStringArray = [
	"state.meta.build_id",
	"state.meta.content_hash",
	"state.meta.scenario_id",
	"state.meta.state_hash_prev",
]

# ── 哈希与存档的排除口径（docs/10 §0.3 命名空间表 + docs/10 §11 排除清单） ──

## 不进 state_hash 的命名空间前缀。
## `derived.*` 读时计算，`param.*` / `content.*` 进 content_hash，`log.*` 进重放对比，
## `scenario.*` 是剧本常量 —— 四类都由 docs/10 §0.3 的表逐行判为「否」。
const HASH_EXCLUDED_PREFIXES: PackedStringArray = [
	"content.", "param.", "derived.", "log.", "scenario.",
]

## 逐条排除的稳定 ID。
## - `state.meta.state_hash_prev`：docs/10 §11 排除清单（字符串，本来也不进编码，这里再挡一道）。
## - `state.time.horizon_q`：docs/13 OQ-210 的临时取法要求 `--horizon 120` 与剧本的 40
##   在 q=0..39 逐季 state_hash 完全相同（验证项 T-R-HORIZON-OVERRIDE）；
##   若 horizon_q 进哈希，这条验证不可能成立。它照常进存档与 manifest。
const HASH_EXCLUDED_IDS: PackedStringArray = [
	"state.meta.state_hash_prev",
	"state.time.horizon_q",
]

## 不进存档的命名空间前缀：内容包只读常量不入档（docs/11 §6.7 M-8 内容包不做迁移，
## 一切由 content_hash 把关），派生量与日志本就可再生。
const SAVE_EXCLUDED_PREFIXES: PackedStringArray = [
	"content.", "param.", "derived.", "log.",
]

# ── 存档字典的键名（docs/11 §6.4） ─────────────────────────────────────────

const SAVE_KEY_SCHEMA: String = "schema_version"
const SAVE_KEY_SCALARS: String = "scalars"
const SAVE_KEY_ARRAYS: String = "arrays"
const SAVE_KEY_SOA: String = "soa"
const SAVE_KEY_N: String = "n"
const SAVE_KEY_ENC: String = "enc"
const SAVE_KEY_DATA: String = "data"
const SAVE_KEY_IDS: String = "ids"
const ENC_B64LE64: String = "b64le64"

## JSON 能精确表示的整数上界（2^53）。
##
## 超过它的整数经过任何标准 JSON 解析器都会掉成 double 并丢低位，
## 而 `state.rng.root_seed` 是 uint64 位型、天然可以超过它。
## 因此 to_dict 对超界标量改写十进制**字符串**，from_dict 两种形态都认。
## 这不是给 JSON 开例外：它保住的恰恰是 INV-132「读档复算 state_hash 必须逐位相同」。
const JSON_SAFE_INT_MAX: int = 1 << 53

# ── state.meta.* ───────────────────────────────────────────────────────────

## state.meta.schema_version —— 代码常量。写入者：LOAD/MIG
var schema_version: int = SCHEMA_VERSION
## state.meta.build_id —— 构建期注入。写入者：LOAD
var build_id: String = ""
## state.meta.content_hash —— 载入时计算。写入者：LOAD
var content_hash: String = ""
## state.meta.state_hash_prev。写入者：S01
var state_hash_prev: String = ""
## state.meta.scenario_id —— 剧本。写入者：LOAD
var scenario_id: String = ""
## state.meta.param_set_version —— 剧本。写入者：LOAD
var param_set_version: int = 0
## state.meta.replay_unreliable。写入者：LOAD
var replay_unreliable: bool = false
## state.meta.command_seq。写入者：CMD
var command_seq: int = 0
## state.meta.entity_seq。写入者：S02, S07
var entity_seq: int = 0

# ── state.time.* ───────────────────────────────────────────────────────────

## state.time.q —— 仅 S08 末 +1（INV-012）
var q: int = 0
## state.time.horizon_q —— 40 或 120。写入者：LOAD
var horizon_q: int = 40
## state.time.phase —— JWUnits.Phase。写入者：S01..S08
var phase: int = JWUnits.Phase.IDLE
## 分配各状态块时的地区数（不是状态，不进哈希与存档；R-SCENARIO-02）。
var dims_r: int = 0
## state.meta.mode —— JWUnits.Mode（R-SCENARIO-01）。写入者：LOAD
var mode: int = JWUnits.Mode.TERM
## state.time.start_year —— 第 0 季所在公历年，0 = 不显示年份（R-CLOCK-01）。写入者：LOAD
var start_year: int = 0

# ── 内容常量与参数 ─────────────────────────────────────────────────────────

## scenario.total_cash_uu —— 剧本。写入者：LOAD。INV-018 的目标值
var total_cash_uu: int = 0
## param.* 的稠密数组，长 JWUnits.PARAM_N。写入者：LOAD
var params: PackedInt64Array = PackedInt64Array()

# ── 域类实例（顺序进哈希，不得重排） ───────────────────────────────────────

var rng: JWRngStreams = null
var accounts: JWAccount = null
var ledger: JWLedger = null
var io: JWIoTable = null
var policy_defs: JWPolicyDef = null
var pricing: JWPricing = null
var bonds: JWBondBook = null
var capital: JWCapital = null
var pop: JWPopulation = null
var world: JWWorldMarket = null
var treasury: JWTreasury = null
var labor: JWLaborMarket = null
var shocks: JWShocks = null
var inventory: JWInventory = null
var projects: JWProjectQueue = null
var migration: JWMigration = null
var politics: JWPolitics = null
var sectors: JWSectorModel = null
var commissioning: JWAssetCommissioning = null
var policy: JWPolicyEngine = null
var blocs: JWInterestGroups = null
var diag: JWDiagnostics = null
var money: JWMoney = null
var buildings: JWBuildings = null
var crisis: JWCrisis = null
var research: JWResearch = null
var partners: JWPartners = null
var credit: JWCredit = null

## 按上表顺序登记的状态块；顺序进哈希，不得重排（INV-136）。
var _blocks: Array[RefCounted] = []

# ── 条目注册表（allocate_all 期建一次，此后只读；按稳定 ID 字节序升序） ────
#
# 它是 docs/17 §1.6 的「对一个注册表的遍历」在根上的落点：哈希、子系统哈希、
# 存档、深拷贝四件事共用同一张表，因此不可能出现「某个字段进了哈希却没进存档」。

## 条目的稳定 ID
var _reg_id: PackedStringArray = PackedStringArray()
## 条目 ID 的 UTF-8 字节（预算好，编码时不再转换）
var _reg_id_utf8: Array[PackedByteArray] = []
## 条目所属块下标；SELF_BLOCK 表示本对象自己
var _reg_block: PackedInt64Array = PackedInt64Array()
## 条目种类 ENTRY_*
var _reg_kind: PackedInt64Array = PackedInt64Array()
## 条目在该块对应注册表内的下标
var _reg_slot: PackedInt64Array = PackedInt64Array()
## 条目所属子系统（JWUnits.SUBSYS_*）
var _reg_subsys: PackedInt64Array = PackedInt64Array()
## 1 表示进 state_hash
var _reg_in_hash: PackedInt64Array = PackedInt64Array()
## 1 表示进存档
var _reg_in_save: PackedInt64Array = PackedInt64Array()

## 规范化编码的复用缓冲。每次哈希先 resize(0) 再写满，不新建对象（docs/17 §1.4）。
var _hash_buf: PackedByteArray = PackedByteArray()

## sha256_hex 的复用上下文。静态成员，避免每次哈希新建一个 HashingContext。
static var _sha_ctx: HashingContext = null

# ── 方法 ───────────────────────────────────────────────────────────────────

## 一次性分配全部数组到 docs/17 §2 的契约长度。此后长度永不改变。
## 步骤：LOAD
## 前置：维度常量已确定
## 后置：每个块的 allocate() 都跑过；不再有任何 resize
## 不变量：docs/10 §0.6（加载期一次性 resize）
## 失败：无
func allocate_all() -> void:
	# R-SCENARIO-02：记下分配时的地区数；载入另一种地区数的剧本时据此判断要不要重新分配。
	dims_r = JWUnits.R
	rng = JWRngStreams.new()
	accounts = JWAccount.new()
	# **必须把 accounts 注入账本**（docs/17 §4.10 成员表「构造注入」）：
	# JWLedger 的 post / post_multi / post_noncash / post_opening 四个入口都以
	# `_accounts == null` 开头判 PHASE_VIOLATION。用无参构造建出来的账本一笔都过不了账，
	# 于是整局跑下来账面恒为 0，而每一步都「返回 OK」——最坏的一类静默。
	ledger = JWLedger.new(accounts)
	io = JWIoTable.new()
	policy_defs = JWPolicyDef.new()
	pricing = JWPricing.new()
	bonds = JWBondBook.new()
	capital = JWCapital.new()
	pop = JWPopulation.new()
	world = JWWorldMarket.new()
	treasury = JWTreasury.new()
	labor = JWLaborMarket.new()
	shocks = JWShocks.new()
	inventory = JWInventory.new()
	projects = JWProjectQueue.new()
	migration = JWMigration.new()
	politics = JWPolitics.new()
	sectors = JWSectorModel.new()
	commissioning = JWAssetCommissioning.new()
	policy = JWPolicyEngine.new()
	blocs = JWInterestGroups.new()
	diag = JWDiagnostics.new()
	money = JWMoney.new()
	buildings = JWBuildings.new()
	crisis = JWCrisis.new()
	research = JWResearch.new()
	partners = JWPartners.new()
	credit = JWCredit.new()
	capital.buildings = buildings

	_blocks.clear()
	_blocks.resize(BLOCK_N)
	_blocks[BLK_RNG] = rng
	_blocks[BLK_ACCOUNTS] = accounts
	_blocks[BLK_LEDGER] = ledger
	_blocks[BLK_IO] = io
	_blocks[BLK_POLICY_DEFS] = policy_defs
	_blocks[BLK_PRICING] = pricing
	_blocks[BLK_BONDS] = bonds
	_blocks[BLK_CAPITAL] = capital
	_blocks[BLK_POP] = pop
	_blocks[BLK_WORLD] = world
	_blocks[BLK_TREASURY] = treasury
	_blocks[BLK_LABOR] = labor
	_blocks[BLK_SHOCKS] = shocks
	_blocks[BLK_INVENTORY] = inventory
	_blocks[BLK_PROJECTS] = projects
	_blocks[BLK_MIGRATION] = migration
	_blocks[BLK_POLITICS] = politics
	_blocks[BLK_SECTORS] = sectors
	_blocks[BLK_COMMISSIONING] = commissioning
	_blocks[BLK_POLICY] = policy
	_blocks[BLK_BLOCS] = blocs
	_blocks[BLK_DIAG] = diag
	_blocks[BLK_MONEY] = money
	_blocks[BLK_BUILDINGS] = buildings
	_blocks[BLK_CRISIS] = crisis
	_blocks[BLK_RESEARCH] = research
	_blocks[BLK_PARTNERS] = partners
	_blocks[BLK_CREDIT] = credit

	for b: RefCounted in _blocks:
		b.allocate()

	params.resize(JWUnits.PARAM_N)
	params.fill(0)
	_build_registry()


## S01 §01.3：遍历流量注册表整表清零。这是全局唯一允许整表清零流量的地方。
## 步骤：S01 §01.3
## 前置：phase == S01
## 后置：全部 flow.* 为 0；随后 flow_abs_sum_all() 必须为 0
## 不变量：INV-013；清零后非零 → 说明有步骤在 S08 之后写了流量
## 失败：Fault.FLOW_NOT_RESET
func reset_all_flows() -> int:
	for b: RefCounted in _blocks:
		b.reset_flows()
	var residual: int = flow_abs_sum_all()
	if residual != 0:
		# 清零之后还有非 0 流量，只有两种可能：某个块的 reset_flows() 漏了一个数组，
		# 或者有步骤绕过注册表直接写了流量。两者都是结构性缺陷，不许就地抹平。
		return JWResult.raise_fault(JWResult.Fault.FLOW_NOT_RESET, residual, 0)
	return JWResult.OK


## 全部块的流量绝对值之和，S01 清零后的自检值。
## 步骤：S01 §01.3
## 前置：reset_all_flows() 已跑过
## 后置：不改状态
## 不变量：INV-013
## 失败：无（调用方按返回值判 Fault.FLOW_NOT_RESET）
func flow_abs_sum_all() -> int:
	var acc: int = 0
	for b: RefCounted in _blocks:
		acc += b.flow_abs_sum()
	return acc


## `q` 的唯一写入点（INV-012 的静态检查锚点）。
## 步骤：S08 §8.7
## 前置：phase == S08；本季全部步骤已完成
## 后置：q += 1
## 不变量：INV-012（state.time.q 只在 S08 末 +1，无其它写入路径）
## 失败：phase 不对 → Fault.PHASE_VIOLATION
func advance_quarter_index() -> int:
	if phase != JWUnits.Phase.S08:
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, phase, JWUnits.Phase.S08)
	q += 1
	return JWResult.OK


## 运行期实体 ID 的唯一来源（单调计数器）。
## 步骤：S02（债券、项目）、S07
## 前置：无
## 后置：entity_seq += 1，返回新值
## 不变量：INV-010（禁止时间戳、指针地址、哈希）
## 失败：无
func next_entity_seq() -> int:
	entity_seq += 1
	return entity_seq


## 规范化编码：整数标量条目。
## 步骤：每季末、存档、WriteGuard
## 前置：buf 是调用方提供的缓冲（热路径不新建）
## 后置：向 buf 追加 uint16 len(id) + id 的 UTF-8 + uint8 type_tag + int64 小端 8 字节
## 不变量：INV-001（遇 float 抛 FLOAT_IN_STATE）、INV-014
## 失败：遇 float → Fault.FLOAT_IN_STATE
##
## 参数类型已经是 int，float 在这一层进不来；INV-001 的防线在 from_dict 的
## _variant_to_int()（读档是唯一可能把 float 混进状态的入口）与构建期静态检查上。
static func canon_scalar(buf: PackedByteArray, id_utf8: PackedByteArray, v: int) -> void:
	var idn: int = id_utf8.size()
	if idn > ID_BYTES_MAX:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idn, ID_BYTES_MAX)
		return
	var base: int = buf.size()
	buf.resize(base + 2 + idn + 1 + 8)
	buf.encode_u16(base, idn)
	_blit(buf, base + 2, id_utf8)
	buf.encode_u8(base + 2 + idn, TAG_INT)
	buf.encode_s64(base + 3 + idn, v)


## 规范化编码：整数数组条目。
## 步骤：每季末、存档、WriteGuard
## 前置：buf 是调用方提供的缓冲
## 后置：向 buf 追加条目头 + uint32 长度（小端） + 逐元素 8 字节
## 不变量：INV-001、INV-014
## 失败：遇 float → Fault.FLOAT_IN_STATE
static func canon_array(buf: PackedByteArray, id_utf8: PackedByteArray, a: PackedInt64Array) -> void:
	var idn: int = id_utf8.size()
	if idn > ID_BYTES_MAX:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idn, ID_BYTES_MAX)
		return
	var n: int = a.size()
	var base: int = buf.size()
	buf.resize(base + 2 + idn + 1 + 4 + 8 * n)
	buf.encode_u16(base, idn)
	_blit(buf, base + 2, id_utf8)
	buf.encode_u8(base + 2 + idn, TAG_ARRAY)
	buf.encode_u32(base + 3 + idn, n)
	var off: int = base + 3 + idn + 4
	var i: int = 0
	while i < n:
		buf.encode_s64(off + 8 * i, a[i])
		i += 1


## 规范化编码：字符串条目（仅用于 SoA 的 ids[]）。
## 步骤：存档
## 前置：buf 是调用方提供的缓冲
## 后置：向 buf 追加条目头 + uint32 字节长度 + UTF-8
## 不变量：INV-014
## 失败：无
static func canon_string(buf: PackedByteArray, id_utf8: PackedByteArray, s: String) -> void:
	var idn: int = id_utf8.size()
	if idn > ID_BYTES_MAX:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, idn, ID_BYTES_MAX)
		return
	var sb: PackedByteArray = s.to_utf8_buffer()
	var sn: int = sb.size()
	var base: int = buf.size()
	buf.resize(base + 2 + idn + 1 + 4 + sn)
	buf.encode_u16(base, idn)
	_blit(buf, base + 2, id_utf8)
	buf.encode_u8(base + 2 + idn, TAG_STRING)
	buf.encode_u32(base + 3 + idn, sn)
	_blit(buf, base + 3 + idn + 4, sb)


## 把 src 的全部字节逐字拷到 dst 的 offset 处（dst 必须已经够长）。
## 步骤：规范化编码内部
## 前置：dst.size() >= offset + src.size()
## 后置：dst[offset + i] == src[i]
## 不变量：INV-014
## 失败：无
static func _blit(dst: PackedByteArray, offset: int, src: PackedByteArray) -> void:
	var n: int = src.size()
	var i: int = 0
	while i < n:
		dst[offset + i] = src[i]
		i += 1


## 规范化缓冲的 SHA-256 十六进制串。
## 步骤：每季末、存档、WriteGuard
## 前置：无
## 后置：不改状态
## 不变量：INV-014
## 失败：无
static func sha256_hex(buf: PackedByteArray) -> String:
	if _sha_ctx == null:
		_sha_ctx = HashingContext.new()
	_sha_ctx.start(HashingContext.HASH_SHA256)
	if not buf.is_empty():
		# HashingContext.update() 对空缓冲返回 FAILED 并打一条引擎级 ERROR。
		# 空输入不是错误：条目为空的子系统（subsystem_hash 的合法情形）就该得到
		# 「空串的 SHA-256」这个确定值。跳过 update 得到的正是它，不跳过则是一条噪声日志
		# 外加同一个值 —— WriteGuard 每季要调它两百多次，必须挡住。
		_sha_ctx.update(buf)
	return _sha_ctx.finish().hex_encode()


## 全状态哈希。条目按稳定 ID 的字节序升序拼接。
## 步骤：S01 入口（记 prev）、每步末（WriteGuard）、S08 末、存档
## 前置：无
## 后置：不改状态
## 不变量：INV-014（同构建 + 同内容 + 同种子 + 同命令流 ⇒ 每季逐位相同）；
##       排除清单：state.meta.state_hash_prev 自身、全部 log.*、全部 derived.*、
##       一切 label_zh / desc_zh / report_template_id / 时间戳
## 失败：无
func state_hash() -> String:
	_encode_into(_hash_buf, SUBSYS_ALL)
	return sha256_hex(_hash_buf)


## 单个子系统的哈希，用于 WriteGuard 与逐步骤哈希。
## 步骤：每步入口与出口
## 前置：subsys ∈ [0, JWUnits.SUBSYS_N)
## 后置：不改状态
## 不变量：INV-013（写出可写子集即 WRITE_OUT_OF_SCOPE）、INV-014
## 失败：越界 → Fault.INDEX_OUT_OF_RANGE 返回空串
func subsystem_hash(subsys: int) -> String:
	if subsys < 0 or subsys >= JWUnits.SUBSYS_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, subsys, JWUnits.SUBSYS_N)
		return ""
	_encode_into(_hash_buf, subsys)
	return sha256_hex(_hash_buf)


## 按注册表顺序把命中条目规范化编码进 buf。
## 步骤：state_hash / subsystem_hash
## 前置：注册表已建好（allocate_all 跑过）
## 后置：buf 被整段重写；不改任何状态
## 不变量：INV-014（顺序由 _build_registry 的字节序排序定死，与遍历实现无关）
## 失败：无
func _encode_into(buf: PackedByteArray, subsys_filter: int) -> void:
	buf.resize(0)
	var n: int = _reg_id.size()
	var e: int = 0
	while e < n:
		if _reg_in_hash[e] == 0:
			e += 1
			continue
		if subsys_filter != SUBSYS_ALL and _reg_subsys[e] != subsys_filter:
			e += 1
			continue
		var kind: int = _reg_kind[e]
		var idb: PackedByteArray = _reg_id_utf8[e]
		if kind == ENTRY_STATE_SCALAR or kind == ENTRY_FLOW_SCALAR:
			canon_scalar(buf, idb, _entry_scalar(e))
		elif kind == ENTRY_STATE_ARRAY or kind == ENTRY_FLOW_ARRAY:
			canon_array(buf, idb, _entry_array(e))
		else:
			# SoA 的 ids[]：逐行一条字符串条目。同一 id 的多条按行号升序相邻排列，
			# 排序是稳定的，因此拼接顺序与行号顺序一致（INV-008 的遍历确定性）。
			var ids: PackedStringArray = _soa_ids(_reg_slot[e])
			var cnt: int = _soa_count(_reg_slot[e])
			var j: int = 0
			while j < cnt and j < ids.size():
				canon_string(buf, idb, ids[j])
				j += 1
		e += 1


## 事件触发条件的 metric 求值（只有比较，没有表达式器）。
## 步骤：S08 §8.4（由 JWEventEngine 调用）
## 前置：metric_code 已在加载期解析成整数码（V-EV-02）
## 后置：不改状态
## 不变量：INV-130；docs/11 §5.13 的 V-EV-02/03
## 失败：未知 metric → Fault.METRIC_UNKNOWN 返回 0
func read_metric(metric_code: int, scope_idx: int) -> int:
	# metric_code 就是**条目注册表下标**：_build_registry() 把全部稳定 ID 按字节序升序排定，
	# 加载期 V-EV-02 用 registry_size() / registry_id() 逐条反查「这个 ID 存不存在、是第几条」，
	# 把 EventTemplate 的 trigger.metric 解析成这个整数码（docs/11 §5.13）。
	# 注册表本身的顺序由 INV-008 / INV-014 定死，因此同构建同内容下码值稳定可复现。
	# 覆盖范围：state.* / flow.* / content.* / param.* 四个命名空间的标量与数组条目。
	# derived.* 是读时计算、不进注册表（docs/10 §11 排除清单），SoA 的 ids[] 是字符串，
	# 两者都没有可比较的整数取值 —— 一律按契约登记 METRIC_UNKNOWN 返回 0，不猜默认值。
	if metric_code < 0 or metric_code >= _reg_id.size():
		JWResult.raise_fault(JWResult.Fault.METRIC_UNKNOWN, metric_code, _reg_id.size())
		return 0
	var kind: int = _reg_kind[metric_code]
	if kind == ENTRY_STATE_SCALAR or kind == ENTRY_FLOW_SCALAR:
		# 标量条目没有作用域维度，scope_idx 不参与求值（条件里的 scope 由 V-EV-02 在
		# 加载期与 metric 配对校验；运行期这里只有一个取值可读，凭空拿它做下标才是错的）。
		return _entry_scalar(metric_code)
	if kind == ENTRY_STATE_ARRAY or kind == ENTRY_FLOW_ARRAY:
		var a: PackedInt64Array = _entry_array(metric_code)
		if scope_idx < 0 or scope_idx >= a.size():
			# 作用域下标越界是程序缺陷（加载期已把 scope 解析成稠密下标），按 docs/10 §0.8 走 FAULT。
			JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, scope_idx, a.size())
			return 0
		return a[scope_idx]
	JWResult.raise_fault(JWResult.Fault.METRIC_UNKNOWN, metric_code, kind)
	return 0


## 序列化（docs/11 §6.4 的 scalars / arrays / soa 三段）。
## 步骤：存档（冷路径）
## 前置：无
## 后置：返回可直接写盘的字典；大数组 enc == "b64le64"
## 不变量：INV-131（存档含全部跨季状态 + root_seed + 6 个计数器 + 完整命令流）
## 失败：无
##
## 命令流（commands.jsonl）与冲击记录（shock_log.jsonl）由 JWCommands / JWShocks 各自导出，
## 不在本字典内（docs/11 §6.2 的目录结构）。`state_hash` 也不在本字典内：
## 它写在 manifest.json，由 JWSaves 在读档时复算比对（docs/11 §6.6）。
func to_dict() -> Dictionary:
	var scalars: Dictionary = {}
	var arrays: Dictionary = {}
	var n: int = _reg_id.size()
	var e: int = 0
	while e < n:
		if _reg_in_save[e] == 0:
			e += 1
			continue
		var kind: int = _reg_kind[e]
		if kind == ENTRY_STATE_SCALAR or kind == ENTRY_FLOW_SCALAR:
			scalars[_reg_id[e]] = _json_int(_entry_scalar(e))
		elif kind == ENTRY_STATE_ARRAY or kind == ENTRY_FLOW_ARRAY:
			var a: PackedInt64Array = _entry_array(e)
			var rec: Dictionary = {}
			rec[SAVE_KEY_N] = a.size()
			rec[SAVE_KEY_ENC] = ENC_B64LE64
			rec[SAVE_KEY_DATA] = Marshalls.raw_to_base64(a.to_byte_array())
			arrays[_reg_id[e]] = rec
		e += 1

	var i: int = 0
	while i < SELF_STRING_IDS.size():
		scalars[SELF_STRING_IDS[i]] = _self_string(i)
		i += 1

	var soa: Dictionary = {}
	var k: int = 0
	while k < SOA_NAMES.size():
		var ids: PackedStringArray = _soa_ids(k)
		var cnt: int = _soa_count(k)
		var out: Array = []
		var j: int = 0
		while j < cnt and j < ids.size():
			out.append(ids[j])
			j += 1
		var srec: Dictionary = {}
		srec[SAVE_KEY_N] = out.size()
		srec[SAVE_KEY_IDS] = out
		soa[SOA_NAMES[k]] = srec
		k += 1

	var d: Dictionary = {}
	d[SAVE_KEY_SCHEMA] = schema_version
	d[SAVE_KEY_SCALARS] = scalars
	d[SAVE_KEY_ARRAYS] = arrays
	d[SAVE_KEY_SOA] = soa
	return d


## 反序列化。
## 步骤：读档（冷路径）
## 前置：schema_version 已迁移到当前版本
## 后置：from_dict 之后立即重算 state_hash 并与档内值比对
## 不变量：INV-131、INV-132（不符即 E_SAVE_CORRUPT 拒绝载入，不做尽力修复）
## 失败：Load.SAVE_CORRUPT / Load.SAVE_VERSION_TOO_NEW
##
## 每写一个条目都**读回来比一次**。这一步不是冗余：
## (a) 挡住「某个块的 set_state_* 还是空实现」造成的静默丢数据；
## (b) 挡住长度不符、编码不符被下游忽略；
## (c) 让 INV-132 的「不做尽力修复」在本函数内就成立 —— 对不上就拒绝，不留半截状态。
## 与档内 state_hash 的比对由 JWSaves 负责（哈希在 manifest.json 里，本函数看不到）。
func from_dict(src: Dictionary) -> JWResult:
	if not src.has(SAVE_KEY_SCHEMA) or not src.has(SAVE_KEY_SCALARS) \
			or not src.has(SAVE_KEY_ARRAYS) or not src.has(SAVE_KEY_SOA):
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)
	var sv: int = _variant_to_int(src[SAVE_KEY_SCHEMA])
	if sv > SCHEMA_VERSION:
		return JWResult.make_err(JWResult.Load.SAVE_VERSION_TOO_NEW, sv, SCHEMA_VERSION)
	if sv < SCHEMA_VERSION:
		# 迁移链是 JWSaves 的职责且不许跳版（docs/11 §6.7 M-2）；到本函数时必须已经是当前版本。
		return JWResult.make_err(JWResult.Load.MIGRATION_MISSING, sv, SCHEMA_VERSION)
	if _reg_id.is_empty():
		# allocate_all() 没跑过，没有注册表可填。
		return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, 0, 0)

	var scalars: Dictionary = src[SAVE_KEY_SCALARS]
	var arrays: Dictionary = src[SAVE_KEY_ARRAYS]
	var soa: Dictionary = src[SAVE_KEY_SOA]

	var n: int = _reg_id.size()
	var e: int = 0
	while e < n:
		if _reg_in_save[e] == 0:
			e += 1
			continue
		var key: String = _reg_id[e]
		var kind: int = _reg_kind[e]
		if kind == ENTRY_STATE_SCALAR or kind == ENTRY_FLOW_SCALAR:
			if not scalars.has(key):
				# 缺失字段禁止用 0 填充（docs/11 §6.7 M-5）。
				return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, e, 0)
			var want: int = _variant_to_int(scalars[key])
			_entry_set_scalar(e, want)
			if _entry_scalar(e) != want:
				return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, e, want)
		elif kind == ENTRY_STATE_ARRAY or kind == ENTRY_FLOW_ARRAY:
			if not arrays.has(key):
				return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, e, 0)
			var rec: Dictionary = arrays[key]
			if not rec.has(SAVE_KEY_N) or not rec.has(SAVE_KEY_ENC) or not rec.has(SAVE_KEY_DATA):
				return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, e, 0)
			if String(rec[SAVE_KEY_ENC]) != ENC_B64LE64:
				return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, e, 0)
			var want_n: int = _variant_to_int(rec[SAVE_KEY_N])
			var raw: PackedByteArray = Marshalls.base64_to_raw(String(rec[SAVE_KEY_DATA]))
			if raw.size() != want_n * 8:
				return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, e, raw.size())
			var want_a: PackedInt64Array = raw.to_int64_array()
			_entry_set_array(e, want_a)
			if _entry_array(e) != want_a:
				return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, e, want_n)
		e += 1

	var i: int = 0
	while i < SELF_STRING_IDS.size():
		if not scalars.has(SELF_STRING_IDS[i]):
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, i, 0)
		_self_set_string(i, String(scalars[SELF_STRING_IDS[i]]))
		i += 1

	var k: int = 0
	while k < SOA_NAMES.size():
		if not soa.has(SOA_NAMES[k]):
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, k, 0)
		var srec: Dictionary = soa[SOA_NAMES[k]]
		if not srec.has(SAVE_KEY_IDS):
			return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, k, 0)
		var list: Array = srec[SAVE_KEY_IDS]
		var want_ids: PackedStringArray = PackedStringArray()
		var j: int = 0
		while j < list.size():
			want_ids.append(String(list[j]))
			j += 1
		_soa_set_ids(k, want_ids)
		var got: PackedStringArray = _soa_ids(k)
		var m: int = 0
		while m < want_ids.size():
			if m >= got.size() or got[m] != want_ids[m]:
				return JWResult.make_err(JWResult.Load.SAVE_CORRUPT, k, m)
			m += 1
		k += 1

	return JWResult.make_ok()


## 只读深拷贝（情景预测与对账页用；不在热路径调用）。
## 步骤：S08 §8.6、UI 对账页
## 前置：无
## 后置：返回一个与本对象逐位相同、互不共享数组的副本
## 不变量：docs/12 §14（每季 duplicate 整份状态是被结构性排除的风险）
## 失败：无
##
## 走的是**全部**注册表条目（含 content.* 与 param.*），不是存档口径 ——
## 副本要能独立跑情景预测，缺了投入产出系数表就没法算。
func duplicate_state() -> JWSimState:
	var c: JWSimState = JWSimState.new()
	c.allocate_all()
	c.schema_version = schema_version
	c.build_id = build_id
	c.content_hash = content_hash
	c.state_hash_prev = state_hash_prev
	c.scenario_id = scenario_id
	c.param_set_version = param_set_version
	c.replay_unreliable = replay_unreliable
	c.command_seq = command_seq
	c.entity_seq = entity_seq
	c.q = q
	c.horizon_q = horizon_q
	c.phase = phase
	c.mode = mode
	c.start_year = start_year
	c.total_cash_uu = total_cash_uu
	c.params = params.duplicate()

	var n: int = _reg_id.size()
	var e: int = 0
	while e < n:
		var kind: int = _reg_kind[e]
		if kind == ENTRY_STATE_SCALAR or kind == ENTRY_FLOW_SCALAR:
			c._entry_set_scalar(e, _entry_scalar(e))
		elif kind == ENTRY_STATE_ARRAY or kind == ENTRY_FLOW_ARRAY:
			c._entry_set_array(e, _entry_array(e).duplicate())
		else:
			c._soa_set_ids(_reg_slot[e], _soa_ids(_reg_slot[e]).duplicate())
		e += 1
	return c


## 全部 P0 不变量的统一检查入口（载入后、每季末、故障包导出前）。
## 步骤：LOAD 末、季末
## 前置：无
## 后置：不改状态
## 不变量：INV-015..021, 024, 025, 027, 028, 035, 047, 071, 083 …（完整清单见 docs/12 §10）
## 失败：返回第一个失败的 Fault 码；不回滚到「看起来正常」的状态
## 载入收尾：重建各子系统的私有「上季基准」，使载入后的状态能被 P0 不变量核对。
## 步骤：LOAD（JWContentLoader 与 JWSaves 在 check_all_p0 之前各调一次；幂等）
## 前置：全部状态块已写入
## 后置：pop 的上季基准与迁移账对齐；不改任何进 state_hash 的字段
## 不变量：见 JWPopulation.rebase_after_load
## 失败：透传子系统的故障码
func finalize_load() -> int:
	if _blocks.is_empty():
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, BLOCK_N)
	var rc: int = pop.rebase_after_load(migration.in_by_group(), migration.out_by_group())
	if rc != JWResult.OK:
		return rc
	# R-CONS-01 补遗：新开局（q == 0）播种上季可支配收入；读回的 q > 0 存档保留存档值。
	if q == 0:
		pop.seed_disposable_prev(pricing)
	return inventory.rebase_after_load(sectors.f_output_actual, io)


## INV-018 的期望现金总量：剧本登记值 + 累计货币发行（R-MONEY-01；旧剧本发行恒为 0，即剧本登记值）。
## 全部现金闭合检查都用它，不各自拼。
func cash_expected() -> int:
	return total_cash_uu + money.issued_total


func check_all_p0() -> int:
	if _blocks.is_empty():
		return JWResult.raise_fault(JWResult.Fault.PHASE_VIOLATION, 0, BLOCK_N)
	# docs/12 §10「季末（全部步骤后）」与「载入后」两行里签名齐备的检查。
	var rc: int = accounts.check_cash_closure(cash_expected(), cash_expected())
	if rc != JWResult.OK:
		return rc
	rc = accounts.check_receivable_payable()
	if rc != JWResult.OK:
		return rc
	# INV-B01（R-BUILDING-01）：cell 的产能与资本 == 建筑堆按 cell 求和。
	rc = capital.check_buildings_consistency()
	if rc != JWResult.OK:
		return rc
	rc = accounts.check_balance_sheet()
	if rc != JWResult.OK:
		return rc
	rc = treasury.check_fiscal_identities(bonds, accounts)
	if rc != JWResult.OK:
		return rc
	# 产能轨／价值轨的全存量一致性（V-CELL-03）**不在此列**：OQ-206 裁定它只在载入期强制，
	# 由 JWContentLoader 解析 cells_init 时逐 cell 执行。本函数还在季末与读档后运行，
	# 那时两轨已因各自 floor 的折旧合法地漂移，诊断见 JWCapital.capacity_value_drift_ppm。
	rc = labor.check_employment_views(pop)
	if rc != JWResult.OK:
		return rc
	# docs/12 §10「载入后」一行要求**全部** P0 不变量，INV-071..073 与 INV-047/059 都在其内。
	# 这两个检查要本季的流量数组做入参，而它们分别是 JWMigration 与 JWSectorModel 的成员，
	# 本对象两块都持有：迁入/迁出汇总走 in_by_group()/out_by_group()（S07 末的同一对数组），
	# 实际产出走 sectors.f_output_actual（S05 末的同一张数组）。两者都是本季流量，
	# 在 S01 的 reset_all_flows() 之前一直有效，存档也逐条带走，因此载入后同样可复核。
	# JWTurnRunner 仍会在 S07/S05 末就地按步调用同样的检查（§10 的分步行），这里是汇总兜底。
	rc = pop.check_conservation(migration.in_by_group(), migration.out_by_group())
	if rc != JWResult.OK:
		return rc
	rc = inventory.check_stock_identity(sectors.f_output_actual)
	if rc != JWResult.OK:
		return rc
	if JWResult.has_pending():
		return JWResult.pending_code()
	return JWResult.OK

# ── 注册表构建（冷路径，只在 allocate_all() 内跑一次） ─────────────────────

## 建条目注册表并按稳定 ID 的字节序升序排定。
## 步骤：LOAD
## 前置：_blocks 已构造且每块 allocate() 已跑过
## 后置：_reg_* 等长；顺序为稳定 ID 字节序升序；无重复 ID
## 不变量：INV-008（遍历顺序确定）、INV-014（哈希顺序确定）、INV-136
## 失败：ID 重复 → Fault.INDEX_OUT_OF_RANGE（重复即 schema 缺陷，不许两个字段抢同一个名字）
func _build_registry() -> void:
	_reg_id = PackedStringArray()
	_reg_id_utf8 = []
	_reg_block = PackedInt64Array()
	_reg_kind = PackedInt64Array()
	_reg_slot = PackedInt64Array()
	_reg_subsys = PackedInt64Array()
	_reg_in_hash = PackedInt64Array()
	_reg_in_save = PackedInt64Array()

	var i: int = 0
	while i < SELF_STATE_SCALAR_IDS.size():
		_reg_add(SELF_STATE_SCALAR_IDS[i], SELF_BLOCK, ENTRY_STATE_SCALAR, i,
				SELF_STATE_SCALAR_SUBSYS[i])
		i += 1

	var bi: int = 0
	while bi < _blocks.size():
		var cmap: Dictionary = _constants_of(bi)
		_reg_add_group(bi, cmap, "STATE_SCALAR_IDS", "STATE_SCALAR_SUBSYS", ENTRY_STATE_SCALAR)
		_reg_add_group(bi, cmap, "STATE_ARRAY_IDS", "STATE_ARRAY_SUBSYS", ENTRY_STATE_ARRAY)
		_reg_add_group(bi, cmap, "FLOW_SCALAR_IDS", "FLOW_SCALAR_SUBSYS", ENTRY_FLOW_SCALAR)
		_reg_add_group(bi, cmap, "FLOW_ARRAY_IDS", "FLOW_ARRAY_SUBSYS", ENTRY_FLOW_ARRAY)
		bi += 1

	var k: int = 0
	while k < SOA_NAMES.size():
		_reg_add(SOA_ID_KEYS[k], SOA_BLOCK[k], ENTRY_SOA_IDS, k, SOA_SUBSYS[k])
		k += 1

	_reg_sort()
	_reg_flags()


## 取某个块脚本的常量表（只在 LOAD 期反射一次，结算期不再触碰）。
## 步骤：LOAD
## 前置：_blocks[bi] 有脚本
## 后置：不改状态
## 不变量：docs/17 §1.6
## 失败：取不到脚本 → 返回空表（该块视为没有注册任何条目）
func _constants_of(bi: int) -> Dictionary:
	var b: RefCounted = _blocks[bi]
	var gds: GDScript = b.get_script() as GDScript
	if gds == null:
		return {}
	return gds.get_script_constant_map()


## 把某个块的一组注册表条目加进总表。
## 步骤：LOAD
## 前置：cmap 是该块的常量表
## 后置：该组每条 ID 各成一个条目
## 不变量：INV-136（下标顺序 == 该块注册表下标顺序）
## 失败：无（缺常量即视为该组为空）
func _reg_add_group(bi: int, cmap: Dictionary, ids_key: String, subsys_key: String,
		kind: int) -> void:
	if not cmap.has(ids_key):
		return
	var ids: PackedStringArray = cmap[ids_key]
	var subsys: PackedInt64Array = PackedInt64Array()
	if cmap.has(subsys_key):
		subsys = cmap[subsys_key]
	var i: int = 0
	while i < ids.size():
		var s: int = BLOCK_DEFAULT_SUBSYS[bi]
		if i < subsys.size():
			s = subsys[i]
		_reg_add(ids[i], bi, kind, i, s)
		i += 1


## 追加一个条目。
## 步骤：LOAD
## 前置：无
## 后置：_reg_* 各追加一项
## 不变量：INV-136
## 失败：无
func _reg_add(id: String, block: int, kind: int, slot: int, subsys: int) -> void:
	_reg_id.append(id)
	_reg_id_utf8.append(id.to_utf8_buffer())
	_reg_block.append(block)
	_reg_kind.append(kind)
	_reg_slot.append(slot)
	_reg_subsys.append(subsys)


## 按稳定 ID 的**字节序**升序重排注册表，并检出重复 ID。
## 步骤：LOAD
## 前置：_reg_* 已填满
## 后置：∀ i < j，_reg_id_utf8[i] 的字节序严格小于 _reg_id_utf8[j]
## 不变量：INV-008、INV-014（拼接顺序不得依赖 Dictionary 迭代序或文件顺序）
## 失败：重复 ID → Fault.INDEX_OUT_OF_RANGE
func _reg_sort() -> void:
	var n: int = _reg_id.size()
	var order: PackedInt64Array = PackedInt64Array()
	order.resize(n)
	var i: int = 0
	while i < n:
		order[i] = i
		i += 1
	# 插入排序：n 约两百，只在加载期跑一次，不值得为它引入排序器。
	var s: int = 1
	while s < n:
		var key: int = order[s]
		var j: int = s - 1
		while j >= 0 and _id_less(_reg_id_utf8[key], _reg_id_utf8[order[j]]):
			order[j + 1] = order[j]
			j -= 1
		order[j + 1] = key
		s += 1

	var id2: PackedStringArray = PackedStringArray()
	var utf2: Array[PackedByteArray] = []
	var blk2: PackedInt64Array = PackedInt64Array()
	var knd2: PackedInt64Array = PackedInt64Array()
	var slt2: PackedInt64Array = PackedInt64Array()
	var sub2: PackedInt64Array = PackedInt64Array()
	var t: int = 0
	while t < n:
		var o: int = order[t]
		id2.append(_reg_id[o])
		utf2.append(_reg_id_utf8[o])
		blk2.append(_reg_block[o])
		knd2.append(_reg_kind[o])
		slt2.append(_reg_slot[o])
		sub2.append(_reg_subsys[o])
		t += 1
	_reg_id = id2
	_reg_id_utf8 = utf2
	_reg_block = blk2
	_reg_kind = knd2
	_reg_slot = slt2
	_reg_subsys = sub2

	var d: int = 1
	while d < n:
		if _reg_id[d] == _reg_id[d - 1]:
			JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, d - 1, d)
			return
		d += 1


## 两段 UTF-8 的字节序比较（短的是长的前缀时短的在前）。
## 步骤：LOAD
## 前置：无
## 后置：不改状态
## 不变量：INV-014（「按稳定 ID 字节序升序」是契约原文，不用语言自带的字符串序代替）
## 失败：无
static func _id_less(a: PackedByteArray, b: PackedByteArray) -> bool:
	var na: int = a.size()
	var nb: int = b.size()
	var m: int = na if na < nb else nb
	var i: int = 0
	while i < m:
		if a[i] != b[i]:
			return a[i] < b[i]
		i += 1
	return na < nb


## 逐条算「进不进哈希 / 进不进存档」。
## 步骤：LOAD
## 前置：_reg_id 已排序
## 后置：_reg_in_hash / _reg_in_save 与 _reg_id 等长
## 不变量：docs/10 §0.3 的命名空间表、docs/10 §11 的排除清单
## 失败：无
func _reg_flags() -> void:
	var n: int = _reg_id.size()
	_reg_in_hash.resize(n)
	_reg_in_save.resize(n)
	var e: int = 0
	while e < n:
		var id: String = _reg_id[e]
		_reg_in_hash[e] = 0 if (_has_prefix(id, HASH_EXCLUDED_PREFIXES)
				or HASH_EXCLUDED_IDS.has(id)) else 1
		_reg_in_save[e] = 0 if _has_prefix(id, SAVE_EXCLUDED_PREFIXES) else 1
		# SoA 的 ids[] 走 soa 段，不进 scalars/arrays 两段。
		if _reg_kind[e] == ENTRY_SOA_IDS:
			_reg_in_save[e] = 0
		e += 1


## id 是否以清单里的任一前缀开头。
## 步骤：LOAD
## 前置：无
## 后置：不改状态
## 不变量：docs/10 §0.3
## 失败：无
static func _has_prefix(id: String, prefixes: PackedStringArray) -> bool:
	var i: int = 0
	while i < prefixes.size():
		if id.begins_with(prefixes[i]):
			return true
		i += 1
	return false

# ── 条目读写分派 ───────────────────────────────────────────────────────────

## 读一个标量条目。
## 步骤：哈希 / 存档 / 深拷贝
## 前置：e 在注册表范围内且该条目是标量
## 后置：不改状态
## 不变量：INV-136
## 失败：块越界 → 返回 0
func _entry_scalar(e: int) -> int:
	var bi: int = _reg_block[e]
	var slot: int = _reg_slot[e]
	if bi == SELF_BLOCK:
		return _self_scalar(slot)
	var b: RefCounted = _blocks[bi]
	if _reg_kind[e] == ENTRY_STATE_SCALAR:
		return b.state_scalar(slot)
	return b.flow_scalar(slot)


## 读一个数组条目（返回块内数组的引用，调用方不得写）。
## 步骤：哈希 / 存档 / 深拷贝
## 前置：e 在注册表范围内且该条目是数组
## 后置：不改状态
## 不变量：INV-136
## 失败：块越界 → 返回空数组
func _entry_array(e: int) -> PackedInt64Array:
	var bi: int = _reg_block[e]
	var slot: int = _reg_slot[e]
	if bi == SELF_BLOCK:
		return PackedInt64Array()
	var b: RefCounted = _blocks[bi]
	if _reg_kind[e] == ENTRY_STATE_ARRAY:
		return b.state_array(slot)
	return b.flow_array(slot)


## 写一个标量条目（仅 LOAD / MIG / 深拷贝）。
## 步骤：读档 / 深拷贝
## 前置：e 在注册表范围内且该条目是标量
## 后置：写入；写不进去的情形由调用方的读回比对发现
## 不变量：INV-132（不做尽力修复）
## 失败：块没有 set_flow_scalar() → 不写，由读回比对判 SAVE_CORRUPT
func _entry_set_scalar(e: int, v: int) -> void:
	var bi: int = _reg_block[e]
	var slot: int = _reg_slot[e]
	if bi == SELF_BLOCK:
		_self_set_scalar(slot, v)
		return
	var b: RefCounted = _blocks[bi]
	if _reg_kind[e] == ENTRY_STATE_SCALAR:
		b.set_state_scalar(slot, v)
		return
	# 流量标量的写入口尚未进 docs/17 §1.6 的状态块协议（见本波返回的 interface_requests）。
	# 有就用；没有就不写，交给读回比对去暴露 —— 绝不假装写成功。
	if b.has_method("set_flow_scalar"):
		b.call("set_flow_scalar", slot, v)


## 写一个数组条目（仅 LOAD / MIG / 深拷贝）。
## 步骤：读档 / 深拷贝
## 前置：e 在注册表范围内且该条目是数组
## 后置：写入；写不进去的情形由调用方的读回比对发现
## 不变量：INV-132
## 失败：块没有 set_flow_array() → 不写，由读回比对判 SAVE_CORRUPT
func _entry_set_array(e: int, v: PackedInt64Array) -> void:
	var bi: int = _reg_block[e]
	var slot: int = _reg_slot[e]
	if bi == SELF_BLOCK:
		return
	var b: RefCounted = _blocks[bi]
	if _reg_kind[e] == ENTRY_STATE_ARRAY:
		b.set_state_array(slot, v)
		return
	if b.has_method("set_flow_array"):
		b.call("set_flow_array", slot, v)


## 本对象自己的整数状态标量，下标 == SELF_STATE_SCALAR_IDS 的下标。
## 步骤：哈希 / 存档 / 深拷贝
## 前置：slot ∈ [0, SELF_STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func _self_scalar(slot: int) -> int:
	if slot == 0:
		return schema_version
	if slot == 1:
		return param_set_version
	if slot == 2:
		return 1 if replay_unreliable else 0
	if slot == 3:
		return command_seq
	if slot == 4:
		return entity_seq
	if slot == 5:
		return q
	if slot == 6:
		return horizon_q
	if slot == 7:
		return phase
	if slot == 8:
		return mode
	if slot == 9:
		return start_year
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, slot, SELF_STATE_SCALAR_IDS.size())
	return 0


## 写本对象自己的整数状态标量（仅 LOAD / MIG / 深拷贝）。
## 步骤：读档 / 深拷贝
## 前置：slot ∈ [0, SELF_STATE_SCALAR_IDS.size())
## 后置：对应字段被写
## 不变量：INV-136
## 失败：越界 → INDEX_OUT_OF_RANGE
func _self_set_scalar(slot: int, v: int) -> void:
	if slot == 0:
		schema_version = v
	elif slot == 1:
		param_set_version = v
	elif slot == 2:
		replay_unreliable = v != 0
	elif slot == 3:
		command_seq = v
	elif slot == 4:
		entity_seq = v
	elif slot == 5:
		q = v
	elif slot == 6:
		horizon_q = v
	elif slot == 7:
		phase = v
	elif slot == 8:
		mode = v
	elif slot == 9:
		start_year = v
	else:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, slot,
				SELF_STATE_SCALAR_IDS.size())


## 本对象自己的字符串状态标量，下标 == SELF_STRING_IDS 的下标。
## 步骤：存档 / 深拷贝
## 前置：slot ∈ [0, SELF_STRING_IDS.size())
## 后置：不改状态
## 不变量：INV-131
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空串
func _self_string(slot: int) -> String:
	if slot == 0:
		return build_id
	if slot == 1:
		return content_hash
	if slot == 2:
		return scenario_id
	if slot == 3:
		return state_hash_prev
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, slot, SELF_STRING_IDS.size())
	return ""


## 写本对象自己的字符串状态标量（仅 LOAD / MIG）。
## 步骤：读档
## 前置：slot ∈ [0, SELF_STRING_IDS.size())
## 后置：对应字段被写
## 不变量：INV-131
## 失败：越界 → INDEX_OUT_OF_RANGE
func _self_set_string(slot: int, v: String) -> void:
	if slot == 0:
		build_id = v
	elif slot == 1:
		content_hash = v
	elif slot == 2:
		scenario_id = v
	elif slot == 3:
		state_hash_prev = v
	else:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, slot, SELF_STRING_IDS.size())

# ── SoA 的 ids[]（docs/11 §6.4 的 soa 段） ─────────────────────────────────

## 某个 SoA 的 ids[]。
## 步骤：哈希 / 存档 / 深拷贝
## 前置：k ∈ [0, SOA_NAMES.size())
## 后置：不改状态
## 不变量：INV-010（SoA 行 ID 来自 entity_seq）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空数组
func _soa_ids(k: int) -> PackedStringArray:
	if k == 0:
		return bonds.id
	if k == 1:
		return projects.id
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, k, SOA_NAMES.size())
	return PackedStringArray()


## 某个 SoA 的有效行数。
## 步骤：哈希 / 存档
## 前置：k ∈ [0, SOA_NAMES.size())
## 后置：不改状态
## 不变量：INV-010
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func _soa_count(k: int) -> int:
	if k == 0:
		return bonds.count
	if k == 1:
		return projects.count
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, k, SOA_NAMES.size())
	return 0


## 写某个 SoA 的 ids[]（仅 LOAD / MIG / 深拷贝）。
## 步骤：读档 / 深拷贝
## 前置：k ∈ [0, SOA_NAMES.size())
## 后置：对应 SoA 的 id 数组被整体替换
## 不变量：INV-010、INV-131
## 失败：越界 → INDEX_OUT_OF_RANGE
func _soa_set_ids(k: int, v: PackedStringArray) -> void:
	# 存档只写前 count 个 ID（哈希同口径），读回的数组因此只有 count 长；而立项 / 发债按 count 下标写新 ID，
	# 读档后第一次立项即越界（界面子代理报告、tools/diag_save_launch.gd 复现）。补齐到该 SoA 的已分配容量：
	# 补出来的空串在 count 之外，不进哈希也不进存档。
	var ids: PackedStringArray = v.duplicate()
	if k == 0:
		if ids.size() < bonds.status.size():
			ids.resize(bonds.status.size())
		bonds.id = ids
	elif k == 1:
		if ids.size() < projects.status.size():
			ids.resize(projects.status.size())
		projects.id = ids
	else:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, k, SOA_NAMES.size())

# ── 存档标量的整数编码 ─────────────────────────────────────────────────────

## 把一个 int64 写成 JSON 能无损承载的形态。
## 步骤：存档
## 前置：无
## 后置：|v| <= 2^53 时原样返回 int，否则返回十进制字符串
## 不变量：INV-132（读档复算哈希必须逐位相同，不许有精度损失）
## 失败：无
static func _json_int(v: int) -> Variant:
	if v > JSON_SAFE_INT_MAX or v < -JSON_SAFE_INT_MAX:
		return str(v)
	return v


## 从存档取一个整数，两种形态都认（int 与十进制字符串）。
## 步骤：读档
## 前置：无
## 后置：不改状态
## 不变量：INV-001（状态里不许有 float，读档是唯一可能混进来的入口）
## 失败：遇 float → Fault.FLOAT_IN_STATE 返回 0（随后的读回比对会判 SAVE_CORRUPT）
static func _variant_to_int(x: Variant) -> int:
	var t: int = typeof(x)
	if t == TYPE_INT:
		return int(x)
	if t == TYPE_STRING or t == TYPE_STRING_NAME:
		return String(x).to_int()
	if t == TYPE_FLOAT:
		JWResult.raise_fault(JWResult.Fault.FLOAT_IN_STATE, 0, 0)
		return 0
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, t, TYPE_INT)
	return 0

# ── 注册表的只读视图（测试与 systems/ 用；结算期不调用） ───────────────────

## 注册表条目数。
## 步骤：测试 / 诊断
## 前置：无
## 后置：不改状态
## 不变量：INV-014
## 失败：无
func registry_size() -> int:
	return _reg_id.size()


## 第 e 条的稳定 ID。
## 步骤：测试 / 诊断 / 故障包
## 前置：e ∈ [0, registry_size())
## 后置：不改状态
## 不变量：INV-014
## 失败：越界 → INDEX_OUT_OF_RANGE 返回空串
func registry_id(e: int) -> String:
	if e < 0 or e >= _reg_id.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, e, _reg_id.size())
		return ""
	return _reg_id[e]


## 第 e 条是否进 state_hash。
## 步骤：测试（哈希覆盖率锁定）
## 前置：e ∈ [0, registry_size())
## 后置：不改状态
## 不变量：INV-014（排除清单本身被测试锁定）
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 false
func registry_in_hash(e: int) -> bool:
	if e < 0 or e >= _reg_in_hash.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, e, _reg_in_hash.size())
		return false
	return _reg_in_hash[e] == 1


## 第 e 条是否进存档。
## 步骤：测试
## 前置：e ∈ [0, registry_size())
## 后置：不改状态
## 不变量：INV-131
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 false
func registry_in_save(e: int) -> bool:
	if e < 0 or e >= _reg_in_save.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, e, _reg_in_save.size())
		return false
	return _reg_in_save[e] == 1


## 第 e 条数组条目的**副本**（Presentation 的 StateView 与故障包用；结算期不调用）。
##
## 骨架之外新增的只读口，签名只增不改，不改任何状态。
## 为什么必须有：docs/17 §4.33 的 `StateView.array_copy(array_id_code)` 要「按 §1.6 的状态块
## 注册表取数组并 duplicate() 后返回」，而注册表的条目读取 `_entry_array` 是本类私有的。
## 没有它，应用层只能去直接摸各个域类的公开成员——那正好绕开了「UI 只经 StateView 读状态」。
## 步骤：任意（冷路径）
## 前置：e ∈ [0, registry_size()) 且该条目是数组类
## 后置：不改状态；调用方拿到的是副本，写它不影响 SimCore
## 不变量：计划书 §12（界面层不得直接修改状态）
## 失败：越界或非数组条目 → 返回空数组（不登记故障：未知 array_id_code 按契约返回空数组）
func registry_array_copy(e: int) -> PackedInt64Array:
	if e < 0 or e >= _reg_kind.size():
		return PackedInt64Array()
	var kind: int = _reg_kind[e]
	if kind != ENTRY_STATE_ARRAY and kind != ENTRY_FLOW_ARRAY:
		return PackedInt64Array()
	return _entry_array(e).duplicate()


## 第 e 条所属子系统。
## 步骤：测试 / WriteGuard
## 前置：e ∈ [0, registry_size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 -1
func registry_subsys(e: int) -> int:
	if e < 0 or e >= _reg_subsys.size():
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, e, _reg_subsys.size())
		return -1
	return _reg_subsys[e]
