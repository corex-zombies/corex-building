fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'corex-building'
description 'COREX item-driven modular survival building'
author 'COREX'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua', 'config.lua', 'locales/en.lua', 'locales/ar.lua',
    'shared/locale.lua', 'shared/catalog.lua', 'shared/geometry.lua'
}
client_scripts { 'client/feedback.lua', 'client/doors.lua', 'client/main.lua', 'client/placement.lua' }
server_scripts {
    '@oxmysql/lib/MySQL.lua', '@corex-capabilities/shared/inventory_bridge.lua',
    'server/passwords.js', 'server/storage.lua', 'server/main.lua'
}
files { 'icons/*.png', 'data/collisions.json', 'sql/corex_building.sql' }
dependencies { 'corex-core', 'corex-capabilities', 'corex-content', 'corex-building-assets', 'ox_lib', 'oxmysql', '/onesync' }
