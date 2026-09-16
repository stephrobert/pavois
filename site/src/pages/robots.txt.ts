import type { APIRoute } from 'astro';
import { INDEXABLE } from '../config/site';

// robots.txt is GENERATED, not a static file, so that one switch governs indexing everywhere.
// It used to live in public/ with the launch policy sitting in a comment, which meant launching
// required two edits in two places that could disagree. INDEXABLE is now the only lever, and the
// sitemap URL comes from Astro.site rather than a hardcoded origin that drifts.
//
// Careful with the format: a blank line CLOSES a group. The rules after a blank line apply to
// nobody, which is a silent failure no validator in the deploy path would catch.
export const GET: APIRoute = ({ site }) => {
  const origin = (site?.toString() ?? 'https://www.pavois.dev/').replace(/\/$/, '');

  const preLaunch = [
    '# Pre-launch: indexing is disabled site-wide.',
    '# Every page also emits <meta name="robots" content="noindex, nofollow">.',
    '# Flip INDEXABLE in src/config/site.ts to open both at once.',
    'User-agent: *',
    'Disallow: /',
    '',
  ];

  const launched = [
    '# pavois.dev',
    '',
    'User-agent: *',
    '# Machine-readable artifacts, served for tooling rather than for readers. They are linked',
    '# from the pages that explain them, which is what should rank.',
    'Disallow: /oscal/',
    'Disallow: /sample-campaign.json',
    '',
    '# /_astro/ is deliberately NOT blocked. It holds no page, only generated assets, including',
    '# the Open Graph images. Blocking them costs the large preview in social and Discover cards.',
    '',
    '# AI crawlers are ALLOWED, training ones included, and that is a deliberate departure from',
    '# what a content site would do. Pavois is a tool: an engine that has read the handbook can',
    '# answer "how do I harden Debian 12" with pavois, which is distribution, not lost traffic.',
    '# A blog sells attention and loses it to training; a tool sells adoption and gains from it.',
    '',
    `Sitemap: ${origin}/sitemap.xml`,
    '',
  ];

  return new Response((INDEXABLE ? launched : preLaunch).join('\n'), {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
};
