-- Account registries shared by the server scripts (filled at startup, see server/server.lua).
savingsAccounts = {}
gangAccounts = {}

-- Savings account of one character: a `bank_accounts` row (account_type = 'Savings')
-- and its last 30 `bank_statements` rows.
function generateSavings(cid)
    local self = {}
    self.cid = cid
    self.balance = 0

    local getSavingsAccount = MySQL.Sync.fetchAll('SELECT * FROM bank_accounts WHERE citizenid = ? AND account_type = ?', { self.cid, 'Savings' })
    if getSavingsAccount[1] ~= nil then
        self.aid = getSavingsAccount[1].record_id
        self.balance = getSavingsAccount[1].amount
    end
    self.bankStatement = MySQL.Sync.fetchAll('SELECT * FROM bank_statements WHERE account = ? AND citizenid = ? ORDER BY record_id DESC LIMIT 30', { 'Savings', self.cid })

    self.saveAccount = function()
        MySQL.Async.fetchAll('UPDATE bank_accounts SET amount = ? WHERE citizenid = ? AND record_id = ?', { self.balance, self.cid, self.aid })
    end

    -- Append one statement row (deposited or withdrawn) and mirror it in the cached statement.
    local function addStatement(deposited, withdraw, text)
        local time = os.date('%Y-%m-%d %H:%M:%S')
        MySQL.Async.insert('INSERT INTO bank_statements (citizenid, account, deposited, withdraw, balance, date, type) VALUES (?, ?, ?, ?, ?, ?, ?)', {
            self.cid,
            'Savings',
            deposited,
            withdraw,
            self.balance,
            time,
            text
        }, function(recordId)
            table.insert(self.bankStatement, {
                record_id = recordId,
                citizenid = self.cid,
                account = 'Savings',
                deposited = deposited,
                withdraw = withdraw,
                balance = self.balance,
                date = time,
                type = text,
            })
        end)
    end

    local rTable = {}

    rTable.GetBalance = function()
        return self.balance
    end

    rTable.getStatement = function()
        return self.bankStatement
    end

    rTable.AddMoney = function(amt, text)
        if type(amt) == 'number' and text then
            self.balance = self.balance + amt
            self.saveAccount()
            addStatement(amt, 0, text)
            return true
        end
        return false
    end

    rTable.RemoveMoney = function(amt, text)
        if type(amt) == 'number' and text then
            if amt <= self.balance then
                self.balance = self.balance - amt
                self.saveAccount()
                addStatement(0, amt, text)
                return true
            end
        end
        return false
    end

    return rTable
end

function createSavingsAccount(cid)
    local completed = false
    local success = false
    local getSavingsAccount = MySQL.Sync.fetchAll('SELECT * FROM bank_accounts WHERE citizenid = ? AND account_type = ? ', { cid, 'Savings' })
    if getSavingsAccount[1] == nil then
        MySQL.Async.insert('INSERT INTO bank_accounts (citizenid, amount, account_type) VALUES (?, ?, ?)', { cid, 0, 'Savings' }, function()
            savingsAccounts[cid] = generateSavings(cid)
            success = true
            completed = true
        end)
        repeat Wait(0) until completed == true
        return success
    end
    return false
end

exports('createSavingsAccount', function(cid)
    return createSavingsAccount(cid)
end)
