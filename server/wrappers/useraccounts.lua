function generateSavings(cid) return BankAccounts.load(cid, 'Savings') end
function createSavingsAccount(cid) return BankAccounts.create(cid, 'Savings', 0) end
exports('createSavingsAccount', createSavingsAccount)
