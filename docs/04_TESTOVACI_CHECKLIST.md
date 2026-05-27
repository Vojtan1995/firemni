
# Testovací checklist

## Auth
- [ ] správný login
- [ ] špatný PIN
- [ ] deaktivovaný účet
- [ ] role worker nemá admin endpointy

## Worker flow
- [ ] zadání existující stavby
- [ ] zadání neexistující stavby
- [ ] výběr patra
- [ ] seznam čísel ucpávek
- [ ] vytvoření ucpávky
- [ ] více prostupů
- [ ] více materiálů
- [ ] přidání fotky

## Statusy
- [ ] rozpracované worker edituje
- [ ] zkontrolované worker needituje
- [ ] vedení vrátí na rozpracováno
- [ ] fakturované je zamčené

## Offline
- [ ] vytvoření offline
- [ ] restart aplikace před syncem
- [ ] návrat online
- [ ] upload fotky po selhání
- [ ] ruční sync tlačítko

## Konflikty
- [ ] duplicitní číslo online
- [ ] duplicitní číslo offline
- [ ] editace změněné entity
- [ ] editace zamčené entity

## Exporty
- [ ] filtr zakázky
- [ ] filtr pracovníka
- [ ] filtr období
- [ ] filtr statusu
- [ ] CSV s českou diakritikou

## Data
- [ ] soft delete
- [ ] obnova adminem
- [ ] archivace zakázky
- [ ] log každé důležité akce
