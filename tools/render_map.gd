## 舆图底图生成器（docs/57 §13）：按固定的地理骨架与确定的随机数，生成
##   assets/map/jc_geo.json   地区边界（多边形）、河流、城市、港口、标签位置、伙伴方位（界面画矢量用）
##   assets/map/jc_base.png   着色的地形底图（山、原、水田、海、河；不画边界，边界由界面画）
## 用法：godot --headless --path . --script res://tools/render_map.gd
## 同一版本的脚本每次生成的结果逐像素相同；改骨架或配色就重新生成。
extends SceneTree

const W: int = 1600
const H: int = 1000
const SEED: int = 16001

# ── 骨架：交点与边界的控制点（坐标 1600×1000，原点左上） ──
const J1: Vector2 = Vector2(590, 0)        # 西岭 / 北原 / 上边
const J2: Vector2 = Vector2(640, 330)      # 西岭 / 北原 / 中州
const J3: Vector2 = Vector2(600, 1000)     # 西岭 / 中州 / 下边
const J4: Vector2 = Vector2(1110, 390)     # 北原 / 中州 / 海岬
const J5: Vector2 = Vector2(1235, 0)       # 北原 / 海岬 / 上边
const J6: Vector2 = Vector2(930, 1000)     # 中州 / 海岬 / 下边

