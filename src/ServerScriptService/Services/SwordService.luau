-- SwordService: мечи и PvP.
--
-- Правила:
--  * драться можно только в биомах: и тот, кто бьёт, и тот, кого бьют,
--    должны быть в биоме. В safe zone и на дорожках между биомами — нельзя;
--  * урона нет: удар роняет игрока (как толчок босса, RagdollService) и отталкивает.
--    Сила толчка — Knockback меча (Config/Items), время на земле — Combat.RagdollTime;
--  * лежачего бить нельзя — иначе вдвоём соперника можно не выпускать с земли;
--  * перезарядка удара — GameConfig.Combat.HitCooldown;
--  * пока игрок несёт яйцо, бить не может: когда он берёт яйцо, меч убирается из рук;
--  * от удара яйцо падает на землю — подобрать его может кто угодно.
--
-- Начальный меч (GameConfig.Combat.StarterSword) выдаётся всем при входе.
-- Остальные — за полный индекс биома (IndexService) и тестовой командой !sword:
--   SwordService.Grant(player, "WoodenSword")  -- выдать (и надеть, если он сильнее)
--   SwordService.Equip(player, "WoodenSword")  -- надеть свой меч ("" — убрать)
-- В руках всегда один меч — надетый (data.EquippedSword).
--
-- Модель меча: ReplicatedStorage.Assets.Swords.<ModelName> (ModelName из Config/Items):
--   * Tool с деталью Handle — берётся как есть (хват настраивается свойством Grip);
--   * или обычная модель — игра сама сделает из неё Tool. Ручкой станет деталь
--     Handle, а если её нет — PrimaryPart.
--   Все детали игра сама приварит к ручке. Внутрь можно положить звуки
--   с именами Swing (взмах) и Hit (попадание) — они будут играть.
--   Нет модели — выдаётся временный меч из кубиков.
--
-- Попадание считает только сервер. Клиент лишь сообщает "нажал" (Tool.Activated),
-- а сервер сам ищет ближайшего игрока перед атакующим. Ударить через всю карту
-- читер не сможет.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Items = require(ReplicatedStorage.Shared.Config.Items)
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local DataService = require(script.Parent.DataService)
local EggService = require(script.Parent.EggService)
local SpeedService = require(script.Parent.SpeedService)
local WorldService = require(script.Parent.WorldService)
local RagdollService = require(script.Parent.RagdollService)

local C = GameConfig.Combat

local SfxService = require(script.Parent.SfxService)

local SwordService = {}

local SWORD_ATTRIBUTE = "SwordId" -- так игра отличает свои мечи от других Tool

local lastHitAt = {}  -- [player] = когда последний раз бил
local lastHintAt = {} -- [player] = когда последний раз объясняли, почему нельзя бить

---------------------------------------------------------------------
-- Вспомогательное
---------------------------------------------------------------------

