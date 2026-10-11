-- RIFT PROTOCOL
-- CombatClient = 客户端战斗输入

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local UserInputService =
	game:GetService("UserInputService")


-- 获取 RemoteEvent
local Remotes =
	ReplicatedStorage:WaitForChild("Remotes")

local BasicAttackEvent =
	Remotes:WaitForChild("BasicAttack")


-- ================================
-- 玩家输入
-- ================================

UserInputService.InputBegan:Connect(
	function(input, gameProcessed)

		-- 如果玩家正在输入聊天等 UI
		-- 就不要触发攻击
		if gameProcessed then
			return
		end


		-- 鼠标左键
		if input.UserInputType
			== Enum.UserInputType.MouseButton1 then

			BasicAttackEvent:FireServer()

		end

	end
)