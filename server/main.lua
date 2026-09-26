local usedPickupZones = {}
local activePickups = {}
local phoneMessages = {}
local contactHandlers = {}
local nextOrderId = 0
local lastMessageAt = {}
local pendingCraftOrders = {}

local function hasPhone(src)
    return HasInvGotItem(src, 'count', Config.PhoneItem, nil, 1)
end

local function getSkill(src, skillName)
    if not skillName or not Config.SkillSystem or GetResourceState(Config.SkillSystem) ~= 'started' then
        return { level = 0, xp = 0 }
    end

    return {
        level = exports[Config.SkillSystem]:getSkillLevel(src, skillName) or 0,
        xp = exports[Config.SkillSystem]:getSkillXp(src, skillName) or 0
    }
end

local function getQbxJobData(src)
    if GetResourceState(Config.CoreName.qbx) ~= 'started' or type(GetPlayer) ~= 'function' then
        return nil
    end

    local player = GetPlayer(src)
    if not player then return nil end

    local data = player.PlayerData or player
    local job = data.job or player.job
    if type(job) ~= 'table' then return nil end

    return {
        name = tostring(job.name or ''):lower(),
        grade = job.grade,
        onDuty = job.onduty ~= false and job.onDuty ~= false
    }
end

local function jobIsAllowed(jobConfig, jobName)
    if type(jobConfig) == 'string' then
        return jobConfig:lower() == jobName
    end

    if type(jobConfig) ~= 'table' then return false end

    for _, allowedJob in ipairs(jobConfig) do
        if type(allowedJob) == 'string' and allowedJob:lower() == jobName then
            return true
        end
    end

    return false
end

local function getContactJobData(src, contact)
    if not contact or contact.job == nil then return nil end

    local jobData = getQbxJobData(src)
    if not jobData then return nil end

    return jobData
end

local function getContactPoliceCount(policeCount)
    if type(policeCount) ~= 'table' or type(policeCount.jobs) ~= 'table' then
        return 0
    end

    if GetResourceState(Config.CoreName.qbx) ~= 'started' then
        return 0
    end

    local total = 0
    local countedJobs = {}
    local onDuty = policeCount.onDuty ~= false

    for _, jobName in ipairs(policeCount.jobs) do
        if type(jobName) == 'string' then
            local normalized = jobName:lower()
            if not countedJobs[normalized] then
                countedJobs[normalized] = true

                local ok, result = pcall(function()
                    if onDuty then
                        local count = exports[Config.CoreName.qbx]:GetDutyCountJob(normalized)
                        return tonumber(count) or 0
                    end

                    local count = 0
                    for playerId in pairs(GetPlayers()) do
                        local jobData = getQbxJobData(tonumber(playerId))
                        if jobData and jobData.name == normalized then
                            count = count + 1
                        end
                    end
                    return count
                end)

                if ok then
                    total = total + (tonumber(result) or 0)
                elseif Config.Debug then
                    print(('[flex_brickphone] Failed to count Qbox job "%s": %s'):format(normalized, tostring(result)))
                end
            end
        end
    end

    return total
end

local function policeCountIsMet(contact)
    local requirement = contact and contact.policeCount
    if type(requirement) ~= 'table' then return true, 0, 0 end

    local required = math.max(0, tonumber(requirement.count) or 0)
    local current = getContactPoliceCount(requirement)

    return current >= required, current, required
end

local function contactTargetMatchesSource(src, contact)
    if not contact then return false end

    local target = contact.target
    if target == nil or target == 'all' then
        return true
    end

    local targetSource = tonumber(target)
    local playerSource = tonumber(src)
    if not targetSource or not playerSource then
        return false
    end

    return targetSource == playerSource
end

local function canAccessContact(src, contact)
    if not contact or contact.enabled == false then return false end
    if not contactTargetMatchesSource(src, contact) then return false end

    local policeCountMet = policeCountIsMet(contact)
    if not policeCountMet then
        return false
    end

    if contact.job ~= nil then
        local jobData = getQbxJobData(src)
        if not jobData or not jobIsAllowed(contact.job, jobData.name) then
            return false
        end

        if contact.onDuty == true and not jobData.onDuty then
            return false
        end
    end

    if not contact.requirement or not contact.requirement.skill then return true end

    local skillData = getSkill(src, contact.requirement.skill)
    local reqType = contact.requirement.type
    local reqValue = tonumber(contact.requirement.value) or 0

    if reqType == 'level' then
        return skillData.level >= reqValue
    elseif reqType == 'xp' then
        return skillData.xp >= reqValue
    end

    return false
