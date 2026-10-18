-- Run from the repository root with Lua 4.0:
-- lua tests/collectible_scout_test.lua
-- Mock engine calls; execute the mod itself without changing its Lua dialect.

function CreateObject(className)
	return {Parent = {onEndLevel = function() end}}
end

function fso(name, className)
	return testScout
end

function GetCurrentLevelName()
	return 'MILL'
end

function FindScriptObject(name)
	return {levelType = 'mental'}
end

function GetGameTimeSecs()
	return testTime
end

function IsDead(ent)
	return ent.dead or 0
end

function GetDistance(ax, ay, az, bx, by, bz)
	return sqrt((ax - bx)^2 + (ay - by)^2 + (az - bz)^2)
end

function GetEntityForwardVector(ent)
	return 1, 0, 0
end

function DotProduct(ax, ay, az, bx, by, bz, normalize)
	local length = sqrt(bx^2 + by^2 + bz^2)
	if length == 0 then return 0 end
	return (ax * bx + ay * by + az * bz) / length
end

function pickupBounds(trigger)
	return trigger.x, trigger.y, trigger.z, 10, 20, 30
end

function foreach_entity_oftype(className, callback)
	testScans = testScans + 1
	local i
	for i = 1, getn(testEntities) do
		if testEntities[i].className == className then callback(testEntities[i]) end
	end
end

function DisplayText(text, x, y)
	return {text = text}
end

function RemoveText(handle)
	handle.removed = 1
end

function SetTextPriority() end
function SetMaxViewDistance() end
function SetSimulationCullDistance() end
function SetEntityFlag() end
function SetEntityDomain() end
function GetEntityDomain() return 1 end
function GetRootJointName() return 'rootJ_1' end

function makeFX()
	local fx = {}
	function fx:run() end
	function fx:attach(target, joint) self.attached = target self.joint = joint end
	function fx:detach() self.attached = nil end
	function fx:setPosition(x, y, z) self.x = x self.y = y self.z = z end
	function fx:setScale(scale) self.scale = scale end
	function fx:stop() self.stopped = 1 end
	return fx
end

function makeEntity(name, x, pickupX)
	local ent = {Name = name, x = x, y = 0, z = 0, className = 'global.collectibles.Figment', Type = 'Co_Figment', ID = 1, value = 1}
	function ent:getPosition() return self.x, self.y, self.z end
	if pickupX ~= nil then
		ent.className = 'global.collectibles.SplineFigment'
		ent.Type = 'global.collectibles.SplineFigment'
		ent.ID = nil
		ent.splineFollowing = 1
		ent.trigger = {x = pickupX, y = 0, z = 0}
	end
	return ent
end

function newScout(entities)
	testTime = 0
	testScans = 0
	testEntities = entities
	TriggerOBB_GetAABB = pickupBounds
	Global = {player = makeEntity('Raz', 0), levelScript = {}}
	Global.levelScript.getPool = function(self, name)
		return {get = makeFX}
	end
	testScout = CollectibleScout()
	testScout.timers = {}
	function testScout:createTimer(ms, id) self.timers[id] = testTime + ms / 1000 end
	function testScout:createTimerSecs(seconds, id) self.timers[id] = testTime + seconds end
	function testScout:killTimer(id) self.timers[id] = nil end
	return testScout
end

function advance(seconds)
	local untilTime = testTime + seconds
	while 1 do
		local nextID, nextTime
		local id, due
		for id, due in testScout.timers do
			if due <= untilTime and (nextTime == nil or due < nextTime) then
				nextID = id
				nextTime = due
			end
		end
		if nextID == nil then break end
		testTime = nextTime
		testScout.timers[nextID] = nil
		testScout:onTimer(nextID)
	end
	testTime = untilTime
end

function near(actual, expected)
	assert(actual ~= nil and abs(actual - expected) < 0.01,
		'expected '..tostring(expected)..', got '..tostring(actual))
end

testCount = 0
function test(name, body)
	body()
	testCount = testCount + 1
	print('PASS '..name)
end

dofile('CollectibleScout/Scripts/CollectibleScout.lua')
assert(CollectibleScout ~= nil)

test('nearest selection uses pickup center instead of the stationary origin', function()
	local spline = makeEntity('Moving', 10, 900)
	local nearby = makeEntity('Nearby', 100)
	local scout = newScout({spline, nearby})
	scout:findNearest()
	assert(scout.bestEntity == nearby)
	near(scout.candidates[2].distance, 900)
end)

