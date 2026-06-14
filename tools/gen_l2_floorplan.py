# -*- coding: utf-8 -*-
"""
生成 L2「痛苦回廊」白盒平面图(俯视),标注:可走房间 / 碰撞立柱(阻挡物) / 无碰撞结构件 / 地标 / 遭遇点。
数据与 scripts/levels/level_02_depths.gd 的 WALK / OBSTACLES / STRUCTURES / LANDMARKS / ENCOUNTERS 同步(改 .gd 后重跑本脚本)。
输出:
  关卡/L2-阻挡物与结构-平面图.svg   (给美术直观查看)
  关卡/L2-阻挡物与结构-清单.md      (每个阻挡物/结构的精确坐标+尺寸表)
坐标=WALK 单位;世界坐标=WALK×SCALE(1.5)。北=−Z=上。
"""
import math, os

SCALE = 1.5

WALK = [
    (-92,-74,-16,2,"W1 西门入口"), (-78,-44,-6,2,"W2 西廊"), (-44,-18,-2,30,"H 中央枢纽"),
    (-40,-30,-70,4,"N1 长北廊"), (-50,-22,-86,-66,"NP 北门"), (-30,2,-52,-28,"UC 上中室"),
    (-46,-30,26,40,"T1 西南廊"), (-78,-46,24,44,"TR 死胡同/祭坛室"), (-18,12,14,26,"E1 东廊"),
    (12,32,8,28,"GR 齿轮室"), (30,58,8,16,"RL_N 右环北"), (50,58,16,40,"RL_E 右环东"),
    (30,58,32,44,"RL_S 右环南"), (30,38,16,36,"RL_W 右环西"), (44,54,40,56,"BC Boss入口廊"),
    (50,84,52,82,"BOSS Boss厅"), (-40,-30,28,58,"S1 枢纽南廊"), (-40,46,48,60,"S2 南长廊"),
]
# 碰撞立柱 [x,z,radius(世界),label]
OBSTACLES = [
    (-38,8,1.4,"O1 枢纽·西北"), (-24,20,1.4,"O2 枢纽·东南"),
    (-8,17,1.2,"O3 东廊chicane"), (2,23,1.2,"O4 东廊chicane"),
    (16,22,1.3,"O5 齿轮室"), (28,14,1.3,"O6 齿轮室"),
    (38,38,1.3,"O7 右环·南"), (50,38,1.3,"O8 右环·南"),
    (62,62,1.5,"O9 Boss厅·西南"), (72,62,1.5,"O10 Boss厅·东南"),
    (62,72,1.5,"O11 Boss厅·西北"), (72,72,1.5,"O12 Boss厅·东北"),
]
PILLAR_H = 3.5  # 立柱高(世界)
# 无碰撞结构件 [x,z,kind,rot,label]
STRUCTURES = [
    (-61,-2,"colonnade",0,"西廊列柱"), (-31,0,"arch",0,"枢纽北口拱门"), (-62,34,"altar",0,"死胡同祭坛"),
    (-15,20,"arch",90,"东廊拱门"), (22,12,"broken_wall",0,"齿轮室断墙"), (44,38,"colonnade",0,"右环南列柱"),
    (49,46,"arch",0,"Boss门廊"), (58,67,"colonnade",90,"Boss厅西列柱"), (76,67,"colonnade",90,"Boss厅东列柱"),
    (-35,-28,"brazier",0,"北廊火盆"), (-36,50,"brazier",0,"南长廊火盆"),
]
LANDMARKS = [(-83,-7,"entrance","西门入口拱门"), (67,67,"boss_pillar","Boss中心柱"), (-31,14,"waypoint","枢纽地标")]
ENC = [(-60,-2),(-31,14),(-15,18),(-3,20),(22,18),(44,38),(-35,-40),(-36,-78),(10,54),(49,48),(67,67),
       (-34,18),(-26,10),(-3,22),(44,34),(67,60)]  # 末 5 = 混编追加(疯犬/弓手/肿胀)

