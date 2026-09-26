fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'flex_brickphone_hacker'
description 'Hacker dlc for brickphone'
version '0.0.1'

ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'shared/config.lua',
    'client/bridge/*.lua',
    'server/bridge/*.lua',
}

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'shared/sv_shared.lua',
    'server/main.lua',
}

files {
    'locales/*.json',
}

dependencies {
    'ox_lib',
    'qbx_core',
    'flex_brickphone'
}