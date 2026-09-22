## 诊断：载入后打印外部世界与投资相关初值。
extends SceneTree


func _init() -> void:
	var st: JWSimState = JWSimState.new()
	st.allocate_all()
	var loader: JWContentLoader = JWContentLoader.new()
	var res: JWResult = loader.load_all("res://content", st)
	print("load ok=%s" % str(res.ok))
	print("base_export_uqs    = %s" % str(st.world.base_export_uqs))
	print("export_demand_ppm  = %s" % str(st.world.export_demand_ppm))
	quit(0)
