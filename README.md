# w_banking
- Banking System for Wraith Core RedM

## Features
- Withdraw / Deposit at the bank counters (Valentine, Rhodes, Saint Denis, Blackwater)
- Transfer funds to another character's account number or citizen ID (online or offline)
- Savings account per character
- Gang account (server exports `createGangAccount` / `gang`)
- `/givecash [citizen id] [amount]` to hand cash to a nearby player (`#5` names whoever is on server id 5)

## Dependencies
- w_lib (shared bootstrap `@w_lib/init.lua`: callbacks, commands, locale, blips, entity creation)
- w_core
- w_smallresources - Log bank activity

## Language
The library controls the language (`setr w_lib:locale "ar"` in server.cfg, or the player's choice in `/w_lib`).
The dictionaries live in `locales/ar.json` and `locales/en.json`; the NUI page takes its strings and
text direction from Lua on open and on every switch.

## Interaction
Bank clerks are reached through the library NUI prompt (w_lib `w.prompt.at`) in front of the counter; the key and radius are set in `Config.Prompt` (no target integration).

## Installation
- Put the resource in the `[wraith]` directory.
- Import `w_banking.sql` in your database
- Add the following code to your server.cfg
```
ensure w_lib
ensure w_core
ensure w_smallresources
ensure w_banking
```
