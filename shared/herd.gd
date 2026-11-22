class_name Herd
extends RefCounted
## Os cavalinhos-da-bruma selvagens. A simulação roda só no servidor; os
## clientes só recebem os acontecimentos (apareceu, andou, bufou, sumiu) e
## tocam os sons.
##
## Vivem em manadas de 3 a 6 na pradaria de girassóis e no deserto gelado.
## Como os pássaros, só existem perto de alguém: cada pedaço do mundo tem
## sempre as mesmas manadas para a mesma semente, e quando ninguém está por
## perto elas somem.
##
## A manada pasta parada um tempo, depois anda devagar para outro ponto perto
## de casa. Quem chega perto é notado: a manada bufa de alerta. Quem continua
## vindo enquanto ela está desconfiada a faz fugir a galope. Quem para e
## espera um pouco (SETTLE) passa a ser tolerado e pode chegar bem perto.
## Barulho forte por perto (golpe, salto, uivo, faísca) espanta na hora. À
## noite, quando o Calado chega perto, eles relincham de alarme e fogem dele.
##
## Domesticar: quem já é tolerado chega bem perto de um cavalo e oferece
## frutas (offer), uma de cada vez, esperando ele mastigar. Depois de 4 ou 5,
## o cavalo fica junto; quem ofereceu precisa ficar quieto ao lado por
## QUIET_TO_TAME segundos, e o cavalo passa a ser dele ("tamed"). Um susto que
## faz a manada fugir, ou ir embora para longe, perde a confiança ganha.
## Domesticado, o cavalo sai da manada, fica salvo no mundo com dono e nome
## (tame_to_save), não some quando todos vão embora, e relincha manso quando
## o dono chega perto.

enum Gait { STAND, WALK, GALLOP, TROT }  # TROT só montado

## Distâncias em casas, tempos em segundos.
const GROUP := [3, 6]
const WALK_SPEED := 1.1
const GALLOP_SPEED := 4.5
const STAY := [20.0, 60.0]  # pastando num lugar antes de andar
const HOP := [4.0, 10.0]  # distância de uma andada normal
const HOME_RADIUS := 18.0  # a manada não se afasta mais que isso de casa
## Casas: cada cavalo para a até SPREAD do alvo da manada, e a pelo menos
## APART de outro. Juntos demais, o som de todos parecia vir de um ponto só.
const SPREAD := 6.0
const APART := 2.2
const STAGGER := 1.2  # segundos: nem todos saem juntos andando

## Quem chega a ALERT casas é notado (bufo de alerta). Se continuar se
## mexendo dentro de FLEE_NEAR enquanto a manada desconfia, ela foge. Parado
## SETTLE segundos dentro de ALERT, passa a ser tolerado (só espanta se
## esbarrar, a TOLERATED casas);
## se sair para longe de FORGET, a manada esquece dele.
const ALERT := 9.0
const FLEE_NEAR := 4.5
const TOLERATED := 0.6  # casas: quem já foi aceito só espanta se esbarrar
const SETTLE := 4.0
const FORGET := 14.0
const MOVE_EPSILON := 0.15  # casas por passo: menos que isso é ficar parado
const FLEE_DISTANCE := [16.0, 24.0]
const CALM_AFTER_FLEE := 12.0  # depois de fugir, não foge de novo tão cedo
## Barulho forte a até NOISE_SCARE casas espanta.
const NOISE_SCARE := 14.0
## Depuração (summon): de onde a manada chamada vem e onde para, em casas.
const SUMMON_FROM := 16.0
const SUMMON_TO := 8.0

## Sons de cada cavalo (segundos entre um e outro).
const GRAZE_EVERY := [5.0, 14.0]
const SNORT_EVERY := [25.0, 60.0]
const NEIGH_EVERY := [70.0, 200.0]
const ALARM_EVERY := 20.0  # relincho de alarme do Calado, no máximo assim

## Chance de um pedaço (CHUNK casas) ter uma manada, por bioma.
const SPAWNS := {
	WorldGen.Biome.PRADARIA: 0.08,
	WorldGen.Biome.DESERTO_GELADO: 0.06,
}

## Sons que o servidor manda (o cliente escolhe a variação).
const SOUNDS := ["pasto", "bufo", "relincho", "alarme", "manso"]

## Domesticar (casas e segundos; ver offer).
const OFFER_REACH := 1.6
const FRUITS_TO_TAME := [4, 5]
const CHEW := 5.0  # mastigando: não aceita outra fruta antes disso
const QUIET_TO_TAME := 10.0
const TAME_NEAR := 3.0  # quem ofereceu fica a até isso do cavalo, quieto
const OWNER_NICKER := 6.0  # o domesticado relincha manso com o dono a até isso
const NICKER_EVERY := [20.0, 50.0]

## Seguir e montar (casas, casas por segundo, segundos). O domesticado segue o
## dono sempre, menos enquanto come: para atrás dele, a FOLLOW_NEAR, quando
## ele se afasta mais que FOLLOW_FAR; de longe (GALLOP_AFTER) vem a galope, e
## se o dono sumir para mais longe que FOLLOW_JUMP (teleporte, desmaio), surge
## ao lado dele. Montado, vai junto de quem monta, andando ou a galope conforme
## a velocidade (RIDE_TROT, RIDE_GALLOP).
const FOLLOW_NEAR := 1.4
const FOLLOW_FAR := 3.2
const FOLLOW_SPEED := 2.2  # um pouco mais rápido que a criatura (1,8)
const GALLOP_AFTER := 10.0
const FOLLOW_JUMP := 40.0
const FOLLOW_RETARGET := 1.5  # dono andou isso desde o último alvo: recalcula
const EAT_TIME := [4.0, 8.0]
const RIDE_TROT := 2.2  # a ré montada (2,4) já soa como trote
const RIDE_GALLOP := 3.7
const MOUNT_REACH := 2.0

