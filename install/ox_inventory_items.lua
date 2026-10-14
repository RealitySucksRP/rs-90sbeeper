-- Merge these entries into ox_inventory/data/items.lua.
-- This file is also valid standalone Lua for release syntax checks.

return {
    ['beeper'] = {
        label = '90s Beeper',
        weight = 220,
        stack = false,
        close = true,
        consume = 0,
        description = 'A compact 1990s pager with its own persistent pager number.',
        client = { export = 'rs-90sbeeper.useBeeper' }
    },

    ['beeperbattery'] = {
        label = 'Beeper Battery',
        weight = 60,
        stack = true,
        close = true,
        consume = 0,
        description = 'A replacement battery for a compact pager.',
        client = { export = 'rs-90sbeeper.RechargeBeeper' }
    },
}
