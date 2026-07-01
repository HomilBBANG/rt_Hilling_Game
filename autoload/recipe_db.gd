extends Node
## 레시피 정적 데이터 레지스트리. 새 레시피는 RECIPE_PATHS 에 추가하면 된다.
## 해금 판정을 한 곳에서 관리(밤 세션 / 선호 음식 선정이 공유).

const RECIPE_PATHS := [
	"res://resources/recipes/canned_stew.tres",
	"res://resources/recipes/herb_bite.tres",
	"res://resources/recipes/fries.tres",
]

var recipes: Array = []


func _ready() -> void:
	for p in RECIPE_PATHS:
		var r := load(p) as RecipeData
		if r:
			recipes.append(r)


## 기본 해금이거나, unlock_item_id 를 도감에서 획득했으면 해금.
func is_unlocked(recipe: RecipeData) -> bool:
	if recipe.unlocked_by_default:
		return true
	if recipe.unlock_item_id != "":
		return CodexManager.is_item_obtained(recipe.unlock_item_id)
	return false


func unlocked() -> Array:
	var out: Array = []
	for r in recipes:
		if is_unlocked(r):
			out.append(r)
	return out


func unlocked_ids() -> Array[String]:
	var out: Array[String] = []
	for r in unlocked():
		out.append(r.id)
	return out
