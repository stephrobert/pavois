#!/usr/bin/env node
/**
 * Tell Bing and Yandex which pages changed, instead of waiting to be crawled.
 *
 * A sitemap says "here is everything, come back when you like". IndexNow says "these N URLs
 * changed just now", and the engines that implement it fetch them in minutes. Google does not
 * participate, so this complements the sitemap rather than replacing it.
 *
 *   node scripts/indexnow.mjs            # submit every URL in dist/sitemap.xml
 *   node scripts/indexnow.mjs --dry-run  # print what would be sent
 *
 * Refuses to submit while the site is noindex: asking an engine to index pages that tell it not
 * to is a contradiction the engine resolves by trusting neither.
 */

import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const DIST = process.argv.find((a) => !a.startsWith("--") && a !== process.argv[0] && a !== process.argv[1]) ?? "dist";
const DRY = process.argv.includes("--dry-run");
const ENDPOINT = "https://api.indexnow.org/IndexNow";

/** The key file is served at /<key>.txt; its name IS the key, and its content must match. */
function findKey(dir) {
  const hits = readdirSync(dir).filter((f) => /^[0-9a-f]{8,128}\.txt$/.test(f));
  if (hits.length !== 1) {
    throw new Error(
      `expected exactly one IndexNow key file in ${dir}, found ${hits.length}: ${hits.join(", ") || "none"}`,
    );
  }
  const key = hits[0].replace(/\.txt$/, "");
  const body = readFileSync(join(dir, hits[0]), "utf8").trim();
  if (body !== key) {
    throw new Error(`${hits[0]} must contain exactly its own name; engines verify that`);
  }
  return key;
}

function urlsFromSitemap(dir) {
  const xml = readFileSync(join(dir, "sitemap.xml"), "utf8");
  return [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
}

function isIndexable(dir) {
  // One page is enough: the flag is site-wide.
  const home = join(dir, "en", "index.html");
  try {
    return !/<meta[^>]+name="robots"[^>]*noindex/i.test(readFileSync(home, "utf8"));
  } catch {
    return false;
  }
}

const key = findKey(DIST);
const urls = urlsFromSitemap(DIST);
if (urls.length === 0) throw new Error("sitemap.xml lists no URL");
const host = new URL(urls[0]).host;

if (!isIndexable(DIST)) {
  console.log(`indexnow: the build is noindex, nothing submitted (${urls.length} URL(s) ready)`);
  process.exit(0);
}

const payload = { host, key, keyLocation: `https://${host}/${key}.txt`, urlList: urls };

if (DRY) {
  console.log(`indexnow: would submit ${urls.length} URL(s) for ${host}`);
  for (const u of urls.slice(0, 5)) console.log(`  ${u}`);
  if (urls.length > 5) console.log(`  ... and ${urls.length - 5} more`);
  process.exit(0);
}

const res = await fetch(ENDPOINT, {
  method: "POST",
  headers: { "Content-Type": "application/json; charset=utf-8" },
  body: JSON.stringify(payload),
});

// 200 accepted, 202 accepted but the key is still being verified. Both are fine.
if (res.status === 200 || res.status === 202) {
  console.log(`indexnow: submitted ${urls.length} URL(s) for ${host} (HTTP ${res.status})`);
  process.exit(0);
}

const body = (await res.text()).slice(0, 300);

// The engine verifies the key file out of band, and the first submission after a key goes live
// routinely lands while that is still running. It is a state to wait out, not a defect in the
// build, and failing the deploy on it would turn a successful publish red for no reason. The next
// deploy retries; a key that is genuinely wrong fails with 403 KeyNotFound instead, which is
// caught below.
if (res.status === 403 && /SiteVerificationNotCompleted/i.test(body)) {
  console.log(`indexnow: the engine is still verifying the key, ${urls.length} URL(s) not submitted yet`);
  console.log(`indexnow: this resolves on its own; the next deploy submits them`);
  process.exit(0);
}

console.error(`indexnow: rejected with HTTP ${res.status}: ${body}`);
process.exit(1);
