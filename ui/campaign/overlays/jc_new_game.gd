## 新开一局：一段开场白、种子（可随手换）、开局托管（推荐 / 全部自己来）、继续上次、读档、旧版入口。
class_name JcNewGame
extends JcOverlay

const LEGACY_SCENE: String = "res://ui/main.tscn"

var _seed_edit: LineEdit = null
var _preset: String = "recommended"


func build() -> void:
	width_ratio = 0.56
	height_ratio = 0.84
	set_closable(session.has_game())
	set_title(t("jc.ng.title"))
	var pic: Control = JcUi.art("res://assets/eras/e01/era01_agriculture.png", Vector2(0, 200), true)
	pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(pic)
	body.add_child(JwUi.para(t("jc.ng.intro"), "text.secondary"))
	body.add_child(JwUi.para(t("jc.ng.goal"), "text.muted"))
	# 继续上次
	var saves: Array = JCGame.list_saves()
	if not saves.is_empty():
		var last: Dictionary = saves[0]
		var slot: String = String(last["slot"])
		var cont: Button = JcUi.button(rt("jc.ng.continue", {"date": rt("jc.u.date", {"year": str(int(last["year"])),
				"season": t("jc.u.season.%d" % int(last["season"]))}), "era": JcFmt.era_name(int(last["era"]))}), true, func() -> void:
			if session.load_slot(slot):
				close())
		body.add_child(cont)
		body.add_child(JwUi.hsep())
	# 开局托管
	body.add_child(JwUi.label(t("jc.ng.steward"), "title_sub", "text.primary"))
	var ph: HBoxContainer = JwUi.hbox(8)
	var grp: ButtonGroup = ButtonGroup.new()
	for pid: String in ["recommended", "manual"]:
		var b: Button = JwUi.button(t("jc.ng.preset." + pid), "TabBtn")
		b.toggle_mode = true
		b.button_group = grp
		b.set_pressed_no_signal(_preset == pid)
		b.pressed.connect(func() -> void: _preset = pid)
		ph.add_child(b)
	body.add_child(ph)
	body.add_child(JwUi.label(t("jc.ng.steward_note"), "caption", "text.muted", true))
	# 种子
	var sh: HBoxContainer = JwUi.hbox(8)
	sh.add_child(JwUi.label(t("jc.ng.seed"), "body", "text.secondary"))
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(1 + (Time.get_ticks_usec() % 99_999))
	_seed_edit.custom_minimum_size = Vector2(120, 0)
	_seed_edit.tooltip_text = t("jc.ng.seed_tip")
	sh.add_child(_seed_edit)
	sh.add_child(JcUi.button(t("jc.ng.reroll"), false, func() -> void:
		_seed_edit.text = str(1 + (Time.get_ticks_usec() % 99_999))))
	body.add_child(sh)
	var h: HBoxContainer = JwUi.hbox(10)
	h.add_child(JcUi.button(t("jc.ng.start"), true, _start))
	h.add_child(JcUi.button(t("jc.ng.load"), false, func() -> void:
		if root_ui != null:
			root_ui.call("open_overlay", "saves", {})))
	h.add_child(JwUi.spacer())
	h.add_child(JcUi.link(t("jc.ng.legacy"), func() -> void: get_tree().change_scene_to_file(LEGACY_SCENE)))
	body.add_child(h)
	body.add_child(JwUi.label(t("jc.ng.legacy_note"), "caption", "text.muted", true))


func _start() -> void:
	var sd: int = int(_seed_edit.text) if _seed_edit.text.is_valid_int() else 1
	if not session.new_game(maxi(1, sd)):
		return
	var modes: Dictionary = JcStewardPanel.PRESETS[_preset]
	for d: String in JCSteward.DOMAINS:
		session.game.set_steward(d, int(modes[d]))
	session.changed.emit()
	close()
