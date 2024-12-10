extends ContentInfo

func init_content():
	print("duckspace")
	DLC.mods_by_id.cat_modutils.scene_patch.add_inheritance_patch("res://world/maps/dungeon_final/Platform.tscn", "res://mods/duckspace/patch1.tscn")
	DLC.mods_by_id.cat_modutils.scene_patch.add_inheritance_patch("res://world/maps/dungeon_final/Platform.tscn", "res://mods/duckspace/patch2.tscn")
