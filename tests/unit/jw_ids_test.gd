## JWIds 单元测试：稠密下标布局（docs/10 §0.5、docs/17 §2.2–§2.4）与 ID 映射表的生命周期。
##
## 覆盖点：索引函数的双射与值域、反解往返、主体/科目下标布局、
## 注册与解析、重复与格式拒绝、freeze 的齐全性检查、冻结后的「零字符串」状态。
##
## 布局是契约的一部分：这些断言里的数值不是「当前实现恰好是这样」，
## 而是「改了就要升 schema_version 并写迁移函数」（INV-136）。
extends JWTest


func before_each() -> void:
	JWResult.clear_pending()
	JWResult.set_step(0)


func after_each() -> void:
	JWResult.clear_pending()


# ── 索引函数：双射与值域 ───────────────────────────────────────────────────

func test_idx_cell_is_a_bijection_onto_0_15() -> void:
	var seen: PackedInt64Array = PackedInt64Array()
	seen.resize(JWUnits.CELL)
	for r: int in JWUnits.R:
		for s: int in JWUnits.S:
			var c: int = JWIds.idx_cell(r, s)
			in_range_int(c, 0, JWUnits.CELL - 1, "idx_cell 值域")
			seen[c] = seen[c] + 1
	eq_int(JWMath.sum(seen), JWUnits.CELL, "覆盖 16 个下标")
	for i: int in JWUnits.CELL:
		eq_int(seen[i], 1, "每个下标恰好命中一次（双射）")


func test_idx_cell_layout_is_region_major() -> void:
	eq_int(JWIds.idx_cell(0, 0), 0, "北原·农业 == 0")
	eq_int(JWIds.idx_cell(0, 3), 3, "北原·服务 == 3")
	eq_int(JWIds.idx_cell(1, 0), 4, "中州·农业 == 4，说明是地区在前")
	eq_int(JWIds.idx_cell(3, 3), 15, "西岭·服务 == 15")


func test_idx_group_is_a_bijection_onto_0_35() -> void:
	var seen: PackedInt64Array = PackedInt64Array()
	seen.resize(JWUnits.GROUP)
	for r: int in JWUnits.R:
		for a: int in JWUnits.A:
			for k: int in JWUnits.K:
				var g: int = JWIds.idx_group(r, a, k)
				in_range_int(g, 0, JWUnits.GROUP - 1, "idx_group 值域")
				seen[g] = seen[g] + 1
	eq_int(JWMath.sum(seen), JWUnits.GROUP, "覆盖 36 个下标")
	for i: int in JWUnits.GROUP:
		eq_int(seen[i], 1, "每个下标恰好命中一次（双射）")


func test_idx_group_layout() -> void:
	eq_int(JWIds.idx_group(0, 0, 0), 0, "北原·未成年·低技能 == 0")
	eq_int(JWIds.idx_group(0, 1, 0), 3, "age 的步长是 3")
	eq_int(JWIds.idx_group(1, 0, 0), 9, "region 的步长是 9")
	eq_int(JWIds.idx_group(3, 2, 2), 35, "西岭·老年·高技能 == 35")


func test_reverse_of_cell_roundtrip() -> void:
	for r: int in JWUnits.R:
		for s: int in JWUnits.S:
			var c: int = JWIds.idx_cell(r, s)
			eq_int(JWIds.region_of_cell(c), r, "region 反解往返")
			eq_int(JWIds.sector_of_cell(c), s, "sector 反解往返")
	check_false(JWResult.has_pending(), "合法下标不登记故障")


func test_reverse_of_group_roundtrip() -> void:
	for r: int in JWUnits.R:
		for a: int in JWUnits.A:
			for k: int in JWUnits.K:
				var g: int = JWIds.idx_group(r, a, k)
				if JWIds.region_of_group(g) != r or JWIds.age_of_group(g) != a \
						or JWIds.skill_of_group(g) != k:
					fail("group %d 反解不等于 (%d, %d, %d)" % [g, r, a, k])
	eq_int(JWIds.region_of_group(35), 3, "末位群组的地区")
	eq_int(JWIds.age_of_group(35), 2, "末位群组的年龄段")
	eq_int(JWIds.skill_of_group(35), 2, "末位群组的技能档")
	check_false(JWResult.has_pending(), "合法下标不登记故障")


