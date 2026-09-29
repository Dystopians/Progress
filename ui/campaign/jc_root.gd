## v2 界面根（docs/57 §15）：顶栏（年月、时代、国库、民心、危机、托管、存档、结束本季）、
## 页签、页面区、右侧栏（顾问、托管拟办、本季命令），覆盖层与提示条。
## 界面只经 JcSession → JCGame 读视图与下命令；玩家可见的中文只在 ui/text/zh_cn/jc_*.json。
## 命令行：--jc-seed=<种子> 直接开局；--jc-load=<存档名> 读档；--jc-play=<脚本> [--jc-until=1700] 按脚本快进；
## 任何 --jw- 参数转去旧版主场景（res://ui/main.tscn）。
class_name JcRoot
extends Control

const PAGES: PackedStringArray = ["overview", "map", "industry", "modern", "tech", "policy", "society", "trade", "chronicle"]

var session: JcSession = null
var pages: Dictionary = {}
var current: String = "overview"
var top_bar: JcTopBar = null
var rail: JcRail = null
var page_stack: Control = null
var overlay_layer: Control = null
var toast_box: PanelContainer = null
var toast_label: Label = null
var overlays: Array[JcOverlay] = []
var _tabs: Dictionary = {}
var _refresh_queued: bool = false
var _toast_t: float = 0.0
var _last_era: int = 1
var _last_world: int = 1


const LEGACY_SCENE: String = "res://ui/main.tscn"


func _ready() -> void:
	# 旧版（1600—1700 经纬）的命令行参数都以 --jw- 开头：交给旧版主场景
	for a: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--jw-"):
			get_tree().call_deferred("change_scene_to_file", LEGACY_SCENE)
			return
	theme = JwTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = JwTheme.c("bg.base")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	session = JcSession.new()
	session.name = "Session"
	add_child(session)
	session.changed.connect(_queue_refresh)
	session.turn_done.connect(_on_turn_done)
	session.toast.connect(show_toast)
	session.game_started.connect(_on_game_started)
	_build_shell()
	set_process(true)
	_boot()


func _boot() -> void:
	var seed_arg: String = _arg("--jc-seed=")
	var load_arg: String = _arg("--jc-load=")
	var play_arg: String = _arg("--jc-play=")
	if play_arg != "":
		var ps: JCPlayscript = JCPlayscript.from_file(play_arg)
		var g: JCGame = JCGame.new()
		if g.new_game(int(ps.data.get("seed", 1))) and ps.bind(g):
			var until_s: String = _arg("--jc-until=")
			var target: int = JCPlayscript.parse_q(until_s, g.st.start_year) if until_s != "" else ps.until_q(g)
			ps.step(g, target)
			g.autosave = true
			session.game = g
			_on_game_started()
			_queue_refresh()
			return
	if load_arg != "" and session.load_slot(load_arg):
		return
	if seed_arg.is_valid_int() and session.new_game(int(seed_arg)):
		return
	open_overlay("newgame", {})


static func _arg(prefix: String) -> String:
	for a: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


func _build_shell() -> void:
	var shell: VBoxContainer = JwUi.vbox(0)
	shell.name = "Shell"
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shell)
	top_bar = JcTopBar.new()
	top_bar.setup(session, self)
	shell.add_child(top_bar)
	var tabs: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.panel", "", 0, 12, 0, 12, 0))
	tabs.custom_minimum_size = Vector2(0, 44)
	var th: HBoxContainer = JwUi.hbox(2)
	tabs.add_child(th)
	var group: ButtonGroup = ButtonGroup.new()
	for id: String in PAGES:
		var b: Button = JwUi.button(JwText.t("jc.tab." + id), "TabBtn")
		b.toggle_mode = true
		b.button_group = group
		b.name = "Tab_" + id
		b.pressed.connect(func() -> void: show_page(id))
		th.add_child(b)
		_tabs[id] = b
	shell.add_child(tabs)
	var main: HBoxContainer = JwUi.hbox(0)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(main)
	page_stack = Control.new()
	page_stack.name = "PageStack"
	page_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(page_stack)
	var classes: Dictionary = {"overview": JcPageOverview, "map": JcPageMap, "industry": JcPageIndustry,
			"modern": JcPageModern, "tech": JcPageTech, "policy": JcPagePolicy, "society": JcPageSociety,
			"trade": JcPageTrade, "chronicle": JcPageChronicle}
	for id2: String in PAGES:
		var pg: JcPage = (classes[id2] as GDScript).new() as JcPage
		pg.setup(session, self, id2)
		pg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pg.visible = false
		page_stack.add_child(pg)
		pages[id2] = pg
	rail = JcRail.new()
	rail.setup(session, self)
	main.add_child(rail)
	overlay_layer = Control.new()
	overlay_layer.name = "OverlayLayer"
	overlay_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_layer)
	toast_box = JwUi.panel_style(JwTheme.box4("bg.raised", "line.strong", 1, 16, 8, 16, 8))
	toast_box.name = "Toast"
	toast_label = JwUi.label("", "body", "text.primary")
	toast_box.add_child(toast_label)
	toast_box.visible = false
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_box)
	show_page("overview")


