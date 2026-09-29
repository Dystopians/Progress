## 科技：按时代分栏的卡片——价钱、进度、还要几季、国内外基础的加速、是不是下一时代要的；点一下定为研究方向。
class_name JcPageTech
extends JcPage


func refresh() -> void:
	clear()
	if not session.has_game():
		return
	var g: JCGame = game()
	var v: Dictionary = views().techs()
	var head: HBoxContainer = JwUi.hbox(12)
	head.add_child(JwUi.label(rt("jc.tech.points", {"n": str(int(v["points"]))}), "body_bold", "text.primary"))
	var fid: String = String(v["focus"])
	head.add_child(JwUi.label(rt("jc.tech.focus", {"tech": g.name_of("tech", fid)}) if fid != "" else t("jc.tech.no_focus"),
			"body", JcUi.GOOD if fid != "" else JcUi.BAD))
	content.add_child(head)
	content.add_child(JwUi.para(t("jc.tech.intro"), "text.muted"))
	var cols: HBoxContainer = JwUi.hbox(12)
	for era: int in range(1, 5):
		var col: VBoxContainer = JwUi.vbox(8)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(JwUi.label(rt("jc.tech.era_col", {"era": JcFmt.era_name(era)}), "title_sub",
				"text.primary" if era <= int(v["era"]) + 1 else "text.muted"))
		# 本时代与下一时代的写全；更远的只列名字与前置，免得一屏全是字
		var far: bool = era > int(v["era"]) + 1
		if far:
			col.add_child(JwUi.label(t("jc.tech.far"), "caption", "text.muted", true))
		for tv: Dictionary in v["list"]:
			if int(tv["era"]) != era:
				continue
			col.add_child(_compact(g, tv) if far else _card(g, tv, int(v["points"])))
		cols.add_child(col)
	content.add_child(cols)


func _compact(g: JCGame, tv: Dictionary) -> Control:
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.panel", "line.hair", 3, 6))
	var v: VBoxContainer = JwUi.vbox(0)
	p.add_child(v)
	v.add_child(JwUi.label(String(tv["name"]), "body", "text.muted"))
	if not (tv["prereq"] as Array).is_empty():
		var names: PackedStringArray = PackedStringArray()
		for pid: Variant in tv["prereq"]:
			names.append(g.name_of("tech", String(pid)))
		v.add_child(JwUi.label(rt("jc.tech.needs", {"list": t("jc.name_sep").join(names)}), "caption", "text.muted", true))
	p.tooltip_text = String(tv["desc"])
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _card(g: JCGame, tv: Dictionary, points: int) -> Control:
	var done: bool = bool(tv["done"])
	var avail: bool = bool(tv["available"])
	var focus: bool = bool(tv["focus"])
	var rule: String = JcUi.GOOD if done else (JcUi.WARN if focus else ("line.strong" if avail else "line.hair"))
	var p: PanelContainer = JwUi.panel_style(JwTheme.box_left_rule("bg.raised" if avail or focus else "bg.panel", rule, 4, 10))
	var v: VBoxContainer = JwUi.vbox(4)
	p.add_child(v)
	var h: HBoxContainer = JwUi.hbox(6)
	h.add_child(JwUi.label(String(tv["name"]), "body_bold", "text.primary" if avail or done else "text.muted"))
	if bool(tv["era_key"]) and not done:
		h.add_child(JcUi.chip(t("jc.tech.key"), JcUi.WARN))
	v.add_child(h)
	v.add_child(JwUi.label(String(tv["desc"]), "caption", "text.secondary", true))
	if done:
		v.add_child(JwUi.label(t("jc.tech.done"), "caption", JcUi.GOOD))
		return p
	var cost: int = int(tv["cost"])
	var prog: int = int(tv["progress"])
	v.add_child(JcUi.meter(JCMath.ratio_ppm(prog, maxi(1, cost)), JcUi.GOOD, 200.0, 6.0))
	var left_s: String = str(maxi(0, cost - prog))
	var info: String = rt("jc.tech.cost", {"left": left_s, "eta": JcFmt.quarters(int(tv["eta_q"]))}) if points > 0 \
			else rt("jc.tech.cost_idle", {"left": left_s})
	var bg: int = int(tv["bg_domestic"]) + int(tv["bg_foreign"])
	if bg > 0:
		info += rt("jc.tech.speed", {"v": JcFmt.pct(bg, 0)})
	v.add_child(JwUi.label(info, "caption", "text.muted", true))
	if not (tv["prereq"] as Array).is_empty() and not avail:
		var names: PackedStringArray = PackedStringArray()
		for pid: Variant in tv["prereq"]:
			names.append(g.name_of("tech", String(pid)))
		v.add_child(JwUi.label(rt("jc.tech.needs", {"list": t("jc.name_sep").join(names)}), "caption", JcUi.WARN, true))
	if avail and not focus:
		var id: String = String(tv["id"])
		var pb: Button = JcUi.button(t("jc.tech.pick"), bool(tv["era_key"]), func() -> void:
			session.order({"kind": "research", "tech": id}, true))
		pb.size_flags_horizontal = Control.SIZE_SHRINK_END
		v.add_child(pb)
	elif focus:
		v.add_child(JwUi.label(t("jc.tech.researching"), "caption", JcUi.WARN))
	return p