func test_reverse_tables_have_contract_lengths() -> void:
	eq_int(JWIds.REGION_OF_CELL.size(), JWUnits.CELL, "cell→region 表长")
	eq_int(JWIds.SECTOR_OF_CELL.size(), JWUnits.CELL, "cell→sector 表长")
	eq_int(JWIds.REGION_OF_GROUP.size(), JWUnits.GROUP, "group→region 表长")
	eq_int(JWIds.AGE_OF_GROUP.size(), JWUnits.GROUP, "group→age 表长")
	eq_int(JWIds.SKILL_OF_GROUP.size(), JWUnits.GROUP, "group→skill 表长")


func test_reverse_out_of_range_registers_fault() -> void:
	eq_int(JWIds.region_of_cell(JWUnits.CELL), 0, "越界返回 0")
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE, "登记 INDEX_OUT_OF_RANGE")
	JWResult.clear_pending()
	eq_int(JWIds.skill_of_group(-1), 0, "负下标返回 0")
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE, "登记 INDEX_OUT_OF_RANGE")


func test_other_index_functions_bounds() -> void:
	eq_int(JWIds.idx_io(0, 0), 0, "io 起点")
	eq_int(JWIds.idx_io(JWUnits.S - 1, JWUnits.S - 1), JWUnits.IO_N - 1, "io 终点 == 15")
	eq_int(JWIds.idx_inv(0, 0), 0, "inv 起点")
	eq_int(JWIds.idx_inv(JWUnits.CELL - 1, JWUnits.S - 1), JWUnits.INV_N - 1, "inv 终点 == 63")
	eq_int(JWIds.idx_emp(JWUnits.CELL - 1, JWUnits.K - 1), JWUnits.EMP_N - 1, "emp 终点 == 47")
	eq_int(JWIds.idx_od(JWUnits.R - 1, JWUnits.R - 1), JWUnits.OD_N - 1, "od 终点 == 15")
	eq_int(JWIds.idx_group_emp(JWUnits.GROUP - 1, JWUnits.S), JWUnits.GROUP_EMP_N - 1,
			"group_emp 终点 == 179（slot 4 是 pubserv）")
	eq_int(JWIds.idx_group_svc(JWUnits.GROUP - 1, JWUnits.SERVICE_KIND - 1),
			JWUnits.GROUP_SVC_N - 1, "group_svc 终点 == 107")
	eq_int(JWIds.idx_group_prod(JWUnits.GROUP - 1, JWUnits.S - 1), JWUnits.GROUP_PROD_N - 1,
			"group_prod 终点 == 143")
	eq_int(JWIds.idx_edu(JWUnits.GROUP - 1, JWUnits.EDU_SLOT - 1), JWUnits.EDU_N - 1,
			"edu 终点 == 287")
	eq_int(JWIds.idx_pubserv_emp(JWUnits.R - 1, JWUnits.K - 1), JWUnits.PUBSERV_EMP_N - 1,
			"pubserv_emp 终点 == 11")
	eq_int(JWIds.idx_pubserv_queue(JWUnits.R - 1, JWUnits.SERVICE_KIND - 1),
			JWUnits.PUBSERV_QUEUE_N - 1, "pubserv_queue 终点 == 11")
	eq_int(JWIds.idx_market(JWUnits.S - 1, JWUnits.BUYER_CLASS_N - 1), JWUnits.MARKET_N - 1,
			"market 终点 == 19")
	eq_int(JWIds.idx_stance(JWUnits.BLOC_N - 1, JWUnits.POLICY_N - 1), JWUnits.STANCE_N - 1,
			"stance 终点 == 35")
	eq_int(JWIds.idx_affil(JWUnits.GROUP - 1, JWUnits.BLOC_N - 1), JWUnits.AFFIL_N - 1,
			"affil 终点 == 107")
	eq_int(JWIds.idx_opex(JWUnits.R - 1, JWUnits.SERVICE_KIND - 1), JWUnits.OPEX_N - 1,
			"opex 终点 == 11")


