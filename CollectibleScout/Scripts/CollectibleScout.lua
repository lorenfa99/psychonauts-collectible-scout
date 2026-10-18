function CollectibleScout_RecordEntity(ent)
	local scout = fso('CollectibleScout', 'CollectibleScout')
	if scout ~= nil then
		scout:recordEntity(ent)
	end
end

function CollectibleScout_RecordCandidate(ent)
	local scout = fso('CollectibleScout', 'CollectibleScout')
	if scout ~= nil then
		scout:recordCandidate(ent)
	end
end

function CollectibleScout(Ob)
	if ( not Ob ) then
		Ob = CreateObject('ScriptBase')
	end

	Ob.outputFolder = 'CollectibleScout'
	Ob.lastReportPath = 'CollectibleScout/last_scan.txt'
	Ob.historyPath = 'CollectibleScout/scan_history.txt'
	Ob.detailLimit = 80
	Ob.TIMER_HIDE_TEXT = 'CollectibleScoutHideText'
	Ob.TIMER_HIDE_HUD = 'CollectibleScoutHideHud'
	Ob.TIMER_CLEAR_HIGHLIGHT = 'CollectibleScoutClearHighlight'
	Ob.TIMER_TRACKER = '15950'
	Ob.TIMER_REFRESH = '15951'
	Ob.lines = {}
	Ob.totalLoaded = 0
	Ob.currentLabel = ''
	Ob.currentCount = 0
	Ob.currentLines = {}
	Ob.overlayText = nil
	Ob.hudHandle = nil
	Ob.lastHudText = nil
	Ob.hudDisplaySecs = 5
	Ob.highlightDisplaySecs = 5
	Ob.refreshInterval = 100
	Ob.visualsUntil = nil
	Ob.trackerActive = 0
	Ob.trackerInterval = 1500
	Ob.noTargetRetrySecs = 0.75
	Ob.noTargetWatchSecs = 5
	Ob.noTargetWatchUntil = nil
	Ob.nextNoTargetScanAt = nil
	Ob.bestEntity = nil
	Ob.bestLabel = nil
	Ob.bestShortLabel = nil
	Ob.bestName = nil
	Ob.bestDistance = nil
	Ob.bestX = nil
	Ob.bestY = nil
	Ob.bestZ = nil
	Ob.candidates = {}
	Ob.manualTargetOverride = 0
	Ob.lastScanTime = nil
	Ob.lastSelectedDistance = nil
	Ob.cycleWindowSecs = 5
	Ob.highlightFX = nil
	Ob.highlightBeaconEmitter = nil
	Ob.highlightSparkEmitter = nil
	Ob.highlightTarget = nil
	Ob.highlightOffsetY = 120
	Ob.usePostEffectHighlight = 1
	Ob.playerX = nil
	Ob.playerY = nil
	Ob.playerZ = nil

	Ob.scanTypes = {
		{label = 'PSI challenge cards', shortLabel = 'Card', className = 'global.collectibles.PSIChallengeCard'},
		{label = 'PSI challenge markers', shortLabel = 'Marker', className = 'global.collectibles.PsiChallengeMarker'},
		{label = 'PSI challenge cores', shortLabel = 'Core', className = 'global.collectibles.PSIChallengeCore'},
		{label = 'Scavenger hunt items', shortLabel = 'Scav', className = 'ca.props.ScavengerHuntItem'},
		{label = 'Brain jars', shortLabel = 'Brain', className = 'global.collectibles.BrainJar'},
		{label = 'Mental cobwebs', shortLabel = 'Web', className = 'global.collectibles.Cobweb'},
		{label = 'Figments', shortLabel = 'Figment', className = 'global.collectibles.Figment'},
		{label = 'Spline figments', shortLabel = 'Figment', className = 'global.collectibles.SplineFigment'},
		{label = 'Emotional baggage', shortLabel = 'Bag', className = 'global.collectibles.EmotionalBaggage'},
		{label = 'Baggage tags', shortLabel = 'Tag', className = 'global.collectibles.EmotionalBaggageTag'},
		{label = 'Memory vaults', shortLabel = 'Vault', className = 'global.characters.Vault'},
		{label = 'Max lives upgrades', shortLabel = 'Life', className = 'global.collectibles.MaxLivesUp'},
		{label = 'Max ammo upgrades', shortLabel = 'Ammo', className = 'global.collectibles.MaxAmmoUp'},
		{label = 'Psi powers', shortLabel = 'Power', className = 'global.collectibles.PsiPower'},
	}

	function Ob:onBeginLevel()
		%Ob.Parent.onBeginLevel(self)
	end

	function Ob:onEndLevel()
		self:stopTracker()
		%Ob.Parent.onEndLevel(self)
	end

	function Ob:onTimer(id)
		if id == self.TIMER_TRACKER then
			self:killTimer(id)
			self:trackerTick()
			if self.trackerActive == 1 then
				self:createTimer(self.trackerInterval, self.TIMER_TRACKER)
			end
		elseif id == self.TIMER_HIDE_TEXT then
			self:hideOverlay()
		elseif id == self.TIMER_HIDE_HUD then
			self:clearHud()
		elseif id == self.TIMER_CLEAR_HIGHLIGHT then
			self:clearTemporaryVisuals()
		elseif id == self.TIMER_REFRESH then
			self:killTimer(id)
			self:refreshSelectedHud()
			if self.visualsUntil ~= nil then
				self:createTimer(self.refreshInterval, self.TIMER_REFRESH)
			end
		else
			%Ob.Parent.onTimer(self, id)
		end
	end

	function Ob:addLine(text)
		tinsert(self.lines, text)
	end

	function Ob:numberText(value)
		if value == nil then
			return 'nil'
		end
		if format ~= nil then
			return format('%.0f', value)
		end
		return tostring(value)
	end

	function Ob:distanceText(value)
		if value == nil then
			return 'nil'
		end
		return self:numberText(floor((value + 25) / 50) * 50)
	end

	function Ob:valueText(value)
		if value == nil then
			return 'nil'
		end
		return tostring(value)
	end

	function Ob:getLevelName()
		if Global ~= nil and Global.levelScript ~= nil and Global.levelScript.getLevelName ~= nil then
			return Global.levelScript:getLevelName()
		end
		return GetCurrentLevelName()
	end

	function Ob:getLevelPrefix()
		if Global ~= nil and Global.levelScript ~= nil and Global.levelScript.getLevelPrefix ~= nil then
			return Global.levelScript:getLevelPrefix()
		end
		local level = self:getLevelName()
		if level ~= nil then
			return strsub(level, 1, 2)
		end
		return '??'
	end

	function Ob:getLevelType()
		local levelScript = FindScriptObject('LevelScript')
		if levelScript ~= nil and levelScript.levelType ~= nil then
			return levelScript.levelType
		end
		return 'unknown'
	end

	function Ob:getScriptType()
		local levelScript = FindScriptObject('LevelScript')
		if levelScript ~= nil and levelScript.Type ~= nil then
			return levelScript.Type
		end
		return 'unknown'
	end

	function Ob:shouldScanType(scanType)
		local className = scanType.className
		local prefix = self:getLevelPrefix()
		local levelType = self:getLevelType()

		if strsub(className, 1, 3) == 'mm.' and prefix ~= 'MM' then
			return 0
		elseif strsub(className, 1, 3) == 'th.' and prefix ~= 'TH' then
			return 0
		elseif strsub(className, 1, 3) == 'ww.' and prefix ~= 'WW' then
			return 0
		elseif strsub(className, 1, 3) == 'as.' and prefix ~= 'AS' then
			return 0
		elseif strsub(className, 1, 3) == 'AS.' and prefix ~= 'AS' then
			return 0
		elseif strsub(className, 1, 3) == 'ca.' and prefix ~= 'CA' then
			return 0
		end

		if levelType == 'mental' then
			if className == 'global.collectibles.PSIChallengeCard'
				or className == 'global.collectibles.PsiChallengeMarker'
				or className == 'global.collectibles.PSIChallengeCore'
				or className == 'global.collectibles.BrainJar'
				or className == 'ca.props.ScavengerHuntItem' then
				return 0
			end
		elseif levelType == 'real' then
			if className == 'global.collectibles.Cobweb'
				or className == 'global.collectibles.Figment'
				or className == 'global.collectibles.SplineFigment'
				or className == 'global.collectibles.EmotionalBaggage'
				or className == 'global.collectibles.EmotionalBaggageTag'
				or className == 'global.characters.Vault' then
				return 0
			end
		end

		return 1
	end

	function Ob:cachePlayerPosition()
		self.playerX = nil
		self.playerY = nil
		self.playerZ = nil
		if Global ~= nil and Global.player ~= nil then
			self.playerX, self.playerY, self.playerZ = Global.player:getPosition()
		end
	end

	function Ob:getEntityName(ent)
		if ent == nil then
			return '(nil entity)'
		end
		if ent.Name ~= nil then
			return ent.Name
		end
		return '(unnamed)'
	end

	function Ob:isCandidateAvailable(ent)
		if ent == nil or ent.getPosition == nil then
			return 0
		end
		if IsDead ~= nil and IsDead(ent) == 1 then
			return 0
		end
		if ent.bCollected == 1 or ent.bHide == 1 or ent.bSBHidden == 1 then
			return 0
		end
		return 1
	end

	function Ob:getTargetPosition(ent)
		if ent == nil or ent.getPosition == nil then
			return
		end
		-- Spline figments can move their mesh and pickup volume without moving
		-- the entity origin. The AABB starts with the pickup volume's world center.
		if ent.splineFollowing ~= nil and ent.trigger ~= nil and TriggerOBB_GetAABB ~= nil then
			local x, y, z = TriggerOBB_GetAABB(ent.trigger)
			if x ~= nil and y ~= nil and z ~= nil then
				return x, y, z
			end
		end
		return ent:getPosition()
	end

	function Ob:getPositionText(ent)
		if ent ~= nil and ent.getPosition ~= nil then
			local x, y, z = self:getTargetPosition(ent)
			if x ~= nil then
				return ' pos=('..self:numberText(x)..', '..self:numberText(y)..', '..self:numberText(z)..')'..self:getDistanceText(x, y, z)
			end
		end
		return ''
	end

	function Ob:getDistanceText(x, y, z)
		if x ~= nil and self.playerX ~= nil then
			local dx = x - self.playerX
			local dy = y - self.playerY
			local dz = z - self.playerZ
			return ' dist='..self:numberText(GetDistance(self.playerX, self.playerY, self.playerZ, x, y, z))
		end
		return ''
	end

	function Ob:getDirectionText(dx, dy, dz)
		local horiz = 'near'
		if Global ~= nil and Global.player ~= nil then
			local fx, fy, fz = GetEntityForwardVector(Global.player)
			local dot = DotProduct(fx, 0, fz, dx, 0, dz, 1)
			if dot > 0.65 then
				horiz = 'ahead'
			elseif dot < -0.65 then
				horiz = 'behind'
			else
				local cross = fx * dz - fz * dx
				if cross > 0 then
					horiz = 'right'
				else
					horiz = 'left'
				end
			end
		end

		local vert = ''
		if dy > 180 then
			vert = ' above'
		elseif dy < -180 then
			vert = ' below'
		end
		return horiz..vert
	end

	function Ob:addStats()
		if Global == nil or Global.player == nil or Global.player.stats == nil then
			self:addLine('Stats: unavailable')
			return
		end

		local stats = Global.player.stats
		self:addLine('Stats loaded from save/current session:')
		self:addLine('  rank='..self:valueText(stats.rank)..' cardsInInv='..self:valueText(stats.cardsInInv)..' coresInInv='..self:valueText(stats.coresInInv)..' websInInv='..self:valueText(stats.websInInv)..' arrowheads='..self:valueText(stats.arrowheads))
		self:addLine('  cards='..self:valueText(stats.PSIChallengeCards)..' markers='..self:valueText(stats.PSImarkers)..' cores='..self:valueText(stats.PSIChallengeCores)..' cobwebs='..self:valueText(stats.cobwebs))
		self:addLine('  figmentsFromLevel='..self:valueText(stats.figmentsFromLevel)..' totalFigments='..self:valueText(stats.totalFigments)..' figmentPoints='..self:valueText(stats.figmentPoints))
		self:addLine('  baggageSolved='..self:valueText(stats.EmotionalBaggageSolved)..' vaultCountFromLevel='..self:valueText(stats.vaultCountFromLevel)..' brainsFromLevel='..self:valueText(stats.brainsFromLevel)..' scavItemsFromLevel='..self:valueText(stats.scavItemsFromLevel))
	end

	function Ob:recordEntity(ent)
		self.currentCount = self.currentCount + 1
		self.totalLoaded = self.totalLoaded + 1
		if self.currentCount <= self.detailLimit then
			tinsert(self.currentLines, '  '..self.currentCount..'. '..self:getEntityName(ent)..self:getPositionText(ent))
		elseif self.currentCount == self.detailLimit + 1 then
			tinsert(self.currentLines, '  ...more omitted from this class')
		end
	end

	function Ob:recordCandidate(ent)
		self.currentCount = self.currentCount + 1
		self.totalLoaded = self.totalLoaded + 1
		if self:isCandidateAvailable(ent) ~= 1 or self.playerX == nil then
			return
		end

		local x, y, z = self:getTargetPosition(ent)
		if x == nil then
			return
		end

		local dist = GetDistance(self.playerX, self.playerY, self.playerZ, x, y, z)
		local candidate = {
			entity = ent,
			label = self.currentLabel,
			shortLabel = self.currentShortLabel,
			name = self:getEntityName(ent),
			distance = dist,
			x = x,
			y = y,
			z = z,
		}
		tinsert(self.candidates, candidate)

		if self.bestEntity == nil or dist < self.bestDistance then
			self:setBestCandidate(candidate)
		end
	end

	function Ob:setBestCandidate(candidate)
		if candidate == nil then
			self.bestEntity = nil
			self.bestLabel = nil
			self.bestShortLabel = nil
			self.bestName = nil
			self.bestDistance = nil
			self.bestX = nil
			self.bestY = nil
			self.bestZ = nil
			return
		end

		self.bestEntity = candidate.entity
		self.bestLabel = candidate.label
		self.bestShortLabel = candidate.shortLabel
		self.bestName = candidate.name
		self.bestDistance = candidate.distance
		self.bestX = candidate.x
		self.bestY = candidate.y
		self.bestZ = candidate.z
	end

	function Ob:countType(label, className)
		self.currentLabel = label
		self.currentCount = 0
		self.currentLines = {}
		foreach_entity_oftype(className, CollectibleScout_RecordEntity)
		if self.currentCount > 0 then
			self:addLine(label..' ['..className..']: '..self.currentCount..' loaded')
			local i
			for i = 1, getn(self.currentLines) do
				self:addLine(self.currentLines[i])
			end
		end
	end

	function Ob:scanAllTypes()
		local i
		for i = 1, getn(self.scanTypes) do
			self:countType(self.scanTypes[i].label, self.scanTypes[i].className)
		end
	end

	function Ob:findNearest()
		self.bestEntity = nil
		self.bestLabel = nil
		self.bestShortLabel = nil
		self.bestName = nil
		self.bestDistance = nil
		self.bestX = nil
		self.bestY = nil
		self.bestZ = nil
		self.candidates = {}
		self.totalLoaded = 0
		self:cachePlayerPosition()

		if self.playerX == nil then
			return
		end

		local i
		for i = 1, getn(self.scanTypes) do
			if self:shouldScanType(self.scanTypes[i]) == 1 then
				self.currentLabel = self.scanTypes[i].label
				self.currentShortLabel = self.scanTypes[i].shortLabel
				self.currentCount = 0
				foreach_entity_oftype(self.scanTypes[i].className, CollectibleScout_RecordCandidate)
			end
		end
	end

	function Ob:selectCycleCandidate()
		local count = getn(self.candidates)
		if count <= 1 or self.bestEntity == nil then
			self.lastSelectedDistance = self.bestDistance
			self.lastScanTime = GetGameTimeSecs()
			return
		end

		local now = GetGameTimeSecs()
		local useCycle = 0
		if self.lastScanTime ~= nil and now - self.lastScanTime <= self.cycleWindowSecs then
			useCycle = 1
		end

		if useCycle == 1 and self.lastSelectedDistance ~= nil then
			local nextCandidate = nil
			local i
			for i = 1, count do
				local candidate = self.candidates[i]
				if candidate.distance > self.lastSelectedDistance + 25 then
					if nextCandidate == nil or candidate.distance < nextCandidate.distance then
						nextCandidate = candidate
					end
				end
			end

			if nextCandidate ~= nil then
				self:setBestCandidate(nextCandidate)
			end
		end

		self.lastSelectedDistance = self.bestDistance
		self.lastScanTime = now
	end

	function Ob:getCandidateRank()
		if self.bestDistance == nil then
			return ''
		end

		local count = getn(self.candidates)
		if count <= 1 then
			return ''
		end

		local rank = 1
		local i
		for i = 1, count do
			if self.candidates[i].distance < self.bestDistance - 25 then
				rank = rank + 1
			end
		end

		return ' '..rank..'/'..count
	end

	function Ob:ensureOutputFolder()
		if not direxists(self.outputFolder) then
			mkdirs(self.outputFolder)
		end
	end

	function Ob:writeLines(path, mode)
		local h = fopen(path, mode)
		if h then
			local i
			for i = 1, getn(self.lines) do
				fwrite(h, self.lines[i]..'\n')
			end
			fwrite(h, '\n')
			fclose(h)
			return 1
		end
		return 0
	end

	function Ob:writeReport()
		self:ensureOutputFolder()
		local wroteLast = self:writeLines(self.lastReportPath, 'w')
		self:writeLines(self.historyPath, 'a')
		return wroteLast
	end

	function Ob:hideOverlay()
		if self.overlayText ~= nil then
			RemoveText(self.overlayText)
			self.overlayText = nil
		end
	end

	function Ob:showOverlay(text)
		self:hideOverlay()
		self.overlayText = DisplayText(text, 40, 80)
		if self.overlayText ~= nil then
			SetTextPriority(self.overlayText, 51)
			self:createTimerSecs(5, self.TIMER_HIDE_TEXT)
		end
	end

	function Ob:clearHud()
		self:killTimer(self.TIMER_HIDE_HUD)
		if self.hudHandle ~= nil then
			RemoveText(self.hudHandle)
			self.hudHandle = nil
		end
		self.lastHudText = nil
	end

	function Ob:showHud(text)
		if text == self.lastHudText and self.hudHandle ~= nil then
			self:killTimer(self.TIMER_HIDE_HUD)
			self:createTimerSecs(self.hudDisplaySecs, self.TIMER_HIDE_HUD)
			return
		end

		self:clearHud()
		if text ~= nil and text ~= '' then
			self.hudHandle = DisplayText(text, 24, 34)
			self.lastHudText = text
			if self.hudHandle ~= nil then
				SetTextPriority(self.hudHandle, 51)
				self:killTimer(self.TIMER_HIDE_HUD)
				self:createTimerSecs(self.hudDisplaySecs, self.TIMER_HIDE_HUD)
			end
		end
	end

	function Ob:clearHighlight()
		self:clearBeaconEmitters()
		if self.highlightFX ~= nil then
			if self.usePostEffectHighlight == 1 then
				SetEntityFlag(self.highlightFX, ENTITY_POST_EFFECTS, 0)
			end
			self.highlightFX:stop(1, 0, 1)
			self.highlightFX = nil
		end
		if self.highlightTarget ~= nil and self.usePostEffectHighlight == 1 then
			SetEntityFlag(self.highlightTarget, ENTITY_POST_EFFECTS, 0)
		end
		self.highlightTarget = nil
	end

	function Ob:clearTemporaryVisuals()
		self:killTimer(self.TIMER_REFRESH)
		self.visualsUntil = nil
		self:killTimer(self.TIMER_HIDE_HUD)
		self:killTimer(self.TIMER_CLEAR_HIGHLIGHT)
		self.noTargetWatchUntil = nil
		self.nextNoTargetScanAt = nil
		self.manualTargetOverride = 0
		self:clearHud()
		self:hideOverlay()
		self:clearHighlight()
	end

	function Ob:clearBeaconEmitters()
		if self.highlightBeaconEmitter ~= nil then
			PESetActive(self.highlightBeaconEmitter, 0)
			PEReset(self.highlightBeaconEmitter, 0)
			PEDestroyEmitter(self.highlightBeaconEmitter)
			self.highlightBeaconEmitter = nil
		end

		if self.highlightSparkEmitter ~= nil then
			PESetActive(self.highlightSparkEmitter, 0)
			PEReset(self.highlightSparkEmitter, 0)
			PEDestroyEmitter(self.highlightSparkEmitter)
			self.highlightSparkEmitter = nil
		end
	end

	function Ob:createBeaconEmitters(x, y, z)
		self.highlightBeaconEmitter = CreateParticleEmitter('CollectibleScoutBeaconPE', 120)
		if self.highlightBeaconEmitter ~= nil then
			SetPosition(self.highlightBeaconEmitter, x, y + self.highlightOffsetY, z)
			if self.usePostEffectHighlight == 1 then
				SetEntityFlag(self.highlightBeaconEmitter, ENTITY_POST_EFFECTS, 1)
			end
			PESetTexture(self.highlightBeaconEmitter, 'textures/fxtextures/ray.dds')
			PESetParticleBlendMode(self.highlightBeaconEmitter, kBLENDMODE_ADD_ALPHA)
			PESetParticleForce(self.highlightBeaconEmitter, 0, 180, 0)
			PESetApplyGravity(self.highlightBeaconEmitter, 0)
			PESetPointSprite(self.highlightBeaconEmitter, 0)
			PESetZSprite(self.highlightBeaconEmitter, 0)
			PESetNoSpread(self.highlightBeaconEmitter, 0)
			PESetRelative(self.highlightBeaconEmitter, 0)
			PESetOriented(self.highlightBeaconEmitter, 0)
			PESetCollideWithGround(self.highlightBeaconEmitter, 0)
			PESetNoZBuffer(self.highlightBeaconEmitter, 1)
			PESetPostOnly(self.highlightBeaconEmitter, 1)
			PESetConeAngle(self.highlightBeaconEmitter, 0, 180)
			PESetParticleSpeed(self.highlightBeaconEmitter, 0, 25)
			PESetParticleStartEndSize(self.highlightBeaconEmitter, 180, 420)
			PESetParticleRotation(self.highlightBeaconEmitter, 0, 0, 1)
			PESetParticleLifetime(self.highlightBeaconEmitter, 0.8, 1.4)
			PESetParticlesPerSec(self.highlightBeaconEmitter, 12, 24)
			PESetStartColor(self.highlightBeaconEmitter, 60, 255, 230, 210)
			PESetEndColor(self.highlightBeaconEmitter, 255, 255, 255, 0)
			PESetDistribution(self.highlightBeaconEmitter, kPD_BOX, kPDV_DEFAULT, -30, -60, -30, 30, 420, 30)
			PESetActive(self.highlightBeaconEmitter, 1)
		end

		self.highlightSparkEmitter = CreateParticleEmitter('CollectibleScoutSparkPE', 80)
		if self.highlightSparkEmitter ~= nil then
			SetPosition(self.highlightSparkEmitter, x, y + self.highlightOffsetY, z)
			if self.usePostEffectHighlight == 1 then
				SetEntityFlag(self.highlightSparkEmitter, ENTITY_POST_EFFECTS, 1)
			end
			PESetTexture(self.highlightSparkEmitter, 'textures/fxtextures/lensflares/lensflareyellowsmall.tga')
			PESetParticleBlendMode(self.highlightSparkEmitter, kBLENDMODE_ADD_ALPHA)
			PESetParticleForce(self.highlightSparkEmitter, 0, 90, 0)
			PESetApplyGravity(self.highlightSparkEmitter, 0)
			PESetPointSprite(self.highlightSparkEmitter, 0)
			PESetZSprite(self.highlightSparkEmitter, 0)
			PESetNoSpread(self.highlightSparkEmitter, 0)
			PESetRelative(self.highlightSparkEmitter, 0)
			PESetOriented(self.highlightSparkEmitter, 0)
			PESetCollideWithGround(self.highlightSparkEmitter, 0)
			PESetNoZBuffer(self.highlightSparkEmitter, 1)
			PESetPostOnly(self.highlightSparkEmitter, 1)
			PESetConeAngle(self.highlightSparkEmitter, 0, 180)
			PESetParticleSpeed(self.highlightSparkEmitter, 20, 55)
			PESetParticleSize(self.highlightSparkEmitter, 70, 140)
			PESetParticleRotation(self.highlightSparkEmitter, 0, 0, 1)
			PESetParticleLifetime(self.highlightSparkEmitter, 0.7, 1.2)
			PESetParticlesPerSec(self.highlightSparkEmitter, 8, 28)
			PESetStartColor(self.highlightSparkEmitter, 255, 255, 120, 230)
			PESetEndColor(self.highlightSparkEmitter, 255, 255, 255, 0)
			PESetDistribution(self.highlightSparkEmitter, kPD_SPHERE, kPDV_AXIAL, x, y + self.highlightOffsetY, z, 80, 120)
			PESetActive(self.highlightSparkEmitter, 1)
		end
	end

	function Ob:highlightTargetEntity(target)
		if target == self.highlightTarget and self.highlightFX ~= nil then
			if target.splineFollowing ~= nil then
				local x, y, z = self:getTargetPosition(target)
				if x ~= nil then
					self.highlightFX:setPosition(x, y + self.highlightOffsetY, z)
				end
			end
			return
		end

		self:clearHighlight()
		self.highlightTarget = target

		if target ~= nil then
			SetMaxViewDistance(target, 100000)
			SetSimulationCullDistance(target, 100000)
			if self.usePostEffectHighlight == 1 then
				SetEntityFlag(target, ENTITY_POST_EFFECTS, 1)
			end
			if Global ~= nil and Global.levelScript ~= nil then
				self.highlightFX = Global.levelScript:getPool('Global.Effects.SupremeInterestFX'):get()
				if self.highlightFX ~= nil then
					SetEntityDomain(self.highlightFX, GetEntityDomain(target))
					if self.usePostEffectHighlight == 1 then
						SetEntityFlag(self.highlightFX, ENTITY_POST_EFFECTS, 1)
					end
					self.highlightFX:run()
					if target.splineFollowing ~= nil then
						self.highlightFX:detach()
						local x, y, z = self:getTargetPosition(target)
						if x ~= nil then
							self.highlightFX:setPosition(x, y + self.highlightOffsetY, z)
						end
					else
						local rootJoint = GetRootJointName(target)
						if rootJoint then
							self.highlightFX:attach(target, rootJoint)
						else
							self.highlightFX:attach(target)
						end
						self.highlightFX:setPosition(0, self.highlightOffsetY, 0)
					end
					self.highlightFX:setScale(2)
				end
			end
		end
	end

	function Ob:trackerTick(cycleTargets)
		self:findNearest()
		if self.bestEntity == nil then
			self:clearHighlight()
			self:showHud('Scout: none')
			self:startNoTargetWatch()
			return
		end
		self:stopNoTargetWatch()
		if cycleTargets == 1 then
			self:selectCycleCandidate()
		end

		self:refreshTrackedHudOnly()
		self:highlightTargetEntity(self.bestEntity)
	end

	function Ob:refreshSelectedHud()
		if self.visualsUntil == nil and self.trackerActive ~= 1 then
			return
		end
		if self.visualsUntil ~= nil and GetGameTimeSecs() >= self.visualsUntil then
			self:clearTemporaryVisuals()
			return
		end
		if self.manualTargetOverride == 1 and self.bestEntity ~= nil then
			self:refreshTrackedHudOnly()
		elseif self.candidates ~= nil and getn(self.candidates) > 0 then
			self:refreshNearestFromCachedCandidates()
		elseif self.bestEntity == nil then
			self:retryNoTargetScan()
		else
			self:refreshTrackedHudOnly()
		end
	end

	function Ob:startNoTargetWatch()
		local now = GetGameTimeSecs()
		self.noTargetWatchUntil = now + self.noTargetWatchSecs
		self.nextNoTargetScanAt = now + self.noTargetRetrySecs
	end

	function Ob:stopNoTargetWatch()
		self.noTargetWatchUntil = nil
		self.nextNoTargetScanAt = nil
	end

	function Ob:retryNoTargetScan()
		if self.noTargetWatchUntil == nil or self.nextNoTargetScanAt == nil then
			return
		end

		local now = GetGameTimeSecs()
		if now > self.noTargetWatchUntil then
			self:stopNoTargetWatch()
			return
		end
		if now < self.nextNoTargetScanAt then
			return
		end

		self.nextNoTargetScanAt = now + self.noTargetRetrySecs
		self:findNearest()
		if self.bestEntity == nil then
			self:showHud('Scout: none')
			return
		end

		self:stopNoTargetWatch()
		self:refreshTrackedHudOnly()
		self:highlightTargetEntity(self.bestEntity)
	end

	function Ob:refreshNearestFromCachedCandidates()
		self:cachePlayerPosition()
		if self.playerX == nil then
			return
		end

		local bestCandidate = nil
		local i
		for i = 1, getn(self.candidates) do
			local candidate = self.candidates[i]
			local ent = candidate.entity
			if self:isCandidateAvailable(ent) == 1 then
				local x, y, z = self:getTargetPosition(ent)
				if x ~= nil then
					local dist = GetDistance(self.playerX, self.playerY, self.playerZ, x, y, z)
					candidate.distance = dist
					candidate.x = x
					candidate.y = y
					candidate.z = z
					if bestCandidate == nil or dist < bestCandidate.distance then
						bestCandidate = candidate
					end
				end
			end
		end

		if bestCandidate == nil then
			self:setBestCandidate(nil)
			self:clearHighlight()
			self:showHud('Scout: none')
			return
		end

		self:setBestCandidate(bestCandidate)
		self:showSelectedHud()
		self:highlightTargetEntity(self.bestEntity)
	end

	function Ob:refreshTrackedHudOnly()
		if self.bestEntity == nil then
			return
		end
		if self:isCandidateAvailable(self.bestEntity) ~= 1 then
			self.manualTargetOverride = 0
			self:refreshNearestFromCachedCandidates()
			return
		end

		self:cachePlayerPosition()
		if self.playerX == nil then
			return
		end

		local x, y, z = self:getTargetPosition(self.bestEntity)
		if x == nil then
			self.manualTargetOverride = 0
			self:refreshNearestFromCachedCandidates()
			return
		end

		self.bestX = x
		self.bestY = y
		self.bestZ = z
		self.bestDistance = GetDistance(self.playerX, self.playerY, self.playerZ, x, y, z)
		self:showSelectedHud()
		self:highlightTargetEntity(self.bestEntity)
	end

	function Ob:showSelectedHud()
		if self.bestEntity == nil or self.bestDistance == nil or self.playerX == nil then
			return
		end
		local dx = self.bestX - self.playerX
		local dy = self.bestY - self.playerY
		local dz = self.bestZ - self.playerZ
		local direction = self:getDirectionText(dx, dy, dz)
		self:showHud(self.bestShortLabel..' '..self:distanceText(self.bestDistance)..' '..direction)
	end

	function Ob:skipCurrentTarget()
		if self.bestEntity == nil then
			self:updateOnce()
			return
		end

		self.trackerActive = 0
		self.manualTargetOverride = 0
		self:killTimer(self.TIMER_TRACKER)
		self:killTimer(self.TIMER_CLEAR_HIGHLIGHT)
		self:clearHud()
		self:clearHighlight()
		self:startTemporaryRefresh()

		if self.candidates ~= nil and getn(self.candidates) > 0 then
			self:selectNextCachedCandidate()
		else
			self:findNearest()
			if self.bestEntity ~= nil then
				self:refreshTrackedHudOnly()
				self:highlightTargetEntity(self.bestEntity)
			end
		end

		if self.bestEntity == nil then
			self:showHud('Scout: none')
			self:startNoTargetWatch()
		else
			self:stopNoTargetWatch()
			self.manualTargetOverride = 1
		end
		self:createTimerSecs(self.highlightDisplaySecs, self.TIMER_CLEAR_HIGHLIGHT)
	end

	function Ob:selectNextCachedCandidate()
		self:cachePlayerPosition()
		if self.playerX == nil or self.candidates == nil or getn(self.candidates) == 0 then
			return
		end

		local currentDistance = self.bestDistance
		local nearestCandidate = nil
		local nextCandidate = nil
		local i
		for i = 1, getn(self.candidates) do
			local candidate = self.candidates[i]
			local ent = candidate.entity
			if self:isCandidateAvailable(ent) == 1 then
				local x, y, z = self:getTargetPosition(ent)
				if x ~= nil then
					local dist = GetDistance(self.playerX, self.playerY, self.playerZ, x, y, z)
					candidate.distance = dist
					candidate.x = x
					candidate.y = y
					candidate.z = z
					if nearestCandidate == nil or dist < nearestCandidate.distance then
						nearestCandidate = candidate
					end
					if currentDistance ~= nil and dist > currentDistance + 25 then
						if nextCandidate == nil or dist < nextCandidate.distance then
							nextCandidate = candidate
						end
					end
				end
			end
		end

		if nextCandidate ~= nil then
			self:setBestCandidate(nextCandidate)
		else
			self:setBestCandidate(nearestCandidate)
		end

		if self.bestEntity ~= nil then
			self:showSelectedHud()
			self:highlightTargetEntity(self.bestEntity)
		end
	end

	function Ob:startTracker()
		self.trackerActive = 1
		self:trackerTick()
		self:killTimer(self.TIMER_TRACKER)
		self:createTimer(self.trackerInterval, self.TIMER_TRACKER)
	end

	function Ob:updateOnce()
		self.trackerActive = 0
		self:killTimer(self.TIMER_TRACKER)
		self:killTimer(self.TIMER_CLEAR_HIGHLIGHT)
		self:clearTemporaryVisuals()
		self:startTemporaryRefresh()
		self:trackerTick()
		self:createTimerSecs(self.highlightDisplaySecs, self.TIMER_CLEAR_HIGHLIGHT)
	end

	function Ob:startTemporaryRefresh()
		self.visualsUntil = GetGameTimeSecs() + self.highlightDisplaySecs
		self:killTimer(self.TIMER_REFRESH)
		self:createTimer(self.refreshInterval, self.TIMER_REFRESH)
	end

	function Ob:stopTracker()
		self.trackerActive = 0
		self:killTimer(self.TIMER_TRACKER)
		self:killTimer(self.TIMER_CLEAR_HIGHLIGHT)
		self:clearTemporaryVisuals()
	end

	function Ob:scan(reason)
		self.lines = {}
		self.totalLoaded = 0
		self:cachePlayerPosition()

		self:addLine('Collectible Scout scan')
		self:addLine('Reason: '..self:valueText(reason))
		self:addLine('Level: '..self:valueText(self:getLevelName())..' prefix='..self:valueText(self:getLevelPrefix())..' type='..self:valueText(self:getLevelType())..' script='..self:valueText(self:getScriptType()))
		if self.playerX ~= nil then
			self:addLine('Raz position: ('..self:numberText(self.playerX)..', '..self:numberText(self.playerY)..', '..self:numberText(self.playerZ)..')')
			self:addLine('dist values are game units from Raz.')
		end
		self:addStats()
		self:addLine('')
		self:addLine('Loaded collectible entities:')
		self:scanAllTypes()

		if self.totalLoaded == 0 then
			self:addLine('  none found in the currently loaded level')
		end

		local wrote = self:writeReport()
		local message = '[Collectible Scout] '..self:valueText(self:getLevelName())..': '..self.totalLoaded..' loaded collectibles. Report: ModData/CollectibleScout/last_scan.txt'
		if wrote ~= 1 then
			message = '[Collectible Scout] Scan complete, but report write failed.'
		end
		GamePrint(message)
	end

	return Ob
end
