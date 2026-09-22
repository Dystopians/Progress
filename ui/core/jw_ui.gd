## 控件工厂：统一字号角色、色板、间距与三类编码，减少各页重复的样板代码。
## 本类只组装控件，不读状态、不算数。
class_name JwUi
extends RefCounted


static func label(text: String, role: String = "body", color_token: String = "text.primary",
		wrap: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_override("font", JwTheme.font(role))
	l.add_theme_font_size_override("font_size", JwTheme.size(role))
	l.add_theme_color_override("font_color", JwTheme.c(color_token))
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.set_meta("jw_role", role)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 可换行正文（CJK 行内断行）。
static func para(text: String, color_token: String = "text.secondary", role: String = "body") -> Label:
	return label(text, role, color_token, true)


static func title(text: String, role: String = "title_block", paper: bool = false) -> Label:
	return label(text, role, "text.ink" if paper else "text.primary")


## 口径角标（caption 级，14 lu）：必须指向一个 ≥16 lu 的冗余承载节点（redundant_of）。
static func caption(text: String, redundant_of: Control = null, color_token: String = "text.muted") -> Label:
	var l: Label = label(text, "caption", color_token, true)
	if redundant_of != null:
		l.set_meta("redundant_of", redundant_of.get_path() if redundant_of.is_inside_tree() else NodePath())
		l.set_meta("redundant_node", redundant_of)
	return l


static func vbox(sep: int = 8) -> VBoxContainer:
	var b: VBoxContainer = VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func hbox(sep: int = 8) -> HBoxContainer:
	var b: HBoxContainer = HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func panel(bg: String = "bg.panel", border: String = "", pad: int = 16) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", JwTheme.box(bg, border, 1 if border != "" else 0, 2, pad))
	return p


static func panel_style(sb: StyleBox) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	return p


static func margin(child: Control, l: int, t: int, r: int, b: int) -> MarginContainer:
	var m: MarginContainer = MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	if child != null:
		m.add_child(child)
	return m


static func button(text: String, variation: String = "") -> Button:
	var b: Button = Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(32, 32)
	b.focus_mode = Control.FOCUS_ALL
	return b


static func link(text: String) -> Button:
	var b: Button = button(text, "LinkBtn")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


static func spacer() -> Control:
	var c: Control = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func vspacer(h: int) -> Control:
	var c: Control = Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hsep() -> HSeparator:
	return HSeparator.new()


static func clear(node: Node) -> void:
	if node == null:
		return
	for ch: Node in node.get_children():
		node.remove_child(ch)
		ch.queue_free()


static func expand(c: Control, h: bool = true, v: bool = false) -> Control:
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func scroll(child: Control, horizontal: bool = false) -> ScrollContainer:
	var s: ScrollContainer = ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal \
			else ScrollContainer.SCROLL_MODE_DISABLED
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


## 三类徽章：图标（实心度递减）+ 徽章字（实 / 算 / 预）。
static func badge(cls: int, paper: bool = false) -> HBoxContainer:
	var b: HBoxContainer = hbox(3)
	b.set_meta("info_class", cls)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cls == JwInfo.Cls.NONE:
		return b
	var tok: String = JwInfo.color_token(cls, paper)
	b.add_child(JwIcon.make(JwInfo.icon_kind(cls), JwTheme.c(tok), 12))
	var l: Label = label(JwInfo.badge(cls), "body_bold", tok)
	b.add_child(l)
	return b


## 风险徽章：图标 + 等级词 + 颜色（三通道，AC-38）。
static func risk_badge(sev: int, text: String, paper: bool = false) -> HBoxContainer:
	var b: HBoxContainer = hbox(6)
	b.set_meta("severity", sev)
	b.set_meta("risk_text", text)
	b.set_meta("icon_id", JwInfo.sev_icon(sev))
	var tok: String = JwInfo.sev_color_token(sev, paper)
	b.set_meta("color_token", tok)
	b.add_child(JwIcon.make(JwInfo.sev_icon(sev), JwTheme.c(tok), 14))
	b.add_child(label(text, "body_bold", tok))
	return b


## 带左标尺的散文行：[标尺][正文（正文自带词前缀）]。正文由模板渲染，本函数不拼句。
static func class_line(cls: int, text: String, paper: bool = false,
		color_token: String = "") -> HBoxContainer:
	var row: HBoxContainer = hbox(8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("info_class", cls)
	row.set_meta("line_text", text)
	row.add_child(JwClassRule.make(cls, paper))
	var tok: String = color_token
	if tok == "":
		tok = "text.ink" if paper else "text.secondary"
	var l: Label = label(text, "body", tok, true)
	row.add_child(l)
	return row


## 区块：标题栏（衬线标题 + 可选副标题）+ 内容区。返回 {root, body, header}。
static func section(title_text: String, subtitle: String = "", paper: bool = false,
		pad: int = 16) -> Dictionary:
	var root: PanelContainer = panel("bg.paper" if paper else "bg.panel", "" if paper else "line.hair", pad)
	var v: VBoxContainer = vbox(10)
	root.add_child(v)
	var head: HBoxContainer = hbox(12)
	var t: Label = title(title_text, "title_block", paper)
	head.add_child(t)
	if subtitle != "":
		var st: Label = label(subtitle, "body", "text.ink2" if paper else "text.muted")
		st.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(st)
	v.add_child(head)
	var body: VBoxContainer = vbox(8)
	v.add_child(body)
	return {"root": root, "body": body, "header": head, "title": t}


## 空态（docs/20 §7.0 JwEmptyState）：为什么现在是空的 / 什么时候会有内容 / 阈值或规则入口。
static func empty_state(why: String, when: String, rule: String, paper: bool = false) -> VBoxContainer:
	var v: VBoxContainer = vbox(4)
	v.set_meta("empty_state", true)
	var tok: String = "text.ink2" if paper else "text.secondary"
	var l1: Label = para(why, tok)
	var l2: Label = para(when, tok)
	var l3: Label = para(rule, "text.ink2" if paper else "text.muted")
	l1.set_meta("empty_part", "why")
	l2.set_meta("empty_part", "when")
	l3.set_meta("empty_part", "rule")
	v.add_child(l1)
	v.add_child(l2)
	v.add_child(l3)
	return v


## 口径角标行：值的五元组（单位 · 存流指比 · 期间 · 价格基期 · 分母/基期）。
static func meta_line(parts: PackedStringArray, redundant_of: Control = null) -> Label:
	var l: Label = caption(" · ".join(parts), redundant_of)
	l.set_meta("meta_parts", parts)
	return l


## 给控件打一个测试与引导可查找的唯一名。
static func tag(c: Control, name_id: String) -> Control:
	c.name = name_id
	c.set_meta("jw_id", name_id)
	return c
