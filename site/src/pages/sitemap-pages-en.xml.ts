import type { APIRoute } from 'astro';
import { childSitemap } from '../lib/sitemap-entries';

// One bucket of the sitemap index. Search Console reports coverage per sitemap, so a family that
// stops being indexed is visible here instead of being averaged into 1698 URLs.
export const GET: APIRoute = ({ site }) => childSitemap(site, 'pages-en');
