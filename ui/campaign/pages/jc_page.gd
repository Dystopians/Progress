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
func build() -> void:
	content = JwUi.vbox(14)
	_scroll = JwUi.scroll(content)
	add_child(_scroll)


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
