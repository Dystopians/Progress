## 单位常量、维度常量与全部枚举。没有任何逻辑，没有任何状态。
##
## 所有人都依赖它，所以它不能依赖任何人（依赖秩 0，见 docs/17 §3.2）。
## 本文件的每一个数值都是契约的一部分：枚举值进日志与存档，维度常量定死稠密下标布局，
## 任何重排都是 schema 破坏性变更，必须升 save.schema_version 并写迁移函数（INV-136）。
class_name JWUnits
extends RefCounted

# ── 单位与标度（docs/10 §0.1 / docs/17 §4.1） ────────────────────────────────

## 1 U = 1 000 000 μU
const U_SCALE: int = 1_000_000_000
## 1 Q_s = 1 000 000 μQ_s
const Q_SCALE: int = 1_000_000
## 比率基数（百万分率）
const PPM: int = 1_000_000
## 基年价格（μU/Q_s），content.price.base_uu_per_qs 的唯一合法值（INV-148）
const BASE_PRICE: int = 1_000_000_000
## 汇率恒定（INV-105），任何写入即 FAULT
const FX_RATE_PPM: int = 1_000_000
## 基年全年名义 GDP（INV-118 的目标值）
const BASE_YEAR_GDP_UU: int = 100_000_000_000
## 金额上限（INV-007）
const AMOUNT_MAX: int = 4_000_000_000_000_000
## 数量上限（INV-007）
const QTY_MAX: int = 1_000_000_000_000
## 价格绝对下界（INV-066）
const PRICE_MIN: int = 400_000_000
## 价格绝对上界（INV-066）
const PRICE_MAX: int = 2_500_000_000
## 溢出守卫用
const INT64_MAX: int = 9_223_372_036_854_775_807
## 「该约束不适用」的哨兵（docs/12 §5.3，INV-044）；其值恒等于 QTY_MAX
const SENTINEL: int = QTY_MAX

# ── 维度常量（docs/17 §2.1，稠密下标布局，重排即破坏性变更） ────────────────

## region: 0 beiyuan 1 zhongzhou 2 haijia 3 xiling
const R: int = 4
## sector: 0 agri 1 manu 2 energy 3 services
const S: int = 4
## age: 0 minor 1 working 2 elder
const A: int = 3
## skill: 0 low 1 mid 2 high
const K: int = 3
## R * S
const CELL: int = 16
## R * A * K
const GROUP: int = 36
## 公共服务单元数，== R
const PUBSERV: int = 4
## S * S
const IO_N: int = 16
## CELL * S
const INV_N: int = 64
## CELL * K
const EMP_N: int = 48
## R * R
const OD_N: int = 16
## GROUP * 5（4 部门 + pubserv）
const GROUP_EMP_N: int = 180
## GROUP * SERVICE_KIND
const GROUP_SVC_N: int = 108
## GROUP * S
const GROUP_PROD_N: int = 144
## 结业队列槽位数
const EDU_SLOT: int = 8
## GROUP * EDU_SLOT
const EDU_N: int = 288
## PUBSERV * K
const PUBSERV_EMP_N: int = 12
## PUBSERV * SERVICE_KIND
const PUBSERV_QUEUE_N: int = 12
## 0 health 1 education 2 utility
const SERVICE_KIND: int = 3
const POLICY_N: int = 12
## POLICY_N * 4
const POLICY_PARAM_N: int = 48
const EVENT_N: int = 12
const SHOCK_N: int = 3
## 0 agri_coop 1 business 2 labor_public
const BLOC_N: int = 3
## BLOC_N * POLICY_N
const STANCE_N: int = 36
## GROUP * BLOC_N
const AFFIL_N: int = 108
const RNG_STREAM_N: int = 6
## 支付优先级 8 档
const PAY_LINE_N: int = 8
## 0 居民 1 公共服务 2 政府采购 3 企业投入 4 出口
const BUYER_CLASS_N: int = 6
## S * BUYER_CLASS_N
const MARKET_N: int = 24
## R * SERVICE_KIND
const OPEX_N: int = 12
const QUANTILE_N: int = 5
const AGENT_N: int = 60
const ACCOUNT_CODE_N: int = 15
## AGENT_N * ACCOUNT_CODE_N
const ACCOUNT_N: int = 900
## 债券 SoA 初始容量（param.bond_batch_cap 的编译期上限）
const BOND_CAP0: int = 512
## 项目 SoA 初始容量
const PROJECT_CAP0: int = 64
## 稀疏迁移流每季上限行数
const MIGRATION_CAP: int = 256
## param.log_capacity_rows 的初值
const LOG_CAP0: int = 8192

