local banks, busy, lastAction = Config.BankLocations, {}, {}
MySQL.ready(function()
    local ok, err = pcall(function()
        local schema = LoadResourceFile(GetCurrentResourceName(), 'w_banking.sql')
        for statement in schema:gmatch('([^;]+);') do MySQL.query.await(statement) end
        local hasKey=MySQL.scalar.await("SELECT COUNT(*) FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='bank_statements' AND column_name='request_key'")
        if tonumber(hasKey)==0 then MySQL.query.await('ALTER TABLE bank_statements ADD COLUMN request_key VARCHAR(190) DEFAULT NULL, ADD UNIQUE KEY cb_request_key (request_key)') end
        -- These are ledger projections; preserve cents in legacy tables as well.
        for _,spec in ipairs({{'bank_accounts','amount'},{'bank_statements','deposited'},{'bank_statements','withdraw'},{'bank_statements','balance'}}) do
            local kind=MySQL.scalar.await('SELECT DATA_TYPE FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name=? AND column_name=?',spec)
            if kind and kind~='decimal' then MySQL.query.await(('ALTER TABLE `%s` MODIFY `%s` DECIMAL(18,2) DEFAULT 0'):format(spec[1],spec[2])) end
        end
        for _, row in ipairs(MySQL.query.await('SELECT citizenid, gangid, account_type FROM bank_accounts') or {}) do
            if row.account_type == 'Savings' and row.citizenid then savingsAccounts[row.citizenid] = generateSavings(row.citizenid)
            elseif row.gangid then gangAccounts[row.gangid] = loadGangAccount(row.gangid) end
        end
        BankAccounts.ready = true
    end)
    if not ok then print(('[w_banking] Database initialization failed: %s'):format(tostring(err))) end
end)

local function modifyBank() return false,'Use the central bank charter controls' end
AddEventHandler('w_banking:server:modifyBank', modifyBank)
exports('modifyBank', modifyBank)
exports('savings', function(cid) return savingsAccounts[cid] end)
exports('gang', function(gid) return gangAccounts[gid] end)
function getCharacterName(src)
    local p = WCore.Functions.GetPlayer(src)
    return p and (p.PlayerData.charinfo.firstname .. ' ' .. p.PlayerData.charinfo.lastname)
