import type { APIRoute } from 'astro';
import { allEntries } from '../lib/sitemap-entries';

/**
 * The sitemap INDEX, which is what robots.txt points at.
 *
 * It used to be the single file holding all 1698 URLs. 1698 is far below Google's 50 000 limit, so
 * this split buys nothing for crawling: it buys the ability to read Search Console. Coverage is
 * reported per sitemap, and one file mixing the product pages, the handbook, the standards, the
 * blog and 790 fiches in each language made "which family is Google refusing" unanswerable.
 *
 * `lastmod` on each child is the newest editorial date it carries, never the build time, for the
 * same reason the URLs have never carried one: a date that changes on every deploy tells a crawler
 * that everything changed, which is false and quickly ignored.
 */
export const GET: APIRoute = async ({ site }) => {
  const origin = (site?.toString() ?? 'https://www.pavois.dev/').replace(/\/$/, '');
  const buckets = await allEntries(origin);

  const body =
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    [...buckets.entries()]
      .map(([name, entries]) => {
        const newest = entries
          .map((e) => e.lastmod)
          .filter((d): d is string => !!d)
          .sort()
          .at(-1);
        return (
          `  <sitemap><loc>${origin}/sitemap-${name}.xml</loc>` +
          (newest ? `<lastmod>${newest}</lastmod>` : '') +
          `</sitemap>`
        );
      })
      .join('\n') +
    '\n</sitemapindex>\n';

  return new Response(body, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};
