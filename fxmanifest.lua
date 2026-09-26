fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'flex BrickPhone'
description 'Brickphone script'
version '0.0.1'

ui_page('ui/index.html') 

ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/sv_shared.lua'
}

client_scripts {
    'client/bridge/esx.lua',
    'client/bridge/qb.lua',
    'client/bridge/qbx.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge/esx.lua',
    'server/bridge/qb.lua',
    'server/bridge/qbx.lua',
    'server/main.lua',
    'server/groups.lua',
}

files {
    'locales/*.json',
    'ui/index.html',
    'ui/style.css',
    'ui/script.js',
}

dependencies {
    'ox_lib',
    'qbx_core',
    'ox_target'
}