# ── 枚举（全部 int，值即稠密下标，不得重排） ────────────────────────────────

enum Region { BEIYUAN = 0, ZHONGZHOU = 1, HAIJIA = 2, XILING = 3 }
enum Sector { AGRI = 0, MANU = 1, ENERGY = 2, SERVICES = 3 }
enum Age { MINOR = 0, WORKING = 1, ELDER = 2 }
enum Skill { LOW = 0, MID = 1, HIGH = 2 }
enum ServiceKind { HEALTH = 0, EDUCATION = 1, UTILITY = 2 }
## 剧本模式（R-SCENARIO-01）：0 单届（旧 40 季现代版）1 战役（四百年）
enum Mode { TERM = 0, CAMPAIGN = 1 }
## 战役剧本的季数上限（R-CLOCK-01：1600—2000 年 = 1600 季）
const HORIZON_Q_MAX: int = 1600
enum Phase { IDLE = 0, S01 = 1, S02 = 2, S03 = 3, S04 = 4, S05 = 5, S06 = 6, S07 = 7, S08 = 8 }
enum Binding { PLAN = 0, CAPACITY = 1, LABOR = 2, ENERGY = 3, MATERIALS = 4 }
# R-INVEST-01：FIRM_CAPITAL 排在出口之后——资本品购买是最可推迟的需求，短缺时最后满足。
enum BuyerClass { HOUSEHOLD = 0, PUBSERV = 1, GOV_PROCUREMENT = 2, FIRM_INPUT = 3, EXPORT = 4,
		FIRM_CAPITAL = 5 }
enum PayLine { DEBT_SERVICE = 0, PUBLIC_WAGES = 1, STATUTORY_TRANSFERS = 2, SERVICE_OPEX = 3,
		PROJECT_CONTRACTS = 4, PROCUREMENT = 5, SUBSIDIES = 6, DISCRETIONARY = 7 }
enum RngStream { SHOCK = 0, EVENT = 1, DEMOGRAPHY = 2, MARKET = 3, POLITICS = 4, RESERVED = 5 }
enum Rationing { NONE = 0, PRIORITY = 1, PROPORTIONAL = 2 }
enum ProjectStatus { PLANNED = 0, IN_PROGRESS = 1, SUSPENDED = 2, COMPLETED = 3,
		COMMISSIONED = 4, CANCELLED = 5 }
## DEFERRED（R-DEFER-01）：玩家命令 6 的合同延期；只有它不在 S02 自动复工，到 defer_until_q 才复工。
enum SuspendReason { NONE = 0, FINANCING = 1, DELIVERY = 2, CONGESTION = 3, FUEL = 4, NO_DEMAND = 5,
		DEFERRED = 6 }
enum BlockedReason { NONE = 0, AUTHORITY = 1, BUDGET = 2, COOLDOWN = 3, PRECONDITION = 4,
		QUEUE = 5, EXITED = 6 }
enum BondStatus { ACTIVE = 0, MATURED = 1, DEFAULTED = 2, RESTRUCTURED = 3, WRITTEN_OFF = 4 }
enum Amortization { BULLET = 0, LEVEL_PRINCIPAL = 1 }
enum Holder { INVPOOL = 0, ROW = 1 }
enum MandateGoal { INDUSTRY = 0, LIVELIHOOD = 1, FISCAL = 2 }
enum MandateStatus { OK = 0, AT_RISK = 1, LOST = 2 }
enum Termination { NONE = 0, HORIZON = 1, LOST_ELECTION = 2, LOST_CONFIDENCE = 3,
		FISCAL_RESTRUCTURING_FAILED = 4 }
