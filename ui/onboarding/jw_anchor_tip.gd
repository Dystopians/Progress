## 锚定提示条（docs/22 §5.3 JwAnchorTip）：非模态、贴附锚点、≤1 行导语 + [知道了] [不再显示]。
## 根节点不拦截鼠标（TIP-1），不覆盖锚点（TIP-2），不用 modulate 淡入（TIP-3），不抢焦点（TIP-7）。
class_name JwAnchorTip
extends PanelContainer

signal dismissed(forever: bool)

var anchor: Control = null
var step_id: String = ""
## 提示条允许出现的区域（全局坐标；外壳传入页面工作区，避免盖住顶栏与底部固定区）。
var bounds: Rect2 = Rect2()
## 页面工作区（锚点在滚动区之外时，提示条贴在工作区底部，不盖住底部固定区）。
var body_rect: Rect2 = Rect2()
## 锚点不在可见区域内时（例如在滚动区下方）改用的导语：说明往哪里找，而不替玩家滚动（OB-F2）。
var lead_off: String = ""
## 优先放在锚点上方（覆盖层里的锚点：放下方会盖住结论行）。
var prefer_above: bool = false
var _lead_on: String = ""


static func make(text: String, id: String) -> JwAnchorTip:
	var t: JwAnchorTip = JwAnchorTip.new()
	t.step_id = id
	t.name = "AnchorTip"
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_stylebox_override("panel", JwTheme.box4("bg.raised", "focus.ring", 2, 12, 8, 10, 8))
	var h: HBoxContainer = JwUi.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_child(h)
	var ic: JwIcon = JwIcon.make("note", JwTheme.c("focus.ring"), 16)
	h.add_child(ic)
	var l: Label = JwUi.label(text, "body_bold", "text.primary")
	l.name = "Lead"
	t._lead_on = text
	h.add_child(l)
	var ok: Button = JwUi.button(JwText.t("onb.ok"))
	ok.name = "Ok"
	ok.focus_mode = Control.FOCUS_ALL
	ok.pressed.connect(func() -> void: t.dismissed.emit(false))
	h.add_child(ok)
	var never: Button = JwUi.button(JwText.t("onb.never"))
	never.name = "Never"
	never.pressed.connect(func() -> void: t.dismissed.emit(true))
	h.add_child(never)
	return t


## 页面刚重建时布局还没排好：进树后隔两帧再放一次，锚点移动或改尺寸时跟着重放。
func _ready() -> void:
	if anchor != null and is_instance_valid(anchor):
		anchor.item_rect_changed.connect(_replace_deferred)
	for i: int in 2:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	place()


func _replace_deferred() -> void:
	if is_inside_tree():
		call_deferred("place")


## 贴近锚点放置：锚点在可见区下半部时放在上方，否则放在下方；放不下就换另一侧，最后夹进可见区。
## 不与锚点矩形相交（TIP-2）；锚点整个在可见区之外时换用 lead_off 导语。
func place() -> void:
	if not is_inside_tree():
		return
	if anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		visible = false
		return
	var vs: Vector2 = get_viewport_rect().size
	var vis: Rect2 = bounds if bounds.size.x > 1.0 else Rect2(Vector2.ZERO, vs)
	var ar: Rect2 = anchor.get_global_rect()
	var lead: Label = get_node_or_null("HBoxContainer/Lead") as Label
	if lead == null:
		for n: Node in find_children("Lead", "Label", true, false):
			lead = n as Label
	# 锚点的可见部分：被所有滚动容器祖先裁剪后，再与可放置区域相交。
	var shown: Rect2 = ar.intersection(_scroll_clip(anchor))
	var on_screen: bool = shown.has_area() and vis.intersects(shown)
	if on_screen:
		ar = shown
	if lead != null:
		lead.text = _lead_on if on_screen or lead_off == "" else lead_off
	reset_size()
	var sz: Vector2 = get_combined_minimum_size()
	var below_y: float = ar.end.y + 8.0
	var above_y: float = ar.position.y - sz.y - 8.0
	var y: float = below_y
	if on_screen:
		var above: bool = prefer_above or ar.get_center().y > vis.get_center().y
		y = above_y if above else below_y
		if y < vis.position.y or y + sz.y > vis.end.y:
			y = below_y if above else above_y
	else:
		var area: Rect2 = body_rect if body_rect.size.x > 1.0 else vis
		y = area.end.y - sz.y - 8.0 if ar.position.y >= area.end.y else area.position.y + 8.0
	y = clampf(y, vis.position.y + 4.0, maxf(vis.position.y + 4.0, vis.end.y - sz.y - 4.0))
	var x: float = clampf(ar.position.x if on_screen else vis.position.x + 16.0, vis.position.x + 8.0,
			maxf(vis.position.x + 8.0, vis.end.x - sz.x - 8.0))
	global_position = Vector2(x, y)
	size = sz


## 锚点所在全部滚动容器的可见矩形之交（全局坐标）。
static func _scroll_clip(c: Control) -> Rect2:
	var clip: Rect2 = Rect2(Vector2(-1.0e6, -1.0e6), Vector2(2.0e6, 2.0e6))
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			clip = clip.intersection((n as ScrollContainer).get_global_rect())
		n = n.get_parent()
	return clip
