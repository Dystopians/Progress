## 界面根（docs/20 §13.2）：外壳、页面栈、抽屉层、覆盖层与模态层，缩放与断点，全局快捷键。
##
## 分层：界面只经 JwSession → JWGame 读视图与投命令，不直接触碰 SimCore（计划书 §12）。
## 缩放唯一入口：Window.content_scale_factor = ui_scale（项目设置 stretch/mode = disabled，§5.2）；
## 只有作为主场景直接挂在根视口下时才改窗口（截图工具把本节点放进 SubViewport 时不改）。
## 命令行：--ui-scale=1.25 / --window-size=1366x768 / --jw-autostart=<种子> / --jw-goal=<0|1|2>
class_name JwRoot
extends Control

const PAGE_IDS: PackedStringArray = ["overview", "region", "policy", "society", "report"]

var session: JwSession = null
var ui_scale: float = 1.0
var scale_info: Dictionary = {}
var pages: Dictionary = {}
var current_page: String = "overview"
var top_bar: JwTopBar = null
var dock: JwActionDock = null
var body: MarginContainer = null
var page_stack: Control = null
var tabs_box: HBoxContainer = null
var drawer_layer: Control = null
var overlay_layer: Control = null
var modal_layer: Control = null
var notice_bar: PanelContainer = null
var onboarding: JwOnboarding = null
var overlay_stack: Array[JwOverlay] = []
var _tab_buttons: Dictionary = {}
var _refresh_queued: bool = false
var autostart_seed: int = 0
var autostart_goal: int = -1


func _ready() -> void:
	_apply_window_scale()
	build(JwSession.new())
	var seed_arg: String = JwScale.cmd_value("--jw-autostart=")
	var goal_arg: String = JwScale.cmd_value("--jw-goal=")
	if goal_arg.is_valid_int():
		autostart_goal = goal_arg.to_int()
	if seed_arg.is_valid_int():
		autostart_seed = seed_arg.to_int()
	if autostart_seed != 0:
		# R-SCENARIO-01：--jw-scenario=<剧本目录名> 指定开局剧本（缺省沿用当前剧本）。
		session.start_new(autostart_seed, autostart_goal, JwScale.cmd_value("--jw-scenario="))
	else:
		open_overlay("newgame", {})
	_on_resized()
	show_page("overview", {})
	top_bar.refresh()
	dock.refresh()
	# 首帧外壳宽度为 0：换行标签的最小高度按 0 宽计算后，容器不会自动回缩。下一帧重排一次外壳。
	await get_tree().process_frame
	var shell: Container = get_node_or_null("Shell") as Container
	if shell != null:
		shell.queue_sort()


## 构建外壳（不触碰窗口）。_ready 调用它；无场景树的测试也直接调用它。
func build(s: JwSession) -> void:
	theme = JwTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = JwTheme.c("bg.base")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	session = s
	session.name = "Session"
	if session.get_parent() == null:
		add_child(session)
	_build_shell()
	session.state_changed.connect(_on_state_changed)
	session.draft_changed.connect(_queue_refresh)
	session.dryrun_changed.connect(_on_dryrun_changed)
	session.settlement_started.connect(_on_settlement_started)
	session.settlement_finished.connect(_on_settlement_finished)
	session.navigate_requested.connect(show_page)
	session.overlay_requested.connect(func(o: String, c: Dictionary) -> void:
		if o == "ledger":
			open_ledger(String(c.get("ledger", "")), int(c.get("row", 0)))
		else:
			open_overlay(o, c))
	resized.connect(_on_resized)
	onboarding = JwOnboarding.new()
	onboarding.name = "Onboarding"
	add_child(onboarding)
	onboarding.setup(session, self)


func _apply_window_scale() -> void:
	scale_info = JwScale.resolve()
	ui_scale = float(scale_info.get("scale", 1.0))
	if not is_inside_tree() or get_parent() != get_tree().root:
		return
	var win: Window = get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.content_scale_factor = ui_scale
	var ws: String = JwScale.cmd_value("--window-size=")
	if ws != "" and ws.contains("x"):
		var parts: PackedStringArray = ws.split("x")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			win.mode = Window.MODE_WINDOWED
			win.size = Vector2i(parts[0].to_int(), parts[1].to_int())
	# §5.1：min_size = 1280×720 × ui_scale；在 1366×768 叠加 125%/150% 的降级档里夹到屏幕可用区，
	# 此时逻辑尺寸低于 1280×720，由不可关闭的提示条告知并允许主区纵向滚动。
	var usable: Vector2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var want: Vector2i = Vector2i(int(1280.0 * ui_scale), int(720.0 * ui_scale))
	if usable.x > 0 and usable.y > 0:
		want = Vector2i(mini(want.x, usable.x), mini(want.y, usable.y))
	win.min_size = want
	print("[JwRoot] ui_scale=%s source=%s dpi=%s" % [str(ui_scale), str(scale_info.get("source", "")),
			str(scale_info.get("dpi", -1))])


