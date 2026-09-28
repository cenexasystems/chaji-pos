/**
 * dateRange.ts
 * ─────────────────────────────────────────────────────────────────────────────
 * Shared date-range utilities used by every filter panel in the app.
 *
 * Rules (per spec):
 *  • All ranges are calendar-based in the *local* timezone (IST), never UTC.
 *  • Today        → 00:00:00.000 … 23:59:59.999 of today.
 *  • This Week    → Monday 00:00 … Sunday 23:59:59.999 of the current ISO week.
 *  • This Month   → 1st 00:00 … last-day 23:59:59.999 of the current month.
 *  • This Year    → Jan-1 00:00 … Dec-31 23:59:59.999.
 *  • Custom       → inclusive start-of-from … end-of-to.
 *  • Timestamps are compared with Date objects (no string parsing with new Date('YYYY-MM-DD')).
 *  • Ranges are recomputed on every call (stays correct across midnight / Monday rollover).
 * ─────────────────────────────────────────────────────────────────────────────
 */

export type DatePreset = 'today' | 'week' | 'month' | 'year' | 'custom' | 'all'

export interface DateRange {
  /** Start: beginning of first day (00:00:00.000 local) */
  start: Date
  /** End: end of last day (23:59:59.999 local) */
  end: Date
}

// ─── Low-level helpers ───────────────────────────────────────────────────────

/** Returns a new Date set to 00:00:00.000 local time on the same calendar day. */
export function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0)
}

/** Returns a new Date set to 23:59:59.999 local time on the same calendar day. */
export function endOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999)
}

/**
 * Returns a YYYY-MM-DD string for a local-time Date.
 * Safe replacement for `d.toISOString().slice(0, 10)` which gives UTC date.
 */
export function toLocalDateStr(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${dd}`
}

/**
 * Parses a YYYY-MM-DD string as a LOCAL date (not UTC).
 * `new Date('2026-09-28')` gives UTC midnight which is the previous day in IST.
 * This function returns the correct local midnight.
 */
export function parseLocalDate(dateStr: string): Date {
  const parts = dateStr.split('-').map(Number)
  return new Date(parts[0], parts[1] - 1, parts[2])
}

// ─── Core range factory ──────────────────────────────────────────────────────

/**
 * Compute a DateRange for a given preset.
 *
 * @param preset   - The preset label.
 * @param now      - Reference "now" (defaults to new Date(), caller can override for testing).
 * @param custom   - Required when preset === 'custom'. Both fields must be YYYY-MM-DD strings.
 */
export function getDateRange(
  preset: Exclude<DatePreset, 'all'>,
  now = new Date(),
  custom?: { from: string; to: string },
): DateRange | null {
  switch (preset) {
    case 'today':
      return { start: startOfDay(now), end: endOfDay(now) }

    case 'week': {
      // ISO week: Monday = day 1, Sunday = day 7
      const dayOfWeek = now.getDay() // 0 = Sun, 1 = Mon, ..., 6 = Sat
      // Monday offset: if today is Sunday (0), offset = -6; otherwise offset = -(dayOfWeek - 1)
      const mondayOffset = dayOfWeek === 0 ? -6 : -(dayOfWeek - 1)
      const monday = new Date(now.getFullYear(), now.getMonth(), now.getDate() + mondayOffset)
      const sunday = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 6)
      return { start: startOfDay(monday), end: endOfDay(sunday) }
    }

    case 'month': {
      const firstDay = new Date(now.getFullYear(), now.getMonth(), 1)
      // Last day: day 0 of next month = last day of current month
      const lastDay = new Date(now.getFullYear(), now.getMonth() + 1, 0)
      return { start: startOfDay(firstDay), end: endOfDay(lastDay) }
    }

    case 'year': {
      const firstDay = new Date(now.getFullYear(), 0, 1)
      const lastDay = new Date(now.getFullYear(), 11, 31)
      return { start: startOfDay(firstDay), end: endOfDay(lastDay) }
    }

    case 'custom': {
      if (!custom?.from || !custom?.to) return null
      const from = parseLocalDate(custom.from)
      const to = parseLocalDate(custom.to)
      if (isNaN(from.getTime()) || isNaN(to.getTime())) return null
      if (from > to) return null // invalid range
      return { start: startOfDay(from), end: endOfDay(to) }
    }

    default:
      return null
  }
}

// ─── Convenience: YYYY-MM-DD strings for Supabase queries ───────────────────

/**
 * Returns { from: 'YYYY-MM-DD', to: 'YYYY-MM-DD' } | null for use in DB queries.
 */
export function getDateRangeStrings(
  preset: DatePreset,
  now = new Date(),
  custom?: { from: string; to: string },
): { from: string; to: string } | null {
  if (preset === 'all') return null
  const range = getDateRange(preset as Exclude<DatePreset, 'all'>, now, custom)
  if (!range) return null
  return { from: toLocalDateStr(range.start), to: toLocalDateStr(range.end) }
}

// ─── isInRange ───────────────────────────────────────────────────────────────

/**
 * Returns true if the given ISO timestamp string falls within [range.start, range.end].
 * Works correctly across local timezone (no UTC off-by-one).
 */
export function isInRange(isoTimestamp: string, range: DateRange): boolean {
  const d = new Date(isoTimestamp)
  if (isNaN(d.getTime())) return false
  return d >= range.start && d <= range.end
}

/**
 * Returns true if a YYYY-MM-DD expense_date string falls within the range.
 */
export function isDateStrInRange(dateStr: string, range: DateRange): boolean {
  if (!dateStr) return false
  const d = parseLocalDate(dateStr)
  if (isNaN(d.getTime())) return false
  // Compare as calendar days (use start of day for date-only fields)
  const startDay = startOfDay(d)
  return startDay >= startOfDay(range.start) && startDay <= startOfDay(range.end)
}

// ─── Human-readable label ────────────────────────────────────────────────────

export function presetLabel(preset: DatePreset): string {
  switch (preset) {
    case 'today':  return 'Today'
    case 'week':   return 'This Week'
    case 'month':  return 'This Month'
    case 'year':   return 'This Year'
    case 'custom': return 'Custom'
    case 'all':    return 'All Dates'
    default:       return ''
  }
}