enum ExplainKind { ACCOUNTED = 0, INFERRED = 1, PROJECTED = 2 }
enum Bloc { AGRI_COOP = 0, BUSINESS = 1, LABOR_PUBLIC = 2 }

## 账本交易类型码，逐字对应 docs/11 §5.3 的 28 项，值不得改（进日志、进存档）
enum Kind { WAGE_PAYMENT = 1, PUBLIC_WAGE_PAYMENT = 2, HOUSEHOLD_CONSUMPTION = 3,
		GOV_PROCUREMENT = 4, INTERMEDIATE_PURCHASE = 5, INVENTORY_CHANGE = 6,
		CAPITAL_PURCHASE = 7, EXPORT = 8, IMPORT = 9, INCOME_TAX = 10, PROFIT_TAX = 11,
		SUBSIDY = 12, TRANSFER = 13, HOUSEHOLD_SUPPORT = 14, BOND_ISSUE = 15,
		BOND_PRINCIPAL = 16, BOND_INTEREST = 17, PROPERTY_INCOME = 18, PROJECT_PAYMENT = 19,
		SERVICE_OPEX = 20, DEPRECIATION = 21, OPERATING_SURPLUS = 22, PRICE_VARIANCE = 23,
		OPENING_BALANCE = 24, MIGRATION_COST = 25, POLICY_TOGGLE_COST = 26,
		CANCEL_PENALTY = 27, WRITEOFF = 28,
		# 第三轮裁定新增（docs/18）：三口径全 none。
		# ASSET_RECLASS —— 同一主体内的资产结转（在建工程 → 资本，R-ASSET-01）；
		# DEPOSIT_PLACE / DEPOSIT_WITHDRAW —— 居民存取款（R-DEPOSIT-01，此前误用发债/还本类型）。
		ASSET_RECLASS = 29, DEPOSIT_PLACE = 30, DEPOSIT_WITHDRAW = 31,
		# 第四轮（R-FEE-01）：公共服务收费，居民 → 政府，三口径全 none（再分配类，同税）。
		PUBLIC_FEE = 32 }
enum ProdClass { NONE = 0, SALE_FINAL = 1, SALE_INTERMEDIATE = 2, INV_CHANGE = 3, VA_NONMARKET = 4 }
enum ExpClass { NONE = 0, C = 1, G = 2, I = 3, DINV = 4, X = 5, M = 6 }
enum IncClass { NONE = 0, COMPENSATION = 1, GROSS_OPERATING_SURPLUS = 2,
		CONSUMPTION_OF_FIXED_CAPITAL = 3 }

## kind 数量上界（下标 0 为占位，不使用）
const KIND_N: int = 33

# ── 子系统（subsystem_hash 与 WriteGuard 的粒度，docs/10 §11 的 15 个） ─────

const SUBSYS_META: int = 0
const SUBSYS_TIME: int = 1
const SUBSYS_GOV: int = 2
const SUBSYS_BOND: int = 3
const SUBSYS_CELL: int = 4
const SUBSYS_PUBSERV: int = 5
const SUBSYS_GROUP: int = 6
const SUBSYS_REGION: int = 7
const SUBSYS_PROJECT: int = 8
const SUBSYS_POLICY: int = 9
const SUBSYS_POLITICS: int = 10
const SUBSYS_WORLD: int = 11
const SUBSYS_PRICE: int = 12
const SUBSYS_MARKET: int = 13
const SUBSYS_RNG: int = 14
const SUBSYS_N: int = 15

