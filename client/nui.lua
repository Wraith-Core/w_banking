function CloseBank()
    InBank = false
    SetNuiFocus(false, false)
    SendNUIMessage({ status = 'closebank' })
end
RegisterNUICallback('NUIFocusOff', function(_, cb) CloseBank(); cb({ok=true}) end)
for _, action in ipairs({'createSavingsAccount','doDeposit','doWithdraw','savingsDeposit','savingsWithdraw','doTransfer'}) do
    RegisterNUICallback(action, function(data, cb)
        if not InBank then return cb({ok=false,message=locale('msg.near_bank')}) end
        local ok, result = pcall(w.callback.triggerServer, 'w_banking:transaction', action, type(data)=='table' and data or {})
        if not ok or type(result)~='table' then result={ok=false,key='msg.failed'} end
        result.message = locale(result.key or 'msg.failed', table.unpack(result.args or {}))
        cb(result)
    end)
end
RegisterNUICallback('refresh', function(_,cb)
    local ok, data = pcall(w.callback.triggerServer,'w_banking:getBankingInformation')
    cb({ok=ok and data~=nil,information=ok and data or nil})
end)

RegisterNUICallback('central',function(_,cb)
    CloseBank()
    exports.w_lib:EconOpen()
    cb({ok=true})
end)
