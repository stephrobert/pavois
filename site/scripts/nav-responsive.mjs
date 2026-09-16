// Which header elements are actually visible, at a given viewport width, in the BUILT stylesheet.
//
// This exists because of a bug that no amount of reading the source would have shown. Near the
// start of global.css, `@media (max-width: 980px) { .nav-links { display: none } }` hides the
// desktop links on mobile. Two thousand lines later, a rule added for the standards dropdown wrote
// `.nav-links { display: flex }` with no media query at all.
//
// A media query adds NO specificity. Same selector, same specificity, later in source: the
// unconditional `display: flex` won at every width. The mobile links never hid, the header wrapped
// onto a second row behind the hamburger, and it stayed that way on every page of the site.
//
// So the check has to be on the RESOLVED value, not on the presence of a rule. It walks the built
// CSS in order, keeps every declaration whose media condition matches the width, and the last one
// standing is what the browser would use.
//
// Usage: node scripts/nav-responsive.mjs [dist]
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const dist = process.argv[2] ?? 'dist';

// What the header must look like at each width. The hamburger and the flat links are mutually
// exclusive: showing both is the bug, showing neither leaves no way to navigate at all.
const EXPECTATIONS = [
  { width: 360, label: 'phone', visible: ['.hamburger'], hidden: ['.nav-links'] },
  { width: 768, label: 'tablet', visible: ['.hamburger'], hidden: ['.nav-links'] },
  { width: 1280, label: 'desktop', visible: ['.nav-links'], hidden: ['.hamburger'] },
];

function stylesheets(dir) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...stylesheets(p));
    else if (entry.name.endsWith('.css')) out.push(p);
  }
  return out;
}

const ROOT_FONT_PX = 16;

function toPx(value, unit) {
  return unit.toLowerCase() === 'rem' ? Number(value) * ROOT_FONT_PX : Number(value);
}

// The source is written with min-width/max-width, but the build MINIFIES those into the modern
// range syntax, (width<=980px), and some sources use rem. A checker that only understood the
// source form would have reported "condition not understood" on the very file it is meant to
// check. Both forms are handled, and a condition that is still not understood is reported rather
// than assumed to match: silently ignoring a query is how a checker starts lying.
function mediaMatches(condition, width) {
  const parts = condition.split(/\s+and\s+/i).map((s) => s.trim());
  for (const part of parts) {
    if (/^(screen|all|only\s+screen)$/i.test(part)) continue;

    // A non-width feature query. It does not constrain width, and for a layout check the default
    // user is assumed: no reduced motion, no forced colors. Those blocks do not apply.
    if (/\((prefers-|forced-colors|hover|pointer|orientation|color|resolution)/i.test(part)) {
      return false;
    }

    const legacy = part.match(/\(\s*(min|max)-width\s*:\s*([\d.]+)(px|rem)\s*\)/i);
    if (legacy) {
      const bound = toPx(legacy[2], legacy[3]);
      if (legacy[1].toLowerCase() === 'min' ? width < bound : width > bound) return false;
      continue;
    }

    const range = part.match(/\(\s*width\s*(<=|>=|<|>|=)\s*([\d.]+)(px|rem)\s*\)/i);
    if (range) {
      const bound = toPx(range[2], range[3]);
      const ok = {
        '<=': width <= bound,
        '>=': width >= bound,
        '<': width < bound,
        '>': width > bound,
        '=': width === bound,
      }[range[1]];
      if (!ok) return false;
      continue;
    }

    return null; // genuinely unknown
  }
  return true;
}

// Resolve `display` for one selector at one width, by scanning declarations in source order.
function resolveDisplay(css, selector, width) {
  let value = null;
  let unknown = 0;
  // Walk blocks, tracking the innermost @media condition. The stylesheet nests at most one level.
  const re = /@media([^{]+)\{|([^{}]+)\{([^{}]*)\}|\}/g;
  let media = null;
  let depth = 0;
  let m;
  while ((m = re.exec(css)) !== null) {
    if (m[1] !== undefined) {
      media = m[1].trim();
      depth = 1;
      continue;
    }
    if (m[0] === '}') {
      if (depth === 1) {
        media = null;
        depth = 0;
      }
      continue;
    }
    const selectors = m[2].split(',').map((s) => s.trim());
    if (!selectors.includes(selector)) continue;
    if (media !== null) {
      const hit = mediaMatches(media, width);
      if (hit === null) {
        unknown += 1;
        continue;
      }
      if (!hit) continue;
    }
    const decl = m[3].match(/(?:^|;)\s*display\s*:\s*([^;!]+)/i);
    if (decl) value = decl[1].trim();
  }
  return { value, unknown };
}

const files = stylesheets(dist);
if (files.length === 0) {
  console.error(`nav-responsive: no stylesheet under ${dist}/ (build the site first)`);
  process.exit(1);
}

let failures = 0;
let checked = 0;
for (const { width, label, visible, hidden } of EXPECTATIONS) {
  const notes = [];
  for (const selector of [...visible, ...hidden]) {
    let resolved = null;
    let unknown = 0;
    for (const f of files) {
      const r = resolveDisplay(readFileSync(f, 'utf8'), selector, width);
      if (r.value !== null) resolved = r.value;
      unknown += r.unknown;
    }
    if (unknown) notes.push(`${selector}: ${unknown} media condition(s) not understood`);
    checked += 1;

    const wantHidden = hidden.includes(selector);
    const isHidden = resolved === 'none';
    if (wantHidden && !isHidden) {
      notes.push(`${selector} should be hidden, resolves to display:${resolved ?? '(unset)'}`);
    }
    if (!wantHidden && isHidden) {
      notes.push(`${selector} should be visible, resolves to display:none`);
    }
  }
  if (notes.length) {
    failures += 1;
    console.log(`  FAIL ${label} (${width}px)`);
    for (const n of notes) console.log(`       ${n}`);
  } else {
    console.log(`  ok   ${label} (${width}px)`);
  }
}

console.log(
  failures
    ? `nav-responsive: the header is not responsive at ${failures} width(s)`
    : `nav-responsive: ${checked} resolved declaration(s), the header switches to the drawer as it should`,
);
process.exit(failures ? 1 : 0);
