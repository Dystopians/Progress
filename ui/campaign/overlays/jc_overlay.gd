## v2 覆盖层基类：半透明遮罩 + 居中面板（标题栏带关闭），内容可纵向滚动；Esc 关闭。
class_name JcOverlay
extends Control

signal closed(o: JcOverlay)

var session: JcSession = null
var root_ui: Node = null
var overlay_id: String = ""
var ctx: Dictionary = {}
var panel: PanelContainer = null
var body: VBoxContainer = null
var title_label: Label = null
var width_ratio: float = 0.72
var height_ratio: float = 0.84
var closable: bool = true
var _close_btn: Button = null
var _head: PanelContainer = null
var _pad: MarginContainer = null


func setup(s: JcSession, r: Node, id: String, context: Dictionary) -> void:
	session = s
	root_ui = r
	overlay_id = id
	ctx = context
	name = "Overlay_" + id
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim: ColorRect = ColorRect.new()
	var dc: Color = JwTheme.c("bg.abyss")
	dc.a = 0.8
	dim.color = dc
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	panel = JwUi.panel("bg.base", "line.strong", 0)
	add_child(panel)
	var outer: VBoxContainer = JwUi.vbox(0)
	panel.add_child(outer)
	var head: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.panel", "", 0, 20, 12, 12, 12))
	_head = head
	var hb: HBoxContainer = JwUi.hbox(12)
	head.add_child(hb)
	title_label = JwUi.title("", "title_block")
	hb.add_child(title_label)
	hb.add_child(JwUi.spacer())
	_close_btn = JwUi.button(JwText.t("jc.ui.close"))
	_close_btn.name = "CloseButton"
	_close_btn.pressed.connect(close)
	_close_btn.visible = closable
	hb.add_child(_close_btn)
	outer.add_child(head)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var pad: MarginContainer = JwUi.margin(null, 20, 16, 20, 20)
	_pad = pad
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	body = JwUi.vbox(14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(body)
	resized.connect(_layout)
	build()
	_layout()
	# 内容多少变了（重建、换页签）就重新定高：内容少时面板跟着矮，不留一大片空
	pad.minimum_size_changed.connect(_queue_layout)
	_queue_layout()


func build() -> void:
	pass


## 局面变了：默认整个重建。
func on_changed() -> void:
	if body == null:
		return
	JwUi.clear(body)
	build()
	_queue_layout()


## 不许关（例如还没有局面时的新开一局）。
func set_closable(v: bool) -> void:
	closable = v
	if _close_btn != null:
		_close_btn.visible = v


func set_title(s: String) -> void:
	if title_label != null:
		title_label.text = s


func _layout() -> void:
	if panel == null:
		return
	var vs: Vector2 = size
	if vs.x <= 1.0 and is_inside_tree():
		vs = get_viewport_rect().size
	var w: float = clampf(vs.x * width_ratio, minf(560.0, vs.x - 16.0), vs.x - 16.0)
	var h: float = clampf(vs.y * height_ratio, minf(240.0, vs.y - 16.0), vs.y - 16.0)
	if _head != null and _pad != null:
		var need: float = _head.get_combined_minimum_size().y + _pad.get_combined_minimum_size().y + 6.0
		h = clampf(need, minf(240.0, vs.y - 16.0), h)
	panel.position = Vector2((vs.x - w) * 0.5, (vs.y - h) * 0.5)
	panel.size = Vector2(w, h)


var _layout_queued: bool = false


func _queue_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_deferred_layout")


func _deferred_layout() -> void:
	_layout_queued = false
	_layout()


func close() -> void:
	closed.emit(self)


func _unhandled_key_input(event: InputEvent) -> void:
	if closable and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func game() -> JCGame:
	return session.game if session != null else null


func t(key: String) -> String:
	return JwText.t(key)


func rt(key: String, slots: Dictionary) -> String:
	return JwText.render(key, slots)
