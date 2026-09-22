## 3 个集团的**成员规模与组织资源随经济结构动态推导**、对各政策的立场。
##
## **组织影响力（`org_power_ppm`）与票、行政能力是三套独立计算**（INV-125）。
## 依赖秩 8（docs/17 §3.2）：只允许引用 ≤7 的类。
## 子系统归属：`JWUnits.SUBSYS_POLITICS`。
##
## 结构性说明：`stance` 只影响改革可行性与议程，**不直接进 `support`**
## （「反对某政策不会自动等同于反对政府的一切」）。这一点由依赖方向保证：
## `JWPolitics.update_support()` 的形参表里没有本类的任何东西。
class_name JWInterestGroups
extends RefCounted

## 本块各状态数组所属子系统（与 STATE_ARRAY_IDS 等长），用于 subsystem_hash 与 WriteGuard。
const STATE_ARRAY_SUBSYS: PackedInt64Array = [
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS,
	JWUnits.SUBSYS_POLITICS, JWUnits.SUBSYS_POLITICS,
]

## 稳定 ID 注册表：下标 == 数组序号，内容是 docs/10 的稳定 ID 字符串。
## 只在加载与哈希时被读，结算期不触碰（无 String 进入热路径）。
## 注：`care_prev` 在 docs/10 尚无稳定 ID，按同族命名暂定（见 interface_requests）。
const STATE_ARRAY_IDS: PackedStringArray = [
	"state.bloc.org_power_ppm",
	"state.bloc.stance_ppm",
	"state.bloc.resource_uu",
	"state.bloc.care_prev",
]
const STATE_SCALAR_IDS: PackedStringArray = []
const FLOW_ARRAY_IDS: PackedStringArray = []
const FLOW_SCALAR_IDS: PackedStringArray = []

# ── 事件效果落点码（docs/11 §5.13 的事件可写白名单，下标即码，顺序不得改） ──
#
# 白名单六项的规范顺序（与 JWPolitics 共用同一套码，两边各自声明自己负责的两／四项，
# 避免秩 8 的本类去引用秩 6 的 JWPolitics——那会给 INV-125 的静态检查制造噪音）：
#   0 state.group.expectation_ppm      1 state.group.trust_ppm
#   2 state.group.support_ppm          3 state.bloc.org_power_ppm
#   4 state.bloc.stance_ppm            5 state.politics.admin_capacity_ppm
# 本类只接受 3 与 4，其余一律 WRITE_OUT_OF_SCOPE（INV-130）。
const EVT_ORG_POWER_PPM: int = 3
const EVT_STANCE_PPM: int = 4

## 立场的合法区间（docs/10 §8.3）。
const STANCE_MIN_PPM: int = -1_000_000
const STANCE_MAX_PPM: int = 1_000_000

## `state.bloc.org_power_ppm[]`，长 3，单位 ppm，写入者 S08。
## 注：docs/17 §4.25 的成员名 `org_power` 与同节冻结的 `func org_power(b)` 同名，GDScript 不允许；
## 成员改名为稳定 ID 同名的 `org_power_ppm`，冻结的方法签名保持原样（已登记为接口变更请求）。
var org_power_ppm: PackedInt64Array = PackedInt64Array()
## `state.bloc.stance_ppm[]`，长 36（BLOC_N × POLICY_N），单位 ppm ∈ [−1e6, 1e6]，写入者 S08。
var stance: PackedInt64Array = PackedInt64Array()
## `state.bloc.resource_uu[]`，长 3，单位 μU，写入者 S08。
## 首版恒定不变（politics_init `resource_update_rule = none_v1`，OQ-248）：
## 它是一个不在复式账本里的类货币数字，任何「每季按经营规模计提」都等于表外造钱。
var resource: PackedInt64Array = PackedInt64Array()
## 各集团「关心指标」的上季值，长 3，写入者 S08。
var care_prev: PackedInt64Array = PackedInt64Array()

