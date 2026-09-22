## 页面四 · 产业与科技（docs/53 M2-7；docs/18 R-RESEARCH-01、R-METHOD-01、R-OWNER-01、R-TRADE-01）：
## 「我现在能研究什么、能建什么、手上的设施是什么状况、跟谁做生意」。
##
## 四块：
## ① 研究：本季研究点的来源与去向、当前方向、科技清单（状态、成本、进度、可否研究）。
## ② 可建：已解锁的建筑类型卡（配图 + 产能 / 造价 / 工期 / 运维），按所有者给出建造入口。
## ③ 现有：建筑堆列表（地区 × 行业 × 类型 × 所有者 × 方式、等级、产能、改造冻结份额）与改造入口。
## ④ 贸易：三个伙伴的额度、价格系数、关系、子账余额，以及调额度 / 缔约入口。
##
## 本页只读 JwReadModel 与 JwCatalog，所有动作都变成草案（与其它页一致：先进草案篮，确认推进时才提交）。
## 旧剧本（单届）没有研究与建筑表，本页给空态说明，不显示假数据。
class_name JwIndustryPage
extends JwPage

## 建造落点：本页自己的地区选择（草案里写明地区，确认框可见）。
var build_region: int = 0
var _root: VBoxContainer = null


func refresh() -> void:
	if _root != null:
		remove_child(_root)
		_root.queue_free()
	_root = JwUi.vbox(12)
	_root.name = "IndustryRoot"
	add_child(_root)
	_root.add_child(term_strip())
	if session == null or session.game == null:
		_root.add_child(JwUi.empty_state(JwText.t("ind.empty.why"), JwText.t("ind.empty.when"),
				JwText.t("ind.empty.rule")))
		return
	if session.model.sc("content.research.enabled") == 0:
		_root.add_child(JwUi.empty_state(JwText.t("ind.term.why"), JwText.t("ind.term.when"),
				JwText.t("ind.term.rule")))
		return
	var body: VBoxContainer = JwUi.vbox(14)
	_root.add_child(JwUi.scroll(body))
	body.add_child(_research_block())
	body.add_child(_buildable_block())
	body.add_child(_stacks_block())
	body.add_child(_trade_block())


func get_required_above_fold(_band: int) -> Array[StringName]:
	return [&"ResearchBlock", &"BuildableBlock"]


## 统一的分块外框（与政策页同一套边框口径）。返回 [外框, 内容容器]。
func _block(tag_id: String, title_key: String) -> Array:
	var box: VBoxContainer = JwUi.vbox(8)
	JwUi.tag(box, tag_id)
	box.add_child(JwUi.label(JwText.t(title_key), "title_sub"))
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.raised", "line.hair", 1, 14, 10, 14, 10))
	p.add_child(box)
	return [p, box]


# ── ① 研究 ─────────────────────────────────────────────────────────────

func _research_block() -> Control:
	var m: JwReadModel = session.model
	var pair: Array = _block("ResearchBlock", "ind.research.title")
	var box: VBoxContainer = pair[1]
	var focus: int = m.sc("state.research.focus")
	box.add_child(JwUi.label(JwText.render("ind.research.summary", {
			"gained": JwFormat.group3(m.sc("flow.research.points_gained")),
			"pool": JwFormat.group3(m.sc("state.research.points_pool")),
			"focus": session.catalog.tech_label(focus) if focus >= 0 \
					else JwText.t("ind.research.no_focus")}), "body", "text.secondary", true))
	box.add_child(JwUi.caption(JwText.t("ind.research.source")))
	for t: int in m.sc("content.tech.count"):
		box.add_child(_tech_row(t, focus))
	return pair[0]


