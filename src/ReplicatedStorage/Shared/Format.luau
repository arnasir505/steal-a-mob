-- Format: красивый вывод чисел, веса и времени для интерфейса.
-- Format.Number(1234567) -> "1.23M"
-- Format.Weight(2500)    -> "2.5K kg"
-- Format.Time(3725)      -> "1h 2m"

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trimZeros(str)
	if string.find(str, "%.") then
		str = string.gsub(str, "0+$", "")
		str = string.gsub(str, "%.$", "")
	end
	return str
end

function Format.Number(n)
	if type(n) ~= "number" or n ~= n then
		return "0"
	end
	local sign = ""
	if n < 0 then
		sign = "-"
		n = -n
	end

	if n < 1000 then
		if n == math.floor(n) then
			return sign .. tostring(math.floor(n))
		end
		return sign .. trimZeros(string.format("%.1f", n))
	end

	local index = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local value = n / 10 ^ (index * 3)

	-- 999.999K должно стать 1M, а не 1000K
	if value >= 999.995 and index < #SUFFIXES - 1 then
		index = index + 1
		value = value / 1000
	end

	local str
	if value >= 100 then
		str = string.format("%.0f", value)
	elseif value >= 10 then
		str = string.format("%.1f", value)
	else
		str = string.format("%.2f", value)
	end
	return sign .. trimZeros(str) .. SUFFIXES[index + 1]
end

function Format.Weight(kg)
	if kg < 1000 then
		return trimZeros(string.format("%.2f", kg)) .. " kg"
	end
	return Format.Number(kg) .. " kg"
end

function Format.Time(seconds)
	seconds = math.max(0, math.floor(seconds))
	local d = math.floor(seconds / 86400)
	local h = math.floor(seconds % 86400 / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if d > 0 then
		return d .. "d " .. h .. "h"
	elseif h > 0 then
		return h .. "h " .. m .. "m"
	elseif m > 0 then
		return m .. "m " .. s .. "s"
	end
	return s .. "s"
end

return Format
