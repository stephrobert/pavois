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

// Audience measurement, on a self-hosted Plausible: no cookie, no personal data, no consent banner
// to negotiate, and the data stays on an instance we run. An empty PLAUSIBLE_SRC disables it
// entirely, script included.
//
// This is the current tracker, where the site identity is COMPILED INTO the script rather than
// passed as `data-domain`. The bundle served at the URL below carries
// `domain:"pavois.dev", endpoint:"https://analytics.stephrobert.tech/api/event"`, plus outbound
// links, file downloads and form submissions already switched on. So there is no data-domain to
// keep in sync here, and the site is identified as `pavois.dev` in the dashboard even though the
// pages are served from www: the domain is Plausible's site KEY, not a filter on the URL.
//
// Custom properties are passed to plausible.init(), which accepts an object or a function. We send
// `lang` and `section`, because without them "do the French pages reach other countries" is a
// regex on the path, and "which section do visitors from a given source read" cannot be answered
// at all. Both are derived from the URL, so they cost nothing and reveal nothing about a visitor.
//
// The tracker only loads in a production build: counting our own dev reloads would be worse than
// counting nothing. It is also skipped on the 404 page, where a hit describes a broken link rather
// than a reader, and where the CloudFront logs carry the URL, the status and the user-agent.
//
// The origin must also appear in the Content-Security-Policy, see
// tools/aws/site-headers-policy.sh. A tracker blocked by CSP fails silently, which is exactly how
// the Google Fonts went missing for weeks. `mise run site:quality` now fails when the build
// fetches an origin the CSP does not allow.
export const PLAUSIBLE_SRC = 'https://analytics.stephrobert.tech/js/pa-ER-zoy5RDhOrq2p_3xS15.js';
