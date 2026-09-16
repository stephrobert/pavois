// The EN and FR versions of a page must run the same commands.
//
// A command is not a translation. `pavois scan local --sudo` is the same in both languages, and the
// only thing that legitimately differs is the trailing comment. When a page is edited in one
// language and not the other, the two versions start telling readers to do different things, and
// nothing catches it: both pages build, both pass every link and quality check, and the gap only
// surfaces when someone reads both.
//
// So this compares the BUILT pages: for every page that exists in both languages, it strips the
// trailing comments from each shell block and requires the remaining commands to match, block for
// block. The handbook's prose parity is checked elsewhere (validate:i18n); this is the executable
// half, which matters more, because a reader copies it.
//
// Usage: node scripts/shell-blocks-parity.mjs [dist]
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';

const dist = process.argv[2] ?? 'dist';
const EN = join(dist, 'en');
const FR = join(dist, 'fr');

// The pages whose blocks a reader COPIES to get a working install. On these the rule is absolute:
// a command is not a translation, so only the trailing comment may differ.
//
// It is deliberately not the whole site. Elsewhere a block is often pseudo-code or a placeholder
// that is meant to be localized (`SOCLE-<DOMAIN>` reads `SOCLE-<DOMAINE>` in French, an `echo`
// inside an example prints a French sentence), and failing on those would train everyone to ignore
// this check. Widening it means first deciding, page by page, which blocks are commands and which
// are illustrations; that is worth doing and it is not this.
const SCOPE = [/^installation\//, /^start\//, /^downloads\//];

function pages(dir, base = dir) {
  const out = [];
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...pages(p, base));
    else if (entry.name === 'index.html') out.push(relative(base, p));
  }
  return out;
}

const TAG = /<[^>]+>/g;

function unescapeHtml(s) {
  // Numeric entities first: the highlighter emits `&#x26;&#x26;` for `&&`, and a named-only decoder
  // leaves that in the message, where it reads as a bug in the checker rather than as the finding.
  return s
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(Number(dec)))
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, '&');
}

/**
 * The commands of each <pre> block, with comments and blank lines removed.
 *
 * Tags are stripped WITHOUT inserting a space: the syntax highlighter wraps every token in its own
 * span, so `curl -fsSLO` is three elements. Replacing tags with a space turns that into
 * `curl  -fsSLO` and every comparison silently stops matching, which is a mistake this file made
 * once already while checking the deployed pages.
 */
function commands(html) {
  const out = [];
  const re = /<pre[^>]*>([\s\S]*?)<\/pre>/g;
  let m;
  while ((m = re.exec(html)) !== null) {
    const text = unescapeHtml(m[1].replace(TAG, ''));
    const lines = text
      .split('\n')
      .map((l) => l.replace(/\s+#.*$/, '').trimEnd()) // trailing comment: the localized part
      .filter((l) => l.trim() && !l.trim().startsWith('#'));
    if (lines.length) out.push(lines.join('\n'));
  }
  return out;
}

const enPages = new Set(pages(EN));
const problems = [];
let compared = 0;
let blocks = 0;

for (const rel of pages(FR)) {
  if (!enPages.has(rel)) continue; // a page in one language only is hreflang's business, not this
  if (!SCOPE.some((re) => re.test(rel))) continue;
  const en = commands(readFileSync(join(EN, rel), 'utf8'));
  const fr = commands(readFileSync(join(FR, rel), 'utf8'));
  compared += 1;

  const page = rel.replace(/\/index\.html$/, '') || '/';
  if (en.length !== fr.length) {
    problems.push(`${page}  en has ${en.length} shell block(s), fr has ${fr.length}`);
    continue;
  }
  for (let i = 0; i < en.length; i += 1) {
    blocks += 1;
    if (en[i] === fr[i]) continue;
    // Show the first line that actually DIFFERS, not the first line of the block. Printing line one
    // of each prints two identical strings whenever the divergence is further down, which reads as
    // a broken checker rather than as a finding.
    const a = en[i].split('\n');
    const b = fr[i].split('\n');
    let k = 0;
    while (k < Math.max(a.length, b.length) && a[k] === b[k]) k += 1;
    problems.push(
      `${page}  block ${i + 1}, line ${k + 1} differs once comments are removed\n` +
        `         en: ${a[k] ?? '(no such line)'}\n` +
        `         fr: ${b[k] ?? '(no such line)'}`,
    );
  }
}

if (compared === 0) {
  console.log(`shell-blocks-parity: no page pair found under ${dist}/, so nothing was verified`);
  process.exit(1);
}

if (problems.length) {
  console.log(`shell-blocks-parity: ${problems.length} block(s) differ between languages\n`);
  for (const p of problems) console.log(`  ${p}`);
  console.log('\nA command is not a translation. Only the trailing comment may differ.');
  process.exit(1);
}

console.log(`shell-blocks-parity: ${compared} page pair(s), ${blocks} shell block(s) compared`);
console.log('shell-blocks-parity: both languages run the same commands');