func _build_shell() -> void:
	var shell: VBoxContainer = JwUi.vbox(0)
	shell.name = "Shell"
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shell)
	top_bar = JwTopBar.new()
	top_bar.setup(session, self)
	shell.add_child(top_bar)
	notice_bar = JwUi.panel_style(JwTheme.box4("bg.raised", "ochre.core", 1, 12, 4, 12, 4))
	notice_bar.name = "ScaleNotice"
	var nb: HBoxContainer = JwUi.hbox(8)
	nb.add_child(JwIcon.make("warn", JwTheme.c("ochre.core"), 14))
	var nl: Label = JwUi.label(JwText.t("shell.min_size_notice"), "body", "text.primary", true)
	nl.custom_minimum_size = Vector2(320, 0)
	nb.add_child(nl)
	notice_bar.add_child(nb)
	notice_bar.visible = false
	shell.add_child(notice_bar)
	var tabs: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.panel", "", 0, 12, 0, 12, 0))
	tabs.name = "PageTabs"
	tabs.custom_minimum_size = Vector2(0, JwScale.TABS_H)
	tabs_box = JwUi.hbox(4)
	tabs.add_child(tabs_box)
	var group: ButtonGroup = ButtonGroup.new()
	for id: String in PAGE_IDS:
		var b: Button = JwUi.button(JwText.t("tab." + id), "TabBtn")
		b.toggle_mode = true
		b.button_group = group
		b.name = "Tab_" + id
		b.pressed.connect(func() -> void: show_page(id, {}))
		tabs_box.add_child(b)
		_tab_buttons[id] = b
	shell.add_child(tabs)
	body = MarginContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(body)
	page_stack = Control.new()
	page_stack.name = "PageStack"
	page_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(page_stack)
	var classes: Array = [JwOverviewPage, JwRegionPage, JwPolicyPage, JwSocietyPage, JwReportPage]
	for i: int in PAGE_IDS.size():
		var pg: JwPage = (classes[i] as GDScript).new() as JwPage
		pg.setup(session, self, PAGE_IDS[i])
		pg.set_anchors_preset(Control.PRESET_FULL_RECT)
		pg.visible = false
		page_stack.add_child(pg)
		pages[PAGE_IDS[i]] = pg
	dock = JwActionDock.new()
	dock.setup(session, self)
	shell.add_child(dock)
	drawer_layer = _layer("DrawerLayer")
	overlay_layer = _layer("OverlayLayer")
	modal_layer = _layer("ModalLayer")


func _layer(n: String) -> Control:
	var c: Control = Control.new()
	c.name = n
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


# ── 页面 ───────────────────────────────────────────────────────────────

func show_page(id: String, ctx: Dictionary = {}) -> void:
	if not pages.has(id):
		return
	current_page = id
	for k: String in PAGE_IDS:
		(pages[k] as JwPage).visible = k == id
		(_tab_buttons[k] as Button).set_pressed_no_signal(k == id)
	var pg: JwPage = pages[id]
	if pg.has_method("apply_context") and not ctx.is_empty():
		pg.call("apply_context", ctx)
	pg.refresh()
	if session != null:
		session.log_event("ev.page_shown", {"page_id": "page." + id})
	if onboarding != null:
		onboarding.on_page_shown(id)


func page(id: String) -> JwPage:
	return pages.get(id, null)


func refresh_all() -> void:
	_refresh_queued = false
	top_bar.refresh()
	dock.refresh()
	var pg: JwPage = pages.get(current_page, null)
	if pg != null:
		pg.refresh()
	for o: JwOverlay in overlay_stack:
		if o.has_method("on_state_refresh"):
			o.call("on_state_refresh")
	if onboarding != null:
		onboarding.on_refresh()


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("refresh_all")


func _on_state_changed() -> void:
	_queue_refresh()


