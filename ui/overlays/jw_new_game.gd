## 开始执政（开局覆盖层）：剧本简介、种子、任期目标（可不选）、界面缩放、读档入口。
class_name JwNewGame
extends JwOverlay

var _seed_edit: LineEdit = null
var _goal: int = -1
var _goal_buttons: Array[Button] = []
## 选中的剧本目录名（R-SCENARIO-01）；空串 = 沿用会话当前剧本。
var _scenario: String = ""


func _init() -> void:
	modal = true
	width_ratio = 0.6
	height_ratio = 0.8


func build() -> void:
	set_title(JwText.t("ng.title"))
	var list: Array[Dictionary] = JwCatalog.list_scenarios()
	if list.size() > 1:
		var rh: HBoxContainer = JwUi.hbox(10)
		rh.add_child(JwUi.label(JwText.t("ng.scenario"), "body", "text.secondary"))
		var so: OptionButton = OptionButton.new()
		so.name = "ScenarioOption"
		for i: int in list.size():
			so.add_item(String(list[i]["label"]), i)
			if String(list[i]["name"]) == session.catalog.scenario_name:
				so.select(i)
		so.item_selected.connect(func(i: int) -> void:
			_scenario = String(list[i]["name"])
			session.use_scenario(_scenario)
			for c: Node in body.get_children():
				body.remove_child(c)
				c.queue_free()
			_goal_buttons.clear()
			build())
		rh.add_child(so)
		body.add_child(rh)
	body.add_child(JwUi.label(JwText.render("ng.country", {"country": session.catalog.country_label()}), "title_page"))
	var hq: int = session.catalog.horizon_q()
	@warning_ignore("integer_division")
	var years: int = hq / 4
	if session.catalog.scenario_mode() == 1:
		body.add_child(JwUi.para(JwText.render("ng.intro_campaign", {"start_year": str(session.catalog.start_year()),
				"end_year": str(session.catalog.start_year() + years), "years": str(years)}), "text.secondary"))
	else:
		body.add_child(JwUi.para(JwText.render("ng.intro", {"quarters": str(hq), "years": str(years)}), "text.secondary"))
	body.add_child(JwUi.para(JwText.t("ng.disclaimer"), "text.muted"))
	var sh: HBoxContainer = JwUi.hbox(10)
	sh.add_child(JwUi.label(JwText.t("ng.seed"), "body", "text.secondary"))
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(Time.get_ticks_usec() % 1_000_000 + 1)
	_seed_edit.custom_minimum_size = Vector2(200, 34)
	sh.add_child(_seed_edit)
	sh.add_child(JwUi.label(JwText.t("ng.seed_note"), "caption", "text.muted", true))
	body.add_child(sh)
	body.add_child(JwUi.label(JwText.t("ng.goal"), "title_sub"))
	var gh: HBoxContainer = JwUi.hbox(10)
	for g: int in 3:
		var b: Button = JwUi.button(JwText.t("mandate_goal.%d" % g))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(160, 38)
		var gg: int = g
		b.pressed.connect(func() -> void:
			_goal = gg if b.button_pressed else -1
			for i: int in _goal_buttons.size():
				_goal_buttons[i].set_pressed_no_signal(i == _goal))
		_goal_buttons.append(b)
		gh.add_child(b)
	body.add_child(gh)
	body.add_child(JwUi.para(JwText.t("ng.goal_note"), "text.muted"))
	var sc: HBoxContainer = JwUi.hbox(10)
	sc.add_child(JwUi.label(JwText.t("ng.scale"), "body", "text.secondary"))
	var ob: OptionButton = OptionButton.new()
	var steps: Array[float] = [1.0, 1.25, 1.5]
	for i2: int in steps.size():
		ob.add_item(JwText.t("ng.scale.%d" % i2), i2)
	var cur: float = 1.0
	if root_ui != null and "ui_scale" in root_ui:
		cur = float(root_ui.get("ui_scale"))
	ob.select(clampi(steps.find(cur), 0, 2))
	ob.item_selected.connect(func(i: int) -> void:
		JwScale.save_scale(steps[i])
		var w: Window = get_window()
		if w != null and root_ui != null and root_ui.get_parent() == get_tree().root:
			w.content_scale_factor = steps[i]
			root_ui.set("ui_scale", steps[i]))
	sc.add_child(ob)
	sc.add_child(JwUi.label(JwText.t("ng.scale_note"), "caption", "text.muted", true))
	body.add_child(sc)
	var ah: HBoxContainer = JwUi.hbox(12)
	var start: Button = JwUi.button(JwText.t("ng.start"), "PrimaryButton")
	start.name = "StartButton"
	start.custom_minimum_size = Vector2(200, 44)
	start.pressed.connect(_start)
	ah.add_child(start)
	var load_b: Button = JwUi.button(JwText.t("ng.load"))
	load_b.pressed.connect(func() -> void:
		if root_ui != null:
			root_ui.call("open_overlay", "saves", {}))
	ah.add_child(load_b)
	body.add_child(ah)


func _start() -> void:
	var seed_v: int = _seed_edit.text.to_int() if _seed_edit.text.is_valid_int() else 1
	if seed_v == 0:
		seed_v = 1
	var r: Dictionary = session.start_new(seed_v, _goal, _scenario)
	if bool(r.get("ok", false)):
		close()
		if root_ui != null:
			root_ui.call("show_page", "overview", {})
	else:
		body.add_child(JwUi.label(JwText.render("ng.fail", {"code": str(int(r.get("code", 0)))}), "body_bold", "ochre.core"))
