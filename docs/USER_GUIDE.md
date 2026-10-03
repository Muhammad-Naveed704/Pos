# StoreFlow POS — User Guide

Version 1.0 · Windows 10 (1809) or later · Works fully offline

StoreFlow POS is a point-of-sale and back-office app for shops, pharmacies,
groceries and retail stores. Everything is stored on your computer; no
internet connection or online account is needed.

Support: mnaveed2862@gmail.com · 0344 2862704 (call or WhatsApp)

---

## 1. First start

1. Open **StoreFlow POS** from the Start menu.
2. The setup wizard asks for:
   - Business name, first store (branch) name, address and phone.
   - **Owner account** — username and password (at least 8 characters).
   - Currency, number format, time zone, tax behaviour and receipt footer.
3. When setup finishes, StoreFlow shows a **recovery key** once.
   Write it down or print it and keep it safe. It is the only way to reset
   the owner password without the old one.
4. Sign in with the owner account.

> Passwords are never stored in plain text. If a cashier forgets their
> password, the owner resets it in **Users & roles**.

## 2. The screen

- **Sidebar** (left): all modules, grouped as Sell, Catalog, People,
  Operations and Administration. `Ctrl+B` collapses it. The card at the bottom
  shows the active store; click it to switch stores.
- **Top bar**: product search (type a name, SKU or barcode and press Enter),
  *Offline ready* status, store switcher, light/dark mode, notifications
  (low stock, out of stock, overdue credit) and your user menu
  (Settings, Help & support, Lock, Sign out).
- `Ctrl+L` locks the screen without losing the sale in progress.

## 3. Recommended setup order

1. **Settings → Business & regional** — currency, decimal style, time zone.
2. **Settings → Checkout & tax** — tax mode (No tax / Added on top / Included
   in price), tax name and registration number, maximum discount, price
   override and negative-stock rules.
3. **Stores** — add other branches if you have them.
4. **Categories** — create *parent categories* first (e.g. Grocery,
   Pharmacy), then sub-categories (Rice, Oil, Tablets). See section 5.
5. **Products** — add products one by one or import a CSV file.
6. **Users & roles** — create a login for every cashier.
7. **Settings → Receipt designer** — paper size, logo, footer, printer.
8. **Settings → Data & backup** — create a first backup and switch on
   automatic backups.

## 4. Products

**Products → New product**

- *Basic details*: name, short name (for small receipts), SKU (the magic-wand
  button suggests one), barcode (scan with the camera button or press the
  generate button for an in-store EAN-13), category and selling unit.
- *Product image*: **Upload image** chooses a JPG/PNG/WEBP. The picture is
  copied into StoreFlow's data folder and resized automatically, so moving or
  deleting the original file does not matter. Use the bin button to remove it.
- *Pricing*: cost price, selling price (the margin is shown), wholesale price,
  tax rate and default discount.
- *Stock & store*: stock on hand (changes are recorded as stock movements),
  reorder level, store-specific price or discount, and switches for
  **Active**, **Track stock** and **Sold in this store**.

**Import / Export** (top right): download the CSV template, fill it in Excel,
then import. You see a preview (new / update / skip / error) before anything
is saved. Missing categories are created for you. When *Safety backup before
restore and bulk imports* is on, a backup is made automatically first.

The list shows the photo, category, price, stock and status
(Active, Low stock, Out of stock, Inactive). Click a row or use ⋮ to edit,
duplicate or deactivate. Products are never deleted, only deactivated, so old
sales keep their history.

## 5. Categories

- **All categories** tab: every category with code, parent, number of
  products, sort order and status.
- **Parent categories** tab: your top-level groups as cards with their
  sub-categories. Use **New parent category** (top right) to create one, and
  **Add sub-category** on a card to create a child inside it.
- In the category form, **Parent** is optional. Leave *No parent (top level)*
  for a main group. The **+** button next to Parent creates a new parent
  category without leaving the form.
- *Sort order*: lower numbers appear first on the POS category chips.

## 6. Selling (Point of Sale)

1. Scan a barcode with a USB scanner (works even when the search box is not
   selected), search by name/SKU, or click a product card's **Add to cart**.
   `F2` selects the search box; press `F2` again to scan with the webcam.
2. Change quantity with − / +, or click a line to edit quantity, price
   (if allowed) or line discount.
3. `F3` choose or quickly create a customer, `F6` sale discount,
   `F4` hold the sale, `F9` resume a held sale, note button for a sale note.
4. `F7` **Pay**: enter cash/card/bank/other amounts; split tenders are
   supported and change is calculated. `F8` completes an exact cash sale.
5. After completing: **P** print, **V** preview, **Save PDF**, or Enter for a
   new sale.

**Credit (udhaar) sales** — in the payment window choose *Partial* or
*Credit*. A customer is required (walk-in customers must pay in full).
Choose a due date. If the customer would go over their credit limit, a user
with *Override credit limit* permission can approve it.

## 7. Returns, refunds and voids

- `Ctrl+R` on the POS, or Sales history → ⋮ → **Return items**: scan the
  receipt barcode or type the invoice number, choose items and quantities,
  choose whether each goes back to stock, and how money is returned.
- If the invoice still has unpaid credit, the return reduces that balance
  first; only the rest is paid back.
