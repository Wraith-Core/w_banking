local banks = Config.BankLocations
local CreateBanks
local BankPed = {}
local BankBlips = {}
local BankPrompts = {}          -- bank index → library prompt record
InBank = false
local openAccountScreen

-- Dictionary subset the NUI page renders (every 'ui.*' key), plus the layout direction.
local function nuiLocalePayload()
    local key = w.getLocaleKey()
    if key ~= 'ar' then key = 'en' end
    local strings = {}
    for k, v in pairs(w.getLocales()) do
        if k:sub(1, 3) == 'ui.' or k:sub(1, 4) == 'nui.' then strings[k] = v end
    end
    return { locale = key, dir = (key == 'ar') and 'rtl' or 'ltr', strings = strings }
end

-- Prompts and blips carry translated labels: built separately so a language switch
-- can relabel them without touching the clerk peds.
local function clearInteractions()
    for bank, rec in pairs(BankPrompts) do
        rec.remove()
        BankPrompts[bank] = nil
    end
    for bank, blip in pairs(BankBlips) do
        w.blip.remove(blip)
        BankBlips[bank] = nil
    end
end

-- The counter prompt: one library proximity prompt in front of each clerk. It hides while
-- the banking page has focus (canInteract) and comes back once the page is closed.
local function createCounterPrompt(bank, label)
    local promptCoords = GetOffsetFromEntityInWorldCoords(BankPed[bank], 0.0, 3.0, 0.0) -- 3 units in front of the clerk
    return w.prompt.at({
        coords = vector3(promptCoords.x, promptCoords.y, promptCoords.z),
        distance = Config.Prompt.distance,
        title = label,
        prompts = {
            {
                key = Config.Prompt.key,
                label = locale('prompt.open'),
                hold = false,
                onComplete = function() openAccountScreen() end,
            },
        },
        canInteract = function() return not InBank end,
    })
end

local function buildInteractions()
    for bank, v in pairs(banks) do
        local label = (v.label:sub(1,5)=='bank.' and locale(v.label) or v.label)
        if BankPed[bank] and not BankPrompts[bank] then
            BankPrompts[bank] = createCounterPrompt(bank, label)
        end
        if v.showblip and not BankBlips[bank] then
            BankBlips[bank] = w.blip.create(v.coords, label, Config.Blip.sprite, nil, nil, Config.Blip.scale)
        end
    end
end

-- Language switch: relabel the prompts and the blips in place.
local function relabelInteractions()
    for bank, rec in pairs(BankPrompts) do
        rec.setTitle((banks[bank].label:sub(1,5)=='bank.' and locale(banks[bank].label) or banks[bank].label))
        rec.setLabel(Config.Prompt.key, locale('prompt.open'))
    end
    for bank, blip in pairs(BankBlips) do
        w.blip.setName(blip, (banks[bank].label:sub(1,5)=='bank.' and locale(banks[bank].label) or banks[bank].label))
    end
end

-- Remove Peds / Blips / Prompts --
local function BankCleanup()
    clearInteractions()
    for bank in pairs(banks) do
        if BankPed[bank] ~= nil then
            w.entity.delete(BankPed[bank])
            BankPed[bank] = nil
        end
    end
end

-- Spawn the bank clerk: the library streams the model and creates the ped, the
-- counter-specific flags (frozen, invincible, ignores the player) are applied after.
local function spawnClerk(model, coords)
    local pedId = w.entity.create(model, vector4(coords.x, coords.y, coords.z - 1.0, coords.w))
    if not pedId then return nil end

    FreezeEntityPosition(pedId, true)
    SetEntityInvincible(pedId, true)
    TaskStandStill(pedId, -1)
    SetBlockingOfNonTemporaryEvents(pedId, true)
    -- SET_PED_RELATIONSHIP_GROUP_HASH(ped, GET_DEFAULT_RELATIONSHIP_GROUP_HASH(model))
    Citizen.InvokeNative(0xC80A74AC829DDD92, pedId, Citizen.InvokeNative(0x3CC4A718C258BDD0, joaat(model)))
    SetEntityCanBeDamagedByRelationshipGroup(pedId, false, `PLAYER`)
    SetEntityAsMissionEntity(pedId, true, true)
    return pedId
end

-- The counter's name for the page's first sentence («رصيدك … في بنك فالنتاين»): the bank whose clerk stands
-- nearest (within 30 m), in the player's language; nil when none is near (the page then says only "the bank").
local function nearestBankName()
    local ok, name = pcall(function()
        local me = GetEntityCoords(PlayerPedId())
        local best, bestDist = nil, 30.0
        for _, v in pairs(banks or {}) do
            local c = type(v) == 'table' and v.coords
            if c and c.x and c.y and c.z then
                local d = #(me - vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0))
                if d < bestDist and type(v.label) == 'string' and v.label ~= '' then best, bestDist = v, d end
            end
        end
        if not best then return nil end
        return best.label:sub(1, 5) == 'bank.' and locale(best.label) or best.label
    end)
    return ok and name or nil
