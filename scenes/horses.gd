extends Node
## Os cavalinhos-da-bruma na rede. Existe igual no servidor e nos clientes
## (/root/Game/Horses), porque é por ele que passam as chamadas de rede.
##
## No servidor, roda a simulação (Herd) e manda a cada jogador só o que
## acontece perto dele. No cliente, guarda onde cada cavalo está, toca os
## cascos enquanto ele anda (o som muda com o chão) e os bufos, relinchos e
## mastigadas no lugar certo, com HRTF quando houver. As fontes são fixas e
## reaproveitadas (o Steam Audio às vezes não pega fontes criadas na hora).

const STEP_SECONDS := 0.25
const VOICES := 16
const REACH := Herd.HEARING
const STEP_REACH := 22.0  # casas: mais longe que isso, os cascos não tocam
## Cadência dos cascos. Andando, quatro pisadas por passada, com balanço
## longo-curto (segundos entre uma e outra); galopando, uma passada inteira
## (as quatro batidas, o corpo e o fôlego já vêm no arquivo) a cada
## GALLOP_STRIDE. O andamento flutua devagar, sem passar dos limites, para não
## soar como metrônomo nem correr ou arrastar demais.
const WALK_GAPS := [0.26, 0.24, 0.26, 0.24]
const WALK_TEMPO := [0.9, 1.1]
const GALLOP_STRIDE := 0.55  # era 0,42: as passadas emendavam umas nas outras
## Galopando, a manada vai no mesmo compasso (cada cavalo até GALLOP_SPREAD
## segundos atrás da batida comum), e só os GALLOP_HEARD mais perto soam
## cheios; os outros ficam GALLOP_BACK_DB mais baixos, de fundo. Fora de fase,
## as passadas de todos viravam uma maçaroca contínua.
const GALLOP_SPREAD := 0.06
const GALLOP_HEARD := 2
const GALLOP_BACK_DB := -8.0
const GALLOP_TEMPO := [0.93, 1.08]
## Bufadas de vez em quando enquanto andam ou galopam (segundos).
const WALK_SNORTS := [4.0, 8.0]
const GALLOP_SNORTS := [2.5, 5.0]
## Volume de cada som. Tudo bem baixinho, como o resto do mundo. Os cascos
## gravados estão 14 dB abaixo nos arquivos (para caber o pico sem distorcer).
## No jogo, o Gabs achou tudo alto, o galope principalmente: o geral desceu
## 6 dB, os cascos mais 4 e o galope mais 8.
const HORSES_DB := -16.0
const SOUND_DB := {"casco": 0.0, "galope": -4.0, "casco_gerado": -14.0, "galope_gerado": -10.0, "pasto": -18.0, "bufo": -10.0, "manso": -10.0, "relincho": -6.0, "alarme": -4.0}
const HEAD_HEIGHT := 1.3  # metros: de onde saem bufo e relincho
const HOOF_HEIGHT := 0.1
## Força do panorama estéreo nas fontes dos cavalos (ver set_wide). Medido
## no PC do Gabs: com 1 (padrão), um som bem do lado fica só 6 dB mais alto
## naquele ouvido; com 2, fica só nele. Acima de 2 o resultado não é
## confiável (3 voltou a 6 dB, 4 deu 0), então não subir sem medir.
const WIDE_PANNING := 2.0

var herd: Herd  # só no servidor
var _step := 0.0

var _audio: SpatialAudio
var _world: WorldGen
var _horses := {}  # id -> { pitch, coat, from: Vector2, to: Vector2, start, duration, gait, next_step, beat, drift, next_snort, last_hoof }
var _voices := []  # [{ player, horse, height, started }]
var _clock := 0.0
## Cascos e vozes com panorama largo. Pelo Steam Audio do jeito que está, o
## lado vinha só do panorama fraco do Godot: nada soava bem à esquerda.
var wide := true
var _gallop_next := 0.0  # próxima batida comum do galope
var _gallop_drift := 0.0


## "tame": os domesticados salvos no mundo (Herd.tame_to_save).
func start_server(world: WorldGen, tame: Array = []) -> void:
	herd = Herd.new(world)
	herd.load_tame(tame)


## Os domesticados, para salvar (vazio fora do servidor).
func tame_to_save() -> Array:
	return herd.tame_to_save() if herd != null else []


func start_client(audio: SpatialAudio, world: WorldGen) -> void:
	_audio = audio
	_world = world
	if _voices.is_empty():
		_make_voices()


