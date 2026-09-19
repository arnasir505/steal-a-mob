-- Main: точка входа сервера. Запускает все сервисы в правильном порядке.
-- Новые сервисы (биомы, боссы, PvP...) будем добавлять сюда.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService:WaitForChild("Services")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(Services.DataService)
local PassService = require(Services.PassService)
local EconomyService = require(Services.EconomyService)
local InventoryService = require(Services.InventoryService)
local TrailService = require(Services.TrailService)
local SpeedService = require(Services.SpeedService)
local PlotService = require(Services.PlotService)

-- Ремоуты создаём заранее, чтобы клиент их дождался
Remotes.Event("Notify")

-- 1. Сначала все сервисы подписываются на события
PassService.Init()
EconomyService.Init()
InventoryService.Init()
TrailService.Init()
SpeedService.Init()
PlotService.Init()

-- 2. DataService запускаем последним, чтобы никто не пропустил загрузку игрока
DataService.Start()

print("[Main] Server started")
