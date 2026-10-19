# Receipt verification and Android actions, 0.2.7+9

The live API response inspected on 2026-10-19 contained only Euromilhoes
083/2026 (pagination total=1). Selecting a contest from the calendar did not
imply its result was stored; 081/2026 therefore remained pending.

The app now supplements local results with three independently parsed official
cartaz snapshots, 081/2026, 082/2026 and 083/2026. All 13 prize tiers, identifiers,
dates and keys passed the existing strict parser and Android validation contract.
Raw captures and hashes are in `evidence/recent-official-results.json`.
081/082 were retrieved using the existing official form's selectContest field;
083 reuses the existing real capture and was compared with the live API.

This is limited offline coverage, not an implementation of full historical
retrieval or a deployment to the production API. Stored complete records take
precedence over bundled snapshots so subsequent server corrections are used.
Partial records cannot downgrade a complete snapshot. Missing contests remain
explicitly unverified; the receipt does not show a zero prize total while no
prize can yet be identified.

Each contest now has a result card with its winning key and verification state.
Receipt actions are pinned in a SafeArea above Android system navigation;
the list scrolls independently. Deletion still requires confirmation.

Regression coverage reproduces the five user-supplied lines for 081/2026
(no prize), checks a winning 5+0 line against its real tier amount, preserves
stored corrections and unresolved contests, and tests the deletion confirmation
on a 360x640 screen with a 34-pixel system-navigation inset.