test('spline marker is placed at the pickup center in world coordinates', function()
	local spline = makeEntity('Moving', 900, 50)
	local scout = newScout({spline})
	scout:updateOnce()
	near(scout.bestDistance, 50)
	near(scout.highlightFX.x, 50)
	near(scout.highlightFX.y, scout.highlightOffsetY)
	assert(scout.highlightFX.attached == nil)
	assert(scout.lastHudText == 'Figment 50 ahead')
	assert(strfind(scout:getPositionText(spline), 'pos=%(50, 0, 0%)') ~= nil)
end)

test('ordinary figments retain entity positioning and joint attachment', function()
	local ent = makeEntity('Static', 250)
	ent.splineFollowing = 1 -- Also present on normal Figment objects in the game.
	local scout = newScout({ent})
	scout:updateOnce()
	near(scout.bestDistance, 250)
	assert(scout.highlightFX.attached == ent)
	assert(scout.highlightFX.joint == 'rootJ_1')
end)

test('missing pickup API or trigger falls back to entity positioning', function()
	local ent = makeEntity('Moving', 250, 999)
	local scout = newScout({ent})
	TriggerOBB_GetAABB = nil
	scout:findNearest()
	near(scout.bestDistance, 250)
	TriggerOBB_GetAABB = pickupBounds
	ent.trigger = nil
	scout:findNearest()
	near(scout.bestDistance, 250)
end)

test('incomplete pickup coordinates fall back safely', function()
	local ent = makeEntity('Moving', 250, 999)
	ent.trigger.y = nil
	local scout = newScout({ent})
	scout:findNearest()
	near(scout.bestDistance, 250)
end)

test('dead, collected and script-hidden entities never become candidates', function()
	local dead = makeEntity('Dead', 1) dead.dead = 1
	local collected = makeEntity('Collected', 2) collected.bCollected = 1
	local hidden = makeEntity('Hidden spline', 3, 3) hidden.bHide = 1
	local scriptHidden = makeEntity('Hidden static', 4) scriptHidden.bSBHidden = 1
	local live = makeEntity('Live', 250)
	local scout = newScout({dead, collected, hidden, scriptHidden, live})
	scout:findNearest()
	assert(getn(scout.candidates) == 1)
	assert(scout.bestEntity == live)
end)

test('uninitialized placed figments do not produce unreachable wall markers', function()
	local placed = makeEntity('Fig6', 10)
	placed.ID = nil
	placed.value = nil
	placed.splineFollowing = 1
	local live = makeEntity('Thawed pickup', 100)
	local scout = newScout({placed, live})
	scout:updateOnce()
	assert(getn(scout.candidates) == 1 and scout.bestEntity == live)
	placed.ID = 0
	scout:findNearest()
	assert(getn(scout.candidates) == 1 and scout.bestEntity == live)
end)

test('initialized figments stay eligible even with the default point value', function()
	local live = makeEntity('Thawed pickup', 100)
	live.value = nil
	local scout = newScout({live})
	scout:findNearest()
	assert(scout.bestEntity == live)
end)

test('cached figments that lose their pickup ID are no longer selected', function()
	local first = makeEntity('First', 50)
	local second = makeEntity('Second', 100)
	local scout = newScout({first, second})
	scout:updateOnce()
	first.ID = nil
	advance(0.2)
	assert(scout.bestEntity == second)
	scout:skipCurrentTarget()
	assert(scout.bestEntity == second)
end)

test('a figment becomes available after its normal pickup initialization', function()
	local placed = makeEntity('Waiting to thaw', 100)
	placed.ID = nil
	local scout = newScout({placed})
	scout:updateOnce()
	assert(scout.bestEntity == nil)
	placed.ID = 7
	advance(1)
	assert(scout.bestEntity == placed)
end)

test('timer refresh follows a moving pickup without rebuilding its effect', function()
	local ent = makeEntity('Moving', 900, 100)
	local scout = newScout({ent})
	scout:updateOnce()
	local fx = scout.highlightFX
	ent.trigger.x = -250
	ent.trigger.y = 300
	advance(0.2)
	near(scout.bestX, -250)
	near(scout.bestY, 300)
	near(scout.bestDistance, sqrt(250^2 + 300^2))
	assert(scout.highlightFX == fx)
	near(fx.x, -250)
	near(fx.y, 300 + scout.highlightOffsetY)
	assert(strfind(scout.lastHudText, 'behind above') ~= nil)
end)

