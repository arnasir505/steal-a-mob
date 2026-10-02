-- Ragdoll: помогает упасть и встать, когда сервер роняет игрока (RagdollService).
--
-- Само падение делает сервер. Но состоянием Humanoid управляет компьютер
-- игрока, поэтому переключаем его здесь: иначе после падения персонаж
-- может ещё какое-то время лежать, прежде чем встанет сам.
--
-- Ещё здесь выключаются встроенные падения Roblox (FallingDown и Ragdoll).
-- Roblox сам роняет персонажа, если тот на большой скорости врезается в стену:
-- его отбрасывает, и он лежит. По дизайну игрок падает только от толчка босса
-- и удара мечом, а это наш RagdollService — он через эти состояния не работает.

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local function noTripping(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	end
end

local function watch(character)
	task.spawn(noTripping, character)
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