## Nome dos cavalos: um prefixo e um sufixo que juntos formam um nome
## inventado (Bram + ion = Bramion), escolhidos em duas listas, como o nome
## dos povoados. Os prefixos terminam em consoante e os sufixos começam em
## vogal, para qualquer par soar bem. Cada cavalo oferece NAME_CHOICES de cada
## por vez, sorteados.
const PREFIXES := [
	"Bram", "Cin", "Gar", "Ser", "Vel", "Mor", "Tor", "Ul", "Ner", "Ast",
	"Corv", "Fal", "Lum", "Sard", "Breg", "Ív", "Hal", "Esp", "Ruv", "Zan",
]
const SUFFIXES := [
	"a", "ena", "ion", "aro", "uz", "ela", "ino", "ava", "ego", "ir",
	"ura", "ante", "ália", "orn", "ês", "ilo", "ada", "eu",
]
const NAME_CHOICES := 6

## Pelagens: só para a vista 3D (e, mais tarde, para a fala).
const COATS := ["cinza-cinza", "baio-escuro", "preto-fumaça", "ruão-pálido"]

const CHUNK := WorldGen.CHUNK
const ACTIVE_CHUNKS := 2
const KEEP_CHUNKS := 3
const HEARING := 32.0  # casas: até onde um jogador fica sabendo de um cavalo
const SYNC_INTERVAL_MS := 500

var world: WorldGen
## Pontos (Vector2) dos horrores, atualizados por quem roda a simulação.
var hush: Array = []
var darkness := 0.0

## id -> cavalo: { id, herd, pitch, coat, pos, from, to, start_ms, end_ms,
## gait, next_graze_ms, next_snort_ms, next_neigh_ms, watchers }
var horses := {}
## id -> manada: { id, chunk, home, members, leave_ms, wary: { peer: {...} },
## calm_until_ms, alarm_ms }
var herds := {}

var _chunks := {}
var _next_id := 1
var _last_sync_ms := -SYNC_INTERVAL_MS
var _rng := RandomNumberGenerator.new()
var _last_players := {}  # peer -> posição no passo anterior
var _noises := []  # [ponto] ouvidos desde o último passo
var _pending := []  # mensagens geradas fora do passo (summon), saem no próximo
## peer -> chave de dono (WorldState.owner_key), atualizado por quem roda.
var peer_keys := {}


func _init(the_world: WorldGen) -> void:
	world = the_world
	_rng.seed = world.world_seed + 4242


## Passo da simulação. "players" é id -> posição (Vector2, em casas).
## Devolve [peer, tipo, argumentos], com tipo "appear", "gone", "move" ou
## "sound".
func update(now_ms: int, players: Dictionary) -> Array:
	var out := _pending
	_pending = []
	_update_chunks(players, out)
	for herd_id in herds.keys():
		_update_herd(herds[herd_id], now_ms, players, out)
	for horse in horses.values():
		if int(horse["herd"]) < 0:
			_update_tame(horse, now_ms, players, out)
	_last_players = players.duplicate()
	_noises.clear()
	if now_ms - _last_sync_ms >= SYNC_INTERVAL_MS:
		_last_sync_ms = now_ms
		_sync_watchers(now_ms, players, out)
	return out


## Um barulho forte num ponto (golpe, habilidade): espanta quem estiver perto.
func hear_noise(point: Vector2) -> void:
	_noises.append(point)


func forget_peer(peer: int) -> void:
	for horse in horses.values():
		horse["watchers"].erase(peer)
	for herd in herds.values():
		herd["wary"].erase(peer)
	for horse in horses.values():
		if int(horse["rider"]) == peer:
			horse["rider"] = -1
			_send_rider(horse, _pending)
	_last_players.erase(peer)


func position_of(horse: Dictionary, now_ms: int) -> Vector2:
	if int(horse["gait"]) == Gait.STAND or now_ms >= int(horse["end_ms"]):
		return horse["to"]
	if now_ms <= int(horse["start_ms"]):
		return horse["from"]
	var x := float(now_ms - int(horse["start_ms"])) / maxi(1, int(horse["end_ms"]) - int(horse["start_ms"]))
	return (horse["from"] as Vector2).lerp(horse["to"], x)


func horse_count() -> int:
	return horses.size()


## O cavalo selvagem mais perto de um ponto, ou {} se não houver.
func nearest(point: Vector2, now_ms: int) -> Dictionary:
	var best := {}
	var best_d := INF
	for horse in horses.values():
		var d := position_of(horse, now_ms).distance_to(point)
		if d < best_d:
			best_d = d
			best = horse
	return best


# --- Domesticar ----------------------------------------------------------------

## "peer" oferece uma fruta ao cavalo "horse_id". Quem chama confere e gasta a
## fruta só se der certo. Devolve { ok, reason }: reason "comeu", "pronto"
## (comeu a última; agora é ficar quieto ao lado), "desconfia" (a manada
## ainda não o tolera), "longe", "mastigando", "domado" (já tem dono) ou
## "sumiu".
func offer(peer: int, horse_id: int, now_ms: int, pos: Vector2) -> Dictionary:
	if not horses.has(horse_id):
		return {"ok": false, "reason": "sumiu"}
	var horse: Dictionary = horses[horse_id]
	if int(horse["herd"]) < 0:
		return {"ok": false, "reason": "domado"}
	var herd: Dictionary = herds[int(horse["herd"])]
	var entry: Dictionary = herd["wary"].get(peer, {})
	if not bool(entry.get("settled", false)):
		return {"ok": false, "reason": "desconfia"}
	if position_of(horse, now_ms).distance_to(pos) > OFFER_REACH:
		return {"ok": false, "reason": "longe"}
	if now_ms < int(horse["chew_until_ms"]):
		return {"ok": false, "reason": "mastigando"}
	if int(horse["trust_peer"]) != peer:
		# Outra pessoa começa do zero com ele.
		horse["trust"] = 0
		horse["trust_peer"] = peer
	horse["trust"] = int(horse["trust"]) + 1
	horse["chew_until_ms"] = now_ms + int(CHEW * 1000.0)
	horse["quiet_ms"] = 0.0
	horse["next_graze_ms"] = now_ms + int(CHEW * 1000.0)
	_pending_sound(horse, "pasto")
	if int(horse["trust"]) >= int(horse["need"]):
		_pending_sound(horse, "manso")
		return {"ok": true, "reason": "pronto"}
	if int(horse["trust"]) >= 2:
		_pending_sound(horse, "manso")
	return {"ok": true, "reason": "comeu"}


