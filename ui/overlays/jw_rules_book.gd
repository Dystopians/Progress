## 规则手册（docs/20 §10.4）：不可隐藏的当前规则清单，入口 ≤2 次点击，每条有唯一锚点。
## 冲击只列机制与取值范围，不披露本局是否发生与抽样值（「本局未披露」）。
class_name JwRulesBook
extends JwOverlay


func _init() -> void:
	width_ratio = 0.8
	height_ratio = 0.9


func build() -> void:
	set_title(JwText.t("rb.title"))
	var m: JwReadModel = session.model
	var cat: JwCatalog = session.catalog
	for i: int in range(1, 15):
		var sec: Dictionary = JwUi.section(JwText.t("rb.s%d" % i))
		JwUi.tag(sec["root"], "RuleAnchor%d" % i)
		var b: VBoxContainer = sec["body"]
		match i:
			14:
				_section_industry(b, m, cat)
			1:
				for p: int in JwReadModel.POLICY_N:
					var pd: Dictionary = cat.policy(p)
					b.add_child(JwUi.label(JwText.render("rb.policy", {"code": String(pd["code"]), "label": String(pd["label"]),
							"one": JwFormat.u(int(pd["one_off_uu"])), "per": JwFormat.u(int(pd["per_quarter_uu"])),
							"lo": JwFormat.quarters(int(pd["lag_min"])), "hi": JwFormat.quarters(int(pd["lag_max"])),
							"problem": JwText.t("policy.problem." + String(pd["code"]))}), "body", "text.secondary", true))
			9:
				b.add_child(JwUi.label(JwText.t("rb.body.9"), "body", "text.secondary", true))
				for ev: Dictionary in cat.events:
					var l9: Label = JwUi.label(_event_line(ev, cat), "body", "text.secondary", true)
					JwUi.tag(l9, "RuleEvent_" + String(ev["code"]))
					b.add_child(l9)
			10:
				for sh: Dictionary in cat.shocks:
					b.add_child(JwUi.label(JwText.render("rb.shock", {"label": String(sh["label"]),
							"channel": JwText.t("shock.channel." + String(sh["channel"])),
							"mlo": JwFormat.pct(int(sh["mag_min"])), "mhi": JwFormat.pct(int(sh["mag_max"])),
							"dlo": JwFormat.quarters(int(sh["dur_min"])), "dhi": JwFormat.quarters(int(sh["dur_max"])),
							"hazard": JwFormat.pct(int(sh["hazard_ppm"])), "earliest": JwFormat.quarter(int(sh["earliest_q"]))}),
							"body", "text.secondary", true))
				b.add_child(JwUi.label(JwText.t("rb.shock.hidden"), "body_bold", "text.primary", true))
			11:
				var hsh: String = String(m.rules.get("meta.content_hash", ""))
				b.add_child(JwUi.label(JwText.render("rb.seed", {"seed": str(session.seed_value), "hash": hsh.substr(0, 16),
						"build": String(m.rules.get("meta.build_id", ""))}), "mono", "text.primary", true))
			6:
				var parts: PackedStringArray = PackedStringArray()
				for r: int in JwReadModel.R:
					parts.append(cat.region_label(r) + " " + str(m.slots_total(r)))
				b.add_child(JwUi.label(JwText.render("rb.body.6", {"slots": "、".join(parts)}), "body", "text.secondary", true))
			7:
				b.add_child(JwUi.label(JwText.render("rb.body.7", {"deficit": JwFormat.pct(m.rule("politics.budget_review_deficit_limit_ppm", 0)),
						"arrears": JwFormat.u(m.rule("politics.budget_review_arrears_limit_uu", 0)),
						"lost": str(m.rule("politics.budget_review_fail_to_lost_count", 0)),
						"noconf": JwFormat.quarters(m.rule("param.no_confidence_q", 0)), "grace": JwFormat.quarters(m.rule("param.default_grace_q", 0)),
						"veto": JwFormat.pct(m.rule("politics.veto_stance_threshold_ppm", 0))}), "body", "text.secondary", true))
			_:
				b.add_child(JwUi.label(JwText.t("rb.body.%d" % i), "body", "text.secondary", true))
		body.add_child(sec["root"])
	# 从术语卡或规则卡跳来时定位到锚点（布局完成后才有位置，故延后一帧）。
	var want: int = int(ctx.get("anchor", 0))
	if want >= 1 and want <= 13:
		_scroll_to_anchor(want)


## 等两帧布局完成（位置才有意义），再把目标节的顶端滚到视口顶端。
func _scroll_to_anchor(n: int) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var target: Control = _find_tagged(self, "RuleAnchor%d" % n)
	var sc: ScrollContainer = find_child("OverlayScroll", true, false) as ScrollContainer
	if target == null or sc == null or sc.get_child_count() == 0:
		return
	var content: Control = sc.get_child(0) as Control
	sc.scroll_vertical = int(target.global_position.y - content.global_position.y)


## 一条事件模板的公开触发条件：全部条件同时成立才按概率抽签；是否会触发不披露。
static func _event_line(ev: Dictionary, cat: JwCatalog) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for c: Dictionary in ev["conds"]:
		parts.append(_cond_text(c, cat))
	return JwText.render("rb.event", {"code": String(ev["code"]), "label": String(ev["label"]),
			"conds": JwText.t("rb.event.sep").join(parts), "p": JwFormat.pct(int(ev["p_ppm"])),
			"cd": JwFormat.quarters(int(ev["cooldown_q"])), "max": str(int(ev["max"]))})


