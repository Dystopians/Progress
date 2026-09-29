## v2 界面会话：持有 JCGame，转发命令、推进与存读档，并把结果以信号告诉界面。
## 界面只经这里（及其 game 的视图与命令接口）读写局面。
class_name JcSession
extends Node

signal changed
signal turn_done(receipt: Dictionary)
signal toast(text: String, bad: bool)
signal game_started

var game: JCGame = null
## 界面状态（跨页共享）
var selected_region: String = "zhongzhou"
var selected_good: String = ""
var map_layer: String = "terrain"
var busy: bool = false


func has_game() -> bool:
	return game != null and game.is_ready()


func views() -> JCViews:
	return game.views()


func new_game(seed: int) -> bool:
	var g: JCGame = JCGame.new()
	if not g.new_game(seed):
		toast.emit(JwText.t("jc.ui.newgame_fail"), true)
		return false
	game = g
	game_started.emit()
	changed.emit()
	return true


func load_slot(slot: String) -> bool:
	var g: JCGame = JCGame.new()
	if not g.load_from(JCGame.save_path(slot)):
		toast.emit(JwText.t("jc.ui.load_fail"), true)
		return false
	game = g
	if g.last_error == "replayed":
		toast.emit(JwText.t("jc.ui.load_replayed"), false)
	game_started.emit()
	changed.emit()
	return true


func save_slot(slot: String) -> bool:
	if not has_game():
		return false
	var ok: bool = game.save_to(JCGame.save_path(slot))
	toast.emit(JwText.t("jc.ui.saved") if ok else JwText.t("jc.ui.save_fail"), not ok)
	return ok


## 下一道命令；被拒时弹出原因。
func order(cmd: Dictionary, quiet: bool = false) -> Dictionary:
	if not has_game():
		return {"ok": false, "reason": "reason.no_game"}
	var r: Dictionary = game.order(cmd)
	if not bool(r.get("ok", false)):
		toast.emit(JcFmt.reason(game, r), true)
	elif not quiet:
		toast.emit(JwText.t("jc.ui.order_ok"), false)
	changed.emit()
	return r


func check(cmd: Dictionary) -> Dictionary:
	if not has_game():
		return {"ok": false, "reason": "reason.no_game"}
	return game.check(cmd)


func undo() -> void:
	if has_game() and game.undo_last():
		toast.emit(JwText.t("jc.ui.undone"), false)
		changed.emit()


func end_turn() -> Dictionary:
	if not has_game() or busy:
		return {}
	busy = true
	var before: Dictionary = game.status()
	var r: Dictionary = game.end_turn()
	busy = false
	var rc: Dictionary = r.duplicate()
	rc["before"] = before
	turn_done.emit(rc)
	changed.emit()
	return r


func fast_forward(n: int) -> Dictionary:
	if not has_game() or busy:
		return {}
	busy = true
	var before: Dictionary = game.status()
	var r: Dictionary = game.fast_forward(n)
	busy = false
	var rc: Dictionary = game.last_receipt.duplicate()
	rc["before"] = before
	turn_done.emit(rc)
	changed.emit()
	return r


func set_steward(domain: String, mode: int, stance: String = "") -> void:
	if has_game() and game.set_steward(domain, mode, stance):
		changed.emit()


func approve(i: int) -> void:
	if has_game():
		var r: Dictionary = game.approve(i)
		if not bool(r.get("ok", false)):
			toast.emit(JcFmt.reason(game, r), true)
		changed.emit()


func approve_all() -> void:
	if has_game():
		var n: int = game.approve_all()
		toast.emit(JwText.render("jc.ui.approved_n", {"n": str(n)}), false)
		changed.emit()


func reject(i: int) -> void:
	if has_game():
		game.reject(i)
		changed.emit()


func accept_advice(id: String) -> void:
	if not has_game():
		return
	var r: Dictionary = game.accept_advice(id)
	if not bool(r.get("ok", false)):
		var why: String = ""
		for x: Dictionary in r.get("results", []):
			if not bool(x.get("ok", false)):
				why = JcFmt.reason(game, x)
		toast.emit(why if why != "" else JwText.t("jc.ui.advice_fail"), true)
	else:
		toast.emit(JwText.t("jc.ui.advice_done"), false)
	changed.emit()


func dismiss_advice(id: String) -> void:
	if has_game():
		game.dismiss_advice(id)
		changed.emit()
