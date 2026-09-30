# Modal Mobile Footer Audit & Remediation Report

### Root Cause
Modals across the application relied on `h-screen` or `100vh` viewports coupled with `items-center` centering. On mobile browsers (Android Chrome and Safari iOS), dynamic system chrome (address bar and navigation bar) reduces the visible viewport by 60–100px; centering an uncontracted `100vh` modal card pushed the bottom action footers off-screen. Furthermore, action footers lacked `sticky bottom-0 z-20`, `shrink-0`, and safe-area inset padding (`env(safe-area-inset-bottom)`), causing them to be clipped or trapped below unconstrained scroll containers.

---

### Audit & Remediation Table

| Modal / Drawer | File | Footer visible on mobile before? | Fix applied | Tested (pass/fail) |
|---|---|---|---|---|
| **Adjust Inventory Stock** | `src/components/inventory/AdjustStockModal.tsx` | ❌ No (clipped ~80px below viewport) | Replaced `100vh` with `h-[100dvh] max-h-[100dvh]`; converted form body to `flex-1 min-h-0 overflow-y-auto overscroll-contain`; implemented solid sticky footer with `sticky bottom-0 z-20`, safe-area inset padding, `min-h-[48px]` touch targets, live dynamic labels & counters across Restock, Remove, and Reconciliation modes. | **PASS** (360px, 390px, 412px, 1280px) |
| **Print Barcode Labels** | `src/components/barcode/BarcodePrintModal.tsx` | ❌ No (pushed off-screen below preview) | Fixed outer overlay to `100dvh`; pinned sticky action bar with `sticky bottom-0 z-20`, safe-area padding, synchronous tap print handler, and live sticker count. | **PASS** (360px, 390px, 412px, 1280px) |
| **Quick Edit Price** | `src/components/inventory/QuickPriceModal.tsx` | ❌ No (clipped on smaller screens) | Switched to `h-[100dvh] max-h-[100dvh]`, scrollable content body, sticky footer with `min-h-[48px]` touch targets. | **PASS** (360px, 390px, 412px) |
| **Vyapar Barcode Generator Workspace** | `src/components/barcode/CreateBarcodeModal.tsx` | ❌ No (footer cut off when keyboard opens) | Added `100dvh` overlay constraints, `max-h-[94dvh]`, scrollable body, and sticky bottom action buttons with touch-target sizing. | **PASS** (360px, 390px) |
| **Sticker Sheet Preview Modal** | `src/components/barcode/BarcodeSheetPreviewModal.tsx` | ❌ Partial (cut off below bottom toolbar) | Added `100dvh` container, scrollable sheet canvas, sticky safe-area footer. | **PASS** (360px, 390px) |
| **Create Custom Label Size Modal** | `src/components/barcode/CreateCustomSizeModal.tsx` | ❌ No (pushed off bottom) | Added `100dvh` container, sticky footer with safe-area padding and 44px buttons. | **PASS** (360px, 390px) |
| **Record Expense Modal** | `src/components/expenses/RecordExpenseModal.tsx` | ❌ No (cut off by mobile keyboard) | Container bounded to `h-[100dvh] max-h-[100dvh]`, `flex-1 min-h-0 overflow-y-auto`, sticky footer with `min-h-[48px]` submit button. | **PASS** (360px, 390px) |
| **Add / Edit Product Modal** | `src/components/AddProductModal.tsx` | ❌ No (pushed off-screen on mobile) | Container set to `100dvh`, modal card `max-h-[92dvh]`, scrollable form body, sticky bottom actions with `min-h-[48px]`. | **PASS** (360px, 390px) |
| **Catalog Edit Product Modal** | `src/components/CatalogModal.tsx` | ❌ No (save button hidden behind keyboard) | Added `100dvh` container, scrollable field body, sticky safe-area footer with `min-h-[48px]` buttons. | **PASS** (360px, 390px) |
| **Add Ad-Hoc / Unregistered Item Modal** | `src/components/pos/AddUnregisteredItemModal.tsx` | ❌ No (overflowing viewport) | Set `100dvh` overlay, card `max-h-[90dvh]`, scrollable inputs, and sticky safe-area footer with 44px buttons. | **PASS** (360px, 390px) |
| **Hardware Barcode Redirect Dialog** | `src/components/pos/BarcodeRedirectDialog.tsx` | ⚠️ Partially visible (tight viewport clipping) | Added `100dvh` overlay, `max-h-[92dvh]`, sticky safe-area action buttons with touch-friendly sizing. | **PASS** (360px, 390px) |
| **Save as Deposit Order Modal** | `src/pages/Pos.tsx` | ❌ No (actions pushed off-screen) | Container updated to `100dvh`, form body scrollable, sticky safe-area action footer with `min-h-[48px]` buttons. | **PASS** (360px, 390px) |
| **Select Variant / Size Modal** | `src/pages/Pos.tsx` | ❌ No (add button pushed off bottom) | Container updated to `100dvh`, scrollable variant list, sticky safe-area footer with `min-h-[48px]` Add button. | **PASS** (360px, 390px) |
| **POS Price Edit & Inventory Modal** | `src/pages/Pos.tsx` | ❌ Partial (cut off on 360px devices) | Container set to `100dvh`, scrollable content, sticky safe-area action buttons with `min-h-[44px]`. | **PASS** (360px, 390px) |
| **Invoice Preview Modal** | `src/pages/Dashboard.tsx` | ⚠️ Partial (table clipped bottom) | Container bounded to `100dvh`, card `max-h-[95dvh]`, scrollable invoice view with safe-area padding. | **PASS** (360px, 390px) |
| **Low Stock Audio Alarm Modal** | `src/components/dashboard/LowStockAlarmModal.tsx` | ❌ No (silence CTA cut off on small phones) | Container set to `100dvh`, list scrollable, sticky safe-area footer with `min-h-[48px]` silence button. | **PASS** (360px, 390px) |
| **Create Advance Order Modal** | `src/pages/AdvanceOrders.tsx` | ❌ No (actions clipped below screen) | Outer container set to `100dvh`, body scrollable, sticky bottom actions with `min-h-[48px]`. | **PASS** (360px, 390px) |
| **Receive Payment Modal** | `src/pages/AdvanceOrders.tsx` | ❌ No (payment button off-screen) | Outer container set to `100dvh`, body scrollable, sticky safe-area payment button with `min-h-[44px]`. | **PASS** (360px, 390px) |
| **Advance Order Details Drawer** | `src/pages/AdvanceOrders.tsx` | ⚠️ Partial (bottom action buttons clipped) | Drawer panel bounded to `100dvh`, sticky safe-area action bar. | **PASS** (360px, 390px) |
| **Stock History Drawer** | `src/components/inventory/StockHistoryDrawer.tsx` | ⚠️ Partial (close button clipped on small heights) | Backing container and panel updated to `100dvh`. | **PASS** (360px, 390px) |
| **Barcode Settings Drawer** | `src/components/barcode/BarcodeSettingsDrawer.tsx` | ⚠️ Partial (save settings cut off on small screens) | Backing container and panel updated to `100dvh`, sticky footer with safe-area padding. | **PASS** (360px, 390px) |
| **Cart Drawer** | `src/components/Drawers.tsx` | ⚠️ Partial (View Cart button clipped by gesture bar) | Added safe-area padding and `min-h-[48px]` to sticky checkout CTA. | **PASS** (360px, 390px) |
| **Product Detail Modal** | `src/components/ProductDetailModal.tsx` | ⚠️ Partial (variant bar clipped by bottom toolbar) | Added `100dvh` overlay constraints and `sticky bottom-0` to mobile action bar. | **PASS** (360px, 390px) |
| **Variant Selector Bottom Sheet** | `src/components/VariantSelectorModal.tsx` | ✅ Yes (already used `92svh` & safe-area) | Verified structure and touch targets. | **PASS** (360px, 390px) |
| **Confirm Image Upload Modal** | `src/components/dashboard/ImageMappingTool.tsx` | ❌ No (pushed off on small screens) | Added `100dvh` overlay, scrollable body, sticky safe-area footer with `min-h-[44px]` buttons. | **PASS** (360px, 390px) |

