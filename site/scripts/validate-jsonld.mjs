#!/usr/bin/env node
/**
 * Validate EVERY JSON-LD block in the built site against the rules Google's Rich Results Test
 * enforces for the types we emit (Article/TechArticle/BlogPosting, BreadcrumbList, Organization,
 * WebSite, SoftwareApplication). The Rich Results Test is a gated web tool with no API, so this is
 * the reproducible equivalent: run it over dist/ in CI instead of pasting 1600+ pages by hand.
 *
 *   node scripts/validate-jsonld.mjs            # validate site/dist
 *   node scripts/validate-jsonld.mjs <dir>
 *
 * Exit 1 on any ERROR (a real Rich Results failure). WARN = Google "non-critical / optional".
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const ROOT = process.argv[2] || 'dist';
const ISO_TZ = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$/;
const ARTICLE = new Set(['Article', 'TechArticle', 'BlogPosting', 'NewsArticle']);

let errors = 0;
let warns = 0;
let pages = 0;
let blocks = 0;
const seen = new Set(); // report each (type, issue) once to keep output readable

function walk(dir) {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    const s = statSync(p);
    if (s.isDirectory()) walk(p);
    else if (p.endsWith('.html')) checkFile(p);
  }
}

function err(where, msg) {
  errors++;
  const k = `E:${msg}`;
  if (!seen.has(k)) { seen.add(k); console.error(`  ERROR  ${msg}\n         e.g. ${where}`); }
}
function warn(msg, where) {
  warns++;
  const k = `W:${msg}`;
  if (!seen.has(k)) { seen.add(k); console.warn(`  warn   ${msg}\n         e.g. ${where}`); }
}

function checkNode(n, where) {
  const type = Array.isArray(n['@type']) ? n['@type'][0] : n['@type'];
  if (!type) return;
  if (ARTICLE.has(type)) {
    if (!n.headline) err(where, `${type}: missing headline`);
    if (!n.image) err(where, `${type}: missing image`);
    if (!n.author || (Array.isArray(n.author) && !n.author.length)) err(where, `${type}: missing author`);
    const a = Array.isArray(n.author) ? n.author[0] : n.author;
    if (a && !a.name && !a['@id']) err(where, `${type}: author has no name`);
    for (const f of ['datePublished', 'dateModified']) {
      if (n[f] && !ISO_TZ.test(n[f])) err(where, `${type}: ${f} is not ISO-8601 with timezone (${n[f]})`);
    }
    if (!n.datePublished) warn(`${type}: no datePublished (optional)`, where);
  }
  if (type === 'BreadcrumbList') {
    const items = n.itemListElement || [];
    if (!items.length) err(where, 'BreadcrumbList: empty itemListElement');
    items.forEach((it) => {
      if (it.position == null || !it.name || !it.item) err(where, 'BreadcrumbList: item missing position/name/item');
    });
  }
  if (type === 'Organization' && (!n.name || !n.url)) err(where, 'Organization: missing name/url');
  if (type === 'WebSite' && (!n.url || !n.name)) err(where, 'WebSite: missing url/name');
  if (type === 'SoftwareApplication') {
    if (!n.name) err(where, 'SoftwareApplication: missing name');
    if (!n.offers && !n.aggregateRating) warn('SoftwareApplication: no offers/aggregateRating', where);
    else if (!n.aggregateRating) warn('SoftwareApplication: no aggregateRating (optional, needs real reviews)', where);
  }
}

function checkFile(path) {
  pages++;
  const html = readFileSync(path, 'utf-8');
  const where = relative(ROOT, path);
  const re = /<script type="application\/ld\+json">([\s\S]*?)<\/script>/g;
  let m;
  while ((m = re.exec(html))) {
    blocks++;
    let data;
    try {
      data = JSON.parse(m[1]);
    } catch (e) {
      err(where, `invalid JSON in ld+json: ${e.message}`);
      continue;
    }
    const nodes = data['@graph'] || [data];
    if (!data['@context']) err(where, 'missing @context');
    for (const n of nodes) checkNode(n, where);
  }
}

walk(ROOT);
console.log(`\nJSON-LD: ${blocks} blocks across ${pages} pages · ${errors} error(s) · ${warns} warning type(s)`);
if (errors) {
  console.error('FAILED — fix the errors above (they would fail the Rich Results Test).');
  process.exit(1);
}
console.log('OK — no Rich Results errors (warnings are Google "optional / non-critical").');
