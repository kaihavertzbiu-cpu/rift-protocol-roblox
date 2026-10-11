-- RIFT PROTOCOL — Public Alpha Server
-- Server-authoritative combat, enemies, mission loop, progression and save data.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local MarketplaceService = game:GetService("MarketplaceService")
Players.RespawnTime = 2.5

-- The imported greybox was built 18 studs above the current floor. Its
-- 2048-stud baseplate covered both the lobby and mission, trapping players
-- after the new scenes teleported them to Y=5. Retire it before anyone spawns.
local function retireLegacyWorld(worldRoot)
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end
	local oldLobby = worldRoot:FindFirstChild("Lobby")
	if oldLobby then oldLobby:Destroy() end
	local spawn = Workspace:FindFirstChild("RIFT_Spawn")
	if spawn and spawn:IsA("SpawnLocation") then
		spawn.CFrame = CFrame.new(0, 1.5, 15)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.CanQuery = false
	end
	print("[RIFT][WORLD] Legacy elevated baseplate/lobby retired; spawn at ground level")
end

local function buildLobbyHero(worldRoot)
	for _,name in ipairs({"LobbyVisual_v0_30", "LobbyVisual_v0_31", "LobbyVisual_v0_32", "LobbyVisual_v0_33"}) do
		local old = worldRoot:FindFirstChild(name)
		if old then old:Destroy() end
	end
	local folder = Instance.new("Folder")
	folder.Name = "LobbyVisual_v0_33"
	folder:SetAttribute("VisualVersion", "0.33")
	folder.Parent = worldRoot

	local coolDark, stone, edge = Color3.fromRGB(38,46,62), Color3.fromRGB(66,77,96), Color3.fromRGB(94,107,131)
	local cyan, violet, amber = Color3.fromRGB(65,220,255), Color3.fromRGB(128,76,255), Color3.fromRGB(255,166,70)
	local function part(name, size, cf, color, material, transparency, shape)
		local p = Instance.new("Part")
		p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
		p.Material, p.Transparency = material or Enum.Material.Slate, transparency or 0
		p.Anchored, p.CanCollide = true, true
		p.CastShadow = transparency == nil or transparency < 0.5
		if shape then p.Shape = shape end
		p.Parent = folder
		return p
	end
	local function glow(parent, color, brightness, range)
		local l = Instance.new("PointLight")
		l.Color, l.Brightness, l.Range, l.Shadows = color, brightness, range, true
		l.Parent = parent
	end
	local function label(adornee, title, subtitle, color)
		local gui = Instance.new("BillboardGui")
		gui.Name, gui.Adornee = "LandmarkLabel", adornee
		gui.Size, gui.StudsOffset = UDim2.fromOffset(164,42), Vector3.new(0,4,0)
		gui.AlwaysOnTop, gui.MaxDistance, gui.Parent = false, 12, adornee
		local a = Instance.new("TextLabel")
		a.Size, a.BackgroundTransparency = UDim2.new(1,0,.58,0), 1
		a.Font, a.Text, a.TextColor3, a.TextSize = Enum.Font.GothamBold, title, color, 12
		a.TextStrokeColor3, a.TextStrokeTransparency, a.Parent = Color3.new(0,0,0), .35, gui
		local b = Instance.new("TextLabel")
		b.Position, b.Size, b.BackgroundTransparency = UDim2.new(0,0,.56,0), UDim2.new(1,0,.44,0), 1
		b.Font, b.Text, b.TextColor3, b.TextSize = Enum.Font.GothamMedium, subtitle, Color3.fromRGB(185,195,215), 8
		b.TextStrokeTransparency, b.Parent = .45, gui
	end
	local function interaction(adornee, actionText, objectText, actionId)
		local prompt=Instance.new("ProximityPrompt")
		prompt.Name="RiftInteraction"
		prompt.ActionText=actionText; prompt.ObjectText=objectText
		prompt.KeyboardKeyCode=Enum.KeyCode.F; prompt.GamepadKeyCode=Enum.KeyCode.ButtonX
		prompt.HoldDuration=.18; prompt.MaxActivationDistance=11; prompt.RequiresLineOfSight=false
		prompt:SetAttribute("RiftAction",actionId); prompt.Parent=adornee
		return prompt
	end

	part("NaveFloor", Vector3.new(42,1,84), CFrame.new(0,0,-10), coolDark, Enum.Material.Slate)
	part("CenterRunner", Vector3.new(13,.18,72), CFrame.new(0,.59,-12), Color3.fromRGB(54,65,88), Enum.Material.SmoothPlastic)
	for i=0,8 do
		local inlay = part("RunnerInlay",Vector3.new(.14,.08,5.2),CFrame.new(0,.72,18-i*8),cyan,Enum.Material.Neon,.35)
		inlay.CanCollide = false
	end
	for _,side in ipairs({-1,1}) do
		local rail=part("RunnerEdge",Vector3.new(.16,.12,72),CFrame.new(side*6.5,.7,-12),Color3.fromRGB(82,128,157),Enum.Material.Metal,.18)
		rail.CanCollide=false
	end
	for z=18,-38,-8 do
		local seam=part("FloorSeam",Vector3.new(40,.04,.12),CFrame.new(0,.53,z),edge,Enum.Material.Metal,.52)
		seam.CanCollide=false
	end
	for _,side in ipairs({-1,1}) do
		part("SidePlatform",Vector3.new(14,1.1,58),CFrame.new(side*28,.25,-10),stone,Enum.Material.Cobblestone)
		part("OuterWall",Vector3.new(2,15,82),CFrame.new(side*36,7,-10),coolDark,Enum.Material.Slate)
		for z=18,-38,-14 do
			part("Buttress",Vector3.new(4.5,16,4.5),CFrame.new(side*33,7.5,z),edge,Enum.Material.Slate)
			part("ButtressCap",Vector3.new(6,1.2,6),CFrame.new(side*33,15.5,z),coolDark,Enum.Material.Metal)
		end
	end
	-- A ribbed vault closes the white sky gap and gives the hub a memorable
	-- cathedral silhouette without lowering the playable camera volume.
	for _,z in ipairs({17,1,-15,-31}) do
		local rib=part("VaultRib",Vector3.new(31,.72,.72),CFrame.new(0,17.2,z),edge,Enum.Material.Metal)
		rib.CanCollide=false
		for _,side in ipairs({-1,1}) do
			local roof=part("VaultPanel",Vector3.new(16,.72,14),CFrame.new(side*8.1,18.9,z)*CFrame.Angles(0,0,math.rad(side*12)),coolDark,Enum.Material.Slate)
			roof.CanCollide=false
		end
		local lantern=part("SanctumLumen",Vector3.new(1.05,1.05,1.05),CFrame.new(0,14.25,z),z%2==1 and cyan or violet,Enum.Material.Neon,.2,Enum.PartType.Ball)
		lantern.CanCollide=false; glow(lantern,lantern.Color,.55,13)
		part("LumenChain",Vector3.new(.12,3.2,.12),CFrame.new(0,15.8,z),Color3.fromRGB(86,96,119),Enum.Material.Metal).CanCollide=false
		for i=0,7 do
			local a=i/8*math.pi*2
			local shard=part("LumenRing",Vector3.new(.18,.75,.18),CFrame.new(math.cos(a)*1.75,14.25+math.sin(a)*1.75,z)*CFrame.Angles(0,0,-a),i%2==0 and cyan or edge,Enum.Material.Neon,.18)
			shard.CanCollide=false
		end
	end
	for i=0,2 do part("RiftStep",Vector3.new(26-i*3,.75,5),CFrame.new(0,.38+i*.72,-34-i*3.2),edge,Enum.Material.Slate) end

	local center = Vector3.new(0,12.5,-43)
	part("RiftBack",Vector3.new(72,28,3),CFrame.new(0,12.5,-46.2),Color3.fromRGB(20,25,37),Enum.Material.Slate)
	part("RiftBackInset",Vector3.new(31,22,.42),CFrame.new(0,12,-44.55),Color3.fromRGB(33,39,55),Enum.Material.Metal)
	local energy=part("RiftEnergy",Vector3.new(13.5,18.5,.55),CFrame.new(center),violet,Enum.Material.ForceField,.28); energy.CanCollide=false
	local core=part("RiftCore",Vector3.new(8,13,.7),CFrame.new(center+Vector3.new(0,0,.2)),cyan,Enum.Material.Neon,.66); core.CanCollide=false; glow(core,cyan,2.7,27)
	for i=0,15 do
		local angle=(i/16)*math.pi*2
		local pos=center+Vector3.new(math.cos(angle)*8.7,math.sin(angle)*11.2,0)
		local seg=part("RiftArchSegment",Vector3.new(4.6,1.2,2.4),CFrame.new(pos)*CFrame.Angles(0,0,angle+math.pi/2),i%2==0 and edge or stone,Enum.Material.Slate)
		if i%4==0 then local rune=part("ArchRune",Vector3.new(2.2,.18,2.55),seg.CFrame*CFrame.new(0,-.7,0),cyan,Enum.Material.Neon,.16); rune.CanCollide=false end
	end
	local marker=part("RiftMarker",Vector3.new(1,1,1),CFrame.new(0,24.5,-42.5),cyan,Enum.Material.Neon,1); marker.CanCollide=false
	label(marker,"RIFT GATE","BEGIN MISSION  •  8–15 MIN",cyan)
	interaction(energy,"ENTER","ASHEN SANCTUM","StartMission")

	local function shrine(x,z,title,subtitle,color,isCore)
		part(title.."Base",Vector3.new(12,1.1,10),CFrame.new(x,.55,z),stone,Enum.Material.Cobblestone)
		part(title.."Plinth",Vector3.new(5.5,3.6,5.5),CFrame.new(x,2.25,z),edge,Enum.Material.Slate)
		local relic
		if isCore then
			local housing=part(title.."Housing",Vector3.new(4.8,4.8,4.8),CFrame.new(x,6,z)*CFrame.Angles(0,math.rad(45),math.rad(12)),Color3.fromRGB(31,38,53),Enum.Material.ForceField,.62)
			housing.CanCollide=false
			relic=part(title.."Relic",Vector3.new(2.15,2.15,2.15),CFrame.new(x,6,z)*CFrame.Angles(math.rad(18),math.rad(45),math.rad(18)),color,Enum.Material.ForceField,.32)
			for _,axis in ipairs({Vector3.new(5.4,.18,.18),Vector3.new(.18,5.4,.18),Vector3.new(.18,.18,5.4)}) do
				local brace=part(title.."CoreBrace",axis,CFrame.new(x,6,z)*CFrame.Angles(0,math.rad(45),0),Color3.fromRGB(92,116,143),Enum.Material.Metal,.08)
				brace.CanCollide=false
			end
		else
			local housing=part(title.."Housing",Vector3.new(2.4,7.8,1.2),CFrame.new(x,6,z)*CFrame.Angles(0,0,math.rad(-8)),Color3.fromRGB(38,39,49),Enum.Material.Metal,.02)
			housing.CanCollide=false
			relic=part(title.."Relic",Vector3.new(.28,5.5,1.45),CFrame.new(x,6,z+.68)*CFrame.Angles(0,0,math.rad(-8)),color,Enum.Material.Neon,.26)
		end
		relic.CanCollide=false; glow(relic,color,1.65,16); label(relic,title,subtitle,color)
		interaction(relic,isCore and "EVOLVE CORE" or "OPEN MASTERY",title,isCore and "UpgradeCore" or "UpgradeMastery")
		for _,dx in ipairs({-4.1,4.1}) do
			local lamp=part("ShrineLamp",Vector3.new(.8,2.6,.8),CFrame.new(x+dx,2.5,z+2.8),Color3.fromRGB(28,30,42),Enum.Material.Metal)
			local flame=part("ShrineFlame",Vector3.new(.36,.68,.36),lamp.CFrame*CFrame.new(0,1.55,0),color,Enum.Material.Neon,.28,Enum.PartType.Ball); flame.CanCollide=false; glow(flame,color,.72,8)
		end
	end
	shrine(-24,6,"MASTERY ALTAR","PERMANENT STAT NODES",amber,false)
	shrine(24,6,"CORE MATRIX","RIFT SHARDS  •  POWER",cyan,true)
	-- A permanent practice annex makes the signature combat loop learnable
	-- before the player commits to a five-wave expedition.
	local forgeAmber=Color3.fromRGB(218,112,48)
	part("TrainingDais",Vector3.new(14,1,14),CFrame.new(-24,.55,-25),stone,Enum.Material.Cobblestone)
	for _,entry in ipairs({
		{Vector3.new(10,.08,.16),CFrame.new(-24,1.12,-30.2)},
		{Vector3.new(10,.08,.16),CFrame.new(-24,1.12,-19.8)},
		{Vector3.new(.16,.08,10),CFrame.new(-29.2,1.12,-25)},
		{Vector3.new(.16,.08,10),CFrame.new(-18.8,1.12,-25)},
	}) do
		local inlay=part("TrainingInlay",entry[1],entry[2],forgeAmber,Enum.Material.Neon,.28)
		inlay.CanCollide=false; inlay.CastShadow=false
	end
	local trainingConsole=part("TrainingConsole",Vector3.new(2.8,4,2.8),CFrame.new(-32,2.2,-18),coolDark,Enum.Material.Metal)
	local trainingCore=part("TrainingCore",Vector3.new(1.1,1.1,1.1),trainingConsole.CFrame*CFrame.new(0,2.5,0),forgeAmber,Enum.Material.Neon,.12,Enum.PartType.Ball)
	trainingCore.CanCollide=false; glow(trainingCore,forgeAmber,.65,10)
	label(trainingCore,"COMBAT FORGE","PRACTICE BREAK  •  EXECUTE  •  SURGE",forgeAmber)
	interaction(trainingCore,"BEGIN DRILL","COMBAT FORGE","StartTraining")
	local duelConsole=part("DuelConsole",Vector3.new(2.8,4,2.8),CFrame.new(32,2.2,-18),coolDark,Enum.Material.Metal)
	local duelCore=part("DuelCore",Vector3.new(1.1,1.1,1.1),duelConsole.CFrame*CFrame.new(0,2.5,0),violet,Enum.Material.Neon,.12,Enum.PartType.Ball)
	duelCore.CanCollide=false; glow(duelCore,violet,.7,10)
	label(duelCore,"RIFT DUEL","1v1  •  SYNCED COMBAT POWER",violet)
	interaction(duelCore,"JOIN QUEUE","RIFT DUEL","ToggleDuelQueue")
	-- Distant silhouettes and banners give the Hub a world beyond the menu space.
	for _,side in ipairs({-1,1}) do
		part("SanctumCliff",Vector3.new(34,24,42),CFrame.new(side*53,5,-35)*CFrame.Angles(0,math.rad(side*12),math.rad(side*5)),Color3.fromRGB(35,42,56),Enum.Material.Rock)
		for _,z in ipairs({-30,-52}) do
			local tower=part("WatchTower",Vector3.new(10,26,10),CFrame.new(side*37,12,z),Color3.fromRGB(47,54,70),Enum.Material.Slate)
			part("TowerCrown",Vector3.new(13,2,13),tower.CFrame*CFrame.new(0,14,0),Color3.fromRGB(73,77,96),Enum.Material.Metal)
			local banner=part("RiftBanner",Vector3.new(.18,8,4.4),CFrame.new(side*31.8,11,z)*CFrame.Angles(0,math.rad(90),0),Color3.fromRGB(78,43,130),Enum.Material.Fabric)
			banner.CanCollide=false
		end
	end
	for i=1,8 do
		local angle=(i/8)*math.pi*2
		local shard=part("PortalShard",Vector3.new(.45,2.6,.45),CFrame.new(center+Vector3.new(math.cos(angle)*6.6,math.sin(angle)*8.4,-.5))*CFrame.Angles(angle,0,-angle),i%2==0 and cyan or violet,Enum.Material.Neon,.08)
		shard.CanCollide=false
	end
	for _,side in ipairs({-1,1}) do for _,z in ipairs({19,2,-16,-32}) do
		local post=part("TorchPost",Vector3.new(1.1,5.5,1.1),CFrame.new(side*17,2.75,z),Color3.fromRGB(48,52,67),Enum.Material.Metal)
		local flame=part("TorchFlame",Vector3.new(.48,.86,.48),post.CFrame*CFrame.new(0,3,0),amber,Enum.Material.Neon,.28,Enum.PartType.Ball); flame.CanCollide=false; glow(flame,amber,.88,11)
	end end

	Lighting.Brightness, Lighting.ClockTime = 3.2, 16.4
	Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(112,120,140), Color3.fromRGB(128,140,161)
    Lighting.ColorShift_Top, Lighting.FogColor = Color3.fromRGB(8,10,16), Color3.fromRGB(58,65,82)
	Lighting.FogStart, Lighting.FogEnd, Lighting.ExposureCompensation = 150, 430, .28
    Lighting.ShadowSoftness = .35
    for _,effect in ipairs(Lighting:GetChildren()) do
        if effect:IsA("BloomEffect") or effect:IsA("SunRaysEffect") or effect:IsA("DepthOfFieldEffect") or effect:IsA("ColorCorrectionEffect") then
            effect.Enabled=false
        elseif effect:IsA("Atmosphere") then
            effect.Density=0; effect.Haze=0; effect.Glare=0
        end
    end
    local atmosphere=Lighting:FindFirstChild("RIFT_Atmosphere") or Instance.new("Atmosphere")
    atmosphere.Name, atmosphere.Color, atmosphere.Decay = "RIFT_Atmosphere", Color3.fromRGB(176,188,215), Color3.fromRGB(70,58,88)
    atmosphere.Density, atmosphere.Offset, atmosphere.Glare, atmosphere.Haze, atmosphere.Parent = .1,.04,0,.22,Lighting
    local grade=Lighting:FindFirstChild("RIFT_ColorGrade") or Instance.new("ColorCorrectionEffect")
	grade.Name, grade.Brightness, grade.Contrast, grade.Saturation, grade.TintColor, grade.Enabled, grade.Parent = "RIFT_ColorGrade",.035,.075,-.055,Color3.fromRGB(241,244,255),true,Lighting
    local bloom=Lighting:FindFirstChild("RIFT_Bloom") or Instance.new("BloomEffect")
	bloom.Name, bloom.Intensity, bloom.Size, bloom.Threshold, bloom.Enabled, bloom.Parent = "RIFT_Bloom",.16,16,2.05,true,Lighting
	print("[RIFT] Lobby Hero Scene v0.33 ready")
