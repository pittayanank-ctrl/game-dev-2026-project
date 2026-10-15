extends Node
## Dev-only automated smoke test, run inside a real build (used to test the web export).
## Started by PerfProbe when the URL has `?start&autotest` (web) or `-- --start --autotest`
## (desktop). Plays through the core loop and prints "TEST ..." lines to the console:
## cutscene, order, delivery, shop, refuel, pause menu, language, save. `verify=N` instead checks
## that the save from a previous run (money = N) was loaded.

var _fails := 0

func _ok(name: String, cond: bool, extra := "") -> void:
	if not cond:
		_fails += 1
	print("TEST %s %s %s" % ["PASS" if cond else "FAIL", name, extra])

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true).timeout

func _accept_key() -> void:
	var e := InputEventAction.new()
	e.action = "ui_accept"
	e.pressed = true
	Input.parse_input_event(e)

func run(main: Node, verify_money: int) -> void:
	var tree := get_tree()
	print("TEST begin platform=%s renderer=%s" % [OS.get_name(), RenderingServer.get_current_rendering_method()])
	if verify_money >= 0:
		_ok("save loaded after page reload", GameState.money == verify_money, "money=%d expected=%d" % [GameState.money, verify_money])
		print("TEST done fails=%d" % _fails)
		return
	await _wait(1.0)
	# 1. Opening cutscene plays and can be skipped.
	var cs := main.get_node("Cutscene")
	_ok("intro cutscene playing", cs.playing)
	for i in 40:
		if not cs.playing:
			break
		_accept_key()
		await _wait(0.1)
	await _wait(0.8)
	_ok("cutscene finished, game running", not cs.playing and not tree.paused)
	# 2. Rider app has offers; take one and deliver it.
	var d := main.get_node("DeliveryManager")
	var bike := main.get_node("Motorcycle")
	await _wait(0.5)
	_ok("rider app offers", d.offers.size() == 3, str(d.offers.size()))
	var money0 := GameState.money
	d.accept_offer(0)
	_ok("order accepted", d.state == d.State.TO_PICKUP)
	bike.global_position = Vector3(d.pickup_pos.x, 0.6, d.pickup_pos.z)
	await _wait(0.4)
	_ok("package picked up", d.state == d.State.TO_DROPOFF)
	for i in 3:
		if d.state != d.State.TO_DROPOFF:
			break
		bike.global_position = Vector3(d.drops[0].x, 0.6, d.drops[0].z)
		await _wait(0.4)
	_ok("delivered and paid", GameState.money > money0, "money %d -> %d" % [money0, GameState.money])
	# A finished chapter plays a cutscene; skip it before riding.
	await _wait(0.6)
	for i in 60:
		if not cs.playing:
			break
		_accept_key()
		await _wait(0.1)
	await _wait(0.8)
	GameState.fuel = GameState.fuel_capacity()
	# 3. Riding: accelerate for a second, the bike should move.
	bike.global_position = Vector3(-3, 0.6, 30)
	bike.global_rotation = Vector3.ZERO
	bike.start_engine()
	await _wait(1.2)
	_ok("engine starts", bike.engine_on)
	Input.action_press("accelerate")
	await _wait(1.5)
	Input.action_release("accelerate")
	_ok("bike accelerates", bike.speed > 5.0, "speed=%.1f" % bike.speed)
	# 4. Shop opens and closes.
	var hud := main.get_node("HUD")
	hud._set_shop_open(true)
	await _wait(0.5)
	_ok("shop opens (game paused)", hud._shop.visible and tree.paused)
	hud._set_shop_open(false)
	await _wait(0.2)
	_ok("shop closes", not hud._shop.visible and not tree.paused)
	# 5. Gas station popup and refuelling.
	var City = load("res://scripts/city.gd")
	GameState.fuel = 0.5
	bike.global_position = City.gas_stations()[0] + Vector3(0, 0.6, 0)
	bike.speed = 0.0
	await _wait(0.3)
	var money1 := GameState.money
	hud._fuel_popup.open()
	await _wait(0.2)
	hud._fuel_popup._fill_button.pressed.emit()
	await _wait(0.3)
	_ok("refuel fills the tank", GameState.fuel >= GameState.fuel_capacity() - 0.01 and GameState.money < money1, "fuel=%.1f" % GameState.fuel)
	hud._fuel_popup.close()
	# 6. Pause menu.
	var pause := main.get_node("PauseMenu")
	pause._open()
	await _wait(0.2)
	_ok("pause menu opens", tree.paused)
	pause._close()
	await _wait(0.2)
	_ok("pause menu closes", not tree.paused)
	# 7. Thai text (bundled font on web).
	Settings.set_language("th")
	_ok("thai translation", tr("Deliver") == "ไปส่ง")
	_ok("font has thai glyphs", UITheme.font.has_char(0x0E01), UITheme.font.get_font_name())
	Settings.set_language("en")
	# 8. Performance after a few seconds of play.
	await _wait(3.0)
	_ok("frame rate", Performance.get_monitor(Performance.TIME_FPS) >= 30, "fps=%d" % Performance.get_monitor(Performance.TIME_FPS))
	# 9. Money cheat keys: "<" = +1,000, ">" = +10,000 (must work in exported builds).
	var before := GameState.money
	for k in [KEY_COMMA, KEY_PERIOD]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.shift_pressed = true
		e.pressed = true
		Input.parse_input_event(e)
		await _wait(0.1)
		var r := e.duplicate()
		r.pressed = false
		Input.parse_input_event(r)
		await _wait(0.1)
	_ok("money cheat < and >", GameState.money - before == 11000, "+%d" % (GameState.money - before))
	GameState.money = before
	# 10. Save to browser storage (checked by reloading the page with verify=money).
	GameState.save_game()
	print("TEST saved money=%d" % GameState.money)
	print("TEST done fails=%d" % _fails)
