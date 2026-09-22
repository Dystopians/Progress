## 同进程确定性诊断：在同一个进程里连开两局完全相同的无命令对局，逐季比对 state_hash。
##
## 用法：godot --headless --path <根> --script res://tools/diag_determinism.gd -- [季数=12] [种子]
## 两局任何一季的哈希不同，即存在跨局泄漏的静态状态（INV-014 风险）；打印第一处分歧的季与各子系统哈希。
extends SceneTree


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n_q: int = int(args[0]) if args.size() > 0 else 12
	var seed_v: int = int(args[1]) if args.size() > 1 else 1000000
	var a: PackedStringArray = _run(n_q, seed_v)
	var b: PackedStringArray = _run(n_q, seed_v)
	var n: int = mini(a.size(), b.size())
	print("第一局 %d 季，第二局 %d 季" % [a.size(), b.size()])
	for q: int in n:
		if a[q] != b[q]:
			print("第 %d 季起分歧：\n  A %s\n  B %s" % [q, a[q], b[q]])
			quit(1)
			return
	if a.size() != b.size():
		print("两局长度不同（终局季不同）")
		quit(1)
		return
	print("两局逐季 state_hash 完全相同")
	quit(0)


func _run(n_q: int, seed_v: int) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all("res://content", st)
	if res == null or not res.ok:
		print("载入失败")
		return out
	st.content_hash = loader.content_hash
	st.param_set_version = loader.param_set_version
	st.rng.set_state_scalar(0, seed_v)
	var cmds: JWCommands = JWCommands.new()
	cmds.allocate()
	var events: JWEventEngine = JWEventEngine.new()
	events.allocate()
	var runner: JWTurnRunner = JWTurnRunner.new(st, events)
	var a0: PackedInt64Array = PackedInt64Array()
	a0.resize(JWCommands.ARG_SLOTS)
	for q: int in n_q:
		cmds.submit(JWCommands.Kind.ADVANCE_QUARTER, a0, q, st.policy_defs)
		var code: int = runner.advance_quarter(cmds)
		if code != JWResult.OK:
			break
		out.append(st.state_hash())
	return out
