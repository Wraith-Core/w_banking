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
local function getPlayer(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end
    local okP, raw = pcall(function()
        local list = exports.w_lib:FwGetOnlinePlayers()
        if type(list) == 'table' then
            for _, p in ipairs(list) do
                if type(p) == 'table' and p.PlayerData and tonumber(p.PlayerData.source) == src then
                    return p
                end
            end
        end
        return nil
    end)
    if okP and type(raw) == 'table' and type(raw.PlayerData) == 'table' and type(raw.Functions) == 'table' then
        return raw
    end
    local okCid, cid = pcall(function() return exports.w_lib:FwGetCharacterIdentifier(src) end)
    if not okCid or not cid or cid == '' then return nil end
    local okPd, pd = pcall(function() return exports.w_lib:FwGetPlayerData(src) end)
    local charinfo = okPd and type(pd) == 'table' and type(pd.charinfo) == 'table' and pd.charinfo or {}
    local okMeta, meta = pcall(function() return exports.w_lib:FwGetMetadata(src) end)
    if not okMeta or type(meta) ~= 'table' then
        meta = okPd and type(pd) == 'table' and type(pd.metadata) == 'table' and pd.metadata or {}
    end
    return {
        PlayerData = {
            source = src,
            citizenid = tostring(cid),
            charinfo = charinfo,
            metadata = meta,
        },
        Functions = {
            GetMoney = function(kind)
                local okM, val = pcall(function() return exports.w_lib:FwGetCurrency(src, kind) end)
                return okM and tonumber(val) or 0
            end,
        },
    }
end
function getCharacterName(src)
    local okN, name = pcall(function() return exports.w_lib:FwGetCharacterName(src) end)
    if okN and type(name) == 'string' and name ~= '' then return name end
    local p = getPlayer(src)
    return p and ((p.PlayerData.charinfo.firstname or '') .. ' ' .. (p.PlayerData.charinfo.lastname or ''))
end
local function usesCentralBank()
    return GetResourceState('w_centralbank') == 'started'
end
local function activeBanks()
    if usesCentralBank() then
        return exports.w_lib:EconIsReady() and exports.w_lib:EconGetBanks() or {}
    end
    return Config.BankLocations or {}
end
local function nearBank(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    if usesCentralBank() and not exports.w_lib:EconIsReady() then return false end
    banks = activeBanks()
    for _, bank in pairs(banks) do
        local c = bank.coords
        if c and #(pos - vector3(c.x, c.y, c.z)) <= Config.ServerDistance then
            return bank.id or bank.name or true
        end
    end
    return false
end
local function failure(key, args) return { ok = false, key = key or 'msg.failed', args = args } end
local function information(src)
    local p = getPlayer(src)
    local branch = nearBank(src)
    if not p or not BankAccounts.ready or not branch then return nil end
    local d = p.PlayerData
    local savings = savingsAccounts[d.citizenid]
    local isCentral = usesCentralBank()
    return {
        branch = branch,
        taxRate = isCentral and (exports.w_lib:EconTaxRate(branch) or 0) or 0,
        closedEconomy = isCentral,
        name = getCharacterName(src),
        accountinfo = tostring(d.charinfo.account or ''),
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
    if not usesCentralBank() then return amount end
    local rate=exports.w_lib:EconTaxRate(nearBank(p.PlayerData.source)) or 0
    return amount+math.floor(amount*rate+0.5)/100
end
local function transfer(p,from,to,amount,reason,data)
    local branch=nearBank(p.PlayerData.source)
    if not branch then return false,'near_bank' end
    if usesCentralBank() then
        local key=type(data)=='table' and data.requestKey
        if type(key)~='string' or #key<8 or #key>80 then key=nil end
        if key then key='bank:'..p.PlayerData.citizenid..':'..reason..':'..key end
        return exports.w_lib:EconBankTransfer(p.PlayerData.source,branch,from,to,amount,reason,key)
    end
    return exports.w_lib:EconTransfer(from,to,amount,reason)
end
local function move(p,from,to,amount,reason,data)
    local prefix='player:'..p.PlayerData.citizenid..':'
    return transfer(p,prefix..from,prefix..to,amount,reason,data)
end
--- 2.0.3 (owner 2026-11-01): a refused move says why (w_centralbank's BankTransfer answers ok, why): short of money
--- with what it costs (the bank's tax included) and what he has, a frozen account, the bank down -- it used
--- to say "not enough" whatever happened. `source`: 'cash' | 'bank' | the savings account object.
local function money(n) return ('%.2f'):format(tonumber(n) or 0) end
local function refused(p, why, source, amount)
    if type(why) ~= 'string' then return failure('msg.not_enough') end -- a w_centralbank before 2.1 answers its tax there
    if why == 'account_frozen' then return failure('msg.frozen') end
    if why == 'near_bank' then return failure('msg.near_bank') end
    if why == 'economy_not_ready' or why == 'invalid_bank' then return failure('msg.unavailable') end
    if why ~= 'insufficient_funds' then return failure() end
    local need = money(withTax(p, amount))
    if source == 'cash' then return failure('msg.not_enough_cash', { need, money(p.Functions.GetMoney('cash')) }) end
    if source == 'bank' then return failure('msg.not_enough_bank', { need, money(p.Functions.GetMoney('bank')) }) end
    return failure('msg.not_enough_savings', { need, money(source.GetBalance()) })
end
local actions = {}
actions.doDeposit = function(p, data)
    local amount = BankAccounts.validAmount(data.amount)
    if not amount then return failure('msg.invalid_amount') end
    local moved, why = move(p, 'cash', 'bank', amount, 'bank-deposit', data)
    if not moved then return refused(p, why, 'cash', amount) end
    record(p, amount, false, 'Cash deposit',data)
    return { ok=true, key='msg.deposit_success', args={amount} }
end
actions.doWithdraw = function(p, data)
    local amount = BankAccounts.validAmount(data.amount)
    if not amount then return failure('msg.invalid_amount') end
    local moved, why = move(p, 'bank', 'cash', amount, 'bank-withdraw', data)
    if not moved then return refused(p, why, 'bank', amount) end
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
    if usesCentralBank() then
        local moved, why = transfer(p,'player:'..p.PlayerData.citizenid..':bank',account.accountId,amount,'savings-deposit',data)
        if not moved then return refused(p, why, 'bank', amount) end
        record(p, withTax(p,amount), true, 'To savings',data)
        BankAccounts.statement(p.PlayerData.citizenid,'Savings',amount,0,account.GetBalance(),'Bank to savings',nil,statementKey(data,p.PlayerData.citizenid,'Savings'))
    else
        local okDebit, why = exports.w_lib:EconAdjustPlayer(p.PlayerData.citizenid, 'bank', -amount, 'savings-deposit')
        if okDebit ~= true then return refused(p, why, 'bank', amount) end
        if not account.AddMoney(amount, 'Bank to savings') then
            exports.w_lib:EconAdjustPlayer(p.PlayerData.citizenid, 'bank', amount, 'savings-deposit-rollback')
            return failure()
        end
        record(p, amount, true, 'To savings', data)
    end
    return { ok=true, key='msg.savings_deposit_success', args={amount} }
end
actions.savingsWithdraw = function(p, data)
    local amount, account = BankAccounts.validAmount(data.amount), savingsAccounts[p.PlayerData.citizenid]
    if not amount then return failure('msg.invalid_amount') end
    if not account then return failure('msg.no_savings') end
    if usesCentralBank() then
        local moved, why = transfer(p,account.accountId,'player:'..p.PlayerData.citizenid..':bank',amount,'savings-withdraw',data)
        if not moved then return refused(p, why, account, amount) end
        record(p, amount, false, 'From savings',data)
        BankAccounts.statement(p.PlayerData.citizenid,'Savings',0,withTax(p,amount),account.GetBalance(),'Savings to bank',nil,statementKey(data,p.PlayerData.citizenid,'Savings'))
    else
        if not account.RemoveMoney(amount, 'Savings to bank') then
            return refused(p, 'insufficient_funds', account, amount)
        end
        local okCredit, why = exports.w_lib:EconAdjustPlayer(p.PlayerData.citizenid, 'bank', amount, 'savings-withdraw')
        if okCredit ~= true then
            account.AddMoney(amount, 'Savings withdraw rollback')
            return refused(p, why, account, amount)
        end
        record(p, amount, false, 'From savings', data)
    end
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
    if not exports.w_lib:EconEnsureAccount(to,cid,'player') then return failure() end
    local moved, why = transfer(p,'player:'..p.PlayerData.citizenid..':bank',to,amount,'bank-transfer',data)
    if not moved then return refused(p, why, 'bank', amount) end
    record(p, withTax(p,amount), true, 'Transfer to ' .. shown,data)
    local receivedBalance = exports.w_lib:EconGetBalance(to) or 0
    BankAccounts.statement(cid, 'Checking', amount, 0, receivedBalance, 'Transfer from ' .. tostring(p.PlayerData.charinfo.account),nil,statementKey(data,cid,'Received-'..p.PlayerData.citizenid))
    -- Asked now, after the ledger calls yielded: he may have connected or left meanwhile.
    local okOnline, online = pcall(function() return exports.w_lib:FwGetPlayerByCitizenId(cid) end)
    local onlineSrc = okOnline and type(online) == 'table' and online.PlayerData and online.PlayerData.source or nil
    if not onlineSrc then
        local okSrc, s = pcall(function() return exports.w_lib:FwGetSource(cid) end)
        onlineSrc = okSrc and tonumber(s) or nil
    end
    if onlineSrc then TriggerClientEvent('w_banking:client:notify', onlineSrc, 'msg.transfer_received', 'success', amount, getCharacterName(p.PlayerData.source)) end
    return { ok=true, key='msg.transfer_success', args={amount,shown} }
end
local function transact(src, action, data)
    if not BankAccounts.ready then return failure('msg.unavailable') end
    local p = getPlayer(src)
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
    local p, other = getPlayer(src), getPlayer(id)
    if not p or not other or id==src then return notify('notify.wrong_id','error') end
    if p.PlayerData.metadata.isdead then return notify('notify.dead','error') end
    if GetPlayerRoutingBucket(src)~=GetPlayerRoutingBucket(id) or #(GetEntityCoords(GetPlayerPed(src))-GetEntityCoords(GetPlayerPed(id))) > (p.PlayerData.metadata.inlaststand and 3 or 10) then return notify('notify.too_far','error') end
    local given, why = exports.w_lib:EconTransfer('player:'..p.PlayerData.citizenid..':cash','player:'..other.PlayerData.citizenid..':cash',amount,'givecash')
    if not given then
        -- 2.0.3: what he carries when that is the reason; otherwise the money did not move for another cause
        if why == 'insufficient_funds' then return notify('notify.not_enough_cash_have','error',('%.2f'):format(p.Functions.GetMoney('cash') or 0)) end
        return notify(why == 'account_frozen' and 'msg.frozen' or 'notify.give_failed','error')
    end
    -- both sides see a name and a citizen id, never a server id
    notify('notify.gave_cash','success',amount,w.citizen.label(target))
    TriggerClientEvent('w_banking:client:notify',id,'notify.received_cash','success',amount,w.citizen.label({ citizenid = p.PlayerData.citizenid, name = getCharacterName(src) }))
end)

w.callback.register('w_banking:branches', function() return activeBanks() end)

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
        if not exports.w_lib:EconIsReady() then
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
