## 读档后立项诊断：经 JWGame 开局 → 推进 N 季 → 存档 → 新实例读档 → 立项 → 再推进。
## 同时逐数组比对读档前后状态块长度（找「from_dict 之后 SoA 变短」）。
## 用法：godot --headless --path <根> --script res://tools/diag_save_launch.gd -- [推进季数=2]
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 2
	JWResult.trace_faults = true
	var g1: JWGame = JWGame.new()
	var r0: JWResult = g1.new_game("res://content", 1000000, 40)
	if r0 == null or not r0.ok:
		print("开局失败")
		quit(1)
		return
	for q: int in n_q:
		_advance(g1)
	var rs: JWResult = g1.save_game("diag_save_launch")
	print("存档：%s" % ("ok" if rs == null or rs.ok else str(rs.code)))
	var g2: JWGame = JWGame.new()
	var r1: JWResult = g2.new_game("res://content", 1000000, 40)
	var rl: JWResult = g2.load_game("diag_save_launch")
	print("读档：%s（read_only=%s）" % ["ok" if rl == null or rl.ok else str(rl.code), str(g2.read_only_mode)])
	_compare(g1.get("_st") as JWSimState, g2.get("_st") as JWSimState)
	# 读档后立项（P04 海岬，满规模，发债）。
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	a[0] = 3
	a[1] = JWUnits.Region.HAIJIA
	a[2] = 1_000_000
	a[3] = 1
	var rc: JWResult = g2.submit_command(JWCommands.Kind.PROJECT_LAUNCH, a)
	print("读档后递交立项：%s" % ("ok" if rc == null or rc.ok else str(rc.code)))
	for i: int in 3:
		var ra: JWResult = _advance(g2)
		print("读档后第 %d 次推进：%s" % [i + 1, "ok" if ra == null or ra.ok else str(ra.code)])
	quit(0)


func _advance(g: JWGame) -> JWResult:
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)
	a0.fill(0)
	g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a0)
	return g.advance_quarter()


## 逐状态块、逐数组比较长度（只报告不同的）。
func _compare(a: JWSimState, b: JWSimState) -> void:
	var blocks: Array = [["projects", a.projects, b.projects], ["policy", a.policy, b.policy],
			["bonds", a.bonds, b.bonds], ["capital", a.capital, b.capital], ["treasury", a.treasury, b.treasury],
			["pop", a.pop, b.pop], ["labor", a.labor, b.labor], ["sectors", a.sectors, b.sectors],
			["inventory", a.inventory, b.inventory], ["politics", a.politics, b.politics], ["blocs", a.blocs, b.blocs]]
	var diffs: int = 0
	for blk: Array in blocks:
		var x: Object = blk[1]
		var y: Object = blk[2]
		var ids: PackedStringArray = x.get("STATE_ARRAY_IDS")
		for i: int in ids.size():
			var va: PackedInt64Array = x.call("state_array", i)
			var vb: PackedInt64Array = y.call("state_array", i)
			if va.size() != vb.size():
				print("  长度不同：%s[%d] %s  存档前 %d / 读档后 %d" % [blk[0], i, ids[i], va.size(), vb.size()])
				diffs += 1
	print("状态块长度比对：%d 处不同" % diffs)