## Quem comeu tudo e tem a pessoa quieta ao lado o bastante vira dela.
## Devolve true se algum cavalo foi domesticado (a manada não anda nesse passo).
func _taming(herd: Dictionary, now_ms: int, players: Dictionary, out: Array) -> bool:
	for horse_id in herd["members"].duplicate():
		var horse: Dictionary = horses[horse_id]
		var peer := int(horse["trust_peer"])
		if int(horse["trust"]) < int(horse["need"]) or not players.has(peer):
			continue
		var pos: Vector2 = players[peer]
		var moved := 0.0
		if _last_players.has(peer):
			moved = pos.distance_to(_last_players[peer])
		if moved >= MOVE_EPSILON or position_of(horse, now_ms).distance_to(pos) > TAME_NEAR:
			horse["quiet_ms"] = 0.0
			continue
		horse["quiet_ms"] = float(horse["quiet_ms"]) + 250.0
		if float(horse["quiet_ms"]) >= QUIET_TO_TAME * 1000.0:
			_tame(herd, horse, peer, now_ms, out)
			return true
	return false


func _tame(herd: Dictionary, horse: Dictionary, peer: int, now_ms: int, out: Array) -> void:
	var here := position_of(horse, now_ms)
	herd["members"].erase(horse["id"])
	horse["herd"] = -1
	horse["owner"] = str(peer_keys.get(peer, ""))
	horse["name"] = ""
	horse["from"] = here
	horse["to"] = here
	horse["gait"] = Gait.STAND
	horse["trust"] = 0
	horse["rider"] = -1
	horse["eat_until_ms"] = now_ms + _ms(EAT_TIME)
	horse["aim"] = here
	horse["next_neigh_ms"] = now_ms + _ms(NICKER_EVERY)
	out.append([peer, "tamed", [horse["id"]]])
	_send_named(horse, out)
	if herd["members"].is_empty():
		_forget_herd(herd)


## A manada perde a confiança de "peer" (-1: de todos).
func _lose_trust(herd: Dictionary, peer: int) -> void:
	for horse_id in herd["members"]:
		var horse: Dictionary = horses[horse_id]
		if peer < 0 or int(horse["trust_peer"]) == peer:
			horse["trust"] = 0
			horse["trust_peer"] = -1
			horse["quiet_ms"] = 0.0


## Tira uma manada vazia (todos domesticados) da lista e do pedaço dela.
func _forget_herd(herd: Dictionary) -> void:
	herds.erase(herd["id"])
	if _chunks.has(herd["chunk"]):
		_chunks[herd["chunk"]].erase(herd["id"])


## O domesticado: segue o dono (menos comendo) ou vai junto de quem monta;
## pasta, bufa e relincha manso quando o dono chega perto.
func _update_tame(horse: Dictionary, now_ms: int, players: Dictionary, out: Array) -> void:
	if int(horse["gait"]) != Gait.STAND and now_ms >= int(horse["end_ms"]):
		horse["gait"] = Gait.STAND
		horse["from"] = horse["to"]
	if int(horse["next_graze_ms"]) < 0:
		horse["next_graze_ms"] = now_ms + _ms(GRAZE_EVERY, 0.0)
		horse["next_snort_ms"] = now_ms + _ms(SNORT_EVERY, 0.2)
		horse["next_neigh_ms"] = now_ms + _ms(NICKER_EVERY, 0.3)
	var rider := int(horse["rider"])
	if rider >= 0:
		if players.has(rider):
			_carry(horse, players[rider], now_ms, out)
		else:
			horse["rider"] = -1
			_send_rider(horse, out)
	else:
		_follow_owner(horse, now_ms, players, out)
	var standing := int(horse["gait"]) == Gait.STAND
	if now_ms >= int(horse["next_graze_ms"]):
		horse["next_graze_ms"] = now_ms + _ms(GRAZE_EVERY)
		if standing and rider < 0 and not _owner_walking(horse, players):
			# Para para comer (só com o dono parado): enquanto isso, não segue.
			horse["eat_until_ms"] = now_ms + _ms(EAT_TIME)
			_sound(horse, "pasto", out)
	if now_ms >= int(horse["next_snort_ms"]):
		horse["next_snort_ms"] = now_ms + _ms(SNORT_EVERY)
		_sound(horse, "bufo", out)
	if now_ms >= int(horse["next_neigh_ms"]):
		horse["next_neigh_ms"] = now_ms + _ms(NICKER_EVERY)
		var owner_peer := _owner_peer(horse)
		if owner_peer >= 0 and rider < 0 and players.has(owner_peer) and (players[owner_peer] as Vector2).distance_to(position_of(horse, now_ms)) <= OWNER_NICKER:
			_sound(horse, "manso", out)