end

local function getAvailablePickupZone()
    for id, coords in pairs(Config.SV_Config.pickUpZones) do
        if not usedPickupZones[id] then
            usedPickupZones[id] = true
            return id, coords
        end
    end

    return nil, nil
end

local function freePickupZone(id)
    if id then
        usedPickupZones[id] = nil
    end
end

local function addPhoneMessage(src, contactId, text, from)
    phoneMessages[src] = phoneMessages[src] or {}
    phoneMessages[src][contactId] = phoneMessages[src][contactId] or {}

    local messages = phoneMessages[src][contactId]
    messages[#messages + 1] = {
        from = from or 'contact',
        text = tostring(text or '')
    }

    while #messages > Config.MessageHistoryLimit do
        table.remove(messages, 1)
    end

    return messages
end

function SendBrickPhoneMessage(src, contactId, text, from)
    if not src or not contactId or text == nil then return false end

    local contact = Config.Contacts[contactId]
    if not contact or not canAccessContact(src, contact) then return false end

    local message = {
        from = from or 'contact',
        text = tostring(text)
    }

    addPhoneMessage(src, contactId, message.text, message.from)
    TriggerClientEvent('flex_brickphone:client:appendMessage', src, contactId, message)
    return true
end

local function sendPhoneMessage(src, contactId, text, from)
    if not src or not contactId or text == nil then return false end

    local contact = Config.Contacts[contactId]
    if not contact or not canAccessContact(src, contact) then return false end

    local message = {
        from = from or 'contact',
        text = tostring(text)
    }

    addPhoneMessage(src, contactId, message.text, message.from)
    TriggerClientEvent('flex_brickphone:client:appendMessage', src, contactId, message)
    return true
end

function RefreshBrickPhoneContacts(src)
    local availableContacts = {}

    for id, contact in pairs(Config.Contacts) do
        if canAccessContact(src, contact) then
            availableContacts[id] = {
                id = contact.id or id,
                name = locale(contact.name) or contact.name,
                number = contact.number
            }
        end
    end

    if GetBrickPhoneGroups then
        for id, contact in pairs(GetBrickPhoneGroups(src) or {}) do
            availableContacts[id] = contact
        end
    end

    TriggerClientEvent('flex_brickphone:client:receiveContacts', src, availableContacts)
end

RegisterNetEvent('flex_brickphone:server:getContacts', function()
    RefreshBrickPhoneContacts(source)
end)