## Troca entre o panorama largo e o HRTF (depuração, para comparar).
func set_wide(on: bool) -> void:
	wide = on
	for voice in _voices:
		(voice["player"] as Node).queue_free()
	_voices.clear()
	_make_voices()


func _make_voices() -> void:
	if _audio == null:
		return
	for i in VOICES:
		# Sempre a mesma fonte de antes (que soa); só o panorama muda.
		var player := _audio.make_far_voice(REACH)
		if player == null:
			return
		player.name = "Cavalo_%d" % i
		player.panning_strength = WIDE_PANNING if wide else 1.0
		_voices.append({"player": player, "horse": -1, "height": 0.0, "started": 0.0, "hrtf": _audio.using_hrtf})


func forget_peer(peer: int) -> void:
	if herd != null:
		herd.forget_peer(peer)


## Barulho forte num ponto (casas): espanta as manadas por perto.
func hear_noise(point: Vector2) -> void:
	if herd != null:
		herd.hear_noise(point)


func _process(delta: float) -> void:
	_clock += delta
	if herd != null:
		_step += delta
		if _step >= STEP_SECONDS:
			_step = 0.0
			_server_step()
	_client_steps()
	_follow()


# --- Servidor ------------------------------------------------------------------

func _server_step() -> void:
	var game := get_parent()
	if game.state == null:
		return
	var positions := {}
	herd.peer_keys.clear()
	for id in game.state.players:
		positions[id] = game.state.players[id]["pos"]
		herd.peer_keys[id] = game.state.owner_key(id)
	herd.darkness = game.daytime.darkness()
	if game.horrors.horrors != null:
		herd.hush = game.horrors.horrors.points()
	for message in herd.update(Time.get_ticks_msec(), positions):
		var peer: int = message[0]
		var args: Array = message[2]
		match message[1]:
			"appear":
				horse_appeared.rpc_id(peer, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10])
			"gone":
				horse_gone.rpc_id(peer, args[0])
			"move":
				horse_moved.rpc_id(peer, args[0], args[1], args[2], args[3], args[4], args[5], args[6])
			"sound":
				horse_sounded.rpc_id(peer, args[0], args[1])
			"named":
				horse_named.rpc_id(peer, args[0], args[1], args[2])
			"tamed":
				game._dirty = true
				horse_tamed.rpc_id(peer, args[0])


# --- Domesticar (pedidos dos clientes, no servidor) -----------------------------

## Espaço num cavalo selvagem: oferece uma fruta da bolsa.
@rpc("any_peer", "call_local", "reliable")
func request_offer(horse_id: int) -> void:
	if not multiplayer.is_server() or herd == null:
		return
	var game := get_parent()
	var id: int = game._sender_id()
	if not game.state.players.has(id):
		return
	if int(game.state.inventory_of(id).get("frutas", 0)) <= 0:
		offer_result.rpc_id(id, "sem_frutas")
		return
	herd.peer_keys[id] = game.state.owner_key(id)
	var result := herd.offer(id, horse_id, Time.get_ticks_msec(), game.state.players[id]["pos"])
	if result["ok"]:
		game.state.give_away(id, "frutas")
		game._dirty = true
		game.inventory_changed.rpc_id(id, game.state.inventory_of(id), "", "")
	offer_result.rpc_id(id, str(result["reason"]))


## O dono escolhe o nome do seu cavalo (um de Herd.NAMES).
@rpc("any_peer", "call_local", "reliable")
func request_name(horse_id: int, new_name: String) -> void:
	if not multiplayer.is_server() or herd == null:
		return
	var game := get_parent()
	var id: int = game._sender_id()
	if not game.state.players.has(id):
		return
	herd.peer_keys[id] = game.state.owner_key(id)
	if herd.rename(id, horse_id, new_name):
		game._dirty = true
		named_result.rpc_id(id, new_name)


## Depuração: domestica o cavalo selvagem mais perto de quem pediu.
func debug_tame(id: int, point: Vector2) -> int:
	if herd == null:
		return -1
	var game := get_parent()
	herd.peer_keys[id] = game.state.owner_key(id)
	# O aviso "tamed" sai no próximo passo, como no jeito normal.
	return herd.debug_tame(id, point, Time.get_ticks_msec())


# --- Avisos do servidor (executados nos clientes) ------------------------------

