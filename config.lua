Config = {}

Config.Debug = false
Config.Framework = 'auto' -- auto, qbox, qbcore, esx, standalone
Config.Inventory = 'auto' -- auto, ox_inventory, framework, standalone

-- ---------------------------------------------------------------------------
-- DEVICE IDENTITY
-- ---------------------------------------------------------------------------
Config.Beeper = {
    deviceLabel = 'RS BEEPER',
    networkLabel = 'LOS SANTOS PAGING',
    clock24Hour = false,
    maxVisibleRows = 3,
    maxMessageLength = 80,
    maxSenderLength = 24,
    maxCallbackLength = 24,
    maxCodeLength = 16,
    memorySlots = 20,
    defaultTone = 'classic',
    -- numeric: only numbers/*/# are accepted as the visible page body.
    -- alphanumeric: classic late-90s text pages are allowed.
    -- mixed: accepts both and leaves presentation to the sending integration.
    mode = 'mixed'
}

-- The pager is usable without an inventory item by default. 90s RP servers that
-- want a physical object should enable this and register one of PagerItems.
Config.RequirePagerItem = false
Config.PagerItems = { 'beeper', 'rs_90sbeeper' }
Config.CloseWhenItemMissing = true
Config.ItemAuditInterval = 5000

-- Keep the server-side pager-number -> live-player binding healthy without
-- relying on one framework load event or one fixed join delay. This is what
-- makes a direct page to 555-xxxx actually BEEP even when character selection
-- finishes later than the initial connection window.
Config.Binding = {
    Enabled = true,
    -- Fast authoritative retries after join/resource start. These do not trust
    -- client state; every attempt resolves the current server-side character /
    -- inventory identity again through the bridge.
    FastRetryDelaysMs = { 500, 1000, 2000, 4000, 8000, 15000 },
    -- Long-lived safety net for slow character selection, character switching,
    -- inventory readiness and source reuse. Set >= 1000ms.
    ReconcileIntervalMs = 5000,
    -- If a direct number page arrives before the periodic pass, search current
    -- server players for the authoritative owner immediately and bind them.
    RecoverOnNumberPage = true
}

Config.StandaloneInventory = {
    Resource = nil,
    HasItemExport = nil,
    HasNamedItemExport = nil,
    RemoveItemExport = nil,
    AddItemExport = nil
}

-- ---------------------------------------------------------------------------
-- KEYBIND -- off by default, on purpose
--
-- This resource ships with NO default key. Every F-key is contended on a real
-- server (F7 is fought over by five RS resources here, F8 is the FiveM console,
-- F11 is pma-voice's proximity cycle), and a default that collides is worse
-- than no default -- it fires someone else's script instead of this one.
--
-- The beeper is opened with /beeper. That always works and claims nothing.
--
-- TO ADD A KEY: set Enabled = true and pick Default. The key then registers as
-- "Open / close RS 90s Beeper" under Settings > Key Bindings > FiveM.
--
-- NOTE: a player who already bound this on an earlier version keeps their key.
-- FiveM stores each player's mapping client-side and a config change here will
-- not move it -- they have to clear it in Settings themselves.
-- ---------------------------------------------------------------------------
Config.Keybind = {
    Enabled = false,
    Default = '',
    Command = 'rs_90sbeeper_toggle',
    Description = 'Open / close RS 90s Beeper'
}

Config.Commands = {
    Open = 'beeper',
    Diagnostic = 'rs90beeperdiag',
    Recharge = 'rechargebeeper',
    Reset = 'rs90beeperreset',
    -- Self-only server-owner smoke test. Disable for production if desired.
    TestPage = 'rs90pagertest'
}

Config.Numbering = {
    -- Generated pager numbers are persistent. Change Format before launch if you
    -- want a different city/era convention; do not change it after numbers are in use.
    Format = '555-%04d',
    Start = 1000,
    Finish = 9999,
    CapcodeDigits = 7
}

Config.Persistence = {
    Enabled = true,
    File = 'data/pagers.json',
    SaveDebounceMs = 800,
    DeviceMetadataKey = 'rs90BeeperId'
}

-- ---------------------------------------------------------------------------
-- POWER / SIGNAL
-- ---------------------------------------------------------------------------
Config.Battery = {
    Enabled = true,
    -- 'auto' consumes a battery item when a real inventory integration exists,
    -- but keeps pure Standalone installs dependency-free by treating /rechargebeeper
    -- as the RP battery-replacement action. true always requires an item; false never does.
    RequireRechargeItem = 'auto',
    StartingLevel = 100,
    -- Refill every pager to StartingLevel when the resource starts. On while no
    -- beeperbattery item exists in the live inventory: RequireRechargeItem
    -- 'auto' demands that item under ox_inventory, so without this a drained
    -- pager can never be recharged by anyone. Set false once the item is in.
    RechargeOnRestart = true,
    -- A pager should last far longer than a handheld radio. This is intentionally
    -- slow and is only simulated while the owner is online and the pager is on.
    DrainPerHour = 0.35,
    LowThreshold = 15,
    RechargeItems = { 'beeperbattery' },
    RechargeAmount = 100
}

Config.Signal = {
    Enabled = true,
    DefaultBars = 4,
    -- A server resource can call SetPlayerSignal / SetPlayerJammed. Pages received
    -- while power/signal is unavailable remain in memory and alert after service returns.
    QueueWhenUnavailable = true
}

-- ---------------------------------------------------------------------------
-- PAGER CODE CULTURE
-- ---------------------------------------------------------------------------
-- Pager codes were informal, regional and sometimes contradictory. These stock
-- entries are a curated period-flavored baseline, not a claim that every city
-- used the same dictionary. Server owners can edit/remove/add codes freely.
Config.Codebook = {
    Enabled = true,
    ShowInDevice = true,
    AutoShowMeaning = false, -- false keeps incoming pages authentic: the player decodes it.
    Entries = {
        { code = '07',    meaning = 'JUST KIDDING',          category = 'SOCIAL' },
        { code = '14',    meaning = 'HI',                    category = 'SOCIAL' },
        { code = '23',    meaning = 'TE AMO',                category = 'LOVE' },
        { code = '26',    meaning = 'TE QUIERO',             category = 'LOVE' },
        { code = '45',    meaning = 'GOODNIGHT',             category = 'SOCIAL' },
        { code = '56',    meaning = 'SWEET DREAMS',          category = 'LOVE' },
        { code = '77',    meaning = 'FRIENDS FOREVER',       category = 'SOCIAL' },
        { code = '99',    meaning = 'NIGHT NIGHT',           category = 'SOCIAL' },
        { code = '123',          meaning = 'I MISS YOU',            category = 'LOVE' },
        { code = '143',          meaning = 'I LOVE YOU',            category = 'LOVE' },
        { code = '193',          meaning = 'MISS ME?',              category = 'LOVE' },
        { code = '303',          meaning = 'STOP PLAYING',          category = 'SOCIAL' },
        { code = '333',          meaning = 'LOVE',                  category = 'LOVE' },
        { code = '411',          meaning = 'QUESTION / INFO',       category = 'UTILITY' },
        { code = '423',          meaning = 'CALL ME',               category = 'CALLBACK' },
        { code = '424',          meaning = 'CALL ME BACK',          category = 'CALLBACK' },
        { code = '477',          meaning = 'BEST FRIENDS FOREVER',  category = 'SOCIAL' },
        { code = '637',          meaning = 'ALWAYS AND FOREVER',    category = 'LOVE' },
        { code = '823',          meaning = 'THINKING OF YOU',       category = 'LOVE' },
        { code = '831',          meaning = 'I LOVE YOU',            category = 'LOVE' },
        { code = '911',          meaning = 'EMERGENCY / CALL NOW',  category = 'EMERGENCY', priority = 'emergency' },
        { code = '1517',         meaning = 'KEEP IN TOUCH',         category = 'SOCIAL' },
        { code = '187',          meaning = 'HATE / MURDER / DEATH', category = 'STREET' },
        { code = '07734',        meaning = 'HELLO (UPSIDE DOWN)',   category = 'CALCULATOR' },
        { code = '50538',        meaning = 'BESOS (UPSIDE DOWN)',   category = 'CALCULATOR' },
        { code = '6000*843',     meaning = 'GOOD BYE',              category = 'CALCULATOR' },
        { code = '1*177155*400', meaning = 'I MISS YOU',            category = 'CALCULATOR' },
        { code = '6000*171647',  meaning = 'GOOD NIGHT',            category = 'CALCULATOR' },
        { code = '60*401773',    meaning = 'GO HOME',               category = 'CALCULATOR' },
        { code = '41*705312',    meaning = 'HI LOSER',              category = 'CALCULATOR' },
    }
}

-- Optional organization aliases. These do not create dependencies. They are just
-- convenient server-side route definitions for SendPageToDepartment().
Config.Departments = {
    police = { type = 'jobs', names = { 'police', 'sheriff' }, dutyOnly = true },
    ems = { type = 'jobs', names = { 'ambulance', 'ems', 'doctor' }, dutyOnly = true },
    fire = { type = 'jobs', names = { 'fire' }, dutyOnly = true },
    services = { type = 'jobs', names = { 'mechanic', 'taxi', 'tow' }, dutyOnly = false }
}

-- Manual hidden groups are intentionally independent of framework jobs/gangs.
-- Another resource can call SetPlayerPagerGroup(source, 'cartel', true), then page
-- that group through SendPageToGroup('cartel', {...}).
Config.Groups = {
    -- cartel = { label = 'CARTEL' },
    -- detectives = { label = 'DETECTIVES' }
}

-- ---------------------------------------------------------------------------
-- PROFILE / UI
-- ---------------------------------------------------------------------------
Config.Profile = {
    Default = {
        tone = 'classic',
        vibrate = true,
        silent = false,
        codeHints = false,
        uiScale = 100,
        uiX = 55,
        uiY = 38
    },
    ScaleMin = 75,
    ScaleMax = 120
}

Config.UI = {
    KeepGameInput = true,
    AllowMovement = true
}

-- The lifecycle manager is ready for a custom pager prop/animation, but the base
-- package does not pretend GTA's handheld radio prop is a pager. Enable this only
-- after configuring an appropriate animation/prop for your server.
Config.Animation = {
    Enabled = false,
    Dict = nil,
    Clip = nil,
    Flag = 49,
    UseProp = false,
    PropModel = nil,
    PropBone = 60309,
    PropOffset = vector3(0.0, 0.0, 0.0),
    PropRotation = vector3(0.0, 0.0, 0.0)
}

Config.Security = {
    OpenCooldownMs = 300,
    RpcMinIntervalMs = 100,
    MaxExternalPagesPerMinutePerResource = 180,
    MaxRoutesPerPage = 256,
    MaxManualGroupsPerPlayer = 32
}

Config.Locale = {
    no_item = 'You need a working beeper in your inventory.',
    pager_item_unregistered = 'RS 90s Beeper is running, but no configured beeper item is registered.',
    inventory_not_ready = 'Your inventory is still loading. Try the beeper again.',
    battery_dead = 'Your beeper battery is dead.',
    battery_low = 'Beeper battery low.',
    recharged = 'Beeper battery replaced: %d%%.',
    memory_full = 'Beeper memory is full. Unlock or delete a saved page.',
    page_received = 'Your beeper goes off.',
    signal_lost = 'NO SERVICE',
    signal_restored = 'Beeper service restored.',
    profile_reset = 'Beeper settings reset.',
    denied = 'Beeper request denied.',
    not_found = 'Pager not found.',
    -- Every refusal the server can hand back needs a line here. locale() falls
    -- through to the key when one is missing, so a gap does not throw -- it
    -- shows the player the raw string "rate_limited", which reads like a crash
    -- instead of a rule.
    locked = 'That page is locked. Unlock it before deleting.',
    rate_limited = 'The beeper is still catching up. Wait a moment.',
    no_battery_item = 'You need a beeper battery to recharge.',
    player_missing = 'Beeper not ready yet. Try again in a moment.',
    unknown_action = 'That beeper function is not available.',
    missing_action = 'That beeper function is not available.',
    invalid_response = 'The paging network returned a bad response.',
    timeout = 'The paging network did not answer. Try again.'
}

-- Communication events.
--
-- Any server script can raise one with:
--   TriggerEvent('rs-comms:dispatch', { ... })
--
-- The pager renders it as a page. It ignores events addressed only to radio
-- channels, because a pager has no channels -- that is intended, not a gap.
-- routine | priority | urgent | emergency
Config.CommEvents = {
    Enabled = true,
    MinPriority = 'routine',
}