func _tech_row(t: int, focus: int) -> Control:
	var m: JwReadModel = session.model
	var row: VBoxContainer = JwUi.vbox(2)
	JwUi.tag(row, "Tech_%d" % t)
	var head: HBoxContainer = JwUi.hbox(10)
	head.add_child(JwUi.label(session.catalog.tech_label(t), "body_bold"))
	head.add_child(JwUi.label(JwText.t("ind.tech.state.%d" % m.at("state.research.status", t)),
			"caption", "text.secondary"))
	head.add_child(JwUi.label(JwText.render("ind.tech.progress", {
			"done": JwFormat.group3(m.at("state.research.progress", t)),
			"cost": JwFormat.group3(m.at("content.tech.cost", t))}), "caption", "text.muted"))
	head.add_child(JwUi.spacer())
	if t == focus:
		head.add_child(JwUi.label(JwText.t("ind.research.current"), "caption", "teal.core"))
	elif m.tech_available(t):
		var b: Button = JwUi.button(JwText.t("ind.research.set_focus"))
		JwUi.tag(b, "SetFocus_%d" % t)
		var tt: int = t
		b.pressed.connect(func() -> void:
			session.add_draft(session.draft_research(tt, session.catalog.tech_label(tt))))
		head.add_child(b)
	row.add_child(head)
	var desc: String = session.catalog.tech_desc(t)
	if desc != "" and (t == focus or m.tech_available(t)):
		row.add_child(JwUi.label(desc, "caption", "text.muted", true))
	return row


# ── ② 可建清单 ──────────────────────────────────────────────────────────

func _buildable_block() -> Control:
	var m: JwReadModel = session.model
	var pair: Array = _block("BuildableBlock", "ind.build.title")
	var box: VBoxContainer = pair[1]
	box.add_child(_region_picker())
	var done: int = m.sc("state.research.completed_mask")
	var any: bool = false
	for bt: int in range(1, m.sc("content.building.type_count")):
		if not _type_unlocked(bt, done):
			continue
		any = true
		box.add_child(_building_card(bt))
	if not any:
		box.add_child(JwUi.label(JwText.t("ind.build.none"), "body", "text.muted", true))
	return pair[0]


func _region_picker() -> Control:
	var h: HBoxContainer = JwUi.hbox(8)
	JwUi.tag(h, "BuildRegionPicker")
	h.add_child(JwUi.label(JwText.t("ind.build.region"), "caption", "text.muted"))
	for r: int in JwReadModel.R:
		var b: Button = JwUi.button(session.catalog.region_label(r),
				"PrimaryButton" if r == build_region else "")
		JwUi.tag(b, "BuildRegion_%d" % r)
		var rr: int = r
		b.pressed.connect(func() -> void:
			build_region = rr
			refresh())
		h.add_child(b)
	return h


## 某建筑类型是否已被已完成的科技解锁（界面侧复算，与 SimCore 同一口径）。
func _type_unlocked(bt: int, completed_mask: int) -> bool:
	var techs: Array[Dictionary] = session.catalog.technologies
	for t: int in techs.size():
		if (completed_mask >> t) & 1 == 0:
			continue
		for u: Variant in techs[t].get("unlocks", {}).get("building_types", []):
			if _building_index_of(String(u)) == bt:
				return true
	return false


func _building_index_of(building_id: String) -> int:
	var arr: Array[Dictionary] = session.catalog.building_types
	for i: int in arr.size():
		if String(arr[i].get("building_id", "")) == building_id:
			return i + 1
	return -1