# ── 改革域位序（`veto_domain_mask` 的位序 == 这里的下标） ──────────────────
#
# 顺序取自 politics_init `_note_reform_domains`，与 systems/content_loader.gd 的
# `REFORM_DOMAINS` 常量逐字一致；那边的注释已经写明「逐字取自本文件」，
# 所以这里把它从注释升格成具名常量，让两侧共用同一份可被编译器看见的事实。
const DOMAIN_TAX_LAW: int = 0
const DOMAIN_SOCIAL_PROGRAM: int = 1
const DOMAIN_CAPITAL_PROJECT: int = 2
const DOMAIN_LAND_REFORM: int = 3
const DOMAIN_PUBLIC_EMPLOYMENT: int = 4
## 改革域的个数（`veto_domain_mask` 的合法位数）。
const REFORM_DOMAIN_N: int = 5
## `policy_domain[p]` 的「尚未由 LOAD 写入」哨兵（见下方 OQ-252 的说明）。
const DOMAIN_UNMAPPED: int = -1

## `content.bloc.veto_domains[]`，长 3，位掩码，写入者 LOAD。
## 位序 == 改革域下标（politics_init `_note_reform_domains` 的顺序）：
## 0 tax_law、1 social_program、2 capital_project、3 land_reform、4 public_employment。
var veto_domain_mask: PackedInt64Array = PackedInt64Array()
## `content.bloc_affiliation_ppm[]`，长 108（GROUP × BLOC_N），单位 ppm（允许 Σ > 1e6），写入者 LOAD。
var affiliation_ppm: PackedInt64Array = PackedInt64Array()
## 政策 → 改革域下标，长 POLICY_N，类 C，写入者 LOAD（已登记为接口变更请求）。
##
## `has_veto(b, policy_idx)` 的冻结签名里没有 `JWPolicyDef`，而否决判定要问「这条政策属于哪个域」，
## 所以该映射必须由本类自己持有。它不是新规则，只是把 politics_init `_note_reform_domains`
## 与 `_note_authority_bits` 已经写定的 policy → domain 归属搬成运行期下标。
##
## **OQ-252（politics_init `_note_schema_deviation_zh` 已登记）**：docs/11 §5.12 的
## `PolicyDefinition` 里没有 `domain` 字段，politics_init 的 schema 里也没有这张映射表，
## 而 docs/12 §2.1 的否决判据写的正是「policy_def[p] 的 domain ∈ bloc.veto_domains[b]」——
## 这条判据**目前没有数据可读**。因此 `allocate()` 把本表填成 `DOMAIN_UNMAPPED` 而不是 0：
## 填 0 会让「归属未知」与「归属 tax_law」变成同一个值，于是持有 tax_law 否决权的工商业联盟
## 会对全部 12 条政策都拿到否决资格——那是一条凭默认值凭空长出来的规则。
## 未知归属不构成否决资格（`has_veto` 返回 false），直到 LOAD 真正写入这张表。
var policy_domain: PackedInt64Array = PackedInt64Array()


