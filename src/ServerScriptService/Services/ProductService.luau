-- ProductService: покупки за Robux — Developer Products и окна покупки геймпассов.
--
-- Главное правило: оплаченное не теряется и не выдаётся дважды.
-- Roblox вызывает ProcessReceipt на каждую покупку продукта и повторяет вызов,
-- пока мы не ответим PurchaseGranted — даже на другом сервере или на следующий день.
-- Поэтому:
--   1. Игрока нет на этом сервере или его данные ещё не загрузились —
--      отвечаем NotProcessedYet: Roblox повторит, когда он зайдёт.
--   2. Номер покупки (PurchaseId) уже записан в data.ProcessedReceipts —
--      товар уже выдан, второй раз не выдаём.
--   3. Иначе выдаём товар и сразу записываем номер покупки в данные игрока.
--   4. Подтверждаем (PurchaseGranted) только ПОСЛЕ того, как данные сохранились.
--      Не сохранились — NotProcessedYet: Roblox повторит, а шаг 2 не даст выдать дважды.
--
-- Товары (Config/Products):
--   Speed        — +Amount скорости
--   MoneyMinutes — доход игрока за Minutes минут, но не меньше MinMoney
--   InstantHatch — мгновенное вылупление одного яйца. Покупка даёт "заряд"
--                  (data.InstantHatches). Он тратится на яйцо, у которого нажали
--                  Hatch Now; если такого яйца уже нет — на яйцо, которому дольше всех
--                  ждать; если яиц нет вовсе — хранится до следующей кнопки Hatch Now.
--
-- Геймпассы проверяет PassService, здесь только открываем окно покупки:
--   ProductService.PromptProduct(player, "Money30Min")
--   ProductService.PromptPass(player, "X2Money")
--   ProductService.RequestInstantHatch(player, itemId) -- кнопка Hatch Now у яйца
-- Для интерфейса (этап 11): Remotes.Event("BuyProduct"), "BuyPass", "InstantHatch".

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Products = require(ReplicatedStorage.Shared.Config.Products)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PassService = require(script.Parent.PassService)
local PlotService = require(script.Parent.PlotService)

local C = GameConfig.Purchases

local SfxService = require(script.Parent.SfxService)

local ProductService = {}

local pendingHatch = {} -- [player] = номер яйца, у которого нажали Hatch Now и открыли покупку

---------------------------------------------------------------------
-- Мгновенное вылупление
---------------------------------------------------------------------

-- Яйцо на участке, которое можно вылупить: сначала выбранное, иначе то,
-- которому ждать дольше всех (так заряд приносит больше всего пользы)
local function pickEgg(data, wantedId)
	local wanted = wantedId and data.Plot.Items[wantedId]
	if wanted and wanted.Type == "Egg" then
		return wantedId
	end
	local bestId, bestEnd
	for id, placed in pairs(data.Plot.Items) do
		if placed.Type == "Egg" and (not bestEnd or (placed.HatchEndsAt or 0) > bestEnd) then
			bestId, bestEnd = id, placed.HatchEndsAt or 0
		end
	end
	return bestId
end

-- Тратит один заряд на яйцо. true — яйцо вылупилось.
local function spendHatch(player, data, wantedId)
	if (data.InstantHatches or 0) <= 0 then
		return false
	end
	local eggId = pickEgg(data, wantedId)
	if not eggId or not PlotService.HatchNow(player, eggId) then
		return false
	end
	data.InstantHatches = data.InstantHatches - 1
	player:SetAttribute("InstantHatches", data.InstantHatches)
	return true
end

-- Кнопка Hatch Now у яйца: есть заряд — тратим, нет — открываем покупку
function ProductService.RequestInstantHatch(player, itemId)
	local data = DataService.Get(player)
	local placed = data and type(itemId) == "string" and data.Plot.Items[itemId]
	if not placed or placed.Type ~= "Egg" then
		return false
	end
	if spendHatch(player, data, itemId) then
		return true
	end
	pendingHatch[player] = itemId
	return ProductService.PromptProduct(player, "InstantHatch")
end

---------------------------------------------------------------------
-- Выдача товаров
---------------------------------------------------------------------

-- Выдаёт товар. Возвращает текст для сообщения игроку.
local function grantProduct(player, data, product)
	if product.Type == "Speed" then
		EconomyService.AddSpeed(player, product.Amount)
		return "+" .. Format.Number(product.Amount) .. " speed"
	elseif product.Type == "MoneyMinutes" then
		local amount = Formulas.MoneyPack(EconomyService.GetIncomePerSecond(player), product.Minutes, product.MinMoney)
		EconomyService.AddMoney(player, amount)
		return "+$" .. Format.Number(amount)
	elseif product.Type == "InstantHatch" then
		data.InstantHatches = (data.InstantHatches or 0) + 1
		player:SetAttribute("InstantHatches", data.InstantHatches)
		local wanted = pendingHatch[player]
		pendingHatch[player] = nil
		if spendHatch(player, data, wanted) then
			return "Egg hatched instantly!"
		end
		return "Instant hatch saved — press Hatch Now on an egg"
	end
	error("неизвестный тип товара " .. tostring(product.Type))
