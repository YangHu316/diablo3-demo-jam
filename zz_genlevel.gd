extends SceneTree

const TILE := 5.0
const SCALE := 1.5
const FLOOR := "res://assets/PolygonDungeon/Models/Environment/Floors/SM_Env_Tiles_01.fbx"
const WALL := "res://assets/PolygonDungeon/Models/Environment/Walls/SM_Env_Wall_01_DoubleSided.fbx"
const CHEST := "res://assets/PolygonDungeon/Models/Props/Containers/SM_Prop_Chest_01.fbx"
const TORCH := "res://assets/PolygonDungeon/Models/Props/Lighting/SM_Prop_Torch_Ornate_01.fbx"
const PILLAR := "res://assets/PolygonDungeon/Models/Environment/Pillars/SM_Env_Ceiling_Stone_Pillar_01.fbx"

const WALK := [
	[-92,-74,-16,2],[-78,-44,-6,2],[-44,-18,-2,30],[-40,-30,-70,4],[-50,-22,-86,-66],
	[-30,2,-52,-28],[-46,-30,26,40],[-78,-46,24,44],[-18,12,14,26],[12,32,8,28],
	[30,58,8,16],[50,58,16,40],[30,58,32,44],[30,38,16,36],[44,54,40,56],
	[50,84,52,82],[-40,-30,28,58],[-40,46,48,60],
]
const ROOM_NAME := [
	"西门入口","西廊","中央枢纽","长北廊","北门目标","上中室","西南廊","宝藏死胡同",
	"东廊","齿轮室","右环北","右环东","右环南","右环西","Boss入口廊","Boss厅","枢纽南廊","南长廊",
]
const TORCHES := [[-35,-58],[-35,-40],[-35,-22],[-35,-4],[-30,54],[-10,54],[10,54],[30,54]]

var _root: Node3D
var _floor_scn: PackedScene
var _wall_scn: PackedScene
var _cells := {}
# 每房间每方向的墙格,用于合并碰撞: room -> {"N":{gj:[gi..]}, "S":..., "W":{gi:[gj..]}, "E":...}
var _walls := {}

func _initialize():
	_floor_scn = load(FLOOR); _wall_scn = load(WALL)
	_root = Node3D.new(); _root.name = "L2_Assembled"

	# ── 灯光 / 雾 / 辉光 ──
	var we := WorldEnvironment.new(); we.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.03,0.03,0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.34,0.36,0.48); e.ambient_light_energy = 0.45
	e.fog_enabled = true; e.fog_light_color = Color(0.06,0.06,0.10); e.fog_density = 0.005
	e.fog_sky_affect = 0.0
	e.glow_enabled = true; e.glow_intensity = 0.9; e.glow_bloom = 0.25; e.glow_strength = 1.1
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = e; _own(we)
	var sun := DirectionalLight3D.new(); sun.name = "Moonlight"
	sun.rotation_degrees = Vector3(-55,-45,0); sun.light_color = Color(0.55,0.62,0.85)
	sun.light_energy = 0.35; sun.shadow_enabled = true; _own(sun)

	# ── 网格 + 房间归属 ──
	var minx=INF; var maxx=-INF; var minz=INF; var maxz=-INF
	for r in WALK:
		minx=minf(minx,r[0]*SCALE); maxx=maxf(maxx,r[1]*SCALE)
		minz=minf(minz,r[2]*SCALE); maxz=maxf(maxz,r[3]*SCALE)
	for gi in range(int(floor(minx/TILE)), int(ceil(maxx/TILE))+1):
		for gj in range(int(floor(minz/TILE)), int(ceil(maxz/TILE))+1):
			var room := _room_of(gi,gj)
			if room >= 0: _cells["%d_%d"%[gi,gj]] = room

	var rooms := {}
	for idx in WALK.size():
		var rn := Node3D.new(); rn.name = "Room_%02d_%s"%[idx,ROOM_NAME[idx]]; _own(rn); rooms[idx]=rn
		_walls[idx] = {"N":{},"S":{},"W":{},"E":{}}

	# ── 视觉地砖+墙(逐块) + 记录墙格供合并碰撞 ──
	for key in _cells:
		var p := (key as String).split("_"); var gi := int(p[0]); var gj := int(p[1])
		var ridx: int = _cells[key]; var room: Node3D = rooms[ridx]
		var cx := gi*TILE; var cz := gj*TILE
		_inst(_floor_scn, room, "Floor_%d_%d"%[gi,gj], Vector3(cx,0,cz), 0.0)
		if not _cells.has("%d_%d"%[gi,gj-1]): _inst(_wall_scn, room, "Wall_N_%d_%d"%[gi,gj], Vector3(cx,0,cz), 0.0); _rec(ridx,"N",gj,gi)
		if not _cells.has("%d_%d"%[gi,gj+1]): _inst(_wall_scn, room, "Wall_S_%d_%d"%[gi,gj], Vector3(cx,0,cz+TILE), 0.0); _rec(ridx,"S",gj,gi)
		if not _cells.has("%d_%d"%[gi-1,gj]): _inst(_wall_scn, room, "Wall_W_%d_%d"%[gi,gj], Vector3(cx,0,cz), 90.0); _rec(ridx,"W",gi,gj)
		if not _cells.has("%d_%d"%[gi+1,gj]): _inst(_wall_scn, room, "Wall_E_%d_%d"%[gi,gj], Vector3(cx+TILE,0,cz), 90.0); _rec(ridx,"E",gi,gj)

	# ── 每房间合并碰撞(地板1盒 + 墙合并盒)挂在房间下 ──
	for idx in WALK.size():
		_build_room_collision(idx, rooms[idx])

	# ── 道具 + 火把光 ──
	var props := Node3D.new(); props.name = "Props"; _own(props)
	_inst_model(CHEST, props, "Chest", _at(-62,34), 2.5)
	_inst_model(PILLAR, props, "BossPillar", _at(67,67), 1.5)
	for i in TORCHES.size():
		var t = TORCHES[i]
		_inst_model(TORCH, props, "Torch_%d"%i, _at(t[0],t[1]), 3.0)
		var l := OmniLight3D.new(); l.name="TorchLight_%d"%i
		l.position=_at_y(t[0],t[1],2.2); l.light_color=Color(1.0,0.6,0.25); l.light_energy=2.8; l.omni_range=12.0
		props.add_child(l); l.owner=_root

	var packed := PackedScene.new(); packed.pack(_root)
	print("SAVED err=", ResourceSaver.save(packed,"res://scenes/levels/level_02_assembled.tscn"), " 节点=", _count(_root))
	quit()

