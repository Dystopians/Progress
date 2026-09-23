## 事件抉择（docs/18 R-EVENTCHOICE-01；M2 审阅 G1）：列出本季待决的选择型事件与各自的选项。
##
## 选一个选项 = 把该选项预填的普通命令（如果有）连同命令 17「记下选择」一起放进本季草案篮；
## 真正生效仍走确认推进，与其它草案一样可撤回。事件本身没有任何经济效果（INV-130）。
## 批量推进因「有事件需要决定」停下时，外壳自动打开本覆盖层；总览页顶部也有入口。
class_name JwEventChoice
extends JwOverlay


func _init() -> void:
	modal = true
	width_ratio = 0.56
	height_ratio = 0.7


func build() -> void:
	set_title(JwText.t("ev_choice.title"))
	var m: JwReadModel = session.model
	var list: Array[int] = pending_events(session)
	if list.is_empty():
		body.add_child(JwUi.label(JwText.t("ev_choice.none"), "body", "text.muted", true))
		return
	body.add_child(JwUi.label(JwText.t("ev_choice.intro"), "caption", "text.muted", true))
	for e: int in list:
		body.add_child(_event_card(e, m))


func _rebuild() -> void:
	JwUi.clear(body)
	build()


## 本季仍可决定、尚未决定的选择型事件（按事件下标升序）。
static func pending_events(s: JwSession) -> Array[int]:
	var out: Array[int] = []
	if s == null or s.game == null:
		return out
	var m: JwReadModel = s.model
	for e: int in s.catalog.events.size():
		if m.at("content.event.choice_count", e) <= 0:
			continue
		var until: int = m.at("state.event.pending_until_q", e)
		if until < 0 or m.q > until:
			continue
		if m.at("state.event.chosen_option", e) >= 0:
			continue
		out.append(e)
	return out


func _event_card(e: int, m: JwReadModel) -> Control:
	var box: VBoxContainer = JwUi.vbox(6)
	JwUi.tag(box, "EventChoice_%d" % e)
	var ev: Dictionary = session.catalog.events[e] if e < session.catalog.events.size() else {}
	box.add_child(JwUi.label(String(ev.get("label", "E%02d" % (e + 1))), "body_bold"))
	var until: int = m.at("state.event.pending_until_q", e)
	box.add_child(JwUi.label(JwText.render("ev_choice.window", {"q": JwFormat.quarter(until)}),
			"caption", "text.muted"))
	var drafted: int = session.event_choice_drafted(e)
	var choices: Array = session.catalog.event_choices.get(e, [])
	for i: int in choices.size():
		var c: Dictionary = choices[i]
		var row: HBoxContainer = JwUi.hbox(10)
		var b: Button = JwUi.button(String(c.get("label_zh", "")),
				"PrimaryButton" if drafted == i else "")
		JwUi.tag(b, "EventOption_%d_%d" % [e, i])
		b.disabled = drafted >= 0
		var ee: int = e
		var ii: int = i
		b.pressed.connect(func() -> void:
			session.choose_event_option(ee, ii)
			_rebuild())
		row.add_child(b)
		row.add_child(JwUi.label(String(c.get("desc_zh", "")), "caption", "text.secondary", true))
		box.add_child(row)
	if drafted >= 0:
		box.add_child(JwUi.label(JwText.t("ev_choice.drafted"), "caption", "teal.core", true))
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.raised", "line.hair", 1, 12, 10, 12, 10))
	p.add_child(box)
	return p
