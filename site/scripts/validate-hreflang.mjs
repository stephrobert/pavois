#!/usr/bin/env node
/**
 * Prove the built site declares its two languages the way search engines require.
 *
 *   node scripts/validate-hreflang.mjs dist
 *
 * hreflang fails silently: a wrong annotation is not an error page, it is a signal the engine
 * discards, and the symptom appears weeks later as the wrong language ranking in the wrong country.
 * Nothing in a normal build catches that, so this walks the output and checks the five mistakes
 * that each, on their own, make an engine drop the whole cluster.
 *
 *   1. non-reciprocal     FR names EN, EN does not name FR back. Google requires both directions
 *                         and ignores the annotation outright when one side is missing.
 *   2. cross-canonical    a FR page whose canonical points at the EN page. The canonical wins, the
 *                         FR page is declared a duplicate of the English one and never ranks.
 *   3. dangling target    an alternate pointing at a URL the build does not produce.
 *   4. no x-default       nothing tells the engine what to serve for an unmatched language.
 *   5. orphan page        a page in one language with no counterpart, silently monolingual.
 *
 * Checks the sitemap too: its alternates must agree with the HTML, since a disagreement is one more
 * way to get the cluster discarded.
 */

import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, relative } from "node:path";

const DIST = process.argv[2] ?? "dist";
const LANGS = ["en", "fr"];
const XDEFAULT = "en";

function htmlFiles(dir, acc = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) htmlFiles(p, acc);
    else if (name.endsWith(".html")) acc.push(p);
  }
  return acc;
}

/** The URL path a built file is served at: dist/fr/start/index.html -> /fr/start/ */
function servedPath(file) {
  const rel = relative(DIST, file).replace(/\\/g, "/");
  return "/" + rel.replace(/index\.html$/, "").replace(/\.html$/, "");
}

const alternates = (html) =>
  [...html.matchAll(/<link\s+rel="alternate"\s+hreflang="([^"]+)"\s+href="([^"]+)"/g)].map((m) => ({
    lang: m[1],
    href: m[2],
  }));
const canonicalOf = (html) => html.match(/<link\s+rel="canonical"\s+href="([^"]+)"/)?.[1];

const errors = [];
const fail = (page, msg) => errors.push(`${page}: ${msg}`);