end

local function buildDuelArena(worldRoot)
	local old=worldRoot:FindFirstChild("DuelArena_v0_10")
	if old then old:Destroy() end
	local folder=Instance.new("Folder"); folder.Name="DuelArena_v0_10"; folder.Parent=worldRoot
	local center=Vector3.new(110,0,-25)
	local function p(name,size,cf,color,material,transparency)
		local x=Instance.new("Part"); x.Name=name; x.Size=size; x.CFrame=cf; x.Color=color
		x.Material=material or Enum.Material.Slate; x.Transparency=transparency or 0
		x.Anchored=true; x.CanCollide=transparency==nil or transparency<.8; x.Parent=folder; return x
	end
	p("DuelFloor",Vector3.new(62,1,44),CFrame.new(center+Vector3.new(0,.5,0)),Color3.fromRGB(47,54,70),Enum.Material.Slate)
	for _,z in ipairs({-21,21}) do p("DuelWall",Vector3.new(64,8,2),CFrame.new(center+Vector3.new(0,4,z)),Color3.fromRGB(30,35,49),Enum.Material.Slate) end
	for _,x in ipairs({-31,31}) do p("DuelWall",Vector3.new(2,8,44),CFrame.new(center+Vector3.new(x,4,0)),Color3.fromRGB(30,35,49),Enum.Material.Slate) end
	local line=p("DuelCenterLine",Vector3.new(.18,.08,36),CFrame.new(center+Vector3.new(0,1.04,0)),Color3.fromRGB(139,88,255),Enum.Material.Neon,.18); line.CanCollide=false
	for _,x in ipairs({-20,20}) do
		local spawn=p("DuelSpawnRune",Vector3.new(.14,8,8),CFrame.new(center+Vector3.new(x,1.03,0))*CFrame.Angles(0,0,math.rad(90)),Color3.fromRGB(87,202,242),Enum.Material.Neon,.55)
		spawn.Shape=Enum.PartType.Cylinder; spawn.CanCollide=false
	end
	for _,x in ipairs({-27,27}) do for _,z in ipairs({-17,17}) do
		local pillar=p("DuelPillar",Vector3.new(3.2,9,3.2),CFrame.new(center+Vector3.new(x,4.5,z)),Color3.fromRGB(69,72,91),Enum.Material.Metal)
		local light=Instance.new("PointLight"); light.Color=Color3.fromRGB(139,88,255); light.Brightness=.7; light.Range=12; light.Parent=pillar
	end end
end

local SYNTY = {
	Floor = "DungeonFloorTile",
	Archway = "DungeonArchway",
	Pillar = "DungeonPillar",
	RoundPillar = "DungeonRoundPillar",
	RunePillar = "DungeonRunePillar",
	Torch = "DungeonTorch",
	RuneBlade = "RuneBladeTemplate",
	TechCrystal = "TechCrystalTemplate",
	EnemySword = "EnemySwordTemplate",
	EnemyShield = "EnemyShieldTemplate",
	VanguardChest = "VanguardChestTemplate",
	VanguardLeftPauldron = "VanguardLeftPauldronTemplate",
	VanguardRightPauldron = "VanguardRightPauldronTemplate",
	VanguardMantle = "VanguardMantleTemplate",
}

local assetTemplates = ServerStorage:WaitForChild("RIFT_Assets_v0_40")

local function meshPart(parent, name, templateName, size, cf)
	local source = assetTemplates:FindFirstChild(templateName)
	assert(source and source:IsA("MeshPart"), "Missing visual template: "..templateName)
	local p = source:Clone()
	p.Name = name
	p.Size = size
	p.CFrame = cf
	if name == "SyntyFloor" then p.Color = Color3.fromRGB(112,118,132)
	elseif name == "SyntyWall" then p.Color = Color3.fromRGB(82,91,111)
	elseif name == "SyntyPillar" or name == "CentralPillarVisual" then p.Color = Color3.fromRGB(65,72,91)
	elseif name == "SyntyArenaArch" or name == "SyntyRoundPillar" then p.Color = Color3.fromRGB(74,80,101)
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = true
	
	p.Parent = parent
	return p
end

local function buildCombatRoom(worldRoot)
	for _,name in ipairs({"CombatVisual_v0_40", "CombatVisual_v0_41", "CombatVisual_v0_42", "CombatVisual_v0_43", "CombatVisual_v0_44"}) do
		local old = worldRoot:FindFirstChild(name)
		if old then old:Destroy() end
	end
	local greybox = worldRoot:FindFirstChild("Mission")
	if greybox then
		for _,d in ipairs(greybox:GetDescendants()) do
			if d:IsA("BasePart") then d.Transparency=1; d.CanCollide=false
			elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then d.Enabled=false end
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "CombatVisual_v0_44"
	folder:SetAttribute("AssetPack", "Synty Dungeon Pack: Cave & Castle Interiors")
	folder:SetAttribute("AssetId", 6934021345)
	folder.Parent = worldRoot

	local centerZ = -420
	-- Imported meshes remain visual-only. Simple invisible proxies provide stable,
	-- predictable player and projectile collision without relying on mesh fidelity.
	local function collisionProxy(name, size, cf)
		local proxy = Instance.new("Part")
		proxy.Name = name
		proxy.Size = size
		proxy.CFrame = cf
		proxy.Transparency = 1
		proxy.Anchored = true
		proxy.CanCollide = true
		proxy.CanTouch = false
		proxy.CanQuery = true
		proxy.CastShadow = false
		proxy.Parent = folder
		return proxy
	end
	local underlay = Instance.new("Part")
	underlay.Name = "ArenaCollision"
	underlay.Size = Vector3.new(82, 1, 92)
	underlay.CFrame = CFrame.new(0, -0.05, centerZ)
	underlay.Transparency = 1
	underlay.Anchored = true
	underlay.CanCollide = true
	underlay.Parent = folder

	-- A mid-value arena bed preserves silhouettes even when imported mesh textures are dark.
	local arenaBed=Instance.new("Part")
	arenaBed.Name="ArenaBed"; arenaBed.Size=Vector3.new(80,.35,90); arenaBed.CFrame=CFrame.new(0,.2,centerZ)
	arenaBed.Color=Color3.fromRGB(50,59,75); arenaBed.Material=Enum.Material.Slate
	arenaBed.Anchored=true; arenaBed.CanCollide=false; arenaBed.CastShadow=false; arenaBed.Parent=folder
	-- The central column is tactical cover: Archer arrows cannot pass through it.
	local cover = Instance.new("Part")
	cover.Name = "CentralPillarCollision"
	cover.Size = Vector3.new(6, 10, 6)
	cover.CFrame = CFrame.new(0, 5.2, centerZ-2)
	cover.Color = Color3.fromRGB(84, 88, 103)
	cover.Material = Enum.Material.Slate
	cover.Anchored = true
	cover.CanCollide = true
	cover.Parent = folder
	meshPart(folder,"CentralPillarVisual",SYNTY.Pillar,Vector3.new(6.2,12,6.2),cover.CFrame)
	for _,x in ipairs({-18,18}) do
		local lane=Instance.new("Part")
		lane.Name="CombatLaneGuide"; lane.Size=Vector3.new(.18,.08,78); lane.CFrame=CFrame.new(x,.62,centerZ)
		lane.Color=Color3.fromRGB(76,173,207); lane.Material=Enum.Material.Neon; lane.Transparency=.48
		lane.Anchored=true; lane.CanCollide=false; lane.CastShadow=false; lane.Parent=folder
	end

	-- Real Synty mesh tiles form the visible floor; the transparent underlay owns collision.
	for x = -30, 30, 20 do
		for z = centerZ - 40, centerZ + 40, 20 do
			meshPart(folder, "SyntyFloor", SYNTY.Floor,
				Vector3.new(20,20,0.05), CFrame.new(x,0.52,z) * CFrame.Angles(math.rad(90),0,0))
		end
	end

	-- Side walls, pillars and a large destination arch establish a readable combat nave.
	for _, side in ipairs({-1,1}) do
		for z = centerZ - 40, centerZ + 40, 20 do
			meshPart(folder,"SyntyWall",SYNTY.Floor,
				Vector3.new(20,20,0.05),CFrame.new(side*41,10,z)*CFrame.Angles(0,math.rad(90),0))
		end
		collisionProxy("ArenaWallCollision",Vector3.new(2.2,22,92),CFrame.new(side*41,11,centerZ))
		for z = centerZ - 34, centerZ + 34, 17 do
			meshPart(folder,"SyntyPillar",SYNTY.Pillar,
				Vector3.new(5.2,18.8,5.2),CFrame.new(side*37.5,9.4,z))
			collisionProxy("WallPillarCollision",Vector3.new(4.4,18.5,4.4),CFrame.new(side*37.5,9.25,z))
		end
		for z = centerZ - 25, centerZ + 25, 25 do
			local rune=meshPart(folder,"SyntyRunePillar",SYNTY.RunePillar,
				Vector3.new(3.5,8.3,3.5),CFrame.new(side*31,4.2,z)*CFrame.Angles(0,math.rad(side*18),0))
			collisionProxy("RunePillarCollision",Vector3.new(2.8,8,2.8),CFrame.new(side*31,4,z))
			local light=Instance.new("PointLight")
			light.Color=Color3.fromRGB(72,205,255); light.Brightness=.9; light.Range=12; light.Parent=rune
		end
	end

	meshPart(folder,"SyntyArenaArch",SYNTY.Archway,
		Vector3.new(28,20,3.5),CFrame.new(0,10,centerZ-44))
	for _, x in ipairs({-14,14}) do
		meshPart(folder,"SyntyRoundPillar",SYNTY.RoundPillar,
			Vector3.new(6.2,21.4,6.2),CFrame.new(x,10.7,centerZ-43))
		collisionProxy("RoundPillarCollision",Vector3.new(5.2,21,5.2),CFrame.new(x,10.5,centerZ-43))
	end
	-- End caps prevent leaving the authored arena through the decorative arch or
	-- the mission spawn edge. They sit just outside the visible floor footprint.
	collisionProxy("ArenaEndCollision",Vector3.new(82,22,2.2),CFrame.new(0,11,centerZ-46))
	collisionProxy("ArenaEndCollision",Vector3.new(82,22,2.2),CFrame.new(0,11,centerZ+46))

	-- Official Synty torch meshes provide warm navigation light without filling the center.
	for _,side in ipairs({-1,1}) do
		for _,z in ipairs({centerZ-24,centerZ,centerZ+24}) do
			local torch=meshPart(folder,"SyntyTorch",SYNTY.Torch,
				Vector3.new(1.3,4.6,1.3),CFrame.new(side*35,5,z)*CFrame.Angles(0,0,math.rad(side*8)))
			local flame=Instance.new("PointLight")
			flame.Color=Color3.fromRGB(255,166,70); flame.Brightness=1.45; flame.Range=15; flame.Shadows=true; flame.Parent=torch
		end
	end

	-- Edge runes frame the play space while keeping the telegraph area clean.
	for _,x in ipairs({-27,27}) do
		for _,z in ipairs({centerZ-31,centerZ+31}) do
			local rune=Instance.new("Part")
			rune.Name="ArenaRune"; rune.Size=Vector3.new(.12,8,8); rune.Shape=Enum.PartType.Cylinder
			rune.CFrame=CFrame.new(x,.62,z)*CFrame.Angles(0,0,math.rad(90))
			rune.Material=Enum.Material.Neon; rune.Color=Color3.fromRGB(74,196,255); rune.Transparency=.58
			rune.Anchored=true; rune.CanCollide=false; rune.Parent=folder
		end
	end
	-- A broken nave roof removes the default-skybox look while preserving a bright rift skylight.
	for _,side in ipairs({-1,1}) do
		local canopy=Instance.new("Part")
		canopy.Name="SanctumCanopy"; canopy.Size=Vector3.new(35,.7,92)
		canopy.CFrame=CFrame.new(side*23,26.5,centerZ); canopy.Color=Color3.fromRGB(24,29,42)
		canopy.Material=Enum.Material.Slate; canopy.Anchored=true; canopy.CanCollide=false; canopy.CastShadow=false; canopy.Parent=folder
		local innerGlow=Instance.new("Part")
		innerGlow.Name="SkylightEdge"; innerGlow.Size=Vector3.new(.22,.16,88)
		innerGlow.CFrame=CFrame.new(side*5.4,26.05,centerZ); innerGlow.Color=side<0 and Color3.fromRGB(65,208,242) or Color3.fromRGB(194,76,222)
		innerGlow.Material=Enum.Material.Neon; innerGlow.Transparency=.24; innerGlow.Anchored=true; innerGlow.CanCollide=false; innerGlow.CastShadow=false; innerGlow.Parent=folder
	end
	for _,z in ipairs({centerZ-38,centerZ-19,centerZ,centerZ+19,centerZ+38}) do
		local rib=Instance.new("Part")
		rib.Name="SanctumRoofRib"; rib.Size=Vector3.new(82,1.15,1.6); rib.CFrame=CFrame.new(0,25.8,z)
		rib.Color=Color3.fromRGB(42,48,64); rib.Material=Enum.Material.Metal
		rib.Anchored=true; rib.CanCollide=false; rib.CastShadow=false; rib.Parent=folder
	end

	-- A restrained destination rift gives the room a focal point and a portfolio-ready silhouette.
	local portalCenter=Vector3.new(0,11,centerZ-45.6)
	local portalCore=Instance.new("Part")
	portalCore.Name="SanctumRiftCore"; portalCore.Size=Vector3.new(14.5,14.5,.38)
	portalCore.CFrame=CFrame.new(portalCenter); portalCore.Material=Enum.Material.Neon
	portalCore.Color=Color3.fromRGB(45,202,235); portalCore.Transparency=.38
	portalCore.Anchored=true; portalCore.CanCollide=false; portalCore.CanTouch=false; portalCore.CastShadow=false; portalCore.Parent=folder
	local portalLight=Instance.new("PointLight")
	portalLight.Color=Color3.fromRGB(90,188,255); portalLight.Brightness=1.15; portalLight.Range=28; portalLight.Shadows=true; portalLight.Parent=portalCore
	for index=1,20 do
		local angle=(index/20)*math.pi*2
		local segment=Instance.new("Part")
		segment.Name="SanctumRiftSegment"; segment.Size=Vector3.new(.7,3.1,.7)
		segment.Material=Enum.Material.Neon
		segment.Color=index%3==0 and Color3.fromRGB(225,75,196) or Color3.fromRGB(76,210,246)
		segment.Transparency=index%2==0 and .12 or .24; segment.Anchored=true
		segment.CanCollide=false; segment.CanTouch=false; segment.CastShadow=false
		segment.CFrame=CFrame.new(portalCenter)*CFrame.Angles(0,0,angle)*CFrame.new(0,9.1,0)*CFrame.Angles(0,0,angle)
		segment.Parent=folder
	end
	for _,zOffset in ipairs({-17,8,31}) do
		local floorRune=Instance.new("Part")
		floorRune.Name="SanctumFloorRune"; floorRune.Shape=Enum.PartType.Cylinder
		floorRune.Size=Vector3.new(.08,13,13); floorRune.CFrame=CFrame.new(0,.66,centerZ+zOffset)*CFrame.Angles(0,0,math.rad(90))
		floorRune.Material=Enum.Material.Neon; floorRune.Color=Color3.fromRGB(86,187,231); floorRune.Transparency=.72
		floorRune.Anchored=true; floorRune.CanCollide=false; floorRune.CanTouch=false; floorRune.CastShadow=false; floorRune.Parent=folder
	end
	print("[RIFT] Combat Room v0.44 ready — environment collision pass active")
