## 读模型：界面读取国家状态的唯一适配层（docs/20 IM-10、B-02）。
##
## 只经 JWGame 的只读视图取数（按 docs/10 稳定 ID），派生量优先取 JWGame.derived_snapshot() 的权威值。
## **本文件是界面层唯一允许对状态数值做聚合运算的地方**（求和、人口加权、按 docs/10 公式反算），
## 每个聚合都在注释里写明公式与出处；页面与组件只格式化、不运算。
## 这层本应属于 Application（docs/20 §17 读模型），受本轮文件范围所限放在 ui/core/，
## 待 Application 提供同名读模型后可一对一替换（已写入接口请求）。
##
## 常量（绑定码、项目状态、拒绝码）是 docs/10 / docs/12 的契约值；界面不引用 res://sim/ 脚本，
## 因此在此镜像登记，tests/ui 用 SimCore 的枚举逐一核对，漂移即测试失败。
class_name JwReadModel
extends RefCounted

const R: int = 4
const S: int = 4
const A: int = 3
const K: int = 3
const CELL: int = 16
const GROUP: int = 36
const POLICY_N: int = 12
const BLOC_N: int = 3
const U: int = 1_000_000_000
const PPM: int = 1_000_000

## 绑定码（docs/10 flow.cell.binding_code）。
const BIND_PLAN: int = 0
const BIND_CAPACITY: int = 1
const BIND_LABOR: int = 2
const BIND_ENERGY: int = 3
const BIND_MATERIALS: int = 4

## 项目状态（docs/10 state.project.status）。
const PS_PLANNED: int = 0
const PS_IN_PROGRESS: int = 1
const PS_SUSPENDED: int = 2
const PS_COMPLETED: int = 3
const PS_COMMISSIONED: int = 4
const PS_CANCELLED: int = 5
## 约束上界的「不适用」哨兵 == JWUnits.QTY_MAX（该约束对这个部门不适用，例如能源部门自身的供电约束）。
const BOUND_NA: int = 1_000_000_000_000
## JWUnits.SuspendReason.DEFERRED（R-DEFER-01：玩家命令 6 的合同延期）
const SUSPEND_DEFERRED: int = 6

## 年龄档。
const AGE_MINOR: int = 0
const AGE_WORKING: int = 1
const AGE_ELDER: int = 2

## 拒绝码（docs/12 E_*，写入 log.rejections；数值是契约）。
const RJ_RUN_TERMINATED: int = 1000
const RJ_PHASE_BUSY: int = 1001
const RJ_UNKNOWN_POLICY: int = 1002
const RJ_POLICY_COOLDOWN: int = 1003
const RJ_AUTHORITY: int = 1004
const RJ_SEATS_SHORT: int = 1005
const RJ_BLOC_VETO: int = 1006
const RJ_BUDGET_INSUFFICIENT: int = 1007
const RJ_NO_FUNDING: int = 1008
const RJ_CREDIT_LIMIT: int = 1009
const RJ_NO_SLOT: int = 1010
const RJ_PRECONDITION: int = 1011
const RJ_ALREADY_ENACTED: int = 1012
const RJ_NOT_FOUND: int = 1013
const RJ_DIRECT_STATE_WRITE: int = 1014
const RJ_PARAM_RANGE: int = 1015
const RJ_PRIORITY_INCOMPLETE: int = 1016
const RJ_OVERPAY: int = 1017
const RJ_COMMAND_ORDER: int = 1018

## 选举季（内部 q，docs/12 INV-127：第 16、32 季）。
const ELECTION_QS: PackedInt64Array = [15, 31]

const SCALAR_IDS: PackedStringArray = [
	"state.time.q", "state.time.horizon_q", "state.time.start_year", "state.meta.mode",
	"state.meta.run_terminated",
	"state.meta.termination_reason", "state.meta.command_seq",
	"state.gov.arrears_uu", "state.gov.committed_memo_uu", "state.gov.reserved_memo_uu",
	"state.gov.service_opex_committed_uu", "state.gov.tax_capacity_ppm",
	"state.gov.credit_limit_domestic_memo_uu", "state.gov.tax_receivable_uu",
	"state.bond.count", "state.project.count",
	"state.politics.admin_capacity_ppm", "state.politics.legal_authority_mask",
	"state.politics.lost_streak_q", "state.politics.mandate_goal", "state.politics.mandate_status",
	"state.politics.next_budget_review_q", "state.politics.next_election_q",
	"state.politics.review_fail_streak", "state.politics.review_pass_streak",
	"state.politics.review_receipts_accum_uu", "state.politics.review_outlays_accum_uu",
	"state.politics.seats_gov", "state.politics.seats_total", "state.politics.term_index",
	"state.world.credit_limit_uu", "state.world.credit_used_uu", "state.world.current_account_uu",
	"state.world.sovereign_rate_ppm_per_q",
	"flow.gov.interest_paid_uu", "flow.gov.new_borrowing_uu", "flow.gov.pay_procurement_uu",
	"flow.gov.pay_public_wages_uu", "flow.gov.primary_paid_uu", "flow.gov.principal_paid_uu",
	"flow.gov.receipts_income_tax_uu", "flow.gov.receipts_other_uu",
	"flow.gov.receipts_profit_tax_uu", "flow.gov.recognized_writeoffs_uu",
	"flow.gov.final_consumption_uu", "flow.gov.gross_capital_formation_uu",
	"flow.world.exports_uu", "flow.world.imports_uu", "flow.politics.budget_review_due",
	"flow.gov.procurement_budget_q_uu", "flow.gov.rollover_uu",
	# M2：研究、建筑、伙伴（R-RESEARCH-01 / R-METHOD-01 / R-TRADE-01）。
	"state.research.points_pool", "state.research.focus", "state.research.completed_mask",
	"content.tech.count", "content.research.enabled",
	"flow.research.points_gained",
	"state.building.count", "content.building.type_count", "content.method.count",
	"content.partner.count",
]