const COAST: Array = [[1340, 0], [1372, 138], [1328, 282], [1392, 392], [1512, 428], [1594, 468], [1580, 546],
	[1468, 566], [1398, 622], [1322, 772], [1212, 890], [1152, 1000]]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = SEED
	var b_xb: PackedVector2Array = _jag([J1, Vector2(612, 170), J2], 4, 0.16)
	var b_xz: PackedVector2Array = _jag([J2, Vector2(560, 520), Vector2(626, 720), J3], 4, 0.16)
	var b_bz: PackedVector2Array = _jag([J2, Vector2(806, 424), Vector2(968, 398), J4], 4, 0.16)
	var b_zh: PackedVector2Array = _jag([J4, Vector2(1156, 560), Vector2(1026, 724), Vector2(966, 880), J6], 4, 0.16)
	var b_bh: PackedVector2Array = _jag([J4, Vector2(1184, 262), Vector2(1226, 118), J5], 4, 0.16)
	var cpts: Array = []
	for p: Array in COAST:
		cpts.append(Vector2(p[0], p[1]))
	var coast: PackedVector2Array = _jag(cpts, 4, 0.12)
	var regions: Dictionary = {}
	# 西岭：左上角 → J1 → 西北边界 → J2 → 西中边界 → J3 → 左下角
	var xl: PackedVector2Array = PackedVector2Array([Vector2(0, 0)])
	xl.append_array(b_xb)
	xl.append_array(b_xz.slice(1))
	xl.append(Vector2(0, H))
	regions["xiling"] = xl
	# 北原：J1 → 上边 → J5 → 北海边界（反）→ J4 → 北中边界（反）→ J2 → 西北边界（反）
	var bl: PackedVector2Array = PackedVector2Array([J1])
	bl.append_array(_rev(b_bh))
	bl.append_array(_rev(b_bz).slice(1))
	bl.append_array(_rev(b_xb).slice(1, _rev(b_xb).size() - 1))
	regions["beiyuan"] = bl
	# 中州：J2 → 北中边界 → J4 → 中海边界 → J6 → 下边 → J3 → 西中边界（反）
	var zl: PackedVector2Array = PackedVector2Array()
	zl.append_array(b_bz)
	zl.append_array(b_zh.slice(1))
	zl.append_array(_rev(b_xz).slice(0, b_xz.size() - 1))
	regions["zhongzhou"] = zl
	# 海岬：J5 → 上边 → 海岸 → 下边 → J6 → 中海边界（反）→ J4 → 北海边界
	var hl: PackedVector2Array = PackedVector2Array([J5])
	hl.append_array(coast)
	hl.append_array(_rev(b_zh))
	hl.append_array(b_bh.slice(1, b_bh.size() - 1))
	regions["haijia"] = hl
	# 河流
	var rivers: Array = [
		{"id": "dahe", "w": 7.0, "pts": _jag([Vector2(230, 400), Vector2(420, 474), Vector2(560, 530), Vector2(706, 566),
			Vector2(860, 604), Vector2(1006, 646), Vector2(1112, 706), Vector2(1216, 742), Vector2(1318, 768)], 3, 0.10)},
		{"id": "beihe", "w": 4.5, "pts": _jag([Vector2(780, 70), Vector2(846, 214), Vector2(900, 372), Vector2(922, 520),
			Vector2(930, 626)], 3, 0.10)},
		{"id": "xihe", "w": 3.5, "pts": _jag([Vector2(170, 160), Vector2(292, 290), Vector2(366, 402), Vector2(420, 474)], 3, 0.10)},
		{"id": "nanhe", "w": 3.0, "pts": _jag([Vector2(330, 880), Vector2(454, 760), Vector2(560, 650), Vector2(706, 566)], 3, 0.10)},
	]
	var geo: Dictionary = {
		"schema": "jc.map", "version": 1, "size": [W, H],
		"regions": {},
		"coast": _arr(coast),
		"rivers": [],
		"cities": [
			{"region": "zhongzhou", "pos": [846, 578], "capital": true},
			{"region": "beiyuan", "pos": [918, 250], "capital": false},
			{"region": "xiling", "pos": [360, 548], "capital": false},
			{"region": "haijia", "pos": [1360, 470], "capital": false},
		],
		"ports": [{"region": "haijia", "pos": [1436, 540]}, {"region": "haijia", "pos": [1300, 772]}],
		"passes": [{"region": "xiling", "pos": [96, 330]}, {"region": "beiyuan", "pos": [760, 40]}],
		"labels": {"xiling": [300, 720], "beiyuan": [910, 150], "zhongzhou": [800, 780], "haijia": [1262, 360]},
		"partners": {"north_ports": [1480, 70], "south_isles": [1470, 900], "inland_khanate": [40, 260],
			"oceanic_league": [1560, 690], "industrial_power": [1540, 250], "alliance_bloc": [1560, 820]},
		"route_start": {"sea": [1440, 545], "land": [100, 330]},
	}
	for rid: String in regions.keys():
		geo["regions"][rid] = _arr(regions[rid])
	for rv: Dictionary in rivers:
		geo["rivers"].append({"id": rv["id"], "w": rv["w"], "pts": _arr(rv["pts"])})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/map"))
	var f: FileAccess = FileAccess.open("res://assets/map/jc_geo.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(geo, " "))
	f.close()
	var img: Image = _render(regions, rivers, coast)
	img.save_png("res://assets/map/jc_base.png")
	print("地图已生成：assets/map/jc_base.png、assets/map/jc_geo.json")
	quit(0)


# ── 几何 ────────────────────────────────────────────────────────────────
## 把控制点连成的折线做中点位移，得到自然的边界；端点不动，保证相邻地区共用同一条边。
func _jag(pts: Array, depth: int, rough: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in pts.size() - 1:
		var seg: PackedVector2Array = _mid(pts[i], pts[i + 1], depth, rough)
		if i > 0:
			seg = seg.slice(1)
		out.append_array(seg)
	return out


func _mid(a: Vector2, b: Vector2, depth: int, rough: float) -> PackedVector2Array:
	if depth <= 0:
		return PackedVector2Array([a, b])
	var m: Vector2 = (a + b) * 0.5
	var n: Vector2 = (b - a).orthogonal().normalized()
	m += n * rng.randf_range(-1.0, 1.0) * (b - a).length() * rough
	var left: PackedVector2Array = _mid(a, m, depth - 1, rough)
	var right: PackedVector2Array = _mid(m, b, depth - 1, rough)
	left.append_array(right.slice(1))
	return left


func _rev(p: PackedVector2Array) -> PackedVector2Array:
	var o: PackedVector2Array = PackedVector2Array()
	for i: int in range(p.size() - 1, -1, -1):
		o.append(p[i])
	return o


func _arr(p: PackedVector2Array) -> Array:
	var o: Array = []
	for v: Vector2 in p:
		o.append([snappedf(v.x, 0.1), snappedf(v.y, 0.1)])
	return o


# ── 栅格化 ──────────────────────────────────────────────────────────────
## 扫描线填充：把多边形填进 id 数组（行内按交点对填）。
func _fill(poly: PackedVector2Array, ids: PackedByteArray, val: int) -> void:
	var n: int = poly.size()
	for y: int in H:
		var fy: float = y + 0.5
		var xs: Array = []
		for i: int in n:
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % n]
			if (a.y <= fy and b.y > fy) or (b.y <= fy and a.y > fy):
				xs.append(a.x + (fy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var k: int = 0
		while k + 1 < xs.size():
			var x0: int = clampi(int(ceil(xs[k] - 0.5)), 0, W)
			var x1: int = clampi(int(floor(xs[k + 1] - 0.5)), -1, W - 1)
			for x: int in range(x0, x1 + 1):
				ids[y * W + x] = val
			k += 2


## 两遍倒角距离变换：到「源」像素（mask 为 1）的近似距离（像素）。
func _dist(mask: PackedByteArray) -> PackedFloat32Array:
	var d: PackedFloat32Array = PackedFloat32Array()
	d.resize(W * H)
	var big: float = 1e9
	for i: int in W * H:
		d[i] = 0.0 if mask[i] == 1 else big
	var s2: float = 1.4142
	for y: int in H:
		for x: int in W:
			var i2: int = y * W + x
			var v: float = d[i2]
			if x > 0:
				v = minf(v, d[i2 - 1] + 1.0)
			if y > 0:
				v = minf(v, d[i2 - W] + 1.0)
				if x > 0:
					v = minf(v, d[i2 - W - 1] + s2)
				if x < W - 1:
					v = minf(v, d[i2 - W + 1] + s2)
			d[i2] = v
	for y2: int in range(H - 1, -1, -1):
		for x2: int in range(W - 1, -1, -1):
			var i3: int = y2 * W + x2
			var v2: float = d[i3]
			if x2 < W - 1:
				v2 = minf(v2, d[i3 + 1] + 1.0)
			if y2 < H - 1:
				v2 = minf(v2, d[i3 + W] + 1.0)
				if x2 < W - 1:
					v2 = minf(v2, d[i3 + W + 1] + s2)
				if x2 > 0:
					v2 = minf(v2, d[i3 + W - 1] + s2)
			d[i3] = v2
	return d


# ── 着色 ────────────────────────────────────────────────────────────────
func _render(regions: Dictionary, rivers: Array, coast: PackedVector2Array) -> Image:
	var rid_of: Dictionary = {"xiling": 1, "beiyuan": 2, "zhongzhou": 3, "haijia": 4}
	var ids: PackedByteArray = PackedByteArray()
	ids.resize(W * H)
	ids.fill(0)
	for rid: String in regions.keys():
		_fill(regions[rid], ids, int(rid_of[rid]))
	# 海岸距离（陆地到海、海到陆地）
	var land: PackedByteArray = PackedByteArray()
	land.resize(W * H)
	var sea: PackedByteArray = PackedByteArray()
	sea.resize(W * H)
	for i: int in W * H:
		land[i] = 1 if ids[i] != 0 else 0
		sea[i] = 1 - land[i]
	var d_to_sea: PackedFloat32Array = _dist(sea)
	var d_to_land: PackedFloat32Array = _dist(land)
	# 河流：沿折线画圆盘做水面，再求到水的距离（河岸湿地）
	var water: PackedByteArray = PackedByteArray()
	water.resize(W * H)
	water.fill(0)
	for rv: Dictionary in rivers:
		var pts: PackedVector2Array = rv["pts"]
		var w: float = float(rv["w"])
		for i: int in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var steps: int = int(a.distance_to(b) / 1.5) + 1
			for s: int in steps + 1:
				var p: Vector2 = a.lerp(b, float(s) / steps)
				var r: float = w * (0.55 + 0.45 * float(i) / pts.size())
				for dy: int in range(-int(r) - 1, int(r) + 2):
					for dx: int in range(-int(r) - 1, int(r) + 2):
						if dx * dx + dy * dy <= r * r:
							var xx: int = int(p.x) + dx
							var yy: int = int(p.y) + dy
							if xx >= 0 and xx < W and yy >= 0 and yy < H:
								water[yy * W + xx] = 1
	var d_water: PackedFloat32Array = _dist(water)
	# 地势：连续的场（不按地区跳变）——西边一条山带往东渐低，北原北缘有丘，海岬的岬角有丘陵
	var n1: FastNoiseLite = _noise(SEED, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.004, FastNoiseLite.FRACTAL_FBM, 5)
	var n2: FastNoiseLite = _noise(SEED + 7, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.010, FastNoiseLite.FRACTAL_RIDGED, 4)
	var n3: FastNoiseLite = _noise(SEED + 13, FastNoiseLite.TYPE_VALUE, 0.9, FastNoiseLite.FRACTAL_NONE, 1)
	var n4: FastNoiseLite = _noise(SEED + 21, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0022, FastNoiseLite.FRACTAL_FBM, 3)
	var cells: FastNoiseLite = _noise(SEED + 31, FastNoiseLite.TYPE_CELLULAR, 0.075, FastNoiseLite.FRACTAL_NONE, 1)
	cells.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var cells_big: FastNoiseLite = _noise(SEED + 37, FastNoiseLite.TYPE_CELLULAR, 0.038, FastNoiseLite.FRACTAL_NONE, 1)
	cells_big.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var forest_n: FastNoiseLite = _noise(SEED + 41, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, FastNoiseLite.FRACTAL_FBM, 3)
	var elev: PackedFloat32Array = PackedFloat32Array()
	elev.resize(W * H)
	var mnt: PackedFloat32Array = PackedFloat32Array()
	mnt.resize(W * H)
	for y: int in H:
		for x: int in W:
			var i4: int = y * W + x
			if ids[i4] == 0:
				elev[i4] = 0.0
				continue
			var warp: float = 110.0 * n4.get_noise_2d(x, y)
			var mount: float = _smooth(clampf((700.0 - x + warp) / 460.0, 0.0, 1.0))
			var north: float = _smooth(clampf((190.0 - y + warp * 0.6) / 190.0, 0.0, 1.0)) * clampf((x - 520.0) / 200.0, 0.0, 1.0)
			var cape: float = clampf(1.0 - Vector2(x, y).distance_to(Vector2(1490, 492)) / 150.0, 0.0, 1.0)
			var rid: float = n2.get_noise_2d(x, y) * 0.5 + 0.5
			var e: float = 0.07 + 0.07 * n1.get_noise_2d(x, y)
			e += mount * (0.22 + 0.50 * pow(rid, 1.4))
			e += north * 0.26 * rid
			e += cape * 0.22 * (0.4 + rid)
			e *= clampf(d_to_sea[i4] / 70.0, 0.3, 1.0)
			e -= 0.09 * clampf(1.0 - d_water[i4] / 26.0, 0.0, 1.0)
			elev[i4] = maxf(0.0, e)
			mnt[i4] = mount
	# 上色：干湿 × 地势 + 田块 + 林地 + 山影 + 纸纹
	var img: Image = Image.create(W, H, false, Image.FORMAT_RGB8)
	var light: Vector3 = Vector3(-0.55, -0.65, 0.52).normalized()
	var c_deep: Color = Color("10243a")
	var c_sea: Color = Color("1b4658")
	var c_shallow: Color = Color("2d7078")
	var c_foam: Color = Color("a8d4cb")
	var c_river: Color = Color("2f8698")
	var c_wet: Color = Color("5d8a48")
	var c_green: Color = Color("6c8f4f")
	var c_dry: Color = Color("a39159")
	var c_forest: Color = Color("3f6340")
	var c_hill: Color = Color("7a7250")
	var c_rock: Color = Color("7c7568")
	var c_peak: Color = Color("bdb7aa")
	var c_sand: Color = Color("cfbd8c")
	for y2: int in H:
		for x2: int in W:
			var i5: int = y2 * W + x2
			var grain: float = 0.97 + 0.03 * n3.get_noise_2d(x2, y2)
			if ids[i5] == 0:
				var t: float = clampf(d_to_land[i5] / 170.0, 0.0, 1.0)
				var col0: Color = c_shallow.lerp(c_sea, clampf(t * 2.2, 0.0, 1.0)).lerp(c_deep, clampf(t * 1.5 - 0.45, 0.0, 1.0))
				if d_to_land[i5] < 4.0:
					col0 = col0.lerp(c_foam, 0.6 * (1.0 - d_to_land[i5] / 4.0))
				var wave: float = sin(y2 * 0.20 + x2 * 0.015 + n1.get_noise_2d(x2 * 2, y2 * 2) * 7.0)
				if wave > 0.94 and d_to_land[i5] > 10.0:
					col0 = col0.lerp(c_foam, 0.08 + 0.06 * clampf(1.0 - t, 0.0, 1.0))
				img.set_pixel(x2, y2, col0 * grain)
				continue
			if water[i5] == 1:
				img.set_pixel(x2, y2, c_river.lerp(c_sea, 0.18) * grain)
				continue
			var e2: float = elev[i5]
			# 干湿：北边干，近水、近海湿
			var dry: float = clampf(0.15 + 0.75 * _smooth(clampf((460.0 - y2) / 460.0, 0.0, 1.0)) + 0.18 * n4.get_noise_2d(x2 + 900, y2)
					- 0.55 * clampf(1.0 - d_water[i5] / 60.0, 0.0, 1.0) - 0.35 * clampf(1.0 - d_to_sea[i5] / 80.0, 0.0, 1.0), 0.0, 1.0)
			var col: Color = c_green.lerp(c_dry, dry).lerp(c_wet, clampf(1.0 - d_water[i5] / 40.0, 0.0, 1.0) * 0.5)
			# 田块：平地上一块块的田（湿处小块水田，干处大块旱地）
			if e2 < 0.2 and mnt[i5] < 0.35:
				var cv: float = cells.get_noise_2d(x2, y2) if dry < 0.5 else cells_big.get_noise_2d(x2, y2)
				col = col * (0.965 + 0.045 * cv)
			# 林地
			var fv: float = forest_n.get_noise_2d(x2, y2)
			if fv > 0.18 and e2 > 0.12 and e2 < 0.55:
				col = col.lerp(c_forest, clampf((fv - 0.18) * 3.0, 0.0, 0.75))
			# 丘陵、山地、雪峰
			if e2 > 0.26:
				col = col.lerp(c_hill, clampf((e2 - 0.26) / 0.14, 0.0, 1.0))
			if e2 > 0.40:
				col = col.lerp(c_rock, clampf((e2 - 0.40) / 0.20, 0.0, 1.0))
			if e2 > 0.72:
				col = col.lerp(c_peak, clampf((e2 - 0.72) / 0.14, 0.0, 0.8))
			if d_to_sea[i5] < 6.0:
				col = col.lerp(c_sand, 0.65 * (1.0 - d_to_sea[i5] / 6.0))
			var ex: float = elev[i5 + 1] - elev[i5 - 1] if x2 > 0 and x2 < W - 1 else 0.0
			var ey: float = elev[i5 + W] - elev[i5 - W] if y2 > 0 and y2 < H - 1 else 0.0
			var nrm: Vector3 = Vector3(-ex * 40.0, -ey * 40.0, 1.0).normalized()
			var sh: float = clampf(nrm.dot(light), 0.0, 1.0)
			col = col * (0.66 + 0.48 * sh)
			img.set_pixel(x2, y2, col * grain)
	return img


func _noise(sd: int, kind: FastNoiseLite.NoiseType, freq: float, frac: FastNoiseLite.FractalType, oct: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed = sd
	n.noise_type = kind
	n.frequency = freq
	n.fractal_type = frac
	n.fractal_octaves = oct
	return n


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