end

local function equipRiftVanguard(character)
	local old = character:FindFirstChild("RiftVanguardArmor")
	if old then old:Destroy() end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("Clothing") or child:IsA("ShirtGraphic") then child:Destroy() end
	end
	local head = character:FindFirstChild("Head")
	if head then
		local face = head:FindFirstChildOfClass("Decal")
		if face then face.Transparency = 1 end
	end

	local armor = Instance.new("Model")
	armor.Name = "RiftVanguardArmor"
	armor.Parent = character
	local obsidian = Color3.fromRGB(29,35,49)
	local plate = Color3.fromRGB(67,78,99)
	local edge = Color3.fromRGB(132,149,176)
	local cyan = Color3.fromRGB(78,205,235)
	local violet = Color3.fromRGB(116,72,202)

	local function armorPart(name, body, size, offset, color, material, shape)
		if not body then return nil end
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.Metal
		p.Shape = shape or Enum.PartType.Block
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
		p.Massless = true; p.Anchored = false; p.CastShadow = true
		p.CFrame = body.CFrame * offset
		p.Parent = armor
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body; weld.Part1 = p; weld.Parent = p
		return p
	end
	local function armorWedge(name, body, size, offset, color, material)
		if not body then return nil end
		local p=Instance.new("WedgePart")
		p.Name=name; p.Size=size; p.Color=color; p.Material=material or Enum.Material.Metal
		p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
		p.CanCollide=false; p.CanTouch=false; p.CanQuery=false
		p.Massless=true; p.Anchored=false; p.CastShadow=true
		p.CFrame=body.CFrame*offset; p.Parent=armor
		local weld=Instance.new("WeldConstraint"); weld.Part0=body; weld.Part1=p; weld.Parent=p
		return p
	end
	local function armorMesh(name,templateName,body,size,offset)
		if not body then return nil end
		local source=assetTemplates:FindFirstChild(templateName)
		if not source or not source:IsA("MeshPart") then return nil end
		local p=source:Clone()
		p.Name=name; p.Size=size; p.Color=Color3.new(1,1,1)
		p.CanCollide=false; p.CanTouch=false; p.CanQuery=false
		p.Massless=true; p.Anchored=false; p.CastShadow=true
		p.CFrame=body.CFrame*offset; p.Parent=armor
		local weld=Instance.new("WeldConstraint"); weld.Part0=body; weld.Part1=p; weld.Parent=p
		return p
	end

	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local lowerTorso = character:FindFirstChild("LowerTorso") or torso
	local leftArm = character:FindFirstChild("LeftUpperArm") or character:FindFirstChild("Left Arm")
	local rightArm = character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm")
	local leftForearm = character:FindFirstChild("LeftLowerArm") or leftArm
	local rightForearm = character:FindFirstChild("RightLowerArm") or rightArm
	local leftLeg = character:FindFirstChild("LeftLowerLeg") or character:FindFirstChild("Left Leg")
	local rightLeg = character:FindFirstChild("RightLowerLeg") or character:FindFirstChild("Right Leg")
	local leftUpperLeg = character:FindFirstChild("LeftUpperLeg") or character:FindFirstChild("Left Leg")
	local rightUpperLeg = character:FindFirstChild("RightUpperLeg") or character:FindFirstChild("Right Leg")

	-- Normalize the visible rig beneath the armor so default avatar colors and
	-- clothing never break the Vanguard silhouette after a respawn.
	for _,body in ipairs(character:GetChildren()) do
		if body:IsA("BasePart") and body.Name~="HumanoidRootPart" then
			body.Color=Color3.fromRGB(34,39,53)
			body.Material=Enum.Material.SmoothPlastic
		end
	end

	armorPart("ChestUnderplate", torso, Vector3.new(1.58,1.64,.3), CFrame.new(0,.1,-.61), obsidian)
	armorMesh("VanguardChest",SYNTY.VanguardChest,torso,Vector3.new(1.92,1.32,.77),CFrame.new(0,.15,-.72))
	armorWedge("LeftChestBevel",torso,Vector3.new(.52,1.78,.42),CFrame.new(-1.02,.12,-.68)*CFrame.Angles(0,math.rad(180),0),plate)
	armorWedge("RightChestBevel",torso,Vector3.new(.52,1.78,.42),CFrame.new(1.02,.12,-.68),plate)
	armorPart("ChestV", torso, Vector3.new(.48,1.12,.14), CFrame.new(0,.18,-.94)*CFrame.Angles(0,0,math.rad(45)), edge)
	local core = armorPart("VanguardCore", torso, Vector3.new(.48,.48,.24), CFrame.new(0,.05,-1.22)*CFrame.Angles(math.rad(90),0,0), cyan, Enum.Material.Neon, Enum.PartType.Cylinder)
	if core then local light=Instance.new("PointLight"); light.Color=cyan; light.Brightness=.8; light.Range=7; light.Parent=core end
	armorPart("WaistGuard", lowerTorso, Vector3.new(1.95,.46,1.04), CFrame.new(0,-.52,0), obsidian)
	armorMesh("LeftPauldron",SYNTY.VanguardLeftPauldron,leftArm,Vector3.new(.94,1.16,1.16),CFrame.new(0,.48,0))
	armorMesh("RightPauldron",SYNTY.VanguardRightPauldron,rightArm,Vector3.new(.94,1.16,1.16),CFrame.new(0,.48,0))
	armorPart("LeftBracer", leftForearm, Vector3.new(.84,1.35,.88), CFrame.new(0,-.05,0), obsidian)
	armorPart("RightBracer", rightForearm, Vector3.new(.84,1.35,.88), CFrame.new(0,-.05,0), obsidian)
	armorPart("LeftBracerRune", leftForearm, Vector3.new(.9,.16,.96), CFrame.new(0,.18,-.08), violet, Enum.Material.Neon)
	armorPart("RightBracerRune", rightForearm, Vector3.new(.9,.16,.96), CFrame.new(0,.18,-.08), cyan, Enum.Material.Neon)
	armorPart("LeftCuisses", leftUpperLeg, Vector3.new(.96,1.4,1.02), CFrame.new(0,.04,0), obsidian)
	armorPart("RightCuisses", rightUpperLeg, Vector3.new(.96,1.4,1.02), CFrame.new(0,.04,0), obsidian)
	armorPart("LeftGreave", leftLeg, Vector3.new(.88,1.45,.98), CFrame.new(0,-.2,-.04), plate)
	armorPart("RightGreave", rightLeg, Vector3.new(.88,1.45,.98), CFrame.new(0,-.2,-.04), plate)
	armorPart("LeftGreaveTrim", leftLeg, Vector3.new(.94,.2,1.04), CFrame.new(0,.34,-.04), edge)
	armorPart("RightGreaveTrim", rightLeg, Vector3.new(.94,.2,1.04), CFrame.new(0,.34,-.04), edge)
	if head then
		armorPart("HelmBrow",head,Vector3.new(1.82,.34,1.82),CFrame.new(0,.48,0),plate)
		armorPart("FaceMask", head, Vector3.new(1.42,.68,.24), CFrame.new(0,-.22,-.98), plate)
		armorWedge("LeftCheekGuard",head,Vector3.new(.34,.76,.34),CFrame.new(-.7,-.17,-.87)*CFrame.Angles(0,math.rad(180),0),obsidian)
		armorWedge("RightCheekGuard",head,Vector3.new(.34,.76,.34),CFrame.new(.7,-.17,-.87),obsidian)
		armorPart("Visor", head, Vector3.new(1.18,.13,.1), CFrame.new(0,.02,-1.12), cyan, Enum.Material.Neon)
		armorWedge("HelmCrown",head,Vector3.new(.42,.9,1.34),CFrame.new(0,.98,.12)*CFrame.Angles(math.rad(-8),0,0),obsidian)
		armorPart("RearVisor", head, Vector3.new(1.3,.11,.1), CFrame.new(0,.24,1.03), violet, Enum.Material.Neon)
	end
	armorMesh("VanguardMantle",SYNTY.VanguardMantle,torso,Vector3.new(2.45,2.75,.58),CFrame.new(0,-.42,.8))
	armorPart("BackSpine", torso, Vector3.new(.18,1.48,.12), CFrame.new(0,.08,1.12), cyan, Enum.Material.Neon)
	armorPart("CapeClaspLeft", torso, Vector3.new(.38,.38,.15), CFrame.new(-.73,.7,1.12)*CFrame.Angles(math.rad(90),0,0), violet, Enum.Material.Neon, Enum.PartType.Cylinder)
	armorPart("CapeClaspRight", torso, Vector3.new(.38,.38,.15), CFrame.new(.73,.7,1.12)*CFrame.Angles(math.rad(90),0,0), violet, Enum.Material.Neon, Enum.PartType.Cylinder)
	armorPart("CapeSigil", torso, Vector3.new(.52,.52,.12), CFrame.new(0,.15,1.16)*CFrame.Angles(math.rad(90),0,0), violet, Enum.Material.Neon, Enum.PartType.Cylinder)
	character:SetAttribute("CombatFrame", "RiftVanguard_v4")
end

local function equipRuneBlade(character)
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or character:FindFirstChild("RuneBlade") then return end
	local blade = assetTemplates:WaitForChild(SYNTY.RuneBlade):Clone()
	blade.Name = "RuneBlade"
	blade.Size = Vector3.new(.31,4.75,.88)
	blade.Material = Enum.Material.Metal
	blade.Anchored = false
	blade.CanCollide = false
	blade.CanTouch = false
	blade.Massless = true
	blade.CastShadow = true
	blade.Parent = character

	local motor = Instance.new("Motor6D")
	motor.Name = "RuneBladeGrip"
	motor.Part0 = hand
	motor.Part1 = blade
	motor.C0 = CFrame.new(0,-1.55,-.08) * CFrame.Angles(0,0,math.rad(-5))
	motor.Parent = hand

	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBase"; a0.Position = Vector3.new(0,-1.75,0); a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailTip"; a1.Position = Vector3.new(0,2.15,0); a1.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "RuneTrail"; trail.Attachment0 = a0; trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(74,210,255))
	trail.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,.06),NumberSequenceKeypoint.new(1,1)})
	trail.Lifetime = .13; trail.MinLength = .08; trail.LightEmission = .9; trail.Enabled = false; trail.Parent = blade
	local light=Instance.new("PointLight")
	light.Color=Color3.fromRGB(78,203,255); light.Brightness=.55; light.Range=7; light.Parent=blade
	blade:SetAttribute("AssetName","Crystal Ornate Straightsword")
	blade:SetAttribute("Creator","Roblox / Synty")
	blade:SetAttribute("SourceAssetId",6933790012)
end

local Root = ReplicatedStorage:WaitForChild("RIFT")
local Config = Root:WaitForChild("Config")
local Remotes = Root:WaitForChild("Remotes")

local Balance = require(Config:WaitForChild("Balance"))
local PlayerConfig = require(Config:WaitForChild("Player"))
local Skills = require(Config:WaitForChild("Skills"))
local Enemies = require(Config:WaitForChild("Enemies"))
local Progression = require(Config:WaitForChild("Progression"))
local GameConfig = require(Config:WaitForChild("Game"))
local Monetization = GameConfig.Monetization or {}

local Action = Remotes:WaitForChild("Action")
local State = Remotes:WaitForChild("State")
local Snapshot = Remotes:WaitForChild("Snapshot")

