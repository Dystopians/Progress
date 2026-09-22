## 覆盖层基类（docs/20 §5.4、§10）：挂在外壳的 OverlayLayer / ModalLayer，Esc 逐层收起。
##
## 背景遮罩用 bg.abyss 半透明底色块（不对文本用 modulate，B-12）。
## 面板尺寸按视口的比例给出，内部允许纵向滚动；关闭时发 closed 信号，由外壳出栈。
class_name JwOverlay
extends Control

signal closed(overlay: JwOverlay)

var session: JwSession = null
var root_ui: Node = null
var overlay_id: String = ""
var ctx: Dictionary = {}
var modal: bool = false
var panel: PanelContainer = null
var body: VBoxContainer = null
var title_label: Label = null
var paper: bool = false
var width_ratio: float = 0.78
var height_ratio: float = 0.86
var _dim: ColorRect = null


func setup(s: JwSession, r: Node, id: String, context: Dictionary) -> void:
	session = s
	root_ui = r
	overlay_id = id
	ctx = context
	name = "Overlay_" + id
	# 已挂在层下：必须连偏移一起重置，否则保留当前 0 尺寸（遮罩不可见）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	var dim_col: Color = JwTheme.c("bg.abyss")
	dim_col.a = 0.78
	_dim.color = dim_col
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	panel = JwUi.panel("bg.paper" if paper else "bg.base", "" if paper else "line.strong", 0)
	add_child(panel)
	var outer: VBoxContainer = JwUi.vbox(0)
	panel.add_child(outer)
	var head: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.paper2" if paper else "bg.panel",
			"", 0, 20, 12, 12, 12))
	var hb: HBoxContainer = JwUi.hbox(12)
	head.add_child(hb)
	title_label = JwUi.title("", "title_page" if paper else "title_block", paper)
	hb.add_child(title_label)
	hb.add_child(JwUi.spacer())
	var close_btn: Button = JwUi.button(JwText.t("common.close"))
	close_btn.name = "CloseButton"
	close_btn.pressed.connect(close)
	hb.add_child(close_btn)
	outer.add_child(head)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "OverlayScroll"
	# 内容最小宽度超过面板时横向滚动，而不是把面板撑出视口（关闭按钮始终可见）。
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var pad: MarginContainer = JwUi.margin(null, 20, 16, 20, 20)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	body = JwUi.vbox(14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(body)
	resized.connect(_layout)
	build()
	_layout()


## 子类在此构建内容（body 已就绪）。
func build() -> void:
	pass


func set_title(t: String) -> void:
	if title_label != null:
		title_label.text = t


func _layout() -> void:
	if panel == null:
		return
	var vs: Vector2 = size
	if vs.x <= 1.0:
		if not is_inside_tree():
			return
		vs = get_viewport_rect().size
	var w: float = clampf(vs.x * width_ratio, minf(640.0, vs.x - 16.0), vs.x - 16.0)
	var h: float = clampf(vs.y * height_ratio, minf(360.0, vs.y - 16.0), vs.y - 16.0)
	panel.position = Vector2((vs.x - w) * 0.5, (vs.y - h) * 0.5)
	panel.size = Vector2(w, h)


func close() -> void:
	closed.emit(self)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


## 便捷：数字格子（与页面同一套台账/规则入口）。
func num(value_text: String, unit_text: String, cls: int, role: String, meta: Dictionary) -> JwNumberCell:
	var n: JwNumberCell = JwNumberCell.make(value_text, unit_text, cls, role, meta, paper)
	n.ledger_requested.connect(func(l: String, r: int) -> void:
		if root_ui != null and root_ui.has_method("open_ledger"):
			root_ui.call("open_ledger", l, r))
	n.rule_requested.connect(func(k: String) -> void:
		if root_ui != null and root_ui.has_method("open_rule"):
			root_ui.call("open_rule", k))
	return n
