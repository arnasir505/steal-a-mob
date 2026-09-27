-- Ragdoll: помогает упасть и встать, когда сервер роняет игрока (RagdollService).
--
-- Само падение делает сервер. Но состоянием Humanoid управляет компьютер
-- игрока, поэтому переключаем его здесь: иначе после падения персонаж
-- может ещё какое-то время лежать, прежде чем встанет сам.

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local function watch(character)
	character:GetAttributeChangedSignal("Ragdoll"):Connect(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		if character:GetAttribute("Ragdoll") then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		else
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

player.CharacterAdded:Connect(watch)
if player.Character then
	watch(player.Character)
end
