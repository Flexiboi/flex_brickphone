Config = {}

Config.Debug = false
Config.CoreName = {
    qb = 'qb-core',
    esx = 'es_extended',
    ox = 'ox_core',
    ox_inv = 'ox_inventory',
    qbx = 'qbx_core',
}

Config.PhoneItem = 'brickphone'
Config.SkillSystem = 'v-hpone'

Config.Contacts = {
    ['groups'] = {
        id = 'groups',
        name = 'groups.contact_name',
        number = 'GROUPS',
        enabled = true,
        system = true
    },
    ['crafter'] = {
        id = 'crafter',
        name = 'contacts.crafter_name',
        number = '555-CRAFT',
        enabled = true,
        requirement = {
            skill = 'crafting',
            type = 'level',
            value = 0
        }
        -- Job-restricted contacts can use either a string or a list:
        -- job = 'police'
        -- job = { 'police', 'ambulance' }
        -- Add onDuty = true when the player must currently be clocked in.
        -- Minimum online/on-duty count for a contact can be configured with:
        -- policeCount = { jobs = { 'police', 'bcso' }, count = 1 }
        -- By default policeCount counts ON-DUTY players. Set onDuty = false
        -- inside policeCount to count all online players in the listed jobs.
    },
    -- ['fleeca_heist'] = {
    --     id = 'fleeca_heist',
    --     name = 'Mvr. Flee Ka',
    --     number = '911',
    --     enabled = true,
    --     policeCount = {
    --         jobs = { 'police', 'bcso' },
    --         count = 0
    --     }
    -- },
}

--[[
    Limits how many messages are retained per contact during the current player session.
]]
Config.MessageHistoryLimit = 60

--[[
    Configures crafting orders, including the maximum quantity per order and concurrent orders.
    craftTime is the number of seconds required to craft one item.
]]
Config.Crafting = {
    maxQuantityPerOrder = 5,
    maxActiveOrders = 5,
    maxPendingOrders = 10,
    craftTimeDefault = 30,
    pickupDistance = 10.0,
}

--[[
    Configures the ped and ox_target interaction used by ready crafting orders.
]]
Config.PickupPed = {
    model = 's_m_m_dockwork_01',
    heading = 0.0,
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    targetIcon = 'fa-solid fa-box',
    targetDistance = 2.0,
}

--[[
    Configures the client-side loading distance for pickup peds.
    Peds are only spawned while the player is inside their ox_lib sphere.
]]
Config.PickupZone = {
    radius = 35.0,
    debug = false,
}

--[[
    Configures persistent BrickPhone groups. Groups reuse the normal contact/conversation flow.
]]
Config.Groups = {
    inviteExpiry = 900,
    maxMembers = 50,
    maxNameLength = 100,
    removeOnDisconnect = false,
    transferOwnerOnLeave = true,
    deleteEmptyGroups = false
}
