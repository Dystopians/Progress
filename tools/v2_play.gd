## v2 行动脚本的无界面执行器：按脚本经 JCGame 推进，每年打印一行摘要。
## 用法：godot --headless --path . --script res://tools/v2_play.gd -- <脚本.json> [seed=N] [until=1750] [every=4] [log]
##   脚本路径可以是 res:// 或本机路径；seed / until 覆盖脚本里的值；log 打印托管与顾问办过的事。
extends SceneTree

const U: float = 10000000.0


func _init() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.is_empty():
		print("用法：-- <脚本.json> [seed=N] [until=1750] [every=4] [log]")
		quit(2)
		return
	var ps: JCPlayscript = JCPlayscript.from_file(a[0])
	if not ps.errors.is_empty():
		print("脚本读不了：", ps.errors)
		quit(2)
		return
	var every: int = 4
	for s: String in a:
		if s.begins_with("seed="):
			ps.data["seed"] = int(s.substr(5))
		elif s.begins_with("until="):
			ps.data["until"] = s.substr(6)
		elif s.begins_with("every="):
			every = maxi(1, int(s.substr(6)))
	var game: JCGame = JCGame.new()
	if not game.new_game(int(ps.data.get("seed", 1))):
		print("开局失败：", game.last_error)
		quit(1)
		return
	var t0: int = Time.get_ticks_msec()
	print("年份    人口万  产值万两 失业%  生活%  国库万  债务万  收支万  时代 世界 合法% 危机 研究点 托管办")
	if not ps.bind(game):
		print("脚本有误：", ps.errors)
	var until_q: int = ps.until_q(game)
	var last_done: int = 0
	while game.st.q < until_q and game.st.over == 0:
		var r: Dictionary = ps.step(game, mini(until_q, game.st.q + every))
		if not bool(r.get("ok", false)):
			print("出错：", r)
			break
		var done: int = game.steward.records.size()
		_row(game, done - last_done)
		last_done = done
		if game.st.over == 1:
			print("终局：%s（%d 年）" % [game.st.over_reason, game.st.year()])
			break
	print("用时 %.1f 秒" % [(Time.get_ticks_msec() - t0) / 1000.0])
	if a.has("log"):
		for e: Dictionary in game.steward.records.slice(maxi(0, game.steward.records.size() - 80)):
			print("  %d %s %s %s %s" % [int(e["q"]), e["domain"], e["reason"], "成" if bool(e["ok"]) else "未成：" + String(e["why"]),
					JSON.stringify(e["slots"])])
	quit(0)


func _row(g: JCGame, done: int) -> void:
	var st: JCState = g.st
	var l: Dictionary = st.last
	var f: Dictionary = g.analyst.fiscal()
	print("%d%s %7.0f %8.0f %5.1f %6.1f %7.0f %7.0f %7.0f  %d    %d  %5.1f  %d%d%d %6d %4d" % [
		st.year() if st.season() > 0 else st.year() - 1, ["春", "夏", "秋", "冬"][(st.q - 1) % 4],
		float(l.get("pop", 0)) / 10000.0, float(l.get("gdp", 0)) / U, float(l.get("unemp_ppm", 0)) / 10000.0,
		float(l.get("living", 0)) / 10000.0, float(st.treasury) / U, float(st.debt) / U, float(int(f["balance"])) / U,
		st.era, st.world_era, float(st.legitimacy) / 10000.0, st.cr_stage[0], st.cr_stage[1], st.cr_stage[2],
		st.points, done])