local world = Workspace:WaitForChild("RIFT_WORLD")
retireLegacyWorld(world)
buildLobbyHero(world)
buildCombatRoom(world)
buildDuelArena(world)
for _, check in ipairs({
	{label = "LOBBY", origin = Vector3.new(0, 12, 15), expectedMaxY = 1},
	{label = "MISSION", origin = Vector3.new(0, 12, -380), expectedMaxY = 1},
}) do
	local hit = Workspace:Raycast(check.origin, Vector3.new(0, -20, 0))
	if not hit or hit.Position.Y > check.expectedMaxY then
		warn("[RIFT][WORLD] Invalid ", check.label, " ground: ", hit and hit.Instance:GetFullName() or "none", hit and hit.Position.Y or "none")
	else
		print(string.format("[RIFT][WORLD] %s ground=%.2f (%s)", check.label, hit.Position.Y, hit.Instance.Name))
	end
end
local missionRoot = world:WaitForChild("Mission")
local missionEnemies = missionRoot:WaitForChild("Enemies")

local store
pcall(function()
	if not RunService:IsStudio() then
        store = DataStoreService:GetDataStore("RIFT_PROTOCOL_PUBLIC_ALPHA_V1")
    end
end)

if RunService:IsStudio() then
    print("[RIFT] Studio memory-only profile: live DataStore access disabled.")
end

local profiles = {}
local sessions = {}
local duelQueue = {}
local function removeFromDuelQueue(player)
	for i=#duelQueue,1,-1 do
		if duelQueue[i]==player or not duelQueue[i].Parent then table.remove(duelQueue,i) end
	end
end
local cooldowns = {}
local combos = {}
local stamina = {}

-- Chapter-one permanent loot. The server owns rolls, inventory and equipment;
-- clients only request an equip operation by definition id.
local WEAPONS = {
	InitiateBlade = {Id="InitiateBlade", Name="INITIATE RIFTBLADE", Rarity="COMMON", ATK=0, Color={164,174,194}},
	CinderEdge = {Id="CinderEdge", Name="CINDER EDGE", Rarity="UNCOMMON", ATK=8, Color={93,210,133}},
	GraveOath = {Id="GraveOath", Name="GRAVE OATH", Rarity="RARE", ATK=12, Color={86,157,255}},
	Riftcarver = {Id="Riftcarver", Name="RIFTCARVER", Rarity="RARE", ATK=16, Color={86,157,255}},
	WardenFang = {Id="WardenFang", Name="WARDEN'S FANG", Rarity="EPIC", ATK=22, Color={175,102,255}},
	EclipseBrand = {Id="EclipseBrand", Name="ECLIPSE BRAND", Rarity="LEGENDARY", ATK=30, Color={255,185,76}},
}
local BOSS_DROP_TABLE = {
	{Id="CinderEdge", Weight=44}, {Id="GraveOath", Weight=27}, {Id="Riftcarver", Weight=18},
	{Id="WardenFang", Weight=9}, {Id="EclipseBrand", Weight=2},
}
local LEVEL_XP = {0, 140, 493, 1105, 2337, 3900, 5800, 8050, 10650, 13600}

local DEFAULT = {
	Credits = 300,
	Shards = 0,
	Mastery = 0,
	CoreLevel = 0,
	Clears = 0,
	BestTime = 0,
	XP = 0,
	Inventory = {"InitiateBlade"},
	EquippedWeapon = "InitiateBlade",
	PreferredDifficulty = "NORMAL",
	QuestKills = 0,
	QuestClaimed = false,
}

local function cloneTable(t)
	local n = {}
	for k,v in pairs(t) do n[k] = type(v) == "table" and cloneTable(v) or v end
	return n
end

local function levelFromXP(xp)
	local level = 1
	for i=2,#LEVEL_XP do if xp >= LEVEL_XP[i] then level=i else break end end
	return level
end

local function ownsWeapon(data, weaponId)
	for _,id in ipairs(data.Inventory or {}) do if id == weaponId then return true end end
	return false
end

local function weaponPublic(id)
	local w = WEAPONS[id] or WEAPONS.InitiateBlade
	return {Id=w.Id, Name=w.Name, Rarity=w.Rarity, ATK=w.ATK, Color=w.Color}
end

local function computeStats(data)
	local base = PlayerConfig.Base
	local hpBonus, atkBonus, defBonus = 0, 0, 0

	for i = 1, math.min(data.Mastery or 0, #Progression.Mastery) do
		local node = Progression.Mastery[i]
		hpBonus += node.HP
		atkBonus += node.ATK
		defBonus += node.DEF
	end

	local coreATK = 0
	if (data.CoreLevel or 0) > 0 then
		coreATK = Progression.AssaultCoreATK[data.CoreLevel] or 0
	end
	local weaponATK = (WEAPONS[data.EquippedWeapon or "InitiateBlade"] or WEAPONS.InitiateBlade).ATK

	local stats = {
		Level = base.Level,
		ATK = base.ATK + atkBonus + coreATK + weaponATK,
		DEF = base.DEF + defBonus,
		HP = base.HP + hpBonus,
		CritChance = base.CritChance,
		CritDamage = base.CritDamage,
	}

	stats.CR =
		stats.ATK * Balance.CombatRating.ATKWeight
		+ stats.DEF * Balance.CombatRating.DEFWeight
		+ stats.HP * Balance.CombatRating.HPWeight

	return stats
end

local function publicProfile(player)
	local data = profiles[player] or DEFAULT
	local stats = computeStats(data)
	return {
		Credits = data.Credits,
		Shards = data.Shards,
		Mastery = data.Mastery,
		CoreLevel = data.CoreLevel,
		Clears = data.Clears,
		BestTime = data.BestTime,
		XP = data.XP or 0,
		Level = levelFromXP(data.XP or 0),
		XPToNext = LEVEL_XP[math.min(#LEVEL_XP, levelFromXP(data.XP or 0)+1)],
		EquippedWeapon = weaponPublic(data.EquippedWeapon),
		Inventory = (function()
			local list = {}
			for _,id in ipairs(data.Inventory or {}) do table.insert(list, weaponPublic(id)) end
			return list
		end)(),
		Difficulty = data.PreferredDifficulty or "NORMAL",
		Quest = {Id="FirstDirective", Title="FIRST DIRECTIVE", Current=data.QuestKills or 0, Target=12, Claimed=data.QuestClaimed == true, RewardCredits=180, RewardShards=1},
		Support = {Founder=player:GetAttribute("FounderPassOwned")==true, Cosmetic=player:GetAttribute("CosmeticPassOwned")==true},
		Stats = stats,
	}
end

local function pushProfile(player)
	State:FireClient(player, "Profile", publicProfile(player))
end

local function refreshSupportEntitlements(player)
	for _,entry in ipairs({
		{Id=Monetization.FounderPassId or 0,Attribute="FounderPassOwned"},
		{Id=Monetization.CosmeticPassId or 0,Attribute="CosmeticPassOwned"},
	}) do
		local owned=false
		if entry.Id>0 then
			local ok,result=pcall(MarketplaceService.UserOwnsGamePassAsync,MarketplaceService,player.UserId,entry.Id)
			owned=ok and result==true
		end
		player:SetAttribute(entry.Attribute,owned)
	end
	if profiles[player] then pushProfile(player) end
end

if (Monetization.FounderPassId or 0)>0 or (Monetization.CosmeticPassId or 0)>0 then
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player,passId,purchased)
		if not purchased then return end
		if passId==Monetization.FounderPassId then player:SetAttribute("FounderPassOwned",true)
		elseif passId==Monetization.CosmeticPassId then player:SetAttribute("CosmeticPassOwned",true)
		else return end
		pushProfile(player)
		State:FireClient(player,"SupportCelebration",{Founder=passId==Monetization.FounderPassId})
	end)
end

if (Monetization.SupporterTipProductId or 0)>0 then
	MarketplaceService.ProcessReceipt=function(receipt)
		if receipt.ProductId~=Monetization.SupporterTipProductId then return Enum.ProductPurchaseDecision.NotProcessedYet end
		local player=Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
		State:FireClient(player,"SupportCelebration",{Tip=true})
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
end

local function applyStats(player, refill)
	local data = profiles[player]
	if not data then return end
	local stats = computeStats(data)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local session = sessions[player]
		local hpScale = session and session.InMission and session.Runes and session.Runes.BloodPact and .85 or 1
		humanoid.MaxHealth = math.floor(stats.HP * hpScale + 0.5)
		if refill then
			humanoid.Health = humanoid.MaxHealth
		else
			humanoid.Health = math.min(humanoid.Health, humanoid.MaxHealth)
		end
	end
end

local function applyWeaponAppearance(player)
	local data = profiles[player]
	local character = player.Character
	local blade = character and character:FindFirstChild("RuneBlade")
	local weapon = data and WEAPONS[data.EquippedWeapon or "InitiateBlade"]
	if not blade or not weapon then return end
	local rgb = weapon.Color
	local color = Color3.fromRGB(rgb[1],rgb[2],rgb[3])
	blade.Color = color
	blade:SetAttribute("WeaponId", weapon.Id)
	blade:SetAttribute("Rarity", weapon.Rarity)
	local trail = blade:FindFirstChildOfClass("Trail")
	if trail then trail.Color = ColorSequence.new(color) end
	local light = blade:FindFirstChildOfClass("PointLight")
	if light then light.Color = color end
end

local function loadProfile(player)
	local data = cloneTable(DEFAULT)
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync("u_" .. player.UserId)
		end)
		if ok and type(saved) == "table" then
			for k,v in pairs(DEFAULT) do
				if saved[k] ~= nil then data[k] = saved[k] end
			end
		end
	end
	profiles[player] = data
	if type(data.Inventory) ~= "table" or #data.Inventory == 0 then data.Inventory = {"InitiateBlade"} end
	if not WEAPONS[data.EquippedWeapon] or not ownsWeapon(data, data.EquippedWeapon) then data.EquippedWeapon = "InitiateBlade" end
	sessions[player] = {InMission = false, Training = false, TrainingStage = 0, InDuel = false, DuelOpponent = 0, DuelPoise = 70, DuelBrokenUntil = 0, Wave = 0, StartTime = 0, Complete = false, Transitioning = false, Runes = {}, Shield = 0, Surge = 0, SurgeUntil = 0, LastPlayerHit = 0, Difficulty = data.PreferredDifficulty or "NORMAL", Report = {Damage=0, Crits=0, Breaks=0, Executions=0, Defeated=0, DamageTaken=0, Dodges=0}}
	cooldowns[player] = {}
	combos[player] = {Step = 1, Last = 0, Next = 0}
	stamina[player] = 100
	player:SetAttribute("Stamina", 100)
end

local function saveProfile(player)
	local data = profiles[player]
	if not data or not store then return end
	pcall(function()
		store:SetAsync("u_" .. player.UserId, data)
	end)
end

local function calculateDamage(stats, coef, enemyDEF)
	local raw = stats.ATK * coef
	local final = raw * Balance.DamageDefenseK / (Balance.DamageDefenseK + enemyDEF)
	local crit = math.random() < stats.CritChance
	if crit then final *= stats.CritDamage end
	return math.floor(final + 0.5), crit
end

local function awardBossDrop(data)
	local roll = math.random(1,100)
	local cursor = 0
	local selected = BOSS_DROP_TABLE[1].Id
	for _,entry in ipairs(BOSS_DROP_TABLE) do
		cursor += entry.Weight
		if roll <= cursor then selected = entry.Id; break end
	end
	local duplicate = ownsWeapon(data, selected)
	local salvage = 0
	if duplicate then
		salvage = 75 + (WEAPONS[selected].ATK * 5)
		data.Credits += salvage
	else
		table.insert(data.Inventory, selected)
		-- Equip an unambiguous upgrade immediately; the Hub still allows cycling.
		local current = WEAPONS[data.EquippedWeapon] or WEAPONS.InitiateBlade
		if WEAPONS[selected].ATK > current.ATK then data.EquippedWeapon = selected end
	end
	local public = weaponPublic(selected)
	public.Duplicate = duplicate
	public.SalvageCredits = salvage
	return public
end

local function createDamageVFX(position, damage, crit, player, target, step)
	State:FireClient(player, "Damage", {
		Position = position,
		Damage = damage,
		Crit = crit,
		Target = target,
		Step = step,
	})
end