func _building_card(bt: int) -> Control:
	var m: JwReadModel = session.model
	var card: HBoxContainer = JwUi.hbox(12)
	JwUi.tag(card, "BuildCard_%d" % bt)
	var art: String = session.catalog.building_art(bt, _era_hint())
	if art != "":
		var tex: TextureRect = TextureRect.new()
		tex.texture = load(art)
		tex.custom_minimum_size = Vector2(128, 128)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		JwUi.tag(tex, "BuildArt_%d" % bt)
		card.add_child(tex)
	var right: VBoxContainer = JwUi.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sec: int = m.at("content.building.sector", bt)
	right.add_child(JwUi.label("%s · %s" % [session.catalog.building_label(bt),
			JwText.t("sector.%d" % sec)], "body_bold"))
	right.add_child(JwUi.label(JwText.render("ind.build.spec", {
			"capacity": JwFormat.qty(m.at("content.building.unit_capacity_uqs", bt),
					JwText.t("sector.unit.%d" % sec)),
			"cost": JwFormat.u(m.at("content.building.cost_uu", bt)),
			"quarters": JwFormat.quarters(m.at("content.building.quarters", bt)),
			"opex": JwFormat.u(m.at("content.building.opex_uu", bt))}), "caption", "text.secondary", true))
	var desc: String = session.catalog.building_desc(bt)
	if desc != "":
		right.add_child(JwUi.label(desc, "caption", "text.muted", true))
	var actions: HBoxContainer = JwUi.hbox(8)
	var owners: int = m.at("content.building.owners_mask", bt)
	for owner: int in 2:
		if (owners >> owner) & 1 == 0:
			continue
		var ob: Button = JwUi.button(JwText.render("ind.build.action", {
				"owner": JwText.t("ind.owner.%d" % owner)}))
		JwUi.tag(ob, "Build_%d_%d" % [bt, owner])
		var bb: int = bt
		var oo: int = owner
		ob.pressed.connect(func() -> void:
			session.add_draft(session.draft_build(bb, build_region, oo, 0,
					session.catalog.building_label(bb),
					session.model.at("content.building.cost_uu", bb))))
		actions.add_child(ob)
	right.add_child(actions)
	card.add_child(right)
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.base", "line.hair", 1, 10, 8, 10, 8))
	p.add_child(card)
	return p


## 配图选哪一档：按已完成科技里最高的时代提示（没完成过就用最早的一档）。
func _era_hint() -> int:
	var m: JwReadModel = session.model
	var done: int = m.sc("state.research.completed_mask")
	var era: int = 1
	for t: int in m.sc("content.tech.count"):
		if (done >> t) & 1 == 1:
			era = maxi(era, m.at("content.tech.era_hint", t))
	return era


# ── ③ 现有建筑堆 ────────────────────────────────────────────────────────

func _stacks_block() -> Control:
	var m: JwReadModel = session.model
	var pair: Array = _block("StacksBlock", "ind.stacks.title")
	var box: VBoxContainer = pair[1]
	box.add_child(JwUi.caption(JwText.t("ind.stacks.note")))
	var shown: int = 0
	for b: int in m.stack_count():
		var row: Dictionary = m.stack_row(b)
		if int(row["capacity"]) <= 0 and int(row["pending"]) <= 0:
			continue
		box.add_child(_stack_row(b, row))
		shown += 1
	if shown == 0:
		box.add_child(JwUi.label(JwText.t("ind.stacks.none"), "body", "text.muted", true))
	return pair[0]


func _stack_row(b: int, row: Dictionary) -> Control:
	var line: HBoxContainer = JwUi.hbox(10)
	JwUi.tag(line, "Stack_%d" % b)
	var cell: int = int(row["cell"])
	@warning_ignore("integer_division")
	var region: int = cell / JwReadModel.S
	var sector: int = cell - region * JwReadModel.S
	line.add_child(JwUi.label("%s · %s" % [session.catalog.region_label(region),
			JwText.t("sector.%d" % sector)], "body"))
	line.add_child(JwUi.label(session.catalog.building_label(int(row["type"])), "body_bold"))
	line.add_child(JwUi.label(JwText.t("ind.owner.%d" % int(row["owner"])), "caption", "text.secondary"))
	line.add_child(JwUi.label(session.catalog.method_label(int(row["method"])), "caption", "text.secondary"))
	line.add_child(JwUi.label(JwText.render("ind.stacks.cap", {
			"level": str(int(row["level"])),
			"cap": JwFormat.qty(int(row["capacity"]), JwText.t("sector.unit.%d" % sector))}),
			"caption", "text.muted"))
	line.add_child(JwUi.spacer())
	if int(row["frozen_ppm"]) > 0:
		line.add_child(JwUi.label(JwText.render("ind.stacks.frozen", {
				"pct": JwFormat.pct(int(row["frozen_ppm"]))}), "caption", "ochre.core"))
		return line
	for mth: int in _methods_for(int(row["type"])):
		if mth == int(row["method"]):
			continue
		var rb: Button = JwUi.button(JwText.render("ind.stacks.retrofit", {
				"method": session.catalog.method_label(mth)}))
		JwUi.tag(rb, "Retrofit_%d_%d" % [b, mth])
		var ent: int = int(row["entity"])
		var mm: int = mth
		var tt: int = int(row["type"])
		rb.pressed.connect(func() -> void:
			session.add_draft(session.draft_retrofit(ent, mm,
					session.catalog.building_label(tt), session.catalog.method_label(mm),
					session.model.at("content.method.retrofit_cost_uu", mm))))
		line.add_child(rb)
	return line


