import { getCollection } from 'astro:content';
import { languages } from '../i18n/ui';
import { groupByDomain } from './domains';

/**
 * The one place the sitemap's URL list is built.
 *
 * It used to live inside `sitemap.xml.ts`, which emitted all 1698 URLs into a single file. That
 * is well under Google's 50 000 limit, so splitting buys nothing for crawling. It buys the only
 * thing that was missing: Search Console reports coverage PER SITEMAP, so "38% of the EN rule
 * fiches are refused" is unreadable when it is averaged into one file holding the product pages,
 * the handbook, the standards, the blog and 790 fiches in each language.
 *
 * The alternates are computed across EVERY entry, not per file: a French fiche's English
 * counterpart lives in another sitemap, and pointing at it is both correct and required, or the
 * cluster is incomplete.
 */

export type Entry = { loc: string; lang: string; key: string; lastmod?: string };

/**
 * Which child sitemap an entry belongs to. The names are the ones Search Console will show.
 *
 * The domain hubs get their own bucket rather than sitting with the pages. They are the fix for
 * the fiches that were never indexed, so the only question worth asking of them is whether Google
 * takes them, and a coverage figure averaged into the handbook and the product pages cannot
 * answer it.
 */
export type Bucket =
  | 'pages-fr'
  | 'pages-en'
  | 'rules-fr'
  | 'rules-en'
  | 'domains-fr'
  | 'domains-en'
  | 'blog';

const LANGS = Object.keys(languages);

// Hand-maintained, so it drifted once: `installation/`, `audit/`, `sample-report/` and
// `docs/benchmark/` are real pages, linked from the main navigation, and were missing here: 8 URLs
// a crawler never saw, including the benchmark, which is the product's whole differentiating
// argument.
const STATIC = [
  '', 'start/', 'installation/', 'audit/', 'docs/', 'docs/cli/', 'docs/tools/', 'docs/benchmark/',
  'handbook/', 'rules/', 'blog/', 'glossary/', 'about/', 'support/', 'downloads/', 'sample-report/', 'attribution/',
  'platforms/',
  'standards/cis/', 'standards/bp28/', 'standards/nist/', 'standards/pci-dss/', 'standards/stig/',
];

const iso = (d?: string) => (d && /^\d{4}-\d{2}-\d{2}$/.test(d) ? d : undefined);

/** The newest editorial date in a set of rules, which is when a page derived from them changed. */
const newest = (rs: { dateModified?: string; datePublished?: string }[]): string | undefined =>
  rs
    .map((r) => iso(r.dateModified ?? r.datePublished))
    .filter((d): d is string => !!d)
    .sort()
    .at(-1);

/** Every URL of the site, in every language, with the bucket each one belongs to. */
export async function allEntries(origin: string): Promise<Map<Bucket, Entry[]>> {
  const rules = await getCollection('rules');
  const handbook = await getCollection('handbook');
  const posts = (await getCollection('blog')).filter((p) => !p.data.draft);

  // One hub per domain, plus the map that lists them. Derived from the same function the pages
  // use, so a hub can never be in the sitemap without existing, or exist without being listed.
  const hubs = groupByDomain(rules.map((r) => r.data));

  const out = new Map<Bucket, Entry[]>([
    ['pages-fr', []], ['pages-en', []], ['rules-fr', []], ['rules-en', []],
    ['domains-fr', []], ['domains-en', []], ['blog', []],
  ]);
  const push = (b: Bucket, lang: string, key: string, lastmod?: string) =>
    out.get(b)!.push({ loc: `${origin}/${lang}/${key}`, lang, key, lastmod });

  for (const lang of LANGS) {
    const pages = (lang === 'fr' ? 'pages-fr' : 'pages-en') as Bucket;
    const fiches = (lang === 'fr' ? 'rules-fr' : 'rules-en') as Bucket;
    const domains = (lang === 'fr' ? 'domains-fr' : 'domains-en') as Bucket;
    for (const s of STATIC) push(pages, lang, s);
    // A hub's content IS its domain's controls, so its lastmod is the newest editorial date among
    // them. Emitting none would tell a crawler nothing, and emitting the build date would tell it
    // that 35 pages change every deploy, which is false and quickly ignored.
    push(domains, lang, 'rules/domain/', newest(rules.map((r) => r.data)));
    for (const h of hubs) push(domains, lang, `rules/domain/${h.slug}/`, newest(h.rules));
    // The handbook chapters sit with the pages: they are a few dozen, and separating them from the
    // 790 fiches is the whole point of the split.
    for (const h of handbook) push(pages, lang, `handbook/${h.data.id}/`, iso(h.data.dateModified ?? h.data.datePublished));
    for (const r of rules) push(fiches, lang, `rules/${r.data.id}/`, iso(r.data.dateModified ?? r.data.datePublished));
  }
  // Blog posts are per-language: each is emitted at its own lang with its hand-set date. A post
  // written in one language only has no counterpart, and the grouping below leaves it without
  // alternates rather than pointing at a URL that would 404.
  for (const p of posts) {
    const slug = p.id.replace(/^(en|fr)\//, '');
    push('blog', p.data.lang, `blog/${slug}/`, iso(p.data.dateModified ?? p.data.datePublished));
  }
  return out;
}

/**
 * Render one child sitemap.
 *
 * `all` is every entry of the site, not only this file's: the alternates are grouped on the
 * language-less key, so a URL here can and must point at its counterpart in another sitemap.
 *
 * No `<priority>`. Google documents that it ignores it, and 1698 lines of a field nobody reads
 * only made it harder to see the `lastmod` values, which ARE used and which come from the real
 * editorial dates rather than the build time.
 */
export function renderUrlset(entries: Entry[], all: Entry[]): string {
  const byKey = new Map<string, Entry[]>();
  for (const e of all) byKey.set(e.key, [...(byKey.get(e.key) ?? []), e]);

  const altsFor = (e: Entry) => {
    const group = byKey.get(e.key) ?? [];
    if (group.length < 2) return ''; // monolingual page: no annotation at all, never a dangling one
    const links = group.map(
      (g) => `<xhtml:link rel="alternate" hreflang="${g.lang}" href="${g.loc}"/>`
    );
    const fallback = group.find((g) => g.lang === 'en');
    if (fallback) links.push(`<xhtml:link rel="alternate" hreflang="x-default" href="${fallback.loc}"/>`);
    return links.join('');
  };

  return (
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" ' +
    'xmlns:xhtml="http://www.w3.org/1999/xhtml">\n' +
    entries
      .map(
        (e) =>
          `  <url><loc>${e.loc}</loc>` +
          (e.lastmod ? `<lastmod>${e.lastmod}</lastmod>` : '') +
          altsFor(e) +
          `</url>`
      )
      .join('\n') +
    '\n</urlset>\n'
  );
}

/** A child sitemap endpoint, which is the same three lines five times over. */
export async function childSitemap(site: URL | undefined, bucket: Bucket): Promise<Response> {
  const origin = (site?.toString() ?? 'https://www.pavois.dev/').replace(/\/$/, '');
  const buckets = await allEntries(origin);
  const all = [...buckets.values()].flat();
  return new Response(renderUrlset(buckets.get(bucket)!, all), {
    headers: { 'Content-Type': 'application/xml; charset=utf-8' },
  });
}
