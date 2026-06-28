import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';
import { marked } from 'marked';

// Light, prerendered glossary index for the client-side tooltip enrichment:
//   { termLower: { term, short(HTML), slug } }
// One per language; the short definition is shown inline, the slug links to /glossary/.
export function getStaticPaths() {
  return [{ params: { lang: 'en' } }, { params: { lang: 'fr' } }];
}

export const GET: APIRoute = async ({ params }) => {
  const lang = params.lang === 'fr' ? 'fr' : 'en';
  const terms = await getCollection('glossary');
  const out: Record<string, { term: string; short: string; slug: string }> = {};

  for (const e of terms) {
    const en = e.data.en;
    const short =
      lang === 'en' && en?.short ? en.short : e.data.fr.short;
    const keys = [e.data.term, ...(e.data.aliases || [])].filter(Boolean);
    for (const k of keys) {
      const low = String(k).toLowerCase().trim();
      if (low.length < 3) continue; // skip 1–2 char terms (too noisy)
      if (!out[low]) {
        out[low] = {
          term: e.data.term,
          short: marked.parseInline(short, { async: false }) as string,
          slug: e.data.slug,
        };
      }
    }
  }

  return new Response(JSON.stringify(out), {
    headers: { 'Content-Type': 'application/json' },
  });
};