## O dono está andando agora (mudou de lugar desde o passo anterior) ou
## longe? Então o cavalo não para para comer.
func _owner_walking(horse: Dictionary, players: Dictionary) -> bool:
	var peer := _owner_peer(horse)
	if peer < 0 or not players.has(peer):
		return false
	# Longe do dono, também não para: primeiro vai até ele.
	if (players[peer] as Vector2).distance_to(horse["to"]) > FOLLOW_FAR:
		return true
	if not _last_players.has(peer):
		return false
	return (players[peer] as Vector2).distance_to(_last_players[peer]) >= MOVE_EPSILON


## O peer do dono, se estiver no mundo; senão -1.
func _owner_peer(horse: Dictionary) -> int:
	for peer in peer_keys:
		if str(peer_keys[peer]) == str(horse["owner"]):
			return int(peer)
	return -1


## Montado: o cavalo vai junto de quem monta, a cada passo.
func _carry(horse: Dictionary, pos: Vector2, now_ms: int, out: Array) -> void:
	var here: Vector2 = horse["to"]
	var moved := here.distance_to(pos)
	var step_s := 0.25
	var gait := Gait.STAND
	if moved >= MOVE_EPSILON * 0.5:
		var speed := moved / step_s
		gait = Gait.GALLOP if speed >= RIDE_GALLOP else (Gait.TROT if speed >= RIDE_TROT else Gait.WALK)
	if gait == Gait.STAND and int(horse["gait"]) == Gait.STAND:
		return
	horse["from"] = here
	horse["to"] = pos
	horse["gait"] = gait
	horse["start_ms"] = now_ms
	horse["end_ms"] = now_ms + int(step_s * 1000.0) + 40
	_send_move(horse, 0.0, out)


## Seguindo: quando o dono se afasta, vai até atrás dele.
func _follow_owner(horse: Dictionary, now_ms: int, players: Dictionary, out: Array) -> void:
	var peer := _owner_peer(horse)
	if peer < 0 or not players.has(peer):
		return
	if now_ms < int(horse["eat_until_ms"]):
		return
	var owner_pos: Vector2 = players[peer]
	var here := position_of(horse, now_ms)
	var far := here.distance_to(owner_pos)
	if far > FOLLOW_JUMP:
		var spot := _spot_near(owner_pos, here)
		horse["from"] = spot
		horse["to"] = spot
		horse["aim"] = owner_pos
		horse["gait"] = Gait.STAND
		_send_move(horse, 0.0, out)
		return
	var moving := int(horse["gait"]) != Gait.STAND
	if moving and (horse["aim"] as Vector2).distance_to(owner_pos) < FOLLOW_RETARGET:
		return
	if not moving and far <= FOLLOW_FAR:
		return
	var target := _spot_near(owner_pos, here)
	if target.distance_to(here) < 0.3:
		return
	var gallop := far > GALLOP_AFTER
	var speed := GALLOP_SPEED if gallop else FOLLOW_SPEED
	horse["from"] = here
	horse["to"] = target
	horse["aim"] = owner_pos
	horse["gait"] = Gait.GALLOP if gallop else Gait.WALK
	horse["start_ms"] = now_ms
	horse["end_ms"] = now_ms + int(here.distance_to(target) / speed * 1000.0) + 100
	_send_move(horse, 0.0, out)


## Um ponto livre a FOLLOW_NEAR de "owner_pos", do lado de onde o cavalo vem.
func _spot_near(owner_pos: Vector2, from: Vector2) -> Vector2:
	var away := (from - owner_pos)
	var base := away.angle() if away.length() > 0.01 else 0.0
	for k in 9:
		var angle := base + (k / 2) * 0.6 * (1 if k % 2 == 0 else -1)
		var point := owner_pos + Vector2.from_angle(angle) * FOLLOW_NEAR
		if _walkable(point):
			return point
	return owner_pos


func _send_move(horse: Dictionary, elapsed: float, out: Array) -> void:
	var duration := maxf(0.0, (int(horse["end_ms"]) - int(horse["start_ms"])) / 1000.0) if int(horse["gait"]) != Gait.STAND else 0.0
	var args := [horse["id"], horse["from"], horse["to"], 0.0, duration, elapsed, int(horse["gait"])]
	for peer in horse["watchers"]:
		out.append([peer, "move", args])


## Montar no próprio cavalo. Devolve "montou", "longe", "nao_e_seu",
## "montado" (alguém já está nele) ou "sumiu".
func mount(peer: int, horse_id: int, pos: Vector2, now_ms: int) -> String:
	if not horses.has(horse_id):
		return "sumiu"
	var horse: Dictionary = horses[horse_id]
	if int(horse["herd"]) >= 0 or str(horse["owner"]) != str(peer_keys.get(peer, "")) or str(horse["owner"]).is_empty():
		return "nao_e_seu"
	if int(horse["rider"]) >= 0:
		return "montado"
	if position_of(horse, now_ms).distance_to(pos) > MOUNT_REACH:
		return "longe"
	horse["rider"] = peer
	horse["eat_until_ms"] = 0
	_send_rider(horse, _pending)
	_carry(horse, pos, now_ms, _pending)
	return "montou"


## Desmontar: o cavalo fica onde está e volta a seguir. Devolve o id, ou -1.
func dismount(peer: int, now_ms: int) -> int:
	var horse_id := riding_of(peer)
	if horse_id < 0:
		return -1
	var horse: Dictionary = horses[horse_id]
	horse["rider"] = -1
	var here := position_of(horse, now_ms)
	horse["from"] = here
	horse["to"] = here
	horse["aim"] = here
	horse["gait"] = Gait.STAND
	_send_move(horse, 0.0, _pending)
	_send_rider(horse, _pending)
	return horse_id


## O cavalo em que "peer" está montado, ou -1.
func riding_of(peer: int) -> int:
	for horse in horses.values():
		if int(horse["rider"]) == peer:
			return int(horse["id"])
	return -1