const ARRAY_IDS: PackedStringArray = [
	"account.balance",
	"state.bond.principal_outstanding_uu", "state.bond.principal_initial_uu",
	"state.bond.coupon_ppm_per_q", "state.bond.issue_q", "state.bond.maturity_q",
	"state.bond.holder", "state.bond.status", "state.bond.amort_schedule",
	"state.project.status", "state.project.policy_idx", "state.project.region_idx",
	"state.project.total_cost_uu", "state.project.paid_uu", "state.project.spend_plan_uu",
	"state.project.planned_quarters", "state.project.delivery_progress_ppm",
	"state.project.construction_progress_ppm", "state.project.capacity_effect_uqs_per_q",
	"state.project.opex_per_q_uu", "state.project.commissioned_q",
	"state.project.residual_value_uu", "state.project.cancel_penalty_uu",
	"state.project.suspension_reason", "state.project.queue_slot_held",
	"state.project.defer_count", "state.project.defer_quarters_total", "state.project.defer_until_q",
	"state.project.defer_fee_uu", "state.project.entity",
	"state.project.building_type", "state.project.building_owner", "state.project.building_method",
	"state.project.retrofit_stack",
	# M2：研究、建筑堆与内容表、伙伴。
	"state.research.status", "state.research.progress",
	"content.tech.cost", "content.tech.era_hint", "content.tech.prereq_mask",
	"state.building.cell", "state.building.type", "state.building.owner", "state.building.method",
	"state.building.level", "state.building.capacity_active_uqs_per_q",
	"state.building.capacity_pending_uqs_per_q", "state.building.capital_value_uu",
	"state.building.frozen_ppm", "state.building.entity",
	"content.building.sector", "content.building.unit_capacity_uqs", "content.building.cost_uu",
	"content.building.quarters", "content.building.opex_uu", "content.building.owners_mask",
	"content.method.building", "content.method.output_ppm", "content.method.retrofit_cost_uu",
	"content.method.retrofit_quarters", "content.method.retrofit_frozen_ppm",
	"state.partner.export_share_ppm", "state.partner.import_share_ppm",
	"state.partner.price_mult_ppm", "state.partner.relation_ppm", "state.partner.treaty_mask",
	"state.partner.balance_uu",
	"state.event.pending_until_q", "state.event.chosen_option", "content.event.choice_count",
	"state.policy.enabled", "state.policy.enacted_q", "state.policy.effective_from_q",
	"state.policy.cooldown_until_q", "state.policy.exit_pending_q", "state.policy.params_ppm",
	"state.policy.region_mask", "state.policy.toggle_count", "state.policy.budget_committed_uu",
	"state.policy.budget_spent_uu",
	"content.policy.kind", "content.policy.cost_one_off_uu", "content.policy.cost_per_quarter_uu",
	"content.policy.opex_per_q_uu", "content.policy.planned_quarters",
	"content.policy.param_min_ppm", "content.policy.param_max_ppm", "content.policy.param_default",
	"content.policy.lag_enact_to_effect_q", "content.policy.cooldown_q",
	"content.policy.toggle_cost_uu", "content.policy.authority_bit", "content.policy.min_seats_ppm",
	"content.policy.requires_bloc_mask", "content.policy.requires_budget_review",
	"content.policy.exit_compensation_ppm", "content.policy.political_reaction",
	"content.policy.effect_magnitude", "content.policy.commission_delay_q",
	"content.region.adjacency", "content.region.logistics_cost_ppm",
	"state.region.construction_slots_total", "state.region.grid_capacity_uqs_per_q",
	"state.region.grid_capacity_pending_uqs_per_q", "state.region.housing_capacity_units",
	"state.region.housing_stock_units", "state.region.housing_pending_units",
	"state.region.irrigation_index_ppm", "state.region.port_capacity_uqs_per_q",
	"state.region.env_exposure_ppm",
	"flow.region.electricity_demand_uqs", "flow.region.electricity_supply_uqs",
	"flow.region.construction_capacity_uqs", "flow.region.construction_used_uqs",
	"state.pubserv.availability_ppm", "state.pubserv.capacity_active_uqs_per_q",
	"state.event.fire_count",
	"state.pubserv.queue_persons", "state.pubserv.teachers_persons",
	"state.pubserv.health_staff_persons",
	"state.group.population_persons", "state.group.employed_persons",
	"state.group.participation_ppm", "state.group.living_index_ppm",
	"state.group.expectation_ppm", "state.group.trust_ppm", "state.group.support_ppm",
	"state.group.consumption_index_ppm", "state.group.service_access_ppm",
	"state.group.education_cohort_persons",
	"flow.group.wage_income_uu", "flow.group.property_income_uu",
	"flow.group.transfer_income_uu", "flow.group.income_tax_paid_uu",
	"flow.group.housing_cost_uu", "flow.group.consumption_uu",
	"flow.group.support_in_uu", "flow.group.support_out_uu", "flow.group.fees_paid_uu",
	"state.cell.capacity_active_uqs_per_q", "state.cell.employment_persons",
	"flow.cell.binding_code", "flow.cell.bound_plan_uqs", "flow.cell.bound_capacity_uqs",
	"flow.cell.bound_labor_uqs", "flow.cell.bound_energy_uqs", "flow.cell.bound_materials_uqs",
	"flow.cell.output_actual_uqs", "flow.cell.output_plan_uqs", "flow.cell.value_added_uu",
	"flow.cell.value_added_real_uu", "flow.cell.gross_output_uu", "flow.cell.wage_bill_uu",
	"flow.cell.unmet_demand_uqs",
	"state.bloc.org_power_ppm", "state.bloc.resource_uu", "state.bloc.stance_ppm",
	"state.world.shock_active", "state.world.shock_magnitude_ppm",
	"state.world.export_demand_ppm", "state.world.import_price_ppm",
	"state.world.delivery_capacity_uqs",
	"flow.gov.pay_opex_uu", "flow.gov.pay_project_uu", "flow.gov.pay_subsidies_uu",
	"flow.gov.pay_transfers_uu", "flow.gov.arrears_added_uu",
]

