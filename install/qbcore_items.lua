-- Merge these entries into qb-core/shared/items.lua when using a QB inventory.
-- This file is also valid standalone Lua for release syntax checks.

return {
    beeper = { name = 'beeper', label = '90s Beeper', weight = 220, type = 'item', image = 'beeper.png', unique = true, useable = true, shouldClose = true, description = 'A compact 1990s pager with its own persistent pager number.' },
    beeperbattery = { name = 'beeperbattery', label = 'Beeper Battery', weight = 60, type = 'item', image = 'beeperbattery.png', unique = false, useable = true, shouldClose = true, description = 'A replacement battery for a compact pager.' },
}
