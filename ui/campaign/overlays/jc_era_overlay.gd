## 时代：本国跨入新时代（章节画面 + 这一时代带来什么 + 去改造中心）、世界进入新时代（期望上升、旧法贬值），
## 以及「时代与地标」总览（四个时代的先后、可建的地标）。ctx.kind = nation | world | book。
class_name JcEraOverlay
extends JcOverlay


func build() -> void:
	var kind: String = String(ctx.get("kind", "book"))
	match kind:
		"nation", "world":
			width_ratio = 0.6
			_chapter(kind, int(ctx.get("era", game().st.era)))
		_:
			_book()


func _era_dict(e: int) -> Dictionary:
	for ed: Dictionary in session.views().eras()["eras"]:
		if int(ed["id"]) == e:
			return ed
	return {}


func _chapter(kind: String, e: int) -> void:
	var g: JCGame = game()
	var ed: Dictionary = _era_dict(e)
	set_title(rt("jc.era_ov.title_" + kind, {"era": JcFmt.era_name(e)}))
	var art: String = String(ed.get("art", ""))
	if art != "" and not art.begins_with("res://"):
		art = "res://" + art
	var pic: Control = JcUi.art(art, Vector2(0, 280), true)
	pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(pic)
	body.add_child(JwUi.title(String(ed.get("name", JcFmt.era_name(e))), "title_page"))
	if String(ed.get("subtitle", "")) != "":
		body.add_child(JwUi.label(String(ed["subtitle"]), "body", "text.muted", true))
	body.add_child(JwUi.para(t("jc.era_ov.body_%s.%d" % [kind, e]), "text.secondary"))
	if kind == "nation":
		# 新东西
		var newb: PackedStringArray = PackedStringArray()
		for cv: Dictionary in session.views().catalog():
			var any_new: bool = false
			for mv: Dictionary in cv["methods"]:
				if int(mv["era"]) == e:
					any_new = true
			if any_new:
				newb.append(String(cv["name"]))
		if not newb.is_empty():
			body.add_child(JwUi.label(t("jc.era_ov.new_buildings"), "body_bold", "text.primary"))
			body.add_child(JwUi.label(t("jc.name_sep").join(newb), "body", "text.secondary", true))
		var mod: Dictionary = session.views().modernize()
		var n_old: int = (mod["stacks"] as Array).size()
		if n_old > 0:
			body.add_child(JwUi.para(rt("jc.era_ov.old", {"n": str(n_old)}), JcUi.WARN))
		var h: HBoxContainer = JwUi.hbox(10)
		h.add_child(JcUi.button(t("jc.era_ov.go_modern"), true, func() -> void:
			close()
			_goto("modern")))
		h.add_child(JcUi.button(t("jc.era_ov.go_book"), false, func() -> void:
			close()
			if root_ui != null:
				root_ui.call("open_overlay", "era", {"kind": "book"})))
		h.add_child(JwUi.spacer())
		h.add_child(JcUi.button(t("jc.era_ov.ok"), false, close))
		body.add_child(h)
	else:
		var st: JCState = g.st
		body.add_child(JwUi.para(rt("jc.era_ov.world_gap", {"ours": JcFmt.era_name(st.era), "world": JcFmt.era_name(e)}),
				JcUi.tone(st.era >= e, st.era + 1 >= e)))
		var h2: HBoxContainer = JwUi.hbox(10)
		h2.add_child(JcUi.button(t("jc.era_ov.go_tech"), true, func() -> void:
			close()
			_goto("tech")))
		h2.add_child(JwUi.spacer())
		h2.add_child(JcUi.button(t("jc.era_ov.ok"), false, close))
		body.add_child(h2)


func _goto(page_id: String) -> void:
	if root_ui != null and root_ui.has_method("show_page"):
		root_ui.call("show_page", page_id)


