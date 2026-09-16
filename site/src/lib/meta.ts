// Titles and meta descriptions have a hard budget: a result page shows roughly 60-70 characters of
// title and 150-160 of description, and cuts the rest mid-word. On hand-written pages that budget
// is an editorial choice. On the 1578 generated rule pages it has to be enforced in code, because
// control titles and summaries are written for a report, not for a search result.
//
// These helpers cut on a boundary rather than at a character offset: a description that ends
// "Configures pamfaillock to lock an account after at most 3 consecutive failed authentica" reads
// as broken, one that ends on a word and an ellipsis reads as a summary.

const TITLE_MAX = 70;
const DESC_MAX = 160;

/** Cut on the last word boundary that fits, appending an ellipsis only if something was removed. */
function cut(text: string, max: number): string {
  const s = text.replace(/\s+/g, ' ').trim();
  if (s.length <= max) return s;
  // Prefer ending on a sentence when one ends within the budget: a whole sentence beats a
  // truncated one, and it costs nothing to check.
  const sentence = s.slice(0, max).match(/^.*[.!?](?=\s|$)/);
  if (sentence && sentence[0].length >= max * 0.6) return sentence[0].trim();
  const room = max - 1; // the ellipsis is one character
  const cutAt = s.lastIndexOf(' ', room);
  return s.slice(0, cutAt > max * 0.5 ? cutAt : room).replace(/[,;:.]$/, '') + '…';
}

/**
 * A page title, with the site suffix, guaranteed to fit. The suffix is dropped before the title is
 * truncated: "Pavois" at the end helps nobody if it costs the words that identify the page.
 */
export function pageTitle(subject: string, suffix = 'Pavois'): string {
  const full = `${subject} · ${suffix}`;
  if (full.length <= TITLE_MAX) return full;
  const room = TITLE_MAX - ` · ${suffix}`.length;
  return `${cut(subject, room)} · ${suffix}`;
}

/**
 * Last-resort clamp for a title a page composed itself. Base.astro applies it so the budget holds
 * for every page, including ones written later by someone who never read this file.
 */
export function clampTitle(title: string): string {
  return title.length <= TITLE_MAX ? title : cut(title, TITLE_MAX);
}

/**
 * A meta description: plain text, no markup, no entity, within what a result page shows.
 * Entities matter as much as length. A description built from body copy carries `&nbsp;` and
 * `<code>` into the snippet, where an engine renders them literally, and that is what a reader
 * sees before deciding whether to click.
 */
export function metaDescription(text: string): string {
  const plain = text
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;|&#160;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;|&#34;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'");
  return cut(plain, DESC_MAX);
}
