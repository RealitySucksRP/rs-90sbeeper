local Bridge = RSPagerClientBridge

local pagerOpen = false
-- An open is a server round trip. Without a pending flag and a serial, a slow
-- reply can arrive AFTER the player closed and reopen the pager on its own --
-- the serial is what lets a close invalidate a reply that is already in flight.
-- Not a keybind problem: /beeper reaches the same path.
local openPending = false
local openSerial = 0
local currentState = nil
local pendingRpc = {}
local rpcCounter = 0
local keyClosePending = false

local function locale(key, ...)
    local value = (Config.Locale and Config.Locale[key]) or key
    if select('#', ...) > 0 then
        local ok, formatted = pcall(string.format, value, ...)
        if ok then return formatted end
    end
    return value
end

local function send(action, payload)
    SendNUIMessage({ action = action, data = payload or {} })
end

-- ---------------------------------------------------------------------------
-- Granular state bags
--
-- Other resources -- a HUD, a job script, a phone -- frequently want to know
-- "does this player have unread pages" or "is the pager dead" without opening a
-- round trip to this resource. Publishing narrow, named keys is the documented
-- RS pattern (radio:talking, radio:channel, device:jammed), deliberately instead
-- of replicating one large device object: a reader subscribes to just the key it
-- cares about, and a change to one field does not invalidate all of them.
--
-- These are LOCAL convenience/UI hints only. Other resources running on the
-- same client can read them without an RPC, but they are intentionally not
-- replicated citywide. Server gameplay must use rs-90sbeeper exports/server
-- routing and must never authorize from client-written state bags.
-- ---------------------------------------------------------------------------
local function publishPagerState()
    if not (LocalPlayer and LocalPlayer.state) then return end
    local st = currentState or {}
    local ok = pcall(function()
        LocalPlayer.state:set('pager:has', st.number ~= nil, false)
        LocalPlayer.state:set('pager:unread', tonumber(st.unread) or 0, false)
        LocalPlayer.state:set('pager:battery', tonumber(st.battery) or 0, false)
    end)
    if not ok then return end
end

local function setUiOwnership(active)
    if LocalPlayer and LocalPlayer.state then
        LocalPlayer.state:set('rsBeeperUiOpen', active == true, false)
        LocalPlayer.state:set('rsUiOpen', active == true, false)
    end
end

-- ---------------------------------------------------------------------------
-- Pose
--
-- Handed to the shared DevicePoseManager (client/pose.lua), the same file
-- rs-radio and rs-tablet use, byte for byte.
--
-- The inline version this replaces had a race it could not win. startPose()
-- YIELDED while waiting for the anim dictionary, and never re-checked anything
-- afterwards -- so closing the pager during that load ran stopPose() first, and
-- then the in-flight startPose() woke up and played the animation anyway. The
-- player was left holding a pose for a device that was no longer on screen, and
-- nothing would clear it until the next open/close.
--
-- The manager solves exactly that with an explicit CLOSED -> OPENING -> ACTIVE
-- -> CLOSING machine where every stage re-checks a token, so a close during
-- OPENING cannot be overtaken. It also brings the context policy the inline
-- version never had -- vehicle, ragdoll, swimming, climbing, cuffed, dead --
-- plus teardown on unload, logout, death and resource stop.
--
-- Mapping note: this device configures a single looping Clip, while the manager
-- takes Enter + Loop. Enter is optional and guarded throughout, so the pager's
-- clip is the Loop and there is no enter blend -- which is right for a pager
-- anyway: it comes off the belt and stays in one read pose.
-- ---------------------------------------------------------------------------
local Pose = RSDevicePose

Pose.Configure({
    Enabled = Config.Animation.Enabled,
    Dict = Config.Animation.Dict,
    Enter = nil,
    Loop = Config.Animation.Clip,
    LoopFlag = Config.Animation.Flag or 49,
    UseProp = Config.Animation.UseProp,
    PropModel = Config.Animation.PropModel,
    PropBone = Config.Animation.PropBone,
    PropOffset = Config.Animation.PropOffset,
    PropRotation = Config.Animation.PropRotation,
    Context = {
        -- A pager is read one-handed off the belt, so unlike the radio it is
        -- fine as a passenger AND while driving is still blocked by the shared
        -- default. Physical-state rules come from the shared defaults.
        Vehicle = 'allow',
        Driver = 'block',
    },
})

