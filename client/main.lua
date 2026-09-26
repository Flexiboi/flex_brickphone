local currentWaypointBlip = nil
local pickupOrders = {}
local refreshPickupWaypoint
local phoneOpen = false
local phoneProp = nil
local phoneAnimDict = 'cellphone@'

local function stopPhoneAnimation()
    local ped = cache.ped

    if DoesEntityExist(ped) then
        StopAnimTask(ped, phoneAnimDict, 'cellphone_text_read_base', 2.0)
        StopAnimTask(ped, phoneAnimDict, 'cellphone_text_out', 2.0)
    end

    if phoneProp and DoesEntityExist(phoneProp) then
        SetEntityAsMissionEntity(phoneProp, true, true)
        DeleteEntity(phoneProp)
    end

    phoneProp = nil
end
exports('stopPhoneAnimation', stopPhoneAnimation)

local function startPhoneAnimation()
    if phoneProp and DoesEntityExist(phoneProp) then return end

    local ped = cache.ped
    if not DoesEntityExist(ped) then return end

    lib.requestAnimDict(phoneAnimDict, 5000)
    local model = lib.requestModel('prop_prologue_phone', 5000)

    if not model then return end

    lib.playAnim(ped, phoneAnimDict, 'cellphone_text_read_base', 3.0, 3.0, -1, 49, 0.0, false, false, false)

    phoneProp = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
    SetEntityAsMissionEntity(phoneProp, true, true)

    local bone = GetPedBoneIndex(ped, 28422)
    AttachEntityToEntity( phoneProp, ped, bone, 0.0, -0.005, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true )

    SetModelAsNoLongerNeeded(model)
end
exports('startPhoneAnimation', startPhoneAnimation)

local function cleanupPickup(orderId)
    local pickup = pickupOrders[orderId]
    if not pickup then return end

    if pickup.target then
        exports.ox_target:removeLocalEntity(pickup.target)
        pickup.target = nil
    end

    if pickup.ped and DoesEntityExist(pickup.ped) then
        SetEntityAsMissionEntity(pickup.ped, true, true)
        DeleteEntity(pickup.ped)
    end

    pickup.ped = nil

    if pickup.zone then
        pickup.zone:remove()
        pickup.zone = nil
    end

    pickupOrders[orderId] = nil
    refreshPickupWaypoint()
end

local function cleanupPickups()
    local orderIds = {}

    for orderId in pairs(pickupOrders) do
        orderIds[#orderIds + 1] = orderId
    end

    for i = 1, #orderIds do
        cleanupPickup(orderIds[i])
    end
end

local function cleanupWaypoint()
    if currentWaypointBlip and DoesBlipExist(currentWaypointBlip) then
        RemoveBlip(currentWaypointBlip)
    end

    currentWaypointBlip = nil
end
exports('cleanupWaypoint', cleanupWaypoint)

refreshPickupWaypoint = function()
    cleanupWaypoint()

    for _, pickup in pairs(pickupOrders) do
        if pickup.ready and pickup.coords then
            local coords = pickup.coords
            local blip = AddBlipForCoord(coords.x, coords.y, coords.z + 1.0)
            SetBlipSprite(blip, 1)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, 1.0)
            SetBlipColour(blip, 38)
            SetBlipRoute(blip, true)
            SetBlipAsShortRange(blip, false)

            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(locale('crafter.pickup_waypoint'))
            EndTextCommandSetBlipName(blip)

            currentWaypointBlip = blip
            return
        end
    end
end

local function cleanupClient()
    phoneOpen = false
    stopPhoneAnimation()
    cleanupPickups()
    cleanupWaypoint()

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'setVisible', visible = false })
    SendNUIMessage({ action = 'clearData', clearContacts = true })
end

local function setPhoneVisible(visible)
    phoneOpen = visible
    SetNuiFocus(visible, visible)

    SendNUIMessage({
        action = 'setVisible',
        visible = visible
    })

    if visible then
        startPhoneAnimation()
    else
        stopPhoneAnimation()
        SendNUIMessage({ action = 'clearData' })
    end
end

local function loadModel(model)
    local modelHash = type(model) == 'number' and model or joaat(model)

    if not IsModelInCdimage(modelHash) or not IsModelValid(modelHash) then
        return nil
    end

    RequestModel(modelHash)

    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(modelHash) do
        if GetGameTimer() >= timeout then return nil end
        Wait(50)
    end

    return modelHash
end

local function spawnPickupPed(orderId)
    local pickup = pickupOrders[orderId]
    if not pickup or pickup.ped then return end

    local model = loadModel(Config.PickupPed.model)
    if not model then
        lib.notify({
            title = locale('error.cannot_craft'),
            type = 'error'
        })
        return
    end

    local coords = pickup.coords

    pickup.ped = CreatePed( 4, model, coords.x, coords.y, coords.z + 1.0, coords.w or Config.PickupPed.heading or 0.0, true, true )

    SetEntityAsMissionEntity(pickup.ped, true, true)
    SetEntityInvincible(pickup.ped, true)
    FreezeEntityPosition(pickup.ped, true)
    SetBlockingOfNonTemporaryEvents(pickup.ped, true)

    if Config.PickupPed.scenario then
        TaskStartScenarioInPlace(pickup.ped, Config.PickupPed.scenario, 0, true)
    end

    SetModelAsNoLongerNeeded(model)

    pickup.target = pickup.ped

    exports.ox_target:addLocalEntity(pickup.ped, {
        {
            name = ('flex_brickphone_pickup_%s'):format(orderId),
            icon = Config.PickupPed.targetIcon,
            label = locale('crafter.interaction_prompt'),
            distance = Config.PickupPed.targetDistance,
            onSelect = function()
                local current = pickupOrders[orderId]
                if not current or not current.ped or not DoesEntityExist(current.ped) then return end

                local netId = NetworkGetNetworkIdFromEntity(current.ped)
                if netId == 0 then return end

                TriggerServerEvent('flex_brickphone:server:pickupCraftedItem', {
                    orderId = orderId,
                    netId = netId
                })
            end
        }
    })
