#!/usr/bin/env node
/**
 * Page-quality audit of the BUILT site: what a search engine, a screen reader and a reader see.
 *
 *   node scripts/quality.mjs dist              # fail if a category is over its budget
 *   node scripts/quality.mjs dist --report     # full breakdown, per category and per section
 *   node scripts/quality.mjs dist --write-budget   # record today's counts as the new ceiling
 *
 * Why a budget rather than a pass/fail. The first run found 855 problems across 1694 pages, most
 * of them inherited: descriptions written for a report, titles written for a table of contents.
 * A check that fails on all of them gets disabled within a week. A budget fails on anything that
 * makes a category WORSE, which is the property that actually holds a line, and the ceilings come
 * down as pages are reworked. A budget is a ledger of debt, not a way to pass.
 *
 * Every rule here is a thing a reader or an engine can observe, never a preference:
 *
 *   title-length          a result page shows ~60-70 characters, then cuts mid-word
 *   description-length    same, at ~150-160; under 25 the engine writes its own from the body
 *   description-markup    an entity or a tag reaches the snippet as characters, not formatting
 *   description-missing   nothing to show, so the engine picks a sentence at random
 *   description-is-title  wastes the only free text an engine displays
 *   image-alt             an image a screen reader cannot announce
 *   heading-h1           zero or several h1: the document has no single subject
 *   lang-attribute        a page that does not say what language it is in
 */

import { readFileSync, readdirSync, statSync, writeFileSync, existsSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const DIST = process.argv.find((a) => !a.startsWith("--") && !a.endsWith("node") && !a.endsWith(".mjs")) ?? "dist";
const REPORT = process.argv.includes("--report");
const WRITE = process.argv.includes("--write-budget");
const BUDGET_FILE = join(dirname(fileURLToPath(import.meta.url)), "..", "quality-budget.json");

const TITLE_MIN = 10, TITLE_MAX = 70;
const DESC_MIN = 25, DESC_MAX = 160;

function htmlFiles(dir, acc = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) htmlFiles(p, acc);
    else if (name.endsWith(".html")) acc.push(p);
  }
  return acc;
}

/**
 * Decode the HTML escaping of an attribute value ONCE, which is what a parser does and therefore
 * what an engine sees. It matters twice over. For length: `&#39;` is five characters in the source
 * and one on screen, so measuring the raw attribute reported a 66-character title as 71. For
 * markup: an entity here is the normal, correct encoding of an apostrophe or an ampersand, and
 * flagging it would punish correct pages. What IS a defect is an entity that SURVIVES one decode,
 * `&amp;nbsp;` becoming `&nbsp;`, because that one reaches the reader as characters.
 */