RegisterNetEvent('flex_brickphone:server:getMessages', function(contactId)
    local src = source
    if type(contactId) ~= 'string' then return end

    local groupId = GetBrickPhoneGroupId and GetBrickPhoneGroupId(contactId)
    if groupId then
        if GetBrickPhoneGroupMessages then
            local messages = GetBrickPhoneGroupMessages(src, groupId)
            if messages then
                TriggerClientEvent('flex_brickphone:client:receiveMessages', src, contactId, messages)
            end
        end
        return
    end

    local contact = Config.Contacts[contactId]
    if not contact or not canAccessContact(src, contact) then return end

    if contactId == 'crafter' and (not phoneMessages[src] or not phoneMessages[src][contactId] or #phoneMessages[src][contactId] == 0) then
        addPhoneMessage(src, contactId, locale('crafter.help_message'), 'contact')
    elseif contactId == 'groups' and (not phoneMessages[src] or not phoneMessages[src][contactId] or #phoneMessages[src][contactId] == 0) then
        addPhoneMessage(src, contactId, locale('groups.help_message'), 'contact')
    end

    local messages = phoneMessages[src] and phoneMessages[src][contactId] or {}
    TriggerClientEvent('flex_brickphone:client:receiveMessages', src, contactId, messages)
end)

local function getActiveOrderCount(src)
    local count = 0

    for _, pickup in pairs(activePickups) do
        if pickup.src == src then
            count += 1
        end
    end

    return count
end

local function createOrderId()
    nextOrderId += 1
    return ('%s_%s'):format(os.time(), nextOrderId)
end

local function parseCraftRequest(message)
    local clean = message:lower():gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')

    local itemLabel, amount = clean:match('^(.-)%s+[xX]?%s*(%d+)$')
    if itemLabel and itemLabel ~= '' then
        return itemLabel, tonumber(amount)
    end

    amount, itemLabel = clean:match('^(%d+)%s+[xX]?%s*(.+)$')
    if amount and itemLabel and itemLabel ~= '' then
        return itemLabel, tonumber(amount)
    end

    if clean ~= '' then
        return clean, 1
    end

    return nil, nil
end

local function getCraftTime(recipe)
    return math.max(1, tonumber(recipe.craftTime) or Config.Crafting.craftTimeDefault)
end

local function normalizeCraftLabel(value)
    return tostring(value or ''):lower():gsub('[%s%p]+', '')
end

local function getInventoryItem(itemName)
    if not itemName or GetResourceState(Config.CoreName.ox_inv) ~= 'started' then return nil end

    local requested = tostring(itemName)
    local items = exports.ox_inventory.Items

    if type(items) ~= 'table' then return nil end

    local direct = items[requested]
    if type(direct) == 'table' then return direct end

    local lowerRequested = requested:lower()
    local upperRequested = requested:upper()

    direct = items[lowerRequested] or items[upperRequested]
    if type(direct) == 'table' then return direct end

    for key, item in pairs(items) do
        if type(item) == 'table' and tostring(key):lower() == lowerRequested then
            return item
        end
    end

    return nil
end

local function getInventoryLabel(itemName)
    local item = getInventoryItem(itemName)
    return item and item.label or itemName
end

local function getRecipeDisplayData(recipe)
    local reward = getInventoryItem(recipe.reward)
    local rewardLabel = reward and reward.label or recipe.reward
    local materials = {}

    for _, mat in ipairs(recipe.materials or {}) do
        materials[#materials + 1] = {
            item = mat.item,
            label = getInventoryLabel(mat.item),
            amount = tonumber(mat.amount) or 0
        }
    end

    return rewardLabel, materials
end

local function findRecipeByInput(input)
    local normalized = normalizeCraftLabel(input)

    for recipeId, recipe in pairs(Config.SV_Config.crafterItems) do
        local orderingName = recipe.orderingName or recipe.orderName or recipeId
        if normalized == normalizeCraftLabel(orderingName) then
            return recipeId, recipe, getInventoryLabel(recipe.reward)
        end
    end

    return nil, nil, nil
end

local function getListCommand()
    return locale('crafter.commands.list')
end

local function buildCraftList()
    local lines = { locale('crafter.list_title'), '' }

    local recipes = {}
    for recipeId, recipe in pairs(Config.SV_Config.crafterItems) do
        local rewardLabel, materials = getRecipeDisplayData(recipe)
        local orderingName = recipe.orderingName or recipe.orderName or recipeId
        recipes[#recipes + 1] = { id = recipeId, recipe = recipe, label = rewardLabel, orderingName = orderingName, materials = materials }
    end

    table.sort(recipes, function(a, b)
        return normalizeCraftLabel(a.label) < normalizeCraftLabel(b.label)
    end)

    for _, entry in ipairs(recipes) do
        local materialParts = {}
        for _, mat in ipairs(entry.materials) do
            materialParts[#materialParts + 1] = ('%sx %s'):format(mat.amount, mat.label)
        end

        local orderingName = entry.recipe.orderingName or entry.recipe.orderName or entry.id
        lines[#lines + 1] = ('### %s'):format(entry.label)
        lines[#lines + 1] = ('**%s:** `%s <amount>`'):format(locale('crafter.list_command'), orderingName)
        lines[#lines + 1] = ('**%s:**'):format(locale('crafter.list_materials'))
        for _, mat in ipairs(entry.materials) do
            lines[#lines + 1] = ('- %sx %s'):format(mat.amount, mat.label)
        end
        lines[#lines + 1] = ('**%s:** %ss'):format(locale('crafter.list_time'), getCraftTime(entry.recipe))
        lines[#lines + 1] = ('**%s:** 1-%s'):format(locale('crafter.list_quantity'), Config.Crafting.maxQuantityPerOrder)
        lines[#lines + 1] = ''
    end

    return table.concat(lines, '\n')
end

local function getCommittedMaterials(src)
    local committed = {}

    local function add(item, amount)
        committed[item] = (committed[item] or 0) + amount
    end

    for _, pickup in pairs(activePickups) do
        if pickup.src == src then
            for _, mat in ipairs(pickup.materials or {}) do
                add(mat.item, tonumber(mat.amount) or 0)
            end
        end
    end

    for recipeId, quantity in pairs(pendingCraftOrders[src] or {}) do
        local recipe = Config.SV_Config.crafterItems[recipeId]
        if recipe then
            for _, mat in ipairs(recipe.materials or {}) do
                add(mat.item, (tonumber(mat.amount) or 0) * quantity)
            end
        end
    end

    return committed
end

local function hasCraftMaterials(src, recipe, quantity)
    local committed = getCommittedMaterials(src)

    for _, mat in ipairs(recipe.materials or {}) do
        local amount = (tonumber(mat.amount) or 0) * quantity
        if amount < 1 then return false end

        if not HasInvGotItem(src, 'count', mat.item, nil, amount + (committed[mat.item] or 0)) then
            return false
        end
    end

    return true
end

local function hasAllCommittedMaterials(src)
    local committed = getCommittedMaterials(src)

    for item, amount in pairs(committed) do
        if amount > 0 and not HasInvGotItem(src, 'count', item, nil, amount) then
            return false
        end
    end

    return true
end

local function countPendingRecipes(src)
    local count = 0
    for _ in pairs(pendingCraftOrders[src] or {}) do
        count += 1
    end
    return count
end

local function buildCraftStatus(src)
    local lines = { locale('crafter.status_title'), '' }
    local activeCount = 0

    for _, pickup in pairs(activePickups) do
        if pickup.src == src then
            activeCount += 1
            local label = getInventoryLabel(pickup.recipe.reward)
            local state
            if pickup.ready then
                state = locale('crafter.status_ready')
            else
                local remaining = math.max(0, math.ceil((pickup.readyAt - GetGameTimer()) / 1000))
                state = locale('crafter.status_crafting'):format(remaining)
            end
            lines[#lines + 1] = ('- **%s x%s** — `%s` — %s'):format(label, pickup.quantity, pickup.orderId, state)
        end
    end

    local pending = pendingCraftOrders[src] or {}
    local pendingCount = 0
    for recipeId, quantity in pairs(pending) do
        pendingCount += 1
        local recipe = Config.SV_Config.crafterItems[recipeId]
        if recipe then
            lines[#lines + 1] = ('- **%s x%s** — `%s` — %s'):format(
                getInventoryLabel(recipe.reward),
                quantity,
                'pending',
                locale('crafter.status_pending')
            )
        end
    end

    if activeCount == 0 and pendingCount == 0 then
        lines[#lines + 1] = locale('crafter.status_empty')
    end

    lines[#lines + 1] = ''
    lines[#lines + 1] = locale('crafter.status_cancel_hint')
    return table.concat(lines, '\n')
end

local function buildPendingOrder(src)
    local pending = pendingCraftOrders[src] or {}
    local lines = { locale('crafter.order_title'), '' }
    local totalTime = 0
    local count = 0

    for recipeId, quantity in pairs(pending) do
        local recipe = Config.SV_Config.crafterItems[recipeId]
        if recipe then
            local label = getInventoryLabel(recipe.reward)
            local itemTime = getCraftTime(recipe)
            totalTime += itemTime * quantity
            count += 1
            lines[#lines + 1] = ('- **%sx %s** — %ss'):format(quantity, label, itemTime * quantity)
        end
    end

    if count == 0 then
        return locale('crafter.order_empty')
    end

    lines[#lines + 1] = ''
    lines[#lines + 1] = ('**%s:** %ss'):format(locale('crafter.order_total_time'), totalTime)
    lines[#lines + 1] = ''
    lines[#lines + 1] = locale('crafter.order_confirm_hint')
    lines[#lines + 1] = locale('crafter.order_add_hint')
    lines[#lines + 1] = locale('crafter.remove_hint')
    lines[#lines + 1] = locale('crafter.order_clear_hint')

    return table.concat(lines, '\n')
end

local function removePickup(src, orderId)
    local pickup = activePickups[orderId]
    if not pickup or pickup.src ~= src then return false end

    freePickupZone(pickup.zoneId)
    activePickups[orderId] = nil

    TriggerClientEvent('flex_brickphone:client:removePickupZone', src, orderId)
    return true
end

local function makePickupReady(orderId)
    local pickup = activePickups[orderId]
    if not pickup then return end

    pickup.ready = true

    TriggerClientEvent('flex_brickphone:client:createPickupZone', pickup.src, {
        orderId = pickup.orderId,
        coords = pickup.coords,
        heading = pickup.coords.w,
        zoneId = pickup.zoneId,
        netId = pickup.netId,
        ready = true
    })

    sendPhoneMessage(
        pickup.src,
        'crafter',
        string.format(
            '### %s\nYour **%dx %s** is ready for pickup.\n- **Pickup:** `%s`',
            locale('crafter.pickup_ready'),
            pickup.quantity,
            getInventoryLabel(pickup.recipe.reward),
            pickup.orderId
        ),
        'contact'
    )
end

local function createCraftOrder(src, itemId, quantity, recipe)
    local zoneId, pickupCoords = getAvailablePickupZone()
    if not zoneId then return false, 'zones' end

    local orderId = createOrderId()
    local craftTime = getCraftTime(recipe)
    local totalTime = craftTime * quantity

    local pickup = {
        src = src,
        orderId = orderId,
        zoneId = zoneId,
        itemId = itemId,
        recipe = recipe,
        quantity = quantity,
        coords = pickupCoords,
        materials = {},
        ready = false,
        readyAt = GetGameTimer() + (totalTime * 1000)
    }

    for _, mat in ipairs(recipe.materials) do
        pickup.materials[#pickup.materials + 1] = {
            item = mat.item,
            amount = mat.amount * quantity
        }
    end

    activePickups[orderId] = pickup

    SetTimeout(totalTime * 1000, function()
        if activePickups[orderId] then
            makePickupReady(orderId)
        end
    end)

    return true, pickup
end

lib.callback.register('flex_brickphone:server:sendMessage', function(src, data)
    if type(data) ~= 'table' or type(data.contactId) ~= 'string' or type(data.message) ~= 'string' then
        return false
    end

    if #data.message > 2000 then
        return false
    end

    local now = GetGameTimer()
    if lastMessageAt[src] and now - lastMessageAt[src] < 250 then
        return false
    end
    lastMessageAt[src] = now

    local contactId = data.contactId

    if Config.Debug then
        print(('[flex_brickphone] sendMessage: src=%s contact=%s message=%q'):format(tostring(src), contactId, data.message))
    end

    if GetBrickPhoneGroupId and GetBrickPhoneSendMessage and GetBrickPhoneGroupId(contactId) then
        local groupId = GetBrickPhoneGroupId(contactId)
        local ok, result = GetBrickPhoneSendMessage(groupId, src, data.message, data.messageType)
        return ok and { received = true, accepted = true, action = 'group_message', messageId = result } or false
    end

    local contact = Config.Contacts[contactId]

    if not contact then
        lib.notify(src, {
            title = locale('error.contact_not_found'),
            type = 'error'
        })
        return false
    end

    if not canAccessContact(src, contact) then
        local policeCountMet, currentPoliceCount, requiredPoliceCount = policeCountIsMet(contact)
        local errorKey = contact.job ~= nil and 'error.job_required' or 'error.skill_too_low'

        if contact.policeCount and not policeCountMet then
            lib.notify(src, {
                title = locale('error.police_count_required'):format(currentPoliceCount, requiredPoliceCount),
                type = 'error'
            })
        else
            lib.notify(src, {
                title = locale(errorKey),
                type = 'error'
            })
        end
        return false
    end

    addPhoneMessage(src, contactId, data.message, 'player')

    local handler = contactHandlers[contactId]
    if Config.Debug then
        print(('[flex_brickphone] contact handler lookup: contact=%s handler=%s'):format(contactId, tostring(handler ~= nil)))
    end
    if handler then
        local skillData = getSkill(src, contact.requirement and contact.requirement.skill)
        local handlerData = {
            message = data.message,
            contact = contact,
            contactId = contactId,
            skill = skillData,
            job = getContactJobData(src, contact),
            policeCount = contact.policeCount and ({
                current = getContactPoliceCount(contact.policeCount),
                required = tonumber(contact.policeCount.count) or 0,
                jobs = contact.policeCount.jobs,
                onDuty = contact.policeCount.onDuty ~= false
            }) or nil
        }

        local ok, result = pcall(function()
            return handler(src, handlerData)
        end)

        if not ok then
            print(('[flex_brickphone] Contact handler "%s" failed: %s'):format(contactId, result))
            return false
        end

        if result == nil then return true end
        return result
    end

    return false
end)

function RegisterBrickPhoneContactHandler(contactId, handler)
    if type(contactId) ~= 'string' or type(handler) ~= 'function' then return false end
    if not Config.Contacts[contactId] then return false end
    contactHandlers[contactId] = handler
    return true
end

exports('registerContactHandler', function(contactId, handler)
    if type(contactId) ~= 'string' or contactId == '' or handler == nil then
        return false
    end

    contactHandlers[contactId] = handler
    return true
end)

exports('unregisterContactHandler', function(contactId)
    if type(contactId) ~= 'string' then return false end
    contactHandlers[contactId] = nil
    return true
end)

exports('registerContact', function(contactId, contact, handler, target)
    if type(contactId) ~= 'string' or contactId == '' or type(contact) ~= 'table' then return false end

    local contactTarget = target ~= nil and target or contact.target
    if contactTarget == nil then
        contactTarget = 'all'
    end

    if contactTarget ~= 'all' and not tonumber(contactTarget) then
        return false
    end

    contact.id = contact.id or contactId
    contact.target = contactTarget
    Config.Contacts[contactId] = contact
    contactHandlers[contactId] = handler or contactHandlers[contactId]

    if contactTarget == 'all' then
        for _, playerId in ipairs(GetPlayers()) do
            RefreshBrickPhoneContacts(tonumber(playerId))
        end
    else
        local targetSource = tonumber(contactTarget)
        if targetSource and GetPlayerName(targetSource) then
            RefreshBrickPhoneContacts(targetSource)
        end
    end

    return true
end)

exports('removeContact', function(contactId)
    if type(contactId) ~= 'string' then return false end
    if not Config.Contacts[contactId] then return false end

    Config.Contacts[contactId] = nil
    contactHandlers[contactId] = nil

    for _, playerId in ipairs(GetPlayers()) do
        RefreshBrickPhoneContacts(tonumber(playerId))
    end

    return true
end)

exports('sendContactMessage', function(src, contactId, message)
    return sendPhoneMessage(src, contactId, message, 'contact')
end)

exports('startMission', function(src, data)
    if type(data) ~= 'table' or not data.coords then return false end

    TriggerClientEvent('flex_brickphone:client:setWaypoint', src, data.coords, data.label or 'Phone Mission')

    if data.contactId and data.message then
        sendPhoneMessage(src, data.contactId, data.message, 'contact')
    end

    return true
end)

lib.callback.register('flex_brickphone:server:openPhone', function(source)
    if hasPhone(source) then return true end

    lib.notify(source, {
        title = locale('error.phone_not_found'),
        type = 'error'
    })

    return false
end)

local function handleCrafterMessage(src, data)
    local message = tostring(data.message or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local lowerMessage = message:lower()
    local listCommand = locale('crafter.commands.list'):lower()
    local orderCommand = locale('crafter.commands.order'):lower()
    local confirmCommand = locale('crafter.commands.confirm'):lower()
    local clearCommand = locale('crafter.commands.clear'):lower()
    local removeCommand = locale('crafter.commands.remove'):lower()

    if lowerMessage == listCommand then
        sendPhoneMessage(src, 'crafter', buildCraftList(), 'contact')
        return { received = true, accepted = true, action = 'list' }
    end

    if lowerMessage == orderCommand or lowerMessage == locale('crafter.commands.view'):lower() then
        sendPhoneMessage(src, 'crafter', buildPendingOrder(src), 'contact')
        return { received = true, accepted = true, action = 'order' }
    end

    local statusCommand = locale('crafter.commands.status'):lower()
    local cancelCommand = locale('crafter.commands.cancel'):lower()

    if lowerMessage == statusCommand then
        sendPhoneMessage(src, 'crafter', buildCraftStatus(src), 'contact')
        return { received = true, accepted = true, action = 'status' }
    end

    if lowerMessage == cancelCommand or lowerMessage:sub(1, #cancelCommand + 1) == (cancelCommand .. ' ') then
        local orderId = message:sub(#cancelCommand + 1):gsub('^%s+', '')
        if orderId == '' then
            sendPhoneMessage(src, 'crafter', locale('crafter.cancel_usage'), 'contact')
            return false
        end

        if removePickup(src, orderId) then
            sendPhoneMessage(src, 'crafter', locale('crafter.order_cancelled'):format(orderId), 'contact')
            return { received = true, accepted = true, action = 'cancel', orderId = orderId }
        end

        sendPhoneMessage(src, 'crafter', locale('crafter.order_not_found'), 'contact')
        return false
    end

    if lowerMessage == confirmCommand then
        local pending = pendingCraftOrders[src] or {}
        local pendingCount = 0
        for _ in pairs(pending) do pendingCount += 1 end

        if pendingCount == 0 then
            sendPhoneMessage(src, 'crafter', locale('crafter.order_empty'), 'contact')
            return false
        end

        if getActiveOrderCount(src) + pendingCount > Config.Crafting.maxActiveOrders then
            sendPhoneMessage(src, 'crafter', locale('crafter.max_orders'), 'contact')
            return false
        end

        if not hasAllCommittedMaterials(src) then
            sendPhoneMessage(src, 'crafter', locale('error.missing_items'), 'contact')
            return false
        end

        local created = {}
        for recipeId, quantity in pairs(pending) do
            local recipe = Config.SV_Config.crafterItems[recipeId]
            local ok, result = createCraftOrder(src, recipeId, quantity, recipe)
            if not ok then
                for _, createdOrder in ipairs(created) do
                    removePickup(src, createdOrder.orderId)
                end
                sendPhoneMessage(src, 'crafter', result == 'zones' and locale('error.pickup_zones_busy') or locale('error.cannot_craft'), 'contact')
                return false
            end
            created[#created + 1] = result
        end

        pendingCraftOrders[src] = nil
        sendPhoneMessage(src, 'crafter', locale('crafter.order_confirmed') .. '\n\n' .. locale('crafter.order_pickup_hint'), 'contact')
        return { received = true, accepted = true, action = 'confirm', orders = created }
    end

    if lowerMessage == clearCommand then
        pendingCraftOrders[src] = nil
        sendPhoneMessage(src, 'crafter', locale('crafter.order_cleared'), 'contact')
        return { received = true, accepted = true, action = 'clear' }
    end

    if lowerMessage == removeCommand or lowerMessage:sub(1, #removeCommand + 1) == (removeCommand .. ' ') then
        local removeInput = message:sub(#removeCommand + 1):gsub('^%s+', '')
        local rawItem, quantity = parseCraftRequest(removeInput)
        local recipeId, recipe, rewardLabel = findRecipeByInput(rawItem)

        if not recipe then
            sendPhoneMessage(src, 'crafter', locale('crafter.unknown_recipe'), 'contact')
            return false
        end

        local pending = pendingCraftOrders[src] or {}
        local existing = tonumber(pending[recipeId]) or 0
        if existing <= 0 then
            sendPhoneMessage(src, 'crafter', locale('crafter.remove_not_found'), 'contact')
            return false
        end

        local hasExplicitAmount = removeInput:match('^.-%s+[xX]?%s*%d+$') or removeInput:match('^%d+%s+[xX]?%s*.+$')
        if not hasExplicitAmount then
            quantity = existing
        end

        quantity = math.floor(tonumber(quantity) or 0)
        if quantity < 1 then
            sendPhoneMessage(src, 'crafter', locale('crafter.invalid_quantity'), 'contact')
            return false
        end

        if quantity > existing then
            sendPhoneMessage(src, 'crafter', locale('crafter.remove_too_many'), 'contact')
            return false
        end

        local remaining = existing - quantity
        if remaining > 0 then
            pending[recipeId] = remaining
        else
            pending[recipeId] = nil
        end

        local removedText
        if quantity == existing then
            removedText = locale('crafter.remove_all_from_order'):format(rewardLabel)
        else
            removedText = locale('crafter.remove_from_order'):format(quantity, rewardLabel)
        end

        sendPhoneMessage(src, 'crafter', removedText .. '\n\n' .. buildPendingOrder(src), 'contact')
        return { received = true, accepted = true, action = 'remove', item = recipeId, quantity = quantity, remaining = remaining }
    end

    local rawItem, quantity = parseCraftRequest(message)
    local recipeId, recipe, rewardLabel = findRecipeByInput(rawItem)

    if not recipe then
        sendPhoneMessage(src, 'crafter', locale('crafter.unknown_recipe'), 'contact')
        return false
    end

    quantity = math.floor(tonumber(quantity) or 1)
    if quantity < 1 or quantity > Config.Crafting.maxQuantityPerOrder then
        sendPhoneMessage(src, 'crafter', locale('crafter.invalid_quantity'), 'contact')
        return false
    end

    pendingCraftOrders[src] = pendingCraftOrders[src] or {}
    local pending = pendingCraftOrders[src]

    if not pending[recipeId] and countPendingRecipes(src) >= Config.Crafting.maxPendingOrders then
        sendPhoneMessage(src, 'crafter', locale('crafter.max_pending_orders'), 'contact')
        return false
    end

    local existing = pending[recipeId] or 0
    if existing + quantity > Config.Crafting.maxQuantityPerOrder then
        sendPhoneMessage(src, 'crafter', locale('crafter.invalid_quantity'), 'contact')
        return false
    end

    if not hasCraftMaterials(src, recipe, quantity) then
        sendPhoneMessage(src, 'crafter', locale('error.missing_items'), 'contact')
        return false
    end

    pending[recipeId] = existing + quantity

    sendPhoneMessage(
        src,
        'crafter',
        ('### %s\n**%sx %s**\n\n%s\n%s'):format(
            locale('crafter.added_to_order'),
            quantity,
            rewardLabel,
            locale('crafter.order_view_hint'),
            locale('crafter.order_confirm_hint')
        ),
        'contact'
    )

    return { received = true, accepted = true, action = 'add', item = recipeId, quantity = quantity }
end

contactHandlers['crafter'] = handleCrafterMessage

RegisterNetEvent('flex_brickphone:server:pickupCraftedItem', function(data)
    local src = source

    if type(data) ~= 'table' or type(data.orderId) ~= 'string' or not tonumber(data.netId) then
        return
    end

    local orderId = data.orderId
    local pickup = activePickups[orderId]

    if not pickup or pickup.src ~= src or not pickup.ready then
        return
    end

    local ped = GetPlayerPed(src)
    if ped == nil or ped == 0 then return end

    local entity = NetworkGetEntityFromNetworkId(tonumber(data.netId))
    if entity == 0 or not DoesEntityExist(entity) then
        return
    end

    local entityCoords = GetEntityCoords(entity)
    local pedCoords = GetEntityCoords(ped)

    if GetEntityModel(entity) ~= joaat(Config.PickupPed.model) then
        DropPlayer(src, locale('error.exploit_kick'))
        return
    end

    if #(entityCoords.xyz - pedCoords.xyz) > Config.Crafting.pickupDistance then
        DropPlayer(src, locale('error.exploit_kick'))
        return
    end

    if #(pedCoords.xyz - pickup.coords.xyz) > Config.PickupZone.radius then
        DropPlayer(src, locale('error.exploit_kick'))
        return
    end

    if #(entityCoords.xyz - pickup.coords.xyz) > 5.0 then
        DropPlayer(src, locale('error.exploit_kick'))
        return
    end

    local recipe = Config.SV_Config.crafterItems[pickup.itemId]
    if not recipe then
        removePickup(src, orderId, true)
        return
    end

    local totalReward = pickup.quantity

    if not hasCraftMaterials(src, recipe, totalReward) then
        lib.notify(src, {
            title = locale('error.missing_items'),
            type = 'error'
        })
        return
    end

    if GetResourceState(Config.CoreName.ox_inv) == 'started' and not exports.ox_inventory:CanCarryItem(src, recipe.reward, totalReward) then
        lib.notify(src, {
            title = locale('error.inventory_full'),
            type = 'error'
        })
        return
    end

    local removed = {}
    for _, mat in ipairs(recipe.materials or {}) do
        local amount = (tonumber(mat.amount) or 0) * totalReward
        if not RemoveItem(src, mat.item, amount) then
            for _, rollback in ipairs(removed) do
                AddItem(src, rollback.item, rollback.amount)
            end
            lib.notify(src, {
                title = locale('error.missing_items'),
                type = 'error'
            })
            return
        end
        removed[#removed + 1] = { item = mat.item, amount = amount }
    end

    local added = AddItem(src, recipe.reward, totalReward)
    if not added then
        for _, rollback in ipairs(removed) do
            AddItem(src, rollback.item, rollback.amount)
        end
        lib.notify(src, {
            title = locale('error.cannot_craft'),
            type = 'error'
        })
        return
    end

    freePickupZone(pickup.zoneId)
    activePickups[orderId] = nil
    TriggerClientEvent('flex_brickphone:client:removePickupZone', src, orderId)

    lib.notify(src, {
        title = locale('success.item_crafted'),
        description = string.format('%dx %s', totalReward, getInventoryLabel(recipe.reward)),
        type = 'success'
    })

    sendPhoneMessage(
        src,
        'crafter',
        string.format(
            '**Pickup complete:** `%s` x%s has been added to your inventory.',
            recipe.reward,
            totalReward
        ),
        'contact'
    )
end)

RegisterNetEvent('flex_brickphone:server:pickupZoneExited', function(orderId)
    local src = source
    local pickup = activePickups[orderId]

    if pickup and pickup.src == src then
        return
    end
end)

local function cleanupPlayer(src)
    for orderId, pickup in pairs(activePickups) do
        if pickup.src == src then
            freePickupZone(pickup.zoneId)
            activePickups[orderId] = nil
        end
    end

    phoneMessages[src] = nil
    pendingCraftOrders[src] = nil
    lastMessageAt[src] = nil
end

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    cleanupPlayer(source)
end)

AddEventHandler('playerDropped', function()
    cleanupPlayer(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for src, _ in pairs(phoneMessages) do
        cleanupPlayer(src)
    end
end)
