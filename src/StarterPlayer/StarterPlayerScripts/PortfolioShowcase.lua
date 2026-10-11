-- RIFT PROTOCOL portfolio capture director
-- F10: toggle capture mode | 1/2/3: shot preset | H: clean frame
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local enabled = false
local cleanFrame = false
local shot = 1
local hiddenGuiStates = {}
local previousCameraType
local previousFov = 70
local orbitClock = 0

local gui = Instance.new("ScreenGui")
gui.Name = "RIFT_PortfolioCapture"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 10000
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function makeBar(name, position)
	local bar = Instance.new("Frame")
	bar.Name = name
	bar.AnchorPoint = Vector2.new(0.5, name == "TopBar" and 0 or 1)
	bar.Position = position
	bar.Size = UDim2.fromScale(1, 0.105)
	bar.BackgroundColor3 = Color3.fromRGB(3, 5, 11)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(2, 3, 8)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8, 10, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(2, 3, 8)),
	})
	gradient.Parent = bar
	return bar
end

local topBar = makeBar("TopBar", UDim2.fromScale(0.5, 0))
local bottomBar = makeBar("BottomBar", UDim2.fromScale(0.5, 1))

local brand = Instance.new("TextLabel")
brand.Name = "Brand"
brand.AnchorPoint = Vector2.new(0.5, 0.5)
brand.Position = UDim2.fromScale(0.5, 0.5)
brand.Size = UDim2.fromScale(0.72, 0.62)
brand.BackgroundTransparency = 1
brand.Font = Enum.Font.GothamBold
brand.Text = "RIFT PROTOCOL   //   ASHEN SANCTUM"
brand.TextColor3 = Color3.fromRGB(226, 234, 255)
brand.TextScaled = true
brand.TextTransparency = 0.04
brand.Parent = topBar

local brandGradient = Instance.new("UIGradient")
brandGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 220, 255)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(245, 247, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(194, 94, 255)),
})
brandGradient.Parent = brand

local guide = Instance.new("TextLabel")
guide.Name = "Guide"
guide.AnchorPoint = Vector2.new(0.5, 0.5)
guide.Position = UDim2.fromScale(0.5, 0.5)
guide.Size = UDim2.fromScale(0.8, 0.56)
guide.BackgroundTransparency = 1
guide.Font = Enum.Font.GothamMedium
guide.Text = "1  HERO   •   2  COMBAT   •   3  WIDE   •   H  CLEAN FRAME   •   F10  EXIT"
guide.TextColor3 = Color3.fromRGB(140, 183, 213)
guide.TextScaled = false
guide.TextSize = 16
guide.Parent = bottomBar

local accent = Instance.new("Frame")
accent.AnchorPoint = Vector2.new(0.5, 0)
accent.Position = UDim2.fromScale(0.5, 0)
accent.Size = UDim2.new(0.22, 0, 0, 2)
accent.BackgroundColor3 = Color3.fromRGB(90, 224, 255)
accent.BorderSizePixel = 0
accent.Parent = bottomBar

local dof = Instance.new("DepthOfFieldEffect")
dof.Name = "RIFT_PortfolioDOF"
dof.Enabled = false
dof.FarIntensity = 0.12
dof.FocusDistance = 22
dof.InFocusRadius = 18
dof.NearIntensity = 0.08
dof.Parent = Lighting

local grade = Instance.new("ColorCorrectionEffect")
grade.Name = "RIFT_PortfolioGrade"
grade.Enabled = false
grade.Brightness = 0.025
grade.Contrast = 0.13
grade.Saturation = 0.08
grade.TintColor = Color3.fromRGB(218, 228, 255)
grade.Parent = Lighting

local function getRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getCombatTarget(root)
	local best
	local bestDistance = 120
	for _, item in ipairs(workspace:GetDescendants()) do
		if item:IsA("Model") and item ~= player.Character then
			local humanoid = item:FindFirstChildOfClass("Humanoid")
			local targetRoot = item:FindFirstChild("HumanoidRootPart") or item.PrimaryPart
			if humanoid and humanoid.Health > 0 and targetRoot then
				local distance = (targetRoot.Position - root.Position).Magnitude
				if distance < bestDistance then
					bestDistance = distance
					best = targetRoot
				end
			end
		end
	end
	return best
end

