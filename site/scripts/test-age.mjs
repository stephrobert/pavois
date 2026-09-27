#!/usr/bin/env node
/**
 * Check the evidence age helper (#371).
 *
 * The defect being pinned: the platforms page baked `age_days` into static HTML, so it published
 * "0 days ago" about a five-day-old campaign and would have gone on doing so indefinitely. The
 * whole value of this helper is that the number changes without a rebuild, and the whole value of
 * this file is that the claim can be falsified.
 *
 * Plain node, no test runner: this repository watches what it depends on, and fifteen assertions do
 * not justify a dependency.
 */
import { relativeAge } from '../src/lib/age.mjs';

const DAY = 86400000;
const NOW = Date.parse('2026-09-26T12:00:00+00:00');
let failed = 0;

function check(name, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  if (!ok) {
    failed += 1;
    console.log(`  FAIL  ${name}\n          got  ${JSON.stringify(got)}\n          want ${JSON.stringify(want)}`);
  } else {
    console.log(`  ok    ${name}`);
  }
}

const age = (ran, w = 30, fr = false) => {
  const r = relativeAge(ran, NOW, w, fr);
  return r && { days: r.days, pastWindow: r.pastWindow };
};

check('a campaign from today is 0 days old', age('2026-09-26T09:00:00+00:00'), { days: 0, pastWindow: false });

// THE WITNESS. This is the published defect, expressed as an assertion: the campaigns the site was
// serving ran on 2026-09-21 and the page said "0 days ago" on the 26th.
check('the five-day-old campaign the site called fresh', age('2026-09-21T19:16:06+00:00'), {
  days: 4,
  pastWindow: false,
});

check('exactly on the window is still inside it', age(new Date(NOW - 30 * DAY).toISOString()), {
  days: 30,
  pastWindow: false,
});
check('one day past the window is past it', age(new Date(NOW - 31 * DAY).toISOString()), {
  days: 31,
  pastWindow: true,
});
check('a year old is very much past it', age(new Date(NOW - 365 * DAY).toISOString()), {
  days: 365,
  pastWindow: true,
});

// A reader whose clock is behind the runner's must not be shown a negative age. This page has
// already published "il y a -1 j" once, from a local timestamp parsed as UTC.
check('a future timestamp clamps to zero', age(new Date(NOW + 2 * DAY).toISOString()), {
  days: 0,
  pastWindow: false,
});

check('no timestamp yields nothing to render', age(null), null);
check('an empty timestamp yields nothing', age(''), null);
check('an unparseable timestamp yields nothing', age('last tuesday'), null);

// The window comes from the matrix, so a matrix that does not carry one must not invent staleness.
// Called directly rather than through the helper above, whose `w = 30` default swallowed the
// `undefined` and made this case test the opposite of what it says. The first run caught it.
const noWindow = relativeAge(new Date(NOW - 900 * DAY).toISOString(), NOW, undefined, false);
check('an absent window never marks anything stale', { days: noWindow.days, pastWindow: noWindow.pastWindow }, {
  days: 900,
  pastWindow: false,
});

const en = relativeAge('2026-09-21T19:16:06+00:00', NOW, 30, false);
const fr = relativeAge('2026-09-21T19:16:06+00:00', NOW, 30, true);
check('English wording', en.text, `4 days ago`);
check('French wording', fr.text, `il y a 4 j`);

// The helper must be reading the clock it is given, not the one on the wall: a test that passes
// because both happen to be today proves nothing next week.
const moving = relativeAge('2026-09-21T19:16:06+00:00', NOW + 10 * DAY, 30, false);
check('the same campaign ages as the clock moves', moving.days, 14);

console.log(`\ntest-age: ${failed === 0 ? 'all checks passed' : `${failed} FAILED`}`);
process.exit(failed === 0 ? 0 : 1);
