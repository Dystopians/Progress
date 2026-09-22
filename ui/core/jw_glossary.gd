## 术语表（docs/20 §10.4「术语首见」、AC-34）：每条 = 术语 / 一句定义 / 本局实例 / 规则手册锚点。
## 文案在 ui/text/zh_cn/glossary.json（gloss.<id>.term / .def / .inst）；实例里的数值由读模型现取，
## 本类只挑字段与格式化，不做运算（运算在 JwReadModel）。
class_name JwGlossary
extends RefCounted

## 术语 → 规则手册锚点（JwRulesBook 的 RuleAnchor1..14）。
const ANCHOR: Dictionary = {
	"info_class": 13, "gov_cash": 3, "arrears": 3, "commitment": 3, "tax_capacity": 3,
	"availability": 3, "budget_review": 7, "termination": 7, "bond_batch": 4, "sovereign_rate": 4,
	"slot": 6, "project_defer": 6, "lag": 1, "veto": 7, "seats": 7, "trust": 7, "living": 8,
	"unemployment": 8, "event": 9, "shock": 10,
	# M2（docs/53）：研究、建筑与生产方式、贸易。
	"research_point": 14, "building_stack": 14, "production_method": 14, "trade_quota": 14,
}

## 各页「本页术语」条列出的术语（顺序即显示顺序）。
const PAGE_TERMS: Dictionary = {
	"overview": ["info_class", "gov_cash", "arrears", "budget_review", "termination", "unemployment", "event", "shock"],
	"region": ["slot", "availability", "living", "unemployment"],
	"policy": ["lag", "veto", "seats", "commitment", "tax_capacity", "bond_batch", "sovereign_rate", "project_defer"],
	"industry": ["research_point", "building_stack", "production_method", "trade_quota", "slot"],
	"society": ["living", "trust", "seats", "veto"],
	"report": ["info_class", "event", "project_defer", "arrears", "commitment"],
}


static func ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for k: Variant in ANCHOR.keys():
		out.append(String(k))
	return out


static func has(id: String) -> bool:
	return ANCHOR.has(id)


static func term(id: String) -> String:
	return JwText.t("gloss.%s.term" % id)


static func definition(id: String) -> String:
	return JwText.t("gloss.%s.def" % id)


static func anchor(id: String) -> int:
	return int(ANCHOR.get(id, 0))


static func page_terms(page_id: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for v: Variant in PAGE_TERMS.get(page_id, []):
		out.append(String(v))
	return out


## 本局实例：一句带当前数值的话（读模型现取；冲击只给种子，不披露抽样）。
static func instance(id: String, s: JwSession) -> String:
	if s == null or s.model == null:
		return ""
	var m: JwReadModel = s.model
	var slots: Dictionary = {}
	match id:
		"info_class", "gov_cash":
			slots = {"cash": JwFormat.u(m.gov_cash())}
		"arrears":
			slots = {"arrears": JwFormat.u(m.sc("state.gov.arrears_uu"))}
		"commitment":
			slots = {"memo": JwFormat.u(m.sc("state.gov.committed_memo_uu"))}
		"tax_capacity":
			slots = {"cap": JwFormat.pct(m.sc("state.gov.tax_capacity_ppm"))}
		"availability":
			slots = {"avail": JwFormat.pct(m.availability_national())}
		"budget_review":
			slots = {"q": JwFormat.quarter(m.next_review_q()), "fails": str(m.sc("state.politics.review_fail_streak"))}
		"termination":
			slots = {"q": JwFormat.quarter(m.next_election_q()), "fails": str(m.sc("state.politics.review_fail_streak"))}
		"bond_batch":
			slots = {"n": str(m.sc("state.bond.count")), "debt": JwFormat.u(m.debt_total())}
		"sovereign_rate":
			slots = {"rate": JwFormat.pct(m.sc("state.world.sovereign_rate_ppm_per_q"))}
		"slot":
			var parts: PackedStringArray = PackedStringArray()
			for r: int in JwReadModel.R:
				parts.append(JwText.render("gloss.slot.part", {"region": s.catalog.region_label(r),
						"used": str(m.slots_used(r)), "total": str(m.slots_total(r))}))
			slots = {"slots": "、".join(parts)}
		"project_defer":
			slots = {"count": str(m.rule("param.max_defer_count", 0)),
					"quarters": JwFormat.quarters(m.rule("param.max_defer_quarters", 0)),
					"rate": JwFormat.pct(m.rule("param.defer_fee_ppm_per_q", 0))}
		"lag":
			var pd: Dictionary = s.catalog.policy(0)
			slots = {"policy": String(pd.get("label", "")), "lo": JwFormat.quarters(int(pd.get("lag_min", 0))),
					"hi": JwFormat.quarters(int(pd.get("lag_max", 0)))}
		"veto":
			slots = {"veto": JwFormat.pct(m.rule("politics.veto_stance_threshold_ppm", 0))}
		"seats":
			slots = {"seats": str(m.sc("state.politics.seats_gov")), "total": str(m.sc("state.politics.seats_total"))}
		"trust":
			slots = {"trust": JwFormat.pct(m.trust_national())}
		"living":
			slots = {"living": JwFormat.pct(m.living_national())}
		"unemployment":
			slots = {"rate": JwFormat.pct(int(m.unemployment().get("rate_ppm", 0)))}
		"event":
			slots = {"n": str(m.events_fired_total())}
		"shock":
			slots = {"seed": str(s.seed_value)}
		"research_point":
			slots = {"gained": JwFormat.group3(m.sc("flow.research.points_gained")),
					"pool": JwFormat.group3(m.sc("state.research.points_pool"))}
		"building_stack":
			slots = {"n": str(m.stack_count())}
		"production_method":
			slots = {"n": str(maxi(m.sc("content.method.count") - 1, 0))}
		"trade_quota":
			slots = {"n": str(m.sc("content.partner.count"))}
		_:
			return ""
	return JwText.render("gloss.%s.inst" % id, slots)
