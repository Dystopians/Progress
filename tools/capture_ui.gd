## 界面截图：以窗口模式载入主场景，等若干帧后把视口画面存成 PNG，然后退出。
## 用法（不能加 --headless，否则没有渲染）：
##   godot --path <根> --windowed --resolution 1600x900 --script res://tools/capture_ui.gd -- \
##       <输出.png> [等待帧数=90] [推进季数=0] [页面=overview] [--jw-autostart=<种子>]
## 页面：overview / region / policy / society / report；term:<术语> 打开术语定义卡；rules:<锚点> 打开规则手册并定位。推进季数 > 0 时经 JwSession.advance() 推进
## （需要已开局：配合 --jw-autostart=<种子> 使用，否则开局对话框挡在前面）。
extends SceneTree

var _out: String = ""
var _wait: int = 90
var _advance: int = 0
var _page: String = ""
var _frames: int = 0
var _main: Node = null
var _advanced: int = 0
var _done_frame: int = -1
var _scroll_target: String = ""


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "user://capture.png"
	_wait = int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 90
	_advance = int(args[2]) if args.size() > 2 and args[2].is_valid_int() else 0
	_page = args[3] if args.size() > 3 and not args[3].begins_with("--") else ""
	var packed: PackedScene = load("res://ui/main.tscn") as PackedScene
	if packed == null:
		print("主场景载入失败")
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	# 第 20 帧起每 10 帧推进一季（结算在会话里同步或异步完成，给界面留出刷新的帧）。
	if _frames >= 20 and _advanced < _advance and _frames % 10 == 0:
		var session: Variant = _main.get("session")
		# 结算在工作线程上异步跑：上一季没结算完之前不推进（否则 PHASE_BUSY 1001）。
		if session != null and session is Object and bool((session as Object).get("settling")):
			return
		if session != null and session is Object and (session as Object).has_method("advance"):
			var r: Variant = (session as Object).call("advance")
			_advanced += 1
			print("推进第 %d 季：%s" % [_advanced, str(r).substr(0, 160)])
	if _advanced < _advance:
		return
	if _done_frame < 0:
		_done_frame = _frames
	if _frames == _done_frame + maxi(_wait - 40, 10) and _page != "" and _main.has_method("show_page"):
		if _main.has_method("close_all_overlays"):
			_main.call("close_all_overlays")
		# 「term:<术语>」：停在总览页并打开该术语的定义卡；「rules:<锚点>」：打开规则手册并定位。
		if _page.begins_with("term:"):
			_main.call("show_page", "overview", {})
			_main.call("open_overlay", "term", {"term": _page.substr(5)})
		elif _page.begins_with("rules:"):
			_main.call("open_overlay", "rules", {"anchor": int(_page.substr(6))})
		elif _page.begins_with("overlay:"):
			# 「overlay:<覆盖层>[@节点标记]」：打开覆盖层（例：overlay:archive@DimPolitics）。
			var spec: String = _page.substr(8)
			_main.call("open_overlay", spec.get_slice("@", 0), {})
			if spec.find("@") > 0:
				_scroll_target = spec.get_slice("@", 1)
		elif _page.find("@") > 0:
			# 「页面@节点标记」：切到该页，并把带该 jw_id 的节点滚进视口（例：overview@TrendCharts）。
			_main.call("show_page", _page.get_slice("@", 0), {})
			_scroll_target = _page.get_slice("@", 1)
		else:
			_main.call("show_page", _page, {})
	if _scroll_target != "" and _frames == _done_frame + maxi(_wait - 20, 12):
		var t: Control = _find_tagged(_main, _scroll_target)
		var n: Node = t
		while n != null and not (n is ScrollContainer):
			n = n.get_parent()
		if t != null and n != null:
			var sc: ScrollContainer = n as ScrollContainer
			var content: Control = sc.get_child(0) as Control
			sc.scroll_vertical = int(t.global_position.y - content.global_position.y)
	if _frames < _done_frame + _wait:
		return
	var img: Image = root.get_texture().get_image()
	var err: int = img.save_png(_out)
	print("截图 %s（%dx%d）：%s" % [ProjectSettings.globalize_path(_out), img.get_width(), img.get_height(),
			"ok" if err == OK else "失败 %d" % err])
	quit(0)


static func _find_tagged(n: Node, id: String) -> Control:
	if n is Control and String((n as Control).get_meta("jw_id", "")) == id:
		return n as Control
	for ch: Node in n.get_children():
		var f: Control = _find_tagged(ch, id)
		if f != null:
			return f
	return null