@rpc("authority", "call_local", "reliable")
func horse_appeared(id: int, pitch: float, coat: int, from: Vector2, to: Vector2, delay: float, duration: float, elapsed: float, gait: int, owner: String, horse_name: String) -> void:
	_horses[id] = {
		"pitch": pitch, "coat": coat, "from": from, "to": to, "owner": owner, "name": horse_name,
		"start": _clock + delay - elapsed, "duration": duration, "gait": gait,
		"next_step": _clock + randf() * 0.5, "beat": 0, "drift": 0.0,
		"next_snort": _clock + _snort_gap(gait) * 0.5, "last_hoof": null,
	}


@rpc("authority", "call_local", "reliable")
func horse_gone(id: int) -> void:
	_horses.erase(id)
	for voice in _voices:
		if voice["horse"] == id:
			voice["horse"] = -1


@rpc("authority", "call_local", "reliable")
func horse_moved(id: int, from: Vector2, to: Vector2, delay: float, duration: float, elapsed: float, gait: int) -> void:
	if not _horses.has(id):
		return
	var horse: Dictionary = _horses[id]
	horse["from"] = from
	horse["to"] = to
	horse["start"] = _clock + delay - elapsed
	horse["duration"] = duration
	horse["gait"] = gait
	horse["next_step"] = INF if gait == Herd.Gait.GALLOP else maxf(float(horse["start"]), _clock)
	horse["beat"] = 0
	horse["next_snort"] = maxf(float(horse["start"]), _clock) + _snort_gap(gait) * 0.5


@rpc("authority", "call_local", "reliable")
func horse_sounded(id: int, kind: int) -> void:
	if not _horses.has(id) or kind < 0 or kind >= Herd.SOUNDS.size():
		return
	var sound_name: String = Herd.SOUNDS[kind]
	if not Net.auto_commands.is_empty():
		print("[teste] cavalo: %s a %.0f casas" % [sound_name, horse_point(id).distance_to(get_parent()._pos)])
	_play(id, HorseSounds.voice(sound_name), SOUND_DB[sound_name], float(_horses[id]["pitch"]), HEAD_HEIGHT)


@rpc("authority", "call_local", "reliable")
func horse_named(id: int, owner: String, horse_name: String) -> void:
	if _horses.has(id):
		_horses[id]["owner"] = owner
		_horses[id]["name"] = horse_name


## Respostas do servidor ao Espaço num cavalo (ver Herd.offer).
const OFFER_TEXT := {
	"comeu": "Ele come a fruta da sua mão.",
	"pronto": "Ele come e fica junto de você. Fique quieto.",
	"desconfia": "Ele ainda desconfia. Espere parado perto da manada.",
	"longe": "Chegue mais perto do cavalo.",
	"mastigando": "Ele ainda está mastigando.",
	"sem_frutas": "Você não tem frutas.",
	"domado": "Esse cavalo já tem dono.",
	"sumiu": "",
}


@rpc("authority", "call_local", "reliable")
func offer_result(reason: String) -> void:
	if not Net.auto_commands.is_empty():
		print("[teste] oferta: %s" % reason)
	var text: String = OFFER_TEXT.get(reason, "")
	if not text.is_empty():
		Speech.say(text)


## O cavalo virou seu: avisa e abre a escolha do nome.
@rpc("authority", "call_local", "reliable")
func horse_tamed(id: int) -> void:
	if not Net.auto_commands.is_empty():
		print("[teste] cavalo domesticado: %d" % id)
	if _horses.has(id):
		_horses[id]["owner"] = get_parent().my_owner_key()
		_play(id, HorseSounds.voice("manso"), SOUND_DB["manso"], float(_horses[id]["pitch"]), HEAD_HEIGHT)
	Speech.say("O cavalo encosta o focinho em você. Agora ele é seu. " + get_parent().open_menu("Nome do cavalo", name_items.bind(id, 0)))


@rpc("authority", "call_local", "reliable")
func named_result(horse_name: String) -> void:
	Speech.say("Seu cavalo se chama %s." % horse_name)


## A lista de nomes para o cavalo "id" (página "page"), mais "Outros nomes".
func name_items(id: int, page: int) -> Array:
	var items := []
	for choice: String in Herd.name_choices(id, page):
		items.append({"label": choice, "run": _ask_name.bind(id, choice), "close": true})
	items.append({"label": "Outros nomes", "open": name_items.bind(id, page + 1)})
	return items


func _ask_name(id: int, choice: String) -> String:
	request_name.rpc_id(1, id, choice)
	return ""


