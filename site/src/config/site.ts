// Site-wide switches. INDEXABLE gates search-engine indexing: keep it FALSE while the site is
// pre-launch (every page emits `noindex, nofollow` and robots.txt blocks all crawlers). Flip it to
// true at launch AND restore public/robots.txt to an allow policy.
export const INDEXABLE = false;
