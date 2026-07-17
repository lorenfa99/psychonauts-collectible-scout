local scout = fso('CollectibleScout', 'CollectibleScout')
if scout == nil then
	scout = SpawnScript('CollectibleScout', 'CollectibleScout')
end

if scout ~= nil then
	scout:updateOnce()
else
	GamePrint('[Collectible Scout] Could not find or spawn scanner.')
end