## 某建筑类型下、已解锁且有改造工程的生产方式。
func _methods_for(bt: int) -> PackedInt64Array:
	var m: JwReadModel = session.model
	var out: PackedInt64Array = PackedInt64Array()
	var done: int = m.sc("state.research.completed_mask")
	for mth: int in range(1, m.sc("content.method.count")):
		if m.at("content.method.building", mth) != bt:
			continue
		if m.at("content.method.retrofit_cost_uu", mth) <= 0:
			continue
		if _method_unlocked(mth, done):
			out.append(mth)
	return out


func _method_unlocked(mth: int, completed_mask: int) -> bool:
	var techs: Array[Dictionary] = session.catalog.technologies
	for t: int in techs.size():
		if (completed_mask >> t) & 1 == 0:
			continue
		for u: Variant in techs[t].get("unlocks", {}).get("methods", []):
			if _method_index_of(String(u)) == mth:
				return true
	return false


func _method_index_of(method_id: String) -> int:
	var arr: Array[Dictionary] = session.catalog.methods
	for i: int in arr.size():
		if String(arr[i].get("method_id", "")) == method_id:
			return i + 1
	return -1


# ── ④ 贸易伙伴 ──────────────────────────────────────────────────────────

func _trade_block() -> Control:
	var m: JwReadModel = session.model
	var pair: Array = _block("TradeBlock", "ind.trade.title")
	var box: VBoxContainer = pair[1]
	var n: int = m.sc("content.partner.count")
	if n <= 0:
		box.add_child(JwUi.label(JwText.t("ind.trade.none"), "body", "text.muted", true))
		return pair[0]
	for p: int in n:
		var line: VBoxContainer = JwUi.vbox(3)
		JwUi.tag(line, "Partner_%d" % p)
		line.add_child(JwUi.label(session.catalog.partner_label(p), "body_bold"))
		line.add_child(JwUi.label(JwText.render("ind.trade.shares", {
				"export": JwFormat.pct(m.at("state.partner.export_share_ppm", p)),
				"import": JwFormat.pct(m.at("state.partner.import_share_ppm", p)),
				"price": JwFormat.ratio(m.at("state.partner.price_mult_ppm", p)),
				"relation": JwFormat.pct(m.at("state.partner.relation_ppm", p)),
				"balance": JwFormat.u(m.at("state.partner.balance_uu", p))}),
				"caption", "text.secondary", true))
		var acts: HBoxContainer = JwUi.hbox(8)
		for mode: int in 3:
			for up: int in 2:
				if mode == 2 and up == 0:
					continue
				var b: Button = JwUi.button(JwText.t("ind.trade.btn.%d.%d" % [mode, up]))
				JwUi.tag(b, "Trade_%d_%d_%d" % [p, mode, up])
				var pp: int = p
				var mm: int = mode
				var uu: int = up
				b.pressed.connect(func() -> void:
					session.add_draft(session.draft_trade(pp, mm, uu, session.catalog.partner_label(pp))))
				acts.add_child(b)
		line.add_child(acts)
		box.add_child(line)
	return pair[0]
