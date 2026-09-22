## SoA 终态行压实与稳定实体号（docs/18 R-CAP-01；docs/53 M1-4）。
extends JWTest


func _pq(n: int) -> JWProjectQueue:
	var pq: JWProjectQueue = JWProjectQueue.new()
	pq.allocate()
	for p: int in n:
		var terminal: bool = p % 2 == 0
		pq.status[p] = JWUnits.ProjectStatus.COMMISSIONED if terminal else JWUnits.ProjectStatus.IN_PROGRESS
		pq.slot_held[p] = 0 if terminal else 1
		pq.entity[p] = 100 + p
		pq.id[p] = "project.q000_%d" % (100 + p)
		pq.total_cost[p] = 1000 + p
		pq.commissioned_q[p] = p if terminal else -1
		for k: int in JWProjectQueue.LINE_N:
			pq.paid[p * JWProjectQueue.LINE_N + k] = p * 10 + k
	pq.count = n
	return pq


func test_projects_below_threshold_untouched() -> void:
	var pq: JWProjectQueue = _pq(48)
	eq_int(pq.compact_terminal(), 0, "用满不到四分之三（48 / 64）⇒ 不压实")
	eq_int(pq.count, 48, "行数不变")


func test_projects_compact_preserves_order_and_rows() -> void:
	var pq: JWProjectQueue = _pq(50)
	eq_int(pq.compact_terminal(), 25, "移除 25 个终态行")
	eq_int(pq.count, 25, "剩 25 行")
	for i: int in 25:
		var old: int = 2 * i + 1
		eq_int(pq.entity[i], 100 + old, "第 %d 行是原第 %d 行（顺序保持）" % [i, old])
		eq_int(pq.total_cost[i], 1000 + old, "单格列随行移动")
		eq_str(pq.id[i], "project.q000_%d" % (100 + old), "ID 随行移动")
		for k: int in JWProjectQueue.LINE_N:
			eq_int(pq.paid[i * JWProjectQueue.LINE_N + k], old * 10 + k, "三线列随行移动")
	eq_int(pq.entity[25], -1, "腾出的行实体号复位为 −1")
	eq_int(pq.commissioned_q[30], -1, "腾出的行投运季复位为 −1")
	eq_str(pq.id[40], "", "腾出的行 ID 清空")
	eq_int(pq.slot_of_entity(105), 2, "按实体号找到新行号")
	eq_int(pq.slot_of_entity(104), -1, "已归档的实体找不到 ⇒ 命令判 NOT_FOUND")


func test_slot_held_terminal_is_kept() -> void:
	var pq: JWProjectQueue = _pq(50)
	pq.slot_held[0] = 1
	pq.compact_terminal()
	eq_int(pq.entity[0], 100, "仍占施工槽位的终态行不归档")


func test_bonds_compact() -> void:
	var bb: JWBondBook = JWBondBook.new()
	bb.allocate()
	var n: int = 400
	for b: int in n:
		var done: bool = b % 4 != 3
		bb.status[b] = JWUnits.BondStatus.MATURED if done else JWUnits.BondStatus.ACTIVE
		bb.principal_outstanding[b] = 0 if done else 1000
		bb.entity[b] = b - 5
		bb.id[b] = "bond.q000_%d" % b
		bb.amort_schedule[b * JWBondBook.HORIZON_MAX + 1] = b
	bb.count = n
	eq_int(bb.compact_terminal(), 300, "移除 300 个已清偿批次")
	eq_int(bb.count, 100, "剩 100 批")
	eq_int(bb.entity[0], 3 - 5, "第 0 行是原第 3 批")
	eq_int(bb.amort_schedule[1 * JWBondBook.HORIZON_MAX + 1], 7, "分期表整行随批次移动")
	eq_int(bb.amort_schedule[100 * JWBondBook.HORIZON_MAX + 1], 0, "腾出的分期表行清零")
	eq_int(bb.slot_of_entity(7 - 5), 1, "按实体号找到新行号")


func test_opening_bonds_have_negative_entities() -> void:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var ld: JWContentLoader = JWContentLoader.new()
	check(ld.load_all("res://content", st).ok, "载入")
	eq_int(st.bonds.entity[0], -1, "开局第 0 批实体号 −1")
	eq_int(st.bonds.slot_of_entity(-2), 1, "−2 对应第 1 批")