local function makeEnemyModel(kind, cfg, position, ownerUserId)
	local model = Instance.new("Model")
	local isNormal = kind ~= "Warden"
	local displayName = cfg.Name
	model.Name = displayName
	model:SetAttribute("Kind", kind)
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("CurrentHP", cfg.HP)
	model:SetAttribute("MaxHP", cfg.HP)
	model:SetAttribute("ATK", cfg.ATK)
	model:SetAttribute("DEF", cfg.DEF)
	model:SetAttribute("MoveSpeed", cfg.MoveSpeed)
	model:SetAttribute("AttackRange", cfg.AttackRange)
	model:SetAttribute("AttackCooldown", cfg.AttackCooldown)
	model:SetAttribute("Telegraph", cfg.Telegraph)
	model:SetAttribute("Role", cfg.Role)
	model:SetAttribute("Poise", cfg.Poise)
	model:SetAttribute("PoiseMax", cfg.Poise)
	model:SetAttribute("BrokenUntil", 0)
	model:SetAttribute("PendingAttackAt", 0)
	if kind == "Warden" then model:SetAttribute("Phase", 1); model:SetAttribute("AttackCount", 0) end
	model:SetAttribute("LastAttack", 0)
	model:SetAttribute("SlowUntil", 0)
	model.Parent = missionEnemies

	local core
	if kind == "Knight" or kind == "Archer" or kind == "Brute" or kind == "Warden" then
		local scale=cfg.Scale
		local armor=kind == "Archer" and Color3.fromRGB(69,76,80) or (kind == "Brute" and Color3.fromRGB(94,82,74) or Color3.fromRGB(72,77,89))
		local armorDark=Color3.fromRGB(39,43,54)
		local corruption=kind == "Warden" and Color3.fromRGB(183,82,196) or Color3.fromRGB(226,82,70)
		core=Instance.new("Part")
		core.Name="RigRoot"; core.Size=Vector3.new(2.5,4.6,1.8)*scale; core.Transparency=1
		core.CFrame=CFrame.new(position.X, position.Y + (scale-1)*2.6, position.Z); core.Anchored=true; core.CanCollide=false; core.CanTouch=false; core.Color=corruption; core.Parent=model
		local function rigPart(namePart,size,c0,color,material,shape)
			c0=CFrame.new(c0.Position*scale)*c0.Rotation
			local p=Instance.new("Part")
			p.Name=namePart; p.Size=size*scale; p.Color=color; p.Material=material or Enum.Material.Metal
			p.Anchored=false; p.Massless=true; p.CanCollide=false; p.CanTouch=false
			if shape then p.Shape=shape end
			p.CFrame=core.CFrame*c0; p.Parent=model
			local joint=Instance.new("Motor6D")
			joint.Name=namePart.."Joint"; joint.Part0=core; joint.Part1=p; joint.C0=c0; joint.Parent=core
			return p,joint
		end
		local torso,torsoJoint=rigPart("ArmoredTorso",Vector3.new(3.2,3.5,1.8),CFrame.new(0,.55,0),armor)
		local head=rigPart("Helmet",Vector3.new(2.25,2.1,2.05),CFrame.new(0,3.2,-.05),armorDark)
		local rightArm=rigPart("SwordArm",Vector3.new(1.05,3.45,1.05),CFrame.new(-2.05,.55,0),armor)
		local leftArm=rigPart("ShieldArm",Vector3.new(1.05,3.45,1.05),CFrame.new(2.05,.55,0),armor)
		local _,rightHip=rigPart("RightLeg",Vector3.new(1.25,3.25,1.35),CFrame.new(-.82,-.9,0),armorDark)
		local _,leftHip=rigPart("LeftLeg",Vector3.new(1.25,3.25,1.35),CFrame.new(.82,-.9,0),armorDark)
		rightHip.Name="RightHip"; leftHip.Name="LeftHip"
		-- Armor plates follow their body segment; no extra lights or emitters.
		local function armorPlate(parent,name,size,offset,color)
			local plate=Instance.new("Part")
			plate.Name=name; plate.Size=size*scale; plate.Color=color; plate.Material=Enum.Material.Metal
			plate.Anchored=false; plate.Massless=true; plate.CanCollide=false; plate.CanTouch=false
			plate.CFrame=parent.CFrame*CFrame.new(offset*scale); plate.Parent=model
			local weld=Instance.new("WeldConstraint"); weld.Part0=parent; weld.Part1=plate; weld.Parent=plate
		end
		local trim=Color3.fromRGB(148,126,92)
		armorPlate(rightArm,"SwordPauldron",Vector3.new(1.5,.85,1.5),Vector3.new(0,1.25,0),trim)
		armorPlate(leftArm,"ShieldPauldron",Vector3.new(1.5,.85,1.5),Vector3.new(0,1.25,0),trim)
		armorPlate(torso,"Breastplate",Vector3.new(2.7,2,.22),Vector3.new(0,.3,-.96),Color3.fromRGB(96,101,115))
		armorPlate(torso,"WaistBelt",Vector3.new(3.3,.35,1.95),Vector3.new(0,-1.35,0),trim)
		armorPlate(head,"HelmetBrow",Vector3.new(2.35,.24,2.1),Vector3.new(0,.38,0),trim)
		local visor=Instance.new("Part")
		visor.Name="CorruptedVisor"; visor.Size=Vector3.new(1.55,.22,.16)*scale; visor.Color=corruption; visor.Material=Enum.Material.Neon
		visor.Anchored=false; visor.Massless=true; visor.CanCollide=false; visor.CFrame=head.CFrame*CFrame.new(Vector3.new(0,.1,-1.08)*scale); visor.Parent=model
		local visorWeld=Instance.new("WeldConstraint"); visorWeld.Part0=head; visorWeld.Part1=visor; visorWeld.Parent=visor
		local chest=Instance.new("Part")
		chest.Name="CorruptionSeal"; chest.Size=Vector3.new(.14,1.2,1.2)*scale; chest.Shape=Enum.PartType.Cylinder
		chest.Color=corruption; chest.Material=Enum.Material.Neon; chest.Transparency=.12
		chest.Anchored=false; chest.Massless=true; chest.CanCollide=false
		chest.CFrame=torso.CFrame*CFrame.new(Vector3.new(0,.15,-.96)*scale)*CFrame.Angles(0,math.rad(90),0); chest.Parent=model
		local chestWeld=Instance.new("WeldConstraint"); chestWeld.Part0=torso; chestWeld.Part1=chest; chestWeld.Parent=chest
		if kind == "Archer" then
			-- A narrow bow silhouette reads differently from the sword/shield Knight.
			for i, pose in ipairs({CFrame.new(0,-1.0,-.8)*CFrame.Angles(0,0,math.rad(-24)), CFrame.new(0,0,-.8), CFrame.new(0,1.0,-.8)*CFrame.Angles(0,0,math.rad(24))}) do
				local bow=Instance.new("Part")
				bow.Name="BowLimb"..i; bow.Size=Vector3.new(.18,1.45,.2)*scale
				bow.Color=Color3.fromRGB(150,116,78); bow.Material=Enum.Material.Wood
				bow.CanCollide=false; bow.Massless=true; bow.CFrame=leftArm.CFrame*pose; bow.Parent=model
				local weld=Instance.new("WeldConstraint"); weld.Part0=leftArm; weld.Part1=bow; weld.Parent=bow
			end
			local stringPart=Instance.new("Part")
			stringPart.Name="BowString"; stringPart.Size=Vector3.new(.045,3.2,.045)*scale
			stringPart.Color=Color3.fromRGB(216,201,169); stringPart.Material=Enum.Material.SmoothPlastic
			stringPart.CanCollide=false; stringPart.Massless=true
			stringPart.CFrame=leftArm.CFrame*CFrame.new(.34,0,-.8); stringPart.Parent=model
			local stringWeld=Instance.new("WeldConstraint"); stringWeld.Part0=leftArm; stringWeld.Part1=stringPart; stringWeld.Parent=stringPart
		else
			local sword=kind == "Brute" and Instance.new("Part") or assetTemplates:WaitForChild(SYNTY.EnemySword):Clone()
			sword.Name=kind == "Brute" and "BulwarkHammer" or "CorruptedSword"
			sword.Size=kind == "Brute" and Vector3.new(.48,5.2,.48)*scale or Vector3.new(.34,4.25,.78)*scale
			sword.Color=kind == "Warden" and Color3.fromRGB(152,107,160) or Color3.fromRGB(112,82,76)
			if kind == "Brute" then sword.Material=Enum.Material.Metal end
			sword.Anchored=false; sword.Massless=true; sword.CanCollide=false
			sword.CFrame=rightArm.CFrame*CFrame.new(Vector3.new(0,-2.45,-.25)*scale); sword.Parent=model
			local swordGrip=Instance.new("Motor6D")
			swordGrip.Name="WeaponGrip"; swordGrip.Part0=rightArm; swordGrip.Part1=sword
			swordGrip.C0=CFrame.new(Vector3.new(0,-2.45,-.25)*scale); swordGrip.Parent=rightArm
			if kind == "Brute" then armorPlate(sword,"HammerHead",Vector3.new(2.8,1.2,1.2),Vector3.new(0,2,0),Color3.fromRGB(83,89,103)) end
			if kind ~= "Brute" then
				local shield=assetTemplates:WaitForChild(SYNTY.EnemyShield):Clone()
				shield.Name="RiftShield"; shield.Size=Vector3.new(2.5,3.1,.55)*scale; shield.Color=armor
				shield.Anchored=false; shield.Massless=true; shield.CanCollide=false
				shield.CFrame=leftArm.CFrame*CFrame.new(Vector3.new(0,-.2,-1)*scale); shield.Parent=model
				local shieldGrip=Instance.new("Motor6D")
				shieldGrip.Name="ShieldGrip"; shieldGrip.Part0=leftArm; shieldGrip.Part1=shield
				shieldGrip.C0=CFrame.new(Vector3.new(0,-.2,-1)*scale)*CFrame.Angles(0,math.rad(90),0); shieldGrip.Parent=leftArm
			end
		end
		if kind == "Warden" then
			armorPlate(head,"CrownCrest",Vector3.new(2.8,.56,2.5),Vector3.new(0,1.05,0),Color3.fromRGB(132,103,102))
			armorPlate(torso,"WardenMantle",Vector3.new(3.8,3.9,.2),Vector3.new(0,-.75,1.08),Color3.fromRGB(74,36,63))
		end
		torsoJoint.Name="ChestJoint"
		model:SetAttribute("FormalVisual","AshenHumanoid_v1")
		model:SetAttribute("Faction","Riftbound")
	else
		core = Instance.new("Part")
		core.Name = "Core"; core.Shape = Enum.PartType.Ball
		core.Size = Vector3.new(3.3,3.3,3.3)*cfg.Scale
		core.Material = Enum.Material.Neon
		core.Color = kind == "Boss" and Color3.fromRGB(255,70,120) or Color3.fromRGB(120,80,255)
		core.Anchored=true; core.CanCollide=false; core.Position=position; core.Parent=model
		local shell=Instance.new("Part")
		shell.Name="Shell"; shell.Size=Vector3.new(7,.65,2.2)*cfg.Scale; shell.Material=Enum.Material.Metal
		shell.Color=Color3.fromRGB(20,26,40); shell.Anchored=true; shell.CanCollide=false; shell.Position=position; shell.Parent=model
		local shell2=shell:Clone(); shell2.Name="Shell2"; shell2.Size=Vector3.new(2.2,.65,7)*cfg.Scale; shell2.Parent=model
	end
	model.PrimaryPart = core

	if not isNormal then
		local light = Instance.new("PointLight")
		light.Color = core.Color
		light.Brightness = kind == "Warden" and 2 or 1.2
		light.Range = kind == "Warden" and 18 or 10
		light.Parent = core
	end

	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = isNormal and .96 or .88
	highlight.OutlineTransparency = isNormal and .22 or .3
	highlight.FillColor = isNormal and Color3.fromRGB(125,38,48) or core.Color
	highlight.OutlineColor = isNormal and Color3.fromRGB(255,112,104) or Color3.new(1,1,1)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.fromOffset(kind == "Boss" and 250 or 150, kind == "Boss" and 58 or 46)
	billboard.StudsOffset = Vector3.new(0, (isNormal and 5.8 or 3.8) * cfg.Scale, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.Adornee = core
	billboard.Parent = core

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1,0,0.38,0)
	name.BackgroundTransparency = 1
	name.Text = displayName
	name.Font = Enum.Font.GothamBold
	name.TextColor3 = Color3.fromRGB(235,240,255)
	name.TextScaled = true
	name.Parent = billboard

	local back = Instance.new("Frame")
	back.Size = UDim2.new(1,0,0.22,0)
	back.Position = UDim2.new(0,0,0.48,0)
	back.BackgroundColor3 = Color3.fromRGB(20,22,32)
	back.BorderSizePixel = 0
	back.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1,1)
	fill.BackgroundColor3 = kind == "Warden" and Color3.fromRGB(255,92,136) or Color3.fromRGB(220,72,84)
	fill.BorderSizePixel = 0
	fill.Parent = back

	local hpText = Instance.new("TextLabel")
	hpText.Name = "HPText"
	hpText.Size = UDim2.new(1,0,0.25,0)
	hpText.Position = UDim2.new(0,0,0.74,0)
	hpText.BackgroundTransparency = 1
	hpText.Font = Enum.Font.GothamMedium
	hpText.TextColor3 = Color3.fromRGB(200,208,230)
	hpText.TextScaled = true
	hpText.Parent = billboard

	local function refresh()
		if not model.Parent then return end
		local hp = model:GetAttribute("CurrentHP") or 0
		local maxhp = model:GetAttribute("MaxHP") or 1
		fill.Size = UDim2.fromScale(math.clamp(hp/maxhp,0,1), 1)
		hpText.Text = string.format("%d / %d", math.max(0, math.floor(hp+0.5)), math.floor(maxhp+0.5))
	end
	model:GetAttributeChangedSignal("CurrentHP"):Connect(refresh)
	refresh()

	return model
end

local function ownedEnemies(player)
	local arr = {}
	for _, enemy in ipairs(missionEnemies:GetChildren()) do
		if enemy:IsA("Model")
			and enemy:GetAttribute("OwnerUserId") == player.UserId
			and (enemy:GetAttribute("CurrentHP") or 0) > 0 then
			table.insert(arr, enemy)
		end
	end
	return arr
end

local function clearOwnedEnemies(player)
	for _, enemy in ipairs(missionEnemies:GetChildren()) do
		if enemy:GetAttribute("OwnerUserId") == player.UserId then
			enemy:Destroy()
		end
	end
end

local function nearestEnemy(player, maxRange)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return nil, math.huge end
	local best, bestDist
	bestDist = math.huge
	for _, enemy in ipairs(ownedEnemies(player)) do
		local core = enemy.PrimaryPart
		if core then
			local d = (root.Position - core.Position).Magnitude
			if d <= maxRange and d < bestDist then
				best, bestDist = enemy, d
			end
		end
	end
	return best, bestDist
end

local function addSurge(player, amount, reason)
	local session=sessions[player]
	if not session or not session.InMission or os.clock() < (session.SurgeUntil or 0) then return end
	session.Surge=math.clamp((session.Surge or 0)+amount,0,100)
	State:FireClient(player,"Surge",{Value=session.Surge,Reason=reason,Ready=session.Surge>=100})
end

