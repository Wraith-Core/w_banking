game 'rdr3'
fx_version 'adamant'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

description 'w_banking'
version '2.0.2'

-- w_lib bootstrap must run before any script that uses w / cache
shared_scripts { '@w_lib/init.lua', 'config.lua' }

-- modules loaded at start: the dictionary (locales/{ar,en}.json) and the callback wire
w_lib { 'locale', 'callback' }

-- account wrappers first: server.lua fills their registries at start
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/accounts.lua', 'server/wrappers/*.lua', 'server/server.lua' }

client_script 'client/*.lua'

ui_page 'nui/index.html'

files {
    'locales/*.json',
    'nui/index.html',
    'nui/style.css', 'nui/store-skin.css', 'nui/store-skin.js',
    'nui/w_banking.js',
    'w_banking.sql',
    'nui/fonts/*.woff2',
}

-- w_core too: its core object is fetched at load (w.framework:getCoreObject())
dependencies { 'w_lib', 'w_core', 'oxmysql' }
