-- Database acknowledgement precedes cache changes and successful replies.
BankAccounts = { ready = false, locks = {} }
savingsAccounts, gangAccounts = {}, {}
function BankAccounts.validAmount(value)
    local n = tonumber(value)
    if not n or n ~= n or n <= 0 or n > (Config.MaxTransaction or 1000000000) then return nil end
    local cents = math.floor(n * 100 + 0.5)
    if math.abs(n * 100 - cents) > 0.000001 or cents < 1 then return nil end
    return cents / 100
end

function BankAccounts.statement(cid, kind, deposited, withdrawn, balance, description, gid, requestKey)
    local ok, result = pcall(MySQL.insert.await,
        "INSERT IGNORE INTO bank_statements (citizenid, gangid, account, deposited, withdraw, balance, date, type, request_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULLIF(?,''))",
        { cid or '', gid or '', kind, deposited, withdrawn, balance, os.date('%Y-%m-%d %H:%M:%S'), tostring(description or kind):sub(1,255), requestKey or '' })
    if not ok then print(('[w_banking] Statement write failed: %s'):format(tostring(result))) end
    return ok
end

function BankAccounts.load(owner, kind)
    local column = kind == 'Gang' and 'gangid' or 'citizenid'
    local row = MySQL.single.await(('SELECT * FROM bank_accounts WHERE %s = ? AND account_type = ? ORDER BY record_id LIMIT 1'):format(column), { owner, kind })
    if not row then return nil end
    local id = row.record_id
    local accountId='banklegacy:'..id
    local function ready()
        return GetResourceState('w_centralbank')=='started' and exports.w_centralbank:IsReady()
            and exports.w_centralbank:EnsureAccount(accountId,kind=='Savings' and owner or ('gang:'..owner),'legacy_bank')
    end
    local function getBalance()
        return ready() and exports.w_centralbank:GetBalance(accountId) or 0
    end
    local function change(amount,description,withdraw)
        amount=BankAccounts.validAmount(amount)
        if not amount or not ready() then return false end
        local ok=exports.w_centralbank:AdjustAccount(accountId,withdraw and -amount or amount,description or 'legacy-bank')
        if ok then
            BankAccounts.statement(kind=='Savings' and owner or nil,kind,withdraw and 0 or amount,withdraw and amount or 0,getBalance(),description,kind=='Gang' and owner or nil)
        end
        return ok==true
    end
    local account = {
        accountId = accountId,
        GetBalance = getBalance,
        getStatement = function()
            return MySQL.query.await(('SELECT * FROM bank_statements WHERE %s = ? AND account = ? ORDER BY record_id DESC LIMIT 30'):format(column), { owner, kind }) or {}
        end,
        AddMoney = function(amount, description) return change(amount, description, false) end,
        RemoveMoney = function(amount, description) return change(amount, description, true) end,
    }
    account.getBalance, account.addMoney, account.removeMoney = account.GetBalance, account.AddMoney, account.RemoveMoney
    return account
end

function BankAccounts.create(owner, kind, starting)
    if GetResourceState('w_centralbank')~='started' or not exports.w_centralbank:IsReady() then return false end
    if not BankAccounts.ready or type(owner) ~= 'string' or owner == '' then return false end
    local key = kind .. ':' .. owner
    if BankAccounts.locks[key] then return false end
    local registry = kind == 'Gang' and gangAccounts or savingsAccounts
    if registry[owner] then return false end
    starting = tonumber(starting) or 0
    if starting ~= 0 and not BankAccounts.validAmount(starting) then return false end
    BankAccounts.locks[key] = true
    local ok, result = pcall(function()
        local column = kind == 'Gang' and 'gangid' or 'citizenid'
        if MySQL.scalar.await(('SELECT record_id FROM bank_accounts WHERE %s = ? AND account_type = ? LIMIT 1'):format(column), { owner, kind }) then
            registry[owner] = BankAccounts.load(owner, kind)
            return false
        end
        local inserted = MySQL.insert.await(('INSERT INTO bank_accounts (%s, amount, account_type) VALUES (?, ?, ?)'):format(column), { owner, 0, kind })
        if not inserted then return false end
        registry[owner] = BankAccounts.load(owner, kind)
        if not registry[owner] then return false end
        if starting>0 and not registry[owner].AddMoney(starting,'Create legacy bank account') then return false end
        return true
    end)
    BankAccounts.locks[key] = nil
    if not ok then print(('[w_banking] Account creation failed: %s'):format(tostring(result))) end
    return ok and result == true
end

AddEventHandler('w_centralbank:balanceChanged',function(account,balance)
    local id=account:match('^banklegacy:(%d+)$')
    if id then MySQL.update('UPDATE bank_accounts SET amount=? WHERE record_id=?',{balance,tonumber(id)}) end
end)

-- w_core moved a character to another citizen id (w_core/server/citizen.lua) after renaming
-- bank_accounts.citizenid. Rebuild the savings entry under the new id instead of moving it:
-- the old object's closures still carry the old owner (statements, EnsureAccount owner).
AddEventHandler('w_core:server:citizenIdChanged',function(old,new)
    old,new=tostring(old),tostring(new)
    savingsAccounts[old]=nil
    CreateThread(function() savingsAccounts[new]=BankAccounts.load(new,'Savings') end)
end)
