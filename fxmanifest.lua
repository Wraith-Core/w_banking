game 'rdr3'
fx_version 'adamant'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

description 'w_banking'
version '2.1.6'

-- w_lib bootstrap must run before any script that uses w / cache
shared_scripts { '@w_lib/init.lua', 'config.lua' }

-- modules loaded at start: the dictionary (locales/{ar,en}.json) and the callback wire
w_lib { 'locale', 'callback' }

-- account wrappers first: server.lua fills their registries at start
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/accounts.lua', 'server/wrappers/*.lua', 'server/server.lua' }

client_script 'client/*.lua'

-- 2.1.0: the page is built by vite (nui/src -> nui/build, `npm run build` in nui/); the build is committed
ui_page 'nui/build/index.html'

files {
    'locales/*.json',
    'nui/build/index.html',
    'nui/build/**/*',
    'w_banking.sql',
}

dependencies { 'w_lib', 'oxmysql' }
