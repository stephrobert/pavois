import type { APIRoute } from 'astro';
import { childSitemap } from '../lib/sitemap-entries';

// The domain hubs, in their own file: they exist to get the fiches crawled, so their
// coverage is the number to read, not one averaged into the rest of the site.
export const GET: APIRoute = ({ site }) => childSitemap(site, 'domains-en');
