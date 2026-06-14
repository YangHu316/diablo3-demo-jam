shader_type canvas_item;

// 暗黑破坏神3 关卡后期调色(角色D / 美术)
// 全屏读取 3D 画面 → 冷暗-暖亮分离调色 + 去饱和 + 暗角,营造 D3 地牢的阴郁电影感。
// 挂在 D3Grade(CanvasLayer, layer=1) 下的全屏 ColorRect 上;HUD 在更高层,不受影响。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float contrast : hint_range(0.5, 2.0) = 1.10;
uniform float brightness : hint_range(0.5, 1.5) = 0.96;
uniform float saturation : hint_range(0.0, 2.0) = 0.86;
uniform vec3 shadow_tint : source_color = vec3(0.40, 0.48, 0.70);    // 冷蓝阴影
uniform vec3 highlight_tint : source_color = vec3(1.00, 0.84, 0.58); // 暖琥珀高光
uniform float tint_amount : hint_range(0.0, 1.0) = 0.30;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
uniform float vignette_softness : hint_range(0.05, 1.0) = 0.55;

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	col = (col - 0.5) * contrast + 0.5;           // 对比度(围绕中灰)
	col *= brightness;                             // 整体压暗
	col = clamp(col, 0.0, 1.0);
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(lum), col, saturation);         // 去饱和
	vec3 grade = mix(shadow_tint, highlight_tint, smoothstep(0.0, 0.9, lum));
	col = mix(col, col * grade, tint_amount);      // 冷暗/暖亮 分离调色
	float d = distance(SCREEN_UV, vec2(0.5)) * 1.41421;
	float vig = 1.0 - smoothstep(1.0 - vignette_softness, 1.05, d) * vignette_strength;
	col *= vig;                                    // 暗角
	COLOR = vec4(col, 1.0);
}
