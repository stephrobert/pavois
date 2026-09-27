#!/usr/bin/env node
/**
 * Run the script the BUILT page actually ships, against a minimal DOM (#371).
 *
 * scripts/test-age.mjs proves the arithmetic. This proves the page uses it: that the selector
 * matches, that the data attributes are read, and that the text lands in the element. Those are
 * different failures, and a correct helper nobody calls renders an empty column, which is worse
 * than the stale number it replaced.
 *
 * The script is extracted from dist/ rather than from src/, so what runs here is what a reader
 * downloads, minifier included. No jsdom: this repository dropped unlighthouse over 512 transitive
 * packages, and thirty lines of fake DOM are cheaper than a dependency.
 *
 *   node scripts/test-age-dom.mjs        (after `mise run site:build`)
 */
import { readFileSync, existsSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const PAGE = process.argv[2] ?? 'dist/en/platforms/index.html';
if (!existsSync(PAGE)) {
  console.log(`test-age-dom: ${PAGE} is missing; run \`mise run site:build\` first`);
  process.exit(1);
}

const html = readFileSync(PAGE, 'utf8');
const m = html.match(/<script type="module">([\s\S]*?)<\/script>/);
if (!m) {
  console.log('test-age-dom: the built page ships no module script, so nothing fills the age column');
  process.exit(1);
}
const shipped = m[1];

// A stand-in for exactly the surface the script touches.
function fakeEl(dataset) {
  const classes = new Set();
  const row = { classList: { add: (c) => classes.add(`row:${c}`), has: (c) => classes.has(`row:${c}`) } };
  return {
    dataset,
    textContent: '',
    title: '',
    classList: { add: (c) => classes.add(c), contains: (c) => classes.has(c) },
    closest: () => row,
    _classes: classes,
  };
}

const DAY = 86400000;
const fresh = fakeEl({ ran: new Date(Date.now() - 3 * DAY).toISOString(), window: '30', lang: 'en' });
const old = fakeEl({ ran: new Date(Date.now() - 400 * DAY).toISOString(), window: '30', lang: 'en' });
const french = fakeEl({ ran: new Date(Date.now() - 2 * DAY).toISOString(), window: '30', lang: 'fr' });
const broken = fakeEl({ ran: 'not a date', window: '30', lang: 'en' });
const els = [fresh, old, french, broken];

runInNewContext(shipped, {
  document: { querySelectorAll: (sel) => (sel.includes('.age') ? els : []) },
  Date,
  Number,
  Math,
  console,
});

let failed = 0;
const check = (name, ok, detail = '') => {
  if (ok) console.log(`  ok    ${name}`);
  else {
    failed += 1;
    console.log(`  FAIL  ${name}${detail ? `\n          ${detail}` : ''}`);
  }
};

check('a fresh row gets its age written', /^3 days ago$/.test(fresh.textContent), `got ${JSON.stringify(fresh.textContent)}`);
check('a fresh row is not marked past the window', !fresh._classes.has('past-window'));
check('an old row gets its age written', /^400 days ago$/.test(old.textContent), `got ${JSON.stringify(old.textContent)}`);
check('an old row IS marked past the window', old._classes.has('past-window'));
check('an old row marks its table row too', old._classes.has('row:past-window'));
check('an old row explains itself on hover', /30-day window/.test(old.title), `got ${JSON.stringify(old.title)}`);
check('French rows are written in French', /^il y a 2 j$/.test(french.textContent), `got ${JSON.stringify(french.textContent)}`);
check('an unparseable date leaves the element alone', broken.textContent === '');

console.log(`\ntest-age-dom: ${failed === 0 ? 'the shipped script fills the column' : `${failed} FAILED`}`);
process.exit(failed === 0 ? 0 : 1);
