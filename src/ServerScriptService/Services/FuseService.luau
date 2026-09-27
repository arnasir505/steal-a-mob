-- FuseService: машина синтеза.
--
-- 3 одинаковых моба (один MobId, редкость и вес любые) -> 1 моб:
--  * вес — как у самого тяжёлого из трёх, но с шансом 5% моб станет тяжелее
--    (в 1.5–3 раза). Чем тяжелее моб, тем меньше этот шанс (Formulas.FuseUpgradeChance);
--  * редкость и мутация — по правилу GameConfig.Fuse.ResultTraits;
--  * результат попадает в рюкзак.
-- Синтезируются только мобы из рюкзака: с участка их надо сначала убрать (E у моба).
-- Все числа — в GameConfig.Fuse, расчёт результата — Formulas.RollFuse.
--
-- Машина: модель или деталь с именем FuseMachine в любом месте Workspace
-- (одна в лобби или по одной на каждом участке). На ней появляется кнопка Fuse.
--
-- Выбирать мобов вручную можно будет в интерфейсе (этап 11):
--   Remotes.Event("Fuse"):FireServer({ "12", "15", "31" })  -- номера мобов в рюкзаке
-- Пока интерфейса нет, кнопка у машины выбирает сама: вид моба, которого
-- в рюкзаке больше всего, и из него три самых дешёвых — ценные мобы не пострадают.
--
--   FuseService.Fuse(player, ids)          -- синтез конкретных мобов
--   FuseService.FuseAuto(player, mobId)    -- выбрать самим (mobId необязателен)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Mobs = require(ReplicatedStorage.Shared.Config.Mobs)

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local PlotBuilder = require(script.Parent.PlotBuilder)

local F = GameConfig.Fuse

local FuseService = {}

local rng = Random.new()
local machines = {}   -- детали машин: к ним цепляется кнопка, по ним меряется расстояние
local lastFuseAt = {} -- [player] = когда последний раз синтезировал (защита от спама)

---------------------------------------------------------------------
-- Машина
---------------------------------------------------------------------

-- Насколько далеко от центра детали можно стоять: большую машину
-- можно трогать с её края, а не только из центра
local function reachOf(part)
	return F.MachineDistance + math.max(part.Size.X, part.Size.Z) / 2
end

local function nearMachine(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, part in ipairs(machines) do
		if part.Parent and (part.Position - root.Position).Magnitude <= reachOf(part) * 1.5 then
			return true
		end
	end
	return false
end

local function setupMachine(machine)
	local part = PlotBuilder.ResolvePart(machine)
	if not part then
		warn("[FuseService] В " .. machine:GetFullName() .. " нет ни одной детали")
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FusePrompt"
	prompt.ActionText = "Fuse"
	prompt.ObjectText = F.InputCount .. " same mobs -> 1"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = F.HoldTime
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = reachOf(part)
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		FuseService.FuseAuto(player)
	end)
	table.insert(machines, part)
end

---------------------------------------------------------------------
-- Синтез
---------------------------------------------------------------------

-- Синтез конкретных мобов из рюкзака. ids — номера мобов (строки).
-- Возвращает новый предмет и true, если моб стал тяжелее. Ничего не делает, если
-- что-то не так: всё проверяется ДО того, как у игрока что-то забрать.
function FuseService.Fuse(player, ids)
	local data = DataService.Get(player)
	if not data or type(ids) ~= "table" or #ids ~= F.InputCount then
		return nil
	end
	local now = os.clock()
	if now - (lastFuseAt[player] or 0) < F.Cooldown then
		return nil
	end

	local items, seen, mobId = {}, {}, nil
	for _, id in ipairs(ids) do
		if type(id) ~= "string" or seen[id] then
			return nil
		end
		seen[id] = true
		local item = data.Backpack.Mobs[id]
		if not item then
			return nil
		end
		if mobId and item.MobId ~= mobId then
			Remotes.Notify(player, "Can't fuse", "All " .. F.InputCount .. " mobs must be the same kind.")
			return nil
		end
		mobId = item.MobId
		table.insert(items, item)
	end
	if not Mobs[mobId] then
		return nil
	end
	lastFuseAt[player] = now

	local result, upgraded = Formulas.RollFuse(items, rng)
	local item = InventoryService.MakeItem(result.MobId, result.Rarity, result.Weight, result.Mutation)
	if not item then
		return nil
	end
	for _, id in ipairs(ids) do
		InventoryService.TakeMob(player, id)
	end
	InventoryService.AddMobItem(player, item)

	if upgraded then
		Remotes.Notify(player, "Lucky fuse!", InventoryService.Describe(item) .. " — heavier!")
	else
		Remotes.Notify(player, "Fused!", InventoryService.Describe(item))
	end
	return item, upgraded
end

-- Пока нет интерфейса: какие мобы пойдут в синтез. Вид — mobId, а если он
-- не указан — тот, которого в рюкзаке больше всего. Из него берём самых
-- дешёвых (по доходу), чтобы не потерять ценных мобов. nil — синтезировать нечего.
function FuseService.PickCheapest(player, mobId)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local groups = {}
	for id, item in pairs(data.Backpack.Mobs) do
		if Mobs[item.MobId] and (not mobId or item.MobId == mobId) then
			groups[item.MobId] = groups[item.MobId] or {}
			table.insert(groups[item.MobId], { Id = id, Value = Formulas.MobIncome(item) })
		end
	end

	local bestId
	for groupId, list in pairs(groups) do
		if #list >= F.InputCount then
			local bestCount = bestId and #groups[bestId] or 0
			if #list > bestCount or (#list == bestCount and groupId < bestId) then
				bestId = groupId
			end
		end
	end
	if not bestId then
		return nil
	end

	local list = groups[bestId]
	table.sort(list, function(a, b)
		return a.Value < b.Value
	end)
	local ids = {}
	for i = 1, F.InputCount do
		table.insert(ids, list[i].Id)
	end
	return ids
end

function FuseService.FuseAuto(player, mobId)
	local ids = FuseService.PickCheapest(player, mobId)
	if not ids then
		Remotes.Notify(player, "Nothing to fuse",
			"You need " .. F.InputCount .. " of the same mob in your backpack.")
		return nil
	end
	return FuseService.Fuse(player, ids)
end

function FuseService.Init()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant.Name == "FuseMachine" and (descendant:IsA("Model") or descendant:IsA("BasePart")) then
			setupMachine(descendant)
		end
	end
	if #machines == 0 then
		warn("[FuseService] В Workspace нет FuseMachine — синтез пока только командой !fuse."
			.. " Поставь деталь или модель с именем FuseMachine (например, в safe zone).")
	else
		print("[FuseService] Машин синтеза: " .. #machines)
	end

	-- Для интерфейса на этапе 11. Работает только рядом с машиной.
	Remotes.Event("Fuse").OnServerEvent:Connect(function(player, ids)
		if nearMachine(player) then
			FuseService.Fuse(player, ids)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastFuseAt[player] = nil
	end)
end

return FuseService
