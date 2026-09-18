-- Remotes: общая папка ReplicatedStorage.Remotes для связи клиента и сервера.
--
-- Сервер:  local ev = Remotes.Event("Notify")     -- создаст, если нет
-- Клиент:  local ev = Remotes.Event("Notify")     -- дождётся, пока сервер создаст
--
-- Напоминание: клиент только ПРОСИТ, сервер всё проверяет сам.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local IS_SERVER = RunService:IsServer()

local folder
if IS_SERVER then
	folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local function get(className, name)
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing
	end
	if not IS_SERVER then
		return folder:WaitForChild(name)
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = folder
	return remote
end

function Remotes.Event(name)
	return get("RemoteEvent", name)
end

function Remotes.Function(name)
	return get("RemoteFunction", name)
end

-- Короткое сообщение игроку (пока это всплывашка Roblox, на этапе 11 заменим своим UI)
function Remotes.Notify(player, title, text)
	if not IS_SERVER then
		return
	end
	Remotes.Event("Notify"):FireClient(player, title, text)
end

-- То же самое, но всем игрокам сервера (редкое яйцо, редкая мутация)
function Remotes.NotifyAll(title, text)
	if not IS_SERVER then
		return
	end
	Remotes.Event("Notify"):FireAllClients(title, text)
end

return Remotes