## S08 §8.3：集团反应（关心指标变化 → 立场；规模与资源 → 组织力）。
## 三个「关心指标」：agri_coop → 农业 cell 的 value_added_real 之和；
## business → 全部 cell 的 profit_pretax 之和；labor_public → 全国就业 + 公共服务可用率的人口加权。
## 步骤：S08 §8.3
## 前置：三项权重（inertia + w_size + w_resource）之和 == 1 000 000（加载期校验）
## 后置：stance ∈ [−1e6, 1e6]；org_power ∈ [0, 1e6]；care_prev 更新
## 不变量：INV-125（**本函数不引用 support_ppm 与 admin_capacity_ppm**，静态检查）、
##          INV-129（成员规模由群组人口映射得出，允许重叠，必须以「加权人数」口径展示）
## 失败：care_prev == 0 → 用 max(|care_prev|, 1)，不除零
func update_blocs(sectors: JWSectorModel, labor: JWLaborMarket, capital: JWCapital,
		pop: JWPopulation, newly_effective_mask: int, defs: JWPolicyDef,
		params: PackedInt64Array) -> int:
	if org_power_ppm.size() != JWUnits.BLOC_N or stance.size() != JWUnits.STANCE_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				org_power_ppm.size(), JWUnits.BLOC_N)
	if params.size() != JWUnits.PARAM_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				params.size(), JWUnits.PARAM_N)

	var care_gain_ppm: int = params[JWUnits.Param.BLOC_CARE_GAIN_PPM]
	var inertia_ppm: int = params[JWUnits.Param.BLOC_ORG_INERTIA_PPM]
	var w_size_ppm: int = params[JWUnits.Param.BLOC_W_SIZE_PPM]
	var w_resource_ppm: int = params[JWUnits.Param.BLOC_W_RESOURCE_PPM]
	var resource_ref_uu: int = params[JWUnits.Param.BLOC_RESOURCE_REF_UU]
	var nation_persons: int = pop.nation_population()

	var b: int = 0
	while b < JWUnits.BLOC_N:
		# ── 关心指标与它的季度变化率（docs/12 §8.3） ──
		var care_now: int = _care_metric(b, sectors, labor, capital, pop)
		var care_num: int = care_now - care_prev[b]
		# 除数取 max(|care_prev|, 1)：亏损为负时按绝对值做分母，care_prev == 0 时不除零。
		var care_den: int = JWMath.absi(care_prev[b])
		if care_den < 1:
			care_den = 1
		var care_delta_ppm: int = JWMath.clamp_i(
				JWMath.mul_div_floor(care_num, JWUnits.PPM, care_den),
				-JWUnits.PPM, JWUnits.PPM)
		var care_term_ppm: int = JWMath.mul_ppm(care_delta_ppm, care_gain_ppm)

		# ── 立场：本季新生效政策的一次性反应 + 关心指标变化（docs/12 §8.3） ──
		var p: int = 0
		while p < JWUnits.POLICY_N:
			var idx: int = JWIds.idx_stance(b, p)
			var reaction_ppm: int = 0
			if (newly_effective_mask >> p) & 1 == 1:
				reaction_ppm = defs.political_reaction_of(p, b)
			stance[idx] = JWMath.clamp_i(stance[idx] + reaction_ppm + care_term_ppm,
					STANCE_MIN_PPM, STANCE_MAX_PPM)
			p += 1

		# ── 组织力：惯性 + 成员规模份额 + 资源份额（三项权重之和 == 1e6，加载期校验） ──
		var members: int = membership_persons(pop, b)
		var pop_den: int = nation_persons
		if pop_den < 1:
			pop_den = 1
		var size_ppm: int = JWMath.clamp_i(
				JWMath.mul_div_floor(members, JWUnits.PPM, pop_den), 0, JWUnits.PPM)
		var res_den: int = resource_ref_uu
		if res_den < 1:
			res_den = 1
		var res_ppm: int = JWMath.clamp_i(
				JWMath.mul_div_floor(resource[b], JWUnits.PPM, res_den), 0, JWUnits.PPM)
		var org_prev_ppm: int = org_power_ppm[b]
		org_power_ppm[b] = JWMath.clamp_i(
				JWMath.mul_ppm(org_prev_ppm, inertia_ppm)
				+ JWMath.mul_ppm(size_ppm, w_size_ppm)
				+ JWMath.mul_ppm(res_ppm, w_resource_ppm),
				0, JWUnits.PPM)

		# care_prev 在本集团的全部读取之后才推进，下季的变化率才是对本季的比较。
		care_prev[b] = care_now
		b += 1
	return JWResult.OK


## 单个集团的「关心指标」当期值（docs/12 §8.3、politics_init 的 care_metric_formula）。
## 步骤：S08 §8.3
## 前置：b ∈ [0, BLOC_N)
## 后置：不改状态
## 不变量：INV-125（只读经济量，不读 support_ppm 与 admin_capacity_ppm）
## 失败：b 越界 → INDEX_OUT_OF_RANGE 返回 0
func _care_metric(b: int, sectors: JWSectorModel, labor: JWLaborMarket,
		capital: JWCapital, pop: JWPopulation) -> int:
	if b == JWUnits.Bloc.AGRI_COOP:
		# care[agri_coop] = Σ_r flow.cell.value_added_real_uu[cell.<r>.agri]
		var va: int = 0
		var c: int = 0
		while c < JWUnits.CELL:
			if JWIds.sector_of_cell(c) == JWUnits.Sector.AGRI:
				va += sectors.value_added_real(c)
			c += 1
		return va
	if b == JWUnits.Bloc.BUSINESS:
		# care[business] = Σ_c flow.cell.profit_pretax_uu[c]（亏损为负，按绝对值做分母）
		var profit: int = 0
		var c2: int = 0
		while c2 < JWUnits.CELL:
			profit += sectors.profit_pretax(c2)
			c2 += 1
		return profit
	if b == JWUnits.Bloc.LABOR_PUBLIC:
		# care[labor_public] = 全国就业人数 + 公共服务可用率的人口加权（两项都是「人」口径）
		var jobs: int = 0
		var c3: int = 0
		while c3 < JWUnits.CELL:
			var k: int = 0
			while k < JWUnits.K:
				jobs += labor.employment(c3, k)
				k += 1
			c3 += 1
		var r: int = 0
		while r < JWUnits.R:
			var k2: int = 0
			while k2 < JWUnits.K:
				jobs += labor.pubserv_employment(r, k2)
				k2 += 1
			jobs += JWMath.mul_ppm(pop.region_population(r), capital.availability(r))
			r += 1
		return jobs
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, b, JWUnits.BLOC_N)
	return 0