var game: JWGame = null
var view: JWGame.StateView = null
var _code: Dictionary = {}
var s: Dictionary = {}
var a: Dictionary = {}
var derived: Dictionary = {}
var rules: Dictionary = {}
var cmdlog: Dictionary = {}
var q: int = 0
var terminated: bool = false
var ledger_rows_n: int = 0


func bind(g: JWGame) -> void:
	game = g
	view = g.view() if g != null else null
	_code.clear()


func code(id: String) -> int:
	if _code.has(id):
		return int(_code[id])
	var c: int = view.code_of(id) if view != null else -1
	_code[id] = c
	return c


## 读取全部标量与数组（一次性，结算后与读档后各调一次）。
func refresh() -> void:
	if game == null:
		return
	view = game.view()
	s.clear()
	a.clear()
	for id: String in SCALAR_IDS:
		var c: int = code(id)
		s[id] = view.scalar(c, 0) if c >= 0 else 0
	for id2: String in ARRAY_IDS:
		var c2: int = code(id2)
		a[id2] = view.array_copy(c2) if c2 >= 0 else PackedInt64Array()
	q = view.q()
	# R-CLOCK-01：战役剧本按公历显示季度（「1623 年 春」）；旧剧本 start_year == 0，仍显示「第 N 季」。
	JwFormat.start_year = sc("state.time.start_year")
	terminated = view.run_terminated()
	derived = game.derived_snapshot() if game.has_method("derived_snapshot") else {}
	rules = game.rule_params() if game.has_method("rule_params") else {}
	cmdlog = game.command_log_copy() if game.has_method("command_log_copy") else {}


## M2：某项科技是否可研究（前置齐备且未完成）。界面据此决定「设为方向」可不可点。
func tech_available(t: int) -> bool:
	if t < 0 or t >= sc("content.tech.count"):
		return false
	var done: int = sc("state.research.completed_mask")
	if (done >> t) & 1 == 1:
		return false
	return at("content.tech.prereq_mask", t) & ~done == 0


## M2：本局的建筑堆行数。
func stack_count() -> int:
	return sc("state.building.count")


## M2：某个建筑堆的一行数据（界面用；产能已按方式与冻结折算由 SimCore 汇总，这里给原值与倍率分量）。
func stack_row(b: int) -> Dictionary:
	return {
		"b": b,
		"entity": at("state.building.entity", b),
		"cell": at("state.building.cell", b),
		"type": at("state.building.type", b),
		"owner": at("state.building.owner", b),
		"method": at("state.building.method", b),
		"level": at("state.building.level", b),
		"capacity": at("state.building.capacity_active_uqs_per_q", b),
		"pending": at("state.building.capacity_pending_uqs_per_q", b),
		"value": at("state.building.capital_value_uu", b),
		"frozen_ppm": at("state.building.frozen_ppm", b),
	}


## R-CAP-01：本季第 p 行项目的稳定实体号（命令参数用它，不用行号）。
func project_entity(p: int) -> int:
	return at("state.project.entity", p)


func sc(id: String) -> int:
	return int(s.get(id, 0))


func ar(id: String) -> PackedInt64Array:
	var v: Variant = a.get(id, PackedInt64Array())
	if v is PackedInt64Array:
		return v
	return PackedInt64Array()


func at(id: String, i: int) -> int:
	var arr: PackedInt64Array = ar(id)
	if i < 0 or i >= arr.size():
		return 0
	return arr[i]


func dv(id: String) -> int:
	var v: Variant = derived.get(id, 0)
	return int(v) if (v is int) else 0


func darr(id: String) -> PackedInt64Array:
	var v: Variant = derived.get(id, PackedInt64Array())
	if v is PackedInt64Array:
		return v
	return PackedInt64Array()


func rule(id: String, default_value: int = 0) -> int:
	var v: Variant = rules.get(id, default_value)
	return int(v) if (v is int) else default_value


## 本局是否已有过至少一次结算（q ≥ 1）。Q01 冷启动态以此判定（docs/20 §11.1）。
func settled() -> bool:
	return q >= 1


# ── 下标布局（docs/10 §0.5） ───────────────────────────────────────────────

static func idx_cell(r: int, sec: int) -> int:
	return r * S + sec


static func idx_group(r: int, age: int, sk: int) -> int:
	return r * (A * K) + age * K + sk


static func region_of_group(g: int) -> int:
	@warning_ignore("integer_division")
	var r: int = g / (A * K)
	return r


static func age_of_group(g: int) -> int:
	@warning_ignore("integer_division")
	var ag: int = (g % (A * K)) / K
	return ag


static func skill_of_group(g: int) -> int:
	return g % K


# ── 财政 ───────────────────────────────────────────────────────────────

## 国库现金：account.balance[idx_account(AGENT_GOV=0, ACC_CASH=0)]。
func gov_cash() -> int:
	return at("account.balance", 0)


## 国内投资池现金：agent 57 × 15 科目 + cash(0)。
func invpool_cash() -> int:
	return at("account.balance", 57 * 15)