local function rootOf(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

-- Драться можно только внутри биома
local function inCombatZone(position)
	return not WorldService.IsInSafeZone(position) and WorldService.GetBiomeAt(position) ~= nil
end

-- Подсказка, но не чаще раза в HintCooldown секунд, чтобы не засыпать сообщениями
local function hint(player, title, text)
	local now = os.clock()
	if now - (lastHintAt[player] or 0) < C.HintCooldown then
		return
	end
	lastHintAt[player] = now
	Remotes.Notify(player, title, text)
end

-- Свой звук внутри меча (Swing / Hit), а если его нет — общий из Config/Sounds
local function playSound(tool, name)
	local sound = tool:FindFirstChild(name, true)
	if sound and sound:IsA("Sound") then
		sound:Play()
		return
	end
	SfxService.PlayAt(tool:FindFirstChild("Handle"), "Sword" .. name)
end

---------------------------------------------------------------------
-- Модель меча (Tool)
---------------------------------------------------------------------

local function makeBlock(name, size, position, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Временный меч, пока автор не сделал свою модель. Лезвие смотрит вверх
-- от ручки (+Y) — так Roblox держит Tool с хватом по умолчанию.
local function buildTempSword(config)
	local tool = Instance.new("Tool")
	local blade = config.Color or Rarities.Get(config.Rarity).Color
	makeBlock("Handle", Vector3.new(0.4, 1.2, 0.4), Vector3.new(0, 0, 0),
		Color3.fromRGB(90, 60, 35), Enum.Material.Wood, tool)
	makeBlock("Guard", Vector3.new(1.4, 0.25, 0.5), Vector3.new(0, 0.72, 0),
		Color3.fromRGB(70, 70, 75), Enum.Material.Metal, tool)
	makeBlock("Blade", Vector3.new(0.25, 3.5, 0.6), Vector3.new(0, 2.6, 0),
		blade, Enum.Material.SmoothPlastic, tool)
	return tool
end

-- Tool из модели автора (или его собственный Tool)
local function buildFromTemplate(template)
	if template:IsA("Tool") then
		return template:Clone()
	end
	local model = template:Clone()
	local handle = model:FindFirstChild("Handle", true)
	if not (handle and handle:IsA("BasePart")) then
		handle = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not handle then
		model:Destroy()
		return nil
	end
	local tool = Instance.new("Tool")
	for _, child in ipairs(model:GetChildren()) do
		child.Parent = tool
	end
	handle.Name = "Handle"
	handle.Parent = tool -- ручка должна лежать прямо в Tool
	model:Destroy()
	return tool
end

local function buildTool(swordId, config)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Swords")
	local template = folder and folder:FindFirstChild(config.ModelName or swordId)

	local tool = template and buildFromTemplate(template)
	if not tool then
		tool = buildTempSword(config)
	end
	local handle = tool:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		warn("[SwordService] У меча " .. swordId .. " нет детали Handle — меч не выдан")
		tool:Destroy()
		return nil
	end

	-- Все детали приварены к ручке и ничему не мешают
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			if part ~= handle then
				local weld = Instance.new("Weld")
				weld.Name = "SwordWeld"
				weld.Part0 = handle
				weld.Part1 = part
				weld.C0 = handle.CFrame:ToObjectSpace(part.CFrame)
				weld.Parent = part
			end
		end
	end

	tool.Name = config.DisplayName or swordId
	tool.ToolTip = "Push power " .. Format.Number(config.Knockback)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute(SWORD_ATTRIBUTE, swordId)
	return tool
end

---------------------------------------------------------------------
-- Удар
---------------------------------------------------------------------

-- Ближайший игрок перед атакующим. Позиции на сервере чуть отстают от того,
-- что видит игрок, и чем быстрее бегут, тем сильнее. Поэтому к дальности
-- добавляется запас: скорость обоих x HitLagSeconds.
local function findTarget(attacker, root)
	local look = root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 0.01 then
		return nil
	end
	forward = forward.Unit
	local minDot = math.cos(math.rad(C.HitAngle))

	local best, bestRoot, bestDistance
	for _, other in ipairs(Players:GetPlayers()) do
		local otherRoot = other ~= attacker and not RagdollService.IsRagdolled(other) and rootOf(other)
		if otherRoot and inCombatZone(otherRoot.Position) then
			local offset = otherRoot.Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local distance = flat.Magnitude
			local lag = (root.AssemblyLinearVelocity.Magnitude
				+ otherRoot.AssemblyLinearVelocity.Magnitude) * C.HitLagSeconds
			if distance <= C.HitRange + lag and math.abs(offset.Y) <= C.HitHeight then
				-- Вплотную попадаем при любом повороте, иначе цель должна быть впереди
				local inFront = distance < 2 or flat.Unit:Dot(forward) >= minDot
				if inFront and (not best or distance < bestDistance) then
					best, bestRoot, bestDistance = other, otherRoot, distance
				end
			end
		end
	end
	return best, bestRoot
end

local function hit(attacker, attackerRoot, victim, victimRoot, config, tool)
	playSound(tool, "Hit")
	-- Несёт яйцо — оно падает на землю, подобрать может кто угодно
	if EggService.GetCarried(victim) then
		EggService.Drop(victim, victimRoot.Position)
		Remotes.Notify(victim, "Egg knocked out!", attacker.DisplayName .. " hit you.")
	end
	-- Как у босса: сначала роняем, потом толкаем — игрок улетает уже обмякшим
	RagdollService.Ragdoll(victim, math.max(C.RagdollTime, SpeedService.KnockbackFlightTime(config.Knockback) + 0.3))
	SpeedService.Knockback(victim, attackerRoot.Position, config.Knockback)
end

-- Игрок нажал с мечом в руках
function SwordService.Swing(player, tool)
	local swordId = tool:GetAttribute(SWORD_ATTRIBUTE)
	local config = Items.Swords[swordId]
	local root = rootOf(player)
	-- Меч должен быть в руках у этого игрока
	if not config or not root or tool.Parent ~= player.Character then
		return
	end

	local now = os.clock()
	if now - (lastHitAt[player] or 0) < C.HitCooldown then
		return
	end
	if EggService.GetCarried(player) then
		hint(player, "Hands busy", "You can't attack while carrying an egg.")
		return
	end
	if not inCombatZone(root.Position) then
		hint(player, "No fighting here", "Swords work only inside biomes.")
		return
	end
	if RagdollService.IsRagdolled(player) then
		return
	end
	lastHitAt[player] = now

	-- Взмах. Стандартный скрипт персонажа Animate сам проигрывает анимацию удара,
	-- когда в Tool появляется значение toolanim = "Slash" (так сделан меч Roblox).
	local slash = Instance.new("StringValue")
	slash.Name = "toolanim"
	slash.Value = "Slash"
	slash.Parent = tool
	Debris:AddItem(slash, 1)
	playSound(tool, "Swing")

	local victim, victimRoot = findTarget(player, root)
	if victim then
		hit(player, root, victim, victimRoot, config, tool)
	end
end

---------------------------------------------------------------------
-- Выдача и надевание
---------------------------------------------------------------------

local function removeSwords(player)
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		for _, child in ipairs(container and container:GetChildren() or {}) do
			if child:IsA("Tool") and child:GetAttribute(SWORD_ATTRIBUTE) then
				child:Destroy()
			end
		end
	end
end

-- Кладёт надетый меч в рюкзак Roblox (панель снизу). Вызывается при каждом
-- появлении персонажа: после смерти Roblox рюкзак очищает.
local function giveSword(player)
	removeSwords(player)
	local data = DataService.Get(player)
	local swordId = data and data.EquippedSword
	local config = swordId and Items.Swords[swordId]
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not config or not backpack or not player.Character then
		return
	end
	local tool = buildTool(swordId, config)
	if not tool then
		return
	end
	tool.Activated:Connect(function()
		SwordService.Swing(player, tool)
	end)
	tool.Parent = backpack
end

function SwordService.Equip(player, swordId)
	local data = DataService.Get(player)
	if not data then
		return false
	end
	if swordId == "" or swordId == nil then
		data.EquippedSword = ""
	elseif type(swordId) == "string" and Items.Swords[swordId] and data.Swords[swordId] then
		data.EquippedSword = swordId
	else
		return false
	end
	player:SetAttribute("EquippedSword", data.EquippedSword)
	giveSword(player)
	return true
end

-- Выдать меч (награда индекса, тестовая команда). Если он сильнее надетого — надевается сам.
-- silent = true — без сообщения (у индекса своё сообщение про награду)
function SwordService.Grant(player, swordId, silent)
	local data = DataService.Get(player)
	local config = Items.Swords[swordId]
	if not data or not config then
		return false
	end
	if data.Swords[swordId] then
		return true
	end
	data.Swords[swordId] = true
	if not silent then
		Remotes.Notify(player, "New sword!", config.DisplayName)
	end

	local current = Items.Swords[data.EquippedSword]
	if not current or config.Knockback > current.Knockback then
		SwordService.Equip(player, swordId)
	end
	return true
end

-- Начальный меч: выдаётся, если его ещё нет, и надевается, если руки пусты.
-- Зовётся при каждом входе, поэтому меч получат и игроки со старыми сохранениями.
function SwordService.GiveStarter(player)
	local data = DataService.Get(player)
	local starterId = C.StarterSword
	if not data or not starterId or starterId == "" or data.Swords[starterId] then
		return
	end
	if not Items.Swords[starterId] then
		warn("[SwordService] Начальный меч " .. starterId .. " не найден в Config/Items")
		return
	end
	data.Swords[starterId] = true
	if data.EquippedSword == "" then
		data.EquippedSword = starterId
	end
end

function SwordService.Init()
	-- Для интерфейса на этапе 11: сервер проверит, что меч свой
	Remotes.Event("EquipSword").OnServerEvent:Connect(function(player, swordId)
		SwordService.Equip(player, swordId)
	end)

	DataService.ProfileLoaded:Connect(function(player, data)
		-- Меч, которого больше нет в конфиге или у игрока, не надеваем
		if data.EquippedSword ~= "" and not (Items.Swords[data.EquippedSword] and data.Swords[data.EquippedSword]) then
			data.EquippedSword = ""
		end
		SwordService.GiveStarter(player)
		player:SetAttribute("EquippedSword", data.EquippedSword)
		giveSword(player)
		player.CharacterAdded:Connect(function()
			task.defer(giveSword, player)
		end)
	end)

	-- Взял яйцо — меч убирается из рук (бить с яйцом всё равно нельзя)
	EggService.EggTaken:Connect(function(player)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastHitAt[player] = nil
		lastHintAt[player] = nil
	end)
end

return SwordService