func test_idx_policy_param_stride_matches_dimensions() -> void:
	# 索引函数里不许出现除法，故行宽写成常量；这条断言就是那个常量的看门人。
	eq_int(JWIds.POLICY_PARAM_STRIDE * JWUnits.POLICY_N, JWUnits.POLICY_PARAM_N,
			"行宽 × 政策数 == 政策参数总槽位")
	eq_int(JWIds.idx_policy_param(0, 0), 0, "policy_param 起点")
	eq_int(JWIds.idx_policy_param(JWUnits.POLICY_N - 1, JWIds.POLICY_PARAM_STRIDE - 1),
			JWUnits.POLICY_PARAM_N - 1, "policy_param 终点 == 47")


func test_idx_account_layout() -> void:
	eq_int(JWIds.idx_account(JWIds.AGENT_GOV, JWIds.ACC_CASH), 0, "政府现金 == 0")
	eq_int(JWIds.idx_account(JWIds.AGENT_OPENING, JWIds.ACC_NW), JWUnits.ACCOUNT_N - 1,
			"开账主体的净值 == 899")
	eq_int(JWIds.ACC_INV_BASE + JWUnits.Sector.SERVICES, 4, "库存科目按部门连排到 4")
	eq_int(JWUnits.ACCOUNT_CODE_N, JWIds.ACC_NW + 1, "科目码总数 == 最后一个科目 + 1")
	eq_int(JWUnits.AGENT_N * JWUnits.ACCOUNT_CODE_N, JWUnits.ACCOUNT_N, "账户总数 == 60 × 15")


# ── 主体下标布局（docs/17 §2.3） ───────────────────────────────────────────

func test_agent_layout_is_contiguous_and_complete() -> void:
	eq_int(JWIds.AGENT_CELL_BASE, JWIds.AGENT_GOV + 1, "gov 之后紧接 cell 段")
	eq_int(JWIds.AGENT_PUBSERV_BASE, JWIds.AGENT_CELL_BASE + JWUnits.CELL, "cell 段占 16 位")
	eq_int(JWIds.AGENT_GROUP_BASE, JWIds.AGENT_PUBSERV_BASE + JWUnits.PUBSERV, "pubserv 段占 4 位")
	eq_int(JWIds.AGENT_INVPOOL, JWIds.AGENT_GROUP_BASE + JWUnits.GROUP, "group 段占 36 位")
	eq_int(JWIds.AGENT_ROW, JWIds.AGENT_INVPOOL + 1, "invpool 之后是 row")
	eq_int(JWIds.AGENT_OPENING, JWIds.AGENT_ROW + 1, "row 之后是 opening")
	eq_int(JWIds.AGENT_OPENING + 1, JWUnits.AGENT_N, "主体总数恰为 60，无空洞")
	eq_int(JWUnits.AGENT_N - JWUnits.PUBSERV, JWIds.AGENT_CASH_ACCOUNTS,
			"现金科目口径 == 全部主体减 4 个 pubserv")
	eq_int(JWIds.AGENT_CASH_ACCOUNTS - 1, JWIds.AGENT_CASH_ACTIVE,
			"活跃现金主体 == 现金科目数减去恒为 0 的 agent.opening（OQ-217）")


func test_agent_of_cell_roundtrip() -> void:
	for c: int in JWUnits.CELL:
		var a: int = JWIds.agent_of_cell(c)
		in_range_int(a, JWIds.AGENT_CELL_BASE, JWIds.AGENT_PUBSERV_BASE - 1, "cell 主体值域")
		eq_int(JWIds.cell_of_agent(a), c, "cell 主体反解往返")


func test_agent_of_group_roundtrip() -> void:
	for g: int in JWUnits.GROUP:
		var a: int = JWIds.agent_of_group(g)
		in_range_int(a, JWIds.AGENT_GROUP_BASE, JWIds.AGENT_INVPOOL - 1, "group 主体值域")
		eq_int(JWIds.group_of_agent(a), g, "group 主体反解往返")


