-- RIFT PROTOCOL — Public Alpha Client
-- Camera, controls, HUD, menus and lightweight VFX.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Root = ReplicatedStorage:WaitForChild("RIFT")
local Remotes = Root:WaitForChild("Remotes")
local Config = Root:WaitForChild("Config")
local Skills = require(Config:WaitForChild("Skills"))
local Progression = require(Config:WaitForChild("Progression"))
local Action = Remotes:WaitForChild("Action")
local State = Remotes:WaitForChild("State")
local Snapshot = Remotes:WaitForChild("Snapshot")

local profile
local inMission = false
local trainingMode = false
local duelMode = false
local duelQueued = false
local cooldownUntil = {}
local cameraShake = 0
local hitStopUntil = 0
local attackBusy = false
local localComboStep = 1
local localComboLast = 0
local missionRequestPending = false
local WALK_SPEED = 20
local SPRINT_SPEED = 30
local effectSettings = {
	Shake = .55,
	HitFlash = true,
	PostFX = true,
}
effectSettings.MissionGrade = game:GetService("Lighting"):FindFirstChild("RIFT_MissionGrade") or Instance.new("ColorCorrectionEffect")
effectSettings.MissionGrade.Name = "RIFT_MissionGrade"
effectSettings.MissionGrade.Brightness = -.035
effectSettings.MissionGrade.Contrast = .11
effectSettings.MissionGrade.Saturation = -.025
effectSettings.MissionGrade.TintColor = Color3.fromRGB(226,234,250)
effectSettings.MissionGrade.Enabled = false
effectSettings.MissionGrade.Parent = game:GetService("Lighting")
effectSettings.InCombatGrade = false
effectSettings.SetMissionGrade = function(active)
	effectSettings.InCombatGrade = active == true
	effectSettings.MissionGrade.Enabled = effectSettings.InCombatGrade and effectSettings.PostFX
end
local function restorePlayerControl(character)
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    humanoid.AutoRotate = true
    humanoid.PlatformStand = false
    humanoid.Sit = false
    humanoid.AutoRotate = true
    humanoid.WalkSpeed = WALK_SPEED
    humanoid.Jump = false
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then descendant.Anchored = false end
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    if root then root.Anchored = false end
    -- Roblox's built-in PlayerModule owns movement. Do not bind, sink or
    -- overwrite WASD here; custom movement layers caused the previous stutter.
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    player.CameraMinZoomDistance = 9
    player.CameraMaxZoomDistance = 22
    camera.CameraType = Enum.CameraType.Custom
    camera.CameraSubject = humanoid
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RIFT_UI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

-- Keep the existing layout readable in a docked Studio viewport.
local gui = Instance.new("Frame")
gui.Name = "Canvas"
gui.BackgroundTransparency = 1
gui.BorderSizePixel = 0
gui.Parent = screenGui
local uiScale = Instance.new("UIScale")
uiScale.Parent = gui
local function resizeUI()
    local viewport = screenGui.AbsoluteSize
    local scale = math.min(1, viewport.X / 1000, viewport.Y / 600)
    -- Phone landscape needs a larger interaction scale than the desktop
    -- composition. 0.68 keeps the 800x470 modal inside the iPhone safe
    -- viewport while preserving practical combat touch targets.
    scale = math.max(scale, UserInputService.TouchEnabled and 0.68 or 0.1)
    uiScale.Scale = scale
    gui.Size = UDim2.fromOffset(viewport.X / scale, viewport.Y / scale)
	if effectSettings.ApplyResponsiveLayout then
		task.defer(effectSettings.ApplyResponsiveLayout)
	end
end
screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeUI)
resizeUI()

-- Keep Roblox's chat/translation banner out of the combat composition for this solo slice.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
end)

-- The title page is a clean presentation layer. Gameplay HUD appears only after entry.
local hud = Instance.new("Frame")
hud.Name = "HUD"
hud.Size = UDim2.fromScale(1,1)
hud.BackgroundTransparency = 1
hud.BorderSizePixel = 0
hud.Visible = false
hud.Parent = gui

local function corner(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = obj
end

local function stroke(obj, color, transparency, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(90,100,140)
	s.Transparency = transparency or 0
	s.Thickness = thickness or 1
	s.Parent = obj
	return s
end

local function gradient(obj, a, b, rotation)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a,b)
	g.Rotation = rotation or 0
	g.Parent = obj
end

local function makeText(parent, text, size, pos, fontSize, bold)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Text = text
	l.TextColor3 = Color3.fromRGB(235,240,255)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
	l.TextSize = fontSize or 16
	l.Parent = parent
	return l
end

local function makeButton(parent, text, size, pos)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Modal = false
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = Color3.fromRGB(21,27,43)
	b.BackgroundTransparency = .04
	b.Text = text
	b.TextColor3 = Color3.fromRGB(238,242,252)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextStrokeTransparency = 1
	b.Parent = parent
	corner(b, 3)
	local border=stroke(b, Color3.fromRGB(112,128,166), 0.46, 1)
	local scale=Instance.new("UIScale"); scale.Parent=b
	local accent=Instance.new("Frame")
	accent.Name="Accent"; accent.Size=UDim2.new(0,3,1,-8); accent.Position=UDim2.fromOffset(0,4)
	accent.BackgroundColor3=Color3.fromRGB(101,194,226); accent.BackgroundTransparency=.12; accent.BorderSizePixel=0; accent.Parent=b
	corner(accent,1)
	local upperEdge=Instance.new("Frame")
	upperEdge.Name="UpperEdge"; upperEdge.Size=UDim2.new(1,-12,0,1); upperEdge.Position=UDim2.fromOffset(6,2)
	upperEdge.BackgroundColor3=Color3.fromRGB(203,224,244); upperEdge.BackgroundTransparency=.72
	upperEdge.BorderSizePixel=0; upperEdge.Parent=b
	local lowerEdge=upperEdge:Clone(); lowerEdge.Name="LowerEdge"; lowerEdge.Position=UDim2.new(0,6,1,-3)
	lowerEdge.BackgroundColor3=Color3.fromRGB(3,6,14); lowerEdge.BackgroundTransparency=.25; lowerEdge.Parent=b
	local endCap=Instance.new("Frame")
	endCap.Name="EndCap"; endCap.Size=UDim2.fromOffset(6,6); endCap.AnchorPoint=Vector2.new(.5,.5)
	endCap.Position=UDim2.new(1,-8,.5,0); endCap.Rotation=45; endCap.BackgroundColor3=Color3.fromRGB(112,128,166)
	endCap.BackgroundTransparency=.28; endCap.BorderSizePixel=0; endCap.Parent=b
	-- Tight corners, etched edges and a small end marker create a game-control
	-- silhouette without relying on licensed image assets.
	b.MouseEnter:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(31,40,61)}):Play()
		TweenService:Create(scale,TweenInfo.new(.12),{Scale=1.018}):Play()
		TweenService:Create(border,TweenInfo.new(.12),{Transparency=.12}):Play()
		TweenService:Create(endCap,TweenInfo.new(.12),{Rotation=135,BackgroundTransparency=.02}):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(21,27,43)}):Play()
		TweenService:Create(scale,TweenInfo.new(.12),{Scale=1}):Play()
		TweenService:Create(border,TweenInfo.new(.12),{Transparency=.46}):Play()
		TweenService:Create(endCap,TweenInfo.new(.12),{Rotation=45,BackgroundTransparency=.28}):Play()
	end)
	b.MouseButton1Down:Connect(function() scale.Scale=.985 end)
	b.MouseButton1Up:Connect(function() TweenService:Create(scale,TweenInfo.new(.08),{Scale=1.012}):Play() end)
	return b
end

effectSettings.StyleActionButton=function(button, accentColor, sigil, leftAligned)
	local accent=button:FindFirstChild("Accent")
	local endCap=button:FindFirstChild("EndCap")
	local border=button:FindFirstChildOfClass("UIStroke")
	if accent then accent.BackgroundColor3=accentColor end
	if endCap then endCap.BackgroundColor3=accentColor end
	if border then border.Color=accentColor; border.Thickness=1.25 end
	button.BackgroundColor3=Color3.fromRGB(18,24,39)
	button.TextColor3=Color3.fromRGB(244,247,255)
	button.TextTransparency=0
	button.TextStrokeColor3=Color3.fromRGB(3,6,12)
	button.TextStrokeTransparency=.72
	button.TextXAlignment=Enum.TextXAlignment.Center
	button.TextSize=#button.Text>24 and 11 or 12
end

effectSettings.PanelChrome=function(panel, accentColor, tag)
	corner(panel,4)
	stroke(panel,accentColor,.36,1)
	local rule=Instance.new("Frame")
	rule.Name="PanelRule"; rule.Size=UDim2.new(0,72,0,2); rule.Position=UDim2.fromOffset(12,5)
	rule.BackgroundColor3=accentColor; rule.BorderSizePixel=0; rule.Parent=panel
	local notch=Instance.new("Frame")
	notch.Name="PanelNotch"; notch.Size=UDim2.fromOffset(8,8); notch.Position=UDim2.new(1,-16,0,8)
	notch.Rotation=45; notch.BackgroundColor3=accentColor; notch.BackgroundTransparency=.22
	notch.BorderSizePixel=0; notch.Parent=panel
	if tag then
		local tagLabel=makeText(panel,tag,UDim2.fromOffset(74,14),UDim2.new(1,-94,0,6),8,true)
		tagLabel.TextXAlignment=Enum.TextXAlignment.Right; tagLabel.TextColor3=accentColor
	end
end

-- A controlled defeat transition masks Roblox's temporary default avatar
-- while the server rebuilds the player's combat frame.
local defeatShade=Instance.new("Frame")
defeatShade.Name="DefeatTransition"; defeatShade.Size=UDim2.new(1,4,1,4); defeatShade.Position=UDim2.fromOffset(-2,-2)
defeatShade.BackgroundColor3=Color3.fromRGB(5,7,14); defeatShade.BackgroundTransparency=1
defeatShade.Visible=false; defeatShade.Active=true; defeatShade.ZIndex=90
defeatShade:SetAttribute("TransitionState","Hidden")
do
	-- The regular HUD respects Roblox's top inset. Death recovery must not:
	-- placing it in a dedicated ScreenGui prevents the bright uncovered strip.
	local defeatLayer=Instance.new("ScreenGui")
	defeatLayer.Name="RIFT_TRANSITION"; defeatLayer.ResetOnSpawn=false; defeatLayer.IgnoreGuiInset=true
	defeatLayer.DisplayOrder=1000; defeatLayer.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
	pcall(function() defeatLayer.ScreenInsets=Enum.ScreenInsets.None end)
	pcall(function() defeatLayer.ClipToDeviceSafeArea=false end)
	defeatLayer.Parent=player:WaitForChild("PlayerGui")
	defeatShade.Parent=defeatLayer
