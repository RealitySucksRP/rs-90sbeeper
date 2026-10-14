# RS 90s Beeper — Pager Code Notes

Pager codes were never one official nationwide language. Different cities, schools, friend groups, families and crews used different dictionaries. That variation is part of the authenticity.

The default RS codebook therefore acts as a starter set. Server owners can edit `Config.Codebook.Entries`, disable the in-device CODE menu, turn code hints off, or register private codes at runtime.

## Strong period examples included

| Code | Default meaning |
|---|---|
| `07` | JUST KIDDING |
| `14` | HI |
| `123` | I MISS YOU |
| `143` | I LOVE YOU |
| `193` | MISS ME? |
| `23` | TE AMO |
| `26` | TE QUIERO |
| `45` | GOODNIGHT |
| `56` | SWEET DREAMS |
| `77` | FRIENDS FOREVER |
| `99` | NIGHT NIGHT |
| `303` | STOP PLAYING |
| `333` | LOVE |
| `411` | QUESTION / INFO |
| `423` | CALL ME |
| `424` | CALL ME BACK |
| `477` | BEST FRIENDS FOREVER |
| `637` | ALWAYS AND FOREVER |
| `823` | THINKING OF YOU |
| `831` | I LOVE YOU |
| `911` | EMERGENCY / CALL NOW |
| `1517` | KEEP IN TOUCH |
| `187` | HATE / MURDER / DEATH reference |
| `07734` | HELLO when read upside down |
| `50538` | BESOS when read upside down |
| `6000*843` | GOOD BYE |
| `1*177155*400` | I MISS YOU |
| `6000*171647` | GOOD NIGHT |
| `60*401773` | GO HOME |
| `41*705312` | HI LOSER |

## Historical references used for the starter set

- Christian Science Monitor, October 23, 1997, "Tech-Hip Teens Tell '007s' '121'" — records `123` as "I miss you" and `143` as "I love you" among teens using beepers.
- Los Angeles Times, November 26, 1997, "Teens Create Language of Pager-Speak" — publishes period quick codes including `143`, `831`, `823`, `637`, `424`, `411`, `333`, `911`, `187`, and calculator-style messages.
- 1998 pager newsgroup discussion preserved by Google Groups — documents commercial pager-code cards and the same family of quick-code conventions.
- Karen Russell, "Beeper World," Harper's Magazine, December 2014 — retrospective list remembered from real beeper use, including `123`, `143`, `193`, `23`, `26`, `423`, `07`, `303`, `45`, `56`, `911`, `77`, `477`, `07734`, and `50538`.

## Private / RP codebooks

The best 90s-RP use is often server-specific. A gang, family, business, police unit or drug crew can create codes whose meaning is known only in-character.

Example config entry:

```lua
{ code = '1875', meaning = 'MEET AT OLD WAREHOUSE', category = 'CREW', groups = { 'cartel' } }
```

Only players assigned to the `cartel` pager group will see that meaning in the optional CODE menu. Everyone can still receive the raw digits if a page is sent to them.
