## v2 界面截图：以窗口模式载入 res://ui/campaign/jc_main.tscn，依次切到各页、打开各弹窗，逐张存成 PNG。
## 用法（不能加 --headless，否则没有渲染）：
##   godot --path <根> --windowed --resolution 1600x900 --script res://tools/capture_v2.gd -- \
##       <输出目录> <镜头,镜头,...> [--jc-seed=7 | --jc-play=res://tools/playscripts_v2/steward_balanced.json --jc-until=1700]
## 镜头：页面名（overview / map / industry / modern / tech / policy / society / trade / chronicle），
##       o:<弹窗>（steward / advisors / build / era / era_nation / era_world / event / receipt / help / saves / newgame / gameover），
##       map@<地区>（舆图并选中该地区），industry@<商品>（产业页并选中该商品）。
## 每张存为 <输出目录>/v2_<镜头>.png（冒号与 @ 换成下划线）。
extends SceneTree

const WAIT: int = 24

var _out_dir: String = "user://v2_shots"
var _shots: PackedStringArray = PackedStringArray()
var _main: Node = null
var _frames: int = 0
var _idx: int = 0
var _next_at: int = 40
var _shot_at: int = -1


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var pos: Array = []
	for a: String in args:
		if not a.begins_with("--"):
			pos.append(a)
	if pos.size() > 0:
		_out_dir = String(pos[0])
	var spec: String = String(pos[1]) if pos.size() > 1 else "overview,map,industry,modern,tech,policy,society,trade,chronicle"
	_shots = spec.split(",", false)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var packed: PackedScene = load("res://ui/campaign/jc_main.tscn") as PackedScene
	if packed == null:
		print("v2 主场景载入失败")
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _idx >= _shots.size():
		if _frames > _next_at:
			var miss: PackedStringArray = JwText.missing_keys()
			print("缺失文案键 %d 个%s" % [miss.size(), ("：" + ", ".join(miss.slice(0, 20))) if not miss.is_empty() else ""])
			quit(0)
		return
	if _frames == _next_at:
		_setup(_shots[_idx])
		_shot_at = _frames + WAIT
	elif _frames == _shot_at:
		var name: String = _shots[_idx].replace(":", "_").replace("@", "_")
		var path: String = _out_dir.path_join("v2_%s.png" % name)
		var img: Image = root.get_texture().get_image()
		var err: int = img.save_png(path)
		print("截图 %s：%s" % [ProjectSettings.globalize_path(path), "ok" if err == OK else "失败 %d" % err])
		_idx += 1
		_next_at = _frames + 4


func _setup(shot: String) -> void:
	var session: JcSession = _main.get("session") as JcSession
	if _main.has_method("close_all_overlays"):
		_main.call("close_all_overlays")
	if shot.begins_with("o:"):
		var id: String = shot.substr(2)
		var ctx: Dictionary = {}
		match id:
			"era":
				ctx = {"kind": "book"}
			"era_nation":
				id = "era"
				ctx = {"kind": "nation", "era": maxi(2, session.game.st.era) if session.has_game() else 2}
			"era_world":
				id = "era"
				ctx = {"kind": "world", "era": maxi(2, session.game.st.world_era) if session.has_game() else 2}
			"receipt":
				if session.has_game():
					ctx = session.game.last_receipt.duplicate()
					ctx["before"] = session.game.status()
		_main.call("open_overlay", id, ctx)
		return
	var page: String = shot
	if shot.contains("@"):
		page = shot.get_slice("@", 0)
		var arg: String = shot.get_slice("@", 1)
		if page == "map":
			session.selected_region = arg
		elif page == "industry":
			session.selected_good = arg
	_main.call("show_page", page)