# ── 数值参数 param.* 的运行期下标（docs/17 §2.6） ──────────────────────────
#
# 枚举名 == 参数卡 ID 去掉 `param.` 前缀后大写；顺序 == 参数卡 ID 的字典序。
# 清单来自 content/parameters/registry.json 的 contract_min_set（72 项）；
# param.rng_salt 不进本数组（它是 content.rng.salt[6]，由 JWRngStreams 持有）。
# 新增参数只能追加在末尾。

enum Param {
	AMOUNT_MAX_UU = 0, BLOC_CARE_GAIN_PPM = 1, BLOC_ORG_INERTIA_PPM = 2,
	BLOC_RESOURCE_REF_UU = 3, BLOC_W_RESOURCE_PPM = 4, BLOC_W_SIZE_PPM = 5,
	BOND_BATCH_CAP = 6, COMMITMENT_HORIZON_Q = 7, CONSTRUCTION_SHARE_CAP_PPM = 8,
	COUPON_MAX_PPM = 9, COUPON_MIN_PPM = 10, DEFAULT_GRACE_Q = 11,
	DEMAND_SMOOTH_PPM = 12, DISSAVE_PPM = 13, EDU_PIPELINE_SLOTS = 14,
	EMISSION_DECAY_PPM = 15, ENGEL_WEIGHT_PPM_0 = 16, ENGEL_WEIGHT_PPM_1 = 17,
	ENGEL_WEIGHT_PPM_2 = 18, ENGEL_WEIGHT_PPM_3 = 19, ENV_EXPOSURE_GAIN_PPM = 20,
	EXPECTATION_INERTIA_PPM = 21, FIRING_FRICTION_PPM = 22, GAP_CAP_PPM = 23,
	HIRING_FRICTION_PPM = 24, HOUSEHOLD_BOND_APPETITE_PPM = 25, INVENTORY_TARGET_PPM = 26,
	INVEST_PROPENSITY_PPM = 27, LIVING_WEIGHT_HOUSE_PPM = 28, LIVING_WEIGHT_SERVICE_PPM = 29,
	LOG_CAPACITY_ROWS = 30, MAINTENANCE_BACKLOG_GAIN_PPM = 31, MAINTENANCE_BACKLOG_MAX_PPM = 32,
	MAINTENANCE_BACKLOG_RECOVER_PPM = 33, MARKET_RATE_BASE_PPM = 34, MARKET_RATE_SLOPE_PPM = 35,
	MIGRATION_MAX_SHARE_PPM = 36, MIGRATION_THRESHOLD_PPM = 37, MIGRATION_W_ENV_PPM = 38,
	MIGRATION_W_HOUSE_PPM = 39, MIGRATION_W_JOB_PPM = 40, MIGRATION_W_SERVICE_PPM = 41,
	MIGRATION_W_WAGE_PPM = 42, MPC_PPM = 43, NO_CONFIDENCE_Q = 44,
	OPEX_RECOVER_PPM = 45, OPEX_STARVE_DECAY_PPM = 46, PAYOUT_RATIO_PPM = 47,
	PERSONS_PER_HOUSING_UNIT = 48, POLICY_TOGGLE_COST_UU = 49, PRICE_CEIL_PPM = 50,
	PRICE_CLAMP_BUDGET_COUNT = 51, PRICE_COVER_GAIN_PPM = 52, PRICE_FLOOR_PPM = 53,
	PRICE_GAP_GAIN_PPM = 54, PRICE_STEP_MAX_PPM = 55, QTY_MAX_UQS = 56,
	RATE_SENSITIVITY_PPM = 57, STUDENT_TEACHER_RATIO = 58, SUPPORT_WEIGHT_PPM_0 = 59,
	SUPPORT_WEIGHT_PPM_1 = 60, SUPPORT_WEIGHT_PPM_2 = 61, TAX_BASE_RATE_PPM = 62,
	TAX_EVASION_SLOPE_PPM = 63, TAX_RECOVERY_PPM = 64, TRAINING_LAG_Q = 65,
	TRUST_DROP_PPM = 66, TRUST_RECOVER_PPM = 67, TRUST_STREAK_CAP_Q = 68,
	UU_TO_CONSTRUCTION_UQS_PPM = 69, WAGE_CASH_SHARE_PPM = 70, WAGE_CEIL_UU = 71,
	WAGE_FLOOR_UU = 72, WAGE_GAIN_PPM = 73, WAGE_STEP_MAX_PPM = 74,
	WRITE_GUARD_SAMPLE_Q = 75,
	# 第四轮追加（不插入字母序中间，避免既有下标整体后移）：
	PUBSERV_FEE_PPM = 76,
	PENSION_UU_PER_ELDER_Q = 77,
	RULE_ISSUE_TENOR_Q = 78,
	P09_ELIGIBLE_SECTOR_MASK = 79,
	# 第五轮（R-P11-01 / R-P12-01）：
	P11_STAFF_GAIN_FULL_PPM = 80,
	P11_SYSTEM_GAIN_FULL_PPM = 81,
	P11_TAX_CAPACITY_CEILING_PPM = 82,
	P11_REGION_BASE_SHARE_PPM_0 = 83, P11_REGION_BASE_SHARE_PPM_1 = 84,
	P11_REGION_BASE_SHARE_PPM_2 = 85, P11_REGION_BASE_SHARE_PPM_3 = 86,
	PROCUREMENT_DISCLOSURE_REF_UU = 87,
	PROC_TRANSPARENCY_GAIN_PPM = 88,
	PROC_TRANSPARENCY_LOAD_PPM = 89,
	PROC_TRANSPARENCY_APPEAL_LOAD_PPM = 90,
	PROC_TRANSPARENCY_RAMP_Q = 91,
	PROC_REVIEW_UU_PER_OPEX_PPM = 92,
	PROC_TRANSPARENCY_STEP_MAX_PPM = 93,
	# R-DEFER-01：项目延期的次数、累计季数上限与每季赔偿率（docs/31 Q-ADV-01）。
	MAX_DEFER_COUNT = 94,
	MAX_DEFER_QUARTERS = 95,
	DEFER_FEE_PPM_PER_Q = 96,
	# R-P11-02：征收能力的断供 / 退出衰减（policy_P11.json 交接记录）。
	P11_CAPACITY_FLOOR_PPM = 97,
	P11_CAPACITY_DECAY_PPM = 98,
	P11_CAPACITY_RECOVER_PPM = 99,
	# R-P12-02：采购透明撤回后的行政能力回落（policy_P12.json exit_rule decay_branch_zh）。
	PROC_TRANSPARENCY_DECAY_PPM = 100,
	PROC_TRANSPARENCY_DECAY_Q = 101,
}
const PARAM_N: int = 102

