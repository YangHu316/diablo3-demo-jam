extends Resource
class_name TierTable

# Weapon/armor power tier table (武器/防具 Tier 台阶).
# Source: 04-Demo装备与掉落 §3.3, 05-Demo成长与数值 §2.3.
# T1: Lv1~3, T2: Lv4~6, T3: Lv7~8.

# tier -> { level_min, level_max, weapon_dps_min/max, armor_min/max }
@export var tiers: Array[Dictionary] = [
	{ "tier": 1, "level_min": 1, "level_max": 3, "weapon_dps_min": 3.0,  "weapon_dps_max": 8.0,  "armor_min": 6,  "armor_max": 14 },
	{ "tier": 2, "level_min": 4, "level_max": 6, "weapon_dps_min": 9.0,  "weapon_dps_max": 18.0, "armor_min": 16, "armor_max": 32 },
	{ "tier": 3, "level_min": 7, "level_max": 8, "weapon_dps_min": 20.0, "weapon_dps_max": 32.0, "armor_min": 36, "armor_max": 70 }
]

func tier_for_level(level: int) -> int:
	for t in tiers:
		if level >= int(t["level_min"]) and level <= int(t["level_max"]):
			return int(t["tier"])
	# 超出范围时夹到最近端.
	if level < 1:
		return 1
	return 3

func tier_data(tier: int) -> Dictionary:
	for t in tiers:
		if int(t["tier"]) == tier:
			return t
	return {}
