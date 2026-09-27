/**
 * How old a piece of evidence is, computed when the page is READ.
 *
 * WHY THIS IS NOT DONE AT BUILD TIME
 *
 * The platform matrix carries `age_days`, computed by tools/release/evidence.py when the matrix is
 * generated. That number is right for one day. The platforms page rendered it straight into static
 * HTML, so for five days www.pavois.dev told every reader that campaigns from 2026-09-21 had run
 * "0 days ago", and would have kept saying it for as long as nobody rebuilt the site.
 *
 * On a page whose entire subject is what has been proved and WHEN, an age that cannot age is not a
 * cosmetic defect. The same applies to the state: a VERIFIED row past the freshness window is a
 * claim whose expiry cannot fire, which is why `pastWindow` exists here.
 *
 * Deliberately plain .mjs and free of DOM: it is the whole reason this can be tested by `node`
 * without adding a test runner to a repository that watches its dependencies.
 */

/** Milliseconds in a day. */
const DAY = 86400000;

/** The narrow no-break space this site puts between a number and its unit. */
const NNBSP = ' ';

/**
 * @param {string|null|undefined} ranAt  ISO timestamp of the campaign, or nothing
 * @param {number} nowMs                 the reader's clock, in milliseconds
 * @param {number} windowDays            the freshness window, from the matrix
 * @param {boolean} fr                   French rendering
 * @returns {{days: number, text: string, pastWindow: boolean}|null} null when there is no timestamp
 */
export function relativeAge(ranAt, nowMs, windowDays, fr) {
  if (!ranAt) return null;
  const ran = Date.parse(ranAt);
  if (Number.isNaN(ran)) return null;
  // Clamped at zero: a reader's clock can sit behind the runner's, and "in -1 days" reads as a bug
  // in the page rather than as a clock on somebody's desk. This page has already shipped a negative
  // age once, from a local timestamp parsed as UTC.
  const days = Math.max(0, Math.floor((nowMs - ran) / DAY));
  return {
    days,
    text: fr ? `il y a ${days}${NNBSP}j` : `${days}${NNBSP}days ago`,
    // Strictly greater, to match evidence.py's `if age > window_days`. A campaign exactly on the
    // boundary is still inside the window in both places, and two different boundaries would be
    // worse than either choice.
    pastWindow: Number.isFinite(windowDays) && days > windowDays,
  };
}