end

-- Open Bank UI -- InBank is raised before the server round trip so a second prompt
-- completion (or event) during the wait cannot open the page twice.
function openAccountScreen(refresh)
    if InBank and not refresh then return end
    InBank = true

    local ok, banking = pcall(w.callback.triggerServer, 'w_banking:getBankingInformation')
    if not ok or not banking then
        InBank = false
        return
    end

    SetNuiFocus(true, true)

    local payload = nuiLocalePayload()
    payload.status = 'openbank'
    payload.information = banking
    payload.bankName = nearestBankName()
    SendNUIMessage(payload)
end
exports('openAccountScreen', openAccountScreen)

-- A bank whose teller is held up (w_heists 1.1.0): the heist's own networked teller stands in his place, in his
-- model, so ours and the counter prompt go until the run is over (GlobalState['w_heists:robbed'].banks[<branch id>]).
local function robbed(v)
    local r = GlobalState['w_heists:robbed']
    return type(v) == 'table' and v.id ~= nil and type(r) == 'table' and type(r.banks) == 'table' and r.banks[tostring(v.id)] == true
end

-- Threads / Startup --
CreateBanks = function()
    for bank, v in pairs(banks) do
        if BankPed[bank] == nil and not robbed(v) then BankPed[bank] = spawnClerk(Config.ClerkModel, v.coords) end
    end
    buildInteractions()
end

local wasRobbed = {}            -- branch id → true while held up
CreateThread(function()
    while true do
        Wait(1000)
        local over = false
        for bank, v in pairs(banks or {}) do
            local id = type(v) == 'table' and v.id ~= nil and tostring(v.id) or nil
            if id and robbed(v) then
                wasRobbed[id] = true
                if BankPrompts[bank] then BankPrompts[bank].remove() BankPrompts[bank] = nil end
                if BankPed[bank] then w.entity.delete(BankPed[bank]) BankPed[bank] = nil end
            elseif id and wasRobbed[id] then
                wasRobbed[id] = nil
                over = true
            end
        end
        if over then CreateBanks() end
    end
end)

CreateThread(function()
    for _, v in pairs(Config.BankDoors) do
        Citizen.InvokeNative(0xD99229FE93B46286, v, 1, 1, 0, 0, 0, 0)
        Citizen.InvokeNative(0x6BAB9442830C7F53, v, 0)
    end
end)

-- Language switch: the library's locale module (declared in the manifest, so its handler runs
-- first) has already reloaded the dictionary; relabel the prompts and blips, re-send the page strings.
AddEventHandler('w_lib:setLocale', function()
    relabelInteractions()
    local payload = nuiLocalePayload()
    payload.status = 'setLocale'
    SendNUIMessage(payload)
end)

-- Events --
RegisterNetEvent('w_banking:openBankScreen', function()
    if InBank then openAccountScreen(true) end
end)

RegisterNetEvent('w_banking:client:syncBanks', function(data)
    BankCleanup()
    banks = data
    CreateBanks()
end)

exports('getBanks', function() return banks or Config.BankLocations end)

-- Server sends dictionary keys (+ format args); the text is translated in the player's language here.
RegisterNetEvent('w_banking:transferError', function(key, ...)
    SendNUIMessage({ status = 'transferError', error = locale(key, ...) })
end)

RegisterNetEvent('w_banking:successAlert', function(key, ...)
    SendNUIMessage({ status = 'successMessage', message = locale(key, ...) })
end)

RegisterNetEvent('w_banking:client:notify', function(key, style, ...)
    w.notify({
        title = locale('notify.title'),
        description = locale(key, ...),
        type = style or 'inform',
        isRTL = w.getLocaleKey() == 'ar',
    })
end)

-- Resource Stop / Cleanup --
exports.w_lib:FwOnCharacterLoaded(function() CreateBanks() end)
exports.w_lib:FwOnCharacterUnloaded(function() BankCleanup() end) -- unload, not loaded: cleanup was running right after CreateBanks
AddEventHandler('onResourceStart', function(resource) if resource ~= GetCurrentResourceName() then return end CreateBanks() end)
w.stopped(function() BankCleanup(); if CloseBank then CloseBank() end end)

exports.w_lib:EconOnBranchesChanged(function(data)
    if type(data)~='table' then return end
    BankCleanup();banks=data;CreateBanks()
end)
CreateThread(function()
    Wait(1500)
    local ok,data=pcall(w.callback.triggerServer,'w_banking:branches')
    if ok and type(data)=='table' and #data>0 then BankCleanup();banks=data;CreateBanks() end
end)