# ── 静态表 ─────────────────────────────────────────────────────────────────

## kind → 生产法分类（docs/11 §5.3）。下标 = Kind 值，长度 KIND_N（0 号占位不使用）。
## INV-114 的「按 kind 反查白名单」就是查这三张表；未登记的 kind 即 LEDGER_KIND_UNCLASSIFIED。
##
## docs/18 R-PUBSERV-01：kind 20 服务运行费、kind 26 政策开关成本不再付进 pubserv（它不持现金），
## 而是政府为公共服务向**市场 cell**购买的投入（开关成本付给中州服务 cell；运行费由 S05 市场的
## 公共服务买方类以 GOV_PROCUREMENT 成交）。收款方是市场生产者，这笔收款是它的销售——
## 生产法分类由 VA_NONMARKET(4) 改为 SALE_FINAL(1)，与同为「政府为 pubserv 购买投入」的
## kind 4 GOV_PROCUREMENT 一致；支出法仍为 G(2)（账本 G 类 == 公职工资 + 政府购买，即以成本计的
## G 扣除折旧），收入法 none。GDP 恒等式本身不读这两张表（G 取 Σ pubserv 产出、生产法取逐 cell
## 增加值），它们只服务于 INV-114 的覆盖性检验；数值后果由 S06 销售归集把 kind 26 计为卖方销售与
## 中州 pubserv 中间消耗来保证（生产法 +V、支出法 G +V）。
## kind 19 项目付款维持 (none, I, none)：国内收款方的销售由 S06 销售归集计入，外部收款方计进口（M）。
const KIND_PROD_CLASS: PackedInt64Array = [
	0,
	0, 4, 1, 1, 2, 3, 1, 1, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
	# R-MIGRATE-01：kind 25 迁移成本改为再分配（原 sale_final）。
	0, 0, 0, 0, 0, 1, 0, 0,
	0, 0, 0, 0,
]