## O cavalo ao alcance do Espaço (Herd.OFFER_REACH), o mais perto, ou -1.
func reach_target(me: Vector2) -> int:
	var best := -1
	var best_d := Herd.OFFER_REACH
	for id: int in _horses:
		var d := horse_point(id).distance_to(me)
		if d <= best_d:
			best_d = d
			best = id
	return best


## Espaço num cavalo: selvagem, oferece fruta; seu e sem nome, escolhe o nome;
## seu, diz o nome; de outro, diz de quem é.
func interact(id: int) -> String:
	var horse: Dictionary = _horses[id]
	var owner: String = horse["owner"]
	if owner.is_empty():
		request_offer.rpc_id(1, id)
		return ""
	var horse_name: String = horse["name"]
	if owner == get_parent().my_owner_key():
		if horse_name.is_empty():
			return get_parent().open_menu("Nome do cavalo", name_items.bind(id, 0))
		return "%s, seu cavalo." % horse_name
	return "%s, cavalo de %s." % [horse_name, owner] if not horse_name.is_empty() else "Cavalo de %s." % owner


## Distância (casas) até o cavalo ao alcance, ou INF.
func reach_distance(id: int, me: Vector2) -> float:
	return INF if id < 0 or not _horses.has(id) else horse_point(id).distance_to(me)


# --- Posição e som -------------------------------------------------------------

## Onde o cavalo está agora, em casas.
func horse_point(id: int) -> Vector2:
	var horse: Dictionary = _horses[id]
	var duration: float = horse["duration"]
	if duration <= 0.0:
		return horse["to"]
	var x := clampf((_clock - float(horse["start"])) / duration, 0.0, 1.0)
	return (horse["from"] as Vector2).lerp(horse["to"], x)


## O cavalo está andando (ou galopando) agora? Devolve a andadura (Herd.Gait).
func horse_gait(id: int) -> int:
	if not _horses.has(id):
		return Herd.Gait.STAND
	var horse: Dictionary = _horses[id]
	var x := (_clock - float(horse["start"])) / maxf(0.001, float(horse["duration"]))
	return int(horse["gait"]) if x > 0.0 and x < 1.0 else Herd.Gait.STAND


## Os cavalos conhecidos (id -> pelagem), para a vista 3D.
func horse_coats() -> Dictionary:
	var out := {}
	for id: int in _horses:
		out[id] = int(_horses[id]["coat"])
	return out


## Para onde o cavalo anda (casas), para virar o corpo na vista 3D.
func horse_heading(id: int) -> Vector2:
	var horse: Dictionary = _horses[id]
	return (horse["to"] as Vector2) - (horse["from"] as Vector2)


func horse_count() -> int:
	return _horses.size()


## Toca os cascos de quem está andando, no ritmo da andadura, e uma bufada
## de vez em quando.
func _client_steps() -> void:
	if _voices.is_empty():
		return
	var me: Vector2 = get_parent()._pos
	var heard := _nearest_galloping(me)
	_gallop_clock()
	for id: int in _horses:
		var gait := horse_gait(id)
		if gait == Herd.Gait.STAND:
			continue
		var horse: Dictionary = _horses[id]
		if _clock < float(horse["next_step"]):
			continue
		var gallop := gait == Herd.Gait.GALLOP
		# Galopando, quem marca a próxima passada é o compasso comum.
		horse["next_step"] = INF if gallop else _clock + _next_gap(horse, false)
		var point := horse_point(id)
		if point.distance_to(me) > STEP_REACH:
			continue
		var surface := _surface_at(point)
		var recorded := HorseSounds.has_hooves(surface)
		var kind := ("galope" if gallop else "casco") + ("" if recorded else "_gerado")
		var stream := HorseSounds.hoof(surface, gallop, horse["last_hoof"])
		horse["last_hoof"] = stream
		# Cascos gravados: só um tiquinho do tom do cavalo, senão muda o ritmo.
		var pitch := (1.0 + (float(horse["pitch"]) - 1.0) * 0.3) * randf_range(0.98, 1.02) if recorded else float(horse["pitch"]) * randf_range(0.95, 1.05)
		var jitter := randf_range(-1.0, 1.0) if gallop else randf_range(-3.0, 1.5)
		if gallop and not heard.has(id):
			jitter += GALLOP_BACK_DB
		_play(id, stream, SOUND_DB[kind] + jitter, pitch, HOOF_HEIGHT)
		if _clock >= float(horse["next_snort"]):
			horse["next_snort"] = _clock + _snort_gap(gait)
			_play(id, HorseSounds.voice("bufo"), SOUND_DB["bufo"] + (1.0 if gallop else 0.0), float(horse["pitch"]), HEAD_HEIGHT)


