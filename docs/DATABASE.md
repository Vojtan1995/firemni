# DATABASE.md

## Hlavní tabulky
- users
- user_sessions
- jobs
- job_floors
- seals
- seal_entries
- seal_entry_materials
- seal_photos
- sync_mutations
- activity_log
- change_log
- login_log
- error_log

## Kritický unikátní index
`job_id + floor_id + seal_number`
musí být unikátní mezi nesmazanými ucpávkami.

## Pravidla
- žádné hard delete
- používat deleted_at
- worker může editovat pouze draft
- seals mají version pro sync konflikty
- fotky ukládat mimo DB, do DB jen metadata a cestu

## Statusy
- draft
- checked
- invoiced

## seal_photos
Fotky:
- patří celé ucpávce
- worker je nemůže mazat
- ukládat metadata + cestu

## sync_mutations
Použít pro idempotentní sync:
- mutation_id UNIQUE
- device_id
- payload
- processed_at