## kind → 支出法分类（docs/11 §5.3）。下标 = Kind 值，长度 KIND_N。
const KIND_EXP_CLASS: PackedInt64Array = [
	0,
	0, 2, 1, 2, 0, 4, 3, 5, 6, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 3, 2,
	# R-MIGRATE-01：kind 25 迁移成本改为再分配（原 C）。
	0, 0, 0, 0, 0, 2, 0, 0,
	0, 0, 0, 0,
]

## kind → 收入法分类（docs/11 §5.3）。下标 = Kind 值，长度 KIND_N。
const KIND_INC_CLASS: PackedInt64Array = [
	0,
	1, 1, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	3, 2, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0,
]

## kind 是否属于「三口径全 none 的再分配类」（10..18, 27, 28），供 INV-029 / INV-113 静态断言。
## 下标 = Kind 值，长度 KIND_N；1 表示是再分配类。
const KIND_IS_REDISTRIBUTION: PackedInt64Array = [
	0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
	1, 1, 1, 1, 1, 1, 1, 1, 0, 0,
	# R-MIGRATE-01：kind 25 迁移成本是再分配类。
	0, 0, 0, 0, 1, 0, 1, 1,
	1, 1, 1, 1,
]

## 每步允许写入的子系统位掩码，下标 = Phase 值（docs/12 每步「可写子集」行的机器化）。
## JWTurnRunner._guard_begin/_guard_end 用它判 WRITE_OUT_OF_SCOPE。
## 位序 = SUBSYS_* 常量；bit(i) == 1 << i。
##
## 逐步来源（docs/12 各步「可写子集」行）：
##   IDLE 无写权；
##   S01  全部 flow.* 清零 + CELL/PUBSERV/REGION/PROJECT/WORLD 的产能转入 + RNG + META.state_hash_prev；
##   S02  META(entity_seq) GOV BOND GROUP(deposit) PROJECT POLICY POLITICS(next_budget_review_q) WORLD；
##   S03  CELL PUBSERV GROUP REGION MARKET RNG；
##   S04  GOV CELL PUBSERV GROUP PROJECT POLICY；
##   S05  GOV CELL PUBSERV GROUP REGION PROJECT WORLD MARKET RNG；
##   S06  GOV CELL PUBSERV GROUP REGION WORLD；
##   S07  GOV CELL PUBSERV GROUP REGION PROJECT POLITICS PRICE RNG；
##   S08  META TIME GROUP POLITICS PRICE RNG。
const WRITABLE_SUBSYS: PackedInt64Array = [
	0,
	# S01：流量整表清零是「全局唯一允许处」（docs/12 §1），必须能写**所有**带流量的子系统；
	# 原掩码漏了 BOND / POLICY / POLITICS，债券本季应付流量一经清零即被判越权（第 8 季抽样时暴露）。
	(1 << SUBSYS_META) | (1 << SUBSYS_GOV) | (1 << SUBSYS_CELL) | (1 << SUBSYS_PUBSERV)
		| (1 << SUBSYS_GROUP) | (1 << SUBSYS_REGION) | (1 << SUBSYS_PROJECT)
		| (1 << SUBSYS_WORLD) | (1 << SUBSYS_PRICE) | (1 << SUBSYS_MARKET) | (1 << SUBSYS_RNG)
		| (1 << SUBSYS_BOND) | (1 << SUBSYS_POLICY) | (1 << SUBSYS_POLITICS),
	(1 << SUBSYS_META) | (1 << SUBSYS_GOV) | (1 << SUBSYS_BOND) | (1 << SUBSYS_GROUP)
		| (1 << SUBSYS_PROJECT) | (1 << SUBSYS_POLICY) | (1 << SUBSYS_POLITICS)
		| (1 << SUBSYS_WORLD),
	(1 << SUBSYS_CELL) | (1 << SUBSYS_PUBSERV) | (1 << SUBSYS_GROUP) | (1 << SUBSYS_REGION)
		| (1 << SUBSYS_MARKET) | (1 << SUBSYS_RNG),
	# S04：R-FINANCE-01 在付款前融资，故与 S02 一样可写 META（entity_seq）、BOND（新批次）、WORLD（外部额度）。
	(1 << SUBSYS_GOV) | (1 << SUBSYS_CELL) | (1 << SUBSYS_PUBSERV) | (1 << SUBSYS_GROUP)
		| (1 << SUBSYS_PROJECT) | (1 << SUBSYS_POLICY)
		| (1 << SUBSYS_META) | (1 << SUBSYS_BOND) | (1 << SUBSYS_WORLD),
	(1 << SUBSYS_GOV) | (1 << SUBSYS_CELL) | (1 << SUBSYS_PUBSERV) | (1 << SUBSYS_GROUP)
		| (1 << SUBSYS_REGION) | (1 << SUBSYS_PROJECT) | (1 << SUBSYS_WORLD)
		| (1 << SUBSYS_MARKET) | (1 << SUBSYS_RNG),
	(1 << SUBSYS_GOV) | (1 << SUBSYS_CELL) | (1 << SUBSYS_PUBSERV) | (1 << SUBSYS_GROUP)
		| (1 << SUBSYS_REGION) | (1 << SUBSYS_WORLD),
	(1 << SUBSYS_GOV) | (1 << SUBSYS_CELL) | (1 << SUBSYS_PUBSERV) | (1 << SUBSYS_GROUP)
		| (1 << SUBSYS_REGION) | (1 << SUBSYS_PROJECT) | (1 << SUBSYS_POLITICS)
		| (1 << SUBSYS_PRICE) | (1 << SUBSYS_RNG),
	(1 << SUBSYS_META) | (1 << SUBSYS_TIME) | (1 << SUBSYS_GROUP) | (1 << SUBSYS_POLITICS)
		| (1 << SUBSYS_PRICE) | (1 << SUBSYS_RNG),
]