## A batida comum do galope: quando chega, marca a passada de cada cavalo
## galopando, com um atraso pequeno e fixo de cada um.
func _gallop_clock() -> void:
	if _clock < _gallop_next:
		return
	_gallop_drift = (_gallop_drift + randfn(0.0, 0.03)) * 0.9
	var tempo := clampf(1.0 + _gallop_drift, GALLOP_TEMPO[0], GALLOP_TEMPO[1])
	var beat := maxf(_gallop_next, _clock)
	_gallop_next = beat + GALLOP_STRIDE * tempo + randfn(0.0, 0.01)
	for id: int in _horses:
		if horse_gait(id) == Herd.Gait.GALLOP:
			_horses[id]["next_step"] = beat + float(posmod(id * 37, 7)) / 6.0 * GALLOP_SPREAD


## Os ids dos GALLOP_HEARD cavalos galopando mais perto de "me".
func _nearest_galloping(me: Vector2) -> Array:
	var near := []
	for id: int in _horses:
		if horse_gait(id) == Herd.Gait.GALLOP:
			near.append([horse_point(id).distance_squared_to(me), id])
	near.sort()
	var ids := []
	for i in mini(GALLOP_HEARD, near.size()):
		ids.append(near[i][1])
	return ids


## Quanto falta para a próxima pisada (andando) ou passada (galopando).
func _next_gap(horse: Dictionary, gallop: bool) -> float:
	var drift := (float(horse["drift"]) + randfn(0.0, 0.03)) * 0.9
	horse["drift"] = drift
	if gallop:
		var tempo := clampf(1.0 + drift, GALLOP_TEMPO[0], GALLOP_TEMPO[1])
		return GALLOP_STRIDE * tempo + randfn(0.0, 0.01)
	var beat: int = horse["beat"]
	horse["beat"] = beat + 1
	var walk_tempo := clampf(1.0 + drift, WALK_TEMPO[0], WALK_TEMPO[1])
	return maxf(0.08, float(WALK_GAPS[beat % WALK_GAPS.size()]) * walk_tempo + randfn(0.0, 0.03))


func _snort_gap(gait: int) -> float:
	var span: Array = GALLOP_SNORTS if gait == Herd.Gait.GALLOP else WALK_SNORTS
	return randf_range(span[0], span[1])


func _surface_at(point: Vector2) -> String:
	if _world == null:
		return "grama"
	var cell := WorldGen.cell_of(point)
	match _world.thing_at(cell):
		WorldGen.Thing.PONTE:
			return "madeira"
		WorldGen.Thing.TRILHA:
			return "terra"
		WorldGen.Thing.VAU, WorldGen.Thing.RIACHO:
			return "agua"
	if WorldGen.COLD_BIOMES.has(_world.biome_at(cell)):
		return "neve"
	return "grama"


func _play(id: int, stream: AudioStream, volume_db: float, pitch: float, height: float) -> void:
	if stream == null or _voices.is_empty():
		return
	var voice: Dictionary = _free_voice()
	var player: AudioStreamPlayer3D = voice["player"]
	voice["horse"] = id
	voice["height"] = height
	player.stop()
	player.stream = stream
	player.volume_db = volume_db + HORSES_DB + (SpatialAudio.HRTF_GAIN_DB if voice["hrtf"] else 0.0)
	player.pitch_scale = pitch
	player.position = _to_3d(horse_point(id), height)
	player.play()
	voice["started"] = _clock


func _free_voice() -> Dictionary:
	var oldest: Dictionary = _voices[0]
	for voice in _voices:
		if not (voice["player"] as AudioStreamPlayer3D).playing:
			return voice
		if float(voice["started"]) < float(oldest["started"]):
			oldest = voice
	return oldest


func _follow() -> void:
	for voice in _voices:
		var id: int = voice["horse"]
		if id < 0 or not _horses.has(id):
			continue
		var player: AudioStreamPlayer3D = voice["player"]
		if player.playing:
			player.position = _to_3d(horse_point(id), float(voice["height"]))
		else:
			voice["horse"] = -1


static func _to_3d(point: Vector2, height: float) -> Vector3:
	return Vector3(point.x * WorldGen.METERS_PER_CELL, height, point.y * WorldGen.METERS_PER_CELL)
