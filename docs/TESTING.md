# Testovací checklist – Ucpávky V1

Viz také [04_TESTOVACI_CHECKLIST.md](04_TESTOVACI_CHECKLIST.md).

## Automatické testy

```bash
cd backend && npm test
cd frontend && flutter test
```

## Manuální scénáře (po spuštění DB + backend + frontend)

### Auth
- [ ] Login worker1 / PIN 1234
- [ ] Špatný PIN → chyba
- [ ] Worker nemá položky Správa / Export v menu

### Worker flow
- [ ] Stavba 12345678 → patra → seznam ucpávek
- [ ] Nová ucpávka s chipy, 2 prostupy, fotka
- [ ] Po uložení dialog Přidat další / Zpět

### Offline
- [ ] Vypnout síť → vytvořit ucpávku → data v Sync obrazovce pending
- [ ] Zapnout síť → Synchronizovat

### Management
- [ ] vedeni / 1234 → změna statusu ucpávky
- [ ] Export soupisu prací

## Spuštění prostředí

```bash
docker compose up -d
cd backend && npx prisma migrate deploy && npx prisma db seed && npm run dev
cd frontend && flutter run -d windows
```