## Avisa quem vê o cavalo de quem está montado nele ("" = ninguém).
func _send_rider(horse: Dictionary, out: Array) -> void:
	var key := str(peer_keys.get(int(horse["rider"]), "")) if int(horse["rider"]) >= 0 else ""
	for peer in horse["watchers"]:
		out.append([peer, "rider", [horse["id"], key]])


## O dono dá nome ao seu cavalo (prefixo + sufixo, ver compose_name).
## Devolve true se mudou.
func rename(peer: int, horse_id: int, new_name: String) -> bool:
	if not horses.has(horse_id) or not is_name(new_name):
		return false
	var horse: Dictionary = horses[horse_id]
	if int(horse["herd"]) >= 0 or str(horse["owner"]) != str(peer_keys.get(peer, "")) or str(horse["owner"]).is_empty():
		return false
	horse["name"] = new_name
	_send_named(horse, _pending)
	return true


## Depuração: domestica na hora o cavalo selvagem mais perto de "point".
## Devolve o id, ou -1 se não houver nenhum a até HEARING casas.
func debug_tame(peer: int, point: Vector2, now_ms: int) -> int:
	var best := {}
	var best_d := HEARING
	for horse in horses.values():
		var d := position_of(horse, now_ms).distance_to(point)
		if int(horse["herd"]) >= 0 and d < best_d:
			best_d = d
			best = horse
	if best.is_empty():
		return -1
	_tame(herds[int(best["herd"])], best, peer, now_ms, _pending)
	return int(best["id"])


## Os prefixos que este cavalo oferece na página "page" (índices em PREFIXES).
static func name_prefixes(horse_id: int, page: int) -> Array:
	return _shuffled_page(PREFIXES.size(), [horse_id, "prefixos"], page)


## Os sufixos oferecidos junto do prefixo escolhido (índices em SUFFIXES).
static func name_suffixes(horse_id: int, prefix: int, page: int) -> Array:
	return _shuffled_page(SUFFIXES.size(), [horse_id, prefix, "sufixos"], page)


static func compose_name(prefix: int, suffix: int) -> String:
	return str(PREFIXES[prefix]) + str(SUFFIXES[suffix])


## É um nome que se forma com as listas?
static func is_name(text: String) -> bool:
	for p in PREFIXES.size():
		if text.begins_with(PREFIXES[p]) and SUFFIXES.has(text.substr(str(PREFIXES[p]).length())):
			return true
	return false


static func _shuffled_page(count: int, key: Array, page: int) -> Array:
	var order := range(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var out := []
	for k in NAME_CHOICES:
		out.append(order[(page * NAME_CHOICES + k) % count])
	return out


## Os domesticados, para salvar no mundo.
func tame_to_save() -> Array:
	var out := []
	for horse in horses.values():
		if int(horse["herd"]) < 0:
			var at: Vector2 = horse["to"]
			out.append({"owner": horse["owner"], "name": horse["name"], "x": at.x, "y": at.y,
				"coat": horse["coat"], "pitch": horse["pitch"]})
	return out


## Traz de volta os domesticados salvos (ver tame_to_save).
func load_tame(saved: Array) -> void:
	for entry in saved:
		if typeof(entry) != TYPE_DICTIONARY or str(entry.get("owner", "")).is_empty():
			continue
		var at := Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)))
		if not at.is_finite():
			continue
		var horse := {
			"id": _next_id, "herd": -1,
			"pitch": clampf(float(entry.get("pitch", 1.0)), 0.8, 1.2),
			"coat": posmod(int(entry.get("coat", 0)), COATS.size()),
			"from": at, "to": at, "start_ms": 0, "end_ms": 0, "gait": Gait.STAND,
			"next_graze_ms": -1, "next_snort_ms": -1, "next_neigh_ms": -1,
			"watchers": {}, "need": 0, "trust": 0, "trust_peer": -1, "chew_until_ms": 0, "quiet_ms": 0.0,
			"owner": str(entry["owner"]), "rider": -1, "eat_until_ms": 0, "aim": at,
			"name": str(entry.get("name", "")) if is_name(str(entry.get("name", ""))) else "",
		}
		_next_id += 1
		horses[horse["id"]] = horse


## Avisa quem vê o cavalo do dono e do nome dele.
func _send_named(horse: Dictionary, out: Array) -> void:
	for peer in horse["watchers"]:
		out.append([peer, "named", [horse["id"], horse["owner"], horse["name"]]])


func _pending_sound(horse: Dictionary, kind: String) -> void:
	_sound(horse, kind, _pending)


# --- Pedaços com cavalos -------------------------------------------------------

func _update_chunks(players: Dictionary, out: Array) -> void:
	var wanted := {}
	var keep := {}
	for id in players:
		var here := _chunk_of(players[id])
		for dy in range(-KEEP_CHUNKS, KEEP_CHUNKS + 1):
			for dx in range(-KEEP_CHUNKS, KEEP_CHUNKS + 1):
				var chunk := here + Vector2i(dx, dy)
				keep[chunk] = true
				if absi(dx) <= ACTIVE_CHUNKS and absi(dy) <= ACTIVE_CHUNKS:
					wanted[chunk] = true
	for chunk in _chunks.keys():
		if not keep.has(chunk):
			for herd_id in _chunks[chunk]:
				_remove_herd(herd_id, out)
			_chunks.erase(chunk)
	for chunk in wanted:
		if not _chunks.has(chunk):
			_chunks[chunk] = _spawn_chunk(chunk)