# ---- 映射 ----
XMIN,XMAX,ZMIN,ZMAX = -92,84,-86,82
S = 2.7
PADL,PADT = 46,52
MAPW = (XMAX-XMIN)*S
MAPH = (ZMAX-ZMIN)*S
PANELX = PADL+MAPW+24
W = PANELX+300
H = max(PADT+MAPH+30, 760)
def sx(x): return PADL+(x-XMIN)*S
def sy(z): return PADT+(z-ZMIN)*S
def esc(s): return s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")

C = dict(bg="#15151c", room="#262630", roomstroke="#3c3c4a", txt="#d6d6e0", dim="#8a8a9a",
         obst="#e35038", obstr="#ff8a6a", arch="#6aa6d8", colo="#56c0b0", braz="#f0a830",
         altar="#bf6ae0", wall="#b08858", ent="#46c878", boss="#d03838", wp="#8888a8", enc="#5a6a55")

e=[]
e.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W:.0f} {H:.0f}" font-family="Segoe UI,Arial,sans-serif">')
e.append(f'<rect x="0" y="0" width="{W:.0f}" height="{H:.0f}" fill="{C["bg"]}"/>')
e.append(f'<text x="{PADL}" y="28" fill="{C["txt"]}" font-size="20" font-weight="700">L2「痛苦回廊」· 阻挡物与结构 平面图(白盒·俯视)</text>')
e.append(f'<text x="{PADL}" y="44" fill="{C["dim"]}" font-size="12">坐标=WALK 单位 · 世界=×{SCALE} · 北(−Z)在上 · 立柱=碰撞阻挡物,结构件=无碰撞装饰</text>')

# 房间
for x0,x1,z0,z1,lab in WALK:
    e.append(f'<rect x="{sx(x0):.1f}" y="{sy(z0):.1f}" width="{(x1-x0)*S:.1f}" height="{(z1-z0)*S:.1f}" fill="{C["room"]}" stroke="{C["roomstroke"]}" stroke-width="1.2"/>')
    cx,cz=(x0+x1)/2,(z0+z1)/2
    e.append(f'<text x="{sx(cx):.1f}" y="{sy(cz):.1f}" fill="{C["dim"]}" font-size="9.5" text-anchor="middle" dominant-baseline="middle">{esc(lab)}</text>')

# 遭遇点(淡)
for x,z in ENC:
    e.append(f'<circle cx="{sx(x):.1f}" cy="{sy(z):.1f}" r="3.2" fill="none" stroke="{C["enc"]}" stroke-width="1.4"/>')

# 结构件(无碰撞)
def rotpts(x,z,half,rot):
    r=math.radians(rot); dx,dz=math.cos(r),math.sin(r)
    return (x-dx*half,z-dz*half),(x+dx*half,z+dz*half)
for x,z,kind,rot,lab in STRUCTURES:
    if kind=="arch":
        (ax,az),(bx,bz)=rotpts(x,z,3,rot)
        e.append(f'<line x1="{sx(ax):.1f}" y1="{sy(az):.1f}" x2="{sx(bx):.1f}" y2="{sy(bz):.1f}" stroke="{C["arch"]}" stroke-width="2"/>')
        for px,pz in ((ax,az),(bx,bz)):
            e.append(f'<circle cx="{sx(px):.1f}" cy="{sy(pz):.1f}" r="2.6" fill="{C["arch"]}"/>')
    elif kind=="colonnade":
        (ax,az),(bx,bz)=rotpts(x,z,8,rot)
        e.append(f'<line x1="{sx(ax):.1f}" y1="{sy(az):.1f}" x2="{sx(bx):.1f}" y2="{sy(bz):.1f}" stroke="{C["colo"]}" stroke-width="2" stroke-dasharray="3 2"/>')
        for i in range(5):
            t=i/4.0; px,pz=ax+(bx-ax)*t,az+(bz-az)*t
            e.append(f'<circle cx="{sx(px):.1f}" cy="{sy(pz):.1f}" r="2.2" fill="{C["colo"]}"/>')
    elif kind=="brazier":
        e.append(f'<circle cx="{sx(x):.1f}" cy="{sy(z):.1f}" r="3.4" fill="{C["braz"]}"/>')
        e.append(f'<circle cx="{sx(x):.1f}" cy="{sy(z):.1f}" r="6" fill="none" stroke="{C["braz"]}" stroke-width="0.8" opacity="0.5"/>')
    elif kind=="altar":
        e.append(f'<rect x="{sx(x)-3.4:.1f}" y="{sy(z)-3.4:.1f}" width="6.8" height="6.8" fill="{C["altar"]}"/>')
    elif kind=="broken_wall":
        (ax,az),(bx,bz)=rotpts(x,z,3,rot)
        e.append(f'<line x1="{sx(ax):.1f}" y1="{sy(az):.1f}" x2="{sx(bx):.1f}" y2="{sy(bz):.1f}" stroke="{C["wall"]}" stroke-width="3" stroke-dasharray="2 2"/>')

