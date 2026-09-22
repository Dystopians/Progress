## JwCommitTimeline 的绘图区（自绘，bg.abyss 底）：表头季号、四条泳道（柱高按全表最大值归一）、合计行。
class_name JwCommitPlot
extends Control

var timeline: JwCommitTimeline = null

const LABEL_W: float = 118.0
const HEAD_H: float = 24.0
const LANE_H: float = 40.0
const TOTAL_H: float = 26.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), JwTheme.c("bg.abyss"), true)
	if timeline == null:
		return
	var font: Font = JwTheme.font("caption")
	var fs: int = JwTheme.size("caption")
	var n: int = timeline.n_q
	var q0: int = int(timeline.schedule.get("q0", 0))
	var cw: float = (size.x - LABEL_W - 8.0) / float(maxi(n, 1))
	var sec: Color = JwTheme.c("text.secondary")
	# 全表最大值（柱高归一的公共尺度：四泳道可以直接比较）。
	var vmax: int = 1
	for lane: String in JwCommitTimeline.LANES:
		for v: int in timeline.lane_values(lane):
			vmax = maxi(vmax, v)
	# 表头：季号。
	for t: int in n:
		var cx: float = LABEL_W + cw * float(t)
		draw_string(font, Vector2(cx + 4, HEAD_H - 7), JwText.render("chart.q", {"q": JwFormat.q2(q0 + t)}),
				HORIZONTAL_ALIGNMENT_LEFT, cw - 6, fs, sec)
	# 泳道。
	for li: int in JwCommitTimeline.LANES.size():
		var lane: String = JwCommitTimeline.LANES[li]
		var y0: float = HEAD_H + LANE_H * float(li)
		draw_line(Vector2(0, y0), Vector2(size.x, y0), JwTheme.c("line.hair"), 1.0)
		draw_string(font, Vector2(8, y0 + LANE_H * 0.62), JwText.t("ct.lane." + lane), HORIZONTAL_ALIGNMENT_LEFT,
				LABEL_W - 12, fs, sec)
		var col: Color = JwTheme.c(JwCommitTimeline.LANE_TOKENS[li])
		var vals: PackedInt64Array = timeline.lane_values(lane)
		for t2: int in mini(n, vals.size()):
			var v2: int = vals[t2]
			if v2 <= 0:
				continue
			var cx2: float = LABEL_W + cw * float(t2)
			var bh: float = maxf((LANE_H - 18.0) * float(v2) / float(vmax), 2.0)
			draw_rect(Rect2(Vector2(cx2 + 4, y0 + LANE_H - 4 - bh), Vector2(cw * 0.34, bh)), col, true)
			draw_string(font, Vector2(cx2 + 4 + cw * 0.38, y0 + LANE_H - 7), JwFormat.u_num(v2), HORIZONTAL_ALIGNMENT_LEFT,
					cw * 0.6, fs, sec)
	# 合计行。
	var yt: float = HEAD_H + LANE_H * float(JwCommitTimeline.LANES.size())
	draw_line(Vector2(0, yt), Vector2(size.x, yt), JwTheme.c("line.strong"), 1.0)
	draw_string(font, Vector2(8, yt + TOTAL_H * 0.7), JwText.t("ct.total"), HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 12, fs,
			JwTheme.c("text.primary"))
	for t3: int in n:
		var cx3: float = LABEL_W + cw * float(t3)
		draw_string(font, Vector2(cx3 + 4, yt + TOTAL_H * 0.7), JwFormat.u_num(timeline.total_at(t3)),
				HORIZONTAL_ALIGNMENT_LEFT, cw - 6, fs, JwTheme.c("text.primary"))
