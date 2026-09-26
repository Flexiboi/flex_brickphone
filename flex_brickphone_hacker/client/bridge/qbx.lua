if GetResourceState('qbx_core') ~= 'started' then return end

function GetPlayerData()
    return exports.qbx_core:GetPlayerData()
end

function onPlayerLoaded()
    return "QBCore:Client:OnPlayerLoaded"
end

function onPlayerUnLoaded()
    return "QBCore:Client:OnPlayerUnload"
end

local function IsPedFreeMode()
	local pedModel = GetEntityModel(cache.ped)

	if pedModel == `mp_m_freemode_01` then
		return true
	elseif pedModel == GetHashKey("mp_f_freemode_01") then
		return true
	else
		return false
	end
end