func _spawn_chunk(chunk: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world.world_seed, chunk.x, chunk.y, "cavalos"])
	var origin := chunk * CHUNK
	var middle := WorldGen.cell_center(origin + Vector2i.ONE * (CHUNK / 2))
	var biome := world.biome_at(WorldGen.cell_of(middle))
	if rng.randf() >= float(SPAWNS.get(biome, 0.0)):
		return []
	# Casa da manada: um ponto de chão livre no pedaço, de preferência longe
	# de trilha (eles evitam onde a gente passa).
	var home := Vector2.INF
	for attempt in 24:
		var cell := origin + Vector2i(rng.randi_range(2, CHUNK - 3), rng.randi_range(2, CHUNK - 3))
		if world.thing_at(cell) == WorldGen.Thing.NADA and world.biome_at(cell) == biome:
			home = WorldGen.cell_center(cell)
			break
	if home == Vector2.INF:
		return []
	var herd_id := _make_herd(chunk, home, biome, rng)
	return [] if herd_id < 0 else [herd_id]


## Cria uma manada com casa em "home". Devolve o id, ou -1 se não coube.
func _make_herd(chunk: Vector2i, home: Vector2, biome: int, rng: RandomNumberGenerator) -> int:
	var herd := {
		"id": _next_id, "chunk": chunk, "home": home, "members": [],
		"leave_ms": -1, "wary": {}, "calm_until_ms": 0, "alarm_ms": 0,
		"biome": biome,
	}
	_next_id += 1
	var size := rng.randi_range(GROUP[0], GROUP[1])
	var spots := _member_spots(home, size, rng)
	for i in spots.size():
		var horse := {
			"id": _next_id, "herd": herd["id"],
			"pitch": rng.randf_range(0.9, 1.1),
			"coat": rng.randi() % COATS.size(),
			"from": spots[i], "to": spots[i], "start_ms": 0, "end_ms": 0,
			"gait": Gait.STAND,
			"next_graze_ms": -1, "next_snort_ms": -1, "next_neigh_ms": -1,
			"watchers": {},
			"need": rng.randi_range(FRUITS_TO_TAME[0], FRUITS_TO_TAME[1]),
			"trust": 0, "trust_peer": -1, "chew_until_ms": 0, "quiet_ms": 0.0,
			"owner": "", "name": "", "rider": -1, "eat_until_ms": 0, "aim": Vector2.INF,
		}
		_next_id += 1
		horses[horse["id"]] = horse
		herd["members"].append(horse["id"])
	if herd["members"].is_empty():
		return -1
	herds[herd["id"]] = herd
	return herd["id"]


## Depuração: traz a manada mais perto (ou cria uma, em qualquer bioma) para
## perto de "point". Ela surge a SUMMON_FROM casas e vem andando até parar a
## SUMMON_TO casas, para dar tempo de ouvir os cascos chegando. Devolve
## quantos cavalos vieram (0 se não achou lugar).
func summon(point: Vector2, now_ms: int) -> int:
	var herd := {}
	var best := INF
	for candidate in herds.values():
		var d := _herd_center(candidate, now_ms).distance_to(point)
		if d < best:
			best = d
			herd = candidate
	var target := Vector2.INF
	var start := Vector2.INF
	for attempt in 48:
		var angle := _rng.randf() * TAU
		var to := point + Vector2.from_angle(angle) * SUMMON_TO
		var from := point + Vector2.from_angle(angle) * SUMMON_FROM
		if _walkable(to) and _walkable(from) and _clear_line(from, to):
			target = to
			start = from
			break
	if target == Vector2.INF:
		return 0
	if herd.is_empty():
		var chunk := _chunk_of(point)
		var rng := RandomNumberGenerator.new()
		rng.seed = _rng.randi()
		var herd_id := _make_herd(chunk, start, world.biome_at(WorldGen.cell_of(point)), rng)
		if herd_id < 0:
			return 0
		if not _chunks.has(chunk):
			_chunks[chunk] = []
		_chunks[chunk].append(herd_id)
		herd = herds[herd_id]
	herd["home"] = target
	herd["wary"].clear()
	herd["leave_ms"] = now_ms + _ms(STAY)
	var spots := _member_spots(target, herd["members"].size(), _rng)
	var starts := _member_spots(start, herd["members"].size(), _rng)
	if spots.is_empty() or starts.is_empty():
		return 0
	for i in herd["members"].size():
		var horse: Dictionary = horses[herd["members"][i]]
		var here: Vector2 = starts[i % starts.size()]
		var to: Vector2 = spots[i % spots.size()]
		var delay := 0.0 if i == 0 else _rng.randf_range(0.1, STAGGER)
		horse["from"] = here
		horse["to"] = to
		horse["gait"] = Gait.WALK
		horse["start_ms"] = now_ms + int(delay * 1000.0)
		horse["end_ms"] = int(horse["start_ms"]) + int(here.distance_to(to) / WALK_SPEED * 1000.0) + 200
		# Quem já via o cavalo recebe a andada nova; quem não via fica sabendo
		# na próxima sincronização.
		var args := [horse["id"], here, to, delay, (int(horse["end_ms"]) - int(horse["start_ms"])) / 1000.0, 0.0, Gait.WALK]
		for peer in horse["watchers"]:
			_pending.append([peer, "move", args])
	return herd["members"].size()


func _remove_herd(herd_id: int, out: Array) -> void:
	if not herds.has(herd_id):
		return
	for horse_id in herds[herd_id]["members"]:
		var horse: Dictionary = horses[horse_id]
		for peer in horse["watchers"]:
			out.append([peer, "gone", [horse_id]])
		horses.erase(horse_id)
	herds.erase(herd_id)


# --- Comportamento -------------------------------------------------------------

