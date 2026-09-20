function loadGangAccount(gid) return BankAccounts.load(gid, 'Gang') end
function createGangAccount(gid, starting) return BankAccounts.create(gid, 'Gang', starting) end
exports('createGangAccount', createGangAccount)