func test_agent_of_pubserv() -> void:
	eq_int(JWIds.agent_of_pubserv(0), 17, "北原公共服务 == 17")
	eq_int(JWIds.agent_of_pubserv(JWUnits.R - 1), 20, "西岭公共服务 == 20")


func test_non_matching_agents_return_minus_one() -> void:
	eq_int(JWIds.cell_of_agent(JWIds.AGENT_GOV), -1, "政府不是 cell")
	eq_int(JWIds.cell_of_agent(JWIds.AGENT_PUBSERV_BASE), -1, "pubserv 不是 cell")
	eq_int(JWIds.cell_of_agent(JWIds.AGENT_OPENING), -1, "开账主体不是 cell")
	eq_int(JWIds.group_of_agent(JWIds.AGENT_GOV), -1, "政府不是 group")
	eq_int(JWIds.group_of_agent(JWIds.AGENT_INVPOOL), -1, "投资池不是 group")
	eq_int(JWIds.group_of_agent(JWIds.AGENT_ROW), -1, "外部世界不是 group")
	eq_int(JWIds.group_of_agent(JWIds.AGENT_PUBSERV_BASE), -1, "pubserv 不是 group")
	check_false(JWResult.has_pending(), "「不是这一类」是正常查询结果，不是故障")


# ── 映射表：注册、解析、反查 ───────────────────────────────────────────────

func test_register_resolve_roundtrip() -> void:
	var ids: JWIds = JWIds.new()
	var r: JWResult = ids.register(JWIds.IdKind.REGION, "region.beiyuan", 0)
	check(r.ok, "登记成功")
	eq_int(r.code, 0, "成功结果码为 0")
	eq_int(ids.resolve(JWIds.IdKind.REGION, "region.beiyuan"), 0, "正查")
	eq_str(ids.id_of(JWIds.IdKind.REGION, 0), "region.beiyuan", "反查")
	eq_int(ids.count_of(JWIds.IdKind.REGION), 1, "计数为 1")
	eq_int(ids.resolve(JWIds.IdKind.REGION, "region.nowhere"), -1, "未登记返回 −1")
	check_false(JWResult.has_pending(), "未登记不是故障")


func test_register_same_id_in_different_kinds() -> void:
	var ids: JWIds = JWIds.new()
	check(ids.register(JWIds.IdKind.SECTOR, "sector.agri", 0).ok, "登记 sector")
	check(ids.register(JWIds.IdKind.POLICY, "sector.agri", 7).ok, "同名字符串在别的 kind 下可共存")
	eq_int(ids.resolve(JWIds.IdKind.SECTOR, "sector.agri"), 0, "各查各的")
	eq_int(ids.resolve(JWIds.IdKind.POLICY, "sector.agri"), 7, "各查各的")


func test_register_rejects_duplicate_id() -> void:
	var ids: JWIds = JWIds.new()
	check(ids.register(JWIds.IdKind.CELL, "cell.beiyuan.agri", 0).ok, "首次登记成功")
	var dup: JWResult = ids.register(JWIds.IdKind.CELL, "cell.beiyuan.agri", 1)
	check_false(dup.ok, "重复 ID 被拒")
	eq_int(dup.code, JWResult.Load.DUP_ID, "拒绝码为 DUP_ID")
	eq_int(ids.count_of(JWIds.IdKind.CELL), 1, "被拒的登记不得计数")


func test_register_rejects_duplicate_index() -> void:
	var ids: JWIds = JWIds.new()
	check(ids.register(JWIds.IdKind.CELL, "cell.beiyuan.agri", 0).ok, "首次登记成功")
	var dup: JWResult = ids.register(JWIds.IdKind.CELL, "cell.beiyuan.manu", 0)
	check_false(dup.ok, "同一下标被两个 ID 占用即破坏双射")
	eq_int(dup.code, JWResult.Load.DUP_ID, "同样按 DUP_ID 拒绝")
	eq_str(ids.id_of(JWIds.IdKind.CELL, 0), "cell.beiyuan.agri", "反查表不得被覆盖")