func show_page(id: String) -> void:
	if not pages.has(id):
		return
	current = id
	for k: String in PAGES:
		(pages[k] as JcPage).visible = k == id
		(_tabs[k] as Button).set_pressed_no_signal(k == id)
	if session.has_game():
		(pages[id] as JcPage).refresh()


func page(id: String) -> JcPage:
	return pages.get(id, null)


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("refresh_all")


func refresh_all() -> void:
	_refresh_queued = false
	if not session.has_game():
		return
	top_bar.refresh()
	rail.refresh()
	var pg: JcPage = pages.get(current, null)
	if pg != null:
		pg.refresh()
	for o: JcOverlay in overlays:
		o.on_changed()


func _on_game_started() -> void:
	_last_era = session.game.st.era
	_last_world = session.game.st.world_era
	close_all_overlays()
	show_page("overview")
	_queue_refresh()


func _on_turn_done(receipt: Dictionary) -> void:
	if not session.has_game():
		return
	var st: JCState = session.game.st
	if st.over == 1:
		open_overlay("gameover", {})
		return
	if st.era != _last_era:
		open_overlay("era", {"kind": "nation", "era": st.era})
		_last_era = st.era
	elif st.world_era != _last_world:
		open_overlay("era", {"kind": "world", "era": st.world_era})
	_last_world = st.world_era
	if not st.pend.is_empty() and int(session.game.steward.mode["events"]) != JCSteward.AUTO:
		open_overlay("event", {})
	elif not receipt.is_empty():
		if JcReceipt.is_notable(receipt):
			open_overlay("receipt", receipt)
		else:
			show_toast(JcReceipt.summary(session.game, receipt), false)


# ── 覆盖层 ─────────────────────────────────────────────────────────────
func open_overlay(id: String, context: Dictionary = {}) -> JcOverlay:
	var o: JcOverlay = null
	match id:
		"newgame":
			o = JcNewGame.new()
		"steward":
			o = JcStewardPanel.new()
		"advisors":
			o = JcAdvisorPanel.new()
		"event":
			o = JcEventOverlay.new()
		"era":
			o = JcEraOverlay.new()
		"build":
			o = JcBuildDialog.new()
		"receipt":
			o = JcReceipt.new()
		"help":
			o = JcHelp.new()
		"saves":
			o = JcSaves.new()
		"gameover":
			o = JcGameOver.new()
		_:
			return null
	overlay_layer.add_child(o)
	o.setup(session, self, id, context)
	o.closed.connect(_on_overlay_closed)
	overlays.append(o)
	return o


func _on_overlay_closed(o: JcOverlay) -> void:
	overlays.erase(o)
	if is_instance_valid(o):
		o.queue_free()
	_queue_refresh()


func close_all_overlays() -> void:
	for o: JcOverlay in overlays.duplicate():
		o.close()


func has_overlay(id: String) -> bool:
	for o: JcOverlay in overlays:
		if o.overlay_id == id:
			return true
	return false


# ── 提示条 ─────────────────────────────────────────────────────────────
func show_toast(text: String, bad: bool) -> void:
	if text == "":
		return
	toast_label.text = text
	toast_label.add_theme_color_override("font_color", JwTheme.c("ochre.hot" if bad else "text.primary"))
	toast_box.visible = true
	toast_box.reset_size()
	toast_box.position = Vector2((size.x - toast_box.size.x) * 0.5, size.y - toast_box.size.y - 28)
	_toast_t = 3.2


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			toast_box.visible = false


# ── 快捷键：数字键切页、Ctrl+Z 撤回、Ctrl+Enter 结束本季 ───────────────
func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var k: InputEventKey = event
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or focus is SpinBox:
		return
	if not overlays.is_empty():
		return
	if k.ctrl_pressed and k.keycode == KEY_Z:
		get_viewport().set_input_as_handled()
		session.undo()
		return
	if k.ctrl_pressed and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		session.end_turn()
		return
	if k.ctrl_pressed or k.alt_pressed:
		return
	var idx: int = k.keycode - KEY_1
	if idx >= 0 and idx < PAGES.size():
		get_viewport().set_input_as_handled()
		show_page(PAGES[idx])
