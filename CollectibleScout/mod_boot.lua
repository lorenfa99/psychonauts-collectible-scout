add_hook('beginlevel', 'CollectibleScout_BeginLevel')
function CollectibleScout_BeginLevel()
	local scout = fso('CollectibleScout', 'CollectibleScout')
	if scout == nil then
		SpawnScript('CollectibleScout', 'CollectibleScout')
	end
end

add_hook('postbeginlevel', 'CollectibleScout_PostBeginLevel')
function CollectibleScout_PostBeginLevel()
	local scout = fso('CollectibleScout', 'CollectibleScout')
	if scout == nil then
		scout = SpawnScript('CollectibleScout', 'CollectibleScout')
	end

	if scout ~= nil then
		scout:stopTracker()
	else
		GamePrint('[Collectible Scout] Could not spawn scanner.')
	end
end
