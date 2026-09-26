function GetOffsetFromVector4(coords, offset)
    local heading = math.rad(coords.w)

    local cosH = math.cos(heading)
    local sinH = math.sin(heading)

    local x = coords.x + (offset.x * cosH - offset.y * sinH)
    local y = coords.y + (offset.x * sinH + offset.y * cosH)
    local z = coords.z + offset.z

    -- Offset heading relative to the base heading
    local finalHeading = (coords.w + offset.w) % 360.0

    return vector4(x, y, z, finalHeading)
end

function SetDoorState(doorHash, coords, closed)
    local doorId = GetHashKey(("%s_%.2f_%.2f_%.2f"):format(
        doorHash,
        coords.x,
        coords.y,
        coords.z
    ))

    if not DoorSystemGetIsPhysicsLoaded(doorId) then
        AddDoorToSystem(
            doorId,
            doorHash,
            coords.x,
            coords.y,
            coords.z,
            false,
            false,
            false
        )
    end

    if closed then
        DoorSystemSetDoorState(doorId, 1, false, false)
    else
        DoorSystemSetDoorState(doorId, 0, false, false)
    end
end

function LoadModel(model)
    RequestModel(grabmodel)
    while not HasModelLoaded(grabmodel) do
        Citizen.Wait(100)
    end
end

function GetEntityNetworkControl(entity)
    if NetworkGetEntityIsNetworked(entity) then
        local netId = NetworkGetNetworkIdFromEntity(entity)
        local timeout = GetGameTimer() + 2000
        while not NetworkHasControlOfEntity(entity) and GetGameTimer() < timeout do
            NetworkRequestControlOfEntity(entity)
            SetNetworkIdCanMigrate(netId, true)
            Wait(0)
        end
        if not NetworkHasControlOfEntity(entity) then
            print('[flex_bankrob] Failed to get network control of entity:', entity, 'netId:', netId)
            return false
        end
    end
    return true
end

function DeleteNetworkedEntity(entity)
    if not entity or entity == 0 then
        return false
    end
    if not DoesEntityExist(entity) then
        return true
    end
    GetEntityNetworkControl(entity)
    SetEntityAsMissionEntity(entity, true, true)
    DeleteObject(entity)
    if DoesEntityExist(entity) then
        DeleteEntity(entity)
    end

    return not DoesEntityExist(entity)
end

function AddSphereZone(coords, data, radius)
    for i = 1, #data do
        data[i].distance = data[i].distance or 1.5
    end

    return exports.ox_target:addSphereZone({
        debug = Config.Debug,
        coords = coords,
        options = data,
        radius = radius or 1.5
    })
end

function RemoveZone(Targets)
    if type(Targets) == 'table' then
        for _, target in ipairs(Targets) do
            exports.ox_target:removeZone(target)
        end
    else
        exports.ox_target:removeZone(Targets)
    end
end

if Config.Debug then
    RegisterCommand("getbankoffset", function(source, args)
        -- Usage:
        -- /getbankoffset 146.29086303711 -1046.3134765625 29.529062271118 159.84617614746 145.89009094238 -1044.3018798828 30.002666473389 251.85873413086

        if #args < 8 then
            print("Usage: /getoffset x1 y1 z1 h1 x2 y2 z2 h2")
            return
        end

        local base = vector4(
            tonumber(args[1]),
            tonumber(args[2]),
            tonumber(args[3]),
            tonumber(args[4])
        )

        local target = vector4(
            tonumber(args[5]),
            tonumber(args[6]),
            tonumber(args[7]),
            tonumber(args[8])
        )

        local heading = math.rad(base.w)

        local dx = target.x - base.x
        local dy = target.y - base.y
        local dz = target.z - base.z

        -- Convert world position into base's local coordinates
        local offsetX = dx * math.cos(heading) + dy * math.sin(heading)
        local offsetY = -dx * math.sin(heading) + dy * math.cos(heading)
        local offsetZ = dz

        -- Calculate relative heading
        local offsetHeading = target.w - base.w

        -- Normalize heading to -180 -> 180
        if offsetHeading > 180.0 then
            offsetHeading = offsetHeading - 360.0
        elseif offsetHeading < -180.0 then
            offsetHeading = offsetHeading + 360.0
        end

        print(("vec4(%.3f, %.3f, %.3f, %.3f)"):format(
            offsetX,
            offsetY,
            offsetZ,
            offsetHeading
        ))
    end)
end