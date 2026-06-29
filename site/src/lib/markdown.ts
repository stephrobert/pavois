import { Marked } from 'marked';
import { createHighlighter } from 'shiki';

export interface Heading {
  depth: number;
  slug: string;
  text: string;
}

// Single dark Shiki theme: the site's code blocks always sit on a dark surface (--term), so dark
// tokens on a light bg would be unreadable — one dark theme keeps light tokens on the dark block in
// both site themes. Loaded once at module init (top-level await); codeToHtml is then sync.
const THEME = 'github-dark-default';
const LANGS = [
  'bash', 'shell', 'console', 'yaml', 'json', 'ruby', 'ini', 'toml', 'diff',
  'dockerfile', 'hcl', 'properties', 'systemd', 'nginx', 'sql', 'python', 'go',
];
const highlighter = await createHighlighter({ themes: [THEME], langs: LANGS });
const loaded = new Set(highlighter.getLoadedLanguages());
const ALIAS: Record<string, string> = { sh: 'bash', shell: 'bash', yml: 'yaml', dockerfile: 'docker', conf: 'ini', cfg: 'ini', text: 'txt', '': 'txt' };

/** Highlight a code string to a <pre class="shiki">…</pre> (dark theme, build-time). */
export function highlight(code: string, lang = ''): string {
  const key = ALIAS[lang] ?? lang;
  const use = loaded.has(key) ? key : 'txt';
  return highlighter.codeToHtml(code.replace(/\n$/, ''), { lang: use, theme: THEME });
}

// GitHub-style slug, accents kept (matches the look of Astro's own heading ids).
function slugify(s: string): string {
  return s
    .toLowerCase()
    .trim()
    // single-char allowlist: keep only letters/numbers/space/hyphen — drops all of <>"/&, so no
    // tag survives (no regex tag-strip needed, which avoids incomplete-sanitization pitfalls).
    .replace(/[^\p{L}\p{N}\s-]/gu, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-');
}

/**
 * Render Markdown to HTML AND collect its H2/H3 headings, with stable ids on every heading so a
 * table of contents can link to them. `marked` does not add ids on its own, and the manual pages
 * render via marked (not Astro's content render), so this gives them anchors + a TOC. Fenced code
 * is syntax-highlighted at build time via Shiki (zero runtime JS).
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
      code(token: { text: string; lang?: string }) {
        return highlight(token.text, (token.lang || '').trim().split(/\s+/)[0]);
      },
    },
  });
  let html = m.parse(body) as string;
  if (opts.lang && opts.internal) {
    html = html.replace(new RegExp(`href="/(${opts.internal})/`, 'g'), `href="/${opts.lang}/$1/`);
  }
  return { html, headings };
}
