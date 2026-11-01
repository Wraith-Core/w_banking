# w_banking

## 2.0.3 (2026-11-01)

- **رسالة الرفض تذكر السبب والأرقام:** «نقدك لا يكفي: المطلوب 12.50$ ومعك 5.00$»، «رصيدك البنكي لا يكفي: المطلوب … مع ضريبة البنك، ورصيدك …»،
  «رصيد الادخار لا يكفي»، «حسابك مجمّد لدى البنك المركزي»، و«البنك غير متاح الآن». كان البنك يقول «رصيدك لا يكفي» لكل رفض.
- `/givecash` يذكر ما معك من نقد إذا كان المبلغ أكبر منه.

ما يحتاج تجربة داخل اللعبة: سحب مبلغ أكبر من الرصيد، إيداع أكبر من النقد، تحويل أكبر من الرصيد.

## الإصدار 2.0.2 — 2026-10-30

يمكن إيداع وسحب وتحويل مبالغ بأجزاء الدولار حتى منزلتين عشريتين، مثل 0.75. نصوص الواجهة تأتي من ملفات اللغة، بما فيها رسائل الضريبة وتأكيد العملية.

ما يحتاج تجربة داخل اللعبة: إيداع وسحب 0.75 والتحويل بين حسابين، والتأكد من الضريبة.

- Banking System for Wraith Core RedM

## Features
- Withdraw / Deposit at the bank counters (Valentine, Rhodes, Saint Denis, Blackwater)
- Transfer funds to another character's account number or citizen ID (online or offline)
- Savings account per character
- Gang account (server exports `createGangAccount` / `gang`)
- `/givecash [citizen id] [amount]` to hand cash to a nearby player (`#5` names whoever is on server id 5)
- 2.0.1: a bank robbery linked to a branch (w_heists 1.1.0) — while it runs, our teller and the counter prompt of that
  branch are gone and the heist's own teller (same model, same spot) stands there and raises his hands; they come back
  when the run is over (`GlobalState['w_heists:robbed'].banks[<branch id>]`)

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