-- The manager asks this before raising or holding the pose, and re-asks it on
-- every context change. Pushing state at it would reintroduce the drift the
-- inline version had, where `poseActive` could disagree with `pagerOpen`.
Pose.SetWanted(function()
    return pagerOpen == true
end)

local function stopPose()
    Pose.Close()
end

local function startPose()
    -- The manager pulls state through SetWanted below rather than being pushed,
    -- so opening is just a re-evaluation.
    Pose.Refresh()
end

local function setFocus(active)
    pagerOpen = active == true
    setUiOwnership(pagerOpen)
    if pagerOpen then
        SetNuiFocus(true, true)
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(Config.UI.KeepGameInput == true) end
    else
        -- Release keep-input before dropping NUI focus. This mirrors the radio
        -- F-key crash fix and avoids tearing down focus while CEF is still
        -- dispatching the same key event.
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
        SetNuiFocus(false, false)
    end
    send('visible', { visible = pagerOpen })
    if pagerOpen then startPose() else stopPose() end
end

local function closeBeeper()
    keyClosePending = false
    -- Invalidate any open still in flight, so its reply is discarded instead of
    -- reopening the device the player just dismissed.
    openPending = false
    openSerial = openSerial + 1
    if not pagerOpen then
        setUiOwnership(false)
        stopPose()
        return
    end
    setFocus(false)
end

local function requestKeyClose()
    -- Key-mapped close must not destroy NUI focus synchronously from the raw
    -- key command while CEF is still processing that same F-key. Ask the UI to
    -- close itself so it uses the same callback path as ESC/X, then keep a small
    -- fallback for a broken or unloaded page.
    if not pagerOpen then
        if openPending then closeBeeper() end
        return
    end
    if keyClosePending then return end
    keyClosePending = true
    send('requestClose', { reason = 'key' })
    SetTimeout(750, function()
        if keyClosePending then closeBeeper() end
    end)
end

local function openBeeper()
    if pagerOpen or openPending then return end
    openPending = true
    openSerial = openSerial + 1
    local serial = openSerial
    -- Round-trip this serial through the server. A local pending flag alone is
    -- insufficient: response A can arrive after its timeout while request B is
    -- pending, and must not be mistaken for B's response.
    TriggerServerEvent('rs-90sbeeper:server:requestOpen', serial)
    -- A lost reply must not lock the device shut forever.
    SetTimeout(3000, function()
        if openPending and serial == openSerial then openPending = false end
    end)
end

local function toggleBeeper()
    -- A second toggle while the server request is in flight is a cancellation.
    -- A visible pager closes through the async NUI path so F-key teardown cannot
    -- race CEF focus/input handling on GTA V Enhanced.
    if pagerOpen then requestKeyClose()
    elseif openPending then closeBeeper()
    else openBeeper() end
end

exports('useBeeper', openBeeper)
exports('OpenBeeper', openBeeper)
exports('CloseBeeper', closeBeeper)
exports('ToggleBeeper', toggleBeeper)
exports('RechargeBeeper', function() TriggerServerEvent('rs-90sbeeper:server:recharge') end)

RegisterNetEvent('rs-90sbeeper:client:use', openBeeper)
RegisterNetEvent('rs-90sbeeper:client:recharge', function()
    TriggerServerEvent('rs-90sbeeper:server:recharge')
end)

if Config.Keybind and Config.Keybind.Enabled then
    RegisterCommand(Config.Keybind.Command, toggleBeeper, false)
    local defaultKey = tostring(Config.Keybind.Default or '')
    if defaultKey ~= '' then
        RegisterKeyMapping(Config.Keybind.Command, Config.Keybind.Description or 'Open / close RS 90s Beeper', 'keyboard', defaultKey)
    else
        print('^3[rs-90sbeeper] Config.Keybind.Enabled is true but Config.Keybind.Default is blank; command registered without a default key.^7')
    end
end

if Config.Commands and Config.Commands.Open then
    RegisterCommand(Config.Commands.Open, toggleBeeper, false)
end

