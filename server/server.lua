-- Load the stored savings and gang accounts once the wrappers are in.
CreateThread(function()
    local savings = MySQL.Sync.fetchAll('SELECT citizenid FROM bank_accounts WHERE account_type = ?', { 'Savings' })
    for _, v in pairs(savings) do
        savingsAccounts[v.citizenid] = generateSavings(v.citizenid)
    end

    local gangs = MySQL.Sync.fetchAll('SELECT gangid FROM bank_accounts WHERE account_type = ?', { 'Gang' })
    for _, v in pairs(gangs) do
        gangAccounts[v.gangid] = loadGangAccount(v.gangid)
    end
end)

-- Bank counters shared with the clients (Config.BankLocations, editable through modifyBank).
local banks = Config.BankLocations

-- Server-only: reached through the modifyBank export, never from a client.
AddEventHandler('w_banking:server:modifyBank', function(bank, k, v)
    if banks[tonumber(bank)] then
        banks[tonumber(bank)][k] = v
        TriggerClientEvent('w_banking:client:syncBanks', -1, banks)
    end
end)

exports('modifyBank', function(bank, k, v)
    TriggerEvent('w_banking:server:modifyBank', bank, k, v)
end)

exports('savings', function(cid)
    if savingsAccounts[cid] then
        return savingsAccounts[cid]
    end
end)

exports('gang', function(gid)
    if gangAccounts[gid] then
        return gangAccounts[gid]
    end
end)

-- `source` is only set inside event handlers, so the caller passes the player id explicitly.
function getCharacterName(src)
    local player = WCore.Functions.GetPlayer(src)
    if not player then return nil end
    return player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
end

local function validAmount(amount)
    local n = tonumber(amount)
    return n ~= nil and n > 0 and n == math.floor(n)
end

w.callback.register('w_banking:getBankingInformation', function(source)
    local src = source
    local player = WCore.Functions.GetPlayer(src)
    if not player then return nil end

    local savings = savingsAccounts[player.PlayerData.citizenid]
    local banking = {
        ['name'] = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname,
        ['bankbalance'] = '$' .. math.groupdigits(player.PlayerData.money['bank']),
        ['cash'] = '$' .. math.groupdigits(player.PlayerData.money['cash']),
        ['accountinfo'] = player.PlayerData.charinfo.account,
        ['savings'] = savings and { amount = '$' .. math.groupdigits(savings.GetBalance() or 0) } or nil,
    }
    return banking
end)

RegisterServerEvent('w_banking:doQuickDeposit', function(amount)
    local src = source
    local player = WCore.Functions.GetPlayer(src)
    if not player then return end
    local currentCash = player.Functions.GetMoney('cash')

    if not validAmount(amount) then return TriggerClientEvent('w_banking:transferError', src, 'msg.invalid_amount') end
    if tonumber(amount) <= currentCash then
        local cash = player.Functions.RemoveMoney('cash', tonumber(amount), 'banking-quick-depo')
        local bank = player.Functions.AddMoney('bank', tonumber(amount), 'banking-quick-depo')

        if not cash then return end
        if not bank then return end

        TriggerClientEvent('w_banking:openBankScreen', src)
        TriggerClientEvent('w_banking:successAlert', src, 'msg.deposit_success', math.groupdigits(amount))
        TriggerEvent('w_log:server:CreateLog', 'banking', 'Banking', 'lightgreen', "**"..GetPlayerName(player.PlayerData.source) .. " (citizenid: "..player.PlayerData.citizenid.." | id: "..player.PlayerData.source..")** made a cash deposit of $"..amount.." successfully.")
    else
        TriggerClientEvent('w_banking:transferError', src, 'msg.not_enough')
    end
end)

