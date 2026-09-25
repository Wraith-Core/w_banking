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
    -- The key takes only the note's ASCII. A transfer note carries the recipient's name, and a byte
    -- cut through an Arabic letter is invalid UTF-8: MySQL cuts the key there (INSERT IGNORE), the
    -- request key at its end is lost, and the next transfer to that name collides and is dropped.
    local tag=note:gsub('[\128-\255]',''):sub(1,25)
    BankAccounts.statement(p.PlayerData.citizenid, 'Checking', withdrawal and 0 or amount, withdrawal and amount or 0, p.Functions.GetMoney('bank'), note,nil,statementKey(data,p.PlayerData.citizenid,'Checking-'..tag))
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
-- The recipient is named by his bank account number or by his citizen id ('12', the old 'OMG95204',
-- '#5' for whoever is on server id 5). An account number (US0<d>W<digits>) never reads as a citizen
-- id, so w.citizen.parse tells the two apart. Both work while the recipient is offline: the money
-- goes to the ledger account of his citizen id, never to a server id.
local function recipientOf(typed, number)
    -- a '#' always meant a server id (an account number never has one): '#0' is a bad id, not an account
    if w.citizen.parse(typed) or number:sub(1, 1) == '#' then
        local target, reason = w.citizen.resolve(typed)
        if not target then return nil, reason == 'invalid_id' and 'msg.transfer_invalid' or 'msg.transfer_no_citizen' end
        return target.citizenid, w.citizen.label(target)
    end
    local receiver = exports.w_lib:FwFindBankAccount(number)
    if not receiver then return nil, 'msg.transfer_no_account' end
    return receiver.PlayerData.citizenid, number
