// CloudFront Function, viewer-request, on the pavois.dev distribution.
//
// Two jobs, and the second one is why this file now lives in the repository instead of only in the
// AWS console: an edge function that redirects the site's entry point is site behaviour, and site
// behaviour belongs next to the site.
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    // 1. The root is a REDIRECT, not a page.
    //
    // Astro's `Astro.redirect('/en/')` in a static build emits an HTML page instead:
    //
    //     <meta http-equiv="refresh" content="2;url=/en/">
    //     <meta name="robots" content="noindex">
    //
    // served with 200. Three problems, all on the domain's front door, and all worse since the
    // apex is served directly rather than through a redirect:
    //
    //   - a TWO SECOND delay. Someone typing pavois.dev watches a blank page before arriving.
    //   - `noindex` on the canonical address of the project: the one people type, link and cite.
    //   - a meta-refresh is a client-side hint. Search engines treat it as a weak signal next to a
    //     301, and answer engines follow it poorly.
    //
    // A 301 at the edge costs nothing, is cacheable, and is what every consumer understands. It is
    // unconditional rather than negotiated on Accept-Language: a language-varying redirect on the
    // entry point needs Vary handling to stay cacheable, and would make the canonical URL of the
    // site depend on the reader's browser, which is not a property a citable reference wants.
    if (uri === '/' || uri === '/index.html') {
        return {
            statusCode: 301,
            statusDescription: 'Moved Permanently',
            headers: {
                location: { value: '/en/' },
                'cache-control': { value: 'public, max-age=3600' }
            }
        };
    }

    // 2. S3's REST endpoint has no directory index: it serves objects by exact key. Astro publishes
    // /en/rules/index.html and links to /en/rules/, so without this rewrite every section URL would
    // 404. The website endpoint does this natively, which is why it is often used instead, but that
    // requires a PUBLIC bucket. This keeps the bucket private behind OAC and does the one thing the
    // website endpoint was wanted for.
    if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
    } else if (!uri.includes('.')) {
        request.uri = uri + '/index.html';
    }
    return request;
}