- **Void** cancels an entire sale from today (only when nothing was refunded
  or paid on account).

## 8. Sales history

Search by invoice, date range, customer, cashier, payment method and status.
Open a sale to view it, print or save the receipt, return items or void.

## 9. Customers, credit and receivables

- **Customers**: name, phone, loyalty points, total purchases, last purchase,
  balance and status. Filter Active/Inactive and sort.
- Open a customer for their **account**: Overview, Invoices (change due dates),
  Ledger (every sale, payment and return with running balance; PDF/print
  statement) and Payments.
- **Receive payment** (`Ctrl+Shift+P` anywhere): amount, method, reference,
  date. It is applied to the oldest invoices first, or choose invoices
  yourself. A payment entered by mistake can be reversed.
- **Receivables**: total owed, overdue, due this week and every customer
  with a balance.

## 10. Inventory

- **Stock** tab: every tracked product with photo, SKU, category, stock,
  reorder level, cost and retail value and status. Filter Low / Out of stock /
  Negative. ⋮ → adjust stock (with a reason) or change reorder level.
- **Stock count**: enter counted quantities; differences are adjusted.
- **Transfer**: move stock to another store.
- **Movements** tab: the full stock ledger.

## 11. Purchases

Record supplier deliveries (goods received) to add stock and optionally
update cost prices, and record returns to suppliers. Manage suppliers in the
Suppliers tab.

## 12. Cashbook

Open a cash drawer session with the opening float, record pay-ins and
pay-outs (expenses, supplier payments, owner drawings), then close with a
counted amount; StoreFlow shows over/short. Cash sales, cash refunds and
customer cash payments are added automatically.

## 13. Reports

Sales summary, daily sales, products (with profit), categories, cashiers,
payment methods, purchases, stock valuation, and customer-account reports
(balances, credit sales, payments received, outstanding with aging, overdue,
customer statement). Choose a date range and export **CSV** or **PDF**.

## 14. Users & roles

Create users, assign a role and the stores they may use. Built-in roles:
Owner, Admin, Manager, Cashier, Inventory Staff. In **Roles & permissions**
switch individual permissions on or off, or create your own roles. Users must
sign in again after their role changes.

## 15. Receipts and printing

**Settings → Receipt designer**: 58 mm or 80 mm thermal, A4 or A5 invoice;
text size; title; logo; address, phone, email, website; header, policy and
footer messages; what to show (cashier, customer, SKU, tax breakdown,
barcode). The live preview updates as you type. **Save design** applies it.

Choose your printer under *Printer*. With *Print directly* on, receipts go
straight to that printer; otherwise StoreFlow asks which printer to use (you
can tick *Always print here*). Use **Test print** to check alignment.

## 16. Backups and restore

**Settings → Data & backup**

- **Create backup** writes one `.storeflowbackup` file (database, settings,
  theme, receipt layout, product photos and logo) and checks it after
  writing.
- **Automatic backups**: daily, weekly or monthly into a folder you choose,
  keeping the newest 5, 10 or 20. Use an external drive or a synced folder
  (OneDrive/Google Drive) so a backup survives a broken PC.
- **Verify a backup** checks any backup file.
- **Restore from backup** replaces all data. A safety backup of the current
  data is made first, and you type RESTORE to confirm. Everyone signs in
  again afterwards.

## 17. Appearance

**Settings → Appearance** (per computer): light/dark/system mode, colour
themes (StoreFlow Orange by default, Windows accent or any colour), font,
text size, density and animations.

## 18. Keyboard shortcuts

| Keys | Action |
| --- | --- |
| F2 | Search products (again: camera scanner) |
| F3 | Choose customer |
| F4 | Hold sale |
| F6 | Sale discount |
| F7 | Take payment |
| F8 | Exact cash checkout |
| F9 | Held sales |
| F10 / Ctrl+Enter | Complete payment |
| Ctrl+R | Return items |
| Ctrl+N | New sale |
| Ctrl+Shift+P | Receive customer payment |
| Ctrl+B | Collapse sidebar |
| Ctrl+L | Lock |
| Esc | Close dialog |

## 19. Troubleshooting

| Problem | What to do |
| --- | --- |
| Forgot owner password | On the sign-in screen choose *Forgot password* and enter the recovery key. |
| Forgot cashier password | Owner/Admin: Users & roles → edit user → set a new password. |
| Printer prints nothing | Check the printer in Windows, then Receipt designer → choose printer → Test print. Thermal printers need the 58/80 mm paper setting. |
| Camera scanner shows no picture | Windows Settings → Privacy & security → Camera → allow StoreFlow POS. Close other apps using the camera. |
| USB scanner types into the wrong place | Make sure the POS page is open; scans are captured automatically there. |
| Product cannot be sold beyond stock | Receive stock in Purchases, adjust stock, or enable *Allow selling below zero stock*. |
| Moving to a new PC | Create a backup, install StoreFlow on the new PC, finish setup, then Restore from backup. |

Where is my data? `%APPDATA%\com.storeflow\StoreFlow POS\StoreFlow POS\` (the Microsoft Store version
keeps it inside the app's private package folder). Back it up with
**Data & backup**, not by copying files while the app is running.
