## Cell Text Display Epic

### Purpose

Improve how text is displayed in journey matrix grid cells so users can read more content at a glance, know when content has been truncated, and access the full text without always needing to click into a cell.

### Scope

- Increase the number of visible lines in each cell
- Signal clearly when text has been cut off
- Provide quick access to full text on hover

### Explicit non-goals

- Changing the cell detail side panel
- Modifying how text is stored or input
- Infinite scroll or per-cell expand/collapse controls

---

### US-CTD-01 — Show more text per cell

**Story:** As a user scanning the journey matrix, I want each cell to display more lines of text so that I can read more of the content without having to click into every cell.

**Acceptance Criteria:**
- Each grid cell displays up to **5 lines** of text (increased from 3)
- Text remains the same font size (12px) and line height (1.45)
- Cells with less than 5 lines of content are unaffected in appearance
- Row height grows naturally to accommodate the extra lines

**Files:** `webapp/protype-2/src/index.css` → `.jm-grid-content`

---

### US-CTD-02 — Show ellipsis when text is truncated

**Story:** As a user, I want to see `...` at the end of a cell when text has been cut off so that I know there is more content to read.

**Acceptance Criteria:**
- When cell content exceeds 5 lines, a `...` appears at the point of cutoff
- The ellipsis is rendered natively by the browser via `-webkit-line-clamp`
- No extra UI elements or buttons are required
- Empty cells are not affected

**Files:** `webapp/protype-2/src/index.css` → `.jm-grid-content`

---

### US-CTD-03 — Hover tooltip shows full cell text

**Story:** As a user, I want to hover over a cell and see the full text in a tooltip so that I can quickly read the complete content without opening the side panel.

**Acceptance Criteria:**
- Hovering any grid cell with content shows a native browser tooltip with the full untruncated text
- The tooltip uses the standard HTML `title` attribute
- Cells with no content show no tooltip
- The tooltip text matches exactly what is stored in the cell

**Files:** `webapp/protype-2/src/journeyMatrixTabulatorHelpers.ts` → `formatMatrixCellMarkup`

---

### US-CTD-04 — Word wrap text within cell boundaries

**Story:** As a user, I want text in each cell to wrap naturally within the column width so that no words are cut off mid-character and all content stays readable inside the cell.

**Acceptance Criteria:**
- Cell text wraps onto the next line when it reaches the column edge
- Long words or strings without spaces do not overflow outside the cell boundary
- Wrapping works consistently across all lenses and stages
- No horizontal scrollbar appears inside a cell

**Files:** `webapp/protype-2/src/index.css` → `.jm-grid-content`
