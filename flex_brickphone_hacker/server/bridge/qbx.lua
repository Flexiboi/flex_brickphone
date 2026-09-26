if GetResourceState(Config.CoreName.qbx) ~= 'started' then return end

function GetPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

function GetPlayerByCitizenId(identifier)
    return exports.qbx_core:GetPlayerByCitizenId(identifier)
end

function RemoveItem(src, item, amount, info, slot)
    return exports.ox_inventory:RemoveItem(src, item, amount, info, slot or nil)
end

function AddItem(src, item, amount, info, slot)
    return exports.ox_inventory:AddItem(src, item, amount or 1, info or {}, slot or nil)
end

function HasInvGotItem(inv, search, item, metadata, amount)
    if type(amount) == "boolean" then return end
    if amount == 0 then return false end
    if exports.ox_inventory:Search(inv, search, item) >= amount then
        return true
    else
        return false
    end
end

function GetInvItems(inv)
    return exports.ox_inventory:GetInventoryItems(inv)
end

function GetItemBySlot(src, slot)
    local Player = exports.qbx_core:GetPlayer(src)
    return Player.Functions.GetItemBySlot(slot)
end

function AddMoney(src, AddType, amount, reason)
    exports.qbx_core:AddMoney(src, AddType, amount, reason or '')
end

function RegisterStash(id, slots, maxWeight)
    exports.ox_inventory:RegisterStash(id, id, slots, maxWeight)
end

function ClearStash(id)
    exports.ox_inventory:ClearInventory(id, 'false')
end

function SetJob(src, job, grade)
    local Player = exports.qbx_core:GetPlayer(src)
    exports.qbx_core:SetJob(src, job, grade)
end

function GetJobs()
    return exports.qbx_core:GetJobs()
end

function GetProfessions(src)
    local Player = exports.qbx_core:GetPlayer(src)
    local result = MySQL.single.await('SELECT '..Config.sql.column..' FROM '..Config.sql.table..' WHERE citizenid = ?', { Player.PlayerData.citizenid })
    if result and result[Config.sql.column] then
        return json.decode(result[Config.sql.column]) or {}
    end
    return {}
end

function SetProfessions(src, professions)
    local Player = exports.qbx_core:GetPlayer(src)
    return MySQL.update.await('UPDATE '..Config.sql.table..' SET '..Config.sql.column..' = ? WHERE citizenid = ?', { json.encode(professions), Player.PlayerData.citizenid })
end