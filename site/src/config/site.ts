// Site-wide switches. INDEXABLE is the ONE lever that governs indexing. While it is false every
// page emits `noindex, nofollow`, the generated robots.txt disallows everything, and site:indexnow
// refuses to submit. Flipping it to true opens all three at once, and nothing else needs editing.
export const INDEXABLE = true;

// Ownership proofs for the webmaster consoles. Each console hands out one token, we echo it in a
// meta tag, it re-fetches the page and the property becomes ours. The tag is emitted even while the
// site is noindex, and that is the point: verify the property now, ask for indexing later.
//
// An empty string emits nothing, so an unverified console leaves no dead tag in the markup.
//
//   Google  Search Console     https://search.google.com/search-console  (content= of the meta tag)
//   Bing    Webmaster Tools    https://www.bing.com/webmasters           (content= of msvalidate.01)
//
// A DNS TXT record is the sturdier alternative for Google: it proves the whole domain at once, apex
// included, and survives a site rebuild. Use it if the zone is reachable; keep this as the fallback
// for anyone who cannot edit DNS. Bing offers an import from Search Console, which is faster than
// verifying twice.
export const GOOGLE_SITE_VERIFICATION = '';
export const BING_SITE_VERIFICATION = 'A49CC502B16F78298FDF79166A73F277';
