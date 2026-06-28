import { Marked } from 'marked';

export interface Heading {
  depth: number;
  slug: string;
  text: string;
}

// GitHub-style slug, accents kept (matches the look of Astro's own heading ids).
function slugify(s: string): string {
  return s
    .replace(/<[^>]+>/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^\p{L}\p{N}\s-]/gu, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-');
}

/**
 * Render Markdown to HTML AND collect its H2/H3 headings, with stable ids on every heading so a
 * table of contents can link to them. `marked` does not add ids on its own, and the manual pages
 * render via marked (not Astro's content render), so this gives them anchors + a TOC.
 *
 * Pass { lang, internal } to rewrite root-relative internal links (/handbook/… -> /<lang>/handbook/…).
 */
export function renderMarkdown(
  body: string,
  opts: { lang?: string; internal?: string } = {}
): { html: string; headings: Heading[] } {
  const headings: Heading[] = [];
  const seen = new Set<string>();
  const m = new Marked({ gfm: true, async: false });
  m.use({
    renderer: {
      heading(token: { tokens: unknown[]; depth: number; text: string }) {
        const text = token.text ?? '';
        let slug = slugify(text) || 'section';
        if (seen.has(slug)) {
          let i = 2;
          while (seen.has(`${slug}-${i}`)) i++;
          slug = `${slug}-${i}`;
        }
        seen.add(slug);
        if (token.depth >= 2 && token.depth <= 3) headings.push({ depth: token.depth, slug, text });
        // @ts-expect-error marked passes the parser as `this`
        const inner = this.parser.parseInline(token.tokens);
        return `<h${token.depth} id="${slug}">${inner}</h${token.depth}>\n`;
      },
    },
  });
  let html = m.parse(body) as string;
  if (opts.lang && opts.internal) {
    html = html.replace(new RegExp(`href="/(${opts.internal})/`, 'g'), `href="/${opts.lang}/$1/`);
  }
  return { html, headings };
}