func _update_herd(herd: Dictionary, now_ms: int, players: Dictionary, out: Array) -> void:
	if int(herd["leave_ms"]) < 0:
		herd["leave_ms"] = now_ms + _ms(STAY, 0.3)
	var center := _herd_center(herd, now_ms)
	var moving := false
	for horse_id in herd["members"]:
		var horse: Dictionary = horses[horse_id]
		if int(horse["gait"]) != Gait.STAND:
			if now_ms >= int(horse["end_ms"]):
				horse["gait"] = Gait.STAND
				horse["from"] = horse["to"]
			else:
				moving = true
		_idle_sounds(horse, now_ms, out)
	var threat := _threat(herd, center, now_ms, players, out)
	if threat != Vector2.INF:
		_move_herd(herd, now_ms, threat, out)
		return
	if _taming(herd, now_ms, players, out):
		return
	var night := darkness >= 0.6
	if not moving and now_ms >= int(herd["leave_ms"]) and herd["wary"].is_empty():
		# De noite andam menos: ficam juntos, quietos.
		if night and _rng.randf() < 0.6:
			herd["leave_ms"] = now_ms + _ms(STAY)
		else:
			_move_herd(herd, now_ms, Vector2.INF, out)


## Decide se a manada foge e de onde. Cuida também do bufo de alerta e do
## relincho de alarme do Calado.
func _threat(herd: Dictionary, center: Vector2, now_ms: int, players: Dictionary, out: Array) -> Vector2:
	var fleeing_ok := now_ms >= int(herd["calm_until_ms"])
	# O Calado: alarme de longe, fuga de perto (sempre, mesmo logo após fugir).
	for spot: Vector2 in hush:
		var d := spot.distance_to(center)
		if d <= Horrors.HUSH_RADIUS and now_ms >= int(herd["alarm_ms"]):
			herd["alarm_ms"] = now_ms + int(ALARM_EVERY * 1000.0)
			_sound(horses[herd["members"][0]], "alarme", out)
			if d <= Horrors.SCARE_RADIUS:
				return spot
	# Barulho forte por perto.
	if fleeing_ok:
		for point: Vector2 in _noises:
			if point.distance_to(center) <= NOISE_SCARE:
				return point
	# Quem chega perto.
	var wary: Dictionary = herd["wary"]
	for peer in wary.keys():
		if not players.has(peer) or (players[peer] as Vector2).distance_to(center) > FORGET:
			wary.erase(peer)
			_lose_trust(herd, peer)
	var found := Vector2.INF
	for peer in players:
		var pos: Vector2 = players[peer]
		var d := pos.distance_to(center)
		if d > ALERT:
			continue
		var moved := 0.0
		if _last_players.has(peer):
			moved = pos.distance_to(_last_players[peer])
		if not wary.has(peer):
			wary[peer] = {"still": 0.0, "settled": false}
			# Bufo de alerta: um da manada levanta a cabeça.
			_sound(horses[herd["members"][_rng.randi() % herd["members"].size()]], "bufo", out)
		var entry: Dictionary = wary[peer]
		if moved < MOVE_EPSILON:
			entry["still"] = float(entry["still"]) + 0.25
			if float(entry["still"]) >= SETTLE:
				entry["settled"] = true
		else:
			entry["still"] = 0.0
		var limit := TOLERATED if entry["settled"] else FLEE_NEAR
		if fleeing_ok and found == Vector2.INF and moved >= MOVE_EPSILON and _nearest_member(herd, pos, now_ms) <= limit:
			found = pos
	if found != Vector2.INF:
		wary.clear()
	return found


## Leva a manada para outro ponto. Com "threat", foge a galope para longe.
func _move_herd(herd: Dictionary, now_ms: int, threat: Vector2, out: Array) -> void:
	var startled := threat != Vector2.INF
	var from := _herd_center(herd, now_ms)
	var target := _pick_target(herd, from, threat)
	if target == Vector2.INF:
		herd["leave_ms"] = now_ms + _ms(STAY, 0.3)
		return
	herd["leave_ms"] = now_ms + _ms(STAY) + (int(8000) if startled else 0)
	if startled:
		herd["calm_until_ms"] = now_ms + int(CALM_AFTER_FLEE * 1000.0)
		_lose_trust(herd, -1)
		_sound(horses[herd["members"][0]], "alarme" if threat in hush else "relincho", out)
	var spots := _member_spots(target, herd["members"].size(), _rng)
	if spots.is_empty():
		return
	var speed := GALLOP_SPEED if startled else WALK_SPEED
	for i in herd["members"].size():
		var horse: Dictionary = horses[herd["members"][i]]
		var here := position_of(horse, now_ms)
		var to: Vector2 = spots[i % spots.size()]
		var delay := 0.0 if i == 0 else _rng.randf_range(0.05, 0.4 if startled else STAGGER)
		horse["from"] = here
		horse["to"] = to
		horse["gait"] = Gait.GALLOP if startled else Gait.WALK
		horse["start_ms"] = now_ms + int(delay * 1000.0)
		horse["end_ms"] = int(horse["start_ms"]) + int(here.distance_to(to) / speed * 1000.0) + 200
		var args := [horse["id"], here, to, delay, (int(horse["end_ms"]) - int(horse["start_ms"])) / 1000.0, 0.0, int(horse["gait"])]
		for peer in horse["watchers"]:
			out.append([peer, "move", args])


