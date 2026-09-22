## 诊断：载入后打印税制初值（P01/P02 参数槽、征收能力）。
extends SceneTree


func _init() -> void:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all("res://content", st)
	print("load ok=%s" % str(res.ok))
	print("tax_capacity_ppm = %d" % st.treasury.tax_capacity_ppm)
	var pp: PackedInt64Array = st.policy.params_ppm_array()
	var nz: int = 0
	for v: int in pp:
		if v != 0:
			nz += 1
	print("policy params 长度 = %d，非零 %d 个" % [pp.size(), nz])
	for p: int in 2:
		var line: String = "  P0%d 槽:" % (p + 1)
		for s: int in 6:
			line += " %d" % pp[JWIds.idx_policy_param(p, s)]
		print(line)
	var en: String = ""
	for p: int in st.policy.enabled.size():
		en += str(st.policy.enabled[p])
	print("enabled = %s" % en)
	quit(0)
