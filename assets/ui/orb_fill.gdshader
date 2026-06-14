shader_type canvas_item;
// 球体液面填充 shader —— 用于 HP/MP 球.
// 纹理为正方形正圆球体(透明背景). 按 UV.y 与 fill_ratio 比较决定"液面以下/以上":
//   液面以下 = 显示球体原色(液体).
//   液面以上 = 压暗(empty_tint), 模拟空球凹槽.
//   液面线带 sin 波动, 表现液体晃动.
// fill_ratio 由 hud.gd 经 tween 驱动(0=空, 1=满).

uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float wave_amp   : hint_range(0.0, 0.1) = 0.012;   // 波动幅度(UV 比例)
uniform float wave_speed : hint_range(0.0, 10.0) = 2.2;    // 波动速度
uniform float wave_freq  : hint_range(0.0, 40.0) = 11.0;   // 波纹密度
uniform vec4  empty_tint  : source_color = vec4(0.12, 0.10, 0.10, 1.0); // 液面以上压暗色
uniform float empty_mix  : hint_range(0.0, 1.0) = 0.82;    // 液面以上向 empty_tint 混合强度
uniform float edge_soft  : hint_range(0.0, 0.05) = 0.006;  // 液面线柔化

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	// 双正弦叠加, 表面更自然.
	float wave = sin(UV.x * wave_freq + TIME * wave_speed) * wave_amp
	           + sin(UV.x * wave_freq * 0.47 + TIME * wave_speed * 1.6) * wave_amp * 0.5;
	// 液面线: fill_ratio=1 时 surface=0(液面在顶), =0 时 surface=1(液面在底).
	float surface = (1.0 - fill_ratio) + wave;
	// below=1 表示该像素在液面以下(液体), 0 表示以上(空). 边缘柔化.
	float below = smoothstep(surface - edge_soft, surface + edge_soft, UV.y);
	// 液面以上: 向 empty_tint 混合(压暗), 保留球体 alpha 形状以贴合凹槽.
	vec3 rgb = mix(tex.rgb, empty_tint.rgb, (1.0 - below) * empty_mix);
	COLOR = vec4(rgb, tex.a);
}
