# Sprint 15 — v1.1: CSV import

Owner decision 24 (`docs/PROGRESS.md`): every default accepted ("run"). No schema change: imported transactions use
the existing `imported` source, which backups already carry.

## Decisions
1. **Entry:** More › Settings › Data › Import transactions from CSV…, a file picked in Files; nothing is fetched.
2. **Columns:** Date, Amount, Description and Category are guessed from the header (English and Spanish names) and
   can each be changed. Dates: year-first, month-first or day-first; when the file fits more than one, the user picks.
3. **Sign:** negative = spending, positive = income; a switch flips it. Transfers are never inferred.
4. **Preview:** every row before anything is saved: ready, likely duplicate (same local day, amount, type and
   description as a recorded transaction; unticked by default), or skipped with the reason and its file line.
5. **Save:** the ticked rows into one chosen active account, posted, in one save: any refusal saves nothing.
   Categories match an active one by name (case and accents ignored) that allows the row's type; otherwise
   Uncategorized. No categories or merchants are created; the description goes to notes.
6. **Limits:** 5 MB and 5,000 rows per file; UTF-8, or Latin-1 for older bank exports. Amounts read as banks write
   them ("-12.50", "12.50-", "(12.50)", "$1,234.56", "1.234,56"); a lone "." with three digits after it reads as a
   decimal point ("12.500" = 12.50).

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | `CSVParser`, `CSVAmount`, `CSVDateFormat`, `CSVMapping` (Core) | ☐ | tests |
| 2 | `CSVImportPlanner` preview, duplicates, categories (Core) | ☐ | tests |
| 3 | `importTransactions` one-save service + `existingForImport` | ☐ | tests |
| 4 | Data › Import and the preview screen | ☐ | ☐ (local: a real bank-style file) |
| 5 | Data-safety review | ☐ | — |

## Close-out
☐ CI green · ☐ walk (`docs/walk/sprint-15/`) · ☐ data-safety review · ☐ PROGRESS + PR