## Para onde a manada vai: ponto de chão livre perto de casa, com caminho
## reto livre; fugindo, o mais longe possível de quem assustou.
func _pick_target(herd: Dictionary, from: Vector2, threat: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_score := -INF
	for attempt in 28:
		var angle := _rng.randf() * TAU
		var dist: float
		if threat != Vector2.INF:
			dist = _rng.randf_range(FLEE_DISTANCE[0], FLEE_DISTANCE[1])
		else:
			dist = _rng.randf_range(HOP[0], HOP[1])
		var point := from + Vector2.from_angle(angle) * dist
		if point.distance_to(herd["home"]) > HOME_RADIUS + (FLEE_DISTANCE[1] if threat != Vector2.INF else 0.0):
			continue
		if not _walkable(point) or not _clear_line(from, point):
			continue
		var score: float
		if threat != Vector2.INF:
			score = point.distance_to(threat)
		else:
			score = _rng.randf() - 0.05 * point.distance_to(herd["home"])
		if score > best_score:
			best_score = score
			best = point
	return best


## Onde cada membro para: pontos de chão livre em volta do alvo.
func _member_spots(target: Vector2, count: int, rng: RandomNumberGenerator) -> Array:
	var spots := []
	for i in count:
		var fallback := Vector2.INF
		for attempt in 16:
			var r := 0.0 if i == 0 else rng.randf_range(APART, SPREAD)
			var point := target + Vector2.from_angle(rng.randf() * TAU) * r
			if not _walkable(point):
				continue
			if fallback == Vector2.INF:
				fallback = point
			var crowded := false
			for other: Vector2 in spots:
				if other.distance_to(point) < APART:
					crowded = true
					break
			if not crowded:
				fallback = point
				break
		if fallback != Vector2.INF:
			spots.append(fallback)
	return spots


func _walkable(point: Vector2) -> bool:
	var cell := WorldGen.cell_of(point)
	return WorldGen.GROUND.has(world.thing_at(cell)) or world.thing_at(cell) == WorldGen.Thing.ARBUSTO


func _clear_line(a: Vector2, b: Vector2) -> bool:
	var steps := ceili(a.distance_to(b) / 0.5)
	for i in range(1, steps + 1):
		var cell := WorldGen.cell_of(a.lerp(b, float(i) / steps))
		if WorldGen.BLOCKING.has(world.thing_at(cell)):
			return false
	return true


func _idle_sounds(horse: Dictionary, now_ms: int, out: Array) -> void:
	if int(horse["next_graze_ms"]) < 0:
		horse["next_graze_ms"] = now_ms + _ms(GRAZE_EVERY, 0.0)
		horse["next_snort_ms"] = now_ms + _ms(SNORT_EVERY, 0.2)
		horse["next_neigh_ms"] = now_ms + _ms(NEIGH_EVERY, 0.3)
		return
	var standing := int(horse["gait"]) == Gait.STAND
	var night := darkness >= 0.6
	if now_ms >= int(horse["next_graze_ms"]):
		horse["next_graze_ms"] = now_ms + _ms(GRAZE_EVERY, 1.0, 1.6 if night else 1.0)
		if standing:
			_sound(horse, "pasto", out)
	if now_ms >= int(horse["next_snort_ms"]):
		horse["next_snort_ms"] = now_ms + _ms(SNORT_EVERY)
		_sound(horse, "bufo", out)
	if now_ms >= int(horse["next_neigh_ms"]):
		horse["next_neigh_ms"] = now_ms + _ms(NEIGH_EVERY)
		if not night:  # de noite, só o alarme
			_sound(horse, "relincho", out)


func _sound(horse: Dictionary, kind: String, out: Array) -> void:
	for peer in horse["watchers"]:
		out.append([peer, "sound", [horse["id"], SOUNDS.find(kind)]])


func _herd_center(herd: Dictionary, now_ms: int) -> Vector2:
	var sum := Vector2.ZERO
	for horse_id in herd["members"]:
		sum += position_of(horses[horse_id], now_ms)
	return sum / herd["members"].size()


func _nearest_member(herd: Dictionary, point: Vector2, now_ms: int) -> float:
	var best := INF
	for horse_id in herd["members"]:
		best = minf(best, position_of(horses[horse_id], now_ms).distance_to(point))
	return best


func _sync_watchers(now_ms: int, players: Dictionary, out: Array) -> void:
	for horse in horses.values():
		var here := position_of(horse, now_ms)
		var watchers: Dictionary = horse["watchers"]
		for peer in watchers.keys():
			if not players.has(peer) or (players[peer] as Vector2).distance_to(here) > HEARING + 4.0:
				watchers.erase(peer)
				if players.has(peer):
					out.append([peer, "gone", [horse["id"]]])
		for peer in players:
			if watchers.has(peer) or (players[peer] as Vector2).distance_to(here) > HEARING:
				continue
			watchers[peer] = true
			out.append([peer, "appear", appear_args(horse, now_ms)])


## [id, tom, pelagem, de, para, segundos até sair, duração, quanto já passou,
## andadura, dono, nome, manada (-1 se domesticado)]. Parado, "de" e "para" são o mesmo ponto; selvagem,
## dono e nome são vazios.
func appear_args(horse: Dictionary, now_ms: int) -> Array:
	var gait := int(horse["gait"])
	if gait == Gait.STAND or now_ms >= int(horse["end_ms"]):
		return [horse["id"], horse["pitch"], horse["coat"], horse["to"], horse["to"], 0.0, 0.0, 0.0, Gait.STAND, horse["owner"], horse["name"], horse["herd"], _rider_key(horse)]
	var duration := (int(horse["end_ms"]) - int(horse["start_ms"])) / 1000.0
	var delay := maxf((int(horse["start_ms"]) - now_ms) / 1000.0, 0.0)
	var elapsed := maxf((now_ms - int(horse["start_ms"])) / 1000.0, 0.0)
	return [horse["id"], horse["pitch"], horse["coat"], horse["from"], horse["to"], delay, duration, elapsed, gait, horse["owner"], horse["name"], horse["herd"], _rider_key(horse)]


func _rider_key(horse: Dictionary) -> String:
	return str(peer_keys.get(int(horse["rider"]), "")) if int(horse["rider"]) >= 0 else ""


static func _chunk_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CHUNK), floori(point.y / CHUNK))


func _ms(span: Array, floor_factor := 1.0, scale := 1.0) -> int:
	return int(_rng.randf_range(span[0] * floor_factor * scale, span[1] * scale) * 1000.0)