## 债务余额 = Σ_b<count principal_outstanding（docs/10 derived.gov.debt_uu）。
func debt_total() -> int:
	var n: int = sc("state.bond.count")
	var out: PackedInt64Array = ar("state.bond.principal_outstanding_uu")
	var t: int = 0
	var b: int = 0
	while b < n and b < out.size():
		t += out[b]
		b += 1
	return t


func receipts_total() -> int:
	return sc("flow.gov.receipts_income_tax_uu") + sc("flow.gov.receipts_profit_tax_uu") \
			+ sc("flow.gov.receipts_other_uu")


## 本季支出（基本支出 + 利息；借款不是收入，还本不是支出 —— docs/18 R-SEASON-01 同口径）。
func outlays_total() -> int:
	return sc("flow.gov.primary_paid_uu") + sc("flow.gov.interest_paid_uu")


## 逐批次债务行（未清偿）。
func bond_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var n: int = sc("state.bond.count")
	for b: int in n:
		var outst: int = at("state.bond.principal_outstanding_uu", b)
		rows.append({
			"b": b,
			"outstanding": outst,
			"initial": at("state.bond.principal_initial_uu", b),
			"coupon_ppm": at("state.bond.coupon_ppm_per_q", b),
			"issue_q": at("state.bond.issue_q", b),
			"maturity_q": at("state.bond.maturity_q", b),
			"holder": at("state.bond.holder", b),
			"status": at("state.bond.status", b),
		})
	return rows


