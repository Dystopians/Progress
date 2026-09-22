## 诊断：载入出厂内容包，逐条打印加载器错误与未处理故障。
## 用法：godot --headless --path <根> --script res://tools/diag_load.gd
extends SceneTree


func _init() -> void:
	JWResult.clear_pending()
	var loader: JWContentLoader = JWContentLoader.new()
	var st: JWSimState = JWSimState.new()
	var rc: JWResult = loader.load_all("res://content", st)
	print("load_all -> ok=%s code=%d" % [str(rc.ok), rc.code])
	print("errors: %d" % loader.errors.size())
	for i: int in loader.errors.size():
		var e: JWResult = loader.errors[i]
		print("  [%d] code=%d a=%d b=%d @ %s" % [i, e.code, e.detail_a, e.detail_b, loader.error_where(i)])
	if JWResult.has_pending():
		print("pending fault: code=%d step=%d" % [JWResult.pending_code(), JWResult.pending_step()])
	quit(0)
