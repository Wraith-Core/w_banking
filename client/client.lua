local banks
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
        if k:sub(1, 3) == 'ui.' then strings[k] = v end
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
    for bank, v in pairs(Config.BankLocations) do
        local label = locale(v.label)
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
        rec.setTitle(locale(Config.BankLocations[bank].label))
        rec.setLabel(Config.Prompt.key, locale('prompt.open'))
    end
    for bank, blip in pairs(BankBlips) do
        w.blip.setName(blip, locale(Config.BankLocations[bank].label))
    end
end

-- Remove Peds / Blips / Prompts --
local function BankCleanup()
    clearInteractions()
    for bank in pairs(Config.BankLocations) do
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

-- Open Bank UI -- InBank is raised before the server round trip so a second prompt
-- completion (or event) during the wait cannot open the page twice.
function openAccountScreen()
    if InBank then return end
    InBank = true

    local banking = w.callback.triggerServer('w_banking:getBankingInformation')
    if not banking then
        InBank = false
        return
    end

    SetNuiFocus(true, true)

    local payload = nuiLocalePayload()
    payload.status = 'openbank'
    payload.information = banking
    SendNUIMessage(payload)
end
exports('openAccountScreen', openAccountScreen)

-- Threads / Startup --
local function CreateBanks()
    for bank, v in pairs(Config.BankLocations) do
        if BankPed[bank] == nil then BankPed[bank] = spawnClerk(Config.ClerkModel, v.coords) end
    end
    buildInteractions()
end

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
    openAccountScreen()
end)

RegisterNetEvent('w_banking:client:syncBanks', function(data)
    banks = data
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
AddEventHandler('WCore:Client:OnPlayerLoaded', function() CreateBanks() end)
AddEventHandler('WCore:Client:OnPlayerUnload', function() BankCleanup() end) -- unload, not loaded: cleanup was running right after CreateBanks
AddEventHandler('onResourceStart', function(resource) if resource ~= GetCurrentResourceName() then return end CreateBanks() end)
w.stopped(BankCleanup)
