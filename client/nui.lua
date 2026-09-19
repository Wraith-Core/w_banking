local function closeBank()
    InBank = false
    SetNuiFocus(false, false)
    SendNUIMessage({ status = 'closebank' })
end

local function validAmount(amount)
    local n = tonumber(amount)
    return n ~= nil and n > 0
end

RegisterNUICallback('NUIFocusOff', function(_, cb)
    closeBank()
    cb('ok')
end)

RegisterNUICallback('createSavingsAccount', function(_, cb)
    TriggerServerEvent('w_banking:createSavingsAccount')
    cb('ok')
end)

RegisterNUICallback('doDeposit', function(data, cb)
    if validAmount(data.amount) then
        TriggerServerEvent('w_banking:doQuickDeposit', data.amount)
    end
    cb('ok')
end)

RegisterNUICallback('doWithdraw', function(data, cb)
    if validAmount(data.amount) then
        TriggerServerEvent('w_banking:doQuickWithdraw', data.amount)
    end
    cb('ok')
end)

RegisterNUICallback('savingsDeposit', function(data, cb)
    if validAmount(data.amount) then
        TriggerServerEvent('w_banking:savingsDeposit', data.amount)
    end
    cb('ok')
end)

RegisterNUICallback('savingsWithdraw', function(data, cb)
    if validAmount(data.amount) then
        TriggerServerEvent('w_banking:savingsWithdraw', data.amount)
    end
    cb('ok')
end)

RegisterNUICallback('doTransfer', function(data, cb)
    if data and validAmount(data.amount) and data.account then
        TriggerServerEvent('w_banking:initiateTransfer', data)
    end
    cb('ok')
end)
