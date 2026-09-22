## 表格原语（行式）：表头 + 斑马行（行高 ≥32 lu，docs/20 §12.1 行区分不只靠细线）。
##
## 每行可带三类左标尺（通道③）与「类」列（AC-07：同表混排多类时必须有类列或分组标题）；
## 每个单元格可单独带三类徽章（逐格单值，BR-2）。口径由列头与表脚承载（docs/20 §4.2）。
## 本类适用于 ≤ 64 行的小表；长台账用 JwLedgerDrawer 的 Tree。
class_name JwTable
extends VBoxContainer

signal row_activated(index: int, row_meta: Dictionary)

var cols: Array = []
var paper: bool = false
var class_column: bool = false
var _rows_box: VBoxContainer = null
var _n: int = 0
var row_metas: Array[Dictionary] = []


static func make(columns: Array, on_paper: bool = false, with_class_col: bool = false) -> JwTable:
	var t: JwTable = JwTable.new()
	t.cols = columns
	t.paper = on_paper
	t.class_column = with_class_col
	t.add_theme_constant_override("separation", 0)
	t._build_header()
	t._rows_box = VBoxContainer.new()
	t._rows_box.add_theme_constant_override("separation", 0)
	t.add_child(t._rows_box)
	return t


func _bg(i: int) -> String:
	if paper:
		return "bg.paper" if i % 2 == 0 else "bg.paper2"
	return "bg.panel" if i % 2 == 0 else "bg.raised"


func _build_header() -> void:
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.paper2" if paper else "bg.abyss",
			"", 0, 8, 6, 8, 6))
	var h: HBoxContainer = JwUi.hbox(8)
	p.add_child(h)
	h.add_child(JwUi.vspacer(0))
	if class_column:
		var cl: Label = JwUi.label(JwText.t("table.col_class"), "title_sub",
				"text.ink" if paper else "text.primary")
		cl.custom_minimum_size = Vector2(52, 0)
		h.add_child(cl)
	for c: Variant in cols:
		var cd: Dictionary = c
		var l: Label = JwUi.label(String(cd.get("title", "")), "title_sub",
				"text.ink" if paper else "text.primary", true)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_apply_width(l, cd)
		l.horizontal_alignment = _align(String(cd.get("align", "l")))
		h.add_child(l)
	p.set_meta("table_header", true)
	add_child(p)


func _apply_width(c: Control, cd: Dictionary) -> void:
	var w: int = int(cd.get("w", 120))
	c.custom_minimum_size.x = w
	if bool(cd.get("expand", false)):
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_FILL


static func _align(a: String) -> HorizontalAlignment:
	if a == "r":
		return HORIZONTAL_ALIGNMENT_RIGHT
	if a == "c":
		return HORIZONTAL_ALIGNMENT_CENTER
	return HORIZONTAL_ALIGNMENT_LEFT


## 追加一行。cells 的元素可以是：String；Control；或 {text, cls, color, role, wrap}。
func add_row(cells: Array, row_cls: int = JwInfo.Cls.NONE, row_meta: Dictionary = {}) -> HBoxContainer:
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4(_bg(_n), "", 0, 8, 4, 8, 4))
	p.custom_minimum_size = Vector2(0, 32)
	var h: HBoxContainer = JwUi.hbox(8)
	p.add_child(h)
	h.add_child(JwClassRule.make(row_cls, paper))
	if class_column:
		var bw: HBoxContainer = JwUi.badge(row_cls, paper)
		bw.custom_minimum_size = Vector2(52, 0)
		h.add_child(bw)
	var i: int = 0
	while i < cols.size():
		var cd: Dictionary = cols[i]
		var cell: Variant = cells[i] if i < cells.size() else ""
		h.add_child(_make_cell(cell, cd))
		i += 1
	p.set_meta("row_index", _n)
	p.set_meta("info_class", row_cls)
	row_metas.append(row_meta)
	if not row_meta.is_empty() and bool(row_meta.get("clickable", false)):
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx: int = _n
		p.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
					and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				row_activated.emit(idx, row_metas[idx]))
	_rows_box.add_child(p)
	_n += 1
	return h


func _make_cell(cell: Variant, cd: Dictionary) -> Control:
	var base_tok: String = "text.ink" if paper else "text.secondary"
	if cell is Control:
		var c: Control = cell
		_apply_width(c, cd)
		return c
	var text: String = ""
	var cls: int = JwInfo.Cls.NONE
	var tok: String = base_tok
	var role: String = "dense"
	var wrap: bool = bool(cd.get("wrap", false))
	var icon: String = ""
	if cell is Dictionary:
		var d: Dictionary = cell
		text = String(d.get("text", ""))
		cls = int(d.get("cls", JwInfo.Cls.NONE))
		tok = String(d.get("color", base_tok))
		role = String(d.get("role", "dense"))
		wrap = bool(d.get("wrap", wrap))
		icon = String(d.get("icon", ""))
	else:
		text = str(cell)
	if String(cd.get("align", "l")) == "r" and role == "dense":
		role = "num"
	if cls == JwInfo.Cls.NONE:
		var l: Label = JwUi.label(text, role, tok, wrap)
		l.horizontal_alignment = _align(String(cd.get("align", "l")))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_apply_width(l, cd)
		return l
	var hb: HBoxContainer = JwUi.hbox(4)
	hb.set_meta("info_class", cls)
	hb.set_meta("cell_text", text)
	_apply_width(hb, cd)
	if String(cd.get("align", "l")) == "r":
		hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_child(JwUi.badge(cls, paper))
	if icon != "":
		# 风险单元格的图标通道（与文字、颜色并列，docs/20 BR-5 三通道）。
		hb.add_child(JwIcon.make(icon, JwTheme.c(tok), 14))
	var l2: Label = JwUi.label(text, role, tok, wrap)
	l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l2)
	return hb


## 分组标题行（A1 表的「段一 · 现行承诺」等；docs/20 §8.3 段标题必须出现）。
func add_group_title(text: String) -> void:
	var p: PanelContainer = JwUi.panel_style(JwTheme.box4("bg.paper2" if paper else "bg.base",
			"line.strong", 0, 8, 6, 8, 4))
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.border_color = JwTheme.c("text.ink2" if paper else "line.strong")
		sb.border_width_top = 1
	var l: Label = JwUi.label(text, "body_bold", "text.ink" if paper else "text.primary")
	p.add_child(l)
	p.set_meta("group_title", text)
	_rows_box.add_child(p)


## 表脚（口径全文、合计说明）。
func add_note(text: String) -> Label:
	var l: Label = JwUi.label(text, "caption", "text.ink2" if paper else "text.muted", true)
	l.set_meta("table_footer", true)
	var m: MarginContainer = JwUi.margin(l, 8, 6, 8, 2)
	add_child(m)
	return l


func row_count() -> int:
	return _n


func clear_rows() -> void:
	JwUi.clear(_rows_box)
	_n = 0
	row_metas.clear()
