-- RIFT PROTOCOL
-- CombatServer = 服务器战斗系统

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- ================================
-- 读取配置
-- ================================

local ConfigFolder = ReplicatedStorage:WaitForChild("Config")

local BalanceConfig = require(
	ConfigFolder:WaitForChild("BalanceConfig")
)

local PlayerConfig = require(
	ConfigFolder:WaitForChild("PlayerConfig")
)

local SkillConfig = require(
	ConfigFolder:WaitForChild("SkillConfig")
)

-- ================================
-- 读取 RemoteEvent
-- ================================

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local BasicAttackEvent =
	Remotes:WaitForChild("BasicAttack")


-- ================================
-- 每个玩家的攻击状态
-- ================================

local playerAttackState = {}


-- ================================
-- 寻找距离玩家最近的敌人
-- ================================

local function findNearestEnemy(player, maxRange)

	local character = player.Character

	if not character then
		return nil
	end

	local rootPart =
		character:FindFirstChild("HumanoidRootPart")

	if not rootPart then
		return nil
	end

	local enemiesFolder =
		Workspace:FindFirstChild("Enemies")

	if not enemiesFolder then
		return nil
	end


	local nearestEnemy = nil
	local nearestDistance = math.huge


	for _, enemy in ipairs(enemiesFolder:GetChildren()) do

		if enemy:IsA("Model") then

			local enemyPart =
				enemy.PrimaryPart
				or enemy:FindFirstChild("Core")

			local currentHP =
				enemy:GetAttribute("CurrentHP")

			if enemyPart and currentHP and currentHP > 0 then

				local distance =
					(rootPart.Position - enemyPart.Position).Magnitude

				if distance <= maxRange
					and distance < nearestDistance then

					nearestEnemy = enemy
					nearestDistance = distance

				end
			end
		end
	end


	return nearestEnemy
end


-- ================================
-- 计算最终伤害
-- ================================

local function calculateDamage(
	playerATK,
	attackCoefficient,
	enemyDEF,
	critChance,
	critDamage
)

	-- 原始伤害
	local rawDamage =
		playerATK * attackCoefficient

	-- 防御减伤
	local K =
		BalanceConfig.DamageDefenseK

	local finalDamage =
		rawDamage * K / (K + enemyDEF)


	-- 暴击
	local isCritical =
		math.random() < critChance

	if isCritical then
		finalDamage =
			finalDamage * critDamage
	end


	return finalDamage, isCritical
end


-- ================================
-- 玩家请求普通攻击
-- ================================

BasicAttackEvent.OnServerEvent:Connect(
	function(player)

		local now = os.clock()

		-- 如果这个玩家第一次攻击
		if not playerAttackState[player] then

			playerAttackState[player] = {
				ComboStep = 1,
				LastAttackTime = 0,
				NextAttackTime = 0,
			}

		end


		local state =
			playerAttackState[player]


		-- ============================
		-- 防止攻击速度作弊
		-- ============================

		if now < state.NextAttackTime then
			return
		end


		local basicAttack =
			SkillConfig.BasicAttack


		-- ============================
		-- 连招超时则重置
		-- ============================

		if now - state.LastAttackTime
			> basicAttack.ComboResetTime then

			state.ComboStep = 1

		end


		local step =
			basicAttack.Steps[state.ComboStep]


		-- ============================
		-- 寻找目标
		-- ============================

		local enemy =
			findNearestEnemy(
				player,
				basicAttack.Range
			)

		if not enemy then
			return
		end


		-- ============================
		-- 读取玩家属性
		-- ============================

		local playerData =
			PlayerConfig.Default

		local enemyDEF =
			enemy:GetAttribute("DEF")
			or 0


		-- ============================
		-- 计算伤害
		-- ============================

		local damage, isCritical =
			calculateDamage(
				playerData.ATK,
				step.ATKCoef,
				enemyDEF,
				playerData.CritChance,
				playerData.CritDamage
			)


		damage =
			math.floor(damage + 0.5)


		-- ============================
		-- 扣除敌人 HP
		-- ============================

		local currentHP =
			enemy:GetAttribute("CurrentHP")

		local maxHP =
			enemy:GetAttribute("MaxHP")

		local newHP =
			math.max(
				currentHP - damage,
				0
			)


		enemy:SetAttribute(
			"CurrentHP",
			newHP
		)


		print(
			"[RIFT]",
			player.Name,
			step.Name,
			"Damage:",
			damage,
			"Crit:",
			isCritical,
			"Enemy HP:",
			newHP
		)


		-- ============================
		-- 敌人死亡
		-- ============================

		if newHP <= 0 then

			print(
				"[RIFT]",
				enemy.Name,
				"DEFEATED"
			)

			-- 第一版测试：
			-- 2.5 秒后直接回满血
			task.delay(2.5, function()

				if enemy
					and enemy.Parent then

					enemy:SetAttribute(
						"CurrentHP",
						maxHP
					)

				end
			end)

		end


		-- ============================
		-- 更新连招
		-- ============================

		state.LastAttackTime = now

		state.NextAttackTime =
			now + step.Cooldown


		state.ComboStep += 1


		if state.ComboStep
			> #basicAttack.Steps then

			state.ComboStep = 1

		end

	end
)


-- 玩家离开游戏时清理数据
Players.PlayerRemoving:Connect(
	function(player)

		playerAttackState[player] = nil

	end
)