end

-- Старые номера покупок больше не нужны: Roblox повторяет только свежие
local function pruneReceipts(data)
	local oldest = os.time() - C.ReceiptKeepDays * 24 * 60 * 60
	for purchaseId, grantedAt in pairs(data.ProcessedReceipts) do
		if type(grantedAt) ~= "number" or grantedAt < oldest then
			data.ProcessedReceipts[purchaseId] = nil
		end
	end
end

-- Одна покупка: выдать ровно один раз и сохранить. Возвращает решение для Roblox.
local function processPurchase(player, productName, purchaseId, robuxSpent)
	local data = DataService.WaitForData(player, C.WaitForDataSeconds)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local key = tostring(purchaseId)
	if not data.ProcessedReceipts[key] then
		local product = Products.DevProducts[productName]
		local ok, result = pcall(grantProduct, player, data, product)
		if not ok then
			warn("[ProductService] Не удалось выдать " .. productName .. " игроку " .. player.Name .. ": " .. tostring(result))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		data.ProcessedReceipts[key] = os.time()
		data.Stats.RobuxSpent = (data.Stats.RobuxSpent or 0) + (robuxSpent or 0)
		pruneReceipts(data)
		SfxService.PlayFor(player, "PurchaseSuccess")
		Remotes.Notify(player, "Thank you!", result)
	end

	-- Подтверждаем только сохранённое: иначе сервер может упасть, и покупка пропадёт
	if not DataService.SaveNow(player) then
		warn("[ProductService] Покупка " .. key .. " выдана, но не сохранилась — Roblox повторит позже")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function productNameById(productId)
	for name, product in pairs(Products.DevProducts) do
		if product.Id ~= 0 and product.Id == productId then
			return name
		end
	end
	return nil
end

-- Roblox вызывает это на каждую покупку продукта (и повторяет, пока не подтвердим)
local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- выдадим, когда зайдёт
	end
	local productName = productNameById(receipt.ProductId)
	if not productName then
		warn("[ProductService] Куплен неизвестный продукт " .. tostring(receipt.ProductId)
			.. " — впиши его Id в Config/Products")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return processPurchase(player, productName, receipt.PurchaseId, receipt.CurrencySpent)
end

---------------------------------------------------------------------
-- Окна покупки
---------------------------------------------------------------------

function ProductService.PromptProduct(player, productName)
	local product = Products.DevProducts[productName]
	if not product then
		return false
	end
	if product.Id == 0 then
		Remotes.Notify(player, "Not available", "This item is not set up yet.")
		warn("[ProductService] У продукта " .. productName .. " нет Id — создай его на сайте Roblox"
			.. " и впиши Id в Config/Products (в Studio проверить без Id: !grant " .. productName .. ")")
		return false
	end
	MarketplaceService:PromptProductPurchase(player, product.Id)
	return true
end

function ProductService.PromptPass(player, passName)
	local pass = Products.GamePasses[passName]
	if not pass then
		return false
	end
	if PassService.Has(player, passName) then
		Remotes.Notify(player, "Already yours", "You already own this pass.")
		return false
	end
	if pass.Id == 0 then
		Remotes.Notify(player, "Not available", "This pass is not set up yet.")
		warn("[ProductService] У геймпасса " .. passName .. " нет Id — создай его на сайте Roblox"
			.. " и впиши Id в Config/Products (в Studio проверить без Id: !pass " .. passName .. ")")
		return false
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.Id)
	return true
end

-- Только для тестов в Studio: выдать продукт так, будто его купили.
-- Проходит тот же путь, что и настоящая покупка (включая сохранение).
function ProductService.GrantForTesting(player, productName)
	if not Products.DevProducts[productName] then
		return nil
	end
	return processPurchase(player, productName, "test-" .. player.UserId .. "-" .. os.clock(), 0)
end

function ProductService.Init()
	MarketplaceService.ProcessReceipt = processReceipt

	-- Для интерфейса на этапе 11
	Remotes.Event("BuyProduct").OnServerEvent:Connect(function(player, productName)
		-- InstantHatch из магазина — заряд "впрок": тратится на яйцо, которому дольше всех ждать,
		-- а если яиц нет — копится до кнопки Hatch Now
		if type(productName) == "string" then
			ProductService.PromptProduct(player, productName)
		end
	end)
	Remotes.Event("BuyPass").OnServerEvent:Connect(function(player, passName)
		if type(passName) == "string" then
			ProductService.PromptPass(player, passName)
		end
	end)
	Remotes.Event("InstantHatch").OnServerEvent:Connect(function(player, itemId)
		ProductService.RequestInstantHatch(player, itemId)
	end)

	-- Кнопка Hatch Now у яйца на участке
	PlotService.InstantHatchRequested:Connect(function(player, itemId)
		ProductService.RequestInstantHatch(player, itemId)
	end)

	DataService.ProfileLoaded:Connect(function(player, data)
		player:SetAttribute("InstantHatches", data.InstantHatches or 0)
	end)
	Players.PlayerRemoving:Connect(function(player)
		pendingHatch[player] = nil
	end)
end

return ProductService
