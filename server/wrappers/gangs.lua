-- Gang account: a `bank_accounts` row (account_type = 'Gang', keyed by gangid) and its statement.
function loadGangAccount(gangid)
    local self = {}
    self.gid = gangid
    self.balance = 0

    local query = MySQL.Sync.fetchAll("SELECT * FROM `bank_accounts` WHERE `gangid` = ? AND `account_type` = 'Gang'", { self.gid })
    if query[1] ~= nil then
        self.balance = query[1].amount
        self.accountid = query[1].record_id
    end

    self.accountStatement = MySQL.Sync.fetchAll("SELECT * FROM `bank_statements` WHERE `account` = 'Gang' AND `gangid` = ? ORDER BY `record_id` DESC LIMIT 30", { self.gid })

    self.saveAccount = function()
        MySQL.Async.fetchAll("UPDATE `bank_accounts` SET `amount` = ? WHERE `record_id` = ?", { self.balance, self.accountid })
    end

    -- Append one statement row (deposited or withdrawn) and mirror it in the cached statement.
    local function addStatement(deposited, withdraw, text)
        local time = os.date('%Y-%m-%d %H:%M:%S')
        MySQL.Async.insert("INSERT INTO `bank_statements` (`gangid`, `account`, `deposited`, `withdraw`, `balance`, `date`, `type`) VALUES (?, ?, ?, ?, ?, ?, ?)", {
            self.gid,
            'Gang',
            deposited,
            withdraw,
            self.balance,
            time,
            text or 'Gang account'
        }, function(recordId)
            table.insert(self.accountStatement, {
                record_id = recordId,
                gangid = self.gid,
                account = 'Gang',
                deposited = deposited,
                withdraw = withdraw,
                balance = self.balance,
                date = time,
                type = text or 'Gang account',
            })
        end)
    end

    local rTable = {}

    rTable.getBalance = function()
        return self.balance
    end

    rTable.getStatement = function()
        return self.accountStatement
    end

    --- Update Functions

    rTable.addMoney = function(m, text)
        if type(m) == 'number' and m > 0 then
            self.balance = self.balance + m
            self.saveAccount()
            addStatement(m, 0, text)
            return true
        end
        return false
    end

    rTable.removeMoney = function(m, text)
        if type(m) == 'number' and m > 0 then
            if self.balance >= m then
                self.balance = self.balance - m
                self.saveAccount()
                addStatement(0, m, text)
                return true
            end
        end
        return false
    end

    return rTable
end

function createGangAccount(gang, startingBalance)
    local newBalance = tonumber(startingBalance) or 0

    local checkExists = MySQL.Sync.fetchAll("SELECT * FROM `bank_accounts` WHERE `gangid` = ? AND `account_type` = 'Gang'", { gang })
    if checkExists[1] == nil then
        MySQL.Async.insert("INSERT INTO `bank_accounts` (`gangid`, `amount`, `account_type`) VALUES (?, ?, ?)", {
            gang,
            newBalance,
            'Gang'
        }, function(success)
            if success > 0 then
                gangAccounts[gang] = loadGangAccount(gang)
            end
        end)
    end
end

exports('createGangAccount', function(gang, starting)
    createGangAccount(gang, starting)
end)
