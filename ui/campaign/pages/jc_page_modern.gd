## 改造中心：时代更替后旧作坊、旧农法的改造——按类型一键「全部改造」、同地区合并改造（七折）、亏本的封存。
class_name JcPageModern
extends JcPage


func refresh() -> void:
	clear()
	if not session.has_game():
		return
	var g: JCGame = game()
	var v: Dictionary = views().modernize()
	content.add_child(JwUi.para(t("jc.mod.intro"), "text.secondary"))
	# 按类型
	var c1: Dictionary = JcUi.card(t("jc.mod.groups"), t("jc.mod.groups_sub"))
	var groups: Array = v["groups"]
	if groups.is_empty():
		(c1["body"] as VBoxContainer).add_child(JwUi.para(t("jc.mod.none"), "text.muted"))
	for gr: Dictionary in groups:
		var row: HBoxContainer = JwUi.hbox(10)
		var txt: String = rt("jc.mod.group", {"building": g.name_of("building", String(gr["building"])),
				"owner": t("jc.owner." + String(gr["owner"])), "count": str(int(gr["count"])), "levels": str(int(gr["levels"])),
				"method": g.name_of("method", String(gr["to"])), "cost": JcFmt.money(int(gr["cost"])),
				"roi": JcFmt.pct(int(gr["roi_ppm"]), 0)})
		row.add_child(JwUi.label(txt, "body", "text.secondary", true))
		var cmd: Dictionary = gr["cmd"]
		var roi: int = int(gr["roi_ppm"])
		row.add_child(JcUi.chip(t("jc.mod.worth") if roi >= 150_000 else t("jc.mod.slow"), JcUi.tone(roi >= 150_000, roi >= 50_000)))
		row.add_child(JcUi.button(t("jc.mod.upgrade_all"), roi >= 150_000, func() -> void: session.order(cmd)))
		(c1["body"] as VBoxContainer).add_child(row)
	content.add_child(c1["root"])
	# 合并
	var c2: Dictionary = JcUi.card(t("jc.mod.merge"), t("jc.mod.merge_sub"))
	var merges: Array = v["merge_groups"]
	if merges.is_empty():
		(c2["body"] as VBoxContainer).add_child(JwUi.para(t("jc.mod.merge_none"), "text.muted"))
	for mg: Dictionary in merges:
		var row2: HBoxContainer = JwUi.hbox(10)
		var regs: PackedStringArray = PackedStringArray()
		for rid: Variant in mg["regions"]:
			regs.append(g.name_of("region", String(rid)))
		row2.add_child(JwUi.label(rt("jc.mod.merge_row", {"building": g.name_of("building", String(mg["building"])),
				"owner": t("jc.owner." + String(mg["owner"])), "regions": t("jc.name_sep").join(regs),
				"count": str(int(mg["stacks"])), "cost": JcFmt.money(int(mg["cost"]))}), "body", "text.secondary", true))
		var cmds: Array = mg["cmds"]
		row2.add_child(JcUi.button(t("jc.mod.merge_do"), false, func() -> void:
			for c: Variant in cmds:
				session.order(c, true)))
		(c2["body"] as VBoxContainer).add_child(row2)
	content.add_child(c2["root"])
	# 逐处
	var c3: Dictionary = JcUi.card(t("jc.mod.each"), t("jc.mod.each_sub"))
	for ob: Dictionary in v["stacks"]:
		var row3: HBoxContainer = JwUi.hbox(10)
		row3.add_child(JwUi.label(rt("jc.mod.each_row", {"building": g.name_of("building", String(ob["building"])),
				"region": g.name_of("region", String(ob["region"])), "from": g.name_of("method", String(ob["from"])),
				"to": g.name_of("method", String(ob["to"])), "levels": str(int(ob["levels"])), "cost": JcFmt.money(int(ob["cost"])),
				"roi": JcFmt.pct(int(ob["roi_ppm"]), 0), "pen": JcFmt.pct(int(ob["penalty_ppm"]), 0)}), "body", "text.secondary", true))
		if not bool(ob.get("labor_ok", true)):
			row3.add_child(JcUi.chip(t("jc.mod.hold_labor"), JcUi.WARN))
		elif not bool(ob.get("room", true)):
			row3.add_child(JcUi.chip(t("jc.mod.hold_busy"), JcUi.MUTED))
		var cmd3: Dictionary = ob["cmd"]
		var ub: Button = JcUi.button(t("jc.mod.upgrade"), false, func() -> void: session.order(cmd3))
		ub.tooltip_text = t("jc.mod.upgrade_tip")
		row3.add_child(ub)
		if int(ob.get("slice", 0)) > 0 and int(ob["slice"]) < int(ob["levels"]):
			var cmd3s: Dictionary = ob["cmd_slice"]
			row3.add_child(JcUi.button(rt("jc.mod.upgrade_part", {"n": str(int(ob["slice"]))}), false, func() -> void:
				session.order(cmd3s)))
		(c3["body"] as VBoxContainer).add_child(row3)
	if (v["stacks"] as Array).is_empty():
		(c3["body"] as VBoxContainer).add_child(JwUi.para(t("jc.mod.none"), "text.muted"))
	content.add_child(c3["root"])
	# 亏本封存
	var losers: Array = v["losers"]
	if not losers.is_empty():
		var c4: Dictionary = JcUi.card(t("jc.mod.losers"), t("jc.mod.losers_sub"))
		for lo: Dictionary in losers:
			var row4: HBoxContainer = JwUi.hbox(10)
			row4.add_child(JwUi.label(rt("jc.mod.loser_row", {"building": g.name_of("building", String(lo["building"])),
					"region": g.name_of("region", String(lo["region"])), "loss": JcFmt.money(int(lo["loss_q"]))}), "body",
					"text.secondary", true))
			var cmd4: Dictionary = lo["cmd"]
			row4.add_child(JcUi.button(t("jc.map.mothball"), false, func() -> void: session.order(cmd4)))
			(c4["body"] as VBoxContainer).add_child(row4)
		content.add_child(c4["root"])