# 地标
for x,z,kind,lab in LANDMARKS:
    if kind=="entrance":
        e.append(f'<path d="M {sx(x)-6:.1f} {sy(z)+5:.1f} L {sx(x):.1f} {sy(z)-6:.1f} L {sx(x)+6:.1f} {sy(z)+5:.1f}" fill="none" stroke="{C["ent"]}" stroke-width="2.2"/>')
        e.append(f'<text x="{sx(x):.1f}" y="{sy(z)+16:.1f}" fill="{C["ent"]}" font-size="9" text-anchor="middle">入口</text>')
    elif kind=="boss_pillar":
        e.append(f'<circle cx="{sx(x):.1f}" cy="{sy(z):.1f}" r="5" fill="{C["boss"]}"/>')
    elif kind=="waypoint":
        e.append(f'<circle cx="{sx(x):.1f}" cy="{sy(z):.1f}" r="4" fill="none" stroke="{C["wp"]}" stroke-width="1.6"/>')

# 碰撞立柱(阻挡物)—— 真实相对半径(r/SCALE WALK),最小可见 4px;红实心 + id
for x,z,r,lab in OBSTACLES:
    rpx=max(r/SCALE*S,4.0)
    oid=lab.split()[0]
    e.append(f'<circle cx="{sx(x):.1f}" cy="{sy(z):.1f}" r="{rpx:.1f}" fill="{C["obst"]}" stroke="{C["obstr"]}" stroke-width="1"/>')
    e.append(f'<text x="{sx(x):.1f}" y="{sy(z)-rpx-2:.1f}" fill="{C["obstr"]}" font-size="8.5" text-anchor="middle">{oid}</text>')

# 图例
lx=PANELX; ly=66
e.append(f'<text x="{lx}" y="{ly}" fill="{C["txt"]}" font-size="14" font-weight="700">图例</text>'); ly+=20
leg=[("碰撞立柱(阻挡物)",C["obst"],"circle"),("拱门 arch",C["arch"],"line"),("列柱廊 colonnade",C["colo"],"dots"),
     ("火盆 brazier",C["braz"],"circle"),("祭坛 altar",C["altar"],"rect"),("断墙 broken_wall",C["wall"],"line"),
     ("入口 entrance",C["ent"],"tri"),("Boss 中心柱",C["boss"],"circle"),("枢纽地标 waypoint",C["wp"],"ring"),
     ("遭遇刷怪点",C["enc"],"ring")]
for name,col,shp in leg:
    if shp in ("circle","tri"): e.append(f'<circle cx="{lx+7}" cy="{ly-3}" r="4.5" fill="{col}"/>')
    elif shp=="ring": e.append(f'<circle cx="{lx+7}" cy="{ly-3}" r="4.5" fill="none" stroke="{col}" stroke-width="1.6"/>')
    elif shp=="rect": e.append(f'<rect x="{lx+3}" y="{ly-7}" width="8" height="8" fill="{col}"/>')
    elif shp=="line": e.append(f'<line x1="{lx+2}" y1="{ly-3}" x2="{lx+12}" y2="{ly-3}" stroke="{col}" stroke-width="2.4"/>')
    elif shp=="dots":
        for k in range(3): e.append(f'<circle cx="{lx+3+k*4}" cy="{ly-3}" r="1.8" fill="{col}"/>')
    e.append(f'<text x="{lx+20}" y="{ly}" fill="{C["txt"]}" font-size="11">{esc(name)}</text>'); ly+=17

