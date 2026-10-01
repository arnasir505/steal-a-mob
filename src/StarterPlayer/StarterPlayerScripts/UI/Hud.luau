-- Hud: то, что всегда на экране.
--  * слева: кнопки Shop и Index;
--  * слева снизу: скорость (с "+" — магазин скорости), деньги и доход в секунду;
--  * справа: квадратные кнопки (трейлы);
--  * справа снизу: таймеры — до новых яиц и до ночи/дня.
-- На телефоне скорость/деньги и таймеры уезжают наверх: внизу у телефона
-- джойстик и кнопка прыжка.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Format = require(ReplicatedStorage.Shared.Format)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Kit = require(script.Parent.Kit)

local Hud = {}

local isPhone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Группа элементов в углу экрана со своим масштабом
local function corner(screen, name, anchor, position, size)
	local frame = Kit.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = anchor,
		Position = position,
		Size = size,
		Active = false,
		Parent = screen,
	})
	Kit.AutoScale(frame)
	return frame
end

local function list(parent, padding, horizontal, align)
	return Kit.new("UIListLayout", {
		Padding = UDim.new(0, padding),
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

---------------------------------------------------------------------
-- Скорость и деньги
---------------------------------------------------------------------

local function buildStats(screen, player, actions)
	local stats = corner(screen, "Stats",
		isPhone and Vector2.new(0, 0) or Vector2.new(0, 1),
		isPhone and UDim2.new(0, 12, 0, 64) or UDim2.new(0, 16, 1, -16),
		UDim2.fromOffset(460, 230))
	list(stats, 2)

	-- Скорость: кроссовок, "+" (магазин скорости), число
	local speedRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(460, 84), LayoutOrder = 1, Active = false, Parent = stats })
	Kit.Icon({ Image = "icon_speed", Fallback = "👟", Size = UDim2.fromOffset(84, 84), Parent = speedRow })
	Kit.Button({
		Name = "SpeedPlus", Image = "icon_plus", Fallback = "+", Color = Kit.Colors.Gold,
		Size = UDim2.fromOffset(38, 38), Position = UDim2.fromOffset(52, 48), Studs = false,
		BorderThickness = 3, Corner = 6, ZIndex = 3, Parent = speedRow,
		OnClick = function()
			actions.OpenShop("Speed")
		end,
	})
	local speedText = Kit.Text({
		Size = UDim2.fromOffset(360, 70), Position = UDim2.new(0, 98, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		AlignX = Enum.TextXAlignment.Left, StrokeThickness = 4, Parent = speedRow,
	})

	-- Деньги и доход
	local moneyRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(460, 84), LayoutOrder = 2, Active = false, Parent = stats })
	Kit.Icon({ Image = "icon_money", Fallback = "💵", Size = UDim2.fromOffset(84, 84), Parent = moneyRow })
	local moneyText = Kit.Text({
		Color = Kit.Colors.Money, Size = UDim2.fromOffset(360, 70), Position = UDim2.new(0, 98, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5), AlignX = Enum.TextXAlignment.Left, StrokeThickness = 4, Parent = moneyRow,
	})
	local incomeText = Kit.Text({
		Color = Kit.Colors.Money, Size = UDim2.fromOffset(360, 34),
		AlignX = Enum.TextXAlignment.Left, Parent = stats,
	})
	incomeText.LayoutOrder = 3 -- под деньгами

	local function refresh()
		speedText.Text = Format.Number(player:GetAttribute("Speed") or 1)
		moneyText.Text = "$" .. Format.Number(player:GetAttribute("Money") or 0)
		incomeText.Text = "      +$" .. Format.Number(player:GetAttribute("IncomePerSecond") or 0) .. "/s"
	end
	for _, name in ipairs({ "Speed", "Money", "IncomePerSecond" }) do
		player:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()
end

---------------------------------------------------------------------
-- Таймеры
---------------------------------------------------------------------

-- Сколько секунд до смены дня и ночи и что наступит
local function dayNightInfo()
	local config = GameConfig.DayNight
	local clock = Lighting.ClockTime
	local isNight = clock < config.SunriseHour or clock >= config.SunsetHour
	local hoursLeft = isNight and (config.SunriseHour - clock) % 24 or (config.SunsetHour - clock)
	local hoursPerSecond = 24 / (config.CycleMinutes * 60)
	return isNight and "Day" or "Night", hoursLeft / hoursPerSecond
