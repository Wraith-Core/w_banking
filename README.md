# w_banking

Banking system for **Wraith Framework RedM** featuring bank teller locations across major towns, personal savings accounts, gang accounts, transfers, transaction statements, and `/givecash`.

## Key Features

- Bank tellers in Valentine, Rhodes, Saint Denis, Blackwater, and more.
- Personal savings accounts (`bank_accounts`), gang accounts, and full transaction statements (`bank_statements`).
- Player-to-player transfers and `/givecash <id> <amount>`.

## Installation

1. Import `w_banking.sql` into your database.
2. Place `w_banking` in `resources/[wraith]/w_banking`.
3. Add `ensure w_banking` to `server.cfg` after `w_lib` and `w_core`.

## Key Exports

```lua
exports.w_banking:openAccountScreen()
exports.w_banking:createSavingsAccount(citizenid)
exports.w_banking:createGangAccount(gangId)
```

## Documentation & Links

- **Developer Docs:** https://wraith-core.github.io/docs/#/resources/economy-jobs
- **txAdmin Recipe:** https://github.com/Wraith-Core/txAdminRecipe

## License

GPL-3.0 — see [LICENSE](LICENSE).