end
actions.doTransfer = function(p, data)
    local amount = BankAccounts.validAmount(data.amount)
    local typed = type(data.account)=='string' and data.account or ''
    local number = typed:gsub('%s','')
    if not amount or number=='' or #number>64 then return failure('msg.transfer_invalid') end
    if number == tostring(p.PlayerData.charinfo.account) then return failure('msg.transfer_self') end
    local cid, shown = recipientOf(typed, number)
    if not cid then return failure(shown) end
    cid = tostring(cid)
    if cid == tostring(p.PlayerData.citizenid) then return failure('msg.transfer_self') end
    local to='player:'..cid..':bank'
    if not exports.w_centralbank:EnsureAccount(to,cid,'player') then return failure() end
    if not transfer(p,'player:'..p.PlayerData.citizenid..':bank',to,amount,'bank-transfer',data) then return failure('msg.not_enough') end
    record(p, withTax(p,amount), true, 'Transfer to ' .. shown,data)
    local receivedBalance = exports.w_centralbank:GetBalance(to)
    BankAccounts.statement(cid, 'Checking', amount, 0, receivedBalance, 'Transfer from ' .. tostring(p.PlayerData.charinfo.account),nil,statementKey(data,cid,'Received-'..p.PlayerData.citizenid))
    -- Asked now, after the ledger calls yielded: he may have connected or left meanwhile.
    local online = WCore.Functions.GetPlayerByCitizenId and WCore.Functions.GetPlayerByCitizenId(cid)
    if online then TriggerClientEvent('w_banking:client:notify', online.PlayerData.source, 'msg.transfer_received', 'success', amount, getCharacterName(p.PlayerData.source)) end
    return { ok=true, key='msg.transfer_success', args={amount,shown} }
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
-- The receiver is named by his citizen id ('#5' = whoever is on server id 5): a server id changes on
-- every connection and, now that citizen ids are plain digits, the two collide. The argument has no
-- `type` (the raw text arrives; w.addCommand's 'string' type refuses digits), so each failure is
-- answered here in the bank's own notices. Cash changes hands in person, so he must be in the game
-- (and near), never the offline way.
local CITIZEN_NOTICE = { invalid_id = 'notify.invalid_citizen', not_found = 'notify.no_citizen', offline = 'notify.citizen_offline' }
w.addCommand('givecash', {help=locale('cmd.givecash'), params={{name='id',help=locale('cmd.givecash_id')},{name='amount',help=locale('cmd.givecash_amount')}}}, function(src,args)
    local amount = BankAccounts.validAmount(args.amount)
    local function notify(key,style,...) TriggerClientEvent('w_banking:client:notify',src,key,style,...) end
    if not args.id or not amount then return notify('notify.usage_givecash','error') end
    local target, reason, offline = w.citizen.requireOnline(args.id, { self = src })
    if not target then return notify(CITIZEN_NOTICE[reason] or 'notify.no_citizen','error',w.citizen.label(offline)) end
    local id = target.source
    local p, other = WCore.Functions.GetPlayer(src), WCore.Functions.GetPlayer(id)
    if not p or not other or id==src then return notify('notify.wrong_id','error') end
    if p.PlayerData.metadata.isdead then return notify('notify.dead','error') end
    if GetPlayerRoutingBucket(src)~=GetPlayerRoutingBucket(id) or #(GetEntityCoords(GetPlayerPed(src))-GetEntityCoords(GetPlayerPed(id))) > (p.PlayerData.metadata.inlaststand and 3 or 10) then return notify('notify.too_far','error') end
    if not exports.w_centralbank:Transfer('player:'..p.PlayerData.citizenid..':cash','player:'..other.PlayerData.citizenid..':cash',amount,'givecash') then return notify('notify.not_enough_cash','error') end
    -- both sides see a name and a citizen id, never a server id
    notify('notify.gave_cash','success',amount,w.citizen.label(target))
    TriggerClientEvent('w_banking:client:notify',id,'notify.received_cash','success',amount,w.citizen.label({ citizenid = p.PlayerData.citizenid, name = getCharacterName(src) }))
end)

w.callback.register('w_banking:branches',function() return GetResourceState('w_centralbank')=='started' and exports.w_centralbank:GetBanks() or {} end)

-- A deleted character leaves nothing here, so its citizen id can be handed to someone else.
--   exports.w_banking:PurgeCharacter(citizenid, ctx) -> true, { [thing] = n } | false, reason
-- Called by w_core from a server thread with the character offline. What w_banking keeps for a
-- character: its savings account (bank_accounts, one row per citizen id) and the caches keyed by
-- that id. The savings money is not in the row (a projection) but in the central bank ledger,
-- 'banklegacy:<record_id>', kind 'legacy_bank', owned by the citizen id. It is NOT moved here:
-- w_centralbank.PurgeCharacter, which w_core calls last, returns it to the reserve (a frozen one
-- too, which a move through the exports would refuse) and deletes the account in its one
-- transaction. It finds the account by that owner, so the owner stays the citizen id.
-- bank_statements is history: w_core moves it off the number with its registry, and no statement
-- is written here, since a new row under the number would be the very leftover this removes.
-- Idempotent: the second call finds no row and answers true with an empty report.
exports('PurgeCharacter',function(citizenid,ctx)
    if GetInvokingResource() ~= 'w_core' then return false, 'forbidden' end
    local cid=citizenid
    -- a number from another resource may arrive as a float (12.0): written as '%d', never '12.0'
    if type(cid)=='number' and cid==math.floor(cid) then cid=('%d'):format(cid) end
    if type(cid)~='string' or cid=='' or #cid>64 or cid:find('[%s%c]') then return false,'invalid_id' end
    if not BankAccounts.ready then return false,'not_ready' end
    -- an account being opened right now would be re-created behind the deletion
    if BankAccounts.locks['Savings:'..cid] or busy[cid] then return false,'busy' end
    local okRows,rows=pcall(MySQL.query.await,'SELECT record_id FROM bank_accounts WHERE citizenid=?',{cid})
    if not okRows then return false,'database' end
    rows=rows or {}
    local report={}
    if #rows>0 then
        -- No ledger to ask: the tables decide. Before the economy opens bank_accounts.amount is the
        -- balance the opening imports; once it is open cb_accounts holds it. A row with money in
        -- either stays (deleting it would lose that money); an empty one goes, and w_core's own
        -- pass deletes the empty banklegacy account, which it finds by its owner. Refusing an
        -- empty one would hold a deletion the other resources have already carried out.
        if GetResourceState('w_centralbank')~='started' or not exports.w_centralbank:IsReady() then
            local okF,funded=pcall(function()
                if (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM bank_accounts WHERE citizenid=? AND amount<>0',{cid})) or 0)>0 then return true end
                if (tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='cb_accounts'")) or 0)==0 then return false end
                local ids={}
                for _,r in ipairs(rows) do ids[#ids+1]='banklegacy:'..r.record_id end -- as accounts.lua names it
                return (tonumber(MySQL.scalar.await(('SELECT COUNT(*) FROM cb_accounts WHERE balance<>0 AND id IN (%s)'):format(('?,'):rep(#ids):sub(1,-2)),ids)) or 0)>0
            end)
            if not okF or funded then return false,'economy_not_ready' end
        end
        local okDel,removed=pcall(MySQL.update.await,'DELETE FROM bank_accounts WHERE citizenid=?',{cid})
        if not okDel then return false,'database' end
        report.bank_accounts=tonumber(removed) or #rows
    end
    -- the caches go with the rows: information() and the savings actions read savingsAccounts
    if savingsAccounts[cid] then report.cache=1 end
    savingsAccounts[cid],busy[cid],lastAction[cid]=nil,nil,nil
    return true,report
end)