const decode = (s) =>
  s
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;|&#34;/gi, '"')
    .replace(/&#0?39;|&apos;/gi, "'")
    .replace(/&nbsp;|&#160;/gi, " ")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&amp;/gi, "&");

const attr = (html, re) => {
  const raw = html.match(re)?.[1];
  return raw === undefined ? undefined : decode(raw);
};
const findings = [];
const add = (page, rule, detail) => findings.push({ page, rule, detail });

/**
 * Origins the Content-Security-Policy allows, read from the versioned policy rather than from the
 * live distribution: the check has to work offline, in CI, before anything is deployed.
 *
 * This rule exists because the CSP has silently broken the site twice. `font-src 'self'` blocked
 * Google Fonts for weeks, and every page quietly fell back to system fonts. A tracker would have
 * failed the same way. A blocked resource raises no build error, no HTTP error and no alert: it
 * simply does not happen, and the only way to notice is to look.
 */
function cspOrigins() {
  const policy = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "tools", "aws", "site-headers-policy.sh");
  if (!existsSync(policy)) return null;
  const text = readFileSync(policy, "utf8");
  const csp = text.match(/CSP="([\s\S]*?)"\n/)?.[1];
  if (!csp) return null;
  return new Set([...csp.matchAll(/https?:\/\/[^\s;\\]+/g)].map((m) => m[0].replace(/\/$/, "")));
}
const allowed = cspOrigins();

const pages = htmlFiles(DIST);
let audited = 0;

for (const file of pages) {
  const html = readFileSync(file, "utf8");
  const page = "/" + relative(DIST, file).replace(/index\.html$/, "").replace(/\\/g, "/");

  // A redirection stub is not a page: it has no content, and it says so with noindex.
  if (/<meta http-equiv="refresh"/i.test(html)) continue;
  if (page.endsWith("404.html")) continue;

  // The sample report and sample campaign are OUTPUT OF THE BINARY, archived byte-for-byte so that
  // what the site shows is what `pavois scan` actually produces. Editing their head to satisfy an
  // SEO rule would make them unrepresentative, which costs more than it gains: the pages that
  // present them, /<lang>/sample-report/, are real pages and are audited like any other.
  if (/^\/sample-(report|campaign)\.html$/.test(page)) continue;
  audited++;

  const title = attr(html, /<title>([^<]*)<\/title>/);
  const desc = attr(html, /<meta name="description" content="([^"]*)"/);

  if (!title) add(page, "title-length", "no title");
  else if (title.length > TITLE_MAX) add(page, "title-length", `${title.length} > ${TITLE_MAX}`);
  else if (title.length < TITLE_MIN) add(page, "title-length", `${title.length} < ${TITLE_MIN}`);

  if (!desc) add(page, "description-missing", "");
  else {
    if (desc.length > DESC_MAX) add(page, "description-length", `${desc.length} > ${DESC_MAX}`);
    else if (desc.length < DESC_MIN) add(page, "description-length", `${desc.length} < ${DESC_MIN}`);
    const entity = desc.match(/&(amp;)?(nbsp|#\d+|[a-z]+);/i);
    if (entity) add(page, "description-markup", `entity ${entity[0]}`);
    else if (/<[a-z/][^>]*>/i.test(desc)) add(page, "description-markup", "html tag");
    if (title && desc.trim() === title.trim()) add(page, "description-is-title", "");
  }

  // An <img> with no alt attribute at all. alt="" is deliberate and correct for decoration.
  for (const img of html.match(/<img\b[^>]*>/gi) ?? []) {
    if (!/\balt\s*=/.test(img)) add(page, "image-alt", img.slice(0, 60));
  }

  const h1 = (html.match(/<h1\b/gi) ?? []).length;
  if (h1 !== 1) add(page, "heading-h1", `${h1} h1`);

  if (!/<html[^>]+\blang=/i.test(html)) add(page, "lang-attribute", "");

  // Only what the browser FETCHES counts: a script, a stylesheet, a font, an image. A link in the
  // prose to an external site is not subject to the CSP and must not be flagged.
  if (allowed) {
    const fetched = [
      ...(html.match(/<script\b[^>]*\bsrc="(https?:\/\/[^"]+)"/gi) ?? []),
      ...(html.match(/<link\b[^>]*\brel="(?:stylesheet|preload)"[^>]*\bhref="(https?:\/\/[^"]+)"/gi) ?? []),
      ...(html.match(/<img\b[^>]*\bsrc="(https?:\/\/[^"]+)"/gi) ?? []),
    ];
    for (const tag of fetched) {
      const url = tag.match(/"(https?:\/\/[^"]+)"/)?.[1];
      if (!url) continue;
      const origin = new URL(url).origin;
      if (origin === "https://www.pavois.dev") continue; // 'self'
      if (!allowed.has(origin)) add(page, "csp-origin", `${origin} is fetched but not in the CSP`);
    }
  }
}

const counts = {};
for (const f of findings) counts[f.rule] = (counts[f.rule] ?? 0) + 1;

const budget = existsSync(BUDGET_FILE) ? JSON.parse(readFileSync(BUDGET_FILE, "utf8")) : {};
const ceilings = budget.ceilings ?? {};

if (WRITE) {
  writeFileSync(
    BUDGET_FILE,
    JSON.stringify(
      {
        note: "Ceilings, not targets. A category may never grow; lower a number whenever pages are reworked. See scripts/quality.mjs.",
        recorded: new Date().toISOString().slice(0, 10),
        pages: audited,
        ceilings: counts,
      },
      null,
      2
    ) + "\n"
  );
  console.log(`quality: budget written, ${Object.values(counts).reduce((a, b) => a + b, 0)} finding(s) over ${audited} page(s)`);
  process.exit(0);
}

if (REPORT) {
  const bySection = {};
  for (const f of findings) {
    const s = f.page.split("/")[2] || "(root)";
    bySection[s] ??= {};
    bySection[s][f.rule] = (bySection[s][f.rule] ?? 0) + 1;
  }
  console.log(`=== ${audited} page(s) audited ===\n`);
  console.log("by rule");
  for (const [r, n] of Object.entries(counts).sort((a, b) => b[1] - a[1])) {
    const c = ceilings[r];
    const mark = c === undefined ? "NEW" : n > c ? `OVER (ceiling ${c})` : n < c ? `improved (ceiling ${c})` : "at ceiling";
    console.log(`  ${String(n).padStart(5)}  ${r.padEnd(22)} ${mark}`);
  }
  console.log("\nby section");
  for (const [s, rules] of Object.entries(bySection).sort(
    (a, b) => Object.values(b[1]).reduce((x, y) => x + y, 0) - Object.values(a[1]).reduce((x, y) => x + y, 0)
  )) {
    const total = Object.values(rules).reduce((x, y) => x + y, 0);
    console.log(`  ${String(total).padStart(5)}  ${s}`);
    for (const [r, n] of Object.entries(rules).sort((a, b) => b[1] - a[1])) console.log(`           ${String(n).padStart(5)}  ${r}`);
  }
  console.log("\nsamples");
  const seen = new Set();
  for (const f of findings) {
    if (seen.has(f.rule)) continue;
    seen.add(f.rule);
    console.log(`  ${f.rule}: ${f.page} ${f.detail}`);
  }
  console.log();
}

// Verdict: a category over its ceiling, or a category that did not exist when the budget was
// recorded, is a regression. Everything else passes, including categories with known debt.
const over = [];
for (const [rule, n] of Object.entries(counts)) {
  const c = ceilings[rule];
  if (c === undefined || n > c) over.push([rule, n, c]);
}
const total = Object.values(counts).reduce((a, b) => a + b, 0);
const budgeted = Object.values(ceilings).reduce((a, b) => a + b, 0);

if (over.length) {
  console.error(`quality: ${over.length} categor(ies) over budget, ${total} finding(s) over ${audited} page(s)`);
  for (const [rule, n, c] of over) {
    console.error(`  ${rule}: ${n}` + (c === undefined ? "  (no ceiling recorded: a new kind of problem)" : `  > ceiling ${c}`));
  }
  console.error(`\nFix the pages, or record a new ceiling with --write-budget and say why in the commit.`);
  process.exit(1);
}

const improved = Object.entries(counts).filter(([r, n]) => ceilings[r] !== undefined && n < ceilings[r]);
console.log(`quality: ${audited} page(s), ${total} known finding(s) within a budget of ${budgeted}`);
if (improved.length) {
  console.log(`quality: ${improved.length} categor(ies) improved, lower the ceiling in quality-budget.json:`);
  for (const [r, n] of improved) console.log(`  ${r}: ${n} (ceiling ${ceilings[r]})`);
}