# ── 方法 ───────────────────────────────────────────────────────────────────

## 校验一个 kind 是否已在三张分类表中登记。
## 步骤：加载期一次 + 每次 post() 一次（O(1) 查表）
## 前置：kind ∈ [1, 28]
## 后置：返回 true 表示三张表都有登记（可为 NONE，但必须是显式登记的 NONE）
## 不变量：INV-114
## 失败：越界或未登记返回 false，调用方转 Fault.LEDGER_KIND_UNCLASSIFIED
static func kind_is_classified(kind: int) -> bool:
	# 三张表都是长度 KIND_N 的稠密表，下标 0 占位不使用：落在 [1, KIND_N-1] 即为「已登记」，
	# 表里的 0（NONE）是显式登记的 NONE（例如再分配类的三口径全 none），不是「缺登记」。
	if kind < 1 or kind >= KIND_N:
		return false
	# 表长自检：任何一张表被改短都会让「查表即登记」这个前提失效，此时一律判未登记，
	# 由调用方转 Fault.LEDGER_KIND_UNCLASSIFIED，而不是让越界访问去报一个无关的错。
	if KIND_PROD_CLASS.size() != KIND_N:
		return false
	if KIND_EXP_CLASS.size() != KIND_N:
		return false
	if KIND_INC_CLASS.size() != KIND_N:
		return false
	return true
