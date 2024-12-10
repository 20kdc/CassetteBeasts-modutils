# Scene Inheritance Resolution Engine #

# This is free and unencumbered software released into the public domain.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.
#
# In jurisdictions that recognize copyright laws, the author or authors
# of this software dedicate any and all copyright interest in the
# software to the public domain. We make this dedication for the benefit
# of the public at large and to the detriment of our heirs and
# successors. We intend this dedication to be an overt act of
# relinquishment in perpetuity of all present and future rights to this
# software under copyright law.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# For more information, please refer to <https://unlicense.org/>

extends Reference

signal dynamic_patch(packed_scene)

var debug := true
var _inheritance_patches := {}
var _held := []

func _init():
	if debug:
		print("Quack! *duck noises*")

	assert(not SceneManager.preloader.singleton_setup_complete)
	yield(SceneManager.preloader, "singleton_setup_completed")

	if debug:
		print("Quack! Singleton setup complete!")

	for key in _inheritance_patches.keys():
		_install(key)

# Ensures dynamic_patch will be called for the given scene resource path before the title screen loads.
func add_dynamic_patch(target: String):
	if debug:
		print("Quack! Dynamic patch added to " + target)
	var table = _inheritance_patches.get(target, null)
	if table == null:
		_inheritance_patches[target] = PoolStringArray([])

func add_inheritance_patch(target: String, source: String):
	if debug:
		print("Quack! Inheritance patch added to " + target + " from " + source)
	var table = _inheritance_patches.get(target, null)
	if table == null:
		_inheritance_patches[target] = PoolStringArray([source])
	else:
		table.push_back(source)
		_inheritance_patches[target] = table

# Performs the patch-and-force-cache immediately.
# This leaks memory, sadly, because it's the only way to get it to stick.
func _install(path: String):
	if debug:
		print("Quack! Installing: " + path)
	var scene = load(path)
	if scene == null:
		return
	if not (scene is PackedScene):
		push_warning("You can only perform scene_patch.install on PackedScene resources! @ " + path)
		return
	if scene.has_meta("__scene_patch_inheritance_engine"):
		# already patched
		return
	var ip = _inheritance_patches.get(path, null)
	if ip != null:
		var scenes := [scene]
		for v in ip:
			var loaded = load(v)
			scenes.push_back(loaded)
			_held.push_back(loaded)
		scene = resolver(scenes, debug)
	scene.set_meta("__scene_patch_inheritance_engine", true)
	scene.take_over_path(path)
	emit_signal("dynamic_patch", scene)
	_held.push_back(scene)
	return scene

# Given an array of related PackedScenes, this attempts to assemble a coherent lineage.
# Notably, all scenes in the array consent to having their base scene changed.
# The returned PackedScene may or may not be equal to base.
# If the returned PackedScene is equal to base, the scene is unchanged.
# If not, then an inheritance change has been constructed.
# This chain is reliant on patched resources from the scenes array.
static func resolver(scenes: Array, debug: bool) -> PackedScene:
	while len(scenes) > 1:
		# Find longest chain.
		var chain := []
		var chain_holder: PackedScene = null
		if debug:
			print(" -- chains --")
		var sidx := 0
		for v in scenes:
			var chain_test = get_chain(v)
			if debug:
				var total = str(sidx) + ": "
				for sv in chain_test:
					total += " -> "
					if sv.resource_path != "":
						total += sv.resource_path
					else:
						total += str(sv)
				print(total)
			if len(chain_test) > len(chain):
				chain = chain_test
				chain_holder = v
			sidx += 1
		if debug:
			print("terminal: " + chain_holder.resource_path + " [" + str(len(chain)) + "]")
		# Filter redundant scenes & rebase others.
		var new_scenes := [chain_holder]
		sidx = 0
		for v in scenes:
			var nsc := get_chain(v)
			var common := chain_common(chain, nsc)
			if debug:
				print(str(sidx) + ": " + str(common) + " common [" + str(len(nsc)) + "]")
			sidx += 1
			if common == len(nsc):
				# Subsumed.
				continue
			elif common == len(chain):
				# Extension (can happen when the rebase already happened)
				new_scenes.push_back(v)
			else:
				# Rebase.
				if debug:
					print("Change base: " + chain_holder.resource_path + " -> " + nsc[common].resource_path)
				change_base(nsc[common], chain_holder)
				new_scenes.push_back(v)
		scenes = new_scenes
	return scenes[0]

# At which index in these chains do they diverge?
static func chain_common(a: Array, b: Array) -> int:
	var i := 0
	while i < len(a) and i < len(b):
		if a[i] != b[i]:
			return i
		i += 1
	return i

# Gets the inheritance chain (up to a depth of 256)
static func get_chain(base: PackedScene) -> Array:
	var chain := []
	var i := 0
	while i < 256:
		chain.push_front(base)
		base = get_base(base)
		if base == null:
			break
		i += 1
	return chain

# Gets the base scene of the target (or null if none)
static func get_base(target: PackedScene) -> PackedScene:
	var bundled := target._bundled
	var base_scene_idx: int = bundled.get("base_scene", -1)
	if base_scene_idx == -1:
		return null
	return bundled["variants"][base_scene_idx]

# Changes the base scene of the target.
static func change_base(target: PackedScene, onto: PackedScene):
	var bundled := target._bundled
	var variants: Array = bundled["variants"]
	var variant := len(variants)
	variants.push_back(onto)
	bundled["base_scene"] = variant
	target._bundled = bundled
