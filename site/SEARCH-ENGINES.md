# Registering the site with the search engines

Three separate things, often confused. Do them in this order.

## 1. Prove we own the property

Each console wants a proof it can fetch. Anything dropped in `site/public/` is served at the root
of the site, so a verification file needs no code, only a commit.

| Console | Proof | Where it goes |
|---|---|---|
| Google Search Console | DNS `TXT` record on `pavois.dev` | the DNS zone, nothing to commit |
| Google Search Console | or an HTML file `google<hash>.html` | `site/public/google<hash>.html` |
| Google Search Console | or a meta tag | `GOOGLE_SITE_VERIFICATION` in `src/config/site.ts` |
| Bing Webmaster Tools | XML file `BingSiteAuth.xml` | `site/public/BingSiteAuth.xml` |
| Bing Webmaster Tools | or a meta tag | `BING_SITE_VERIFICATION` in `src/config/site.ts` |

`BingSiteAuth.xml` is one line, and the token comes from the console:

```xml
<?xml version="1.0"?><users><user>PASTE_THE_BING_TOKEN_HERE</user></users>
```

Prefer the DNS `TXT` record for Google when the zone is reachable: it proves the whole domain at
once, apex included, and survives a rebuild. Bing can import a property already verified in Search
Console, which avoids verifying twice.

Verification works while the site is `noindex`, and that is the order we want: own the property
first, ask for indexing later. The meta tags are emitted regardless of `INDEXABLE` for that reason.

## 2. Submit the sitemap

Once verified, give each console `https://www.pavois.dev/sitemap.xml`. That is what gets the pages
discovered and, in Search Console, what turns the coverage report into something readable.

## 3. Announce changes as they happen

`mise run site:indexnow` posts the changed URLs to IndexNow, which Bing and Yandex act on within
minutes. It runs on every deploy, after the upload. Google does not implement the protocol, so the
sitemap remains the only channel there.

The key lives at `site/public/<key>.txt` and its content is its own name; that file IS the proof
that whoever submits controls the host. Nothing to register, no account, no secret: losing it is a
non-event, generate another.

## The launch switch

`INDEXABLE` in `src/config/site.ts` is `false` until launch. While it is false:

- every page emits `noindex, nofollow`
- `public/robots.txt` disallows everything
- `site:indexnow` refuses to submit, and says so

Flipping it to `true` means editing **both** the flag and `public/robots.txt`. Do it only once the
live site is what we want indexed: an engine that crawls a placeholder remembers it.