# 阻挡物精确表(SVG 内嵌)
ly+=10
e.append(f'<text x="{lx}" y="{ly}" fill="{C["txt"]}" font-size="14" font-weight="700">碰撞立柱(阻挡物)精确表</text>'); ly+=16
e.append(f'<text x="{lx}" y="{ly}" fill="{C["dim"]}" font-size="9.5">id  WALK(x,z)  世界(x,z)  半径/直径(世界)·高{PILLAR_H}</text>'); ly+=14
for x,z,r,lab in OBSTACLES:
    oid=lab.split()[0]; area=lab.split(None,1)[1] if len(lab.split(None,1))>1 else ""
    wx,wz=x*SCALE,z*SCALE
    e.append(f'<text x="{lx}" y="{ly}" fill="{C["txt"]}" font-size="9.5">{oid:>3}  ({x},{z})  ({wx:.0f},{wz:.0f})  r={r} / ⌀{r*2:.1f}  {esc(area)}</text>'); ly+=13.2

e.append('</svg>')
svg="\n".join(e)

OUT_SVG = os.path.join("关卡","L2-阻挡物与结构-平面图.svg")
OUT_MD  = os.path.join("关卡","L2-阻挡物与结构-清单.md")
os.makedirs("关卡", exist_ok=True)
with open(OUT_SVG,"w",encoding="utf-8") as f: f.write(svg)

# ---- markdown 清单 ----
md=[]
md.append("# L2「痛苦回廊」· 阻挡物与结构 清单(白盒)\n")
md.append("> 关卡C / 自动生成(`tools/gen_l2_floorplan.py`,与 `scripts/levels/level_02_depths.gd` 同步)。平面图见 [`L2-阻挡物与结构-平面图.svg`](L2-阻挡物与结构-平面图.svg)。")
md.append("> 坐标 = **WALK 单位**;世界坐标 = WALK × **SCALE(1.5)**;北(−Z)在上。给美术替模/布景用。\n")
md.append("## 一、碰撞立柱(阻挡物)—— 有物理碰撞,破开大空间 + 弓系风筝掩体\n")
md.append("| id | 区域 | WALK(x,z) | 世界(x,z) | 半径(世界) | 直径 | 高 |")
md.append("|---|---|---|---|---|---|---|")
for x,z,r,lab in OBSTACLES:
    oid=lab.split()[0]; area=lab.split(None,1)[1]
    md.append(f"| {oid} | {area} | ({x}, {z}) | ({x*SCALE:.0f}, {z*SCALE:.0f}) | {r} | {r*2:.1f} | {PILLAR_H} |")
md.append(f"\n圆柱立柱(`CylinderShape3D` r=半径·h={PILLAR_H});`collision_layer=4`。**白盒未对 navmesh 抠洞**(敌人物理滑动绕行)。\n")
md.append("## 二、无碰撞结构件(装饰·不挡路·零导航影响)\n")
md.append("| 区域/名称 | 类型 | WALK(x,z) | 朝向° | 说明 |")
md.append("|---|---|---|---|---|")
kindcn={"arch":"拱门","colonnade":"列柱廊","brazier":"火盆","altar":"祭坛","broken_wall":"断墙"}
for x,z,kind,rot,lab in STRUCTURES:
    md.append(f"| {lab} | {kindcn[kind]} | ({x}, {z}) | {rot} | {kind} |")
md.append("\n## 三、地标\n")
md.append("| 名称 | 类型 | WALK(x,z) |")
md.append("|---|---|---|")
for x,z,kind,lab in LANDMARKS:
    md.append(f"| {lab} | {kind} | ({x}, {z}) |")
md.append("\n> 改 `level_02_depths.gd` 的 OBSTACLES/STRUCTURES/LANDMARKS 后,重跑 `python tools/gen_l2_floorplan.py` 刷新本图与清单。")
with open(OUT_MD,"w",encoding="utf-8") as f: f.write("\n".join(md))

print("OK ->", OUT_SVG)
print("OK ->", OUT_MD)
print("obstacles:", len(OBSTACLES), " structures:", len(STRUCTURES), " rooms:", len(WALK))
