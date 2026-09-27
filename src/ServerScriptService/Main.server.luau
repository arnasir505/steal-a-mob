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
local WorldService = require(Services.WorldService)
local PlotService = require(Services.PlotService)
local EggService = require(Services.EggService)
local RagdollService = require(Services.RagdollService)
local BossService = require(Services.BossService)
local SwordService = require(Services.SwordService)
local IndexService = require(Services.IndexService)
local FuseService = require(Services.FuseService)
local FriendsService = require(Services.FriendsService)
local DailyService = require(Services.DailyService)
local LeaderboardService = require(Services.LeaderboardService)
local RoundService = require(Services.RoundService)
local TimeChangeService = require(Services.TimeChangeService)

-- Ремоуты создаём заранее, чтобы клиент их дождался
Remotes.Event("Notify")

-- 1. Сначала все сервисы подписываются на события
PassService.Init()
EconomyService.Init()
InventoryService.Init()
TrailService.Init()
SpeedService.Init()

-- Карта: safe zone и биомы. Должна читаться до участков и яиц.
WorldService.Init()
PlotService.Init()
EggService.Init()
RagdollService.Init()
BossService.Init() -- до раундов: иначе яйца могут упасть на модель босса
SwordService.Init()
IndexService.Init()
FuseService.Init()
FriendsService.Init()
DailyService.Init()
LeaderboardService.Init()
RoundService.Init()
TimeChangeService.Init()

-- 2. DataService запускаем последним, чтобы никто не пропустил загрузку игрока
DataService.Start()

print("[Main] Server started")