end

local function createPickupZone(pickupData)
    if not pickupData or not pickupData.coords or not pickupData.orderId then return end

    cleanupPickup(pickupData.orderId)

    local orderId = pickupData.orderId
    local pickup = {
        orderId = orderId,
        coords = pickupData.coords,
        zoneId = pickupData.zoneId,
        zone = nil,
        ped = nil,
        target = nil,
        ready = pickupData.ready == true
    }

    pickupOrders[orderId] = pickup
    refreshPickupWaypoint()

    pickup.zone = lib.zones.sphere({
        name = ('brickphone_pickup_%s'):format(orderId),
        coords = vector3(pickup.coords.x, pickup.coords.y, pickup.coords.z),
        radius = Config.PickupZone.radius,
        debug = Config.PickupZone.debug == true,

        onEnter = function()
            spawnPickupPed(orderId)
        end,

        onExit = function()
            local current = pickupOrders[orderId]
            if not current then return end

            if current.target then
                exports.ox_target:removeLocalEntity(current.target)
                current.target = nil
            end

            if current.ped and DoesEntityExist(current.ped) then
                SetEntityAsMissionEntity(current.ped, true, true)
                DeleteEntity(current.ped)
            end

            current.ped = nil
            TriggerServerEvent('flex_brickphone:server:pickupZoneExited', orderId)
        end
    })

end

exports('useBrickPhone', function(data, slot)
    if not data then return end

    lib.callback('flex_brickphone:server:openPhone', false, function(canOpen)
        if not canOpen then return end

        SendNUIMessage({
            action = 'setLocale',
            locale = lib.getLocales()
        })

        setPhoneVisible(true)
        TriggerServerEvent('flex_brickphone:server:getContacts')
    end)
end)

exports('openPhone', function()
    exports.useBrickPhone({
        name = Config.PhoneItem
    }, nil)
end)

exports('closePhone', function()
    setPhoneVisible(false)
end)

exports('sendContactMessage', function(contactId, message)
    SendNUIMessage({
        action = 'appendMessage',
        contactId = contactId,
        message = type(message) == 'table' and message or {
            from = 'contact',
            text = message
        }
    })
end)

exports('replyToContact', function(contactId, message, callback)
    if not contactId or type(message) ~= 'string' then
        if callback then callback(false) end
        return false
    end

    lib.callback('flex_brickphone:server:sendMessage', false, function(result)
        if callback then callback(result) end
    end, {
        contactId = contactId,
        message = message
    })

    return true
end)

exports('setPhoneWaypoint', function(coords, label)
    TriggerEvent('flex_brickphone:client:setWaypoint', coords, label)
end)

RegisterNUICallback('close', function(_, cb)
    setPhoneVisible(false)
    cb({})
end)

RegisterNUICallback('getMessages', function(data, cb)
    if not data or type(data.contactId) ~= 'string' then
        cb({ received = false })
        return
    end

    TriggerServerEvent('flex_brickphone:server:getMessages', data.contactId)
    cb({ received = true })
end)

RegisterNUICallback('sendMessage', function(data, cb)
    if not data or not data.contactId or type(data.message) ~= 'string' then
        cb({ received = false })
        return
    end

    lib.callback('flex_brickphone:server:sendMessage', false, function(result)
        SendNUIMessage({
            action = 'messageResult',
            contactId = data.contactId,
            received = result
        })

        cb({ received = result })
    end, data)
end)

RegisterNetEvent('flex_brickphone:client:receiveContacts', function(contacts)
    SendNUIMessage({
        action = 'setContacts',
        contacts = contacts
    })
end)

RegisterNetEvent('flex_brickphone:client:receiveMessages', function(contactId, messages)
    SendNUIMessage({
        action = 'setMessages',
        contactId = contactId,
        messages = messages
    })
end)

RegisterNetEvent('flex_brickphone:client:appendMessage', function(contactId, message)
    local normalized = type(message) == 'table' and message or {
        from = 'contact',
        text = tostring(message or '')
    }

    SendNUIMessage({
        action = 'appendMessage',
        contactId = contactId,
        message = normalized
    })
end)

RegisterNetEvent('flex_brickphone:client:notify', function(data)
    lib.notify(data)
end)

RegisterNetEvent('flex_brickphone:client:setWaypoint', function(coords, label)
    cleanupWaypoint()

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 1)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 1.0)
    SetBlipColour(blip, 38)
    SetBlipAsShortRange(blip, true)
    SetBlipRoute(blip, true)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or 'Phone Mission')
    EndTextCommandSetBlipName(blip)

    currentWaypointBlip = blip
end)

RegisterNetEvent('flex_brickphone:client:createPickupZone', function(pickupData)
    createPickupZone(pickupData)
end)

RegisterNetEvent('flex_brickphone:client:removePickupZone', function(orderId)
    if orderId then
        cleanupPickup(orderId)
    else
        cleanupPickups()
    end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function()
    TriggerServerEvent('flex_brickphone:server:getContacts')
end)

RegisterNetEvent('qbx_core:client:jobUpdated', function()
    TriggerServerEvent('flex_brickphone:server:getContacts')
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    cleanupClient()
    TriggerServerEvent('flex_brickphone:server:playerCleanup')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    cleanupClient()
end)