## 已签债券批次的未来到期表（规则推断，docs/20 §3.2：未来到期本金与逐批次票息是 DERIVED）。
## 本金：amort_schedule[b*64 + (Q − issue_q[b])]；票息：该季期初余额 × coupon_ppm_per_q（floor）。
## 只含已发行批次，不含尚未发生的新借款。返回 n_q 行：{q, principal, coupon}。
func debt_schedule(n_q: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var n: int = sc("state.bond.count")
	var sched: PackedInt64Array = ar("state.bond.amort_schedule")
	var bal: PackedInt64Array = PackedInt64Array()
	bal.resize(n)
	for b: int in n:
		bal[b] = at("state.bond.principal_outstanding_uu", b)
	for t: int in n_q:
		var qq: int = q + t
		var pr: int = 0
		var cp: int = 0
		for b: int in n:
			if bal[b] <= 0:
				continue
			@warning_ignore("integer_division")
			var coupon: int = bal[b] * at("state.bond.coupon_ppm_per_q", b) / PPM
			cp += coupon
			var k: int = qq - at("state.bond.issue_q", b)
			var due: int = 0
			if k >= 1 and k < 64:
				var idx: int = b * 64 + k
				if idx < sched.size():
					due = mini(sched[idx], bal[b])
			pr += due
			bal[b] -= due
		rows.append({"q": qq, "principal": pr, "coupon": cp})
	return rows


## 已签项目的分期应付（规则推断）：施工中/挂起项目每季按 总额/计划季数 履约，至剩余额为止。
func project_installments(n_q: int) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(n_q)
	out.fill(0)
	var n: int = sc("state.project.count")
	for p: int in n:
		var st: int = at("state.project.status", p)
		if st != PS_IN_PROGRESS and st != PS_SUSPENDED:
			continue
		var total: int = at("state.project.total_cost_uu", p)
		var paid: int = project_paid(p)
		var remaining: int = maxi(total - paid, 0)
		var pq: int = maxi(at("state.project.planned_quarters", p), 1)
		@warning_ignore("integer_division")
		var per: int = total / pq
		var t: int = 0
		while t < n_q and remaining > 0:
			var d: int = mini(per, remaining)
			out[t] += d
			remaining -= d
			t += 1
	return out


## 四季最窄余量（不含本季草案，规则推断）：
## min_t（期初现金 − Σ_{t'≤t}（到期本金 + 票息 + 已签项目分期））。不计经常性收支（口径写在角标里）。
func headroom_nodraft(n_q: int) -> Dictionary:
	var sch: Array[Dictionary] = debt_schedule(n_q)
	var inst: PackedInt64Array = project_installments(n_q)
	var cash: int = gov_cash()
	var worst: int = cash
	var worst_q: int = q
	var cum: int = 0
	for t: int in n_q:
		cum += int(sch[t]["principal"]) + int(sch[t]["coupon"]) + inst[t]
		var v: int = cash - cum
		if t == 0 or v < worst:
			worst = v
			worst_q = q + t
	return {"value": worst, "q": worst_q, "committed_4q": cum}


# ── 人口与就业（docs/10 INV-075） ──────────────────────────────────────

func group_population(g: int) -> int:
	return at("state.group.population_persons", g)


## 逐组就业 = Σ_slot employed_persons[g*5 + slot]（4 部门 + 公共服务）。
func group_employed(g: int) -> int:
	var t: int = 0
	for sl: int in 5:
		t += at("state.group.employed_persons", g * 5 + sl)
	return t


## 逐组劳动力：优先取 derived.group.labor_force_persons；未结算时按 INV-075 反算
## labor_force = floor(pop × participation / 1e6)（仅劳动年龄组）。
func group_labor_force(g: int) -> int:
	if age_of_group(g) != AGE_WORKING:
		return 0
	var lf: PackedInt64Array = darr("derived.group.labor_force_persons")
	if lf.size() == GROUP and settled():
		return lf[g]
	@warning_ignore("integer_division")
	var v: int = group_population(g) * at("state.group.participation_ppm", g) / PPM
	return v


func _unemp_over(groups: PackedInt64Array) -> Dictionary:
	var lf: int = 0
	var emp: int = 0
	for g: int in groups:
		if age_of_group(g) != AGE_WORKING:
			continue
		lf += group_labor_force(g)
		emp += mini(group_employed(g), group_labor_force(g))
	var un: int = maxi(lf - emp, 0)
	@warning_ignore("integer_division")
	var rate: int = un * PPM / lf if lf > 0 else 0
	return {"rate_ppm": rate, "labor_force": lf, "unemployed": un, "employed": emp}


## 全国失业率：已结算时取 derived.labor.unemployment_ppm（权威），分母与人数按同一口径反算同屏给出。
func unemployment() -> Dictionary:
	var all: PackedInt64Array = PackedInt64Array()
	for g: int in GROUP:
		all.append(g)
	var d: Dictionary = _unemp_over(all)
	if settled() and derived.has("derived.labor.unemployment_ppm"):
		d["rate_ppm"] = dv("derived.labor.unemployment_ppm")
		d["source"] = "derived"
	else:
		d["source"] = "state"
	return d


func region_groups(r: int) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for g: int in GROUP:
		if region_of_group(g) == r:
			out.append(g)
	return out


func region_unemployment(r: int) -> Dictionary:
	return _unemp_over(region_groups(r))


func region_population(r: int) -> int:
	var t: int = 0
	for g: int in region_groups(r):
		t += group_population(g)
	return t


func national_population() -> int:
	var t: int = 0
	for g: int in GROUP:
		t += group_population(g)
	return t


# ── 收入、负担与三类民意 ─────────────────────────────────────────────────

## 可支配收入（本季流量）= 工资 + 财产 + 转移 + 互助转入 − 互助转出 − 个税 − 公共服务收费
## （与 JWPopulation.disposable_income 同口径）。
func group_disposable(g: int) -> int:
	return at("flow.group.wage_income_uu", g) + at("flow.group.property_income_uu", g) \
			+ at("flow.group.transfer_income_uu", g) + at("flow.group.support_in_uu", g) \
			- at("flow.group.support_out_uu", g) - at("flow.group.income_tax_paid_uu", g) \
			- at("flow.group.fees_paid_uu", g)


## 人均可支配收入（μU/人/季，floor）。人口为 0 → −1（空组）。
func group_disposable_pc(g: int) -> int:
	var p: int = group_population(g)
	if p <= 0:
		return -1
	@warning_ignore("integer_division")
	var v: int = group_disposable(g) / p
	return v


## 家庭负担率（docs/20 §7.2.3，界面侧提出、待变量字典确认）：
## （住房支出 + 基本服务支出）÷ 可支配收入。首版 SimCore 只有住房支出流量，基本服务支出为 0。
## 可支配收入 ≤ 0 → −1（不适用）。
func group_burden(g: int) -> int:
	var disp: int = group_disposable(g)
	if disp <= 0:
		return -1
	@warning_ignore("integer_division")
	var v: int = at("flow.group.housing_cost_uu", g) * PPM / disp
	return v


func region_burden(r: int) -> Dictionary:
	var h: int = 0
	var d: int = 0
	for g: int in region_groups(r):
		h += at("flow.group.housing_cost_uu", g)
		d += maxi(group_disposable(g), 0)
	@warning_ignore("integer_division")
	var v: int = h * PPM / d if d > 0 else -1
	return {"ppm": v, "housing_uu": h, "disposable_uu": d}


## 人口加权平均（ppm 类逐组量）；exclude_minor 用于支持度（选民口径，politics._note_resident_support）。
func weighted(id: String, groups: PackedInt64Array, exclude_minor: bool = false) -> int:
	var num: int = 0
	var den: int = 0
	for g: int in groups:
		if exclude_minor and age_of_group(g) == AGE_MINOR:
			continue
		var p: int = group_population(g)
		num += at(id, g) * p
		den += p
	@warning_ignore("integer_division")
	var v: int = num / den if den > 0 else 0
	return v


func all_groups() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for g: int in GROUP:
		out.append(g)
	return out


func living_national() -> int:
	return weighted("state.group.living_index_ppm", all_groups())


func expectation_national() -> int:
	return weighted("state.group.expectation_ppm", all_groups())


func trust_national() -> int:
	return weighted("state.group.trust_ppm", all_groups())


func support_national() -> int:
	return weighted("state.group.support_ppm", all_groups(), true)


func support_region(r: int) -> int:
	return weighted("state.group.support_ppm", region_groups(r), true)


## 逐组服务可及性（三类服务等权，与 politics.update_subjective 同口径）。
func group_service_access(g: int) -> int:
	var t: int = 0
	for k: int in 3:
		t += at("state.group.service_access_ppm", g * 3 + k)
	@warning_ignore("integer_division")
	var v: int = t / 3
	return v


## 逐组教育准备程度：在读队列人数 ÷ 组人口（ppm）。未成年组的「教育准备」用它表达（§08）。
func group_edu_readiness(g: int) -> int:
	var p: int = group_population(g)
	if p <= 0:
		return -1
	var t: int = 0
	for sl: int in 8:
		t += at("state.group.education_cohort_persons", g * 8 + sl)
	@warning_ignore("integer_division")
	var v: int = t * PPM / p
	return v


## 通用的人口加权组间分位（P10 / P50 / 均值 / P90）：values 按群组下标给出（长 GROUP），只计有人口的群组；
## adults_only 时跳过未成年组。未结算或无人口时全部为 −1。均值 = Σ(值 × 人口) / Σ人口（组间，不含组内差异）。
func group_quantiles(values: PackedInt64Array, groups: PackedInt64Array, adults_only: bool = true) -> Dictionary:
	var items: Array = []
	var total_p: int = 0
	var total_v: int = 0
	for g: int in groups:
		var pp: int = group_population(g)
		if pp <= 0 or g >= values.size() or (adults_only and age_of_group(g) == AGE_MINOR):
			continue
		items.append([values[g], pp])
		total_p += pp
		total_v += values[g] * pp
	if total_p <= 0 or not settled():
		return {"p10": -1, "p50": -1, "p90": -1, "mean": -1}
	items.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]))
	var out: Dictionary = {}
	for pair: Array in [["p10", 100000], ["p50", 500000], ["p90", 900000]]:
		@warning_ignore("integer_division")
		var target: int = total_p * int(pair[1]) / PPM
		var cum: int = 0
		var val: int = int(items[items.size() - 1][0])
		for it: Array in items:
			cum += int(it[1])
			if cum >= target:
				val = int(it[0])
				break
		out[String(pair[0])] = val
	@warning_ignore("integer_division")
	out["mean"] = total_v / total_p
	return out


