## 发布包样例存档生成（docs/41 §2「样例存档」）。
##
## 经应用层门面 JWGame（唯一合法写入路径）开三局、按固定命令序列推进并存档：
##   sample_q00        新开局（第 0 季，未推进）
##   sample_q08_grid   第 0 季在海岬立项电网升级（P04，发债），第 3 季预算审议时把第一档税率调到 22%，推进到第 8 季
##   sample_q16_shock  换一个会在前 16 季触发外部冲击的种子，不作为推进到第 16 季（展示冲击与预算审查）
## 存档写在 user://saves/<slot>/；运行结束打印其绝对路径，发布时整目录拷进 release/saves/。
## **必须在全部引擎与内容改动之后生成**：读档核对 content_hash，改过内容的旧样例只能只读检视（INV-134）。
## 用法：godot --headless --path <根> --script res://tools/make_sample_saves.gd -- [冲击种子=42]
extends SceneTree

const HORIZON_Q: int = 40
const BASE_SEED: int = 1000000


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var shock_seed: int = int(args[0]) if args.size() > 0 else 42
	var ok: bool = true
	ok = _make("sample_q00", BASE_SEED, 0, []) and ok
	# 命令：[季, kind, 参数…]（参数按 JWCommands 的槽位，未写的槽为 0）。
	ok = _make("sample_q08_grid", BASE_SEED, 8, [
		[0, JWCommands.Kind.PROJECT_LAUNCH, 3, JWUnits.Region.HAIJIA, 1_000_000, 1],
		[3, JWCommands.Kind.POLICY_SET_PARAMS, 0, 400000, 250000, 1200000, 220000],
	]) and ok
	ok = _make("sample_q16_shock", shock_seed, 16, [], true) and ok
	print("存档目录：%s" % ProjectSettings.globalize_path("user://saves/"))
	quit(0 if ok else 1)


func _make(slot: String, seed_v: int, n_q: int, plan: Array, need_shock: bool = false) -> bool:
	var game: JWGame = JWGame.new()
	var r0: JWResult = game.new_game("res://content", seed_v, HORIZON_Q)
	if r0 == null or not r0.ok:
		print("%s：开局失败（%d）" % [slot, 0 if r0 == null else r0.code])
		return false
	for q: int in n_q:
		for step: Array in plan:
			if int(step[0]) != q:
				continue
			var a: PackedInt64Array = PackedInt64Array()
			a.resize(JWCommands.ARG_SLOTS)
			a.fill(0)
			for j: int in range(2, step.size()):
				a[j - 2] = int(step[j])
			var rs: JWResult = game.submit_command(int(step[1]), a)
			print("%s 第 %d 季递交命令 %d：%s" % [slot, q, int(step[1]),
					"受理入档" if rs == null or rs.ok else "形状拒绝 %d" % rs.code])
		# 每季命令流必须以恰好一条 advance_quarter 标记结尾（docs/11 §6.1 kind 99）。
		var a0: PackedInt64Array = PackedInt64Array()
		a0.resize(JWCommands.ARG_SLOTS)
		a0.fill(0)
		game.submit_command(JWCommands.Kind.ADVANCE_QUARTER, a0)
		var ra: JWResult = game.advance_quarter()
		if ra != null and not ra.ok:
			print("%s：第 %d 季推进返回 %d" % [slot, q, ra.code])
			return false
		# 形状受理不等于结算受理：逐条核对本季递交的命令在 S02 是否真的被受理（被拒即样例作废）。
		var cmds: JWCommands = game.get("_cmds") as JWCommands
		for i: int in cmds.count:
			if int(cmds.c_issued_q[i]) == q and int(cmds.c_kind[i]) != JWCommands.Kind.ADVANCE_QUARTER 					and int(cmds.c_accepted[i]) != 1:
				print("%s：第 %d 季命令 %d 在结算时被拒，码 %d" % [slot, q, int(cmds.c_kind[i]), int(cmds.c_reject_code[i])])
				return false
	var st: JWSimState = game.get("_st") as JWSimState
	if need_shock:
		var seen: bool = false
		for k: int in st.shocks.active.size():
			if st.shocks.active[k] == 1 or st.shocks.last_end_q[k] != JWShocks.LAST_END_NONE:
				seen = true
		if not seen:
			print("%s：种子 %d 前 %d 季没有触发任何外部冲击，换一个种子" % [slot, seed_v, n_q])
			return false
	var rsv: JWResult = game.save_game(slot)
	if rsv == null or not rsv.ok:
		print("%s：存档失败（%d）" % [slot, 0 if rsv == null else rsv.code])
		return false
	# 读档往返：另起一局读回，状态哈希必须逐位相同，且不是只读模式（内容指纹一致）。
	var g2: JWGame = JWGame.new()
	g2.new_game("res://content", seed_v, HORIZON_Q)
	var rl: JWResult = g2.load_game(slot)
	if (rl != null and not rl.ok) or g2.read_only_mode:
		print("%s：读档失败或进入只读（%s）" % [slot, "只读" if g2.read_only_mode else str(rl.code)])
		return false
	if (g2.get("_st") as JWSimState).state_hash() != st.state_hash():
		print("%s：读档往返后状态哈希不一致" % slot)
		return false
	# 权威重放：从第 0 季按命令流逐季重放，逐季比对（INV-133）。
	var rv: JWResult = g2.verify_replay(slot)
	if rv != null and not rv.ok:
		print("%s：权威重放不一致（%d）" % [slot, rv.code])
		return false
	print("%s：已存、往返与重放核对通过（种子 %d，第 %d 季）" % [slot, seed_v, n_q])
	return true