static func _cond_text(c: Dictionary, cat: JwCatalog) -> String:
	var metric: String = String(c["metric"])
	var scope: String = String(c["scope"])
	var op: String = String(c["op"])
	var v: int = int(c["value"])
	if metric == "state.time.q":
		return JwText.render("rb.event.cond.from_q", {"q": JwFormat.quarter(v)})
	if metric == "state.policy.enabled":
		var on: bool = (op == "eq" and v == 1) or (op == "ne" and v == 0)
		return JwText.render("rb.event.cond.policy_on" if on else "rb.event.cond.policy_off",
				{"policy": cat.scope_label(scope)})
	if metric == "flow.politics.budget_review_due":
		return JwText.t("rb.event.cond.review")
	var mname: String = JwText.t_or("ev.metric." + metric, "ev.metric.unknown")
	var value: String = _cond_value(metric, v)
	var sl: String = cat.scope_label(scope)
	var opt: String = JwText.t_or("ev.op." + op, "ev.op.unknown")
	if sl == "":
		return JwText.render("rb.event.cond_ns", {"metric": mname, "op": opt, "value": value})
	return JwText.render("rb.event.cond", {"metric": mname, "scope": sl, "op": opt, "value": value})


## 阈值按指标的单位后缀格式化（只格式化，不换算口径）。
static func _cond_value(metric: String, v: int) -> String:
	if metric.ends_with("binding_code"):
		return JwText.t("binding.%d" % v)
	if metric.ends_with("_uu_per_qs"):
		# 部门价格：以基年价 1 U / Q 为 100%。
		@warning_ignore("integer_division")
		return JwText.render("ev.unit.price", {"pct": JwFormat.pct(v / 1000)})
	if metric.ends_with("_ppm"):
		return JwFormat.pct(v)
	if metric.ends_with("_uu"):
		return JwFormat.u(v)
	if metric.ends_with("_persons"):
		return JwFormat.persons(v)
	if metric.ends_with("_units"):
		return JwText.render("ev.unit.units", {"n": JwFormat.group3(v)})
	if metric.ends_with("_uqs") or metric.ends_with("_uqs_per_q") or metric.ends_with("_uqe"):
		return JwFormat.qty_num(v)
	return JwFormat.group3(v)


static func _find_tagged(n: Node, id: String) -> Control:
	if n is Control and String((n as Control).get_meta("jw_id", "")) == id:
		return n as Control
	for ch: Node in n.get_children():
		var f: Control = _find_tagged(ch, id)
		if f != null:
			return f
	return null


## 第 14 章（docs/53 M2）：研究、建筑与生产方式、贸易伙伴。数值全部现取自内容表，界面不另存一份。
func _section_industry(b: VBoxContainer, m: JwReadModel, cat: JwCatalog) -> void:
	if m.sc("content.research.enabled") == 0:
		b.add_child(JwUi.label(JwText.t("rb.body.14_term"), "body", "text.secondary", true))
		return
	b.add_child(JwUi.label(JwText.t("rb.body.14"), "body", "text.secondary", true))
	for t: int in m.sc("content.tech.count"):
		b.add_child(JwUi.label(JwText.render("rb.tech", {"label": cat.tech_label(t),
				"cost": JwFormat.group3(m.at("content.tech.cost", t)),
				"prereq": _mask_names(m.at("content.tech.prereq_mask", t), cat)}),
				"body", "text.secondary", true))
	for bt: int in range(1, m.sc("content.building.type_count")):
		var sec: int = m.at("content.building.sector", bt)
		b.add_child(JwUi.label(JwText.render("rb.building", {"label": cat.building_label(bt),
				"sector": JwText.t("sector.%d" % sec),
				"capacity": JwFormat.qty(m.at("content.building.unit_capacity_uqs", bt),
						JwText.t("sector.unit.%d" % sec)),
				"cost": JwFormat.u(m.at("content.building.cost_uu", bt)),
				"quarters": JwFormat.quarters(m.at("content.building.quarters", bt)),
				"opex": JwFormat.u(m.at("content.building.opex_uu", bt)),
				"owners": _owner_names(m.at("content.building.owners_mask", bt))}),
				"body", "text.secondary", true))
	for mt: int in range(1, m.sc("content.method.count")):
		b.add_child(JwUi.label(JwText.render("rb.method", {"label": cat.method_label(mt),
				"building": cat.building_label(m.at("content.method.building", mt)),
				"output": JwFormat.ratio(m.at("content.method.output_ppm", mt)),
				"cost": JwFormat.u(m.at("content.method.retrofit_cost_uu", mt)),
				"quarters": JwFormat.quarters(m.at("content.method.retrofit_quarters", mt)),
				"frozen": JwFormat.pct(m.at("content.method.retrofit_frozen_ppm", mt))}),
				"body", "text.secondary", true))
	for p: int in m.sc("content.partner.count"):
		b.add_child(JwUi.label(JwText.render("rb.partner", {"label": cat.partner_label(p),
				"export": JwFormat.pct(m.at("state.partner.export_share_ppm", p)),
				"import": JwFormat.pct(m.at("state.partner.import_share_ppm", p)),
				"price": JwFormat.ratio(m.at("state.partner.price_mult_ppm", p)),
				"relation": JwFormat.pct(m.at("state.partner.relation_ppm", p))}),
				"body", "text.secondary", true))


## 前置科技掩码 → 名字串；没有前置时给「无」。
static func _mask_names(mask: int, cat: JwCatalog) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for t: int in cat.technologies.size():
		if (mask >> t) & 1 == 1:
			parts.append(cat.tech_label(t))
	return JwText.t("rb.none") if parts.is_empty() else "、".join(parts)


static func _owner_names(mask: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for o: int in 2:
		if (mask >> o) & 1 == 1:
			parts.append(JwText.t("ind.owner.%d" % o))
	return JwText.t("rb.none") if parts.is_empty() else "、".join(parts)