RegisterServerEvent('w_banking:doQuickWithdraw', function(amount)
    local src = source
    local player = WCore.Functions.GetPlayer(src)
    if not player then return end
    local currentCash = player.Functions.GetMoney('bank')

    if not validAmount(amount) then return TriggerClientEvent('w_banking:transferError', src, 'msg.invalid_amount') end
    if tonumber(amount) <= currentCash then
        local cash = player.Functions.RemoveMoney('bank', tonumber(amount), 'banking-quick-withdraw')
        local bank = player.Functions.AddMoney('cash', tonumber(amount), 'banking-quick-withdraw')

        if not bank then return end
        if not cash then return end

        TriggerClientEvent('w_banking:openBankScreen', src)
        TriggerClientEvent('w_banking:successAlert', src, 'msg.withdraw_success', math.groupdigits(amount))
        TriggerEvent('w_log:server:CreateLog', 'banking', 'Banking', 'red', "**"..GetPlayerName(player.PlayerData.source) .. " (citizenid: "..player.PlayerData.citizenid.." | id: "..player.PlayerData.source..")** made a cash withdrawal of $"..amount.." successfully.")
    else
        TriggerClientEvent('w_banking:transferError', src, 'msg.not_enough')
    end
end)

RegisterServerEvent('w_banking:savingsDeposit', function(amount)
    local src = source
    local player = WCore.Functions.GetPlayer(src)
    if not player then return end
    local currentBank = player.Functions.GetMoney('bank')
    local account = savingsAccounts[player.PlayerData.citizenid]

    if not account then return TriggerClientEvent('w_banking:transferError', src, 'msg.no_savings') end
    if not validAmount(amount) then return TriggerClientEvent('w_banking:transferError', src, 'msg.invalid_amount') end
    if tonumber(amount) <= currentBank then
        local bank = player.Functions.RemoveMoney('bank', tonumber(amount), 'banking-savings-deposit')
        if not bank then return end
        local savings = account.AddMoney(tonumber(amount), 'Bank to Savings Transfer')
        if not savings then
            player.Functions.AddMoney('bank', tonumber(amount), 'banking-savings-deposit-refund')
            return
        end

        TriggerClientEvent('w_banking:openBankScreen', src)
        TriggerClientEvent('w_banking:successAlert', src, 'msg.savings_deposit_success', math.groupdigits(amount))
        TriggerEvent('w_log:server:CreateLog', 'banking', 'Banking', 'lightgreen', "**"..GetPlayerName(player.PlayerData.source) .. " (citizenid: "..player.PlayerData.citizenid.." | id: "..player.PlayerData.source..")** made a savings deposit of $"..tostring(amount).." successfully.")
    else
        TriggerClientEvent('w_banking:transferError', src, 'msg.not_enough')
    end
end)

RegisterServerEvent('w_banking:savingsWithdraw', function(amount)
    local src = source
    local player = WCore.Functions.GetPlayer(src)
    if not player then return end
    local account = savingsAccounts[player.PlayerData.citizenid]

    if not account then return TriggerClientEvent('w_banking:transferError', src, 'msg.no_savings') end
    if not validAmount(amount) then return TriggerClientEvent('w_banking:transferError', src, 'msg.invalid_amount') end
    if tonumber(amount) <= (account.GetBalance() or 0) then
        local savings = account.RemoveMoney(tonumber(amount), 'Savings to Bank Transfer')
        if not savings then return end
        local bank = player.Functions.AddMoney('bank', tonumber(amount), 'banking-savings-withdraw')
        if not bank then return end

        TriggerClientEvent('w_banking:openBankScreen', src)
        TriggerClientEvent('w_banking:successAlert', src, 'msg.savings_withdraw_success', math.groupdigits(amount))
        TriggerEvent('w_log:server:CreateLog', 'banking', 'Banking', 'red', "**"..GetPlayerName(player.PlayerData.source) .. " (citizenid: "..player.PlayerData.citizenid.." | id: "..player.PlayerData.source..")** made a savings withdrawal of $"..tostring(amount).." successfully.")
    else
        TriggerClientEvent('w_banking:transferError', src, 'msg.not_enough')
    end
end)

RegisterServerEvent('w_banking:createSavingsAccount', function()
    local src = source
    local player = WCore.Functions.GetPlayer(src)
    if not player then return end
    local success = createSavingsAccount(player.PlayerData.citizenid)

    if not success then return TriggerClientEvent('w_banking:transferError', src, 'msg.savings_exists') end
    TriggerClientEvent('w_banking:openBankScreen', src)
    TriggerClientEvent('w_banking:successAlert', src, 'msg.savings_opened')
    TriggerEvent('w_log:server:CreateLog', 'banking', 'Banking', "lightgreen", "**"..GetPlayerName(player.PlayerData.source) .. " (citizenid: "..player.PlayerData.citizenid.." | id: "..player.PlayerData.source..")** opened a savings account")
end)