## 加权成员规模（derived.bloc.membership_persons，纯函数）。
## 步骤：S08、报告
## 前置：affiliation_ppm 已加载
## 后置：不改状态
## 不变量：INV-129（**是加权人数不是人头**，OQ-223；展示层必须标注）
## 失败：无
func membership_persons(pop: JWPopulation, b: int) -> int:
	if b < 0 or b >= JWUnits.BLOC_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, b, JWUnits.BLOC_N)
		return 0
	if affiliation_ppm.size() != JWUnits.AFFIL_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				affiliation_ppm.size(), JWUnits.AFFIL_N)
		return 0
	# Σ_g mul_ppm(population_persons[g], bloc_affiliation_ppm[g][b])：
	# 允许 Σ_b affiliation > 1e6（重叠成员），所以这里得到的是**加权人数**，不是人头。
	var total: int = 0
	var g: int = 0
	while g < JWUnits.GROUP:
		total += JWMath.mul_ppm(pop.population[g], affiliation_ppm[JWIds.idx_affil(g, b)])
		g += 1
	return total


## 立场读取（供 JWPolicyEngine 的资格链与 JWPolitics.check_authority 使用）。
## 注意：调用方向是**别人读本类**，本类不读别人（除 §4.25 的四个经济指标源）。
## 步骤：S02
## 前置：下标合法
## 后置：不改状态
## 不变量：INV-125
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func stance_of(b: int, p: int) -> int:
	if b < 0 or b >= JWUnits.BLOC_N or p < 0 or p >= JWUnits.POLICY_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, b, p)
		return 0
	if stance.size() != JWUnits.STANCE_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				stance.size(), JWUnits.STANCE_N)
		return 0
	return stance[JWIds.idx_stance(b, p)]


## 立场整表读取（供 JWPolitics.check_authority 以形参方式取用，避免 INV-125 的对象依赖）。
## 步骤：S02
## 前置：allocate() 已完成
## 后置：不改状态
## 不变量：INV-125
## 失败：无
func stance_array() -> PackedInt64Array:
	# PackedInt64Array 在 GDScript 里是值语义：返回的是一份拷贝，调用方写它也影响不到本类的状态。
	# 这正是 check_authority 只要形参、不要对象依赖的原因（docs/17 §4.25）。
	return stance


## 组织影响力读取（**与票、行政能力是三套独立计算**）。
## 步骤：S02、报告
## 前置：b ∈ [0, JWUnits.BLOC_N)
## 后置：不改状态
## 不变量：INV-125
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 0
func org_power(b: int) -> int:
	if b < 0 or b >= JWUnits.BLOC_N or org_power_ppm.size() != JWUnits.BLOC_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, b, JWUnits.BLOC_N)
		return 0
	return org_power_ppm[b]