func _on_dryrun_changed() -> void:
	dock.refresh()
	var pg: JwPage = pages.get(current_page, null)
	if pg != null and pg.has_method("on_dryrun"):
		pg.call("on_dryrun")
	for o: JwOverlay in overlay_stack:
		if o.has_method("on_dryrun"):
			o.call("on_dryrun")


func _on_settlement_started() -> void:
	top_bar.refresh()
	dock.refresh()


func _on_settlement_finished(receipt: Dictionary) -> void:
	# 先开回放覆盖层（模态，盖住页面），页面重建挪到下一帧：把收尾工作分到两帧，主线程单帧更短（TH-4）。
	top_bar.refresh()
	open_overlay("settlement", receipt)
	if is_inside_tree():
		await get_tree().process_frame
	refresh_all()


# ── 覆盖层 ─────────────────────────────────────────────────────────────

func open_overlay(id: String, ctx: Dictionary = {}) -> JwOverlay:
	var o: JwOverlay = null
	match id:
		"newgame":
			o = JwNewGame.new()
		"budget":
			o = JwBudgetReview.new()
		"confirm":
			o = JwConfirmAdvance.new()
		"settlement":
			o = JwSettlementReplay.new()
		"annual":
			o = JwAnnualReview.new()
		"archive":
			o = JwFinalArchive.new()
		"saves":
			o = JwSaveManager.new()
		"ledger":
			o = JwLedgerDrawer.new()
		"rule":
			o = JwRuleCard.new()
		"legend":
			o = JwClassLegend.new()
		"rules":
			o = JwRulesBook.new()
		"term":
			o = JwTermCard.new()
		_:
			return null
	var layer: Control = modal_layer if o.modal else overlay_layer
	layer.add_child(o)
	o.setup(session, self, id, ctx)
	o.closed.connect(_on_overlay_closed)
	overlay_stack.append(o)
	if session != null:
		session.log_event("ev.overlay_opened", {"overlay": "overlay." + id})
	if onboarding != null:
		onboarding.on_overlay_opened(id, o)
	return o


func _on_overlay_closed(o: JwOverlay) -> void:
	overlay_stack.erase(o)
	if is_instance_valid(o):
		o.queue_free()
	if onboarding != null:
		onboarding.on_overlay_closed(o.overlay_id)
	_queue_refresh()


func close_all_overlays() -> void:
	for o: JwOverlay in overlay_stack.duplicate():
		o.close()


func top_overlay() -> JwOverlay:
	if overlay_stack.is_empty():
		return null
	return overlay_stack[overlay_stack.size() - 1]


func open_ledger(ledger: String, row: int = 0) -> void:
	if ledger == "":
		return
	open_overlay("ledger", {"ledger": ledger, "row": row})
	if session != null:
		session.log_event("ev.ledger_opened", {"ledger": ledger, "row_id": row})


func open_rule(rule_key: String) -> void:
	open_overlay("rule", {"rule": rule_key})
	if session != null:
		session.log_event("ev.rule_card_opened", {"rule_id": rule_key})


# ── 断点与缩放 ─────────────────────────────────────────────────────────

func logical_size() -> Vector2:
	return size


func _on_resized() -> void:
	if dock == null:
		return
	var ls: Vector2 = logical_size()
	var wb: int = JwScale.width_band(ls.x)
	dock.set_compact(ls.y < 900.0)
	dock.set_width_band(wb)
	top_bar.set_width_band(wb)
	var bh: float = JwScale.body_height(ls)
	var hb: int = JwScale.height_band(bh)
	notice_bar.visible = ls.x < 1280.0 or ls.y < 720.0
	for k: String in PAGE_IDS:
		(pages[k] as JwPage).set_bands(wb, hb)


# ── 快捷键（docs/20 §5.6：文本控件获焦时整体禁用；不占用裸 Enter / Space） ──

func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return
	var k: InputEventKey = event
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or focus is SpinBox:
		return
	if k.keycode == KEY_ENTER and k.ctrl_pressed and k.shift_pressed:
		get_viewport().set_input_as_handled()
		if session.game != null:
			open_overlay("confirm", {})
		return
	if k.keycode == KEY_ENTER and k.ctrl_pressed:
		get_viewport().set_input_as_handled()
		if session.game != null:
			open_overlay("budget", {})
		return
	if not overlay_stack.is_empty():
		return
	if k.ctrl_pressed or k.alt_pressed:
		return
	var idx: int = k.keycode - KEY_1
	if idx >= 0 and idx < PAGE_IDS.size():
		get_viewport().set_input_as_handled()
		show_page(PAGE_IDS[idx], {})