-- Notification in the player's own language: the client translates the key with its arguments.
local function notify(src, key, style, ...)
    TriggerClientEvent('w_banking:client:notify', src, key, style, ...)
end

w.addCommand('givecash', {
    help = locale('cmd.givecash'),
    params = {
        -- untyped on purpose: the handler validates and answers the player in his language
        { name = 'id', help = locale('cmd.givecash_id') },
        { name = 'amount', help = locale('cmd.givecash_amount') }
    }
}, function(source, args)
    local src = source
    local id = tonumber(args.id)
    local amount = tonumber(args.amount) and math.ceil(tonumber(args.amount)) or nil

    if not id or not amount or amount <= 0 then return notify(src, 'notify.usage_givecash', 'error') end

    local player = WCore.Functions.GetPlayer(src)
    local otherPlayer = WCore.Functions.GetPlayer(id)

    if player and otherPlayer and id ~= src then
        if player.PlayerData.metadata.isdead then return notify(src, 'notify.dead', 'error') end

        local distance = player.PlayerData.metadata.inlaststand and 3.0 or 10.0
        if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(id))) > distance then return notify(src, 'notify.too_far', 'error') end

        if not player.Functions.RemoveMoney('cash', amount) then return notify(src, 'notify.not_enough_cash', 'error') end
        if not otherPlayer.Functions.AddMoney('cash', amount) then
            player.Functions.AddMoney('cash', amount)
            return notify(src, 'notify.give_failed', 'error')
        end

        notify(src, 'notify.gave_cash', 'success', math.groupdigits(amount), id)
        notify(id, 'notify.received_cash', 'success', math.groupdigits(amount), src)
    else
        notify(src, 'notify.wrong_id', 'error')
    end
end)

-- Transfer between bank accounts (account number = charinfo.account of the receiving character).
local function findAccountOwner(accountNumber)
    return exports.w_lib:FwFindBankAccount(accountNumber)
end

RegisterServerEvent('w_banking:initiateTransfer', function(data)
    local src = source
    local player = WCore.Functions.GetPlayer(src)
    if not player then return end

    local amount = type(data) == 'table' and tonumber(data.amount) or nil
    local accountNumber = type(data) == 'table' and data.account and tostring(data.account):gsub('%s', '') or nil
    if not amount or amount <= 0 or not accountNumber or accountNumber == '' then
        return TriggerClientEvent('w_banking:transferError', src, 'msg.transfer_invalid')
    end
    amount = math.floor(amount)

    if accountNumber == player.PlayerData.charinfo.account then
        return TriggerClientEvent('w_banking:transferError', src, 'msg.transfer_self')
    end
    if amount > player.Functions.GetMoney('bank') then
        return TriggerClientEvent('w_banking:transferError', src, 'msg.not_enough')
    end

    local receiver, offline = findAccountOwner(accountNumber)
    if not receiver then
        return TriggerClientEvent('w_banking:transferError', src, 'msg.transfer_no_account')
    end

    if not player.Functions.RemoveMoney('bank', amount, 'banking-transfer-out') then
        return TriggerClientEvent('w_banking:transferError', src, 'msg.not_enough')
    end
    if not receiver.Functions.AddMoney('bank', amount, 'banking-transfer-in') then
        player.Functions.AddMoney('bank', amount, 'banking-transfer-refund')
        return TriggerClientEvent('w_banking:transferError', src, 'msg.transfer_no_account')
    end
    if offline then receiver.Functions.Save() end

    local senderName = getCharacterName(src)
    TriggerClientEvent('w_banking:openBankScreen', src)
    TriggerClientEvent('w_banking:successAlert', src, 'msg.transfer_success', math.groupdigits(amount), accountNumber)
    if not offline then
        notify(receiver.PlayerData.source, 'msg.transfer_received', 'success', math.groupdigits(amount), senderName)
    end
    TriggerEvent('w_log:server:CreateLog', 'banking', 'Banking', 'lightgreen', "**"..GetPlayerName(src) .. " (citizenid: "..player.PlayerData.citizenid.." | id: "..src..")** transferred $"..amount.." to account "..accountNumber.." ("..receiver.PlayerData.citizenid..")")
end)