## 某个按群组的状态数组（长 GROUP）；缺失时为全 0。
func group_field(id: String) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(GROUP)
	for g: int in GROUP:
		out[g] = at(id, g)
	return out


## 逐组服务可及性（长 GROUP）。
func group_access_values() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	out.resize(GROUP)
	for g: int in GROUP:
		out[g] = group_service_access(g)
	return out


## 收入分位近似（人口加权的组间人均可支配收入分位，不含组内差异；docs/14「不输出精确基尼系数」）。
## 返回 {p10, p50, p90, mean}（μU/人/季）；未结算时全部为 −1。
func income_quantiles(groups: PackedInt64Array) -> Dictionary:
	var items: Array = []
	var total_p: int = 0
	var total_d: int = 0
	for g: int in groups:
		var p: int = group_population(g)
		if p <= 0 or age_of_group(g) == AGE_MINOR:
			continue
		items.append([group_disposable_pc(g), p])
		total_p += p
		total_d += group_disposable(g)
	if total_p <= 0 or not settled():
		return {"p10": -1, "p50": -1, "p90": -1, "mean": -1, "p20": -1, "p80": -1}
	items.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]))
	var out: Dictionary = {}
	for pair: Array in [["p10", 100000], ["p20", 200000], ["p50", 500000], ["p80", 800000],
			["p90", 900000]]:
		@warning_ignore("integer_division")
		var target: int = total_p * int(pair[1]) / PPM
		var cum: int = 0
		var val: int = int(items[items.size() - 1][0])
		for it: Array in items:
			cum += int(it[1])
			if cum >= target:
				val = int(it[0])
				break
		out[String(pair[0])] = val
	@warning_ignore("integer_division")
	out["mean"] = total_d / total_p
	return out


# ── 生产与约束（docs/12 §5.3） ─────────────────────────────────────────

func cell_bounds(c: int) -> Dictionary:
	return {
		"plan": at("flow.cell.bound_plan_uqs", c),
		"capacity": at("flow.cell.bound_capacity_uqs", c),
		"labor": at("flow.cell.bound_labor_uqs", c),
		"energy": at("flow.cell.bound_energy_uqs", c),
		"materials": at("flow.cell.bound_materials_uqs", c),
		"actual": at("flow.cell.output_actual_uqs", c),
		"binding": at("flow.cell.binding_code", c),
	}


## 部门实际增加值（基年价）= Σ_region flow.cell.value_added_real_uu。
func sector_va_real(sec: int) -> int:
	var t: int = 0
	for r: int in R:
		t += at("flow.cell.value_added_real_uu", idx_cell(r, sec))
	return t


func region_va_real(r: int) -> int:
	var t: int = 0
	for sec: int in S:
		t += at("flow.cell.value_added_real_uu", idx_cell(r, sec))
	return t


## 紧约束计数（按绑定码；PLAN 不是瓶颈）。
func binding_counts() -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0])
	for c: int in CELL:
		var b: int = at("flow.cell.binding_code", c)
		if b >= 0 and b < 5:
			out[b] += 1
	return out


## 地区的主导约束类别：该区 4 部门里出现最多的非 PLAN 绑定码；全是 PLAN → PLAN。
func region_binding(r: int) -> int:
	var cnt: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0])
	for sec: int in S:
		var b: int = at("flow.cell.binding_code", idx_cell(r, sec))
		if b >= 0 and b < 5:
			cnt[b] += 1
	var best: int = BIND_PLAN
	var best_n: int = 0
	for b2: int in range(1, 5):
		if cnt[b2] > best_n:
			best_n = cnt[b2]
			best = b2
	return best


## 电力实际可用率：优先 derived.region.electricity_availability_ppm；未结算时按容量 ÷ 需求。
func elec_availability(r: int) -> int:
	var d: PackedInt64Array = darr("derived.region.electricity_availability_ppm")
	if d.size() == R and settled():
		return d[r]
	return PPM


func pubserv_availability(r: int) -> int:
	return at("state.pubserv.availability_ppm", r)


## 四地区公共服务可用率的简单平均（术语卡实例用；地区权重见地区页）。
func availability_national() -> int:
	var t: int = 0
	for r: int in R:
		t += pubserv_availability(r)
	@warning_ignore("integer_division")
	return t / R


## 本局至今各事件触发次数之和（state.event.fire_count，R-EVENT-01）。
func events_fired_total() -> int:
	var t: int = 0
	for v: int in ar("state.event.fire_count"):
		t += v
	return t


# ── 项目与槽位 ───────────────────────────────────────────────────────────

func project_paid(p: int) -> int:
	return at("state.project.paid_uu", p * 3) + at("state.project.paid_uu", p * 3 + 1) \
			+ at("state.project.paid_uu", p * 3 + 2)


