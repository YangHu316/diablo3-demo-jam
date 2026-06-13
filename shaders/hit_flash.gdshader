// hit_flash.gdshader
// 受击闪白 + 冰冻染色 共用 shader。
// flash_intensity: 命中瞬间=1.0,0.06s tween 回 0
// freeze_intensity: 冻结期间=1.0,解冻=0(直接设,无 tween)
// 两者叠加:先把 ALBEDO lerp 到冰蓝,再 lerp 到白色,这样命中冻结目标时白色优先。

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo_color : source_color = vec4(0.827, 0.184, 0.184, 1.0);
uniform float flash_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float freeze_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.8;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float flash_emission_strength : hint_range(0.0, 4.0) = 0.8;

const vec3 FREEZE_TINT = vec3(0.45, 0.7, 1.0);

void fragment() {
	vec3 base = albedo_color.rgb;
	// 先把基色 lerp 到冰蓝
	vec3 frozen = mix(base, FREEZE_TINT, freeze_intensity);
	// 再 lerp 到白色(命中闪白)
	vec3 final_color = mix(frozen, vec3(1.0), flash_intensity);
	ALBEDO = final_color;
	// emission:闪白主导 + 冻结小辉光,暗处也能看到
	EMISSION = vec3(1.0) * flash_intensity * flash_emission_strength + FREEZE_TINT * freeze_intensity * 0.2;
	// 冻结时调低 roughness、调高 metallic,让目标看起来"覆冰"
	ROUGHNESS = mix(roughness, 0.15, freeze_intensity);
	METALLIC = mix(metallic, 0.4, freeze_intensity);
	ALPHA = albedo_color.a;
}
