-- Database acknowledgement precedes cache changes and successful replies.
-- Uses w_centralbank ledger when started, and standard MySQL bank_accounts.amount otherwise.
BankAccounts = { ready = false, locks = {} }
savingsAccounts, gangAccounts = {}, {}

local function usesCentralBank()
    return GetResourceState('w_centralbank') == 'started'
end

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
        { cid or '', gid or '', kind, deposited, withdrawn, balance, os.date('%Y-%m-%d %H:%M:%S'), tostring(description or kind):sub(1, 255), requestKey or '' })
    if not ok then print(('[w_banking] Statement write failed: %s'):format(tostring(result))) end
    return ok
end

function BankAccounts.load(owner, kind)
    local column = kind == 'Gang' and 'gangid' or 'citizenid'
    local row = MySQL.single.await(('SELECT * FROM bank_accounts WHERE %s = ? AND account_type = ? ORDER BY record_id LIMIT 1'):format(column), { owner, kind })
    if not row then return nil end
    local id = row.record_id
    local accountId = 'banklegacy:' .. id

    local function ready()
        if usesCentralBank() then
            return exports.w_lib:EconIsReady()
                and exports.w_lib:EconEnsureAccount(accountId, kind == 'Savings' and owner or ('gang:' .. owner), 'legacy_bank')
        end
        return BankAccounts.ready == true
    end

    local function getBalance()
        if usesCentralBank() then
            return ready() and exports.w_lib:EconGetBalance(accountId) or 0
        end
        local val = MySQL.scalar.await('SELECT amount FROM bank_accounts WHERE record_id = ? LIMIT 1', { id })
        return tonumber(val) or 0
    end

    local function change(amount, description, withdraw)
        amount = BankAccounts.validAmount(amount)
        if not amount or not ready() then return false end
        if usesCentralBank() then
            local ok = exports.w_lib:EconAdjustAccount(accountId, withdraw and -amount or amount, description or 'legacy-bank')
            if ok then
                BankAccounts.statement(kind == 'Savings' and owner or nil, kind, withdraw and 0 or amount, withdraw and amount or 0, getBalance(), description, kind == 'Gang' and owner or nil)
            end
            return ok == true
        end

        local affected
        if withdraw then
            affected = MySQL.update.await('UPDATE bank_accounts SET amount = ROUND(amount - ?, 2) WHERE record_id = ? AND amount >= ?', { amount, id, amount })
        else
            affected = MySQL.update.await('UPDATE bank_accounts SET amount = ROUND(amount + ?, 2) WHERE record_id = ?', { amount, id })
        end
        if (tonumber(affected) or 0) > 0 then
            BankAccounts.statement(kind == 'Savings' and owner or nil, kind, withdraw and 0 or amount, withdraw and amount or 0, getBalance(), description, kind == 'Gang' and owner or nil)
            return true
        end
        return false
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
    if usesCentralBank() and not exports.w_lib:EconIsReady() then return false end
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
        if starting > 0 and not registry[owner].AddMoney(starting, 'Create bank account') then return false end
        return true
    end)
    BankAccounts.locks[key] = nil
    if not ok then print(('[w_banking] Account creation failed: %s'):format(tostring(result))) end
    return ok and result == true
end

exports.w_lib:EconOnBalanceChanged(function(account, balance)
    if not usesCentralBank() then return end
    local id = tostring(account or ''):match('^banklegacy:(%d+)$')
    if id then MySQL.update('UPDATE bank_accounts SET amount=? WHERE record_id=?', { balance, tonumber(id) }) end
end)

exports.w_lib:FwOnCitizenIdChanged(function(old, new)
    old, new = tostring(old), tostring(new)
    savingsAccounts[old] = nil
    CreateThread(function() savingsAccounts[new] = BankAccounts.load(new, 'Savings') end)
end)