func project_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var n: int = sc("state.project.count")
	for p: int in n:
		var total: int = at("state.project.total_cost_uu", p)
		var paid: int = project_paid(p)
		var pq: int = maxi(at("state.project.planned_quarters", p), 1)
		var pol: int = at("state.project.policy_idx", p)
		rows.append({
			"p": p,
			"policy": pol,
			"region": at("state.project.region_idx", p),
			"status": at("state.project.status", p),
			"total": total,
			"paid": paid,
			"remaining": maxi(total - paid, 0),
			"planned_quarters": pq,
			"delivery_ppm": at("state.project.delivery_progress_ppm", p),
			"construction_ppm": at("state.project.construction_progress_ppm", p),
			"capacity_effect": at("state.project.capacity_effect_uqs_per_q", p),
			"opex": at("state.project.opex_per_q_uu", p),
			"commissioned_q": at("state.project.commissioned_q", p),
			"residual": at("state.project.residual_value_uu", p),
			"penalty": at("state.project.cancel_penalty_uu", p),
			"suspension": at("state.project.suspension_reason", p),
			"slot_held": at("state.project.queue_slot_held", p),
			"defer_count": at("state.project.defer_count", p),
			"defer_q_total": at("state.project.defer_quarters_total", p),
			"defer_until_q": at("state.project.defer_until_q", p),
			"defer_fee": at("state.project.defer_fee_uu", p),
			"comp_ppm": at("content.policy.exit_compensation_ppm", pol),
		})
	return rows


## 最早投运季（规则推断）：进度按计划季数匀速推进时的完工季 + 投运延迟；已投运返回投运季。
## 公式：完工季 = q + ceil((1e6 − min(交付, 施工进度)) × 计划季数 / 1e6)；投运季 = 完工季 + commission_delay。
func earliest_commission_q(row: Dictionary) -> int:
	if int(row["status"]) == PS_COMMISSIONED:
		return int(row["commissioned_q"])
	var prog: int = mini(int(row["delivery_ppm"]), int(row["construction_ppm"]))
	var left_ppm: int = maxi(PPM - prog, 0)
	var pq: int = int(row["planned_quarters"])
	@warning_ignore("integer_division")
	var left_q: int = (left_ppm * pq + PPM - 1) / PPM
	var delay: int = maxi(at("content.policy.commission_delay_q", int(row["policy"])), 1)
	return q + maxi(left_q, 0) + delay - 1


## 提前撤回的三项代价（规则推断，docs/20 §7.5.2）：已付不可收回 / 未完工残值 / 合同赔偿。
## 赔偿 = floor(剩余合同额 × 退出赔偿比例)（content.policy.exit_compensation_ppm）；
## 残值 = floor(已付 × 施工进度)（与 P07 exit_rule 的登记口径一致，展示用近似）。
func withdraw_cost(row: Dictionary) -> Dictionary:
	var paid: int = int(row["paid"])
	@warning_ignore("integer_division")
	var residual: int = paid * int(row["construction_ppm"]) / PPM
	@warning_ignore("integer_division")
	var penalty: int = int(row["remaining"]) * int(row["comp_ppm"]) / PPM
	return {"sunk": paid - residual, "residual": residual, "penalty": penalty,
			"remaining_commit": int(row["remaining"])}


## 延期的代价与余量（规则推断，docs/18 R-DEFER-01）：
## 赔偿 = floor(剩余合同额 × min(每季赔偿率 × 季数, 1e6) / 1e6)，当季付清；剩余承诺不变；
## allowed 与结算器 JWProjectQueue.defer 的判据逐条一致：S02 先让到期的延期复工、挂起的项目复工，
## 再受理命令，故「在建或挂起（非延期，或延期已到期）」且次数、累计季数未超限即可。
func defer_cost(row: Dictionary, quarters: int) -> Dictionary:
	var rate: int = clampi(rule("param.defer_fee_ppm_per_q", 0) * quarters, 0, PPM)
	@warning_ignore("integer_division")
	var fee: int = int(row["remaining"]) * rate / PPM
	var count_left: int = maxi(rule("param.max_defer_count", 0) - int(row["defer_count"]), 0)
	var q_left: int = maxi(rule("param.max_defer_quarters", 0) - int(row["defer_q_total"]), 0)
	var st: int = int(row["status"])
	var deferred: bool = st == PS_SUSPENDED and int(row["suspension"]) == SUSPEND_DEFERRED
	var due: bool = deferred and int(row["defer_until_q"]) <= q
	var running: bool = st == PS_IN_PROGRESS or (st == PS_SUSPENDED and (not deferred or due))
	var allowed: bool = running and count_left > 0 and quarters >= 1 and quarters <= q_left
	return {"fee": fee, "rate_ppm": rate, "remaining_commit": int(row["remaining"]),
			"count_left": count_left, "q_left": q_left, "resume_q": q + quarters,
			"allowed": allowed, "deferred": deferred and not due, "until_q": int(row["defer_until_q"])}


func slots_total(r: int) -> int:
	return at("state.region.construction_slots_total", r)


## 已占施工槽位：优先 derived.region.construction_slots_used；否则 Σ 本区 queue_slot_held。
func slots_used(r: int) -> int:
	var d: PackedInt64Array = darr("derived.region.construction_slots_used")
	var t: int = 0
	var n: int = sc("state.project.count")
	for p: int in n:
		if at("state.project.region_idx", p) == r and at("state.project.queue_slot_held", p) == 1:
			t += 1
	if d.size() == R and settled():
		return maxi(d[r], t)
	return t


# ── 政策 ───────────────────────────────────────────────────────────────

func policy_param(p: int, j: int) -> int:
	return at("state.policy.params_ppm", p * 4 + j)