func test_register_rejects_bad_id_format() -> void:
	var ids: JWIds = JWIds.new()
	var bad: PackedStringArray = PackedStringArray([
		"Region.beiyuan", "1region", ".region", "region.", "region beiyuan",
		"region-beiyuan", "", "_region", "region..beiyuan",
	])
	for i: int in bad.size():
		var res: JWResult = ids.register(JWIds.IdKind.REGION, bad[i], i)
		if res.ok or res.code != JWResult.Load.ID_FORMAT:
			fail("非法 ID \"%s\" 应以 ID_FORMAT 拒绝" % bad[i])
	eq_int(ids.count_of(JWIds.IdKind.REGION), 0, "非法 ID 一个都没进表")


func test_register_accepts_uppercase_in_later_segments() -> void:
	var ids: JWIds = JWIds.new()
	check(ids.register(JWIds.IdKind.POLICY, "policy.P04", 3).ok, "政策编号段允许大写")
	check(ids.register(JWIds.IdKind.EVENT, "event.E11", 10).ok, "事件编号段允许大写")
	check(ids.register(JWIds.IdKind.SHOCK, "shock.S02", 1).ok, "冲击编号段允许大写")
	check(ids.register(JWIds.IdKind.BOND, "bond.q003_01", 0).ok, "债券批次 ID")
	check(ids.register(JWIds.IdKind.GROUP, "group.beiyuan.working.high", 5).ok, "四段群组 ID")
	eq_int(ids.resolve(JWIds.IdKind.POLICY, "policy.P04"), 3, "大写段可正查")


func test_register_rejects_bad_kind_and_index() -> void:
	var ids: JWIds = JWIds.new()
	var bad_kind: JWResult = ids.register(JWIds.ID_KIND_N, "region.beiyuan", 0)
	check_false(bad_kind.ok, "kind 越界被拒")
	eq_int(bad_kind.code, JWResult.Fault.INDEX_OUT_OF_RANGE, "拒绝码为 INDEX_OUT_OF_RANGE")
	JWResult.clear_pending()
	var bad_index: JWResult = ids.register(JWIds.IdKind.REGION, "region.beiyuan", -1)
	check_false(bad_index.ok, "负下标被拒")
	eq_int(bad_index.code, JWResult.Fault.INDEX_OUT_OF_RANGE, "拒绝码为 INDEX_OUT_OF_RANGE")


func test_id_of_out_of_range() -> void:
	var ids: JWIds = JWIds.new()
	eq_str(ids.id_of(JWIds.IdKind.REGION, 0), "", "未登记的下标反查为空串")
	eq_int(JWResult.pending_code(), JWResult.Fault.INDEX_OUT_OF_RANGE, "登记 INDEX_OUT_OF_RANGE")


# ── freeze：齐全性与「零字符串」状态 ──────────────────────────────────────

func test_freeze_requires_complete_region_set() -> void:
	var ids: JWIds = JWIds.new()
	var res: JWResult = ids.freeze()
	check_false(res.ok, "地区没登记齐不得冻结")
	eq_int(res.code, JWResult.Load.REGION_SET, "拒绝码为 REGION_SET")
	eq_int(res.detail_a, JWUnits.R, "期望值是维度常量")
	eq_int(res.detail_b, 0, "实际值是已登记条数")
	check_false(ids.is_frozen(), "失败的 freeze 不得留下半冻结状态")


func test_freeze_requires_complete_cell_and_group_sets() -> void:
	var ids: JWIds = JWIds.new()
	_register_regions(ids)
	var no_cell: JWResult = ids.freeze()
	check_false(no_cell.ok, "cell 没登记齐不得冻结")
	eq_int(no_cell.code, JWResult.Load.CELL_SET, "拒绝码为 CELL_SET")
	_register_cells(ids)
	var no_group: JWResult = ids.freeze()
	check_false(no_group.ok, "group 没登记齐不得冻结")
	eq_int(no_group.code, JWResult.Load.GROUP_SET, "拒绝码为 GROUP_SET（INV-142）")
	eq_int(no_group.detail_a, JWUnits.GROUP, "期望 36 个群组")


