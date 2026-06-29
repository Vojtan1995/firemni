# P0 rollout a change management

## Release paket

Každý release obsahuje vlastníka, commit/tag, migrace, rollback, výsledky testů,
security změny, známá rizika a jméno schvalovatele.

## Rehearsal

Na stagingu: migrace, admin enrollment, TOTP login, recovery, step-up, privacy
export, anonymizace, restore, load test, pentest retest a hlavní business flow.

## Produkce

1. Bootstrap pouze pred verejnym provozem: docasne nasadit backend s `ADMIN_MFA_REQUIRED=false`, kompatibilnim klientem a platnym `MFA_DATA_KEY`.
2. Vydat kompatibilní Android/Windows klient.
3. Nastavit silná hesla minimálně dvěma adminům.
4. Enrollovat TOTP a ověřit recovery kódy v trezoru.
5. Ověřit, že platný `MFA_DATA_KEY` je nastavený i pro live konfiguraci.
6. Zapnout `ADMIN_MFA_REQUIRED=true` před zpřístupněním produkce uživatelům.
7. Zvýšit minimální podporovaný klientský build.
8. Ověřit backup/restore monitoring.
9. Spustit login → sync → foto → export smoke.
10. Monitorovat chyby, výkon a login failures nejméně 72 hodin.

Produkční env example je fail-closed (`ADMIN_MFA_REQUIRED=true`). Hodnota `false`
je povolena jen pro výše popsaný bootstrap a nesmí zůstat v live provozu.

Backend při kroku 6 provede startup gate: vyžaduje nejméně dva aktivní adminy,
u každého heslo, aktivní TOTP, nepoužitý recovery kód a auditní událost
`mfa_recovery_used`. Nesplněný gate ukončí start procesu před otevřením portu.

## Rollback

Rollback smí použít pouze build kompatibilní s novými DB tabulkami a MFA. Nesmí
obnovit admin login bez MFA. Databázové migrace se destruktivně nevracejí.

## Gate uzavření etapy

Vyžaduje úspěšný restore report, dva MFA adminy, GDPR schválení, load report,
externí pentest a retest, produkční smoke a seznam residual risks. Odložené
šifrování zařízení a certifikační evidence zůstávají otevřené P0.