end
local function nearBank(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    if GetResourceState('w_centralbank')~='started' or not exports.w_centralbank:IsReady() then return false end
    banks=exports.w_centralbank:GetBanks()
    for _, bank in pairs(banks) do
        local c = bank.coords
        if #(pos - vector3(c.x,c.y,c.z)) <= Config.ServerDistance then return bank.id end
    end
    return false
end
local function failure(key) return { ok = false, key = key or 'msg.failed' } end
local function information(src)
    local p = WCore.Functions.GetPlayer(src)
    if not p or not BankAccounts.ready or not nearBank(src) then return nil end
    local d = p.PlayerData
    local savings = savingsAccounts[d.citizenid]
    return {
        branch = nearBank(src), taxRate=exports.w_centralbank:TaxRate(nearBank(src)), closedEconomy=true, name = getCharacterName(src), accountinfo = tostring(d.charinfo.account or ''),
        bankbalance = p.Functions.GetMoney('bank'), cash = p.Functions.GetMoney('cash'),
        savings = savings and { amount = savings.GetBalance() } or nil,
        history = MySQL.query.await('SELECT account, deposited, withdraw, balance, date, type FROM bank_statements WHERE citizenid = ? AND account IN (?, ?) ORDER BY record_id DESC LIMIT 30', { d.citizenid, 'Checking', 'Savings' }) or {},
    }
end
w.callback.register('w_banking:getBankingInformation', information)
local function statementKey(data,cid,kind)
    local key=type(data)=='table' and data.requestKey
    if type(key)~='string' or #key<8 or #key>80 then return nil end
    return cid..':'..tostring(kind):sub(1,40)..':'..key
end
local function record(p, amount, withdrawal, note, data)
    BankAccounts.statement(p.PlayerData.citizenid, 'Checking', withdrawal and 0 or amount, withdrawal and amount or 0, p.Functions.GetMoney('bank'), note,nil,statementKey(data,p.PlayerData.citizenid,'Checking-'..note:sub(1,25)))
end
local function withTax(p,amount)
    local rate=exports.w_centralbank:TaxRate(nearBank(p.PlayerData.source)) or 0
    return amount+math.floor(amount*rate+0.5)/100
end
local function transfer(p,from,to,amount,reason,data)
    local branch=nearBank(p.PlayerData.source)
    if not branch then return false end
    local key=type(data)=='table' and data.requestKey
    if type(key)~='string' or #key<8 or #key>80 then key=nil end
    if key then key='bank:'..p.PlayerData.citizenid..':'..reason..':'..key end
    return exports.w_centralbank:BankTransfer(p.PlayerData.source,branch,from,to,amount,reason,key)
end
local function move(p,from,to,amount,reason,data)
    local prefix='player:'..p.PlayerData.citizenid..':'
    return transfer(p,prefix..from,prefix..to,amount,reason,data)
end
local actions = {}
actions.doDeposit = function(p, data)
    local amount = BankAccounts.validAmount(data.amount)
    if not amount then return failure('msg.invalid_amount') end
    if not move(p, 'cash', 'bank', amount, 'bank-deposit', data) then return failure('msg.not_enough') end
    record(p, amount, false, 'Cash deposit',data)
    return { ok=true, key='msg.deposit_success', args={amount} }
end
actions.doWithdraw = function(p, data)
    local amount = BankAccounts.validAmount(data.amount)
    if not amount then return failure('msg.invalid_amount') end
    if not move(p, 'bank', 'cash', amount, 'bank-withdraw', data) then return failure('msg.not_enough') end
    record(p, withTax(p,amount), true, 'Cash withdrawal',data)
    return { ok=true, key='msg.withdraw_success', args={amount} }
end
actions.createSavingsAccount = function(p)
    if not createSavingsAccount(p.PlayerData.citizenid) then return failure('msg.savings_exists') end
    return { ok=true, key='msg.savings_opened' }
end
actions.savingsDeposit = function(p, data)
    local amount, account = BankAccounts.validAmount(data.amount), savingsAccounts[p.PlayerData.citizenid]
    if not amount then return failure('msg.invalid_amount') end
    if not account then return failure('msg.no_savings') end
    if not transfer(p,'player:'..p.PlayerData.citizenid..':bank',account.accountId,amount,'savings-deposit',data) then return failure('msg.not_enough') end
    record(p, withTax(p,amount), true, 'To savings',data)
    BankAccounts.statement(p.PlayerData.citizenid,'Savings',amount,0,account.GetBalance(),'Bank to savings',nil,statementKey(data,p.PlayerData.citizenid,'Savings'))
    return { ok=true, key='msg.savings_deposit_success', args={amount} }
end
actions.savingsWithdraw = function(p, data)
    local amount, account = BankAccounts.validAmount(data.amount), savingsAccounts[p.PlayerData.citizenid]
    if not amount then return failure('msg.invalid_amount') end
    if not account then return failure('msg.no_savings') end
    if not transfer(p,account.accountId,'player:'..p.PlayerData.citizenid..':bank',amount,'savings-withdraw',data) then return failure('msg.not_enough') end
    record(p, amount, false, 'From savings',data)
    BankAccounts.statement(p.PlayerData.citizenid,'Savings',0,withTax(p,amount),account.GetBalance(),'Savings to bank',nil,statementKey(data,p.PlayerData.citizenid,'Savings'))
    return { ok=true, key='msg.savings_withdraw_success', args={amount} }
end
actions.doTransfer = function(p, data)
    local amount = BankAccounts.validAmount(data.amount)
    local number = type(data.account)=='string' and data.account:gsub('%s','') or ''
    if not amount or number=='' or #number>64 then return failure('msg.transfer_invalid') end
    if number == tostring(p.PlayerData.charinfo.account) then return failure('msg.transfer_self') end
    local receiver, offline = exports.w_lib:FwFindBankAccount(number)
    if not receiver then return failure('msg.transfer_no_account') end
    -- Recheck after the lookup yields, in case the character connected meanwhile.
    if offline and WCore.Functions.GetPlayerByCitizenId then
        local online = WCore.Functions.GetPlayerByCitizenId(receiver.PlayerData.citizenid)
        if online then receiver, offline = online, false end
    end
    local to='player:'..receiver.PlayerData.citizenid..':bank'
    if not exports.w_centralbank:EnsureAccount(to,receiver.PlayerData.citizenid,'player') then return failure() end
    if not transfer(p,'player:'..p.PlayerData.citizenid..':bank',to,amount,'bank-transfer',data) then return failure('msg.not_enough') end
    record(p, withTax(p,amount), true, 'Transfer to ' .. number,data)
    local receivedBalance = exports.w_centralbank:GetBalance(to)
    BankAccounts.statement(receiver.PlayerData.citizenid, 'Checking', amount, 0, receivedBalance, 'Transfer from ' .. tostring(p.PlayerData.charinfo.account),nil,statementKey(data,receiver.PlayerData.citizenid,'Received-'..p.PlayerData.citizenid))
    if not offline then TriggerClientEvent('w_banking:client:notify', receiver.PlayerData.source, 'msg.transfer_received', 'success', amount, getCharacterName(p.PlayerData.source)) end
    return { ok=true, key='msg.transfer_success', args={amount,number} }
end
local function transact(src, action, data)
    if not BankAccounts.ready then return failure('msg.unavailable') end
    local p = WCore.Functions.GetPlayer(src)
    if not p or not nearBank(src) or p.PlayerData.metadata.isdead then return failure('msg.near_bank') end
    if not actions[action] or type(data)~='table' then return failure('msg.invalid_amount') end
    local cid, now = p.PlayerData.citizenid, GetGameTimer()
    if busy[cid] or (lastAction[cid] and now-lastAction[cid]<500) then return failure('msg.busy') end
    busy[cid], lastAction[cid] = true, now
    local ok, result = pcall(actions[action], p, data)
    busy[cid] = nil
    if not ok then print(('[w_banking] Transaction failed: %s'):format(tostring(result))) return failure() end
    if result.ok then
        local fresh, info = pcall(information, src)
        if fresh then result.information = info end
    end
    return result
end
w.callback.register('w_banking:transaction', transact)
-- Existing integrations keep their event names and receive authoritative replies.
for event, action in pairs({
    doQuickDeposit='doDeposit', doQuickWithdraw='doWithdraw', savingsDeposit='savingsDeposit',
    savingsWithdraw='savingsWithdraw', createSavingsAccount='createSavingsAccount', initiateTransfer='doTransfer',
}) do
    RegisterNetEvent('w_banking:' .. event, function(value)
        local src = source
        local result = transact(src, action, type(value)=='table' and value or {amount=value})
        TriggerClientEvent(result.ok and 'w_banking:successAlert' or 'w_banking:transferError', src, result.key, table.unpack(result.args or {}))
        if result.ok then TriggerClientEvent('w_banking:openBankScreen', src) end
    end)
end
w.addCommand('givecash', {help=locale('cmd.givecash'), params={{name='id',help=locale('cmd.givecash_id')},{name='amount',help=locale('cmd.givecash_amount')}}}, function(src,args)
    local id, amount = tonumber(args.id), BankAccounts.validAmount(args.amount)
    local function notify(key,style,...) TriggerClientEvent('w_banking:client:notify',src,key,style,...) end
    if not id or not amount then return notify('notify.usage_givecash','error') end
    local p, other = WCore.Functions.GetPlayer(src), WCore.Functions.GetPlayer(id)
    if not p or not other or id==src then return notify('notify.wrong_id','error') end
    if p.PlayerData.metadata.isdead then return notify('notify.dead','error') end
    if GetPlayerRoutingBucket(src)~=GetPlayerRoutingBucket(id) or #(GetEntityCoords(GetPlayerPed(src))-GetEntityCoords(GetPlayerPed(id))) > (p.PlayerData.metadata.inlaststand and 3 or 10) then return notify('notify.too_far','error') end
    if not exports.w_centralbank:Transfer('player:'..p.PlayerData.citizenid..':cash','player:'..other.PlayerData.citizenid..':cash',amount,'givecash') then return notify('notify.not_enough_cash','error') end
    notify('notify.gave_cash','success',amount,id)
    TriggerClientEvent('w_banking:client:notify',id,'notify.received_cash','success',amount,src)
end)

w.callback.register('w_banking:branches',function() return GetResourceState('w_centralbank')=='started' and exports.w_centralbank:GetBanks() or {} end)
