fx_version 'cerulean'
game 'gta5'

author 'RealitySucksRP'
description 'RS 90s Beeper - standalone 1990s pager network for phones, dispatch, jobs, gangs, illegal RP and custom resources'
version '0.4.6'

ui_page 'html/index.html'

shared_scripts {
    'config.lua',
    -- Common RS communication-event protocol. This resource vendors its own
    -- copy so it remains standalone and has no runtime dependency.
    'shared/commevent.lua'
}

client_scripts {
    'bridge/rs_uiguard.lua',
    'client/bridge.lua',
    -- DevicePoseManager, byte-identical with rs-radio and rs-tablet. Must load
    -- BEFORE main.lua, which configures it at file scope.
    'client/pose.lua',
    'client/main.lua'
}

server_scripts {
    -- No database dependency. server/main.lua keeps JSON when data/ is writable
    -- and automatically falls back to FiveM's built-in resource KVP store when
    -- managed hosting makes the resource folder read-only.
    'server/bridge.lua',
    'server/main.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/img/beeper.png',
    'html/sounds/pager_classic.ogg',
    'html/sounds/pager_priority.ogg',
    'html/sounds/pager_key.ogg',
    'html/sounds/pager_off.ogg',
    'html/sounds/pager_denied.ogg'
}
