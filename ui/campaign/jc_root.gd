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
	# 按屏幕缩放（高分屏上字才不会太小）；玩家在「存档」里或用 Ctrl+加号 / 减号 调过的，以玩家的为准
	apply_ui_scale(float(JwScale.resolve()["scale"]))
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
	# 审阅预览：--jc-art-preview=v7（或清单路径）时直接从审核目录读新图，不搬文件
	var pv: String = _arg("--jc-art-preview=")
	if pv != "":
		var n: int = JcUi.preview_load(JcUi.PREVIEW_V7 if pv == "v7" else pv)
		show_toast(JwText.render("jc.preview.on", {"n": str(n)}), false)
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
		JcUi.set_icon(b, JcUi.UI_ICON % ("tab_" + id), 22)
		th.add_child(b)
		_tabs[id] = b
	th.add_child(JwUi.spacer())
	var era_b: HBoxContainer = top_bar.era_box()
	era_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(era_b)
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
	resized.connect(_fit_width)
	_fit_width()
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
	elif session.game.situation_asks() > 0 and int(session.game.steward.mode["events"]) != JCSteward.AUTO:
		open_overlay("situation", {})
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
		"situation":
			o = JcSituationOverlay.new()
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


# ── 快捷键：数字键切页、Ctrl+Z 撤回、Ctrl+Enter 结束本季、F11 切换全屏与窗口 ─────
func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var k: InputEventKey = event
	if k.ctrl_pressed and (k.keycode == KEY_EQUAL or k.keycode == KEY_KP_ADD or k.keycode == KEY_MINUS or k.keycode == KEY_KP_SUBTRACT):
		get_viewport().set_input_as_handled()
		var up: bool = k.keycode == KEY_EQUAL or k.keycode == KEY_KP_ADD
		var steps: PackedFloat64Array = JwScale.STEPS
		var i: int = steps.find(JwScale.snap(get_window().content_scale_factor))
		i = clampi(i + (1 if up else -1), 0, steps.size() - 1)
		set_ui_scale(steps[i])
		return
	if k.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		var w: Window = get_window()
		var full: bool = w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
		w.mode = Window.MODE_MAXIMIZED if full else Window.MODE_FULLSCREEN
		return
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


## 界面大小：Window.content_scale_factor（与旧版同一入口，见 JwScale）。
## 逻辑宽度不到 1500（1920 宽屏开 150%、2560 宽屏开 200% 都是 1280）：右栏收窄、顶栏收紧。
## 各页随页面栈的宽度自己调排版（JcPage.relayout）。
const NARROW_W: float = 1500.0


func _fit_width() -> void:
	if rail == null or top_bar == null:
		return
	var narrow: bool = size.x > 0.0 and size.x < NARROW_W
	rail.custom_minimum_size.x = 300.0 if narrow else 360.0
	top_bar.set_compact(narrow)


func apply_ui_scale(v: float) -> void:
	var win: Window = get_window()
	if win == null:
		return
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.content_scale_factor = minf(JwScale.snap(v), max_ui_scale())


## 屏幕放得下的最大界面大小：放大后的逻辑尺寸至少 1280×720，再大界面就挤坏了。
## 比如 2560×1600 的屏最大 200%，1920×1080 的屏最大 150%。
func max_ui_scale() -> float:
	var win: Window = get_window()
	if win == null or DisplayServer.get_name() == "headless":
		return JwScale.STEPS[JwScale.STEPS.size() - 1]
	var scr: Vector2i = DisplayServer.screen_get_size(win.current_screen)
	if scr.x <= 0 or scr.y <= 0:
		return 1.0
	var fit: float = minf(float(scr.x) / float(JwScale.MIN_LOGICAL.x), float(scr.y) / float(JwScale.MIN_LOGICAL.y))
	var best: float = JwScale.STEPS[0]
	for s: float in JwScale.STEPS:
		if s <= fit + 0.001:
			best = s
	return best


## 玩家调界面大小：立即生效并记下来，下次打开照用（超过屏幕放得下的，按放得下的最大一档）。
func set_ui_scale(v: float) -> void:
	var real: float = minf(JwScale.snap(v), max_ui_scale())
	apply_ui_scale(real)
	JwScale.save_scale(real)
	show_toast(JwText.render("jc.sv.scale_now", {"pct": str(int(round(real * 100.0)))}), false)
