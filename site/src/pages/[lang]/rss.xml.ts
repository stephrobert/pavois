import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';
import { languages } from '../../i18n/ui';

export function getStaticPaths() {
  return Object.keys(languages).map((lang) => ({ params: { lang } }));
}

const esc = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// RSS 2.0 for the blog, per language (hand-rolled, no @astrojs/rss dep). pubDate from the
// hand-maintained datePublished (00:00 UTC, deterministic — no build-time clock).
export const GET: APIRoute = async ({ params, site }) => {
  const lang = (params.lang as string) || 'en';
  const origin = (site?.toString() ?? 'https://pavois.dev/').replace(/\/$/, '');
  const posts = (await getCollection('blog'))
    .filter((p) => p.data.lang === lang && !p.data.draft)
    .sort((a, b) => (a.data.datePublished < b.data.datePublished ? 1 : -1));

  const titleSite = lang === 'fr' ? 'Blog Pavois' : 'Pavois Blog';
  const desc =
    lang === 'fr'
      ? 'Durcissement Linux effectif, conformité multi-normes, verdict reboot-proof.'
      : 'Effective Linux hardening, multi-standard compliance, the reboot-proof verdict.';

  const items = posts
    .map((p) => {
      const slug = p.id.replace(/^(en|fr)\//, '');
      const url = `${origin}/${lang}/blog/${slug}/`;
      const pub = new Date(`${p.data.datePublished}T00:00:00Z`).toUTCString();
      const cat = p.data.category ? `<category>${esc(p.data.category)}</category>` : '';
      return (
        `    <item>\n` +
        `      <title>${esc(p.data.title)}</title>\n` +
        `      <link>${url}</link>\n` +
        `      <guid isPermaLink="true">${url}</guid>\n` +
        `      <description>${esc(p.data.description)}</description>\n` +
        `      <pubDate>${pub}</pubDate>\n` +
        `      ${cat}\n` +
        `    </item>`
      );
    })
    .join('\n');

  const xml =
    `<?xml version="1.0" encoding="UTF-8"?>\n` +
    `<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">\n` +
    `  <channel>\n` +
    `    <title>${esc(titleSite)}</title>\n` +
    `    <link>${origin}/${lang}/blog/</link>\n` +
    `    <description>${esc(desc)}</description>\n` +
    `    <language>${lang === 'fr' ? 'fr-FR' : 'en-US'}</language>\n` +
    `    <atom:link href="${origin}/${lang}/rss.xml" rel="self" type="application/rss+xml" />\n` +
    `${items}\n` +
    `  </channel>\n` +
    `</rss>\n`;

  return new Response(xml, { headers: { 'Content-Type': 'application/rss+xml; charset=utf-8' } });
};
