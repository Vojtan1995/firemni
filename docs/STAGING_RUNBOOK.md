# Izolovaný staging

## Povinná topologie

- samostatný Railway project/service,
- samostatná PostgreSQL databáze,
- samostatný R2 bucket bez produkčních objektů,
- samostatné JWT, MFA, DB a R2 secrets,
- `NODE_ENV=production` pro ověření produkčních guardů,
- `CORS_ORIGIN` pouze staging klient,
- `PUBLIC_UPLOADS=false`, `STORAGE_DRIVER=s3`,
- `ADMIN_MFA_REQUIRED=true`,
- `SENTRY_DSN` do staging projektu,
- vypnuté Telegram/e-mail produkční notifikace.

## Zákazy

- nekopírovat produkční DB,
- nepoužívat produkční R2 credentials,
- nepoužívat skutečná jména, adresy, fotografie ani zprávy,
- nepoužívat staging secrets v lokálním `.env`,
- nespouštět load seed bez `ALLOW_LOAD_SEED=1`.

## Založení

1. Vytvořit Railway staging project a PostgreSQL.
2. Vytvořit R2 bucket `unifast-staging`.
3. Nastavit env podle `backend/.env.staging.example`.
4. Nasadit migrace.
5. Spustit běžný seed a poté volitelně load seed.
6. Ověřit `/ready`.
7. Ověřit, že staging nemá přístup k produkčnímu bucketu.
8. Zapsat URL a vlastníky do P0 registru.

## Akceptace

- staging může být kompletně smazán bez dopadu na produkci,
- produkční credentials na stagingu nejsou,
- testovací uživatelé jsou označeni jako syntetičtí,
- `/ready` kontroluje staging DB a staging storage.
