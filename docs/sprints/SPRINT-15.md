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
6. **Limits:** 5 MB and 5,000 rows per file; UTF-8, or Latin-1 for older bank exports.

## Data-safety review (Sprint 15) — fixed before the gate
Nothing that could be misread is guessed; it is skipped with its reason, or the user must choose:
- Amounts: one sign marker ("-", trailing "-", parentheses, "+", DR, CR); only the household currency's code or
  symbol; thousands in groups of three; no more decimals than the currency has (extra zeros fine). "1.234" in a
  two-decimal currency, "12.505", "12.50 USD", "1.5E3", "(-12.50)" are refused. Above `Money.maxPlanMinorUnits` is
  skipped as too large (a reference or balance column), and the service refuses it too.
- The decimal mark is detected from the column; when values like "1.234" leave it open, the user picks. Dates that
  read more than one way must be chosen too (no silent month-first).
- A row with more or fewer fields than the header (a stray separator) is skipped; skip messages carry the real file
  line, past blank lines and multi-line fields.
- Every row is listed (not just 300); the preview recomputes only when the mapping or duplicate data change; per-row
  ticks are explicit and survive recomputes; Import waits for the duplicate check, which covers only live (not
  cancelled) transactions in the chosen account over the file's dates, and says so if it fails.
- The app's own CSV export is refused for import (restore a backup instead): it carries types, statuses and
  transfers the importer would misread.
- Two-digit years 70–99 are 19xx; only ASCII digits count; the size limit is checked on the file's bytes.

## Items
| # | Item | Built (CI green) | Walked |
|---|---|---|---|
| 1 | `CSVParser`, `CSVAmount`, `CSVDateFormat`, `CSVMapping` (Core) | ☐ | tests |
| 2 | `CSVImportPlanner` preview, duplicates, categories (Core) | ☐ | tests |
| 3 | `importTransactions` one-save service + `existingForImport` | ☐ | tests |
| 4 | Data › Import and the preview screen | ☐ | ☐ (local: a real bank-style file) |
| 5 | Data-safety review | ☐ | — |

## Close-out
☑ CI green (run 36268510203, `25afbec`) · ☑ walk (`docs/walk/sprint-15/`) · ☑ data-safety review · ☑ PROGRESS + PR
