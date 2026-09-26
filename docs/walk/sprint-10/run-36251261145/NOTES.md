# Sprint 10 walk — run 36251261145 (`ffd3b8a`, CI green)

Seen, screenshot by screenshot:
- **Accounts (light):** Main account (Bank account · Default, CA$0.00) and Savings (CA$500.00); household total
  CA$500.00. Correct.
- **New Transfer (light):** From defaults to Main account, To Savings, amount 100, the transfer footer, date and
  status. Correct.
- **Budget (light):** "Transfer to Savings", "Main account → Savings", CA$100.00 unsigned, transfer icon; New
  transfer and filter buttons in the toolbar. Correct.
- **Dashboard (light):** current CA$500.00 unchanged by the transfer; Accounts card Main −CA$100.00, Savings
  CA$600.00; spent this week CA$0.00 (the transfer is not spending). Correct.
- **Account editor (dark):** readable, Save disabled until a name is typed. Correct.
- **Accounts (largest text): defect.** The row broke "Main ac-count" and "CA$0 .00" across lines. Fixed in the
  next commit (the amount moves under the name and the icon goes at accessibility sizes); re-walk on the next
  green run.