func policy_params(p: int) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for j: int in 4:
		out.append(policy_param(p, j))
	return out


func param_min(p: int, j: int) -> int:
	return at("content.policy.param_min_ppm", p * 4 + j)


func param_max(p: int, j: int) -> int:
	return at("content.policy.param_max_ppm", p * 4 + j)


func param_default(p: int, j: int) -> int:
	return at("content.policy.param_default", p * 4 + j)


func policy_enabled(p: int) -> bool:
	return at("state.policy.enabled", p) == 1


## 立法窗口：本季是否为预算审查季（S02 在 q == next_budget_review_q 时置位）。
func review_window_open() -> bool:
	return q == sc("state.politics.next_budget_review_q")


func next_review_q() -> int:
	var n: int = sc("state.politics.next_budget_review_q")
	return n if n >= q else n + 4


func next_election_q() -> int:
	for e: int in ELECTION_QS:
		if e >= q:
			return e
	return -1


## 资格链的界面侧镜像（与 S02 的五档同序：权限/席位/否决 → 冷却 → 窗口 → 队列 → 资金）。
## 权威判定在 S02；提交前以草案试算的 S02 回执为准。返回 {code, …各档数值}。
## scale_ppm 只影响资金档（开启时本季预留 = 每季成本 × 规模）。
func eligibility(p: int, for_launch: bool, region: int = -1, scale_ppm: int = PPM) -> Dictionary:
	var out: Dictionary = {"code": 0, "p": p}
	if terminated:
		out["code"] = RJ_RUN_TERMINATED
		return out
	if for_launch:
		# project_launch 在 S02 只判施工槽位与规模退化（JWProjectQueue.launch），不判权限与资金。
		if region >= 0:
			var used: int = slots_used(region)
			var tot: int = slots_total(region)
			out["slots_used"] = used
			out["slots_total"] = tot
			if used >= tot:
				out["code"] = RJ_NO_SLOT
		return out
	if policy_enabled(p):
		out["code"] = RJ_ALREADY_ENACTED
		out["since_q"] = at("state.policy.enacted_q", p)
		return out
	var bit: int = at("content.policy.authority_bit", p)
	var mask: int = sc("state.politics.legal_authority_mask")
	out["authority_bit"] = bit
	out["authority_mask"] = mask
	if (mask >> bit) & 1 != 1:
		out["code"] = RJ_AUTHORITY
		return out
	var seats: int = sc("state.politics.seats_gov")
	var total: int = sc("state.politics.seats_total")
	var min_ppm: int = at("content.policy.min_seats_ppm", p)
	out["seats_gov"] = seats
	out["seats_total"] = total
	out["min_seats_ppm"] = min_ppm
	if total > 0 and seats * PPM < min_ppm * total:
		out["code"] = RJ_SEATS_SHORT
		return out
	var veto_mask: int = at("content.policy.requires_bloc_mask", p)
	var thr: int = rule("politics.veto_stance_threshold_ppm", -300000)
	for b: int in BLOC_N:
		if (veto_mask >> b) & 1 == 1:
			var st: int = at("state.bloc.stance_ppm", b * POLICY_N + p)
			if st < thr:
				out["code"] = RJ_BLOC_VETO
				out["bloc"] = b
				out["stance_ppm"] = st
				out["threshold_ppm"] = thr
				return out
	var cd: int = at("state.policy.cooldown_until_q", p)
	if q < cd:
		out["code"] = RJ_POLICY_COOLDOWN
		out["cooldown_until_q"] = cd
		return out
	if at("content.policy.requires_budget_review", p) == 1 and not review_window_open():
		out["code"] = RJ_PRECONDITION
		out["window"] = true
		out["next_window_q"] = next_review_q()
		return out
	@warning_ignore("integer_division")
	var need: int = at("content.policy.cost_per_quarter_uu", p) * scale_ppm / PPM \
			+ at("content.policy.toggle_cost_uu", p)
	var avail: int = gov_cash() - sc("state.gov.reserved_memo_uu")
	out["need"] = need
	out["avail"] = avail
	if avail < need:
		out["code"] = RJ_BUDGET_INSUFFICIENT
	return out


# ── 外部与冲击 ───────────────────────────────────────────────────────────

func credit_left() -> int:
	return sc("state.world.credit_limit_uu") - sc("state.world.credit_used_uu")


func active_shocks() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for k: int in 3:
		if at("state.world.shock_active", k) == 1:
			rows.append({"k": k, "magnitude_ppm": at("state.world.shock_magnitude_ppm", k)})
	return rows


# ── 命令日志 ───────────────────────────────────────────────────────────

## 指定内部季的命令回执：[{kind, args, accepted, reject_code, command_id}]（不含推进标记）。
func commands_of_quarter(qq: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var n: int = int(cmdlog.get("count", 0))
	if n <= 0:
		return rows
	var iq: PackedInt64Array = cmdlog.get("issued_q", PackedInt64Array())
	var kd: PackedInt64Array = cmdlog.get("kind", PackedInt64Array())
	var ac: PackedInt64Array = cmdlog.get("accepted", PackedInt64Array())
	var rj: PackedInt64Array = cmdlog.get("reject_code", PackedInt64Array())
	var ag: PackedInt64Array = cmdlog.get("args", PackedInt64Array())
	var ci: PackedInt64Array = cmdlog.get("command_id", PackedInt64Array())
	var slots: int = int(cmdlog.get("arg_slots", 6))
	for i: int in n:
		if iq[i] != qq or kd[i] == 99:
			continue
		rows.append({"kind": kd[i], "args": ag.slice(i * slots, i * slots + slots),
				"accepted": ac[i], "reject_code": rj[i], "command_id": ci[i]})
	return rows
