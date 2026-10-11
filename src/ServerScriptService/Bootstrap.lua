-- RIFT PROTOCOL
-- Bootstrap = 游戏启动初始化脚本

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- 读取我们之前制作的敌人配置
local ConfigFolder = ReplicatedStorage:WaitForChild("Config")
local EnemyConfig = require(ConfigFolder:WaitForChild("EnemyConfig"))

-- =========================================================
-- 1. 创建 Enemies 文件夹
-- =========================================================

local enemiesFolder = Workspace:FindFirstChild("Enemies")

if not enemiesFolder then
	enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "Enemies"
	enemiesFolder.Parent = Workspace
end


-- =========================================================
-- 2. 给敌人创建头顶血条
-- =========================================================

local function createHealthBar(enemyModel, corePart, config)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HealthBar"
	billboard.Size = UDim2.fromOffset(180, 55)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = corePart
	billboard.Parent = corePart

	-- 敌人名字
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "EnemyName"
	nameLabel.Size = UDim2.new(1, 0, 0.35, 0)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = config.Name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = billboard

	-- 血条背景
	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Size = UDim2.new(1, 0, 0.28, 0)
	barBackground.Position = UDim2.new(0, 0, 0.38, 0)
	barBackground.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = billboard

	-- 当前血量
	local healthFill = Instance.new("Frame")
	healthFill.Name = "HealthFill"
	healthFill.Size = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = Color3.fromRGB(70, 220, 100)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = barBackground

	-- 数字血量
	local hpText = Instance.new("TextLabel")
	hpText.Name = "HPText"
	hpText.Size = UDim2.new(1, 0, 0.30, 0)
	hpText.Position = UDim2.new(0, 0, 0.70, 0)
	hpText.BackgroundTransparency = 1
	hpText.TextColor3 = Color3.new(1, 1, 1)
	hpText.TextScaled = true
	hpText.Font = Enum.Font.Gotham
	hpText.Parent = billboard

	-- 更新血条
	local function refreshHealth()

		local currentHP = enemyModel:GetAttribute("CurrentHP")
		local maxHP = enemyModel:GetAttribute("MaxHP")

		if not currentHP or not maxHP then
			return
		end

		local ratio = math.clamp(currentHP / maxHP, 0, 1)

		healthFill.Size = UDim2.new(ratio, 0, 1, 0)

		hpText.Text = string.format(
			"%d / %d",
			math.floor(currentHP + 0.5),
			math.floor(maxHP + 0.5)
		)
	end

	enemyModel:GetAttributeChangedSignal("CurrentHP"):Connect(refreshHealth)
	enemyModel:GetAttributeChangedSignal("MaxHP"):Connect(refreshHealth)

	refreshHealth()
end


-- =========================================================
-- 3. 创建 Drone I
-- =========================================================

local function createDrone()

	local config = EnemyConfig.Drone

	-- 防止重复生成
	local oldDrone = enemiesFolder:FindFirstChild(config.Name)

	if oldDrone then
		oldDrone:Destroy()
	end

	-- 创建敌人 Model
	local drone = Instance.new("Model")
	drone.Name = config.Name

	-- 把数值储存在敌人身上
	drone:SetAttribute("EnemyID", "Drone")
	drone:SetAttribute("CurrentHP", config.HP)
	drone:SetAttribute("MaxHP", config.HP)

	drone:SetAttribute("ATK", config.ATK)
	drone:SetAttribute("DEF", config.DEF)

	drone.Parent = enemiesFolder


	-- =============================
	-- Drone 主核心
	-- =============================

	local core = Instance.new("Part")
	core.Name = "Core"

	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(4, 4, 4)

	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(150, 70, 255)

	core.Anchored = true
	core.CanCollide = true

	core.Parent = drone


	-- =============================
	-- 左翼
	-- =============================

	local leftWing = Instance.new("Part")
	leftWing.Name = "LeftWing"

	leftWing.Size = Vector3.new(4, 0.8, 2)

	leftWing.Material = Enum.Material.Metal
	leftWing.Color = Color3.fromRGB(45, 45, 55)

	leftWing.Anchored = true
	leftWing.CanCollide = true

	leftWing.Parent = drone


	-- =============================
	-- 右翼
	-- =============================

	local rightWing = Instance.new("Part")
	rightWing.Name = "RightWing"

	rightWing.Size = Vector3.new(4, 0.8, 2)

	rightWing.Material = Enum.Material.Metal
	rightWing.Color = Color3.fromRGB(45, 45, 55)

	rightWing.Anchored = true
	rightWing.CanCollide = true

	rightWing.Parent = drone


	-- =============================
	-- 决定敌人出生位置
	-- =============================

	local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation")

	local spawnPosition

	if spawnLocation then

		spawnPosition =
			spawnLocation.Position
			+ spawnLocation.CFrame.LookVector * 18
			+ Vector3.new(0, 4, 0)

	else

		spawnPosition = Vector3.new(0, 4, -18)

	end


	core.Position = spawnPosition

	leftWing.Position =
		spawnPosition + Vector3.new(-3.5, 0, 0)

	rightWing.Position =
		spawnPosition + Vector3.new(3.5, 0, 0)


	drone.PrimaryPart = core


	-- =============================
	-- 给敌人加一点光效
	-- =============================

	local light = Instance.new("PointLight")

	light.Color = Color3.fromRGB(160, 80, 255)
	light.Brightness = 2
	light.Range = 10

	light.Parent = core


	-- 创建头顶血条
	createHealthBar(drone, core, config)


	print(
		"[RIFT] Spawned",
		config.Name,
		"HP:",
		config.HP
	)
end


-- 游戏启动时执行
createDrone()