## 该集团对该政策是否具备否决权（查 veto_domain_mask 的位）。
## 步骤：S02 §2.1
## 前置：b ∈ [0, JWUnits.BLOC_N)；policy_idx ∈ [0, JWUnits.POLICY_N)
## 后置：不改状态
## 不变量：INV-125、INV-099
## 失败：越界 → INDEX_OUT_OF_RANGE 返回 false
func has_veto(b: int, policy_idx: int) -> bool:
	if b < 0 or b >= JWUnits.BLOC_N or policy_idx < 0 or policy_idx >= JWUnits.POLICY_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, b, policy_idx)
		return false
	if veto_domain_mask.size() != JWUnits.BLOC_N or policy_domain.size() != JWUnits.POLICY_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
				veto_domain_mask.size(), policy_domain.size())
		return false
	var domain: int = policy_domain[policy_idx]
	if domain == DOMAIN_UNMAPPED:
		# OQ-252：这条政策的改革域归属在内容层还没有字段可读。未知归属不构成否决资格——
		# 这不是登记失败，而是「判据的输入尚未存在」；补上数据之前不得凭默认值放行否决。
		return false
	if domain < 0 or domain >= REFORM_DOMAIN_N:
		JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, domain, REFORM_DOMAIN_N)
		return false
	# 只回答「有没有否决资格」。立场阈值那一半在 JWPolitics.check_authority 里判
	# （politics_init `_note_veto_rule`：域命中 **且** stance < 阈值 才是否决）。
	return (veto_domain_mask[b] >> domain) & 1 == 1


## R-AUTHORITY-01：把「按域持有否决资格的集团」写成每条政策一个位掩码（位 b == 集团 b）。
## 步骤：S02 之前（JWTurnRunner 注入 JWPolicyEngine）
## 前置：out.size() == JWUnits.POLICY_N
## 后置：out[p] 的位 b == has_veto(b, p)
## 不变量：INV-125（只读域表，不读支持度）
## 失败：长度不符 → INDEX_OUT_OF_RANGE
func veto_masks_into(out: PackedInt64Array) -> int:
	if out.size() != JWUnits.POLICY_N:
		return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, out.size(), JWUnits.POLICY_N)
	for p: int in JWUnits.POLICY_N:
		var m: int = 0
		for b: int in JWUnits.BLOC_N:
			if has_veto(b, p):
				m = m | (1 << b)
		out[p] = m
	return JWResult.OK


## 事件效果落点（org_power_ppm 与 stance_ppm 两项）。
## 步骤：S08 §8.4
## 前置：target ∈ {org_power_ppm, stance_ppm}
## 后置：加 delta 后 clamp
## 不变量：INV-130
## 失败：target 不在白名单 → Fault.WRITE_OUT_OF_SCOPE
func apply_event_delta(target_code: int, scope_idx: int, delta_ppm: int) -> int:
	if target_code == EVT_ORG_POWER_PPM:
		if scope_idx < 0 or scope_idx >= JWUnits.BLOC_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					scope_idx, JWUnits.BLOC_N)
		org_power_ppm[scope_idx] = JWMath.clamp_i(org_power_ppm[scope_idx] + delta_ppm,
				0, JWUnits.PPM)
		return JWResult.OK
	if target_code == EVT_STANCE_PPM:
		# scope_idx 是已由事件引擎解析好的稠密立场下标 idx_stance(b, p)，
		# 本函数不做 id → 下标 的解析（结算期不碰 String）。
		if scope_idx < 0 or scope_idx >= JWUnits.STANCE_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					scope_idx, JWUnits.STANCE_N)
		stance[scope_idx] = JWMath.clamp_i(stance[scope_idx] + delta_ppm,
				STANCE_MIN_PPM, STANCE_MAX_PPM)
		return JWResult.OK
	# 白名单之外的一切落点（现金、库存、产能、人口）在这里被挡住：首版事件没有任何账本效应。
	return JWResult.raise_fault(JWResult.Fault.WRITE_OUT_OF_SCOPE, target_code, scope_idx)


## §1.6 状态块协议：LOAD 期一次性 resize 到 §2 的契约长度。
## 步骤：LOAD
## 前置：维度常量已确定
## 后置：org_power_ppm / resource / care_prev 长 BLOC_N；stance 长 STANCE_N；affiliation_ppm 长 AFFIL_N
## 不变量：docs/10 §0.6（加载期一次性 resize）
## 失败：无
func allocate() -> void:
	org_power_ppm.resize(JWUnits.BLOC_N)
	org_power_ppm.fill(0)
	stance.resize(JWUnits.STANCE_N)
	stance.fill(0)
	resource.resize(JWUnits.BLOC_N)
	resource.fill(0)
	care_prev.resize(JWUnits.BLOC_N)
	care_prev.fill(0)
	veto_domain_mask.resize(JWUnits.BLOC_N)
	veto_domain_mask.fill(0)
	affiliation_ppm.resize(JWUnits.AFFIL_N)
	affiliation_ppm.fill(0)
	policy_domain.resize(JWUnits.POLICY_N)
	# 不填 0：0 是 tax_law 的合法域下标，用它当「未写入」会凭空造出否决权（OQ-252，见成员注释）。
	policy_domain.fill(DOMAIN_UNMAPPED)


