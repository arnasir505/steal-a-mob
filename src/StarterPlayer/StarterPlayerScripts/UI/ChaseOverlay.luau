-- ChaseOverlay: погоня и переноска яйца.
--  * за игроком гонится босс (атрибут ChasedBy от BossService) — плашка "RUN!!"
--    сверху и красная рамка по краям экрана;
--  * игрок несёт яйцо (атрибут CarryRarity) — кнопка Drop внизу экрана.
--    Клавиша G делает то же самое (EggDrop.client).
-- Кнопка Drop стоит внизу, над панелью предметов, а не в центре экрана —
-- правило интерфейса из CLAUDE.md.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Kit = require(script.Parent.Kit)

local ChaseOverlay = {}

-- Красная рамка: четыре полосы по краям, прозрачные к центру.
-- Свой слой (ScreenGui): на весь экран, вместе с местом под верхней панелью Roblox
-- (IgnoreGuiInset), и ПОД кнопками интерфейса (DisplayOrder меньше, чем у GameUI).
local function buildVignette(player)
	local layer = Kit.new("ScreenGui", {
		Name = "ChaseVignette",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		DisplayOrder = 0,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local holder = Kit.new("Frame", {
		Name = "Vignette", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		Visible = false, Active = false, Parent = layer,
	})
	local edges = {
		{ Size = UDim2.fromScale(1, 0.22), Position = UDim2.fromScale(0, 0), Rotation = 90 },
		{ Size = UDim2.fromScale(1, 0.22), Position = UDim2.fromScale(0, 0.78), Rotation = -90 },
		{ Size = UDim2.fromScale(0.16, 1), Position = UDim2.fromScale(0, 0), Rotation = 0 },
		{ Size = UDim2.fromScale(0.16, 1), Position = UDim2.fromScale(0.84, 0), Rotation = 180 },
	}
	for _, edge in ipairs(edges) do
		local frame = Kit.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(220, 20, 40), Size = edge.Size, Position = edge.Position,
			Active = false, Parent = holder,
		})
		Kit.new("UIGradient", {
			Transparency = NumberSequence.new(0.35, 1),
			Rotation = edge.Rotation,
			Parent = frame,
		})
	end
	return holder
end

function ChaseOverlay.Build(screen, player)
	local vignette = buildVignette(player)

	-- Плашка RUN!! сверху по центру
	local banner = Kit.new("Frame", {
		Name = "RunBanner", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(420, 100), Visible = false,
		Active = false, Parent = screen,
	})
	Kit.AutoScale(banner)
	local plate = Kit.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(90, 0, 0), Size = UDim2.fromScale(1, 1), Active = false, Parent = banner,
	})
	Kit.Corner(plate, 22)
	Kit.Stroke(plate, 4, Color3.fromRGB(230, 30, 30), true)
	Kit.Text({ Text = "RUN!!", Size = UDim2.fromScale(0.8, 0.75), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), StrokeThickness = 4, Parent = plate })
	local chaser = Kit.Text({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0.5, 0, 1, 8), AnchorPoint = Vector2.new(0.5, 0), Parent = banner })
	local pulse = Kit.new("UIScale", { Parent = plate })

	-- Кнопка Drop внизу, над панелью предметов Roblox
	local dropHolder = Kit.new("Frame", {
		Name = "Drop", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -100), Size = UDim2.fromOffset(280, 80), Visible = false,
		Active = false, Parent = screen,
	})
	Kit.AutoScale(dropHolder)
	Kit.Button({
		Text = "Drop", Image = "icon_drop", Fallback = "🗑", Color = Kit.Colors.Red,
		Size = UDim2.fromOffset(280, 80), Parent = dropHolder,
		OnClick = function()
			Remotes.Event("DropEgg"):FireServer()
		end,
	})

	local function refresh()
		local chasedBy = player:GetAttribute("ChasedBy")
		banner.Visible = chasedBy ~= nil
		vignette.Visible = chasedBy ~= nil
		chaser.Text = chasedBy and (chasedBy .. " is chasing you!") or ""
		dropHolder.Visible = (player:GetAttribute("CarryRarity") or "") ~= ""
	end
	player:GetAttributeChangedSignal("ChasedBy"):Connect(refresh)
	player:GetAttributeChangedSignal("CarryRarity"):Connect(refresh)
	refresh()

	-- Плашка RUN!! пульсирует
	RunService.RenderStepped:Connect(function()
		if banner.Visible then
			pulse.Scale = 1 + 0.06 * math.sin(os.clock() * 8)
		end
	end)
end

return ChaseOverlay