func test_freeze_then_no_more_strings() -> void:
	var ids: JWIds = JWIds.new()
	_register_regions(ids)
	_register_cells(ids)
	_register_groups(ids)
	eq_int(ids.count_of(JWIds.IdKind.GROUP), JWUnits.GROUP, "36 个群组登记齐")
	var ok: JWResult = ids.freeze()
	check(ok.ok, "齐全后冻结成功")
	check(ids.is_frozen(), "已冻结")
	# 冻结后 SimCore 进入零字符串状态：再解析字符串即 PHASE_VIOLATION。
	eq_int(ids.resolve(JWIds.IdKind.REGION, "region.beiyuan"), -1, "冻结后解析返回 −1")
	eq_int(JWResult.pending_code(), JWResult.Fault.PHASE_VIOLATION, "登记 PHASE_VIOLATION")
	JWResult.clear_pending()
	# 反查必须继续可用：故障包与存档的 ids[] 恰恰是冻结之后才写的。
	eq_str(ids.id_of(JWIds.IdKind.REGION, 0), "region.beiyuan", "冻结后反查仍可用")
	check_false(JWResult.has_pending(), "反查不登记故障")


func test_register_after_freeze_is_phase_violation() -> void:
	var ids: JWIds = JWIds.new()
	_register_regions(ids)
	_register_cells(ids)
	_register_groups(ids)
	check(ids.freeze().ok, "冻结成功")
	var late: JWResult = ids.register(JWIds.IdKind.BOND, "bond.q000_01", 0)
	check_false(late.ok, "冻结后不得再登记")
	eq_int(late.code, JWResult.Fault.PHASE_VIOLATION, "拒绝码为 PHASE_VIOLATION")
	eq_int(JWResult.pending_code(), JWResult.Fault.PHASE_VIOLATION, "同时登记故障")


func test_double_freeze_is_phase_violation() -> void:
	var ids: JWIds = JWIds.new()
	_register_regions(ids)
	_register_cells(ids)
	_register_groups(ids)
	check(ids.freeze().ok, "首次冻结成功")
	var again: JWResult = ids.freeze()
	check_false(again.ok, "重复冻结是流水线顺序错误，不是幂等操作")
	eq_int(again.code, JWResult.Fault.PHASE_VIOLATION, "拒绝码为 PHASE_VIOLATION")


func test_two_registries_are_independent() -> void:
	var a: JWIds = JWIds.new()
	var b: JWIds = JWIds.new()
	check(a.register(JWIds.IdKind.REGION, "region.beiyuan", 0).ok, "a 登记")
	eq_int(b.resolve(JWIds.IdKind.REGION, "region.beiyuan"), -1, "b 不受 a 影响（映射表是实例状态）")
	eq_int(b.count_of(JWIds.IdKind.REGION), 0, "b 的计数独立")


# ── 辅助：按契约布局登记完整集合 ──────────────────────────────────────────

const REGION_NAMES: PackedStringArray = ["beiyuan", "zhongzhou", "haijia", "xiling"]
const SECTOR_NAMES: PackedStringArray = ["agri", "manu", "energy", "services"]
const AGE_NAMES: PackedStringArray = ["minor", "working", "elder"]
const SKILL_NAMES: PackedStringArray = ["low", "mid", "high"]


func _register_regions(ids: JWIds) -> void:
	for r: int in JWUnits.R:
		if not ids.register(JWIds.IdKind.REGION, "region.%s" % REGION_NAMES[r], r).ok:
			fail("登记地区 %d 失败" % r)


func _register_cells(ids: JWIds) -> void:
	for r: int in JWUnits.R:
		for s: int in JWUnits.S:
			var id: String = "cell.%s.%s" % [REGION_NAMES[r], SECTOR_NAMES[s]]
			if not ids.register(JWIds.IdKind.CELL, id, JWIds.idx_cell(r, s)).ok:
				fail("登记 %s 失败" % id)


func _register_groups(ids: JWIds) -> void:
	for r: int in JWUnits.R:
		for a: int in JWUnits.A:
			for k: int in JWUnits.K:
				var id: String = "group.%s.%s.%s" % [REGION_NAMES[r], AGE_NAMES[a], SKILL_NAMES[k]]
				if not ids.register(JWIds.IdKind.GROUP, id, JWIds.idx_group(r, a, k)).ok:
					fail("登记 %s 失败" % id)