## §1.6 状态块协议：按下标只读取用状态数组（返回引用，调用方不得写）。
## 步骤：加载、哈希、存档
## 前置：i ∈ [0, STATE_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-136（下标顺序是 schema 的一部分）
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func state_array(i: int) -> PackedInt64Array:
	if i == 0:
		return org_power_ppm
	if i == 1:
		return stance
	if i == 2:
		return resource
	if i == 3:
		return care_prev
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：写入状态数组，**仅 LOAD / MIG**。
## 步骤：LOAD / MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd（静态检查）
## 后置：对应成员被整体替换，长度必须与契约一致
## 不变量：INV-136
## 失败：越界或长度不符 → 返回对应 Fault / Load 码
func set_state_array(i: int, v: PackedInt64Array) -> int:
	if i == 0:
		if v.size() != JWUnits.BLOC_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					v.size(), JWUnits.BLOC_N)
		org_power_ppm = v
		return JWResult.OK
	if i == 1:
		if v.size() != JWUnits.STANCE_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					v.size(), JWUnits.STANCE_N)
		stance = v
		return JWResult.OK
	if i == 2:
		if v.size() != JWUnits.BLOC_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					v.size(), JWUnits.BLOC_N)
		resource = v
		return JWResult.OK
	if i == 3:
		if v.size() != JWUnits.BLOC_N:
			return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE,
					v.size(), JWUnits.BLOC_N)
		care_prev = v
		return JWResult.OK
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_ARRAY_IDS.size())


## §1.6 状态块协议：按下标读取状态标量（本块无状态标量）。
## 步骤：加载、哈希、存档
## 前置：i ∈ [0, STATE_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func state_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, STATE_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：写入状态标量，**仅 LOAD / MIG**（本块无状态标量）。
## 步骤：LOAD / MIG
## 前置：调用点位于 systems/content_loader.gd 或 systems/saves.gd（静态检查）
## 后置：不改状态
## 不变量：INV-136
## 失败：越界 → 返回 Fault.INDEX_OUT_OF_RANGE
func set_state_scalar(i: int, v: int) -> int:
	return JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, v)


## §1.6 状态块协议：按下标只读取用流量数组（本块无流量）。
## 步骤：报告、哈希对账
## 前置：i ∈ [0, FLOW_ARRAY_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回空数组
func flow_array(i: int) -> PackedInt64Array:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_ARRAY_IDS.size())
	return PackedInt64Array()


## §1.6 状态块协议：按下标读取流量标量（本块无流量）。
## 步骤：报告、哈希对账
## 前置：i ∈ [0, FLOW_SCALAR_IDS.size())
## 后置：不改状态
## 不变量：INV-013
## 失败：越界 → JWResult.raise_fault(INDEX_OUT_OF_RANGE) 并返回 0
func flow_scalar(i: int) -> int:
	JWResult.raise_fault(JWResult.Fault.INDEX_OUT_OF_RANGE, i, FLOW_SCALAR_IDS.size())
	return 0


## §1.6 状态块协议：全部 FLOW_* 归零，**仅 S01**（本块无流量，是空实现）。
## 步骤：S01 §01.3
## 前置：调用点位于 systems/turn_runner.gd 的 _step_s01（静态检查）
## 后置：不改状态
## 不变量：INV-013
## 失败：无
func reset_flows() -> void:
	# 本块没有任何 FLOW_* 成员：集团量全是跨季状态（org_power / stance / resource / care_prev），
	# 清零它们等于每季把集团记忆抹掉。空实现是正确实现，不是遗漏。
	pass


## §1.6 状态块协议：S01 清零后的自检，非 0 即 FLOW_NOT_RESET（本块恒 0）。
## 步骤：S01 §01.3 末
## 前置：reset_flows() 刚被调用
## 后置：不改状态
## 不变量：INV-013
## 失败：无
func flow_abs_sum() -> int:
	return 0