local function damageEnemy(player, enemy, coef, hitStep, poiseDamage)
	if not enemy or not enemy.Parent then return false end
	if enemy:GetAttribute("OwnerUserId") ~= player.UserId then return false end
	local hp = enemy:GetAttribute("CurrentHP") or 0
	if hp <= 0 then return false end

	local stats = computeStats(profiles[player])
	local def = enemy:GetAttribute("DEF") or 0
	local damage, crit = calculateDamage(stats, coef, def)
	local now = os.clock()
	if sessions[player] and now < (sessions[player].SurgeUntil or 0) then damage=math.floor(damage*1.35+.5) end
	local runes = (sessions[player] and sessions[player].Runes) or {}
	if now < (enemy:GetAttribute("BrokenUntil") or 0) then
		damage = math.floor(damage * (runes.ShatterSigil and 1.45 or 1.2) + .5)
	end
	if runes.ExecutionMark and hp <= (enemy:GetAttribute("MaxHP") or 1)*.25 then damage = math.floor(damage*1.18+.5) end
	if runes.EmberEdge and hitStep == 3 then damage += 35 end
	if runes.BloodPact and hitStep and hitStep >= 5 then damage = math.floor(damage*1.2+.5) end
	if runes.RiftEcho and hitStep and hitStep >= 5 and math.random() < .2 then damage += math.floor(damage*.35+.5) end
	local newHP = math.max(0, hp - damage)
	enemy:SetAttribute("CurrentHP", newHP)
	local session = sessions[player]
	if session and session.Report then
		session.Report.Damage += damage
		if crit then session.Report.Crits += 1 end
	end
	local bar = enemy.PrimaryPart and enemy.PrimaryPart:FindFirstChild("HealthBar")
	if bar and enemy:GetAttribute("Role") ~= "Boss" then
		bar.Enabled = true
		task.delay(2, function() if bar.Parent then bar.Enabled = false end end)
	end
	enemy:SetAttribute("HitReactUntil", now+.10)
	if poiseDamage and poiseDamage > 0 and now >= (enemy:GetAttribute("BrokenUntil") or 0) then
		local remaining = math.max(0, (enemy:GetAttribute("Poise") or 0) - poiseDamage)
		enemy:SetAttribute("Poise", remaining)
		if remaining == 0 then
			enemy:SetAttribute("BrokenUntil", now+2.2)
			enemy:SetAttribute("PendingAttackAt", 0)
			State:FireClient(player,"Break",{Position=enemy.PrimaryPart.Position,Target=enemy})
			State:FireClient(player,"ExecuteReady",{Position=enemy.PrimaryPart.Position,Target=enemy,Duration=2.2})
			if enemy:GetAttribute("TrainingDummy") then
				State:FireClient(player,"TrainingGuide",{Stage=2,Text="GUARD BROKEN  //  PRESS F TO EXECUTE"})
			end
			addSurge(player,10,"BREAK")
			if session and session.Report then session.Report.Breaks += 1 end
		end
	end
	addSurge(player,crit and 7 or (hitStep and hitStep>=4 and 5 or 3),crit and "CRIT" or "HIT")
	if newHP>0 and newHP <= (enemy:GetAttribute("MaxHP") or 1)*.28 and enemy:GetAttribute("Role")~="Boss" then
		State:FireClient(player,"ExecuteReady",{Position=enemy.PrimaryPart.Position,Target=enemy,Duration=1.2})
	end
	createDamageVFX(enemy.PrimaryPart.Position, damage, crit, player, enemy, hitStep)
	if enemy:GetAttribute("TrainingDummy") then
		if newHP <= 0 then
			if enemy:GetAttribute("Executing") then
				addSurge(player,100,"TRAINING EXECUTION")
				if session then session.TrainingStage=3 end
				State:FireClient(player,"TrainingGuide",{Stage=3,Text="SURGE READY  //  PRESS R TO OVERDRIVE"})
			else
				local executeHP=math.max(1,math.floor((enemy:GetAttribute("MaxHP") or 1)*.2))
				enemy:SetAttribute("CurrentHP",executeHP)
				State:FireClient(player,"ExecuteReady",{Position=enemy.PrimaryPart.Position,Target=enemy,Duration=4})
			end
			task.delay(.45,function()
				if enemy and enemy.Parent then
					enemy:SetAttribute("CurrentHP",enemy:GetAttribute("MaxHP") or 650)
					enemy:SetAttribute("Poise",enemy:GetAttribute("PoiseMax") or 60)
					enemy:SetAttribute("BrokenUntil",0)
				end
			end)
		end
		return true
	end

	if hitStep == 3 and (enemy:GetAttribute("Kind") == "Knight" or enemy:GetAttribute("Kind") == "Archer") then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and enemy.PrimaryPart then
			local delta = enemy.PrimaryPart.Position - root.Position
			local flat = Vector3.new(delta.X,0,delta.Z)
			if flat.Magnitude > .1 then enemy:PivotTo(enemy:GetPivot() + flat.Unit * 3.2) end
		end
	end

	if newHP <= 0 then
		addSurge(player,12,"DEFEAT")
		if session and session.Report then session.Report.Defeated += 1 end
		local data = profiles[player]
		if data and not data.QuestClaimed then
			data.QuestKills = math.min(12, (data.QuestKills or 0) + 1)
			State:FireClient(player, "QuestProgress", {Current=data.QuestKills, Target=12})
			pushProfile(player)
		end
		State:FireClient(player, "EnemyDefeated", {Name = enemy.Name, Position = enemy.PrimaryPart.Position, Remaining = #ownedEnemies(player)})
		task.delay(0.22, function()
			if enemy and enemy.Parent then enemy:Destroy() end
		end)
	end
	return true
end

local function duelOpponentInRange(player,maxRange)
	local session=sessions[player]
	if not session or not session.InDuel then return nil,math.huge end
	local opponent=Players:GetPlayerByUserId(session.DuelOpponent or 0)
	local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local otherRoot=opponent and opponent.Character and opponent.Character:FindFirstChild("HumanoidRootPart")
	local otherHumanoid=opponent and opponent.Character and opponent.Character:FindFirstChildOfClass("Humanoid")
	if not opponent or not root or not otherRoot or not otherHumanoid or otherHumanoid.Health<=0 then return nil,math.huge end
	local distance=(root.Position-otherRoot.Position).Magnitude
	return distance<=maxRange and opponent or nil,distance
end

local function damageDuelOpponent(player,opponent,coef,hitStep,poiseDamage)
	local session=sessions[player]
	local targetSession=sessions[opponent]
	if not session or not targetSession or not session.InDuel or not targetSession.InDuel then return false end
	if session.DuelOpponent~=opponent.UserId or targetSession.DuelOpponent~=player.UserId then return false end
	local character=opponent.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	local root=character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health<=0 or not root then return false end
	local now=os.clock()
	local damage=math.floor((50*coef)*Balance.DamageDefenseK/(Balance.DamageDefenseK+20)+.5)
	local crit=math.random()<.1
	if crit then damage=math.floor(damage*1.5+.5) end
	if now<(targetSession.DuelBrokenUntil or 0) then damage=math.floor(damage*1.18+.5) end
	if now<(session.SurgeUntil or 0) then damage=math.floor(damage*1.25+.5) end
	humanoid:TakeDamage(damage)
	createDamageVFX(root.Position+Vector3.new(0,2,0),damage,crit,player,character,hitStep)
	State:FireClient(opponent,"PlayerHit",{Damage=damage,Shielded=0,Duel=true})
	addSurge(player,crit and 7 or (hitStep and hitStep>=4 and 5 or 3),crit and "CRIT" or "HIT")
	if poiseDamage and poiseDamage>0 and now>=(targetSession.DuelBrokenUntil or 0) then
		targetSession.DuelPoise=math.max(0,(targetSession.DuelPoise or 70)-poiseDamage)
		if targetSession.DuelPoise==0 then
			targetSession.DuelBrokenUntil=now+1.8
			targetSession.DuelPoise=70
			addSurge(player,10,"DUEL BREAK")
			State:FireClient(player,"Break",{Position=root.Position,Target=character})
			State:FireClient(player,"ExecuteReady",{Position=root.Position,Target=character,Duration=1.8,Duel=true})
			State:FireClient(opponent,"DuelGuardBroken",{Duration=1.8})
		end
	end
	return true
end

local function pulseVFX(fromPos, toPos, color)
	local orb = Instance.new("Part")
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(1.2,1.2,1.2)
	orb.Material = Enum.Material.Neon
	orb.Color = color
	orb.Anchored = true
	orb.CanCollide = false
	orb.Position = fromPos
	orb.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 5
	light.Range = 12
	light.Parent = orb
	local tween = TweenService:Create(orb, TweenInfo.new(0.18, Enum.EasingStyle.Linear), {Position = toPos})
	tween:Play()
	Debris:AddItem(orb, 0.3)
end

local function cooldownReady(player, key, cd)
	cooldowns[player] = cooldowns[player] or {}
	local now = os.clock()
	local readyAt = cooldowns[player][key] or 0
	if now < readyAt then return false end
	cooldowns[player][key] = now + cd
	State:FireClient(player, "Cooldown", {Key = key, Duration = cd})
	return true
end

local function actionReady(player, key, cost, cooldown)
	local now = os.clock()
	if now < ((cooldowns[player] or {})[key] or 0) then return false end
	if (stamina[player] or 0) < cost then
		State:FireClient(player, "Notice", {Text = "NOT ENOUGH STAMINA"})
		return false
	end
	stamina[player] -= cost
	player:SetAttribute("Stamina", stamina[player])
	return cooldownReady(player, key, cooldown)
end

local startWave
local finishMission

local function checkWave(player)
	task.delay(0.25, function()
		local session = sessions[player]
		if not session or not session.InMission or session.Transitioning then return end
		if #ownedEnemies(player) == 0 then
			session.Transitioning = true
			if session.Wave >= #GameConfig.Waves then
				finishMission(player)
			elseif session.Wave == 3 or session.Wave == 4 then
				task.wait(1.2)
				if sessions[player] == session and session.InMission then
					local offer = GameConfig.RuneOffers[session.Wave-2]
					session.AwaitingRune = session.Wave + 1
					State:FireClient(player, "RuneOffer", {Choices=offer})
				end
			else
				task.wait(1.4)
				if sessions[player] and sessions[player].InMission then
					startWave(player, session.Wave + 1)
				end
			end
		end
	end)
end

local function attachDeathWatch(player, enemy)
	enemy:GetAttributeChangedSignal("CurrentHP"):Connect(function()
		if (enemy:GetAttribute("CurrentHP") or 0) <= 0 then
			checkWave(player)
		end
	end)
end

startWave = function(player, waveIndex)
	local session = sessions[player]
	if not session or not session.InMission then return end
	session.Wave = waveIndex
	session.Transitioning = false

	clearOwnedEnemies(player)
	local wave = GameConfig.Waves[waveIndex]
	State:FireClient(player, "Mission", {
		Active = true,
		Wave = waveIndex,
		TotalWaves = #GameConfig.Waves,
		Label = wave.Label,
		EnemyCount = #wave.Enemies,
		Difficulty = session.Difficulty or "NORMAL",
	})

	local center = GameConfig.MissionCenter
	local offsets = {
		Vector3.new(-18,1,-8),
		Vector3.new(18,1,-8),
		Vector3.new(0,1,-22),
		Vector3.new(-24,1,-22),
		Vector3.new(24,1,-22),
	}

	for i, kind in ipairs(wave.Enemies) do
		local cfg = cloneTable(Enemies[kind])
		if session.Difficulty == "HARD" then
			cfg.HP = math.floor(cfg.HP * 1.45 + .5)
			cfg.ATK = math.floor(cfg.ATK * 1.35 + .5)
			cfg.Poise = math.floor(cfg.Poise * 1.2 + .5)
			cfg.AttackCooldown = math.max(.75, cfg.AttackCooldown * .9)
		end
		local pos = center + (offsets[i] or Vector3.new((i-1)*8,1,-15))
		local enemy = makeEnemyModel(kind, cfg, pos, player.UserId)
		attachDeathWatch(player, enemy)
	end
end

local function chooseRune(player, runeId)
	local session = sessions[player]
	if not session or not session.InMission or not session.AwaitingRune or typeof(runeId) ~= "string" then return end
	local offer = GameConfig.RuneOffers[session.Wave-2]
	local selected
	for _, candidate in ipairs(offer or {}) do
		if candidate.Id == runeId then selected = candidate; break end
	end
	if not selected then return end
	session.Runes[selected.Id] = true
	local nextWave = session.AwaitingRune
	session.AwaitingRune = nil
	if selected.Id == "BloodPact" then applyStats(player, false) end
	State:FireClient(player,"RuneChosen",{Name=selected.Name})
	startWave(player, nextWave)
end

local function releaseCharacterForMovement(player, character)
	if not character then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return false end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then descendant.Anchored = false end
	end
	humanoid.PlatformStand = false
	humanoid.Sit = false
	humanoid.AutoRotate = true
	humanoid.WalkSpeed = 20
	pcall(function() root:SetNetworkOwner(player) end)
	return true
end

local function startTraining(player)
	local session=sessions[player]
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	local root=character and character:FindFirstChild("HumanoidRootPart")
	if not session or not character or not humanoid or not root then
		State:FireClient(player,"Notice",{Text="FRAME NOT READY — RETRY"})
		return
	end
	removeFromDuelQueue(player)
	clearOwnedEnemies(player)
	session.InMission=true; session.Training=true; session.TrainingStage=1
	session.Complete=false; session.Wave=0; session.Transitioning=false; session.AwaitingRune=nil
	session.Runes={}; session.Shield=0; session.Surge=0; session.SurgeUntil=0
	session.Report={Damage=0,Crits=0,Breaks=0,Executions=0,Defeated=0,DamageTaken=0,Dodges=0}
	player:SetAttribute("RiftShield",0)
	releaseCharacterForMovement(player,character)
	character:PivotTo(CFrame.lookAt(Vector3.new(-24,3,-17),Vector3.new(-24,3,-25)))
	applyStats(player,true)
	local cfg=cloneTable(Enemies.Knight)
	cfg.Name="RIFT TRAINING FRAME"; cfg.HP=650; cfg.DEF=10; cfg.ATK=0; cfg.MoveSpeed=0
	cfg.AttackRange=0; cfg.AttackCooldown=99; cfg.Telegraph=2; cfg.Role="Training"; cfg.Poise=60; cfg.Scale=1.05
	local dummy=makeEnemyModel("Knight",cfg,Vector3.new(-24,3,-25),player.UserId)
	dummy:SetAttribute("TrainingDummy",true)
	State:FireClient(player,"TrainingStart",{Target=dummy})
	State:FireClient(player,"Surge",{Value=0,Ready=false})
end

local function startMission(player)
	local session = sessions[player]
	if not session then
		State:FireClient(player, "Notice", {Text = "SESSION INITIALIZING — RETRY"})
		return
	end
	if session.InMission then
		-- A Start request from the Combat Forge is a real mode transition.
		-- Clear the training frame instead of replaying MissionStart while the
		-- server still considers the player to be in Training.
		if session.Training then
			clearOwnedEnemies(player)
			session.InMission=false
			session.Training=false
			session.TrainingStage=0
		elseif session.InDuel then
			State:FireClient(player,"Notice",{Text="LEAVE THE DUEL BEFORE STARTING AN EXPEDITION"})
			return
		else
			State:FireClient(player, "MissionStart", {})
			return
		end
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root then
		State:FireClient(player, "Notice", {Text = "FRAME NOT READY — RETRY"})
		return
	end
	removeFromDuelQueue(player)

	session.InMission = true
	session.Training = false
	session.TrainingStage = 0
	session.Complete = false
	session.Wave = 0
	session.Transitioning = false
	session.StartTime = os.clock()
	session.Runes = {}
	session.Shield = 0
	session.Surge = 0
	session.SurgeUntil = 0
	session.LastPlayerHit = os.clock()
	session.AwaitingRune = nil
	session.Difficulty = (profiles[player] and profiles[player].PreferredDifficulty) or "NORMAL"
	session.Report = {Damage=0, Crits=0, Breaks=0, Executions=0, Defeated=0, DamageTaken=0, Dodges=0}
	player:SetAttribute("RiftShield", 0)

	clearOwnedEnemies(player)
	releaseCharacterForMovement(player, character)
	character:PivotTo(GameConfig.MissionSpawn)
	applyStats(player, true)

	State:FireClient(player, "MissionStart", {})
	State:FireClient(player, "Surge", {Value=0,Ready=false})
	task.wait(0.7)
	startWave(player, 1)
end

finishMission = function(player)
	local session = sessions[player]
	if not session or not session.InMission or session.Complete then return end
	session.Complete = true

	local elapsed = os.clock() - session.StartTime
	local data = profiles[player]
	local rewardCredits = Progression.MissionRewards.Credits
	local rewardShards = Progression.MissionRewards.Shards
	local rewardXP = 250
	if session.Difficulty == "HARD" then
		rewardCredits = math.floor(rewardCredits * 1.5)
		rewardShards += 2
		rewardXP = math.floor(rewardXP * 1.4)
	end
	if data.Clears == 0 then rewardCredits += Progression.MissionRewards.FirstClearCredits end

	data.Credits += rewardCredits
	data.Shards += rewardShards
	data.XP = (data.XP or 0) + rewardXP
	data.Clears += 1
	local loot = awardBossDrop(data)
	applyStats(player, false)
	applyWeaponAppearance(player)
	local newBest = data.BestTime == 0 or elapsed < data.BestTime
	if newBest then
		data.BestTime = elapsed
	end
	local report = session.Report or {}
	local score = math.clamp(math.floor(100 - math.max(0,elapsed-90)*.12 - (report.DamageTaken or 0)*.08 + (report.Breaks or 0)*3 + (report.Dodges or 0) + (report.Executions or 0)*2), 0, 100)
	report.Score = score
	report.Grade = score >= 92 and "S" or score >= 82 and "A" or score >= 68 and "B" or "C"
	-- Seal the arena before showing results. A dying boss could otherwise keep its
	-- AI loop alive for a moment, kill the player, and invalidate the replay state.
	clearOwnedEnemies(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.Health = humanoid.MaxHealth end

	saveProfile(player)
	pushProfile(player)

	State:FireClient(player, "MissionComplete", {
		Time = elapsed,
		Credits = rewardCredits,
		Shards = rewardShards,
		BestTime = data.BestTime,
		XP = rewardXP,
		Loot = loot,
		Report = cloneTable(report),
		Difficulty = session.Difficulty,
		NewBest = newBest,
	})
end

local function returnLobby(player)
	removeFromDuelQueue(player)
	local session = sessions[player]
	if session then
		session.InMission = false
		session.Training = false
		session.TrainingStage = 0
		session.InDuel = false
		session.DuelOpponent = 0
		session.Complete = false
		session.Wave = 0
		session.Transitioning = false
		session.AwaitingRune = nil
		session.Runes = {}
		session.Shield = 0
		session.Surge = 0
		session.SurgeUntil = 0
		player:SetAttribute("RiftShield", 0)
	end
	clearOwnedEnemies(player)
	local character = player.Character
	if character then
		releaseCharacterForMovement(player, character)
		character:PivotTo(GameConfig.LobbySpawn)
		applyStats(player, true)
	end
	State:FireClient(player, "Lobby", {})
end

local function prepareDuelist(player,opponent,position,lookAt)
	local session=sessions[player]
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	if not session or not character or not humanoid then return false end
	clearOwnedEnemies(player)
	session.InMission=true; session.InDuel=true; session.Training=false; session.TrainingStage=0
	session.DuelOpponent=opponent.UserId; session.DuelPoise=70; session.DuelBrokenUntil=0
	session.Surge=0; session.SurgeUntil=0; session.Runes={}; session.Shield=0; session.Complete=false
	releaseCharacterForMovement(player,character)
	humanoid.MaxHealth=500; humanoid.Health=500; humanoid.WalkSpeed=20
	character:PivotTo(CFrame.lookAt(position,lookAt))
	State:FireClient(player,"DuelStart",{Opponent=opponent.DisplayName,OpponentUserId=opponent.UserId})
	State:FireClient(player,"Surge",{Value=0,Ready=false})
	return true
end

local function startDuel(a,b)
	if not a or not b or not a.Parent or not b.Parent then return false end
	local sa,sb=sessions[a],sessions[b]
	if not sa or not sb or sa.InMission or sb.InMission then return false end
	local center=Vector3.new(110,3,-25)
	local okA=prepareDuelist(a,b,center+Vector3.new(-18,0,0),center)
	local okB=prepareDuelist(b,a,center+Vector3.new(18,0,0),center)
	if not okA or not okB then
		returnLobby(a); returnLobby(b); return false
	end
	return true
end

local function finishDuel(loser,forfeit)
	local loserSession=sessions[loser]
	if not loserSession or not loserSession.InDuel then return end
	local winner=Players:GetPlayerByUserId(loserSession.DuelOpponent or 0)
	local winnerSession=winner and sessions[winner]
	for _,player in ipairs({loser,winner}) do
		local session=player and sessions[player]
		if session then
			session.InDuel=false; session.InMission=false; session.DuelOpponent=0
			session.DuelPoise=70; session.DuelBrokenUntil=0; session.Surge=0; session.SurgeUntil=0
		end
	end
	State:FireClient(loser,"DuelComplete",{Won=false,Opponent=winner and winner.DisplayName or "RIVAL",Forfeit=forfeit==true})
	if winner and winner.Parent and winnerSession then
		State:FireClient(winner,"DuelComplete",{Won=true,Opponent=loser.DisplayName,Forfeit=forfeit==true})
	end
	task.delay(2.2,function()
		for _,player in ipairs({loser,winner}) do
			if player and player.Parent then pcall(function() player:LoadCharacter() end) end
		end
	end)
end

local function toggleDuelQueue(player)
	local session=sessions[player]
	if not session or session.InMission then return end
	for i,queued in ipairs(duelQueue) do
		if queued==player then
			table.remove(duelQueue,i)
			State:FireClient(player,"DuelQueue",{Waiting=false})
			return
		end
	end
	table.insert(duelQueue,player)
	State:FireClient(player,"DuelQueue",{Waiting=true,Position=#duelQueue})
	while #duelQueue>=2 do
		local a=table.remove(duelQueue,1)
		local b=table.remove(duelQueue,1)
		if a and b and a.Parent and b.Parent and startDuel(a,b) then return end
	end
end

local function doBasic(player)
	local session = sessions[player]
	if not session or not session.InMission then return end
	local state = combos[player]
	if not state then return end
	local now = os.clock()
	if now < state.Next then return end

	if now - state.Last > Skills.Basic.ComboReset then state.Step = 1 end
	local step = Skills.Basic.Steps[state.Step]
	local enemy = nearestEnemy(player, Skills.Basic.Range)
	local duelTarget=session.InDuel and duelOpponentInRange(player,Skills.Basic.Range) or nil
	if not enemy and not duelTarget then
		state.Last = now
		state.Next = now + step.Cooldown
		state.Step += 1
		if state.Step > #Skills.Basic.Steps then state.Step = 1 end
		return
	end
	if duelTarget then damageDuelOpponent(player,duelTarget,step.Coef,state.Step,step.Poise)
	else damageEnemy(player, enemy, step.Coef, state.Step, step.Poise) end
	State:FireClient(player, "AttackFX", {Step = state.Step})

	state.Last = now
	state.Next = now + step.Cooldown
	state.Step += 1
	if state.Step > #Skills.Basic.Steps then state.Step = 1 end
end

local function doHeavy(player)
	local session = sessions[player]
	if not session or not session.InMission then return end
	local config = Skills.Heavy
	if not actionReady(player, "Heavy", config.Stamina, config.Cooldown) then return end
	local enemy = nearestEnemy(player, config.Range)
	local duelTarget=session.InDuel and duelOpponentInRange(player,config.Range) or nil
	if duelTarget then damageDuelOpponent(player,duelTarget,config.Coef,4,config.Poise)
	elseif enemy then damageEnemy(player, enemy, config.Coef, 4, config.Poise) end
end

local function doDodge(player, direction)
	local session = sessions[player]
	if not session or not session.InMission then return end
	local config = Skills.Dodge
	if not actionReady(player, "Dodge", config.Stamina, config.Cooldown) then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	-- Accept a direction only after validating its type, magnitude and plane.
	local flat = typeof(direction) == "Vector3" and Vector3.new(direction.X, 0, direction.Z) or root.CFrame.LookVector
	local magnitude = flat.Magnitude
	flat = magnitude == magnitude and magnitude > .1 and magnitude < 1.5 and flat.Unit or root.CFrame.LookVector
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local dashDuration = .18
	local dashSpeed = 58
	local vertical = math.max(0, root.AssemblyLinearVelocity.Y)
	root.AssemblyLinearVelocity = flat*dashSpeed + Vector3.new(0, vertical, 0)
	if humanoid then humanoid.AutoRotate = false end
	local attachment = Instance.new("Attachment")
	attachment.Name = "RiftDodgeAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "RiftDodgeVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = flat*dashSpeed + Vector3.new(0, vertical, 0)
	velocity.MaxForce = math.huge
	velocity.Parent = root
	Debris:AddItem(velocity, dashDuration)
	Debris:AddItem(attachment, dashDuration + .03)
	task.delay(dashDuration, function()
		if humanoid and humanoid.Parent then humanoid.AutoRotate = true end
	end)
	character:SetAttribute("InvulnerableUntil", os.clock()+config.IFrame)
	if session.Report then session.Report.Dodges += 1 end
	State:FireClient(player, "DodgeFX", {Direction=flat, Duration=dashDuration})
end

local function doSkill(player, key)
	local session = sessions[player]
	if not session or not session.InMission then return end
	local sk = Skills[key]
	if not sk or not cooldownReady(player, key, sk.Cooldown) then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	if key == "Q" then
		local enemy = nearestEnemy(player, sk.Range)
		local duelTarget=session.InDuel and duelOpponentInRange(player,sk.Range) or nil
		if duelTarget then
			local targetRoot=duelTarget.Character and duelTarget.Character:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				pulseVFX(root.Position+Vector3.new(0,2,0),targetRoot.Position+Vector3.new(0,2,0),Color3.fromRGB(115,120,255))
				task.delay(.16,function() damageDuelOpponent(player,duelTarget,sk.Coef,5,sk.Poise) end)
			end
		elseif enemy then
			pulseVFX(root.Position + Vector3.new(0,2,0), enemy.PrimaryPart.Position, Color3.fromRGB(115,120,255))
			task.delay(0.16, function()
				if enemy and enemy.Parent then damageEnemy(player, enemy, sk.Coef, 5, sk.Poise) end
			end)
		end

	elseif key == "E" then
		local enemy = nearestEnemy(player, sk.Range)
		local duelTarget=session.InDuel and duelOpponentInRange(player,sk.Range) or nil
		if duelTarget then
			damageDuelOpponent(player,duelTarget,sk.Coef,4,sk.Poise)
			local targetRoot=duelTarget.Character and duelTarget.Character:FindFirstChild("HumanoidRootPart")
			if targetRoot then State:FireClient(player,"GuardBreakFX",{Position=targetRoot.Position}) end
		elseif enemy then
			damageEnemy(player, enemy, sk.Coef, 4, sk.Poise)
			State:FireClient(player, "GuardBreakFX", {Position=enemy.PrimaryPart.Position})
		end
	end
end

local function doExecute(player)
	local session=sessions[player]
	if not session or not session.InMission then return end
	if session.InDuel then
		local opponent,distance=duelOpponentInRange(player,9)
		local targetSession=opponent and sessions[opponent]
		if not opponent or distance>9 or not targetSession or os.clock()>=(targetSession.DuelBrokenUntil or 0) then return end
		local root=opponent.Character and opponent.Character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		targetSession.DuelBrokenUntil=0
		State:FireClient(player,"ExecuteFX",{Target=opponent.Character,Position=root.Position,Boss=false,Duel=true})
		damageDuelOpponent(player,opponent,2.7,6,0)
		addSurge(player,22,"DUEL EXECUTE")
		return
	end
	local enemy, distance=nearestEnemy(player,9)
	if not enemy or distance>9 then return end
	local now=os.clock()
	local hp=enemy:GetAttribute("CurrentHP") or 0
	local maxHP=math.max(1,enemy:GetAttribute("MaxHP") or 1)
	local boss=enemy:GetAttribute("Role")=="Boss"
	local eligible=now < (enemy:GetAttribute("BrokenUntil") or 0) or (not boss and hp/maxHP<=.28)
	if not eligible or enemy:GetAttribute("Executing") then return end
	enemy:SetAttribute("Executing",true)
	enemy:SetAttribute("BrokenUntil",now+1)
	local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and enemy.PrimaryPart then
		local approach=enemy.PrimaryPart.Position-enemy.PrimaryPart.CFrame.LookVector*3
		player.Character:PivotTo(CFrame.lookAt(Vector3.new(approach.X,root.Position.Y,approach.Z),enemy.PrimaryPart.Position))
	end
	State:FireClient(player,"ExecuteFX",{Target=enemy,Position=enemy.PrimaryPart.Position,Boss=boss})
	task.delay(.18,function()
		if not enemy or not enemy.Parent then return end
		if session.Report then session.Report.Executions=(session.Report.Executions or 0)+1 end
		addSurge(player,boss and 24 or 32,"EXECUTE")
		damageEnemy(player,enemy,boss and 5.2 or 999,6,0)
		if enemy and enemy.Parent then enemy:SetAttribute("Executing",false) end
	end)
end

local function doSurge(player)
	local session=sessions[player]
	if not session or not session.InMission or (session.Surge or 0)<100 or os.clock()<(session.SurgeUntil or 0) then return end
	local duration=8
	session.Surge=0; session.SurgeUntil=os.clock()+duration
	local endsAt=session.SurgeUntil
	local humanoid=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.WalkSpeed=26 end
	State:FireClient(player,"SurgeStart",{Duration=duration})
	State:FireClient(player,"Surge",{Value=0,Ready=false,Active=true,Duration=duration})
	if session.Training then
		session.TrainingStage=4
		State:FireClient(player,"TrainingComplete",{Text="DRILL COMPLETE  //  FREE PRACTICE  ·  B RETURN"})
	end
	task.delay(duration,function()
		local current=sessions[player]
		if not current or current.SurgeUntil~=endsAt then return end
		current.SurgeUntil=0
		local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then h.WalkSpeed=20 end
		State:FireClient(player,"SurgeEnd",{})
	end)
end

local function upgradeMastery(player)
	local data = profiles[player]
	if not data then return end
	local nextIndex = data.Mastery + 1
	local node = Progression.Mastery[nextIndex]
	if not node then
		State:FireClient(player, "Notice", {Text = "MASTERY MAXED"})
		return
	end
	if data.Credits < node.Cost then
		State:FireClient(player, "Notice", {Text = "NOT ENOUGH CREDITS"})
		return
	end
	data.Credits -= node.Cost
	data.Mastery = nextIndex
	applyStats(player, true)
	pushProfile(player)
	saveProfile(player)
	State:FireClient(player, "Notice", {Text = "MASTERY NODE " .. nextIndex .. " UNLOCKED"})
end

local function upgradeCore(player)
	local data = profiles[player]
	if not data then return end
	local nextLevel = data.CoreLevel + 1
	local cost = Progression.CoreShardCosts[nextLevel]
	if not cost then
		State:FireClient(player, "Notice", {Text = "CORE MAXED"})
		return
	end
	if data.Shards < cost then
		State:FireClient(player, "Notice", {Text = "NOT ENOUGH CORE SHARDS"})
		return
	end
	data.Shards -= cost
	data.CoreLevel = nextLevel
	applyStats(player, true)
	pushProfile(player)
	saveProfile(player)
	State:FireClient(player, "Notice", {Text = "ASSAULT CORE LV." .. nextLevel})
end

local function equipWeapon(player, weaponId)
	local data = profiles[player]
	if not data or typeof(weaponId) ~= "string" or not WEAPONS[weaponId] or not ownsWeapon(data, weaponId) then return end
	data.EquippedWeapon = weaponId
	applyStats(player, false)
	applyWeaponAppearance(player)
	pushProfile(player)
	saveProfile(player)
	State:FireClient(player, "Notice", {Text = WEAPONS[weaponId].Name .. " EQUIPPED"})
end

local function setDifficulty(player, difficulty)
	local data, session = profiles[player], sessions[player]
	if not data or not session or session.InMission or (difficulty ~= "NORMAL" and difficulty ~= "HARD") then return end
	data.PreferredDifficulty = difficulty
	session.Difficulty = difficulty
	pushProfile(player)
	saveProfile(player)
	State:FireClient(player, "Notice", {Text = difficulty == "HARD" and "HARD MODE ARMED  /  +50% CREDITS" or "NORMAL MODE SELECTED"})
end

local function claimQuest(player)
	local data = profiles[player]
	if not data or data.QuestClaimed or (data.QuestKills or 0) < 12 then return end
	data.QuestClaimed = true
	data.Credits += 180
	data.Shards += 1
	pushProfile(player)
	saveProfile(player)
	State:FireClient(player, "Notice", {Text = "FIRST DIRECTIVE COMPLETE  /  +180 C  +1 SHARD"})
end

Action.OnServerEvent:Connect(function(player, action, arg)
	if action == "Basic" then
		doBasic(player)
	elseif action == "Heavy" then
		doHeavy(player)
	elseif action == "Dodge" then
		doDodge(player, arg)
	elseif action == "ChooseRune" then
		chooseRune(player, arg)
	elseif action == "Skill" then
		doSkill(player, arg)
	elseif action == "Execute" then
		doExecute(player)
	elseif action == "Surge" then
		doSurge(player)
	elseif action == "StartMission" then
		local ok, err = pcall(startMission, player)
		if not ok then
			warn("[RIFT] StartMission failed for", player.Name, err)
			local session = sessions[player]
			if session then session.InMission = false; session.Transitioning = false end
			State:FireClient(player, "Notice", {Text = "RIFT START FAILED — RETRY"})
		end
	elseif action == "StartTraining" then
		startTraining(player)
	elseif action == "ToggleDuelQueue" then
		toggleDuelQueue(player)
	elseif action == "ForfeitDuel" then
		finishDuel(player,true)
	elseif action == "ReturnLobby" then
		returnLobby(player)
	elseif action == "RestartMission" then
		local session=sessions[player]
		-- The result screen is authoritative for this request. Also accept the
		-- replay after an edge-case respawn has already reset mission flags.
		if session and not session.InDuel then
			session.InMission=false
			session.Complete=false
			clearOwnedEnemies(player)
			startMission(player)
		end
	elseif action == "UpgradeMastery" then
		upgradeMastery(player)
	elseif action == "UpgradeCore" then
		upgradeCore(player)
	elseif action == "EquipWeapon" then
		equipWeapon(player, arg)
	elseif action == "SetDifficulty" then
		setDifficulty(player, arg)
	elseif action == "ClaimQuest" then
		claimQuest(player)
	end
end)

Snapshot.OnServerInvoke = function(player)
	return publicProfile(player), sessions[player]
end

local function animateEnemyRig(enemy, now, moving)
	if enemy:GetAttribute("FormalVisual") ~= "AshenHumanoid_v1" then return end
	local root=enemy.PrimaryPart
	local rightHip=root:FindFirstChild("RightHip")
	local leftHip=root:FindFirstChild("LeftHip")
	local swordArm=root:FindFirstChild("SwordArmJoint")
	local shieldArm=root:FindFirstChild("ShieldArmJoint")
	local chest=root:FindFirstChild("ChestJoint")
	local stride=moving and math.sin(now*8.5)*.48 or math.sin(now*2.2)*.035
	if rightHip then rightHip.Transform=CFrame.Angles(stride,0,0) end
	if leftHip then leftHip.Transform=CFrame.Angles(-stride,0,0) end
	local attacking=now-(enemy:GetAttribute("LastAttack") or 0)<.28
	if swordArm then
		swordArm.Transform=attacking and CFrame.Angles(math.rad(-72),0,math.rad(-32)) or CFrame.Angles(-stride*.42,0,math.rad(-8))
	end
	if shieldArm then shieldArm.Transform=CFrame.Angles(stride*.22,0,math.rad(10)) end
	if chest then
		local hit=now<(enemy:GetAttribute("HitReactUntil") or 0)
		chest.Transform=CFrame.new(0,math.abs(math.sin(now*4))*(moving and .08 or .025),0)*CFrame.Angles(0,0,hit and math.rad(7) or 0)
	end
end

task.spawn(function()
	while true do
		task.wait(.25)
		for player, amount in pairs(stamina) do
			if player.Parent and amount < 100 then
				stamina[player] = math.min(100, amount + 4.5)
				player:SetAttribute("Stamina", stamina[player])
			end
			local session = sessions[player]
			if player.Parent and session and session.InMission and session.Runes.GuardianRune
				and os.clock() - session.LastPlayerHit >= 3 and session.Shield < 40 then
				session.Shield = 40
				player:SetAttribute("RiftShield", 40)
				State:FireClient(player,"Notice",{Text="GUARDIAN SHIELD READY"})
			end
		end
	end
end)

local function floorTelegraph(position, radius, duration, mode)
	local mark=Instance.new("Part")
	mark.Name="EnemyTelegraph"
	mark.Shape=Enum.PartType.Cylinder
	mark.Size=Vector3.new(.08,radius*2,radius*2)
	mark.CFrame=CFrame.new(position.X,.76,position.Z)*CFrame.Angles(0,0,math.rad(90))
	mark.Color=mode=="RiftPulse" and Color3.fromRGB(222,66,188)
		or (mode=="Sweep" and Color3.fromRGB(255,132,56) or Color3.fromRGB(241,73,50))
	mark.Material=Enum.Material.Neon
	mark.Transparency=.87
	mark.Anchored=true; mark.CanCollide=false; mark.CanTouch=false; mark.CanQuery=false
	mark.Parent=Workspace
	TweenService:Create(mark,TweenInfo.new(duration,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{
		Transparency=.55,
		Size=Vector3.new(.08,radius*2.08,radius*2.08),
	}):Play()
	Debris:AddItem(mark,duration+.1)
end

-- Enemy AI
task.spawn(function()
	while true do
		task.wait(0.10)
		local now = os.clock()
		local activeAttackers = {}
		for _, enemy in ipairs(missionEnemies:GetChildren()) do
			if not enemy:IsA("Model") or not enemy.PrimaryPart then continue end
			if (enemy:GetAttribute("CurrentHP") or 0) <= 0 then continue end
			local ownerId = enemy:GetAttribute("OwnerUserId")
			local player = ownerId and Players:GetPlayerByUserId(ownerId)
			local session = player and sessions[player]
			if not player or not session or not session.InMission then continue end
			if enemy:GetAttribute("TrainingDummy") then
				animateEnemyRig(enemy,now,false)
				continue
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not humanoid or humanoid.Health <= 0 or not root then continue end

			local pos = enemy.PrimaryPart.Position
			local target = root.Position
			local flatTarget = Vector3.new(target.X, pos.Y, target.Z)
			local delta = flatTarget - pos
			local dist = delta.Magnitude
			local attackRange = enemy:GetAttribute("AttackRange") or 5
			local speed = enemy:GetAttribute("MoveSpeed") or 8
			local role = enemy:GetAttribute("Role") or "Melee"
			if role == "Boss" then
				local hpRatio = (enemy:GetAttribute("CurrentHP") or 0)/math.max(1,enemy:GetAttribute("MaxHP") or 1)
				local phase = hpRatio <= .35 and 3 or (hpRatio <= .70 and 2 or 1)
				if phase > (enemy:GetAttribute("Phase") or 1) then
					enemy:SetAttribute("Phase",phase)
					enemy:SetAttribute("AttackCooldown",phase==3 and 1.55 or 1.8)
					enemy:SetAttribute("ATK",phase==3 and 80 or 72)
					enemy:SetAttribute("PendingAttackAt",0)
					enemy:SetAttribute("PhaseTransitionUntil",now+1.15)
					enemy:SetAttribute("Poise",enemy:GetAttribute("PoiseMax") or 300)
					local core=enemy:FindFirstChild("Core")
					local light=core and core:FindFirstChildOfClass("PointLight")
					if core then core.Color=phase==3 and Color3.fromRGB(255,63,135) or Color3.fromRGB(205,82,232) end
					if light then light.Color=core.Color; light.Brightness=phase==3 and 4.2 or 3.1; light.Range=phase==3 and 24 or 20 end
					local phaseHighlight=enemy:FindFirstChildOfClass("Highlight")
					if phaseHighlight then phaseHighlight.OutlineColor=core and core.Color or Color3.fromRGB(255,73,150) end
					State:FireClient(player,"BossPhase",{Phase=phase,Position=enemy.PrimaryPart.Position})
				end
				if now < (enemy:GetAttribute("PhaseTransitionUntil") or 0) then
					animateEnemyRig(enemy,now,false)
					continue
				end
			end
			if now < (enemy:GetAttribute("SlowUntil") or 0) then speed *= 0.45 end
			local brokenUntil = enemy:GetAttribute("BrokenUntil") or 0
			if brokenUntil > 0 and now >= brokenUntil then
				enemy:SetAttribute("BrokenUntil", 0)
				enemy:SetAttribute("Poise", enemy:GetAttribute("PoiseMax") or 80)
			end
			if now < brokenUntil then
				animateEnemyRig(enemy, now, false)
				continue
			end

			local pendingAt = enemy:GetAttribute("PendingAttackAt") or 0
			local highlight = enemy:FindFirstChildOfClass("Highlight")
			if pendingAt > 0 then
				activeAttackers[player] = (activeAttackers[player] or 0) + 1
				if now >= pendingAt then
					enemy:SetAttribute("PendingAttackAt", 0)
					if highlight then highlight.FillTransparency = .96 end
					local currentDistance = (Vector3.new(root.Position.X,pos.Y,root.Position.Z)-pos).Magnitude
					local mode = enemy:GetAttribute("AttackMode")
					local resolveRange = mode == "RiftPulse" and 14 or (mode == "Sweep" and 11 or attackRange+2)
					local blocked = false
					if role == "Ranged" then
						local params = RaycastParams.new()
						params.FilterType = Enum.RaycastFilterType.Exclude
						params.FilterDescendantsInstances = {enemy, character}
						blocked = Workspace:Raycast(pos, root.Position-pos, params) ~= nil
						if not blocked then pulseVFX(pos, root.Position, Color3.fromRGB(235,102,63)) end
					end
					if currentDistance <= resolveRange and not blocked and now >= (character:GetAttribute("InvulnerableUntil") or 0) then
						local enemyATK = enemy:GetAttribute("ATK") or 0
						local stats = computeStats(profiles[player])
						local dmg = math.floor(enemyATK * Balance.DamageDefenseK / (Balance.DamageDefenseK + stats.DEF) + .5)
						session.LastPlayerHit = now
						local shielded = math.min(session.Shield or 0, dmg)
						session.Shield = (session.Shield or 0) - shielded
						player:SetAttribute("RiftShield", session.Shield)
						local dealt = dmg-shielded
						humanoid:TakeDamage(dealt)
						if session.Report then session.Report.DamageTaken += math.max(0,dealt) end
						State:FireClient(player, "PlayerHit", {Damage=dealt, Shielded=shielded})
					end
				end
				animateEnemyRig(enemy, now, false)
				continue
			end

			local retreat = role == "Ranged" and dist < 11
			local moving=(dist > attackRange or retreat) and dist > .05
			animateEnemyRig(enemy,now,moving)
			if moving then
				local step = math.min(speed * .10, retreat and (11-dist) or (dist-attackRange+.2))
				local newPos = pos + delta.Unit * math.max(0, step) * (retreat and -1 or 1)
				enemy:PivotTo(CFrame.new(newPos, flatTarget))
			else
				local last = enemy:GetAttribute("LastAttack") or 0
				local cd = enemy:GetAttribute("AttackCooldown") or 1.5
				if now - last >= cd and (activeAttackers[player] or 0) < 2 then
					activeAttackers[player] = (activeAttackers[player] or 0) + 1
					enemy:SetAttribute("LastAttack", now)
					local windup = enemy:GetAttribute("Telegraph") or .5
					if role == "Boss" then
						local count=(enemy:GetAttribute("AttackCount") or 0)+1
						enemy:SetAttribute("AttackCount",count)
						local phase=enemy:GetAttribute("Phase") or 1
						local pattern=phase==1 and {"Cleave","Cleave","Sweep"}
							or (phase==2 and {"Sweep","Cleave","RiftPulse"} or {"RiftPulse","Sweep","RiftPulse","Cleave"})
						local mode=pattern[(count-1)%#pattern+1]
						enemy:SetAttribute("AttackMode",mode)
						windup=mode=="RiftPulse" and (phase==3 and .82 or 1.05) or (mode=="Sweep" and .85 or .90)
						local radius=mode=="RiftPulse" and 14 or (mode=="Sweep" and 11 or 8)
						floorTelegraph(pos,radius,windup,mode)
						State:FireClient(player,"BossTelegraph",{Mode=mode,Duration=windup,Phase=phase})
					elseif role == "Heavy" then
						floorTelegraph(pos,9,windup,"Heavy")
					end
					enemy:SetAttribute("PendingAttackAt", now + windup)
					if highlight then
						highlight.FillColor = Color3.fromRGB(250,73,54)
						highlight.FillTransparency = .68
					end
				end
			end
		end
	end
end)

-- World interactions mirror the HUD actions, so the Hub feels like a place
-- rather than a static menu. The server still owns every progression change.
for _,prompt in ipairs(world:GetDescendants()) do
	if prompt:IsA("ProximityPrompt") and prompt.Name=="RiftInteraction" then
		prompt.Triggered:Connect(function(player)
			local action=prompt:GetAttribute("RiftAction")
			if action=="StartMission" then
				startMission(player)
			elseif action=="StartTraining" then
				startTraining(player)
			elseif action=="ToggleDuelQueue" then
				toggleDuelQueue(player)
			elseif action=="UpgradeMastery" then
				upgradeMastery(player)
			elseif action=="UpgradeCore" then
				upgradeCore(player)
			end
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	loadProfile(player)
	task.spawn(refreshSupportEntitlements,player)
	-- Studio and slow clients occasionally miss the initial automatic spawn.
	-- A bounded watchdog prevents the title page from opening without a frame.
	task.delay(1,function()
		if player.Parent and not player.Character then
			pcall(function() player:LoadCharacter() end)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		character:SetAttribute("RiftReady",false)
		local humanoid=character:WaitForChild("Humanoid",5)
		character:WaitForChild("HumanoidRootPart",5)
		equipRiftVanguard(character)
		equipRuneBlade(character)
		applyStats(player, true)
		applyWeaponAppearance(player)
		releaseCharacterForMovement(player, character)
		-- Death ends the current expedition cleanly. Respawning into an active
		-- enemy wave was the source of the default-avatar flash and broken state.
		local session=sessions[player]
		local returnToMission=session and session.InMission and not session.Respawning
		if session and session.Respawning then
			session.Respawning=false; session.InMission=false; session.Complete=false
			session.Training=false; session.TrainingStage=0; session.Wave=0; session.Transitioning=false; session.AwaitingRune=nil; session.Runes={}; session.Shield=0; session.Surge=0; session.SurgeUntil=0
			player:SetAttribute("RiftShield",0); clearOwnedEnemies(player)
		end
		character:PivotTo(returnToMission and GameConfig.MissionSpawn or GameConfig.LobbySpawn)
		character:SetAttribute("RiftReady",true)
		State:FireClient(player,"RespawnReady",{})
		if humanoid then
				humanoid.Died:Connect(function()
					local live=sessions[player]
					removeFromDuelQueue(player)
					if live and live.InDuel then
						finishDuel(player,false)
						return
					end
					if live then live.Respawning=true; live.InMission=false; live.Transitioning=false; live.AwaitingRune=nil end
				clearOwnedEnemies(player)
				State:FireClient(player,"PlayerDefeated",{RespawnIn=Players.RespawnTime})
			end)
		end
		pushProfile(player)
	end)
	task.delay(1, function()
		if player.Parent then pushProfile(player) end
	end)
end)

for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		loadProfile(p)
		if p.Character then equipRiftVanguard(p.Character); equipRuneBlade(p.Character); applyStats(p, true); applyWeaponAppearance(p); releaseCharacterForMovement(p, p.Character) end
		pushProfile(p)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	removeFromDuelQueue(player)
	local session=sessions[player]
	if session and session.InDuel then finishDuel(player,true) end
	saveProfile(player)
	clearOwnedEnemies(player)
	profiles[player] = nil
	sessions[player] = nil
	cooldowns[player] = nil
	combos[player] = nil
	stamina[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveProfile(player)
	end
end)
