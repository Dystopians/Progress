## v2 主页面基类：外壳在局面变化或切页时调用 refresh()；页面只格式化、不计算。
class_name JcPage
extends MarginContainer

var session: JcSession = null
var root_ui: Node = null
var page_id: String = ""
var content: VBoxContainer = null
var _scroll: ScrollContainer = null


func setup(s: JcSession, r: Node, id: String) -> void:
	session = s
	root_ui = r
	page_id = id
	name = "Page_" + id
	add_theme_constant_override("margin_left", 16)
	add_theme_constant_override("margin_right", 12)
	add_theme_constant_override("margin_top", 12)
	add_theme_constant_override("margin_bottom", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	build()


## 默认结构：一个可纵向滚动的内容栏。需要别的布局的页面重写 build()。
## 横向也允许滚：界面放大后内容再宽也不会钻到右边顾问栏底下，最多出一条横向滚动条。
func build() -> void:
	content = JwUi.vbox(14)
	_scroll = JwUi.scroll(content, true)
	add_child(_scroll)


## 页面实际能用的宽度（页面栈的宽减去左右边距）；还没排版时是 0。
func avail_width() -> float:
	var p: Control = get_parent_control()
	if p == null:
		return 0.0
	return p.size.x - float(get_theme_constant("margin_left") + get_theme_constant("margin_right"))


func _ready() -> void:
	var p: Control = get_parent_control()
	if p != null:
		p.resized.connect(func() -> void: relayout(avail_width()))
	relayout(avail_width())


## 页面栈的宽度变了（拖窗口、调界面大小）时调用；要随宽度改排版的页面重写它。w ≤ 0 表示还没排版。
func relayout(_w: float) -> void:
	pass


func refresh() -> void:
	pass


func clear() -> void:
	if content != null:
		JwUi.clear(content)


func game() -> JCGame:
	return session.game if session != null else null


func views() -> JCViews:
	return session.views()


func open_overlay(id: String, ctx: Dictionary = {}) -> void:
	if root_ui != null and root_ui.has_method("open_overlay"):
		root_ui.call("open_overlay", id, ctx)


func goto_page(id: String) -> void:
	if root_ui != null and root_ui.has_method("show_page"):
		root_ui.call("show_page", id)


func t(key: String) -> String:
	return JwText.t(key)


func rt(key: String, slots: Dictionary) -> String:
	return JwText.render(key, slots)