func _rec(room:int, dir:String, line:int, idx:int):
	var d = _walls[room][dir]
	if not d.has(line): d[line]=[]
	d[line].append(idx)

# 合并连续墙格成长盒,给房间建 StaticBody3D 碰撞
func _build_room_collision(room_idx:int, room:Node3D):
	var sb := StaticBody3D.new(); sb.name="Collision"; sb.collision_layer=4; sb.collision_mask=0
	room.add_child(sb); sb.owner=_root
	# 地板盒(覆盖该 WALK 矩形)
	var r = WALK[room_idx]
	var fcx=(r[0]+r[1])*0.5*SCALE; var fcz=(r[2]+r[3])*0.5*SCALE
	_addbox(sb, Vector3(fcx,-0.1,fcz), Vector3((r[1]-r[0])*SCALE,0.4,(r[3]-r[2])*SCALE))
	# 墙盒(N/S 沿 X 合并;W/E 沿 Z 合并)
	for dir in ["N","S"]:
		for line in _walls[room_idx][dir]:
			for run in _runs(_walls[room_idx][dir][line]):
				var z = (line if dir=="N" else line+1)*TILE
				var x0=run[0]*TILE; var x1=(run[1]+1)*TILE
				_addbox(sb, Vector3((x0+x1)*0.5,2.0,z), Vector3(x1-x0,4.0,0.5))
	for dir in ["W","E"]:
		for line in _walls[room_idx][dir]:
			for run in _runs(_walls[room_idx][dir][line]):
				var x = (line if dir=="W" else line+1)*TILE
				var z0=run[0]*TILE; var z1=(run[1]+1)*TILE
				_addbox(sb, Vector3(x,2.0,(z0+z1)*0.5), Vector3(0.5,4.0,z1-z0))

func _runs(arr:Array)->Array:
	arr.sort()
	var out:=[]; var s=arr[0]; var prev=arr[0]
	for k in range(1,arr.size()):
		if arr[k]==prev+1: prev=arr[k]
		else: out.append([s,prev]); s=arr[k]; prev=arr[k]
	out.append([s,prev]); return out

func _addbox(sb:StaticBody3D, center:Vector3, size:Vector3):
	var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size=size; cs.shape=sh
	cs.position=center; sb.add_child(cs); cs.owner=_root

func _room_of(gi:int,gj:int)->int:
	var px=(gi+0.5)*TILE/SCALE; var pz=(gj+0.5)*TILE/SCALE
	for idx in WALK.size():
		var r=WALK[idx]
		if px>r[0] and px<r[1] and pz>r[2] and pz<r[3]: return idx
	return -1
func _at(x:float,z:float)->Vector3: return Vector3(x*SCALE,0,z*SCALE)
func _at_y(x:float,z:float,y:float)->Vector3: return Vector3(x*SCALE,y,z*SCALE)
func _inst(scn:PackedScene,parent:Node,nm:String,pos:Vector3,ry:float):
	var n:Node3D=scn.instantiate(); n.name=nm; n.position=pos; n.rotation_degrees=Vector3(0,ry,0); parent.add_child(n); n.owner=_root
func _inst_model(path:String,parent:Node,nm:String,pos:Vector3,scl:float):
	if not ResourceLoader.exists(path): return
	var n:Node3D=(load(path) as PackedScene).instantiate(); n.name=nm; n.position=pos; n.scale=Vector3(scl,scl,scl); parent.add_child(n); n.owner=_root
func _own(n:Node): _root.add_child(n); n.owner=(null if n==_root else _root)
func _count(n:Node)->int:
	var c:=1
	for ch in n.get_children(): c+=_count(ch)
	return c
