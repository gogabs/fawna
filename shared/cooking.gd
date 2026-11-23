class_name Cooking
extends RefCounted
## O forno: o que se cozinha nele, aceso, com o que está na bolsa. Fica em
## shared/ porque servidor e clientes usam as mesmas regras; quem decide é o
## servidor (WorldState.cook_start e o nó Survival).
##
## Cada receita gasta os ingredientes na hora e, passados "seconds", põe o que
## fez na bolsa. Ingrediente com a chave do grupo ("raiz", "cogumelo") aceita
## qualquer espécie dele; com a chave da espécie ("raiz_cenoura"), só ela.
## "pot": precisa de um pote de argila na bolsa (o pote não se gasta).
## "roast_all": assa tudo o que se assa na bolsa (Body.ROASTS), de uma vez.

## Distância (em casas) até o forno aceso para cozinhar.
const REACH := 2.5

const RECIPES := {
	"broa": {"name": "Broa de milho", "needs": {"milho": 3}, "makes": {"broa": 1}, "seconds": 6.0,
		"say": "Você mói o milho entre duas pedras, molda a broa e a põe no forno."},
	"ensopado": {"name": "Ensopado", "needs": {"raiz_cenoura": 1, "raiz": 2, "cogumelo": 1}, "pot": true,
		"makes": {"ensopado": 1}, "seconds": 8.0,
		"say": "Você pica as raízes e o cogumelo no pote, com água, e o põe no forno."},
	"assar": {"name": "Assar tudo", "roast_all": true, "seconds": 5.0,
		"say": "Você espalha o que tem para assar dentro do forno."},
	"pote": {"name": "Queimar o pote de argila", "needs": {"pote_cru": 1}, "makes": {"pote": 1}, "seconds": 10.0,
		"say": "Você põe o pote cru no fundo do forno, perto da brasa."},
}
const ORDER := ["broa", "ensopado", "assar", "pote"]


static func title(recipe: String) -> String:
	return str(RECIPES[recipe]["name"])


## O que a receita tiraria da bolsa agora: { take: {chave: n}, missing:
## {chave: n} }. As espécies pedidas pelo nome saem primeiro; o grupo pega o
## resto, na ordem da Bolsa.
static func plan(bag: Dictionary, recipe: String) -> Dictionary:
	var info: Dictionary = RECIPES.get(recipe, {})
	var take := {}
	var missing := {}
	if info.is_empty():
		return {"take": take, "missing": {"?": 1}}
	if bool(info.get("roast_all", false)):
		for item: String in bag:
			if not Body.roast_of(item).is_empty() and int(bag[item]) > 0:
				take[item] = int(bag[item])
		if take.is_empty():
			missing["assar"] = 1
		return {"take": take, "missing": missing}
	var needs: Dictionary = info.get("needs", {})
	var left := bag.duplicate()
	# Primeiro as chaves exatas, depois os grupos.
	var keys := needs.keys()
	keys.sort_custom(func(a, b): return int(Economy.subtypes_of(a).is_empty()) > int(Economy.subtypes_of(b).is_empty()))
	for key: String in keys:
		var want := int(needs[key])
		var options: Array = [key]
		if not Economy.subtypes_of(key).is_empty():
			options = Economy.subtypes_of(key).map(func(sub): return key + "_" + sub)
		for option: String in options:
			var have := int(left.get(option, 0))
			var used := mini(have, want)
			if used > 0:
				take[option] = int(take.get(option, 0)) + used
				left[option] = have - used
				want -= used
			if want <= 0:
				break
		if want > 0:
			missing[key] = want
	if bool(info.get("pot", false)) and int(bag.get("pote", 0)) <= 0:
		missing["pote"] = 1
	return {"take": take, "missing": missing}


## O que a receita faz com o que tirou: {item: n}.
static func makes(recipe: String, take: Dictionary) -> Dictionary:
	var info: Dictionary = RECIPES[recipe]
	if bool(info.get("roast_all", false)):
		var out := {}
		for item: String in take:
			var into := Body.roast_of(item)
			out[into] = int(out.get(into, 0)) + int(take[item])
		return out
	return info["makes"].duplicate()


## "3 espigas de milho" / "1 cenoura, 2 raízes, 1 cogumelo e um pote de argila".
static func needs_text(recipe: String) -> String:
	var info: Dictionary = RECIPES[recipe]
	if bool(info.get("roast_all", false)):
		return "raízes e espigas de milho cruas, todas as que estiverem na bolsa"
	var text := missing_text(info.get("needs", {}))
	if bool(info.get("pot", false)):
		text += ", no pote de argila (que não se gasta)"
	return text


## {raiz: 2, pote: 1} -> "2 raízes e o pote de argila".
static func missing_text(missing: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in missing:
		if key == "pote":
			parts.append("o pote de argila")
		elif key == "assar":
			parts.append("algo cru para assar")
		else:
			parts.append(Economy.item_text(key, int(missing[key])))
	if parts.size() <= 1:
		return "".join(parts)
	return ", ".join(parts.slice(0, -1)) + " e " + parts[-1]
