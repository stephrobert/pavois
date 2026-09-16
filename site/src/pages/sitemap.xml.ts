import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';
import { languages } from '../i18n/ui';

// Custom sitemap (no @astrojs/sitemap, to keep the pinned dep set untouched). Enumerates the
// content collections + static routes for both languages. `lastmod` is emitted ONLY from a real,
// hand-maintained data date (never the build date), omitted otherwise, per the SEO ruleset.
const LANGS = Object.keys(languages);
// Hand-maintained, so it drifted: `installation/`, `audit/`, `sample-report/` and `docs/benchmark/`
// are real pages, linked from the main navigation, and were missing here: 8 URLs a crawler never
// saw, including the benchmark, which is the product's whole differentiating argument.
const STATIC = [
  '', 'start/', 'installation/', 'audit/', 'docs/', 'docs/cli/', 'docs/tools/', 'docs/benchmark/',
  'handbook/', 'rules/', 'blog/', 'glossary/', 'about/', 'downloads/', 'sample-report/', 'attribution/',
  'standards/cis/', 'standards/bp28/', 'standards/nist/', 'standards/pci-dss/', 'standards/stig/',
];

export const GET: APIRoute = async ({ site }) => {
  const origin = (site?.toString() ?? 'https://www.pavois.dev/').replace(/\/$/, '');
  const rules = await getCollection('rules');
  const handbook = await getCollection('handbook');
  const posts = (await getCollection('blog')).filter((p) => !p.data.draft);
  const iso = (d?: string) => (d && /^\d{4}-\d{2}-\d{2}$/.test(d) ? d : undefined);

  // `key` is the path WITHOUT its language, which is what makes two URLs the same page in two
  // languages. It is what the alternates are grouped on below.
  type Entry = { loc: string; lang: string; key: string; lastmod?: string; priority: string };
  const entries: Entry[] = [];
  const push = (lang: string, key: string, lastmod?: string, priority = '0.6') =>
    entries.push({ loc: `${origin}/${lang}/${key}`, lang, key, lastmod, priority });

  for (const lang of LANGS) {
    for (const s of STATIC) push(lang, s, undefined, s === '' ? '0.9' : '0.7');
    for (const r of rules) push(lang, `rules/${r.data.id}/`, iso(r.data.dateModified ?? r.data.datePublished), '0.6');
    for (const h of handbook) push(lang, `handbook/${h.data.id}/`, iso(h.data.dateModified ?? h.data.datePublished), '0.7');
  }
  // Blog posts are per-language: emit each at its own lang with its hand-set date. A post written
  // in one language only has no counterpart, and the grouping below leaves it without alternates
  // rather than pointing at a URL that would 404.
  for (const p of posts) {
    const slug = p.id.replace(/^(en|fr)\//, '');
    push(p.data.lang, `blog/${slug}/`, iso(p.data.dateModified ?? p.data.datePublished), '0.7');
  }

  // Declare each language cluster in the sitemap as well as in the page head. Both are valid on
  // their own; emitting both means a crawler learns the pair on DISCOVERY, without having to fetch
  // the two pages first. On 1692 URLs with no crawl budget to spare, that is the difference between
  // the French pages being understood now and in several months.
  //
  // The two declarations must agree, or the engine discards the cluster; scripts/validate-hreflang
  // fails the build if they ever diverge.
  const byKey = new Map<string, Entry[]>();
  for (const e of entries) byKey.set(e.key, [...(byKey.get(e.key) ?? []), e]);
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

  const body =
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" ' +
    'xmlns:xhtml="http://www.w3.org/1999/xhtml">\n' +
    entries
      .map(
        (e) =>
          `  <url><loc>${e.loc}</loc>` +
          (e.lastmod ? `<lastmod>${e.lastmod}</lastmod>` : '') +
          `<priority>${e.priority}</priority>` +
          altsFor(e) +
          `</url>`
      )
      .join('\n') +
    '\n</urlset>\n';

  return new Response(body, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