RegisterNetEvent('rs-90sbeeper:client:open', function(state, requestSerial)
    -- The request serial distinguishes the current reply from an older reply
    -- that arrived after timing out or after the player cancelled it.
    if not openPending or tonumber(requestSerial) ~= openSerial then return end
    openPending = false
    currentState = type(state) == 'table' and state or {}
    send('state', currentState)
    publishPagerState()
    setFocus(true)
end)

RegisterNetEvent('rs-90sbeeper:client:stateSync', function(state)
    currentState = type(state) == 'table' and state or currentState
    send('state', currentState or {})
    publishPagerState()
end)

RegisterNetEvent('rs-90sbeeper:client:incoming', function(message, summary)
    summary = type(summary) == 'table' and summary or {}
    if currentState then
        currentState.unread = summary.unread or currentState.unread
        currentState.battery = summary.battery or currentState.battery
        currentState.signal = summary.signal or currentState.signal
    end
    send('incoming', { message = message or {}, summary = summary })
    -- A new page is the single most important moment for pager:unread -- this is
    -- what a HUD is watching for.
    publishPagerState()
end)

RegisterNetEvent('rs-90sbeeper:client:pending', function(count, latest, summary)
    summary = type(summary) == 'table' and summary or {}
    if currentState then
        currentState.unread = summary.unread or currentState.unread
        currentState.signal = summary.signal or currentState.signal
    end
    send('pending', { count = tonumber(count) or 0, message = latest or {}, summary = summary })
    publishPagerState()
end)

RegisterNetEvent('rs-90sbeeper:client:signal', function(signal)
    if currentState then currentState.signal = signal end
    send('signal', signal or {})
end)

RegisterNetEvent('rs-90sbeeper:client:battery', function(level, recharged)
    if currentState then currentState.battery = tonumber(level) or currentState.battery end
    send('battery', { battery = tonumber(level) or 0, recharged = recharged == true })
    publishPagerState()
    if recharged then Bridge.Notify(locale('recharged', tonumber(level) or 0), 'success') end
end)

RegisterNetEvent('rs-90sbeeper:client:notice', function(key, kind)
    Bridge.Notify(locale(key), kind or 'inform')
end)

RegisterNetEvent('rs-90sbeeper:client:denied', function(reason, requestSerial)
    -- Only open-request denials carry a serial. Recharge/diagnostic denials keep
    -- their existing one-argument contract and must not cancel an unrelated open.
    if requestSerial ~= nil then
        if not openPending or tonumber(requestSerial) ~= openSerial then return end
        openPending = false
    end
    local key = tostring(reason or 'denied')
    if key == 'no_battery_item' then
        Bridge.Notify('You need a beeper battery.', 'error')
    else
        Bridge.Notify(locale(key), 'error')
    end
    send('denied', { reason = key })
end)

RegisterNetEvent('rs-90sbeeper:client:forceClose', function(reason)
    closeBeeper()
    if reason then Bridge.Notify(locale(reason), 'error') end
end)

