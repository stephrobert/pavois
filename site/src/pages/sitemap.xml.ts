import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';
import { languages } from '../i18n/ui';

// Custom sitemap (no @astrojs/sitemap, to keep the pinned dep set untouched). Enumerates the
// content collections + static routes for both languages. `lastmod` is emitted ONLY from a real,
// hand-maintained data date (never the build date), omitted otherwise, per the SEO ruleset.
const LANGS = Object.keys(languages);
// Hand-maintained, so it drifted: `installation/`, `audit/`, `sample-report/` and `docs/benchmark/`
// are real pages, linked from the main navigation, and were missing here — 8 URLs a crawler never
// saw, including the benchmark, which is the product's whole differentiating argument.
const STATIC = [
  '', 'start/', 'installation/', 'audit/', 'docs/', 'docs/tools/', 'docs/benchmark/',
  'handbook/', 'rules/', 'blog/', 'glossary/', 'about/', 'downloads/', 'sample-report/', 'attribution/',
  'standards/cis/', 'standards/bp28/', 'standards/nist/', 'standards/pci-dss/', 'standards/stig/',
];

export const GET: APIRoute = async ({ site }) => {
  const origin = (site?.toString() ?? 'https://pavois.dev/').replace(/\/$/, '');
  const rules = await getCollection('rules');
  const handbook = await getCollection('handbook');
  const posts = (await getCollection('blog')).filter((p) => !p.data.draft);
  const iso = (d?: string) => (d && /^\d{4}-\d{2}-\d{2}$/.test(d) ? d : undefined);

  type Entry = { loc: string; lastmod?: string; priority: string };
  const entries: Entry[] = [];
  const push = (path: string, lastmod?: string, priority = '0.6') =>
    entries.push({ loc: `${origin}/${path}`, lastmod, priority });

  for (const lang of LANGS) {
    for (const s of STATIC) push(`${lang}/${s}`, undefined, s === '' ? '0.9' : '0.7');
    for (const r of rules) push(`${lang}/rules/${r.data.id}/`, iso(r.data.dateModified ?? r.data.datePublished), '0.6');
    for (const h of handbook) push(`${lang}/handbook/${h.data.id}/`, iso(h.data.dateModified ?? h.data.datePublished), '0.7');
  }
  // Blog posts are per-language: emit each at its own lang with its hand-set date.
  for (const p of posts) {
    const slug = p.id.replace(/^(en|fr)\//, '');
    push(`${p.data.lang}/blog/${slug}/`, iso(p.data.dateModified ?? p.data.datePublished), '0.7');
  }

  const body =
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    entries
      .map(
        (e) =>
          `  <url><loc>${e.loc}</loc>` +
          (e.lastmod ? `<lastmod>${e.lastmod}</lastmod>` : '') +
          `<priority>${e.priority}</priority></url>`
      )
      .join('\n') +
    '\n</urlset>\n';

  return new Response(body, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