// Pages that belong to a language cluster. The root redirect and 404 are outside it by design.
const pages = htmlFiles(DIST).filter((f) => /^\/(en|fr)\//.test(servedPath(f)));
if (pages.length === 0) throw new Error(`no localized page found under ${DIST}/{en,fr}`);

const declared = new Map(); // served path -> {lang, canonical, alts}
for (const file of pages) {
  const html = readFileSync(file, "utf8");
  const path = servedPath(file);
  declared.set(path, {
    lang: path.slice(1, 3),
    canonical: canonicalOf(html),
    alts: alternates(html),
  });
}

const pathOf = (href) => {
  try {
    return new URL(href).pathname;
  } catch {
    return null;
  }
};

for (const [path, page] of declared) {
  // 2. the canonical must be the page itself, in its own language.
  const canonPath = page.canonical ? pathOf(page.canonical) : null;
  if (!page.canonical) fail(path, "no canonical");
  else if (canonPath !== path) fail(path, `canonical points elsewhere: ${canonPath}`);

  const byLang = new Map(page.alts.map((a) => [a.lang, a.href]));

  // 4. x-default, and it must name a page that exists.
  if (!byLang.has("x-default")) fail(path, "no x-default alternate");

  // Every declared language, self included: Google wants the page to list itself.
  for (const lang of LANGS) {
    if (!byLang.has(lang)) fail(path, `no alternate for ${lang}`);
  }

  for (const [lang, href] of byLang) {
    if (!href.startsWith("https://")) fail(path, `alternate ${lang} is not absolute: ${href}`);
    const target = pathOf(href);
    if (!target) {
      fail(path, `alternate ${lang} is not a URL: ${href}`);
      continue;
    }
    // 3. the target must be a page the build produced.
    if (!declared.has(target)) {
      fail(path, `alternate ${lang} points at a page the build does not produce: ${target}`);
      continue;
    }
    if (lang === "x-default") {
      if (declared.get(target).lang !== XDEFAULT) fail(path, `x-default is not ${XDEFAULT}: ${target}`);
      continue;
    }
    if (declared.get(target).lang !== lang) {
      fail(path, `alternate ${lang} points at a ${declared.get(target).lang} page: ${target}`);
      continue;
    }
    // 1. reciprocity: the target must name this page back, with this page's language.
    const back = declared.get(target).alts.find((a) => a.lang === page.lang);
    if (!back) fail(path, `alternate ${lang} (${target}) does not name ${page.lang} back`);
    else if (pathOf(back.href) !== path) fail(path, `alternate ${lang} (${target}) names ${pathOf(back.href)} as ${page.lang}, not this page`);
  }
}

// 5. orphans: a path present in one language and absent in the other.
for (const [path, page] of declared) {
  for (const lang of LANGS) {
    if (lang === page.lang) continue;
    const counterpart = "/" + lang + path.slice(3);
    if (!declared.has(counterpart)) fail(path, `no ${lang} counterpart (${counterpart})`);
  }
}

// The sitemap, when it carries alternates, must say the same thing as the HTML.
// sitemap.xml is an INDEX now, and it holds no <url> at all. Reading it alone would find zero
// alternates and take the "no alternates declared (allowed)" branch below: the check would go on
// passing while measuring nothing, which is worse than the split it was meant to survive. So the
// children are read, and an index that lists none is itself a failure.
const indexPath = join(DIST, "sitemap.xml");
let sitemapNote = "sitemap: no alternates declared (allowed: the HTML link elements carry them)";
if (existsSync(indexPath)) {
  const idx = readFileSync(indexPath, "utf8");
  const children = [...idx.matchAll(/<loc>[^<]*\/(sitemap-[^<\/]+\.xml)<\/loc>/g)].map((m) => m[1]);
  if (!children.length) {
    console.error("sitemap.xml lists no child sitemap: the alternates cannot be checked");
    process.exit(1);
  }
  const xml = children
    .map((c) => (existsSync(join(DIST, c)) ? readFileSync(join(DIST, c), "utf8") : ""))
    .join("\n");
  const blocks = [...xml.matchAll(/<url>([\s\S]*?)<\/url>/g)].map((m) => m[1]);
  if (!blocks.length) {
    console.error(`the ${children.length} child sitemap(s) hold no <url>`);
    process.exit(1);
  }
  const withAlts = blocks.filter((b) => b.includes("hreflang"));
  if (withAlts.length) {
    for (const b of blocks) {
      const loc = b.match(/<loc>([^<]+)<\/loc>/)?.[1];
      const locPath = loc ? pathOf(loc) : null;
      if (!locPath || !declared.has(locPath)) continue;
      const inSitemap = new Set(
        [...b.matchAll(/hreflang="([^"]+)"\s+href="([^"]+)"/g)].map((m) => `${m[1]} ${pathOf(m[2])}`)
      );
      const inHtml = new Set(declared.get(locPath).alts.map((a) => `${a.lang} ${pathOf(a.href)}`));
      for (const a of inHtml) {
        if (!inSitemap.has(a)) fail(locPath, `sitemap omits the alternate the HTML declares: ${a}`);
      }
    }
    sitemapNote = `sitemap: ${withAlts.length} entr(ies) carry alternates, consistent with the HTML`;
  }
}

const perLang = LANGS.map((l) => `${l}=${[...declared.values()].filter((p) => p.lang === l).length}`).join(" ");
if (errors.length) {
  console.error(`hreflang: ${errors.length} problem(s) across ${declared.size} page(s) (${perLang})`);
  for (const e of errors.slice(0, 40)) console.error(`  ${e}`);
  if (errors.length > 40) console.error(`  ... and ${errors.length - 40} more`);
  process.exit(1);
}
console.log(`hreflang: ${declared.size} page(s) form reciprocal clusters (${perLang})`);
console.log(`hreflang: every page is its own canonical, x-default is ${XDEFAULT}`);
console.log(sitemapNote);
