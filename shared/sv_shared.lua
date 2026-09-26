Config.SV_Config = {}

lib.locale()

Config.SV_Config.crafterItems = {
    ['pistol'] = {
        orderingName = 'pistol',
        reward = 'weapon_pistol',
        craftTime = 30,
        materials = {
            { item = 'lockpick', amount = 2 },
            { item = 'steel', amount = 5 }
        }
    }
}

Config.SV_Config.pickUpZones = {
    [1] = vector4(-330.0, -140.0, 38.0, 180.0),
    [2] = vector4(1100.0, -2000.0, 30.0, 90.0)
}