local function setCleanFrame(value)
	cleanFrame = value
	for _, child in ipairs(player.PlayerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child ~= gui then
			if value then
				if hiddenGuiStates[child] == nil then
					hiddenGuiStates[child] = child.Enabled
				end
				child.Enabled = false
			elseif hiddenGuiStates[child] ~= nil then
				child.Enabled = hiddenGuiStates[child]
			end
		end
	end
	topBar.Visible = not value
	bottomBar.Visible = not value
	if not value then
		table.clear(hiddenGuiStates)
	end
end

local function setEnabled(value)
	if enabled == value then return end
	enabled = value
	if value then
		camera = workspace.CurrentCamera
		previousCameraType = camera.CameraType
		previousFov = camera.FieldOfView
		orbitClock = 0
		shot = 1
		gui.Enabled = true
		topBar.Visible = true
		bottomBar.Visible = true
		topBar.Position = UDim2.fromScale(0.5, -0.12)
		bottomBar.Position = UDim2.fromScale(0.5, 1.12)
		TweenService:Create(topBar, TweenInfo.new(0.38, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.fromScale(0.5, 0)}):Play()
		TweenService:Create(bottomBar, TweenInfo.new(0.38, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.fromScale(0.5, 1)}):Play()
		dof.Enabled = true
		grade.Enabled = true
		camera.CameraType = Enum.CameraType.Scriptable
		TweenService:Create(camera, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {FieldOfView = 48}):Play()
	else
		setCleanFrame(false)
		gui.Enabled = false
		dof.Enabled = false
		grade.Enabled = false
		if camera then
			camera.CameraType = previousCameraType or Enum.CameraType.Custom
			camera.FieldOfView = previousFov
		end
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed and input.KeyCode ~= Enum.KeyCode.F10 then return end
	if input.KeyCode == Enum.KeyCode.F10 then
		setEnabled(not enabled)
	elseif enabled and input.KeyCode == Enum.KeyCode.One then
		shot = 1
	elseif enabled and input.KeyCode == Enum.KeyCode.Two then
		shot = 2
	elseif enabled and input.KeyCode == Enum.KeyCode.Three then
		shot = 3
	elseif enabled and input.KeyCode == Enum.KeyCode.H then
		setCleanFrame(not cleanFrame)
	end
end)

RunService:BindToRenderStep("RIFT_PortfolioCamera", Enum.RenderPriority.Camera.Value + 10, function(dt)
	if not enabled then return end
	local root = getRoot()
	if not root or not camera then return end
	orbitClock += dt
	local rootPosition = root.Position
	local desired
	local lookAt
	if shot == 1 then
		local angle = orbitClock * 0.14
		local localOffset = Vector3.new(math.sin(angle) * 7.5, 3.1, math.cos(angle) * 7.5)
		desired = rootPosition + root.CFrame:VectorToWorldSpace(localOffset)
		lookAt = rootPosition + Vector3.new(0, 2.2, 0)
		dof.FocusDistance = 8
		dof.InFocusRadius = 8
	elseif shot == 2 then
		local target = getCombatTarget(root)
		lookAt = target and (rootPosition:Lerp(target.Position, 0.64) + Vector3.new(0, 1.8, 0)) or (rootPosition + root.CFrame.LookVector * 14 + Vector3.new(0, 1.8, 0))
		desired = rootPosition + root.CFrame.RightVector * 4.6 - root.CFrame.LookVector * 8.5 + Vector3.new(0, 4.2, 0)
		dof.FocusDistance = math.clamp((lookAt - desired).Magnitude, 10, 45)
		dof.InFocusRadius = 18
	else
		local target = getCombatTarget(root)
		local focus = target and rootPosition:Lerp(target.Position, 0.5) or rootPosition
		local radius = target and math.clamp((target.Position - rootPosition).Magnitude + 17, 24, 46) or 32
		local angle = orbitClock * 0.08
		desired = focus + Vector3.new(math.cos(angle) * radius, 14, math.sin(angle) * radius)
		lookAt = focus + Vector3.new(0, 2.2, 0)
		dof.FocusDistance = radius
		dof.InFocusRadius = 30
	end
	local targetCFrame = CFrame.lookAt(desired, lookAt)
	camera.CFrame = camera.CFrame:Lerp(targetCFrame, 1 - math.exp(-dt * 4.6))
end)

player.CharacterRemoving:Connect(function()
	if enabled then setEnabled(false) end
end)