end
local defeatRule=Instance.new("Frame")
defeatRule.Size=UDim2.fromOffset(220,2); defeatRule.Position=UDim2.new(.5,-110,.5,-54)
defeatRule.BackgroundColor3=Color3.fromRGB(160,72,108); defeatRule.BorderSizePixel=0; defeatRule.ZIndex=91; defeatRule.Parent=defeatShade
local defeatTitle=makeText(defeatShade,"FRAME DESTABILIZED",UDim2.new(0,520,0,52),UDim2.new(.5,-260,.5,-34),30,true)
defeatTitle.TextXAlignment=Enum.TextXAlignment.Center; defeatTitle.TextColor3=Color3.fromRGB(244,224,236); defeatTitle.ZIndex=91
local defeatStatus=makeText(defeatShade,"RECONSTRUCTING AT SANCTUM…",UDim2.new(0,520,0,26),UDim2.new(.5,-260,.5,24),12,true)
defeatStatus.TextXAlignment=Enum.TextXAlignment.Center; defeatStatus.TextColor3=Color3.fromRGB(121,205,232); defeatStatus.ZIndex=91
local function showDefeatTransition()
	local state=defeatShade:GetAttribute("TransitionState")
	if state=="Covering" or state=="Covered" then return end
	defeatShade:SetAttribute("TransitionState","Covering")
	local wasVisible=defeatShade.Visible
	defeatShade.Visible=true
	if not wasVisible then defeatShade.BackgroundTransparency=1 end
	defeatStatus.Text="RECONSTRUCTING RIFT FRAME  //  3"
	defeatTitle.TextTransparency=1; defeatStatus.TextTransparency=1; defeatRule.BackgroundTransparency=1
	TweenService:Create(defeatShade,TweenInfo.new(.42,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{BackgroundTransparency=.015}):Play()
	TweenService:Create(defeatTitle,TweenInfo.new(.32,Enum.EasingStyle.Quad),{TextTransparency=0}):Play()
	TweenService:Create(defeatStatus,TweenInfo.new(.38,Enum.EasingStyle.Quad),{TextTransparency=0}):Play()
	TweenService:Create(defeatRule,TweenInfo.new(.3),{BackgroundTransparency=.08}):Play()
	task.delay(.44,function()
		if defeatShade:GetAttribute("TransitionState")=="Covering" then defeatShade:SetAttribute("TransitionState","Covered") end
	end)
	task.spawn(function()
		for remaining=3,1,-1 do
			local current=defeatShade:GetAttribute("TransitionState")
			if current~="Covering" and current~="Covered" then return end
			defeatStatus.Text="RECONSTRUCTING RIFT FRAME  //  "..remaining
			task.wait(.68)
		end
		if defeatShade:GetAttribute("TransitionState")=="Covered" then defeatStatus.Text="SYNCING WITH SANCTUM…" end
	end)
end
local function hideDefeatTransition()
	local state=defeatShade:GetAttribute("TransitionState")
	if state=="Hidden" or state=="Revealing" then return end
	defeatShade:SetAttribute("TransitionState","Revealing")
	defeatStatus.Text="FRAME RESTORED  //  RETURNING TO SANCTUM"
	task.delay(.28,function()
		if defeatShade:GetAttribute("TransitionState")~="Revealing" then return end
		TweenService:Create(defeatShade,TweenInfo.new(.52,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{BackgroundTransparency=1}):Play()
		TweenService:Create(defeatTitle,TweenInfo.new(.3),{TextTransparency=1}):Play()
		TweenService:Create(defeatStatus,TweenInfo.new(.3),{TextTransparency=1}):Play()
		TweenService:Create(defeatRule,TweenInfo.new(.3),{BackgroundTransparency=1}):Play()
		task.delay(.54,function()
			if defeatShade:GetAttribute("TransitionState")=="Revealing" then
				defeatShade.Visible=false; defeatShade:SetAttribute("TransitionState","Hidden")
			end
		end)
	end)
end

-- Title screen
local titleScreen = Instance.new("Frame")
titleScreen.Size = UDim2.fromScale(1,1)
titleScreen.BackgroundColor3 = Color3.fromRGB(7,9,16)
titleScreen.BackgroundTransparency = 0.28
titleScreen.Name = "TitleScreen"
titleScreen.ZIndex = 20
titleScreen.Active = true
titleScreen.Parent = gui
gradient(titleScreen, Color3.fromRGB(8,10,20), Color3.fromRGB(18,11,34), 35)

-- The opening frame should communicate the product before the player reads a
-- menu. This procedural rift mark keeps the title art self-contained and
-- avoids depending on an unlicensed splash image.
do
	local topBar=Instance.new("Frame")
	topBar.Size=UDim2.new(1,0,0,4); topBar.BackgroundColor3=Color3.fromRGB(83,205,238)
	topBar.BackgroundTransparency=.18; topBar.BorderSizePixel=0; topBar.ZIndex=21; topBar.Parent=titleScreen
	gradient(topBar,Color3.fromRGB(83,205,238),Color3.fromRGB(158,82,255),0)
	local bottomBar=topBar:Clone(); bottomBar.AnchorPoint=Vector2.new(0,1); bottomBar.Position=UDim2.fromScale(0,1); bottomBar.Parent=titleScreen

	local art=Instance.new("Frame")
	art.Name="RiftKeyArt"; art.Size=UDim2.fromOffset(310,310); art.AnchorPoint=Vector2.new(.5,.5)
	art.Position=UDim2.new(.73,0,.47,0); art.BackgroundTransparency=1; art.ZIndex=21; art.Parent=titleScreen
	for index,size in ipairs({286,230,174}) do
		local ring=Instance.new("Frame")
		ring.Name="Orbit"..index; ring.Size=UDim2.fromOffset(size,size); ring.AnchorPoint=Vector2.new(.5,.5)
		ring.Position=UDim2.fromScale(.5,.5); ring.BackgroundTransparency=1; ring.ZIndex=21; ring.Parent=art
		corner(ring,size/2)
		local outline=stroke(ring,index==2 and Color3.fromRGB(158,82,255) or Color3.fromRGB(83,205,238),.48, index==2 and 3 or 2)
		outline.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
		local notch=Instance.new("Frame")
		notch.Size=UDim2.fromOffset(index==2 and 54 or 34,4); notch.AnchorPoint=Vector2.new(.5,.5)
		notch.Position=UDim2.new(.5,0,0,0); notch.BackgroundColor3=index==2 and Color3.fromRGB(235,91,191) or Color3.fromRGB(94,220,247)
		notch.BorderSizePixel=0; notch.ZIndex=22; notch.Parent=ring; corner(notch,2)
		task.spawn(function()
			local direction=index==2 and -1 or 1
			while ring.Parent do
				local dt=RunService.RenderStepped:Wait()
				ring.Rotation=(ring.Rotation+dt*(5+index*3)*direction)%360
			end
		end)
	end
	local core=Instance.new("Frame")
	core.Size=UDim2.fromOffset(92,156); core.AnchorPoint=Vector2.new(.5,.5); core.Position=UDim2.fromScale(.5,.5)
	core.BackgroundColor3=Color3.fromRGB(76,54,164); core.BackgroundTransparency=.12; core.BorderSizePixel=0; core.Rotation=12
	core.ZIndex=22; core.Parent=art; corner(core,42); stroke(core,Color3.fromRGB(109,224,247),.08,2)
	gradient(core,Color3.fromRGB(62,221,244),Color3.fromRGB(172,56,225),90)
	local coreCut=Instance.new("Frame")
	coreCut.Size=UDim2.fromOffset(30,120); coreCut.AnchorPoint=Vector2.new(.5,.5); coreCut.Position=UDim2.fromScale(.5,.5)
	coreCut.BackgroundColor3=Color3.fromRGB(8,10,20); coreCut.BackgroundTransparency=.05; coreCut.BorderSizePixel=0
	coreCut.ZIndex=23; coreCut.Parent=core; corner(coreCut,15)
	local artLabel=makeText(art,"RIFT SIGNAL  //  STABLE",UDim2.new(1,0,0,20),UDim2.new(0,0,1,-4),10,true)
	artLabel.TextXAlignment=Enum.TextXAlignment.Center; artLabel.TextColor3=Color3.fromRGB(111,214,239); artLabel.ZIndex=22
end

local titleEyebrow = Instance.new("TextLabel")
titleEyebrow.BackgroundTransparency = 1
titleEyebrow.Size = UDim2.new(0.48,0,0,22)
titleEyebrow.Position = UDim2.new(0.09,0,0.245,0)
titleEyebrow.Text = "PUBLIC ALPHA  //  CHAPTER 01"
titleEyebrow.Visible = true
titleEyebrow.TextColor3 = Color3.fromRGB(95,220,255)
titleEyebrow.Font = Enum.Font.GothamBold
titleEyebrow.TextSize = 12
titleEyebrow.TextTransparency = 0.08
titleEyebrow.TextXAlignment = Enum.TextXAlignment.Left
titleEyebrow.Parent = titleScreen

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(0.5,0,0.12,0)
title.Position = UDim2.new(0.09,0,0.29,0)
title.Text = "RIFT PROTOCOL"
title.TextColor3 = Color3.fromRGB(245,246,255)
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleScreen

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Size = UDim2.new(0.48,0,0.04,0)
subtitle.Position = UDim2.new(0.09,0,0.43,0)
subtitle.Text = "THE VEIL IS BREAKING"
subtitle.TextColor3 = Color3.fromRGB(145,135,255)
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextScaled = true
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = titleScreen

local sessionPromise = Instance.new("TextLabel")
sessionPromise.BackgroundTransparency = 1
sessionPromise.Size = UDim2.new(0.5,0,0,20)
sessionPromise.Position = UDim2.new(0.09,0,0.495,0)
sessionPromise.Text = "BREAK THEIR GUARD  ·  EXECUTE THE FALLEN  ·  UNLEASH RIFT SURGE"
sessionPromise.Visible = true
sessionPromise.TextColor3 = Color3.fromRGB(178,186,210)
sessionPromise.Font = Enum.Font.GothamMedium
sessionPromise.TextSize = 11
sessionPromise.Parent = titleScreen

local enter = makeButton(titleScreen, "CONTINUE  //  ENTER SANCTUM", UDim2.new(0,320,0,52), UDim2.new(0.09,0,0.56,0))
enter.Name = "EnterRift"
enter.BackgroundColor3 = Color3.fromRGB(76,62,204)
effectSettings.StyleActionButton(enter,Color3.fromRGB(107,215,238),">",true)
local titleHint = makeText(titleScreen, "ENTER / SPACE / MOVE TO CONTINUE", UDim2.new(0,360,0,18), UDim2.new(.09,0,.655,0), 10, true)
titleHint.TextXAlignment = Enum.TextXAlignment.Left
titleHint.TextColor3 = Color3.fromRGB(115,199,225)
local titleDismissed = false
local function dismissTitle()
	if titleDismissed then return end
	titleDismissed = true
	TweenService:Create(titleScreen, TweenInfo.new(0.35), {BackgroundTransparency = 1}):Play()
	for _,d in ipairs(titleScreen:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			TweenService:Create(d, TweenInfo.new(0.25), {TextTransparency = 1, BackgroundTransparency = 1}):Play()
		end
	end
	task.delay(0.38, function()
        titleScreen.Visible = false
        titleScreen.Active = false
        hud.Visible = true
        restorePlayerControl(player.Character)
    end)
end
enter.Activated:Connect(dismissTitle)

-- Brand
local brand = makeText(hud, "RIFT PROTOCOL", UDim2.new(0,235,0,28), UDim2.new(0,22,0,18), 18, true)
brand.TextColor3 = Color3.fromRGB(220,224,255)
local version = makeText(hud, "LIVE BUILD  //  CHAPTER 01", UDim2.new(0,230,0,18), UDim2.new(0,23,0,44), 10, false)
version.TextColor3 = Color3.fromRGB(94,203,232)
do
	local brandRule=Instance.new("Frame")
	brandRule.Size=UDim2.fromOffset(186,2); brandRule.Position=UDim2.fromOffset(22,64)
	brandRule.BackgroundColor3=Color3.fromRGB(91,205,233); brandRule.BorderSizePixel=0; brandRule.Parent=hud
	gradient(brandRule,Color3.fromRGB(91,205,233),Color3.fromRGB(151,80,239),0)
end

-- Profile panel
local statsPanel = Instance.new("Frame")
statsPanel.Size = UDim2.new(0,244,0,148)
statsPanel.Position = UDim2.new(0,18,0,78)
statsPanel.BackgroundColor3 = Color3.fromRGB(14,19,31)
statsPanel.BackgroundTransparency = 0.08
statsPanel.Parent = hud
effectSettings.PanelChrome(statsPanel,Color3.fromRGB(117,102,238),"FRAME")

do
	local frameEmblem=Instance.new("Frame")
	frameEmblem.Name="FrameEmblem"; frameEmblem.Size=UDim2.fromOffset(52,52); frameEmblem.Position=UDim2.fromOffset(12,18)
	frameEmblem.BackgroundColor3=Color3.fromRGB(25,28,55); frameEmblem.BorderSizePixel=0; frameEmblem.Parent=statsPanel
	corner(frameEmblem,4); stroke(frameEmblem,Color3.fromRGB(101,205,235),.16,1.25)
	gradient(frameEmblem,Color3.fromRGB(55,45,119),Color3.fromRGB(14,21,38),110)
	local emblemText=makeText(frameEmblem,"RP",UDim2.fromScale(1,1),UDim2.fromScale(0,0),18,true)
	emblemText.TextXAlignment=Enum.TextXAlignment.Center; emblemText.TextColor3=Color3.fromRGB(208,226,255)
	local crCaption=makeText(statsPanel,"COMBAT RATING",UDim2.fromOffset(146,16),UDim2.fromOffset(74,18),8,true)
	crCaption.TextColor3=Color3.fromRGB(117,191,222)
end
local crText = makeText(statsPanel, "CR 0000", UDim2.fromOffset(152,30), UDim2.fromOffset(74,34), 22, true)
crText.TextColor3 = Color3.fromRGB(160,145,255)
do
	local statsRule=Instance.new("Frame")
	statsRule.Size=UDim2.new(1,-24,0,1); statsRule.Position=UDim2.fromOffset(12,79)
	statsRule.BackgroundColor3=Color3.fromRGB(83,98,130); statsRule.BackgroundTransparency=.35; statsRule.BorderSizePixel=0; statsRule.Parent=statsPanel
end
local atkText = makeText(statsPanel, "ATK", UDim2.new(.5,-14,0,22), UDim2.fromOffset(12,88), 12, true)
local defText = makeText(statsPanel, "DEF", UDim2.new(.5,-14,0,22), UDim2.new(.5,2,0,88), 12, true)
local hpText = makeText(statsPanel, "HP", UDim2.new(1,-24,0,22), UDim2.fromOffset(12,116), 12, true)
atkText.TextColor3=Color3.fromRGB(242,156,122); defText.TextColor3=Color3.fromRGB(116,206,238); hpText.TextColor3=Color3.fromRGB(117,224,174)

-- Currency
local currency = Instance.new("Frame")
currency.Size = UDim2.new(0,250,0,58)
currency.Position = UDim2.new(1,-268,0,18)
currency.BackgroundColor3 = Color3.fromRGB(12,16,27)
currency.BackgroundTransparency = 0.08
currency.Parent = hud
effectSettings.PanelChrome(currency,Color3.fromRGB(222,170,82),"WALLET")
local creditsText = makeText(currency, "CREDITS  0", UDim2.new(.52,-14,0,24), UDim2.new(0,12,0,22), 12, true)
local shardsText = makeText(currency, "SHARDS  0", UDim2.new(.48,-12,0,24), UDim2.new(.52,2,0,22), 12, true)
shardsText.TextColor3 = Color3.fromRGB(130,205,255)

-- Mission status
local missionChip = Instance.new("Frame")
missionChip.Size = UDim2.new(0,500,0,54)
missionChip.Position = UDim2.new(0.5,-250,0,15)
missionChip.BackgroundColor3 = Color3.fromRGB(10,15,26)
missionChip.BackgroundTransparency = 0.18
missionChip.BorderSizePixel = 0
missionChip.Parent = hud
effectSettings.PanelChrome(missionChip,Color3.fromRGB(91,205,233),"OBJECTIVE")
local missionAccent=Instance.new("Frame")
missionAccent.Size=UDim2.new(0,3,1,-12); missionAccent.Position=UDim2.fromOffset(0,6)
missionAccent.BackgroundColor3=Color3.fromRGB(91,205,233); missionAccent.BorderSizePixel=0; missionAccent.Parent=missionChip
corner(missionAccent,2)

local missionText = Instance.new("TextLabel")
missionText.BackgroundTransparency = 1
missionText.Size = UDim2.new(1,-34,0,23)
missionText.Position = UDim2.fromOffset(16,9)
missionText.Text = "LOBBY // PREPARE YOUR FRAME"
missionText.TextColor3 = Color3.fromRGB(224,230,244)
missionText.Font = Enum.Font.GothamBold
missionText.TextSize = 13
missionText.TextXAlignment = Enum.TextXAlignment.Left
missionText.Parent = missionChip
local objectiveText = makeText(missionChip, "ENTER THE RIFT  /  COMPLETE THE EXPEDITION", UDim2.new(1,-32,0,17), UDim2.fromOffset(16,31), 9, true)
objectiveText.TextXAlignment = Enum.TextXAlignment.Left
objectiveText.TextColor3 = Color3.fromRGB(105,214,240)

-- Lobby actions
local lobbyPanel = Instance.new("Frame")
lobbyPanel.Size = UDim2.new(0,320,0,154)
lobbyPanel.Position = UDim2.new(1,-338,1,-182)
lobbyPanel.BackgroundColor3 = Color3.fromRGB(12,16,27)
lobbyPanel.BackgroundTransparency = 0.04
lobbyPanel.Name = "LobbyPanel"
lobbyPanel.Parent = hud
effectSettings.PanelChrome(lobbyPanel,Color3.fromRGB(124,99,244),"LOADOUT")

local lpTitle = makeText(lobbyPanel, "FRAME LOADOUT", UDim2.new(1,-24,0,28), UDim2.new(0,12,0,14), 15, true)
local masteryButton = makeButton(lobbyPanel, "UNLOCK NEXT MASTERY", UDim2.new(1,-24,0,40), UDim2.new(0,12,0,52))
local coreButton = makeButton(lobbyPanel, "UPGRADE ASSAULT CORE", UDim2.new(1,-24,0,40), UDim2.new(0,12,0,100))
effectSettings.StyleActionButton(masteryButton,Color3.fromRGB(127,111,246),"M",true)
effectSettings.StyleActionButton(coreButton,Color3.fromRGB(80,204,234),"C",true)
local startButton = makeButton(hud, "ENTER ASHEN SANCTUM", UDim2.fromOffset(460,68), UDim2.new(.5,-230,1,-92))
startButton.BackgroundColor3 = Color3.fromRGB(82,66,220)
effectSettings.StyleActionButton(startButton,Color3.fromRGB(116,103,255),"01",true)
local trainingButton = makeButton(hud,"TRAINING GROUND",UDim2.fromOffset(220,48),UDim2.new(.5,-230,1,-150))
trainingButton.Name="StartTraining"; trainingButton.BackgroundColor3=Color3.fromRGB(108,76,42)
effectSettings.StyleActionButton(trainingButton,Color3.fromRGB(225,159,72),"TRN",true)
local duelButton = makeButton(hud,"RIFT DUEL",UDim2.fromOffset(220,48),UDim2.new(.5,10,1,-150))
duelButton.Name="ToggleDuelQueue"; duelButton.BackgroundColor3=Color3.fromRGB(61,48,128)
effectSettings.StyleActionButton(duelButton,Color3.fromRGB(185,92,236),"PVP",true)

-- Productized chapter card: one clear CTA, replay value and reward promise.
local chapterCard = Instance.new("Frame")
chapterCard.Name = "ChapterCard"
chapterCard.Size = UDim2.fromOffset(320,228)
chapterCard.Position = UDim2.new(1,-338,0,94)
chapterCard.BackgroundColor3 = Color3.fromRGB(10,15,28)
chapterCard.BackgroundTransparency = .05
chapterCard.Parent = hud
effectSettings.PanelChrome(chapterCard,Color3.fromRGB(93,91,220),"EXPEDITION")
gradient(chapterCard,Color3.fromRGB(20,24,47),Color3.fromRGB(10,15,28),115)
local chapterKicker = makeText(chapterCard,"CHAPTER 01  //  MAIN EXPEDITION",UDim2.new(1,-28,0,20),UDim2.fromOffset(14,17),10,true)
chapterKicker.TextColor3=Color3.fromRGB(112,207,235)
local chapterTitle = makeText(chapterCard,"ASHEN SANCTUM",UDim2.new(1,-28,0,32),UDim2.fromOffset(14,42),22,true)
local chapterDesc = makeText(chapterCard,"BREAK  →  EXECUTE  →  SURGE\n5 ENCOUNTERS  ·  ASHEN WARDEN",UDim2.new(1,-28,0,42),UDim2.fromOffset(14,78),10,true)
chapterDesc.TextWrapped=true; chapterDesc.TextColor3=Color3.fromRGB(158,168,196)
local chapterPower = makeText(chapterCard,"RECOMMENDED POWER  900",UDim2.new(1,-28,0,20),UDim2.fromOffset(14,124),11,true)
chapterPower.TextColor3=Color3.fromRGB(198,188,255)
local rewardPreview = makeText(chapterCard,"REWARDS  300 C  ·  4 SHARDS  ·  BOSS WEAPON",UDim2.new(1,-28,0,20),UDim2.fromOffset(14,149),10,true)
rewardPreview.TextColor3=Color3.fromRGB(225,183,105)
local difficultyButton = makeButton(chapterCard,"DIFFICULTY  NORMAL",UDim2.new(1,-28,0,38),UDim2.fromOffset(14,179))
difficultyButton.Name="DifficultyToggle"
effectSettings.StyleActionButton(difficultyButton,Color3.fromRGB(222,170,82),"D",true)
difficultyButton.Activated:Connect(function()
	local nextMode = profile and profile.Difficulty == "HARD" and "NORMAL" or "HARD"
	Action:FireServer("SetDifficulty",nextMode)
end)

local questCard = Instance.new("Frame")
questCard.Name="QuestCard"; questCard.Size=UDim2.fromOffset(244,132); questCard.Position=UDim2.new(0,18,1,-150)
questCard.BackgroundColor3=Color3.fromRGB(12,17,30); questCard.BackgroundTransparency=.05; questCard.Parent=hud
questCard.Visible=not UserInputService.TouchEnabled
effectSettings.PanelChrome(questCard,Color3.fromRGB(225,169,82),"DAILY")
local questKicker=makeText(questCard,"FIRST DIRECTIVE",UDim2.new(1,-24,0,20),UDim2.fromOffset(12,14),12,true)
questKicker.TextColor3=Color3.fromRGB(236,188,105)
local questProgress=makeText(questCard,"DEFEAT RIFTBOUND  0 / 12",UDim2.new(1,-24,0,20),UDim2.fromOffset(12,39),10,true)
local questReward=makeText(questCard,"REWARD  180 C  +  1 SHARD",UDim2.new(1,-24,0,18),UDim2.fromOffset(12,61),9,false)
questReward.TextColor3=Color3.fromRGB(145,158,190)
local questButton=makeButton(questCard,"IN PROGRESS",UDim2.new(1,-24,0,34),UDim2.fromOffset(12,90))
questButton.Name="ClaimQuest"
effectSettings.StyleActionButton(questButton,Color3.fromRGB(225,169,82),"Q",true)
questButton.Activated:Connect(function() Action:FireServer("ClaimQuest") end)

masteryButton.Name = "UpgradeMastery"
coreButton.Name = "UpgradeCore"
startButton.Name = "StartMission"
masteryButton.Activated:Connect(function() Action:FireServer("UpgradeMastery") end)
coreButton.Activated:Connect(function() Action:FireServer("UpgradeCore") end)
local function requestMissionStart()
    if inMission or missionRequestPending or titleScreen.Visible then return end
    missionRequestPending = true
    startButton.Text = "OPENING RIFT..."
    restorePlayerControl(player.Character)
    Action:FireServer("StartMission")
    task.delay(2.5, function()
        if missionRequestPending and not inMission then
            missionRequestPending = false
            startButton.Text = "RETRY RIFT MISSION"
        end
    end)
end
startButton.Activated:Connect(requestMissionStart)
trainingButton.Activated:Connect(function()
	if inMission or titleScreen.Visible then return end
	restorePlayerControl(player.Character)
	Action:FireServer("StartTraining")
end)
duelButton.Activated:Connect(function()
	if inMission or titleScreen.Visible then return end
	Action:FireServer("ToggleDuelQueue")
end)

-- Skill bar
local skillBar = Instance.new("Frame")
skillBar.Size = UDim2.new(0,680,0,92)
skillBar.Position = UDim2.new(0.5,-340,1,-116)
skillBar.BackgroundColor3 = Color3.fromRGB(10,13,22)
skillBar.BackgroundTransparency = 0.2
skillBar.Name = "SkillBar"
skillBar.Visible = false
skillBar.Parent = hud
effectSettings.PanelChrome(skillBar,Color3.fromRGB(84,138,184),"COMBAT ARRAY")

local keys = {"LMB","RMB","SPACE","Q","E","R"}
local names = {"COMBO","HEAVY BREAK","PHASE DODGE","RIFT SLASH","GUARD BREAK","RIFT SURGE"}
effectSettings.SkillSigils = {"I","II","↯","Q","E","R"}
effectSettings.SkillColors = {
	Color3.fromRGB(92,191,230), Color3.fromRGB(239,151,82), Color3.fromRGB(90,216,188),
	Color3.fromRGB(89,184,248), Color3.fromRGB(239,123,79), Color3.fromRGB(201,82,238),
}
local skillFrames = {}
for i,key in ipairs(keys) do
	local f = Instance.new("Frame")
	f.Name = "Skill_"..key
	f.Size = UDim2.new(0,102,0,72)
	f.Position = UDim2.new(0,10+(i-1)*110,0,12)
	f.BackgroundColor3 = Color3.fromRGB(22,27,43)
	f.Parent = skillBar
	corner(f, 4)
	stroke(f,effectSettings.SkillColors[i],.18,i==6 and 2 or 1.25)
	gradient(f,Color3.fromRGB(29,36,57),Color3.fromRGB(10,14,25),90)
	local charge=Instance.new("Frame")
	charge.Name="ChargeEdge"; charge.Size=UDim2.new(1,-10,0,3); charge.Position=UDim2.fromOffset(5,5)
	charge.BackgroundColor3=effectSettings.SkillColors[i]; charge.BorderSizePixel=0; charge.Parent=f
	local sigil=makeText(f,effectSettings.SkillSigils[i],UDim2.fromOffset(42,34),UDim2.new(.5,-21,0,13),18,true)
	sigil.TextXAlignment=Enum.TextXAlignment.Center; sigil.TextColor3=Color3.fromRGB(234,241,252)

	local k = makeText(f, key, UDim2.new(0,42,0,16), UDim2.new(1,-47,0,10), 8, true)
	k.TextXAlignment=Enum.TextXAlignment.Right; k.TextColor3 = effectSettings.SkillColors[i]
	local n = makeText(f, names[i], UDim2.new(1,-10,0,17), UDim2.new(0,5,1,-22), 8, true)
	n.TextXAlignment=Enum.TextXAlignment.Center; n.TextColor3 = Color3.fromRGB(218,222,240)

	local hit = Instance.new("TextButton")
	hit.Name = "Activate_"..key
	hit.Size = UDim2.fromScale(1,1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.ZIndex = 5
	hit.Parent = f
	local cd = Instance.new("TextLabel")
	cd.Name = "Cooldown"
	cd.Size = UDim2.fromScale(1,1)
	cd.BackgroundColor3 = Color3.fromRGB(5,8,16)
	cd.BackgroundTransparency = 0.25
	cd.Text = ""
	cd.TextColor3 = Color3.new(1,1,1)
	cd.Font = Enum.Font.GothamBold
	cd.TextSize = 22
	cd.Visible = false
	cd.ZIndex = 6
	cd.Parent = f
	corner(cd, 4)
	hit.MouseEnter:Connect(function() TweenService:Create(f,TweenInfo.new(.1),{BackgroundColor3=Color3.fromRGB(35,42,62)}):Play() end)
	hit.MouseLeave:Connect(function() TweenService:Create(f,TweenInfo.new(.1),{BackgroundColor3=Color3.fromRGB(22,27,43)}):Play() end)

	skillFrames[key] = {Frame=f, CD=cd, Button=hit, KeyLabel=k, NameLabel=n}
end

local surgePanel=Instance.new("Frame")
surgePanel.Name="SurgeMeter"; surgePanel.Size=UDim2.fromOffset(680,22); surgePanel.Position=UDim2.new(.5,-340,1,-144)
surgePanel.BackgroundColor3=Color3.fromRGB(10,14,27); surgePanel.BackgroundTransparency=.04
surgePanel.Visible=false; surgePanel.Parent=hud; corner(surgePanel,7); stroke(surgePanel,Color3.fromRGB(127,76,255),.34,1)
local surgeFill=Instance.new("Frame")
surgeFill.Name="Fill"; surgeFill.Size=UDim2.fromScale(0,1); surgeFill.BackgroundColor3=Color3.fromRGB(115,79,245)
surgeFill.BorderSizePixel=0; surgeFill.Parent=surgePanel; corner(surgeFill,7)
local surgeText=makeText(surgePanel,"RIFT SURGE  0%",UDim2.new(1,-18,1,0),UDim2.fromOffset(9,0),10,true)
surgeText.TextXAlignment=Enum.TextXAlignment.Center
local surgeValue=0
local function updateSurgeMeter(value,active)
	surgeValue=math.clamp(value or 0,0,100)
	TweenService:Create(surgeFill,TweenInfo.new(.18,Enum.EasingStyle.Quad),{Size=UDim2.fromScale(surgeValue/100,1)}):Play()
	local rSlot=skillFrames["R"]
	if active then
		surgeText.Text="OVERDRIVE ACTIVE  //  DAMAGE + SPEED BOOST"
		rSlot.NameLabel.Text="OVERDRIVE ACTIVE"; rSlot.Frame.BackgroundColor3=Color3.fromRGB(90,37,91)
	elseif surgeValue>=100 then
		surgeText.Text="ULTIMATE READY  //  PRESS R OR CLICK"
		rSlot.NameLabel.Text="PRESS R · SURGE"; rSlot.Frame.BackgroundColor3=Color3.fromRGB(82,34,83)
	else
		surgeText.Text=string.format("SURGE  %d%%  //  ATTACK · BREAK · EXECUTE TO CHARGE",surgeValue)
		rSlot.NameLabel.Text=string.format("ULTIMATE · %d%%",surgeValue); rSlot.Frame.BackgroundColor3=Color3.fromRGB(22,27,43)
	end
	surgeFill.BackgroundColor3=surgeValue>=100 and Color3.fromRGB(235,91,191) or Color3.fromRGB(115,79,245)
end

local combatCoach=Instance.new("Frame")
combatCoach.Name="CombatCoach"; combatCoach.Size=UDim2.fromOffset(680,58); combatCoach.Position=UDim2.new(.5,-340,1,-212)
combatCoach.BackgroundColor3=Color3.fromRGB(9,13,24); combatCoach.BackgroundTransparency=.06
combatCoach.Visible=false; combatCoach.Parent=hud; effectSettings.PanelChrome(combatCoach,Color3.fromRGB(98,168,235),"TACTICAL LINK")
local coachTitle=makeText(combatCoach,"COMBAT PROTOCOL",UDim2.fromOffset(170,20),UDim2.fromOffset(16,11),11,true)
coachTitle.TextColor3=Color3.fromRGB(106,213,240)
local coachText=makeText(combatCoach,"BREAK → F EXECUTE  ·  HIT TO CHARGE SURGE  ·  Q / E SKILLS  ·  SPACE DODGE",UDim2.new(1,-32,0,22),UDim2.fromOffset(16,31),10,true)
coachText.TextColor3=Color3.fromRGB(211,217,238)
local coachToken=0
local function showCombatCoach()
	coachToken+=1; local token=coachToken; combatCoach.Visible=true
	task.delay(8,function() if coachToken==token then combatCoach.Visible=false end end)
end
local function dismissCombatCoach() coachToken+=1; combatCoach.Visible=false end

effectSettings.TrainingExit=makeButton(hud,"B   RETURN TO SANCTUM",UDim2.fromOffset(210,38),UDim2.new(1,-230,0,116))
effectSettings.TrainingExit.Name="TrainingExit"
effectSettings.TrainingExit.Visible=false
effectSettings.TrainingExit.Activated:Connect(function()
	if trainingMode then Action:FireServer("ReturnLobby") end
end)

-- Notice
local notice = Instance.new("TextLabel")
notice.Size = UDim2.new(0,520,0,52)
notice.Position = UDim2.new(0.5,-260,0.76,0)
notice.BackgroundTransparency = 1
notice.Text = ""
notice.TextTransparency = 1
notice.TextColor3 = Color3.fromRGB(235,240,255)
notice.Font = Enum.Font.GothamBold
notice.TextSize = 20
notice.Parent = hud

local function showNotice(text, color)
	notice.Text = text
	notice.TextColor3 = color or Color3.fromRGB(235,240,255)
	notice.TextTransparency = 0
	notice.Position = UDim2.new(0.5,-260,0.76,0)
	TweenService:Create(notice, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1,
		Position = UDim2.new(0.5,-260,0.72,0),
	}):Play()
end

-- Result panel
local result = Instance.new("Frame")
result.Size = UDim2.new(0,700,0,460)
result.Position = UDim2.new(0.5,-350,0.5,-230)
result.BackgroundColor3 = Color3.fromRGB(10,13,23)
result.Visible = false
result.Name = "ResultPanel"
result.ZIndex = 30
result.Active = true
result.Parent = hud
corner(result, 16)
stroke(result, Color3.fromRGB(120,100,255), 0.12, 2)
gradient(result, Color3.fromRGB(18,22,40), Color3.fromRGB(10,13,23), 90)

local resultTitle = makeText(result, "EXPEDITION COMPLETE", UDim2.new(1,-40,0,44), UDim2.new(0,20,0,20), 27, true)
resultTitle.TextXAlignment = Enum.TextXAlignment.Center
local resultBody = makeText(result, "", UDim2.fromOffset(465,178), UDim2.fromOffset(200,92), 15, false)
resultBody.TextXAlignment = Enum.TextXAlignment.Left
resultBody.TextYAlignment = Enum.TextYAlignment.Top
local returnButton = makeButton(result, "RETURN TO HUB  /  LOADOUT", UDim2.fromOffset(250,46), UDim2.new(.5,-260,1,-66))
returnButton.Name = "ReturnLobby"
returnButton.Activated:Connect(function()
	result.Visible = false
	Action:FireServer("ReturnLobby")
end)

effectSettings.Result={}
do
	local accent=Instance.new("Frame")
	accent.Size=UDim2.new(1,-40,0,3); accent.Position=UDim2.fromOffset(20,68)
	accent.BackgroundColor3=Color3.fromRGB(104,211,237); accent.BorderSizePixel=0; accent.Parent=result
	gradient(accent,Color3.fromRGB(104,211,237),Color3.fromRGB(212,76,224),0)

	local gradeCard=Instance.new("Frame")
	gradeCard.Size=UDim2.fromOffset(142,178); gradeCard.Position=UDim2.fromOffset(30,92)
	gradeCard.BackgroundColor3=Color3.fromRGB(15,18,32); gradeCard.Parent=result
	corner(gradeCard,12); stroke(gradeCard,Color3.fromRGB(205,85,222),.18,1.5)
	effectSettings.Result.Grade=makeText(gradeCard,"S",UDim2.new(1,0,0,100),UDim2.fromOffset(0,14),72,true)
	effectSettings.Result.Grade.TextXAlignment=Enum.TextXAlignment.Center
	effectSettings.Result.GradeCaption=makeText(gradeCard,"RIFT GRADE",UDim2.new(1,0,0,25),UDim2.fromOffset(0,116),11,true)
	effectSettings.Result.GradeCaption.TextXAlignment=Enum.TextXAlignment.Center
	effectSettings.Result.Score=makeText(gradeCard,"SCORE 100",UDim2.new(1,0,0,24),UDim2.fromOffset(0,142),12,true)
	effectSettings.Result.Score.TextXAlignment=Enum.TextXAlignment.Center

	local best=makeText(result,"NEW PERSONAL BEST",UDim2.fromOffset(142,38),UDim2.fromOffset(30,286),11,true)
	best.TextXAlignment=Enum.TextXAlignment.Center; best.TextColor3=Color3.fromRGB(112,221,239)
	best.BackgroundColor3=Color3.fromRGB(13,32,43); best.BackgroundTransparency=.08
	corner(best,8); stroke(best,Color3.fromRGB(92,211,231),.24,1)
	effectSettings.Result.Best=best

	local lootCard=Instance.new("Frame")
	lootCard.Size=UDim2.fromOffset(465,76); lootCard.Position=UDim2.fromOffset(200,286)
	lootCard.BackgroundColor3=Color3.fromRGB(17,20,35); lootCard.Parent=result
	corner(lootCard,10); stroke(lootCard,Color3.fromRGB(229,178,91),.18,1.2)
	local lootHeader=makeText(lootCard,"BOSS DROP  //  ASHEN WARDEN",UDim2.new(1,-24,0,22),UDim2.fromOffset(12,9),10,true)
	lootHeader.TextColor3=Color3.fromRGB(229,178,91)
	effectSettings.Result.Loot=makeText(lootCard,"",UDim2.new(1,-24,0,30),UDim2.fromOffset(12,35),14,true)

	effectSettings.Result.Restart=makeButton(result,"RUN AGAIN  /  IMPROVE GRADE",UDim2.fromOffset(250,46),UDim2.new(.5,10,1,-66))
	effectSettings.Result.Restart.Name="RestartMission"
	effectSettings.Result.Restart.Activated:Connect(function()
		result.Visible=false
		Action:FireServer("RestartMission")
	end)
end

local runePanel = Instance.new("Frame")
runePanel.Name = "RuneChoice"
runePanel.Size = UDim2.fromScale(1,1)
runePanel.BackgroundColor3 = Color3.fromRGB(8,12,24)
runePanel.BackgroundTransparency = .14
runePanel.Visible = false
runePanel.Active = true
runePanel.ZIndex = 34
runePanel.Parent = hud
local runeTitle = makeText(runePanel, "THE RIFT OFFERS A CHOICE", UDim2.new(1,0,0,52), UDim2.new(0,0,.18,0), 27, true)
runeTitle.TextXAlignment = Enum.TextXAlignment.Center
runeTitle.ZIndex = 35
local runeCards = {}
for i=1,3 do
	local card = makeButton(runePanel,"", UDim2.fromOffset(214,238), UDim2.new(.5,-331+(i-1)*224,.37,0))
	card.ZIndex = 36
	card.Text = ""
	local tag = makeText(card,"",UDim2.new(1,-24,0,25),UDim2.fromOffset(12,19),13,true)
	tag.TextColor3 = Color3.fromRGB(189,153,104); tag.ZIndex = 37
	local name = makeText(card,"",UDim2.new(1,-24,0,54),UDim2.fromOffset(12,58),19,true)
	name.TextWrapped = true; name.ZIndex = 37
	local desc = makeText(card,"",UDim2.new(1,-24,0,91),UDim2.fromOffset(12,128),13,false)
	desc.TextWrapped = true; desc.TextYAlignment = Enum.TextYAlignment.Top; desc.ZIndex = 37
	card.Activated:Connect(function()
		if card:GetAttribute("RuneId") then Action:FireServer("ChooseRune", card:GetAttribute("RuneId")) end
	end)
	runeCards[i] = {Card=card, Tag=tag, Name=name, Description=desc}
end

-- Health
local healthPanel = Instance.new("Frame")
healthPanel.Size = UDim2.new(0,338,0,28)
healthPanel.Position = UDim2.new(0,24,1,-154)
healthPanel.BackgroundColor3 = Color3.fromRGB(17,22,32)
healthPanel.Name = "HealthPanel"
healthPanel.Visible = false
healthPanel.Parent = hud
corner(healthPanel, 3); stroke(healthPanel,Color3.fromRGB(79,164,132),.3,1)
local healthFill = Instance.new("Frame")
healthFill.Size = UDim2.new(1,-4,1,-4); healthFill.Position=UDim2.fromOffset(2,2)
healthFill.BackgroundColor3 = Color3.fromRGB(70,220,160)
healthFill.Parent = healthPanel
corner(healthFill, 2); gradient(healthFill,Color3.fromRGB(83,224,164),Color3.fromRGB(31,124,105),0)
local healthLabel = makeText(healthPanel, "FRAME INTEGRITY", UDim2.fromScale(1,1), UDim2.fromScale(0,0), 10, true)
healthLabel.TextXAlignment = Enum.TextXAlignment.Left
do
	local hpPadding=Instance.new("UIPadding"); hpPadding.PaddingLeft=UDim.new(0,12); hpPadding.Parent=healthLabel
end
local staminaPanel = Instance.new("Frame")
staminaPanel.Name = "StaminaPanel"
staminaPanel.Size = UDim2.fromOffset(270,10)
staminaPanel.Position = UDim2.new(0,24,1,-118)
staminaPanel.BackgroundColor3 = Color3.fromRGB(26,34,37)
staminaPanel.Visible = false
staminaPanel.Parent = hud
corner(staminaPanel, 2); stroke(staminaPanel,Color3.fromRGB(94,190,178),.48,1)
local staminaFill = Instance.new("Frame")
staminaFill.Size = UDim2.fromScale(1,1)
staminaFill.BackgroundColor3 = Color3.fromRGB(88,205,170)
staminaFill.Parent = staminaPanel
corner(staminaFill, 2); gradient(staminaFill,Color3.fromRGB(91,218,193),Color3.fromRGB(47,131,145),0)
local function updateStamina()
	staminaFill.Size = UDim2.fromScale(math.clamp((player:GetAttribute("Stamina") or 100)/100,0,1),1)
end
player:GetAttributeChangedSignal("Stamina"):Connect(updateStamina)
updateStamina()

local bossPanel = Instance.new("Frame")
bossPanel.Name = "BossStatus"
bossPanel.Size = UDim2.fromOffset(560,78)
bossPanel.Position = UDim2.new(.5,-280,0,24)
bossPanel.BackgroundColor3 = Color3.fromRGB(20,21,31)
bossPanel.BackgroundTransparency = .04
bossPanel.Visible = false
bossPanel.Parent = hud
effectSettings.PanelChrome(bossPanel,Color3.fromRGB(215,73,116),"BOSS AUTHORITY")
local bossTitle = makeText(bossPanel,"ASHEN WARDEN",UDim2.new(1,-24,0,25),UDim2.fromOffset(14,8),17,true)
bossTitle.TextXAlignment = Enum.TextXAlignment.Left
local bossHealthBack = Instance.new("Frame")
bossHealthBack.Size=UDim2.new(1,-28,0,15); bossHealthBack.Position=UDim2.fromOffset(14,38)
bossHealthBack.BackgroundColor3=Color3.fromRGB(43,38,43); bossHealthBack.Parent=bossPanel
local bossHealthFill=Instance.new("Frame")
bossHealthFill.Size=UDim2.fromScale(1,1); bossHealthFill.BackgroundColor3=Color3.fromRGB(209,78,77); bossHealthFill.Parent=bossHealthBack
local bossPoiseBack=Instance.new("Frame")
bossPoiseBack.Size=UDim2.new(1,-28,0,5); bossPoiseBack.Position=UDim2.fromOffset(14,61)
bossPoiseBack.BackgroundColor3=Color3.fromRGB(51,51,59); bossPoiseBack.Parent=bossPanel
local bossPoiseFill=Instance.new("Frame")
bossPoiseFill.Size=UDim2.fromScale(1,1); bossPoiseFill.BackgroundColor3=Color3.fromRGB(223,172,106); bossPoiseFill.Parent=bossPoiseBack

effectSettings.BossAttack={}
do
	local banner=Instance.new("Frame")
	banner.Name="BossAttackWarning"; banner.Size=UDim2.fromOffset(420,42)
	banner.Position=UDim2.new(.5,-210,0,108); banner.BackgroundColor3=Color3.fromRGB(19,12,22)
	banner.BackgroundTransparency=.08; banner.Visible=false; banner.Parent=hud
	corner(banner,7)
	local bannerStroke=stroke(banner,Color3.fromRGB(237,83,118),.12,1.5)
	local warningText=makeText(banner,"WARDEN CLEAVE  //  DODGE",UDim2.new(1,-24,0,25),UDim2.fromOffset(12,5),12,true)
	warningText.TextXAlignment=Enum.TextXAlignment.Center
	local timer=Instance.new("Frame")
	timer.Size=UDim2.new(1,-16,0,3); timer.Position=UDim2.new(0,8,1,-7)
	timer.BorderSizePixel=0; timer.BackgroundColor3=Color3.fromRGB(245,83,122); timer.Parent=banner
	local warningToken=0
	function effectSettings.BossAttack.Show(mode,duration)
		warningToken+=1; local token=warningToken
		local labels={Cleave="CLEAVE  //  DODGE THROUGH",Sweep="SWEEP  //  CLEAR THE RADIUS",RiftPulse="RIFT PULSE  //  EVADE NOW"}
		local colors={Cleave=Color3.fromRGB(245,83,104),Sweep=Color3.fromRGB(255,146,69),RiftPulse=Color3.fromRGB(224,80,205)}
		local color=colors[mode] or colors.Cleave
		warningText.Text="WARDEN "..(labels[mode] or string.upper(tostring(mode or "ATTACK")))
		warningText.TextColor3=color; bannerStroke.Color=color; timer.BackgroundColor3=color
		timer.Size=UDim2.new(1,-16,0,3); banner.Visible=true
		TweenService:Create(timer,TweenInfo.new(duration or .9,Enum.EasingStyle.Linear),{Size=UDim2.new(0,0,0,3)}):Play()
		task.delay((duration or .9)+.22,function() if warningToken==token then banner.Visible=false end end)
	end
	function effectSettings.BossAttack.Phase(data)
		local position=data.Position
		if position then
			for i=1,2 do
				local ring=Instance.new("Part")
				ring.Name="WardenPhaseRing"; ring.Shape=Enum.PartType.Cylinder; ring.Size=Vector3.new(.12,2,2)
				ring.Material=Enum.Material.Neon; ring.Color=(data.Phase or 2)>=3 and Color3.fromRGB(255,67,145) or Color3.fromRGB(202,85,238)
				ring.Transparency=.18; ring.Anchored=true; ring.CanCollide=false; ring.CanTouch=false; ring.CanQuery=false
				ring.CFrame=CFrame.new(position)*CFrame.Angles(0,0,math.rad(90)); ring.Parent=workspace
				task.delay((i-1)*.12,function()
					TweenService:Create(ring,TweenInfo.new(.55,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=Vector3.new(.08,24+i*7,24+i*7),Transparency=1}):Play()
				end)
				Debris:AddItem(ring,.9)
			end
		end
		cameraShake=math.max(cameraShake,.62)
		bossHealthFill.BackgroundColor3=(data.Phase or 2)>=3 and Color3.fromRGB(239,59,118) or Color3.fromRGB(204,74,177)
		showNotice((data.Phase or 2)>=3 and "FINAL PHASE  //  RIFT COLLAPSE" or "PHASE II  //  THE WARDEN UNBOUND",Color3.fromRGB(244,105,172))
	end
	function effectSettings.BossAttack.Hide()
		warningToken+=1
		banner.Visible=false
	end
end

-- A short non-blocking chapter boss reveal gives wave five a clear dramatic
-- beat without taking camera control away from the player.
effectSettings.BossIntro={}
do
	local frame=Instance.new("Frame")
	frame.Name="BossIntroduction"; frame.Size=UDim2.fromScale(1,1); frame.BackgroundColor3=Color3.fromRGB(3,4,9)
	-- Use the inset-free transition layer so the letterbox reaches every edge
	-- on desktop, mobile and Studio's docked viewport.
	frame.BackgroundTransparency=1; frame.Visible=false; frame.Active=false; frame.ZIndex=60; frame.Parent=defeatLayer
	frame:SetAttribute("Token",0)
	local top=Instance.new("Frame"); top.Size=UDim2.new(1,0,0,0); top.Position=UDim2.fromScale(0,0)
	top.BackgroundColor3=Color3.fromRGB(4,5,11); top.BorderSizePixel=0; top.ZIndex=61; top.Parent=frame
	local bottom=Instance.new("Frame"); bottom.Size=UDim2.new(1,0,0,0); bottom.AnchorPoint=Vector2.new(0,1); bottom.Position=UDim2.fromScale(0,1)
	bottom.BackgroundColor3=Color3.fromRGB(4,5,11); bottom.BorderSizePixel=0; bottom.ZIndex=61; bottom.Parent=frame
	local rule=Instance.new("Frame"); rule.Size=UDim2.fromOffset(0,2); rule.Position=UDim2.new(.5,0,.5,-61)
	rule.BackgroundColor3=Color3.fromRGB(208,75,112); rule.BorderSizePixel=0; rule.ZIndex=62; rule.Parent=frame
	local kicker=makeText(frame,"CHAPTER 01  //  RIFT AUTHORITY",UDim2.fromOffset(520,22),UDim2.new(.5,-260,.5,-48),11,true)
	kicker.TextXAlignment=Enum.TextXAlignment.Center; kicker.TextColor3=Color3.fromRGB(114,207,234); kicker.TextTransparency=1; kicker.ZIndex=62
	local title=makeText(frame,"ASHEN WARDEN",UDim2.fromOffset(700,58),UDim2.new(.5,-350,.5,-24),38,true)
	title.TextXAlignment=Enum.TextXAlignment.Center; title.TextColor3=Color3.fromRGB(242,226,235); title.TextTransparency=1; title.ZIndex=62
	local subtitle=makeText(frame,"BREAK THE CROWN  ·  SURVIVE THE RIFT PULSE",UDim2.fromOffset(600,24),UDim2.new(.5,-300,.5,38),11,true)
	subtitle.TextXAlignment=Enum.TextXAlignment.Center; subtitle.TextColor3=Color3.fromRGB(211,146,168); subtitle.TextTransparency=1; subtitle.ZIndex=62
	function effectSettings.BossIntro.Show()
		local token=(frame:GetAttribute("Token") or 0)+1; frame:SetAttribute("Token",token)
		frame.Visible=true; frame.BackgroundTransparency=1
		top.Size=UDim2.new(1,0,0,0); bottom.Size=UDim2.new(1,0,0,0); rule.Size=UDim2.fromOffset(0,2)
		kicker.TextTransparency=1; title.TextTransparency=1; subtitle.TextTransparency=1
		TweenService:Create(frame,TweenInfo.new(.24),{BackgroundTransparency=.58}):Play()
		TweenService:Create(top,TweenInfo.new(.32,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=UDim2.new(1,0,0,66)}):Play()
		TweenService:Create(bottom,TweenInfo.new(.32,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=UDim2.new(1,0,0,66)}):Play()
		TweenService:Create(rule,TweenInfo.new(.42,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(440,2),Position=UDim2.new(.5,-220,.5,-61)}):Play()
		TweenService:Create(kicker,TweenInfo.new(.28),{TextTransparency=0}):Play()
		TweenService:Create(title,TweenInfo.new(.34),{TextTransparency=0}):Play()
		TweenService:Create(subtitle,TweenInfo.new(.42),{TextTransparency=0}):Play()
		-- Hold the title long enough to read on a first encounter while combat
		-- remains fully interactive behind this presentation layer.
		task.delay(2.35,function()
			if frame:GetAttribute("Token")~=token then return end
			TweenService:Create(frame,TweenInfo.new(.4),{BackgroundTransparency=1}):Play()
			TweenService:Create(top,TweenInfo.new(.4),{Size=UDim2.new(1,0,0,0)}):Play()
			TweenService:Create(bottom,TweenInfo.new(.4),{Size=UDim2.new(1,0,0,0)}):Play()
			for _,label in ipairs({kicker,title,subtitle}) do TweenService:Create(label,TweenInfo.new(.24),{TextTransparency=1}):Play() end
			task.delay(.42,function() if frame:GetAttribute("Token")==token then frame.Visible=false end end)
		end)
	end
	function effectSettings.BossIntro.Hide()
		frame:SetAttribute("Token",(frame:GetAttribute("Token") or 0)+1); frame.Visible=false
	end
end
local bossConnections={}
local function detachBoss()
	for _, connection in ipairs(bossConnections) do connection:Disconnect() end
	table.clear(bossConnections)
	bossPanel.Visible=false
	missionChip.Visible=true
	effectSettings.BossAttack.Hide()
end
local function attachBoss()
	detachBoss()
	task.spawn(function()
		local deadline=os.clock()+8
		while inMission and os.clock()<deadline do
			local world=workspace:FindFirstChild("RIFT_WORLD")
			local mission=world and world:FindFirstChild("Mission")
			local enemies=mission and mission:FindFirstChild("Enemies")
			for _, enemy in ipairs(enemies and enemies:GetChildren() or {}) do
				if enemy:GetAttribute("Kind")=="Warden" and enemy:GetAttribute("OwnerUserId")==player.UserId then
					local function refresh()
						bossHealthFill.Size=UDim2.fromScale(math.clamp((enemy:GetAttribute("CurrentHP") or 0)/math.max(1,enemy:GetAttribute("MaxHP") or 1),0,1),1)
						bossPoiseFill.Size=UDim2.fromScale(math.clamp((enemy:GetAttribute("Poise") or 0)/math.max(1,enemy:GetAttribute("PoiseMax") or 1),0,1),1)
						bossTitle.Text="ASHEN WARDEN  /  PHASE "..tostring(enemy:GetAttribute("Phase") or 1)
					end
					table.insert(bossConnections,enemy:GetAttributeChangedSignal("CurrentHP"):Connect(refresh))
					table.insert(bossConnections,enemy:GetAttributeChangedSignal("Poise"):Connect(refresh))
					table.insert(bossConnections,enemy:GetAttributeChangedSignal("Phase"):Connect(refresh))
					refresh()
					missionChip.Visible=false
					bossPanel.Visible=true
					return
				end
			end
			task.wait(.15)
		end
	end)
end

-- Player-facing progression hub. These systems were already functional, but
-- this screen makes their power contribution and upgrade path visible.
local progressButton = makeButton(hud, "MASTERY & POWER", UDim2.new(0,224,0,40), UDim2.new(0,20,0,220))
progressButton.Name = "OpenProgression"
effectSettings.StyleActionButton(progressButton,Color3.fromRGB(133,105,244),"P",true)
local movementHint = makeText(hud, "MOVE  WASD  ·  SHIFT SPRINT", UDim2.new(0,224,0,20), UDim2.new(0,24,0,266), 10, true)
movementHint.TextColor3 = Color3.fromRGB(112,205,230)

-- Presentation controls keep impact readable without forcing intense flashes
-- or camera motion on every player.
local settingsButton = makeButton(hud, "DISPLAY SETTINGS", UDim2.new(0,224,0,36), UDim2.new(0,20,0,292))
settingsButton.Name = "OpenSettings"
effectSettings.StyleActionButton(settingsButton,Color3.fromRGB(91,173,215),"M",true)
local armoryButton = makeButton(hud, "EQUIPMENT", UDim2.new(0,224,0,36), UDim2.new(0,20,0,336))
armoryButton.Name = "OpenArmory"
effectSettings.StyleActionButton(armoryButton,Color3.fromRGB(226,158,77),"I",true)
effectSettings.SupportButton = makeButton(hud, "COSMETICS & SUPPORT", UDim2.new(0,224,0,36), UDim2.new(0,20,0,380))
effectSettings.SupportButton.Name = "OpenSupport"
effectSettings.StyleActionButton(effectSettings.SupportButton,Color3.fromRGB(201,102,226),"K",true)

-- Group permanent systems into one readable navigation surface. Keeping the
-- buttons in a shared dock makes the lobby feel authored instead of scattered.
do
	local dock=Instance.new("Frame")
	dock.Name="SanctumSystems"; dock.Size=UDim2.fromOffset(256,210); dock.Position=UDim2.fromOffset(12,236)
	dock.BackgroundColor3=Color3.fromRGB(9,14,25); dock.BackgroundTransparency=.04; dock.BorderSizePixel=0; dock.Parent=hud
	effectSettings.SystemDock=dock
	effectSettings.PanelChrome(dock,Color3.fromRGB(84,145,187),"SYSTEMS")
	gradient(dock,Color3.fromRGB(17,24,40),Color3.fromRGB(9,14,25),90)
	local dockTitle=makeText(dock,"SANCTUM COMMAND",UDim2.new(1,-24,0,20),UDim2.fromOffset(12,13),11,true)
	dockTitle.TextColor3=Color3.fromRGB(111,211,238)
	local dockHint=makeText(dock,"PERMANENT FRAME SYSTEMS",UDim2.new(1,-24,0,16),UDim2.fromOffset(12,32),8,true)
	dockHint.TextColor3=Color3.fromRGB(126,139,169)
	for index,button in ipairs({progressButton,armoryButton,settingsButton,effectSettings.SupportButton}) do
		button.Parent=dock; button.Size=UDim2.new(1,-20,0,35); button.Position=UDim2.fromOffset(10,54+(index-1)*39)
	end
	movementHint.Visible=false
end

-- Reserve three stable lobby zones at every desktop width: persistent systems
-- on the left, primary actions in the middle and expedition context on the
-- right. Short touch viewports collapse the optional loadout card instead of
-- stacking it over the chapter card.
effectSettings.ApplyResponsiveLayout=function()
	local scale=math.max(uiScale.Scale,.01)
	local logicalWidth=screenGui.AbsoluteSize.X/scale
	local logicalHeight=screenGui.AbsoluteSize.Y/scale
	local compact=logicalHeight<540
	effectSettings.CompactUI=compact

	local rightWidth=logicalWidth<1040 and 300 or 320
	local rightX=logicalWidth-rightWidth-18
	local laneLeft=280
	local laneRight=rightX-14
	local centerWidth=math.clamp(laneRight-laneLeft,320,420)
	local centerX=laneLeft+math.max(0,(laneRight-laneLeft-centerWidth)*.5)
	local secondaryWidth=(centerWidth-12)*.5

	startButton.Size=UDim2.fromOffset(centerWidth,68)
	startButton.Position=UDim2.new(0,centerX,1,-92)
	trainingButton.Size=UDim2.fromOffset(secondaryWidth,48)
	trainingButton.Position=UDim2.new(0,centerX,1,-150)
	duelButton.Size=UDim2.fromOffset(secondaryWidth,48)
	duelButton.Position=UDim2.new(0,centerX+secondaryWidth+12,1,-150)

	local missionWidth=math.clamp(logicalWidth-540,420,500)
	missionChip.Size=UDim2.fromOffset(missionWidth,54)
	missionChip.Position=UDim2.new(.5,-missionWidth*.5,0,15)
	chapterCard.Size=UDim2.fromOffset(rightWidth,228)
	chapterCard.Position=UDim2.fromOffset(rightX,compact and 82 or 94)
	lobbyPanel.Size=UDim2.fromOffset(rightWidth,154)
	lobbyPanel.Position=UDim2.new(0,rightX,1,-182)
	if not inMission then lobbyPanel.Visible=not compact end
end
effectSettings.ApplyResponsiveLayout()

local settingsShade = Instance.new("Frame")
settingsShade.Name = "SettingsShade"
settingsShade.Size = UDim2.fromScale(1,1)
settingsShade.BackgroundColor3 = Color3.fromRGB(3,5,11)
settingsShade.BackgroundTransparency = .3
settingsShade.Visible = false
settingsShade.Active = true
settingsShade.ZIndex = 50
settingsShade.Parent = hud

local settingsPanel = Instance.new("Frame")
settingsPanel.Name = "SettingsPanel"
settingsPanel.Size = UDim2.fromOffset(520,352)
settingsPanel.Position = UDim2.new(.5,-260,.5,-176)
settingsPanel.BackgroundColor3 = Color3.fromRGB(9,13,24)
settingsPanel.ZIndex = 51
settingsPanel.Parent = settingsShade
corner(settingsPanel,18); stroke(settingsPanel,Color3.fromRGB(93,91,220),.18,2)
gradient(settingsPanel,Color3.fromRGB(22,25,49),Color3.fromRGB(8,12,23),110)

local settingsTitle = makeText(settingsPanel,"DISPLAY // COMBAT FEEDBACK",UDim2.new(1,-130,0,34),UDim2.fromOffset(28,24),22,true)
settingsTitle.ZIndex=52
local settingsDesc = makeText(settingsPanel,"Tune readability and motion intensity for your setup.",UDim2.new(1,-56,0,22),UDim2.fromOffset(29,60),11,false)
settingsDesc.TextColor3=Color3.fromRGB(148,159,190); settingsDesc.ZIndex=52
local closeSettings = makeButton(settingsPanel,"CLOSE  X",UDim2.fromOffset(88,34),UDim2.new(1,-112,0,22)); closeSettings.ZIndex=53

local shakeButton = makeButton(settingsPanel,"CAMERA SHAKE  MEDIUM",UDim2.new(1,-56,0,52),UDim2.fromOffset(28,104)); shakeButton.ZIndex=53
local flashButton = makeButton(settingsPanel,"HIT FLASH  SOFT",UDim2.new(1,-56,0,52),UDim2.fromOffset(28,168)); flashButton.ZIndex=53
local postButton = makeButton(settingsPanel,"POST FX  BALANCED",UDim2.new(1,-56,0,52),UDim2.fromOffset(28,232)); postButton.ZIndex=53
local settingsFoot = makeText(settingsPanel,"M opens this panel  ·  Settings apply immediately",UDim2.new(1,-56,0,20),UDim2.fromOffset(28,304),10,true)
settingsFoot.TextColor3=Color3.fromRGB(108,196,222); settingsFoot.ZIndex=52

local function applyPostFX()
	for _,effectName in ipairs({"RIFT_Bloom","RIFT_ColorGrade"}) do
		local effect=game:GetService("Lighting"):FindFirstChild(effectName)
		if effect and effect:IsA("PostEffect") then effect.Enabled=effectSettings.PostFX end
	end
	effectSettings.MissionGrade.Enabled=effectSettings.PostFX and effectSettings.InCombatGrade
	postButton.Text=effectSettings.PostFX and "POST FX  BALANCED" or "POST FX  OFF"
end
local function refreshFeedbackSettings()
	if effectSettings.Shake >= .9 then shakeButton.Text="CAMERA SHAKE  FULL"
	elseif effectSettings.Shake > 0 then shakeButton.Text="CAMERA SHAKE  MEDIUM"
	else shakeButton.Text="CAMERA SHAKE  OFF" end
	flashButton.Text=effectSettings.HitFlash and "HIT FLASH  SOFT" or "HIT FLASH  OFF"
	applyPostFX()
end
local function setSettingsOpen(open)
	if titleScreen.Visible or result.Visible or runePanel.Visible then open=false end
	settingsShade.Visible=open
	if not open then restorePlayerControl(player.Character) end
end
settingsButton.Activated:Connect(function() setSettingsOpen(not settingsShade.Visible) end)
closeSettings.Activated:Connect(function() setSettingsOpen(false) end)
shakeButton.Activated:Connect(function()
	if effectSettings.Shake >= .9 then effectSettings.Shake=.55
	elseif effectSettings.Shake > 0 then effectSettings.Shake=0
	else effectSettings.Shake=1 end
	refreshFeedbackSettings()
end)
flashButton.Activated:Connect(function() effectSettings.HitFlash=not effectSettings.HitFlash; refreshFeedbackSettings() end)
postButton.Activated:Connect(function() effectSettings.PostFX=not effectSettings.PostFX; refreshFeedbackSettings() end)
refreshFeedbackSettings()

local progressionShade = Instance.new("Frame")
progressionShade.Name = "ProgressionShade"
progressionShade.Size = UDim2.fromScale(1,1)
progressionShade.BackgroundColor3 = Color3.fromRGB(3,5,11)
progressionShade.BackgroundTransparency = 0.28
progressionShade.Visible = false
progressionShade.Active = true
progressionShade.ZIndex = 40
progressionShade.Parent = hud

local progressionPanel = Instance.new("Frame")
progressionPanel.Name = "ProgressionPanel"
progressionPanel.Size = UDim2.new(0,760,0,470)
progressionPanel.Position = UDim2.new(0.5,-380,0.5,-235)
progressionPanel.BackgroundColor3 = Color3.fromRGB(9,13,24)
progressionPanel.BorderSizePixel = 0
progressionPanel.ZIndex = 41
progressionPanel.Parent = progressionShade
corner(progressionPanel, 18)
stroke(progressionPanel, Color3.fromRGB(112,98,255), 0.12, 2)
gradient(progressionPanel, Color3.fromRGB(21,25,48), Color3.fromRGB(8,12,23), 110)

local progressionTitle = makeText(progressionPanel, "RIFT FRAME // POWER SYSTEMS", UDim2.new(1,-110,0,34), UDim2.new(0,28,0,22), 23, true)
progressionTitle.ZIndex = 42
local progressionSubtitle = makeText(progressionPanel, "Build combat rating, unlock mastery nodes and evolve your Core.", UDim2.new(1,-100,0,22), UDim2.new(0,29,0,57), 12, false)
progressionSubtitle.TextColor3 = Color3.fromRGB(147,158,190)
progressionSubtitle.ZIndex = 42
local closeProgression = makeButton(progressionPanel, "CLOSE  X", UDim2.new(0,86,0,34), UDim2.new(1,-108,0,22))
closeProgression.ZIndex = 43

local powerCard = Instance.new("Frame")
powerCard.Size = UDim2.new(0,260,0,340)
powerCard.Position = UDim2.new(0,28,0,98)
powerCard.BackgroundColor3 = Color3.fromRGB(13,18,34)
powerCard.BackgroundTransparency = 0.05
powerCard.ZIndex = 42
powerCard.Parent = progressionPanel
corner(powerCard, 14)
stroke(powerCard, Color3.fromRGB(72,205,255), 0.35, 1)

local powerKicker = makeText(powerCard, "COMBAT RATING / POWER", UDim2.new(1,-28,0,22), UDim2.new(0,16,0,16), 12, true)
powerKicker.TextColor3 = Color3.fromRGB(105,215,255); powerKicker.ZIndex = 43
local powerValue = makeText(powerCard, "0", UDim2.new(1,-28,0,52), UDim2.new(0,16,0,42), 39, true)
powerValue.TextColor3 = Color3.fromRGB(190,175,255); powerValue.ZIndex = 43
local levelValue = makeText(powerCard, "LV.01  RIFT WALKER", UDim2.new(1,-28,0,22), UDim2.new(0,16,0,96), 12, true)
levelValue.TextColor3 = Color3.fromRGB(205,211,232); levelValue.ZIndex = 43
local formulaValue = makeText(powerCard, "ATK x 3.5  +  DEF x 11.6  +  HP", UDim2.new(1,-28,0,34), UDim2.new(0,16,0,127), 11, false)
formulaValue.TextColor3 = Color3.fromRGB(122,132,164); formulaValue.TextWrapped = true; formulaValue.ZIndex = 43
local statBreakdown = makeText(powerCard, "ATK\nDEF\nHP\nCRIT", UDim2.new(1,-32,0,116), UDim2.new(0,16,0,174), 16, true)
statBreakdown.TextColor3 = Color3.fromRGB(228,233,249); statBreakdown.ZIndex = 43
local accountProgress = makeText(powerCard, "LEVEL XP  0 / 140\nMISSIONS CLEARED  0\nBEST CLEAR  --", UDim2.new(1,-32,0,70), UDim2.new(0,16,1,-86), 11, true)
accountProgress.TextColor3 = Color3.fromRGB(139,151,184); accountProgress.ZIndex = 43

local systemColumn = Instance.new("Frame")
systemColumn.Size = UDim2.new(0,424,0,340)
systemColumn.Position = UDim2.new(0,308,0,98)
systemColumn.BackgroundTransparency = 1
systemColumn.ZIndex = 42
systemColumn.Parent = progressionPanel

local function makeSystemCard(y, accent, titleText, description)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1,0,0,102)
	card.Position = UDim2.new(0,0,0,y)
	card.BackgroundColor3 = Color3.fromRGB(15,20,36)
	card.BackgroundTransparency = 0.03
	card.ZIndex = 42
	card.Parent = systemColumn
	corner(card, 13); stroke(card, accent, 0.48, 1)
	local titleLabel = makeText(card, titleText, UDim2.new(1,-150,0,25), UDim2.new(0,16,0,12), 16, true)
	titleLabel.TextColor3 = accent; titleLabel.ZIndex = 43
	local bodyLabel = makeText(card, description, UDim2.new(1,-150,0,48), UDim2.new(0,16,0,43), 12, false)
	bodyLabel.TextColor3 = Color3.fromRGB(166,176,202); bodyLabel.TextWrapped = true; bodyLabel.TextYAlignment = Enum.TextYAlignment.Top; bodyLabel.ZIndex = 43
	return card, titleLabel, bodyLabel
end

local masteryCard, masteryTitle, masteryDetail = makeSystemCard(0, Color3.fromRGB(170,130,255), "MASTERY NETWORK", "Unlock permanent stat nodes with Credits.")
local masteryHubButton = makeButton(masteryCard, "UNLOCK", UDim2.new(0,116,0,38), UDim2.new(1,-132,0,32)); masteryHubButton.ZIndex = 44
local coreCard, coreTitle, coreDetail = makeSystemCard(116, Color3.fromRGB(72,205,255), "ASSAULT CORE", "Evolve your Core with shards to gain permanent ATK.")
local coreHubButton = makeButton(coreCard, "EVOLVE", UDim2.new(0,116,0,38), UDim2.new(1,-132,0,32)); coreHubButton.ZIndex = 44
local weaponCard, weaponTitle, weaponDetail = makeSystemCard(232, Color3.fromRGB(255,112,154), "WEAPON LOADOUT", "INITIATE RIFTBLADE  ·  ATK +0")
local equipNextButton = makeButton(weaponCard, "OPEN ARMORY", UDim2.new(0,116,0,38), UDim2.new(1,-132,0,32)); equipNextButton.ZIndex = 44
equipNextButton.Name = "OpenWeaponArmory"

-- A visible collection/equipment surface turns weapon drops into a readable
-- progression system instead of a hidden line of profile data. Keep the
-- implementation scoped so the large client controller stays under Luau's
-- top-level local-register limit.
local Armory={}
do
	local panel = Instance.new("Frame")
	panel.Name="ArmoryPanel"; panel.Size=UDim2.fromOffset(720,430); panel.Position=UDim2.new(.5,-360,.5,-215)
	panel.BackgroundColor3=Color3.fromRGB(8,12,22); panel.Visible=false; panel.ZIndex=46; panel.Parent=progressionShade
	corner(panel,12); stroke(panel,Color3.fromRGB(101,194,226),.3,1)
	gradient(panel,Color3.fromRGB(20,26,43),Color3.fromRGB(8,12,22),110)
	Armory.Panel=panel
	local title=makeText(panel,"EQUIPMENT // RIFT ARMORY",UDim2.new(1,-130,0,32),UDim2.fromOffset(24,18),22,true); title.ZIndex=47
	local sub=makeText(panel,"Weapons drop from the Ashen Warden. Select one to equip its permanent ATK bonus.",UDim2.new(1,-48,0,22),UDim2.fromOffset(24,51),11,false)
	sub.TextColor3=Color3.fromRGB(147,160,190); sub.ZIndex=47
	local close=makeButton(panel,"CLOSE  X",UDim2.fromOffset(88,34),UDim2.new(1,-112,0,18)); close.ZIndex=48
	local slots={}
	for i=1,6 do
		local col=(i-1)%3; local row=math.floor((i-1)/3)
		local slot=makeButton(panel,"",UDim2.fromOffset(208,136),UDim2.fromOffset(24+col*224,88+row*150))
		slot.Name="WeaponSlot"..i; slot.ZIndex=48
		local rarity=makeText(slot,"LOCKED",UDim2.new(1,-24,0,18),UDim2.fromOffset(12,12),9,true); rarity.ZIndex=49
		local itemName=makeText(slot,"UNDISCOVERED WEAPON",UDim2.new(1,-24,0,38),UDim2.fromOffset(12,34),14,true); itemName.TextWrapped=true; itemName.ZIndex=49
		local bonus=makeText(slot,"DEFEAT THE WARDEN",UDim2.new(1,-24,0,20),UDim2.fromOffset(12,82),10,false); bonus.TextColor3=Color3.fromRGB(135,145,170); bonus.ZIndex=49
		local status=makeText(slot,"LOCKED",UDim2.new(1,-24,0,18),UDim2.fromOffset(12,108),9,true); status.TextColor3=Color3.fromRGB(105,115,140); status.ZIndex=49
		slot.Activated:Connect(function()
			local itemId=slot:GetAttribute("ItemId")
			if itemId then Action:FireServer("EquipWeapon",itemId) end
		end)
		slots[i]={Button=slot,Rarity=rarity,Name=itemName,Bonus=bonus,Status=status}
	end
	local colors={COMMON=Color3.fromRGB(170,180,198),UNCOMMON=Color3.fromRGB(93,210,133),RARE=Color3.fromRGB(86,157,255),EPIC=Color3.fromRGB(183,112,255),LEGENDARY=Color3.fromRGB(255,185,76)}
	function Armory.Update()
		local inventory=profile and profile.Inventory or {}
		local equippedId=profile and profile.EquippedWeapon and profile.EquippedWeapon.Id
		for i,ui in ipairs(slots) do
			local item=inventory[i]
			ui.Button:SetAttribute("ItemId",item and item.Id or nil)
			if item then
				local equipped=item.Id==equippedId; local tint=colors[item.Rarity] or colors.COMMON
				ui.Rarity.Text=item.Rarity or "COMMON"; ui.Rarity.TextColor3=tint
				ui.Name.Text=item.Name or "RIFT WEAPON"; ui.Name.TextColor3=Color3.fromRGB(236,240,250)
				ui.Bonus.Text=string.format("PERMANENT ATK  +%d",item.ATK or 0)
				ui.Status.Text=equipped and "● EQUIPPED" or "CLICK TO EQUIP"
				ui.Status.TextColor3=equipped and Color3.fromRGB(104,225,214) or Color3.fromRGB(165,177,207)
				ui.Button.BackgroundColor3=equipped and Color3.fromRGB(31,46,57) or Color3.fromRGB(21,27,43)
			else
				ui.Rarity.Text="LOCKED"; ui.Rarity.TextColor3=Color3.fromRGB(91,100,125)
				ui.Name.Text="UNDISCOVERED WEAPON"; ui.Name.TextColor3=Color3.fromRGB(112,121,145)
				ui.Bonus.Text="DEFEAT THE ASHEN WARDEN"; ui.Status.Text="LOCKED"
				ui.Status.TextColor3=Color3.fromRGB(84,93,115); ui.Button.BackgroundColor3=Color3.fromRGB(15,19,31)
			end
		end
	end
	function Armory.SetOpen(open)
		if titleScreen.Visible or result.Visible then open=false end
		progressionShade.Visible=open or progressionShade.Visible
		panel.Visible=open
		if open then Armory.Update() end
	end
	close.Activated:Connect(function()
		panel.Visible=false; progressionShade.Visible=false; progressionPanel.Visible=true; restorePlayerControl(player.Character)
	end)
end

local function setProgressionOpen(open)
	if titleScreen.Visible or result.Visible then open = false end
	progressionPanel.Visible=open
	progressionShade.Visible = open
	if not open then Armory.Panel.Visible=false; restorePlayerControl(player.Character) end
end
progressButton.Activated:Connect(function() setProgressionOpen(not progressionShade.Visible) end)
armoryButton.Activated:Connect(function()
	progressionPanel.Visible=false; progressionShade.Visible=true; Armory.SetOpen(true)
end)
equipNextButton.Activated:Connect(function()
	progressionPanel.Visible=false; progressionShade.Visible=true; Armory.SetOpen(true)
end)
closeProgression.Activated:Connect(function() setProgressionOpen(false) end)
masteryHubButton.Activated:Connect(function() Action:FireServer("UpgradeMastery") end)
coreHubButton.Activated:Connect(function() Action:FireServer("UpgradeCore") end)

-- Commercialization is deliberately cosmetic and dormant until real product
-- IDs are configured. The storefront can be reviewed locally without ever
-- prompting a fake purchase or blocking the free mission path.
effectSettings.Support={}
do
	local commerce=require(Config:WaitForChild("Game")).Monetization or {}
	local shade=Instance.new("Frame")
	shade.Name="SupportShade"; shade.Size=UDim2.fromScale(1,1); shade.BackgroundColor3=Color3.fromRGB(3,5,11)
	shade.BackgroundTransparency=.22; shade.Visible=false; shade.Active=true; shade.ZIndex=54; shade.Parent=hud
	local panel=Instance.new("Frame")
	panel.Name="SupportPanel"; panel.Size=UDim2.fromOffset(800,470); panel.Position=UDim2.new(.5,-400,.5,-235)
	panel.BackgroundColor3=Color3.fromRGB(8,11,21); panel.ZIndex=55; panel.Parent=shade
	corner(panel,18); stroke(panel,Color3.fromRGB(194,137,255),.16,2)
	gradient(panel,Color3.fromRGB(29,23,50),Color3.fromRGB(8,12,23),105)
	local title=makeText(panel,"RIFT SUPPORT // COSMETIC ARCHIVE",UDim2.new(1,-140,0,36),UDim2.fromOffset(28,22),23,true); title.ZIndex=56
	local desc=makeText(panel,"Support development through identity and visual expression. Every combat system remains free.",UDim2.new(1,-56,0,24),UDim2.fromOffset(29,60),11,false)
	desc.TextColor3=Color3.fromRGB(158,168,199); desc.ZIndex=56
	local close=makeButton(panel,"CLOSE  X",UDim2.fromOffset(88,34),UDim2.new(1,-112,0,22)); close.ZIndex=57
	local function offerCard(x,accent,kicker,name,body,productId,productKind,fallbackPrice)
		local card=Instance.new("Frame"); card.Size=UDim2.fromOffset(232,296); card.Position=UDim2.fromOffset(x,102)
		card.BackgroundColor3=Color3.fromRGB(14,18,31); card.ZIndex=56; card.Parent=panel
		corner(card,12); stroke(card,accent,.34,1); gradient(card,Color3.fromRGB(27,31,50),Color3.fromRGB(11,15,27),90)
		local stripe=Instance.new("Frame"); stripe.Size=UDim2.new(1,0,0,3); stripe.BackgroundColor3=accent; stripe.BorderSizePixel=0; stripe.ZIndex=57; stripe.Parent=card
		local tag=makeText(card,kicker,UDim2.new(1,-24,0,18),UDim2.fromOffset(12,18),9,true); tag.TextColor3=accent; tag.ZIndex=57
		local label=makeText(card,name,UDim2.new(1,-24,0,48),UDim2.fromOffset(12,46),18,true); label.TextWrapped=true; label.ZIndex=57
		local copy=makeText(card,body,UDim2.new(1,-24,0,106),UDim2.fromOffset(12,106),11,false)
		copy.TextWrapped=true; copy.TextYAlignment=Enum.TextYAlignment.Top; copy.TextColor3=Color3.fromRGB(170,180,205); copy.ZIndex=57
		local buy=makeButton(card,productId>0 and "VIEW LIVE PRICE" or string.format("SETUP PENDING  ·  %d R$",fallbackPrice),UDim2.new(1,-24,0,42),UDim2.new(0,12,1,-58)); buy.ZIndex=58
		buy.Name="Purchase"..productKind..tostring(x)
		if productId>0 then task.spawn(function()
			local ok,info=pcall(game:GetService("MarketplaceService").GetProductInfo,game:GetService("MarketplaceService"),productId,productKind=="Pass" and Enum.InfoType.GamePass or Enum.InfoType.Product)
			if ok and info and info.PriceInRobux then buy.Text=string.format("PURCHASE  ·  %d R$",info.PriceInRobux) end
		end) end
		buy.Activated:Connect(function()
			if not productId or productId<=0 then effectSettings.Support.SetOpen(false); showNotice("PURCHASES LOCKED IN LOCAL BUILD",accent); return end
			local ok=pcall(function()
				if productKind=="Pass" then game:GetService("MarketplaceService"):PromptGamePassPurchase(player,productId)
				else game:GetService("MarketplaceService"):PromptProductPurchase(player,productId) end
			end)
			if not ok then showNotice("STORE UNAVAILABLE — TRY AGAIN LATER",Color3.fromRGB(255,115,135)) end
		end)
		return card
	end
	offerCard(28,Color3.fromRGB(229,181,86),"PERMANENT IDENTITY","FOUNDER PASS","Founder title · gilded lobby nameplate · commemorative sigil · supporter chat tag. No combat power.",commerce.FounderPassId or 0,"Pass",commerce.FounderFallbackPrice or 299)
	offerCard(284,Color3.fromRGB(96,214,235),"VISUAL EXPRESSION","ARCANE COSMETIC PACK","Weapon chroma · dash trail · Rift Surge aura · extra appearance slot. Telegraph colors remain readable.",commerce.CosmeticPassId or 0,"Pass",commerce.CosmeticFallbackPrice or 149)
	offerCard(540,Color3.fromRGB(202,113,255),"REPEATABLE SUPPORT","RIFT SIGNAL TIP","A voluntary support signal with a short lobby celebration. No stats, currency or progression advantage.",commerce.SupporterTipProductId or 0,"Product",commerce.TipFallbackPrice or 25)
	local foot=makeText(panel,"FREE PLAYERS KEEP THE FULL STORY, BOSS, HARD MODE AND POWER PROGRESSION.",UDim2.new(1,-56,0,22),UDim2.fromOffset(28,422),10,true)
	foot.TextColor3=Color3.fromRGB(117,211,220); foot.TextXAlignment=Enum.TextXAlignment.Center; foot.ZIndex=56
	function effectSettings.Support.SetOpen(open)
		if titleScreen.Visible or inMission or result.Visible then open=false end
		if open then
			setProgressionOpen(false); setSettingsOpen(false)
		end
		shade.Visible=open
		if not open then restorePlayerControl(player.Character) end
	end
	effectSettings.Support.Shade=shade
	close.Activated:Connect(function() effectSettings.Support.SetOpen(false) end)
	effectSettings.SupportButton.Activated:Connect(function() effectSettings.Support.SetOpen(not shade.Visible) end)
end

local function updateProfile(p)
	profile = p
	if not p then return end
	creditsText.Text = string.format("CREDITS  %d", p.Credits or 0)
	shardsText.Text = string.format("CORE SHARDS  %d", p.Shards or 0)
	local s = p.Stats or {}
	crText.Text = string.format("CR  %d", math.floor((s.CR or 0)+0.5))
	atkText.Text = string.format("ATK     %d", math.floor((s.ATK or 0)+0.5))
	defText.Text = string.format("DEF     %d", math.floor((s.DEF or 0)+0.5))
	hpText.Text = string.format("HP      %d", math.floor((s.HP or 0)+0.5))
	powerValue.Text = tostring(math.floor((s.CR or 0)+0.5))
	levelValue.Text = string.format("LV.%d  RIFT WALKER", p.Level or s.Level or 1)
	statBreakdown.Text = string.format("ATK        %d\nDEF        %d\nHP         %d\nCRIT       %d%%", math.floor((s.ATK or 0)+0.5), math.floor((s.DEF or 0)+0.5), math.floor((s.HP or 0)+0.5), math.floor((s.CritChance or 0)*100+0.5))
	accountProgress.Text = string.format("LEVEL XP  %d / %d\nMISSIONS CLEARED  %d\nBEST CLEAR  %s", p.XP or 0, p.XPToNext or 0, p.Clears or 0, (p.BestTime or 0) > 0 and string.format("%.2fs", p.BestTime) or "--")

	local weapon = p.EquippedWeapon or {Name="INITIATE RIFTBLADE", Rarity="COMMON", ATK=0}
	weaponTitle.Text = string.format("WEAPON LOADOUT  %d OWNED", #(p.Inventory or {}))
	weaponDetail.Text = string.format("%s  [%s]\nPERMANENT ATK  +%d", weapon.Name or "RIFTBLADE", weapon.Rarity or "COMMON", weapon.ATK or 0)
	lpTitle.Text = string.format("LOADOUT  //  %s", weapon.Name or "RIFTBLADE")
	equipNextButton.Text = "OPEN ARMORY"
	Armory.Update()
	local hard = p.Difficulty == "HARD"
	difficultyButton.Text = hard and "DIFFICULTY  HARD   /   +50% C" or "DIFFICULTY  NORMAL"
	difficultyButton.BackgroundColor3 = hard and Color3.fromRGB(138,48,65) or Color3.fromRGB(31,36,58)
	rewardPreview.Text = hard and "REWARDS  450 C  ·  6 SHARDS  ·  BOSS WEAPON" or "REWARDS  300 C  ·  4 SHARDS  ·  BOSS WEAPON"
	startButton.Text = hard and "ENTER ASHEN SANCTUM  //  HARD" or "ENTER ASHEN SANCTUM"
	local quest = p.Quest or {Current=0,Target=12,Claimed=false}
	questProgress.Text = string.format("DEFEAT RIFTBOUND  %d / %d",quest.Current or 0,quest.Target or 12)
	questButton.Text = quest.Claimed and "DIRECTIVE COMPLETE" or ((quest.Current or 0) >= (quest.Target or 12) and "CLAIM REWARD" or "IN PROGRESS")
	questButton.BackgroundColor3 = (not quest.Claimed and (quest.Current or 0) >= (quest.Target or 12)) and Color3.fromRGB(126,86,30) or Color3.fromRGB(31,36,58)

	local nextNode = Progression.Mastery[(p.Mastery or 0)+1]
	if nextNode then
		masteryButton.Text = string.format("MASTERY %d → %d   ·   %d C", p.Mastery or 0, (p.Mastery or 0)+1, nextNode.Cost)
		local gain = nextNode.ATK > 0 and ("ATK +"..nextNode.ATK) or nextNode.DEF > 0 and ("DEF +"..nextNode.DEF) or ("HP +"..nextNode.HP)
		masteryTitle.Text = string.format("MASTERY NETWORK  %d / %d", p.Mastery or 0, #Progression.Mastery)
		masteryDetail.Text = string.format("NEXT NODE  %s\nCOST  %d CREDITS", gain, nextNode.Cost)
		masteryHubButton.Text = "UNLOCK"
	else
		masteryButton.Text = "MASTERY MAXED"
		masteryTitle.Text = "MASTERY NETWORK  MAX"
		masteryDetail.Text = "All permanent attribute nodes unlocked."
		masteryHubButton.Text = "MAXED"
	end

	local nextCore = (p.CoreLevel or 0)+1
	local coreCost = Progression.CoreShardCosts[nextCore]
	if coreCost then
		coreButton.Text = string.format("ASSAULT CORE LV.%d   ·   %d SHARD", nextCore, coreCost)
		local previousATK = Progression.AssaultCoreATK[nextCore-1] or 0
		local nextATK = Progression.AssaultCoreATK[nextCore] or previousATK
		coreTitle.Text = string.format("ASSAULT CORE  LV.%d / %d", p.CoreLevel or 0, #Progression.AssaultCoreATK)
		coreDetail.Text = string.format("NEXT EVOLUTION  ATK +%d\nCOST  %d CORE SHARDS", nextATK-previousATK, coreCost)
		coreHubButton.Text = "EVOLVE"
	else
		coreButton.Text = "ASSAULT CORE MAXED"
		coreTitle.Text = "ASSAULT CORE  MAX"
		coreDetail.Text = "Core output has reached the current limit."
		coreHubButton.Text = "MAXED"
	end
end

local function characterHooks(character)
	local humanoid = character:WaitForChild("Humanoid")
	for _,descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then descendant.LocalTransparencyModifier=1 end
	end
	restorePlayerControl(character)
	local outline=character:FindFirstChild("PlayerReadability") or Instance.new("Highlight")
	outline.Name="PlayerReadability"; outline.Adornee=character
	outline.FillTransparency=1; outline.OutlineTransparency=.48
	outline.OutlineColor=Color3.fromRGB(145,225,255); outline.DepthMode=Enum.HighlightDepthMode.Occluded
	outline.Parent=character
	local function refresh()
		healthFill.Size = UDim2.fromScale(math.clamp(humanoid.Health / math.max(1,humanoid.MaxHealth),0,1),1)
		healthLabel.Text = string.format("%d / %d", math.floor(humanoid.Health+0.5), math.floor(humanoid.MaxHealth+0.5))
	end
	humanoid.HealthChanged:Connect(refresh)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh)
	humanoid.Died:Connect(function()
		inMission=false; attackBusy=false; dismissCombatCoach(); showDefeatTransition()
	end)
	refresh()
	task.spawn(function()
		local deadline=os.clock()+5
		while character.Parent and character:GetAttribute("RiftReady")~=true and os.clock()<deadline do task.wait(.05) end
		for _,descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("BasePart") then
				TweenService:Create(descendant,TweenInfo.new(.22),{LocalTransparencyModifier=0}):Play()
			end
		end
		if defeatShade.Visible then hideDefeatTransition() end
	end)
end
if player.Character then task.spawn(characterHooks, player.Character) end
player.CharacterAdded:Connect(characterHooks)

-- Keep Roblox's default controller as the first choice. Some Studio sessions
-- have loaded without a functioning PlayerModule; in that case this fallback
-- feeds the Humanoid's own locomotion, without CFrame/velocity frame forcing.
local fallbackDelay = 0
local fallbackDriving = false
RunService:BindToRenderStep("RIFT_NATIVE_MOVE_FALLBACK", Enum.RenderPriority.Input.Value + 1, function(dt)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or titleScreen.Visible or progressionShade.Visible or settingsShade.Visible or result.Visible or runePanel.Visible or UserInputService:GetFocusedTextBox() then
		fallbackDelay = 0
		if fallbackDriving and humanoid then humanoid:Move(Vector3.zero, false) end
		fallbackDriving = false
		return
	end
	local x = (UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
	local z = (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
	if x == 0 and z == 0 then
		fallbackDelay = 0
		if fallbackDriving then humanoid:Move(Vector3.zero, false) end
		fallbackDriving = false
		return
	end
	if humanoid.MoveDirection.Magnitude >= .05 and not fallbackDriving then
		fallbackDelay = 0
		return
	end
	fallbackDelay += dt
	if fallbackDelay < .18 and not fallbackDriving then return end
	if not fallbackDriving then print("[RIFT][MOVE] Default movement absent; native Humanoid fallback engaged") end
	fallbackDriving = true
	local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
	local right = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)
	if forward.Magnitude < .1 or right.Magnitude < .1 then return end
	local direction = forward.Unit*z + right.Unit*x
	humanoid:Move(direction.Magnitude > 1 and direction.Unit or direction, false)
end)

-- Studio-only input/physics probe: logs only while WASD is held, so a tester
-- can distinguish missing input from geometry or Humanoid movement failure.
if RunService:IsStudio() then
	task.spawn(function()
		local previousPosition
		local stuckSeconds = 0
		for _ = 1, 300 do
			task.wait(.4)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if humanoid and root then
				local keyHeld = UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.A)
					or UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.D)
				if keyHeld then
					local distance = previousPosition and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(previousPosition.X, 0, previousPosition.Z)).Magnitude or 0
					local focused = UserInputService:GetFocusedTextBox() ~= nil
					print(string.format("[RIFT][MOVE_PROBE] key=1 focus=%s module=%s xz=%.2f dir=%.2f speed=%.1f anchored=%s y=%.2f", tostring(focused), tostring(player.PlayerScripts:FindFirstChild("PlayerModule") ~= nil), distance, humanoid.MoveDirection.Magnitude, humanoid.WalkSpeed, tostring(root.Anchored), root.Position.Y))
					stuckSeconds = distance < .15 and stuckSeconds + .4 or 0
					if stuckSeconds >= 2 and stuckSeconds < 2.4 then
						warn("[RIFT][MOVE_PROBE] WASD held but no horizontal displacement for 2 seconds")
					end
				else
					stuckSeconds = 0
				end
				previousPosition = root.Position
			end
		end
	end)
end

-- Camera: use Roblox's stable character camera so keyboard movement never loses control.
camera.CameraType = Enum.CameraType.Custom
RunService:BindToRenderStep("RIFT_CAMERA_SHAKE", Enum.RenderPriority.Camera.Value + 1, function(dt)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    if cameraShake > 0 and effectSettings.Shake > 0 then
        local strength = math.min(cameraShake, 0.12) * effectSettings.Shake
        local now = os.clock()
        humanoid.CameraOffset = Vector3.new(math.sin(now*48)*strength, math.cos(now*37)*strength*.45, 0)
        cameraShake = math.max(0, cameraShake - dt*12)
    elseif humanoid.CameraOffset.Magnitude > 0 then
        humanoid.CameraOffset = Vector3.zero
    end
end)
-- Cooldown HUD
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for key,untilTime in pairs(cooldownUntil) do
		local ui = skillFrames[key]
		if ui then
			local remain = untilTime - now
			if remain > 0 then
				ui.CD.Visible = true
				ui.CD.Text = string.format("%.1f", remain)
			else
				ui.CD.Visible = false
				cooldownUntil[key] = nil
			end
		end
	end
end)

local ATTACK_TIMING = {
	[1] = {Windup=.14, Strike=.10, Stop=.025, Recover=.28, Shake=.12},
	[2] = {Windup=.16, Strike=.10, Stop=.032, Recover=.30, Shake=.19},
	[3] = {Windup=.20, Strike=.12, Stop=.045, Recover=.40, Shake=.31},
	[4] = {Windup=.34, Strike=.14, Stop=.056, Recover=.40, Shake=.42},
}

local function playSound(parent, soundId, volume, speed)
	if not parent then return end
	local s=Instance.new("Sound")
	s.SoundId=soundId; s.Volume=volume; s.PlaybackSpeed=speed or 1
	s.RollOffMaxDistance=70; s.RollOffMinDistance=6; s.Parent=parent; s:Play()
	Debris:AddItem(s,2)
end

local function weaponTrail(enabled, step)
	local character=player.Character
	local blade=character and character:FindFirstChild("RuneBlade")
	local trail=blade and blade:FindFirstChild("RuneTrail")
	if trail then
		trail.Lifetime = step >= 3 and .22 or .13
		trail.WidthScale = NumberSequence.new({NumberSequenceKeypoint.new(0,step>=3 and 1.0 or .55),NumberSequenceKeypoint.new(1,0)})
		trail.Enabled=enabled
	end
end

local function slashArc(step)
	local character=player.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local count=step>=3 and 7 or 5
	local radius=step>=3 and 4.8 or 3.7
	local color=step==2 and Color3.fromRGB(185,150,255) or Color3.fromRGB(205,245,255)
	for i=1,count do
		local t=(i-1)/(count-1)
		local angle=math.rad(-58+t*116)
		if step==2 then angle=-angle end
		local x=math.sin(angle)*radius
		local y=1.7+math.cos(angle)*radius*.32
		local p=Instance.new("Part")
		p.Name="SlashArc"; p.Size=Vector3.new(step>=3 and 1.5 or 1.0,.09,.26)
		p.Material=Enum.Material.Neon; p.Color=color; p.Transparency=.28+t*.3
		p.Anchored=true; p.CanCollide=false; p.CanTouch=false
		p.CFrame=root.CFrame*CFrame.new(x,y,-3.4)*CFrame.Angles(0,0,-angle)
		p.Parent=workspace
		TweenService:Create(p,TweenInfo.new(step>=3 and .25 or .17),{Transparency=1,Size=p.Size*Vector3.new(1.5,.4,1)}):Play()
		Debris:AddItem(p,.3)
	end
end

local function impactBurst(data)
	local step=data.Step or 1
	local color=data.Crit and Color3.fromRGB(255,220,110) or Color3.fromRGB(215,247,255)
	local radius=step>=3 and 4.6 or 3
	for i=1,(step>=3 and 8 or 5) do
		local a=(i/(step>=3 and 8 or 5))*math.pi*2
		local p=Instance.new("Part")
		p.Name="HitSpark"; p.Size=Vector3.new(.12,.12,step>=3 and 2.1 or 1.25)
		p.Material=Enum.Material.Neon; p.Color=color; p.Anchored=true; p.CanCollide=false; p.CanTouch=false
		p.CFrame=CFrame.new(data.Position)*CFrame.Angles(0,a,math.rad((i%3-1)*20))
		p.Parent=workspace
		TweenService:Create(p,TweenInfo.new(.16,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{CFrame=p.CFrame*CFrame.new(0,0,-radius),Transparency=1}):Play()
		Debris:AddItem(p,.2)
	end
	local ring=Instance.new("Part")
	ring.Name="ImpactRing"; ring.Shape=Enum.PartType.Cylinder; ring.Size=Vector3.new(.12,1.4,1.4)
	ring.Material=Enum.Material.Neon; ring.Color=color; ring.Transparency=.18; ring.Anchored=true; ring.CanCollide=false
	ring.CFrame=CFrame.new(data.Position)*CFrame.Angles(0,0,math.rad(90)); ring.Parent=workspace
	TweenService:Create(ring,TweenInfo.new(.2),{Size=Vector3.new(.08,radius,radius),Transparency=1}):Play(); Debris:AddItem(ring,.24)
	if effectSettings.HitFlash and data.Target and data.Target.Parent then
		local flash=Instance.new("Highlight")
		flash.Name="HitFlash"; flash.Adornee=data.Target; flash.FillColor=Color3.new(1,1,1)
		flash.OutlineColor=color; flash.FillTransparency=.86; flash.OutlineTransparency=.62; flash.DepthMode=Enum.HighlightDepthMode.Occluded
		flash.Parent=data.Target
		TweenService:Create(flash,TweenInfo.new(step>=3 and .085 or .06),{FillTransparency=1,OutlineTransparency=1}):Play()
		Debris:AddItem(flash,.11)
	end
	local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	-- A short impact is heard only on a confirmed hit; the old metallic
	-- "shing" was ringing over every attack like a pitched instrument.
	local impactSource = data.Target and data.Target.PrimaryPart or root
	playSound(impactSource,"rbxassetid://7171761940",step>=3 and .42 or .27,step>=3 and .83 or 1)
	if step==4 then playSound(impactSource,"rbxasset://sounds/impact_explosion_03.mp3",.12,.72) end
end

local function tweenJoint(joint, target, duration, style)
	if not joint then return end
	local tween=TweenService:Create(joint,TweenInfo.new(duration,style or Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{C0=target})
	tween:Play()
end

local function playBasicAttack(heavy)
	if attackBusy or not inMission then return end
	local now=os.clock()
	if not heavy and now-localComboLast>Skills.Basic.ComboReset then localComboStep=1 end
	local step=heavy and 4 or localComboStep
	local timing=ATTACK_TIMING[step]
	local character=player.Character
	local torso=character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
	local lower=character and (character:FindFirstChild("LowerTorso") or torso)
	local shoulder=torso and (torso:FindFirstChild("RightShoulder") or torso:FindFirstChild("Right Shoulder"))
	local waist=lower and lower:FindFirstChild("Waist")
	local blade=character and character:FindFirstChild("RuneBlade")
	local shoulderBase=shoulder and shoulder.C0
	local waistBase=waist and waist.C0
	attackBusy=true
	if not heavy then localComboLast=now end

	local windup, strike
	if step==1 then
		windup=CFrame.Angles(math.rad(-18),math.rad(-22),math.rad(62)); strike=CFrame.Angles(math.rad(8),math.rad(35),math.rad(-72))
	elseif step==2 then
		windup=CFrame.Angles(math.rad(-28),math.rad(42),math.rad(-55)); strike=CFrame.Angles(math.rad(-2),math.rad(-48),math.rad(68))
	elseif step==3 then
		windup=CFrame.Angles(math.rad(-118),math.rad(5),math.rad(18)); strike=CFrame.Angles(math.rad(42),math.rad(-8),math.rad(-22))
	else
		windup=CFrame.Angles(math.rad(-145),0,math.rad(12)); strike=CFrame.Angles(math.rad(65),0,math.rad(-10))
	end
	if shoulder then tweenJoint(shoulder,shoulderBase*windup,timing.Windup,Enum.EasingStyle.Quad) end
	if waist then tweenJoint(waist,waistBase*CFrame.Angles(step==3 and math.rad(-14) or 0,math.rad(step==2 and 24 or -18),0),timing.Windup) end
	task.wait(timing.Windup)
	weaponTrail(true,step)
	playSound(blade or character,"rbxassetid://9080058053",step>=3 and .32 or .23,step>=3 and .82 or 1)
	if shoulder then tweenJoint(shoulder,shoulderBase*strike,timing.Strike,step==3 and Enum.EasingStyle.Exponential or Enum.EasingStyle.Quad) end
	if waist then tweenJoint(waist,waistBase*CFrame.Angles(step==3 and math.rad(18) or 0,math.rad(step==2 and -28 or 25),0),timing.Strike) end
	slashArc(step)
	Action:FireServer(heavy and "Heavy" or "Basic")
	task.wait(timing.Strike)
	while os.clock()<hitStopUntil do RunService.RenderStepped:Wait() end
	weaponTrail(false,step)
	if shoulder then tweenJoint(shoulder,shoulderBase,timing.Recover) end
	if waist then tweenJoint(waist,waistBase,timing.Recover) end
	task.wait(timing.Recover)
	if not heavy then localComboStep=step%3+1 end
	attackBusy=false
end

effectSettings.SkillCastFX = function(key, character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	if key == "Q" then
		for index=1,3 do
			local wave=Instance.new("Part")
			wave.Name="RiftSlashWave"; wave.Shape=Enum.PartType.Cylinder
			wave.Size=Vector3.new(.12,4.8+index*.9,4.8+index*.9)
			wave.Material=Enum.Material.Neon; wave.Color=index==2 and Color3.fromRGB(236,91,210) or Color3.fromRGB(82,213,255)
			wave.Transparency=.22+index*.12; wave.Anchored=true; wave.CanCollide=false; wave.CanTouch=false; wave.CanQuery=false
			wave.CFrame=root.CFrame*CFrame.new(0,1.6,-3-index*.55)*CFrame.Angles(0,math.rad(90),0)
			wave.Parent=workspace
			TweenService:Create(wave,TweenInfo.new(.28,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{CFrame=wave.CFrame*CFrame.new(-16,0,0),Transparency=1,Size=wave.Size*1.35}):Play()
			Debris:AddItem(wave,.34)
		end
		showNotice("Q  //  RIFT SLASH  //  MID-RANGE",Color3.fromRGB(102,213,255))
	else
		local ring=Instance.new("Part")
		ring.Name="GuardBreakPulse"; ring.Shape=Enum.PartType.Cylinder
		ring.Size=Vector3.new(.14,2.4,2.4); ring.Material=Enum.Material.Neon; ring.Color=Color3.fromRGB(255,174,77)
		ring.Transparency=.12; ring.Anchored=true; ring.CanCollide=false; ring.CanTouch=false; ring.CanQuery=false
		ring.CFrame=root.CFrame*CFrame.new(0,-2.65,-4)*CFrame.Angles(0,0,math.rad(90)); ring.Parent=workspace
		TweenService:Create(ring,TweenInfo.new(.26,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=Vector3.new(.08,12,12),Transparency=1}):Play()
		Debris:AddItem(ring,.32)
		cameraShake=math.max(cameraShake,.24)
		showNotice("E  //  GUARD BREAK  //  HIGH POISE",Color3.fromRGB(255,186,92))
	end
end

local function playSkillAttack(key)
	if attackBusy or not inMission or os.clock() < (cooldownUntil[key] or 0) then return end
	local character = player.Character
	local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
	local shoulder = torso and (torso:FindFirstChild("RightShoulder") or torso:FindFirstChild("Right Shoulder"))
	local base = shoulder and shoulder.C0
	attackBusy = true
	if shoulder then tweenJoint(shoulder,base*CFrame.Angles(math.rad(-65),0,math.rad(42)),key=="Q" and .20 or .28) end
	task.wait(key=="Q" and .20 or .28)
	weaponTrail(true,4)
	effectSettings.SkillCastFX(key, character)
	playSound(character and character:FindFirstChild("RuneBlade") or character,key=="Q" and "rbxassetid://9080058053" or "rbxasset://sounds/impact_explosion_03.mp3",key=="Q" and .3 or .22,key=="Q" and .9 or .72)
	if shoulder then tweenJoint(shoulder,base*CFrame.Angles(math.rad(24),0,math.rad(-62)),.13) end
	slashArc(4)
	Action:FireServer("Skill",key)
	task.wait(.13)
	weaponTrail(false,4)
	if shoulder then tweenJoint(shoulder,base,.22) end
	task.wait(.22)
	attackBusy = false
end

local function requestDodge()
	if not inMission or result.Visible or UserInputService:GetFocusedTextBox() then return end
	dismissCombatCoach()
	local character=player.Character
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	local flat=humanoid and humanoid.MoveDirection or Vector3.zero
	if flat.Magnitude < .1 then flat=camera.CFrame.LookVector end
	Action:FireServer("Dodge",Vector3.new(flat.X,0,flat.Z))
end
local function requestSurge()
	if not inMission or result.Visible or UserInputService:GetFocusedTextBox() then return end
	dismissCombatCoach(); Action:FireServer("Surge")
end
skillFrames["LMB"].Button.Activated:Connect(function() dismissCombatCoach(); task.spawn(playBasicAttack,false) end)
skillFrames["RMB"].Button.Activated:Connect(function() dismissCombatCoach(); task.spawn(playBasicAttack,true) end)
skillFrames["SPACE"].Button.Activated:Connect(requestDodge)
skillFrames["Q"].Button.Activated:Connect(function() dismissCombatCoach(); task.spawn(playSkillAttack,"Q") end)
skillFrames["E"].Button.Activated:Connect(function() dismissCombatCoach(); task.spawn(playSkillAttack,"E") end)
skillFrames["R"].Button.Activated:Connect(requestSurge)

-- Input
local movementKeyMap = {
	[Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
}

local function setPlayerSpeed(speed)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.WalkSpeed = speed end
	if effectSettings.SprintTween then effectSettings.SprintTween:Cancel() end
	effectSettings.SprintTween=TweenService:Create(camera,TweenInfo.new(.2,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{
		FieldOfView=speed>WALK_SPEED and 75 or 70,
	})
	effectSettings.SprintTween:Play()
end

if UserInputService.TouchEnabled then
	local touchSprint=makeButton(hud,"SPRINT",UDim2.fromOffset(96,66),UDim2.new(1,-122,1,-250))
	touchSprint.Name="TouchSprint"; touchSprint.ZIndex=18; touchSprint.Visible=false
	effectSettings.TouchSprint=touchSprint
	touchSprint.InputBegan:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.Touch and not titleScreen.Visible and not progressionShade.Visible and not settingsShade.Visible and not effectSettings.Support.Shade.Visible then
			setPlayerSpeed(SPRINT_SPEED)
		end
	end)
	touchSprint.InputEnded:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.Touch then setPlayerSpeed(WALK_SPEED) end
	end)
end
effectSettings.SetTouchSprintVisible=function(visible)
	if effectSettings.TouchSprint then effectSettings.TouchSprint.Visible=visible==true end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if movementKeyMap[input.KeyCode] then
		if titleScreen.Visible then dismissTitle() end
		if progressionShade.Visible then setProgressionOpen(false) end
		if settingsShade.Visible then setSettingsOpen(false) end
		if effectSettings.Support.Shade.Visible then effectSettings.Support.SetOpen(false) end
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		if not titleScreen.Visible and not progressionShade.Visible and not settingsShade.Visible and not effectSettings.Support.Shade.Visible and not result.Visible then
			setPlayerSpeed(SPRINT_SPEED)
		end
	end
	if titleScreen.Visible then
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space then dismissTitle() end
		return
	end
	if input.KeyCode == Enum.KeyCode.P then
		effectSettings.Support.SetOpen(false)
		setSettingsOpen(false)
		setProgressionOpen(not progressionShade.Visible)
		return
	elseif input.KeyCode == Enum.KeyCode.I then
		effectSettings.Support.SetOpen(false)
		setSettingsOpen(false)
		if progressionShade.Visible and Armory.Panel.Visible then setProgressionOpen(false)
		else progressionPanel.Visible=false; progressionShade.Visible=true; Armory.SetOpen(true) end
		return
	elseif input.KeyCode == Enum.KeyCode.K then
		setProgressionOpen(false); setSettingsOpen(false)
		effectSettings.Support.SetOpen(not effectSettings.Support.Shade.Visible)
		return
	elseif input.KeyCode == Enum.KeyCode.M then
		effectSettings.Support.SetOpen(false)
		setProgressionOpen(false)
		setSettingsOpen(not settingsShade.Visible)
		return
	elseif input.KeyCode == Enum.KeyCode.Escape and (progressionShade.Visible or settingsShade.Visible or effectSettings.Support.Shade.Visible) then
		setProgressionOpen(false); setSettingsOpen(false); effectSettings.Support.SetOpen(false)
		return
	end
	if settingsShade.Visible or effectSettings.Support.Shade.Visible then return end
	-- B must remain reliable even when Roblox marks the key as processed.
	-- It is the explicit escape path from isolated combat modes.
	if input.KeyCode == Enum.KeyCode.B and duelMode then
		Action:FireServer("ForfeitDuel")
		return
	elseif input.KeyCode == Enum.KeyCode.B and trainingMode then
		Action:FireServer("ReturnLobby")
		return
	end
	if input.KeyCode == Enum.KeyCode.Space and inMission and not result.Visible and not UserInputService:GetFocusedTextBox() then
		requestDodge()
		return
	end
	if input.KeyCode == Enum.KeyCode.F and inMission and not result.Visible and not UserInputService:GetFocusedTextBox() then
		dismissCombatCoach()
		Action:FireServer("Execute")
		return
	elseif input.KeyCode == Enum.KeyCode.R and inMission and not result.Visible and not UserInputService:GetFocusedTextBox() then
		requestSurge()
		return
	end
	if processed or result.Visible or runePanel.Visible then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dismissCombatCoach()
		task.spawn(playBasicAttack, false)
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		dismissCombatCoach()
		task.spawn(playBasicAttack, true)
	elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.B then
		requestMissionStart()
	elseif input.KeyCode == Enum.KeyCode.Q then
		dismissCombatCoach()
		task.spawn(playSkillAttack,"Q")
	elseif input.KeyCode == Enum.KeyCode.E then
		dismissCombatCoach()
		task.spawn(playSkillAttack,"E")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		setPlayerSpeed(WALK_SPEED)
	end
end)

local function worldPopup(data)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2,0.2,0.2)
	anchor.Position = data.Position + Vector3.new(math.random(-10,10)/10, 2.8, 0)
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(170,60)
	bb.AlwaysOnTop = true
	bb.Adornee = anchor
	bb.Parent = anchor

	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1,1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextStrokeTransparency = 0.45
	t.Text = data.Crit and ("CRIT  "..data.Damage) or tostring(data.Damage)
	t.TextColor3 = data.Crit and Color3.fromRGB(255,210,65) or Color3.fromRGB(245,248,255)
	t.Parent = bb

	TweenService:Create(anchor, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = anchor.Position + Vector3.new(0,2.5,0)
	}):Play()
	TweenService:Create(t, TweenInfo.new(0.65), {TextTransparency=1,TextStrokeTransparency=1}):Play()
	Debris:AddItem(anchor,0.72)
end

local function burstAtCharacter(color, scale)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(2,2,2)
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.22
	p.Anchored = true
	p.CanCollide = false
	p.CFrame = root.CFrame
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(0.28), {
		Size = Vector3.new(scale,scale,scale),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p,0.32)
end

local executeMarkerToken=0
local executeMarkerObjects={}
local function clearExecuteMarker()
	executeMarkerToken+=1
	for _,object in ipairs(executeMarkerObjects) do if object and object.Parent then object:Destroy() end end
	table.clear(executeMarkerObjects)
end
local function showExecuteMarker(data)
	clearExecuteMarker()
	local target=data and data.Target
	local core=target and target.PrimaryPart
	if not target or not core then return end
	local token=executeMarkerToken
	local h=Instance.new("Highlight")
	h.Name="ExecutionReady"; h.Adornee=target; h.FillColor=Color3.fromRGB(177,74,255)
	h.OutlineColor=Color3.fromRGB(255,221,116); h.FillTransparency=.8; h.OutlineTransparency=.08
	h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; h.Parent=target
	local bb=Instance.new("BillboardGui")
	bb.Name="ExecutePrompt"; bb.Adornee=core; bb.Size=UDim2.fromOffset(180,48); bb.StudsOffset=Vector3.new(0,4.7,0)
	bb.AlwaysOnTop=true; bb.Parent=core
	local text=Instance.new("TextLabel")
	text.Size=UDim2.fromScale(1,1); text.BackgroundColor3=Color3.fromRGB(18,11,31); text.BackgroundTransparency=.12
	text.Text="F  //  EXECUTE"; text.TextColor3=Color3.fromRGB(255,232,150); text.Font=Enum.Font.GothamBlack; text.TextSize=16
	text.Parent=bb; corner(text,8); stroke(text,Color3.fromRGB(190,92,255),.08,2)
	executeMarkerObjects={h,bb}
	task.delay((data.Duration or 1.5),function() if executeMarkerToken==token then clearExecuteMarker() end end)
end

local surgeAura
local function setSurgeAura(enabled,duration)
	if surgeAura and surgeAura.Parent then surgeAura:Destroy() end
	surgeAura=nil
	if not enabled then return end
	local character=player.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local h=Instance.new("Highlight")
	h.Name="RiftSurgeAura"; h.Adornee=character; h.FillColor=Color3.fromRGB(105,67,255)
	h.OutlineColor=Color3.fromRGB(255,96,200); h.FillTransparency=.72; h.OutlineTransparency=.04
	h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; h.Parent=character; surgeAura=h
	local light=Instance.new("PointLight")
	light.Name="RiftSurgeLight"; light.Color=Color3.fromRGB(153,84,255); light.Brightness=2.4; light.Range=18; light.Parent=root
	Debris:AddItem(light,(duration or 8)+.2)
	for i=1,3 do
		local ring=Instance.new("Part")
		ring.Shape=Enum.PartType.Cylinder; ring.Size=Vector3.new(.08,2+i*1.2,2+i*1.2)
		ring.Material=Enum.Material.Neon; ring.Color=i%2==0 and Color3.fromRGB(255,86,190) or Color3.fromRGB(100,115,255)
		ring.Transparency=.32; ring.Anchored=true; ring.CanCollide=false
		ring.CFrame=root.CFrame*CFrame.new(0,-2.6,0)*CFrame.Angles(0,0,math.rad(90)); ring.Parent=workspace
		TweenService:Create(ring,TweenInfo.new(.55+i*.08),{Size=Vector3.new(.04,10+i*2,10+i*2),Transparency=1}):Play(); Debris:AddItem(ring,1)
	end
	if duration then task.delay(duration,function() setSurgeAura(false) end) end
end

local function executeBurst(data)
	clearExecuteMarker(); hitStopUntil=math.max(hitStopUntil,os.clock()+.09); cameraShake=math.max(cameraShake,.72)
	local position=data.Position
	if not position then return end
	for i=1,4 do
		local ring=Instance.new("Part")
		ring.Name="ExecutionRing"; ring.Shape=Enum.PartType.Cylinder; ring.Size=Vector3.new(.1,2+i,2+i)
		ring.Material=Enum.Material.Neon; ring.Color=i%2==0 and Color3.fromRGB(255,205,92) or Color3.fromRGB(164,67,255)
		ring.Transparency=.12; ring.Anchored=true; ring.CanCollide=false
		ring.CFrame=CFrame.new(position)*CFrame.Angles(math.rad(90),0,0); ring.Parent=workspace
		TweenService:Create(ring,TweenInfo.new(.22+i*.035,Enum.EasingStyle.Exponential,Enum.EasingDirection.Out),{Size=Vector3.new(.04,14+i*3,14+i*3),Transparency=1}):Play()
		Debris:AddItem(ring,.45)
	end
	showNotice(data.Boss and "WARDEN EXECUTION STRIKE" or "RIFT EXECUTION",Color3.fromRGB(255,218,121))
end

State.OnClientEvent:Connect(function(kind, data)
	if kind == "Profile" then
		updateProfile(data)

	elseif kind == "TrainingStart" then
		inMission = true
		effectSettings.SetMissionGrade(true)
		trainingMode = true
		duelMode = false
		missionRequestPending = false
		settingsShade.Visible = false; progressionShade.Visible = false; result.Visible = false
		progressButton.Visible=false; armoryButton.Visible=false; settingsButton.Visible=false; effectSettings.SupportButton.Visible=false; effectSettings.SystemDock.Visible=false; effectSettings.Support.SetOpen(false)
		restorePlayerControl(player.Character)
		lobbyPanel.Visible = false; chapterCard.Visible = false; questCard.Visible = false
		startButton.Visible = false; trainingButton.Visible = false; duelButton.Visible = false
		skillBar.Visible = true; surgePanel.Visible = true; healthPanel.Visible = true; staminaPanel.Visible = true
		effectSettings.SetTouchSprintVisible(true)
		effectSettings.TrainingExit.Visible=true
		updateSurgeMeter(0,false)
		missionText.Text = "COMBAT FORGE  //  SIGNATURE DRILL"
		objectiveText.Text = "STEP 1  RMB HEAVY ATTACK  //  BREAK THE TRAINING FRAME"
		coachTitle.Text = "BREAK  →  EXECUTE  →  SURGE"
		coachText.Text = "RMB break guard  ·  F execute  ·  R overdrive  ·  B return to Sanctum"
		showCombatCoach()
		showNotice("COMBAT DRILL ONLINE",Color3.fromRGB(238,185,104))

	elseif kind == "DuelQueue" then
		duelQueued = data.Waiting == true
		duelButton.Text = duelQueued and string.format("SEARCHING  #%d  /  CANCEL",data.Position or 1) or "RIFT DUEL"
		showNotice(duelQueued and "RIFT DUEL QUEUE JOINED" or "DUEL QUEUE CANCELLED",Color3.fromRGB(174,126,255))

	elseif kind == "DuelStart" then
		inMission = true; trainingMode = false; duelMode = true; duelQueued = false
		effectSettings.SetMissionGrade(true)
		missionRequestPending = false; result.Visible = false; settingsShade.Visible = false; progressionShade.Visible = false
		progressButton.Visible=false; armoryButton.Visible=false; settingsButton.Visible=false; effectSettings.SupportButton.Visible=false; effectSettings.SystemDock.Visible=false; effectSettings.Support.SetOpen(false)
		restorePlayerControl(player.Character)
		lobbyPanel.Visible=false; chapterCard.Visible=false; questCard.Visible=false
		startButton.Visible=false; trainingButton.Visible=false; duelButton.Visible=false
		skillBar.Visible=true; surgePanel.Visible=true; healthPanel.Visible=true; staminaPanel.Visible=true
		effectSettings.SetTouchSprintVisible(true)
		effectSettings.TrainingExit.Visible=false
		updateSurgeMeter(0,false)
		missionText.Text = "RIFT DUEL  //  VS "..string.upper(data.Opponent or "RIVAL")
		objectiveText.Text = "SYNCED POWER  ATK 50  ·  DEF 20  ·  HP 500  //  DEFEAT YOUR RIVAL"
		coachTitle.Text = "1v1 COMBAT PROTOCOL"
		coachText.Text = "BREAK → F punish  ·  SPACE dodge  ·  R Surge  ·  B forfeits the duel"
		showCombatCoach(); showNotice("DUEL LINK ESTABLISHED",Color3.fromRGB(174,126,255))

	elseif kind == "MissionStart" then
		inMission = true
		effectSettings.SetMissionGrade(true)
		trainingMode = false
		duelMode = false
		missionRequestPending = false
		result.Visible = false
		settingsShade.Visible = false
		progressionShade.Visible = false
		progressButton.Visible=false; armoryButton.Visible=false; settingsButton.Visible=false; effectSettings.SupportButton.Visible=false; effectSettings.SystemDock.Visible=false; effectSettings.Support.SetOpen(false)
		restorePlayerControl(player.Character)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end
		lobbyPanel.Visible = false
		chapterCard.Visible = false
		questCard.Visible = false
		startButton.Visible = false
		trainingButton.Visible = false
		duelButton.Visible = false
		effectSettings.SystemDock.Visible = false
		skillBar.Visible = true
		surgePanel.Visible = true
		updateSurgeMeter(0, false)
		healthPanel.Visible = true
		staminaPanel.Visible = true
		effectSettings.SetTouchSprintVisible(true)
		effectSettings.TrainingExit.Visible=false
		coachTitle.Text = "COMBAT LINK ONLINE"
		coachText.Text = "BREAK → F EXECUTE  ·  Build Surge → R OVERDRIVE  ·  Q / E skills  ·  SPACE dodge"
		showCombatCoach()
		missionText.Text = "RIFT LINK ESTABLISHED"
		objectiveText.Text = "OBJECTIVE  REACH THE FIRST COMBAT WAVE"
		showNotice("MISSION START", Color3.fromRGB(155,145,255))

	elseif kind == "Mission" then
		inMission = true
		missionText.Text = string.format("%s   //   WAVE %d / %d", data.Label or "RIFT", data.Wave or 0, data.TotalWaves or 0)
		objectiveText.Text = string.format("OBJECTIVE  DEFEAT HOSTILES   %d REMAIN", data.EnemyCount or 0)
		showNotice(data.Label or "NEW WAVE")
		if data.Wave == 5 then effectSettings.BossIntro.Show(); attachBoss() end

	elseif kind == "MissionComplete" then
		inMission = false
		effectSettings.SetMissionGrade(false)
		trainingMode = false
		duelMode = false
		detachBoss()
		effectSettings.BossIntro.Hide()
		runePanel.Visible = false
		startButton.Visible = false
		trainingButton.Visible = false
		duelButton.Visible = false
		skillBar.Visible = false
		surgePanel.Visible = false
		clearExecuteMarker()
		setSurgeAura(false)
		dismissCombatCoach()
		healthPanel.Visible = false
		staminaPanel.Visible = false
		effectSettings.SetTouchSprintVisible(false)
		effectSettings.TrainingExit.Visible=false
		missionText.Text = "RIFT STABILIZED"
		objectiveText.Text = "OBJECTIVE COMPLETE  /  CLAIM BOSS DROP"
		result.Visible = true
		local report = data.Report or {}
		local loot = data.Loot or {Name="NO DROP",Rarity="--",ATK=0}
		local lootLine = loot.Duplicate and string.format("%s [%s]  ·  DUPLICATE SALVAGED +%d C", loot.Name or "WEAPON", loot.Rarity or "", loot.SalvageCredits or 0)
			or string.format("%s [%s]  ·  ATK +%d", loot.Name or "WEAPON", loot.Rarity or "", loot.ATK or 0)
		local grade=report.Grade or "B"
		local gradeColors={S=Color3.fromRGB(247,196,87),A=Color3.fromRGB(116,222,236),B=Color3.fromRGB(174,133,247),C=Color3.fromRGB(229,112,101)}
		resultTitle.Text = string.format("RIFT CLEARED   //   %s", data.Difficulty or "NORMAL")
		effectSettings.Result.Grade.Text=grade
		effectSettings.Result.Grade.TextColor3=gradeColors[grade] or gradeColors.B
		effectSettings.Result.Score.Text=string.format("SCORE  %d",report.Score or 0)
		effectSettings.Result.Best.Visible=data.NewBest==true
		effectSettings.Result.Loot.Text=lootLine
		resultBody.Text = string.format(
			"CLEAR TIME       %.2fs\nDAMAGE DEALT     %d\nDAMAGE TAKEN     %d\nBREAKS           %d\nEXECUTIONS       %d\nPERFECT DODGES   %d\n\nREWARDS   +%d XP   +%d CREDITS   +%d SHARDS",
			data.Time or 0, report.Damage or 0, report.DamageTaken or 0, report.Breaks or 0, report.Executions or 0, report.Dodges or 0,
			data.XP or 0, data.Credits or 0, data.Shards or 0
		)

	elseif kind == "Lobby" then
		inMission = false
		effectSettings.SetMissionGrade(false)
		trainingMode = false
		duelMode = false
		duelQueued = false
		detachBoss()
		effectSettings.BossIntro.Hide()
		runePanel.Visible = false
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.Jump=false; humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end
		missionRequestPending = false
		startButton.Text = profile and profile.Difficulty == "HARD" and "ENTER ASHEN SANCTUM  //  HARD" or "ENTER ASHEN SANCTUM"
		startButton.Visible = true
		trainingButton.Visible = true
		duelButton.Visible = true
		duelButton.Text = "RIFT DUEL"
		progressButton.Visible=true; armoryButton.Visible=true; settingsButton.Visible=true; effectSettings.SupportButton.Visible=true; effectSettings.SystemDock.Visible=true
		lobbyPanel.Visible = true
		chapterCard.Visible = true
		questCard.Visible = not UserInputService.TouchEnabled
		effectSettings.ApplyResponsiveLayout()
		skillBar.Visible = false
		surgePanel.Visible = false
		clearExecuteMarker()
		setSurgeAura(false)
		dismissCombatCoach()
		healthPanel.Visible = false
		staminaPanel.Visible = false
		effectSettings.SetTouchSprintVisible(false)
		effectSettings.TrainingExit.Visible=false
		missionText.Text = "LOBBY // PREPARE YOUR FRAME"
		objectiveText.Text = "OBJECTIVE  REVIEW LOADOUT  /  ENTER THE RIFT"

	elseif kind == "Damage" then
		worldPopup(data)
		impactBurst(data)
		local step=data.Step or 1
		local timing=ATTACK_TIMING[step] or ATTACK_TIMING[1]
		hitStopUntil=math.max(hitStopUntil,os.clock()+timing.Stop)
		cameraShake=math.max(cameraShake,timing.Shake+(data.Crit and .2 or 0))

	elseif kind == "RuneOffer" then
		progressionShade.Visible = false
		for i, choice in ipairs(data.Choices or {}) do
			local card = runeCards[i]
			if card then
				card.Card:SetAttribute("RuneId", choice.Id)
				card.Tag.Text = choice.Tag or "RUNE"
				card.Name.Text = choice.Name or "RUNE"
				card.Description.Text = choice.Description or ""
			end
		end
		runePanel.Visible = true
	elseif kind == "RuneChosen" then
		runePanel.Visible = false
		showNotice("RUNE BOUND  /  "..(data.Name or ""), Color3.fromRGB(228,193,130))

	elseif kind == "Cooldown" then
		cooldownUntil[data.Key] = os.clock() + data.Duration

	elseif kind == "AttackFX" then
		localComboStep=(data.Step or 1)%3+1

	elseif kind == "EnemyDefeated" then
		clearExecuteMarker()
		objectiveText.Text = string.format("OBJECTIVE  DEFEAT HOSTILES   %d REMAIN", data.Remaining or 0)
		if data.Position then
			impactBurst({Position=data.Position,Step=3,Crit=false})
			local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			playSound(root,"rbxasset://sounds/impact_explosion_03.mp3",.2,.78)
		end
	elseif kind == "BossTelegraph" then
		effectSettings.BossAttack.Show(data.Mode,data.Duration)
	elseif kind == "BossPhase" then
		effectSettings.BossAttack.Phase(data)
	elseif kind == "QuestProgress" then
		questProgress.Text = string.format("DEFEAT RIFTBOUND  %d / %d",data.Current or 0,data.Target or 12)
	elseif kind == "SupportCelebration" then
		effectSettings.Support.SetOpen(false)
		burstAtCharacter(data.Founder and Color3.fromRGB(238,191,92) or Color3.fromRGB(199,105,255),18)
		showNotice(data.Founder and "FOUNDER SIGNAL BOUND  //  THANK YOU" or "RIFT SIGNAL RECEIVED  //  THANK YOU",data.Founder and Color3.fromRGB(238,191,92) or Color3.fromRGB(199,105,255))
		local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		playSound(root,"rbxasset://sounds/electronicpingshort.wav",.25,1.08)

	elseif kind == "DodgeFX" then
		burstAtCharacter(Color3.fromRGB(90,220,255), 14)
		local character=player.Character
		local root=character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local direction=typeof(data.Direction)=="Vector3" and data.Direction.Magnitude>.1 and data.Direction.Unit or root.CFrame.LookVector
			local trail=Instance.new("Part")
			trail.Name="PhaseDodgeTrail"; trail.Size=Vector3.new(3.8,.18,9); trail.Material=Enum.Material.Neon
			trail.Color=Color3.fromRGB(82,196,255); trail.Transparency=.42; trail.Anchored=true
			trail.CanCollide=false; trail.CanTouch=false; trail.CanQuery=false
			trail.CFrame=CFrame.lookAt(root.Position-Vector3.new(0,2.65,0),root.Position-Vector3.new(0,2.65,0)+direction)*CFrame.new(0,0,3.6)
			trail.Parent=workspace
			TweenService:Create(trail,TweenInfo.new(.2,Enum.EasingStyle.Quad),{Transparency=1,Size=Vector3.new(2,.08,13)}):Play()
			Debris:AddItem(trail,.24)
			local phase=Instance.new("Highlight")
			phase.Name="PhaseDodgeFlash"; phase.Adornee=character; phase.FillColor=Color3.fromRGB(91,211,255)
			phase.OutlineColor=Color3.fromRGB(222,121,255); phase.FillTransparency=.52; phase.OutlineTransparency=.15
			phase.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; phase.Parent=character
			TweenService:Create(phase,TweenInfo.new(.2),{FillTransparency=1,OutlineTransparency=1}):Play()
			Debris:AddItem(phase,.24)
			playSound(root,"rbxassetid://9080058053",.18,1.35)
		end
		cameraShake=math.max(cameraShake,.14)
	elseif kind == "GuardBreakFX" then
		cameraShake = math.max(cameraShake, .34)
	elseif kind == "Break" then
		showNotice("BREAK", Color3.fromRGB(255,200,115))
		if data.Position then impactBurst({Position=data.Position, Step=4, Target=data.Target}) end
	elseif kind == "ExecuteReady" then
		showExecuteMarker(data)
	elseif kind == "ExecuteFX" then
		clearExecuteMarker()
		executeBurst(data)
	elseif kind == "Surge" then
		surgePanel.Visible = inMission
		updateSurgeMeter(data.Value or 0, data.Active == true)
	elseif kind == "SurgeStart" then
		updateSurgeMeter(0, true)
		setSurgeAura(true, data.Duration or 8)
		cameraShake = math.max(cameraShake, .48)
		showNotice("RIFT SURGE  //  OVERDRIVE", Color3.fromRGB(235,91,191))
	elseif kind == "SurgeEnd" then
		setSurgeAura(false)
		updateSurgeMeter(0, false)
	elseif kind == "TrainingGuide" then
		objectiveText.Text = data.Text or "CONTINUE THE DRILL"
		showNotice(data.Text or "TRAINING UPDATED",Color3.fromRGB(238,185,104))
	elseif kind == "TrainingComplete" then
		objectiveText.Text = data.Text or "DRILL COMPLETE  //  B RETURN"
		showNotice("SIGNATURE COMBAT MASTERED",Color3.fromRGB(235,91,191))
	elseif kind == "DuelGuardBroken" then
		showNotice("GUARD BROKEN  //  EVADE THE PUNISH",Color3.fromRGB(255,112,104))
	elseif kind == "DuelComplete" then
		inMission=false; duelMode=false; trainingMode=false; attackBusy=false
		effectSettings.SetTouchSprintVisible(false)
		effectSettings.TrainingExit.Visible=false
		surgePanel.Visible=false; clearExecuteMarker(); setSurgeAura(false); dismissCombatCoach()
		missionText.Text = data.Won and "RIFT DUEL  //  VICTORY" or "RIFT DUEL  //  DEFEAT"
		objectiveText.Text = data.Forfeit and "DUEL ENDED BY FORFEIT  //  RETURNING TO SANCTUM" or "COMBAT RECORD SEALED  //  RETURNING TO SANCTUM"
		showNotice(data.Won and "DUEL VICTORY" or "DUEL DEFEAT",data.Won and Color3.fromRGB(238,190,98) or Color3.fromRGB(255,112,104))

	elseif kind == "PlayerHit" then
		cameraShake = math.max(cameraShake, .32)
		if (data.Damage or 0) > 0 then
			showNotice("-"..tostring(data.Damage).." HP", Color3.fromRGB(255,100,120))
		elseif (data.Shielded or 0) > 0 then
			showNotice("SHIELD  -"..tostring(data.Shielded), Color3.fromRGB(99,215,230))
		end
	elseif kind == "PlayerDefeated" then
		inMission=false; trainingMode=false; duelMode=false; missionRequestPending=false; attackBusy=false
		effectSettings.SetTouchSprintVisible(false)
		effectSettings.TrainingExit.Visible=false
		effectSettings.SystemDock.Visible=false
		surgePanel.Visible=false; clearExecuteMarker(); setSurgeAura(false)
		dismissCombatCoach(); showDefeatTransition()
		missionText.Text="FRAME DESTABILIZED"; objectiveText.Text="RECONSTRUCTING AT SANCTUM"
	elseif kind == "RespawnReady" then
		inMission=false; trainingMode=false; duelMode=false; duelQueued=false; missionRequestPending=false; attackBusy=false
		effectSettings.SetTouchSprintVisible(false)
		effectSettings.TrainingExit.Visible=false
		result.Visible=false; runePanel.Visible=false; settingsShade.Visible=false; progressionShade.Visible=false; effectSettings.Support.SetOpen(false)
		startButton.Visible=true; trainingButton.Visible=true; duelButton.Visible=true; lobbyPanel.Visible=true; chapterCard.Visible=true; questCard.Visible=not UserInputService.TouchEnabled
		progressButton.Visible=true; armoryButton.Visible=true; settingsButton.Visible=true; effectSettings.SupportButton.Visible=true; effectSettings.SystemDock.Visible=true
		effectSettings.ApplyResponsiveLayout()
		duelButton.Text="RIFT DUEL"
		skillBar.Visible=false; surgePanel.Visible=false; healthPanel.Visible=false; staminaPanel.Visible=false
		clearExecuteMarker(); setSurgeAura(false); updateSurgeMeter(0,false)
		missionText.Text="LOBBY // FRAME RESTORED"; objectiveText.Text="OBJECTIVE  REVIEW LOADOUT  /  ENTER THE RIFT"
		hideDefeatTransition()

	elseif kind == "Notice" then
		showNotice(data.Text or "")
	end
end)

task.spawn(function()
	task.wait(1)
	local ok, p, s = pcall(function()
		return Snapshot:InvokeServer()
	end)
	if ok then
		updateProfile(p)
		if s and s.InMission then
			inMission = true
			trainingMode = s.Training == true
			duelMode = s.InDuel == true
			lobbyPanel.Visible = false
			chapterCard.Visible = false
			questCard.Visible = false
			startButton.Visible = false
			trainingButton.Visible = false
			duelButton.Visible = false
			effectSettings.SystemDock.Visible = false
			skillBar.Visible = true
			healthPanel.Visible = true
			staminaPanel.Visible = true
		else
			effectSettings.ApplyResponsiveLayout()
		end
	end
end)
