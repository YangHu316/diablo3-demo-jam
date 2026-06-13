extends Resource
class_name EquipSlots

# Equipment slot catalog (装备槽位). 13 slots total.
# Source: 04-Demo装备与掉落 §3.2.
# Pure constants/enum holder — referenced by Inventory & item generation.

enum Slot {
	HEAD,      # 头
	SHOULDER,  # 肩
	CHEST,     # 胸
	WRIST,     # 腕
	GLOVES,    # 手套
	WAIST,     # 腰
	LEGS,      # 腿
	BOOTS,     # 靴
	AMULET,    # 项链
	RING_1,    # 戒指1
	RING_2,    # 戒指2
	BOW,       # 主手弓 (职业专属)
	QUIVER     # 副手箭袋 (职业专属)
}

const SLOT_COUNT: int = 13

const SLOT_NAMES: Dictionary = {
	Slot.HEAD: &"head",
	Slot.SHOULDER: &"shoulder",
	Slot.CHEST: &"chest",
	Slot.WRIST: &"wrist",
	Slot.GLOVES: &"gloves",
	Slot.WAIST: &"waist",
	Slot.LEGS: &"legs",
	Slot.BOOTS: &"boots",
	Slot.AMULET: &"amulet",
	Slot.RING_1: &"ring",
	Slot.RING_2: &"ring",
	Slot.BOW: &"bow",
	Slot.QUIVER: &"quiver"
}

const SLOT_DISPLAY: Dictionary = {
	Slot.HEAD: "头部",
	Slot.SHOULDER: "肩部",
	Slot.CHEST: "胸甲",
	Slot.WRIST: "护腕",
	Slot.GLOVES: "手套",
	Slot.WAIST: "腰带",
	Slot.LEGS: "腿甲",
	Slot.BOOTS: "靴子",
	Slot.AMULET: "项链",
	Slot.RING_1: "戒指1",
	Slot.RING_2: "戒指2",
	Slot.BOW: "弓",
	Slot.QUIVER: "箭袋"
}
