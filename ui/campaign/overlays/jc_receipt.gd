## 季报：这一季（或快进的这几季）发生了什么——几个大数的变化、大事、托管替你办的事、民间新开的买卖。
## 只有大事时才弹出；平常季度只在底部提示一行（JcReceipt.summary）。
class_name JcReceipt
extends JcOverlay

## 这些纪事算「大事」，出现了才弹出季报
const NOTABLE: PackedStringArray = ["chron.era_enter", "chron.world_era", "chron.crisis_up", "chron.crisis_down",
		"chron.game_over", "chron.tech_done", "chron.landmark_done", "chron.partner_appear", "chron.event_fired",
		"chron.campaign_end", "chron.granary_release"]
## 这些在季报里单独列、不算大事
const ROUTINE: PackedStringArray = ["chron.build_done", "chron.upgrade_done", "chron.private_build", "chron.private_close",
		"chron.private_upgrade", "chron.private_switch", "chron.private_fallback"]


static func is_notable(receipt: Dictionary) -> bool:
	for e: Dictionary in receipt.get("notes", []):
		if NOTABLE.has(String(e.get("key", ""))):
			return true
	return String(receipt.get("stop", "")) != "" and String(receipt.get("stop", "")) != "over"


## 平常季度的一行提示：日期 + 国库变化 + 民间新开几处。
static func summary(g: JCGame, receipt: Dictionary) -> String:
	var before: Dictionary = receipt.get("before", {})
	var d_tr: int = g.st.treasury - int(before.get("treasury", g.st.treasury))
	var n_new: int = 0
	var n_done: int = 0
	for e: Dictionary in receipt.get("notes", []):
		var k: String = String(e.get("key", ""))
		if k == "chron.private_build":
			n_new += 1
		elif k == "chron.build_done" or k == "chron.upgrade_done":
			n_done += 1
	var s: String = JwText.render("jc.rcpt.toast", {"date": JcFmt.date(g.st.q, g.st.start_year),
			"treasury": JcFmt.money_signed(d_tr)})
	if n_done > 0:
		s += JwText.render("jc.rcpt.toast_done", {"n": str(n_done)})
	if n_new > 0:
		s += JwText.render("jc.rcpt.toast_new", {"n": str(n_new)})
	return s


func build() -> void:
	width_ratio = 0.56
	height_ratio = 0.8
	var g: JCGame = game()
	var q0: int = int(ctx.get("q_from", g.st.q))
	var q1: int = int(ctx.get("q_to", g.st.q))
	var turns: int = maxi(1, q1 - q0)
	if turns > 1:
		set_title(rt("jc.rcpt.title_ff", {"from": JcFmt.date(q0, g.st.start_year), "to": JcFmt.date(q1, g.st.start_year)}))
	else:
		set_title(rt("jc.rcpt.title", {"date": JcFmt.date(q0, g.st.start_year)}))
	var stop: String = String(ctx.get("stop", ""))
	if stop != "":
		body.add_child(JwUi.para(t("jc.rcpt.stop." + stop), JcUi.WARN))
	# 大数的变化
	var before: Dictionary = ctx.get("before", {})
	var now: Dictionary = g.status()
	if not before.is_empty():
		var tiles: HBoxContainer = JwUi.hbox(10)
		# 四个大数各配图标，变化那一行配涨跌箭头
		var d_tr: int = int(now["treasury"]) - int(before["treasury"])
		tiles.add_child(JcUi.tile(t("jc.ov.treasury"), JcFmt.money(int(now["treasury"])), JcFmt.money_signed(d_tr),
				JcUi.tone(d_tr >= 0), "", JcUi.UI_ICON % "stat_treasury", JcUi.trend_icon(int(now["treasury"]), int(before["treasury"]))))
		var d_liv: int = int(now["living"]) - int(before["living"])
		tiles.add_child(JcUi.tile(t("jc.ov.living"), JcFmt.pct(int(now["living"]), 0), JcFmt.pct_signed(d_liv),
				JcUi.tone(d_liv >= 0, d_liv > -20_000), "", JcUi.UI_ICON % "stat_living",
				JcUi.trend_icon(int(now["living"]), int(before["living"]))))
		var d_leg: int = int(now["legitimacy"]) - int(before["legitimacy"])
		tiles.add_child(JcUi.tile(t("jc.ov.legit"), JcFmt.pct(int(now["legitimacy"]), 0), JcFmt.pct_signed(d_leg),
				JcUi.tone(d_leg >= 0, d_leg > -20_000), "", JcUi.UI_ICON % "stat_legitimacy",
				JcUi.trend_icon(int(now["legitimacy"]), int(before["legitimacy"]))))
		var d_pop: int = int(now["pop"]) - int(before["pop"])
		tiles.add_child(JcUi.tile(t("jc.ov.pop"), JcFmt.people(int(now["pop"])), ("+" if d_pop >= 0 else "") + JcFmt.people(d_pop),
				JcUi.MUTED, "", JcUi.UI_ICON % "stat_pop", JcUi.trend_icon(int(now["pop"]), int(before["pop"]))))
		body.add_child(tiles)
	# 大事
	var notes: Array = ctx.get("notes", [])
	var big: Array = []
	var routine: Array = []
	for e: Dictionary in notes:
		var k: String = String(e.get("key", ""))
		if NOTABLE.has(k):
			big.append(e)
		elif ROUTINE.has(k):
			routine.append(e)
	if not big.is_empty():
		body.add_child(JwUi.label(t("jc.rcpt.big"), "title_sub", "text.primary"))
		for e2: Dictionary in big:
			var k2: String = String(e2["key"])
			var tok: String = JcUi.BAD if k2 == "chron.crisis_up" or k2 == "chron.game_over" else \
					(JcUi.GOOD if k2 in ["chron.era_enter", "chron.tech_done", "chron.landmark_done", "chron.crisis_down"] else "text.primary")
			body.add_child(JwUi.label("· " + JcFmt.chron(g, e2), "body", tok, true))
	# 托管代办
	var done: Array = ctx.get("steward", [])
	if not done.is_empty():
		body.add_child(JwUi.label(rt("jc.rcpt.steward", {"n": str(done.size())}), "title_sub", "text.primary"))
		for p: Dictionary in done.slice(0, 12):
			body.add_child(JwUi.label("· " + JcFmt.r(String(p["reason"]), JcFmt.slots(g, p.get("slots", {}))), "caption",
					"text.secondary", true))
		if done.size() > 12:
			body.add_child(JwUi.label(rt("jc.rcpt.more", {"n": str(done.size() - 12)}), "caption", "text.muted"))
	# 营造与民间
	if not routine.is_empty():
		body.add_child(JwUi.label(t("jc.rcpt.works"), "title_sub", "text.primary"))
		var shown: int = 0
		for e3: Dictionary in routine:
			if shown >= 10:
				break
			body.add_child(JwUi.label("· " + JcFmt.chron(g, e3), "caption", "text.secondary", true))
			shown += 1
		if routine.size() > shown:
			body.add_child(JwUi.label(rt("jc.rcpt.more", {"n": str(routine.size() - shown)}), "caption", "text.muted"))
	if big.is_empty() and done.is_empty() and routine.is_empty():
		body.add_child(JwUi.para(t("jc.rcpt.quiet"), "text.muted"))
	var h: HBoxContainer = JwUi.hbox(8)
	h.add_child(JwUi.spacer())
	h.add_child(JcUi.button(t("jc.rcpt.ok"), true, close))
	body.add_child(h)