RegisterNetEvent('rs-90sbeeper:client:diagnostics', function(data)
    data = type(data) == 'table' and data or {}
    local pager = data.pager or {}
    local signal = pager.signal or {}
    local binding = data.binding or {}
    local producers = type(data.producers) == 'table' and data.producers or {}
    local producerNames = {}
    for _, producer in ipairs(producers) do
        producerNames[#producerNames + 1] = ('%s(%s)'):format(tostring(producer.resource or '?'), tostring(producer.calls or 0))
    end
    local lines = {
        ('Framework: %s'):format(tostring(data.framework or 'unknown')),
        ('Inventory: %s'):format(tostring(data.inventory or 'unknown')),
        ('Persistence: %s'):format(tostring(data.persistence or 'unknown')),
        ('Comm protocol: v%s'):format(tostring(data.commProtocol or '?')),
        ('Comm bus: %s'):format(tostring(data.commBus or 'rs-comms:dispatch')),
        ('Live binding: %s | Device: %s'):format(binding.bound == true and 'YES' or 'NO', tostring(binding.deviceId or '-')),
        ('Binding checks: attempts=%s reconcile=%s recovery=%s last=%s/%s'):format(
            tostring(binding.attempts or 0), tostring(binding.reconciles or 0), tostring(binding.recoveries or 0),
            tostring(binding.lastCause or '-'), tostring(binding.lastReason or '-')
        ),
        ('Pager: %s'):format(tostring(pager.number or data.error or 'unavailable')),
        ('Capcode: %s'):format(tostring(pager.capcode or '-')),
        ('Power: %s'):format(pager.powered == false and 'OFF' or 'ON'),
        ('Battery: %s%%'):format(tostring(pager.battery or '-')),
        ('Signal: %s/4 %s'):format(tostring(signal.bars or 0), tostring(signal.reason or '')),
        ('Inbox: %s (%s unread / %s locked)'):format(tostring(pager.messages or 0), tostring(pager.unread or 0), tostring(pager.locked or 0)),
        ('Groups: %s'):format(#(pager.groups or {}) > 0 and table.concat(pager.groups, ',') or 'none'),
        ('External producers seen this boot: %s'):format(#producerNames > 0 and table.concat(producerNames, ', ') or 'NONE')
    }
    print('^5[rs-90sbeeper diagnostics]^7')
    for _, line in ipairs(lines) do print(('  %s'):format(line)) end
    local summary = ('Pager %s | Bound %s | Comm v%s | Producers seen %s'):format(
        tostring(pager.number or data.error or 'unavailable'),
        binding.bound == true and 'YES' or 'NO',
        tostring(data.commProtocol or '?'),
        tostring(#producers)
    )
    Bridge.Notify(summary, data.pager and binding.bound == true and 'success' or 'error')
end)

RegisterNetEvent('rs-90sbeeper:client:rpcResult', function(requestId, response)
    local pending = pendingRpc[tostring(requestId or '')]
    if not pending then return end
    pendingRpc[tostring(requestId)] = nil
    pending.cb(type(response) == 'table' and response or { ok = false, error = 'invalid_response' })
end)

local function nextRequestId()
    rpcCounter = (rpcCounter + 1) % 1000000
    return ('%d-%d'):format(GetGameTimer(), rpcCounter)
end

RegisterNUICallback('rpc', function(request, cb)
    request = type(request) == 'table' and request or {}
    local action = tostring(request.action or '')
    local requestId = tostring(request.requestId or nextRequestId())
    local payload = type(request.payload) == 'table' and request.payload or {}

    if action == '' then cb({ ok = false, error = 'missing_action' }) return end

    if action == 'ui.close' then
        keyClosePending = false
        closeBeeper()
        cb({ ok = true })
        return
    end

    if action == 'ui.move' then
        cb({ ok = true })
        return
    end

    pendingRpc[requestId] = { cb = cb, expires = GetGameTimer() + 8000 }
    TriggerServerEvent('rs-90sbeeper:server:rpc', requestId, action, payload)
end)

CreateThread(function()
    while true do
        Wait(250)
        local now = GetGameTimer()
        for requestId, pending in pairs(pendingRpc) do
            if now >= pending.expires then
                pendingRpc[requestId] = nil
                pending.cb({ ok = false, error = 'timeout' })
            end
        end
    end
end)

CreateThread(function()
    while true do
        if pagerOpen then
            Wait(0)
            local ped = PlayerPedId()
            if not ped or ped <= 0 or IsEntityDead(ped) then
                closeBeeper()
            elseif Config.UI.KeepGameInput then
                DisableControlAction(0, 24, true) -- attack
                DisableControlAction(0, 25, true) -- aim
                DisableControlAction(0, 37, true) -- weapon wheel
                DisableControlAction(0, 200, true) -- pause / escape consumed by NUI
            end
        else
            Wait(300)
        end
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    setUiOwnership(false)
    send('visible', { visible = false })
end)

local function forceCloseForUnload()
    keyClosePending = false
    closeBeeper()
    -- Belt-and-suspenders cleanup for character selectors/framework reloads: if
    -- focus was already desynced, force it down even when pagerOpen was false.
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SetNuiFocus(false, false)
    setUiOwnership(false)
    stopPose()
    send('visible', { visible = false })
end

RegisterNetEvent('QBCore:Client:OnPlayerUnload', forceCloseForUnload)
RegisterNetEvent('qbx_core:client:playerLoggedOut', forceCloseForUnload)
RegisterNetEvent('esx:onPlayerLogout', forceCloseForUnload)
RegisterNetEvent('esx:playerLogout', forceCloseForUnload)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    keyClosePending = false
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SetNuiFocus(false, false)
    setUiOwnership(false)
    stopPose()
end)
