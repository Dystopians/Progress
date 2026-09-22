## 改造项目的单季诊断（R-METHOD-01）：建一座工场、改造它，打印故障现场。
extends SceneTree


func _init() -> void:
	JWResult.trace_faults = true
	var g: JWGame = JWGame.new()
	g.autosave_slot = "autosave_diag_retrofit"
	g.new_game("res://content#campaign_1600", 44, 0)
	var st: JWSimState = g.get("_st") as JWSimState
	st.research.completed_mask = (1 << 4) | (1 << 5)
	st.research.advance_research(0)
	var a: PackedInt64Array = PackedInt64Array()
	a.resize(JWCommands.ARG_SLOTS)
	a.fill(0)
	a[0] = 3
	a[1] = 1
	a[2] = JWBuildings.OWNER_GOV
	g.submit_command(JWCommands.Kind.BUILD_BUILDING, a)
	var n0: int = st.buildings.count
	for i: int in 14:
		var e: PackedInt64Array = PackedInt64Array()
		e.resize(JWCommands.ARG_SLOTS)
		e.fill(0)
		g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, e)
		var r: JWResult = g.advance_quarter()
		if r != null and not r.ok:
			print("建造期第 %d 季失败 %d" % [i, r.code])
			quit()
		if st.buildings.count > n0:
			print("第 %d 季建成，新堆 %d" % [i, st.buildings.count - 1])
			break
	var nb: int = st.buildings.count - 1
	var rr: PackedInt64Array = PackedInt64Array()
	rr.resize(JWCommands.ARG_SLOTS)
	rr.fill(0)
	rr[0] = st.buildings.entity[nb]
	rr[1] = 4
	g.submit_command(JWCommands.Kind.RETROFIT_STACK, rr)
	var e2: PackedInt64Array = PackedInt64Array()
	e2.resize(JWCommands.ARG_SLOTS)
	e2.fill(0)
	g.submit_command(JWCommands.Kind.ADVANCE_QUARTER, e2)
	var r2: JWResult = g.advance_quarter()
	print("改造季：ok=%s code=%d step=%d 冻结=%d" % [str(r2 == null or r2.ok), r2.code if r2 else 0,
			JWResult.pending_step(), st.buildings.frozen_ppm[nb]])
	quit()