---

### Verification Summary
- **Viewports tested**: 360px × 740px (Android Chrome small), 390px × 844px (iPhone 12/13/14), 412px × 915px (Android Chrome standard), and 1280px × 800px (Desktop).
- **AdjustStockModal Modes Verified**:
  1. **Restock**: Cancel and Confirm visible without scrolling; initial count 0 has Confirm button disabled with label `"Confirm Restock (+0 Units)"`; clicking quick presets (`+1`, `+5`, `+10`, `+25`, `+50`, `+100`) or stepper (`-`/`+`) immediately enables the button and live-updates the count (e.g. `"Confirm Restock (+10 Units)"`); tapping Cancel closes the modal.
  2. **Remove Stock**: Cancel and Confirm visible; initial count 0 has Confirm button disabled; clicking quick presets (e.g. `-5`) updates count live to `"Confirm Removal (-5 Units)"` and enables button; stock validation enforces maximum limit.
  3. **Reconciliation**: Cancel and Confirm visible; initial physical count equal to stock (delta = 0) disables Confirm button; adjusting count via stepper (`+`/`-`) updates label live to `"Confirm Reconciliation (Set 38 Units)"` and enables button.
- **Sticky Behavior**: Scrolling modal body keeps action bar firmly pinned to bottom of viewport with solid background and top separator.
- **Desktop Appearance**: Unchanged; centered floating modal card preserved with identical spacing, fonts, colors, and border radius.
- **Site-Wide Safety**: `src/components/Footer.tsx` remains completely untouched.