test('cached nearest selection rechecks live pickup positions', function()
	local spline = makeEntity('Moving', 10, 300)
	local nearby = makeEntity('Nearby', 100)
	local scout = newScout({spline, nearby})
	scout:updateOnce()
	assert(scout.bestEntity == nearby)
	spline.trigger.x = 50
	advance(0.2)
	assert(scout.bestEntity == spline)
	near(scout.bestDistance, 50)
end)

test('target switching orders spline candidates by their pickup positions', function()
	local spline = makeEntity('Moving', 10, 300)
	local nearest = makeEntity('Nearest', 100)
	local middle = makeEntity('Middle', 200)
	local scout = newScout({spline, nearest, middle})
	scout:updateOnce()
	scout:skipCurrentTarget()
	assert(scout.bestEntity == middle)
	scout:skipCurrentTarget()
	assert(scout.bestEntity == spline)
	near(scout.bestDistance, 300)
end)

test('manual selection keeps following its moving target', function()
	local spline = makeEntity('Moving', 10, 300)
	local nearest = makeEntity('Nearest', 100)
	local scout = newScout({spline, nearest})
	scout:updateOnce()
	scout:skipCurrentTarget()
	spline.trigger.x = 500
	advance(0.2)
	assert(scout.bestEntity == spline)
	near(scout.bestDistance, 500)
	near(scout.highlightFX.x, 500)
end)

test('a collected manual target is replaced before its death animation ends', function()
	local spline = makeEntity('Moving', 10, 300)
	local nearest = makeEntity('Nearest', 100)
	local scout = newScout({spline, nearest})
	scout:updateOnce()
	scout:skipCurrentTarget()
	spline.bCollected = 1
	advance(0.2)
	assert(scout.bestEntity == nearest)
	assert(scout.manualTargetOverride == 0)
end)

test('a target hidden after scanning is removed from cached selection', function()
	local spline = makeEntity('Moving', 10, 50)
	local nearest = makeEntity('Nearest', 100)
	local scout = newScout({spline, nearest})
	scout:updateOnce()
	spline.bHide = 1
	advance(0.2)
	assert(scout.bestEntity == nearest)
end)

test('HUD refresh cannot extend the five second display or revive it later', function()
	local scout = newScout({makeEntity('Moving', 900, 100)})
	scout:updateOnce()
	local fx = scout.highlightFX
	advance(5.1)
	assert(scout.hudHandle == nil and scout.highlightFX == nil)
	assert(scout.visualsUntil == nil and scout.timers[scout.TIMER_REFRESH] == nil)
	assert(fx.stopped == 1)
	scout:refreshSelectedHud()
	assert(scout.hudHandle == nil and scout.highlightFX == nil)
end)

test('a repeated scan gets a fresh five second display window', function()
	local scout = newScout({makeEntity('Moving', 900, 100)})
	scout:updateOnce()
	advance(4)
	scout:updateOnce()
	advance(1.2)
	assert(scout.hudHandle ~= nil and scout.highlightFX ~= nil)
	advance(4)
	assert(scout.hudHandle == nil and scout.highlightFX == nil)
end)

test('the no-target watch finds newly loaded figments and still expires', function()
	local scout = newScout({})
	scout:updateOnce()
	assert(scout.lastHudText == 'Scout: none')
	testEntities = {makeEntity('Newly loaded', 900, 100)}
	advance(1)
	assert(scout.bestEntity == testEntities[1])
	near(scout.bestDistance, 100)
	advance(4.1)
	assert(scout.hudHandle == nil and scout.highlightFX == nil)
end)

test('level exit cancels pending refreshes and removes temporary visuals', function()
	local scout = newScout({makeEntity('Moving', 900, 100)})
	scout:updateOnce()
	scout:onEndLevel()
	advance(6)
	assert(scout.hudHandle == nil and scout.highlightFX == nil)
	assert(scout.timers[scout.TIMER_REFRESH] == nil)
	assert(scout.visualsUntil == nil)
end)

test('continuous tracking still accepts refreshes from patched Astralathe', function()
	local ent = makeEntity('Moving', 900, 100)
	local scout = newScout({ent})
	scout:startTracker()
	ent.trigger.x = 500
	scout:refreshSelectedHud()
	near(scout.bestDistance, 500)
	near(scout.highlightFX.x, 500)
	scout:stopTracker()
	assert(scout.timers[scout.TIMER_TRACKER] == nil)
end)

print(testCount..' tests passed')