func _book() -> void:
	var g: JCGame = game()
	var v: Dictionary = session.views().eras()
	set_title(t("jc.era_ov.book"))
	# 四个时代
	var row: HBoxContainer = JwUi.hbox(10)
	for ed: Dictionary in v["eras"]:
		var e: int = int(ed["id"])
		var reached: bool = int(ed["reached_q"]) >= 0 or e == 1
		var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised" if reached else "bg.panel",
				JcUi.GOOD if reached else "line.hair", 4, 10))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vb: VBoxContainer = JwUi.vbox(4)
		p.add_child(vb)
		vb.add_child(JwUi.label(String(ed["name"]), "body_bold", "text.primary" if reached else "text.muted"))
		vb.add_child(JwUi.label(String(ed["subtitle"]), "caption", "text.muted", true))
		var ours: String = JcFmt.date(int(ed["reached_q"]), g.st.start_year) if int(ed["reached_q"]) >= 0 else t("jc.era_ov.not_yet")
		var world: String = JcFmt.date(int(ed["world_q"]), g.st.start_year) if int(ed["world_q"]) >= 0 else t("jc.era_ov.not_yet")
		if e == 1:
			ours = t("jc.era_ov.from_start")
			world = ours
		vb.add_child(JwUi.label(rt("jc.era_ov.when", {"ours": ours, "world": world}), "caption", "text.secondary", true))
		if bool(ed["led"]):
			vb.add_child(JcUi.chip(t("jc.era_ov.led"), JcUi.GOOD))
		row.add_child(p)
	body.add_child(row)
	body.add_child(JwUi.para(t("jc.era_ov.landmark_intro"), "text.muted"))
	# 地标
	var cap_r: String = ""
	for rv: Dictionary in session.views().regions():
		if bool(rv["capital"]):
			cap_r = String(rv["id"])
	var reg: String = session.selected_region if session.selected_region != "" else cap_r
	var gr: GridContainer = JcUi.grid(2, 12, 12)
	for lm: Dictionary in v["landmarks"]:
		if int(lm["era"]) > int(v["era"]) + 1:
			continue
		gr.add_child(_landmark_box(g, lm, reg))
	body.add_child(gr)


func _landmark_box(g: JCGame, lm: Dictionary, reg: String) -> PanelContainer:
	var state: int = int(lm["state"])
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised", JcUi.GOOD if state >= 2 else
			(JcUi.WARN if state == 1 else "line.strong"), 4, 10))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h: HBoxContainer = JwUi.hbox(10)
	p.add_child(h)
	var art: String = String(lm["art"])
	if art != "" and not art.begins_with("res://"):
		art = "res://" + art
	h.add_child(JcUi.art(art, Vector2(120, 90), true))
	var vb: VBoxContainer = JwUi.vbox(4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vb)
	var hh: HBoxContainer = JwUi.hbox(6)
	hh.add_child(JwUi.label(String(lm["name"]), "body_bold", "text.primary"))
	hh.add_child(JcUi.chip(JcFmt.era_name(int(lm["era"])), JcUi.MUTED))
	vb.add_child(hh)
	vb.add_child(JwUi.label(String(lm["desc"]), "caption", "text.secondary", true))
	var id: String = String(lm["id"])
	match state:
		2, 3:
			vb.add_child(JwUi.label(rt("jc.era_ov.lm_done", {"region": g.name_of("region", String(lm["region"]))}), "caption", JcUi.GOOD))
		1:
			vb.add_child(JwUi.label(rt("jc.era_ov.lm_building", {"region": g.name_of("region", String(lm["region"])),
					"left": JcFmt.quarters(maxi(0, int(lm["need_q"]) - int(lm["progress"])))}), "caption", JcUi.WARN))
		_:
			# 只摆出现在就能按的按钮；不能建的只写原因
			var bh: HBoxContainer = JwUi.hbox(6)
			var cost: int = int(lm["cost"])
			if String(lm["kind"]) == "leading":
				if bool(lm["full_ok"]):
					bh.add_child(JcUi.button(rt("jc.era_ov.lm_full", {"cost": JcFmt.money(cost)}), true, func() -> void:
						session.order({"kind": "landmark", "landmark": id, "region": reg, "full": true})))
				if bool(lm["lite_ok"]):
					@warning_ignore("integer_division")
					var lite: int = cost * 6 / 10
					bh.add_child(JcUi.button(rt("jc.era_ov.lm_lite", {"cost": JcFmt.money(lite)}), false, func() -> void:
						session.order({"kind": "landmark", "landmark": id, "region": reg, "full": false})))
			elif bool(lm["lite_ok"]):
				bh.add_child(JcUi.button(rt("jc.era_ov.lm_build", {"cost": JcFmt.money(cost)}), false, func() -> void:
					session.order({"kind": "landmark", "landmark": id, "region": reg, "full": false})))
			if bh.get_child_count() > 0:
				vb.add_child(bh)
			else:
				bh.queue_free()
			if not bool(lm["lite_ok"]):
				vb.add_child(JwUi.label(JcFmt.reason(g, {"reason": String(lm["why"])}), "caption", "text.muted", true))
			else:
				vb.add_child(JwUi.label(rt("jc.era_ov.lm_where", {"region": g.name_of("region", reg)}), "caption", "text.muted"))
	return p