end

local function timerRow(parent, image, fallback, order)
	local row = Kit.new("Frame", {
		BackgroundColor3 = Kit.Colors.Black,
		BackgroundTransparency = 0.5,
		Size = UDim2.fromOffset(440, 72),
		LayoutOrder = order,
		Active = false,
		Parent = parent,
	})
	Kit.Corner(row, 36)
	Kit.new("UIGradient", {
		Transparency = NumberSequence.new(1, 0),
		Parent = row,
	})
	Kit.Icon({ Image = image, Fallback = fallback, Size = UDim2.fromOffset(72, 72), Position = UDim2.fromOffset(8, 0), Parent = row })
	local text = Kit.Text({
		Size = UDim2.new(1, -96, 0.75, 0), Position = UDim2.new(0, 88, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		AlignX = Enum.TextXAlignment.Left, Parent = row,
	})
	return text
end

local function buildTimers(screen)
	local timers = corner(screen, "Timers",
		isPhone and Vector2.new(1, 0) or Vector2.new(1, 1),
		isPhone and UDim2.new(1, -12, 0, 12) or UDim2.new(1, -16, 1, -16),
		UDim2.fromOffset(440, 156))
	list(timers, 10, false, Enum.HorizontalAlignment.Right)

	local roundText = timerRow(timers, "icon_timer", "⏳", 1)
	local nightText = timerRow(timers, "icon_night", "🌙", 2)
	nightText.Parent.Visible = GameConfig.DayNight.Enabled

	local elapsed = 0
	RunService.Heartbeat:Connect(function(delta)
		elapsed = elapsed + delta
		if elapsed < 0.25 then
			return
		end
		elapsed = 0

		if ReplicatedStorage:GetAttribute("RoundResetting") then
			roundText.Text = "New eggs..."
		else
			local endsAt = ReplicatedStorage:GetAttribute("RoundEndsAt") or 0
			local left = endsAt - workspace:GetServerTimeNow()
			roundText.Text = "New eggs in " .. Format.Time(left)
		end

		if GameConfig.DayNight.Enabled then
			local upcoming, seconds = dayNightInfo()
			nightText.Text = upcoming .. " in " .. Format.Time(seconds)
		end
	end)
end

---------------------------------------------------------------------
-- Кнопки
---------------------------------------------------------------------

local function buildMenuButtons(screen, actions)
	local left = corner(screen, "Menu", Vector2.new(0, 0.5), UDim2.new(0, 16, 0.5, 0), UDim2.fromOffset(240, 190))
	list(left, 14)
	Kit.Button({
		Name = "Shop", Text = "Shop", Image = "icon_shop", Fallback = "🛒", Color = Kit.Colors.Green,
		Size = UDim2.fromOffset(230, 80), LayoutOrder = 1, Parent = left,
		OnClick = function()
			actions.OpenShop("Featured", true)
		end,
	})
	Kit.Button({
		Name = "Index", Text = "Index", Image = "icon_index", Fallback = "📘", Color = Kit.Colors.Blue,
		Size = UDim2.fromOffset(230, 80), LayoutOrder = 2, Parent = left,
		OnClick = actions.ToggleIndex,
	})

	local right = corner(screen, "SideButtons", Vector2.new(1, 0.5), UDim2.new(1, -16, 0.5, 0), UDim2.fromOffset(100, 340))
	list(right, 16, false, Enum.HorizontalAlignment.Right)
	local trails = Kit.Button({
		Name = "Trails", Image = "trail_runner", Fallback = "✨", Color = Kit.Colors.Purple,
		Size = UDim2.fromOffset(96, 96), LayoutOrder = 1, Parent = right,
		OnClick = function()
			actions.OpenShop("Trails")
		end,
	})
	Kit.Text({
		Text = "Trails", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0.5, 0, 1, -4),
		AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 3, Parent = trails,
	})
end

function Hud.Build(screen, player, actions)
	buildMenuButtons(screen, actions)
	buildStats(screen, player, actions)
	buildTimers(screen)
end

return Hud
