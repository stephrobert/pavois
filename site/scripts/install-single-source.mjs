// No page may grow its own copy of an install command.
//
// The install instructions lived in three places and drifted, as duplicated instructions always do.
// One page led with a build from source and announced that no release existed; another led with the
// binary. One told the reader to pipe a script into a shell, while the other said, correctly, that a
// hardening tool whose first line is `curl | sh` has already lost the argument. Each of those was
// found by a reader, one at a time, and fixed one at a time.
//
// src/data/install.ts is now the single source. This guard is what keeps it single: it scans the
// page sources for install commands written as literals, and fails on any that is not an import
// from that module. It also enforces the `curl | sh` ban, because the site states that rule in
// prose and a rule nothing checks is a rule that will be broken by the next convenient shortcut.
//
// Usage: node scripts/install-single-source.mjs [srcDir]
import { readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';

const src = process.argv[2] ?? 'src';
const SOURCE = join('src', 'data', 'install.ts');

// Commands that install or fetch Pavois or its toolchain. A page naming any of these in a template
// literal is writing its own copy.
const COMMANDS = [
  { re: /gh release download/, what: 'gh release download' },
  { re: /gh attestation verify/, what: 'gh attestation verify' },
  { re: /releases\/download\//, what: 'a release download URL' },
  { re: /extrepo enable mise/, what: 'the mise repository setup' },
  { re: /mise run regen/, what: 'the from-source build' },
  { re: /sha256sum --ignore-missing/, what: 'the checksum verification' },
  { re: /dpkg -i pavois|rpm -i pavois/, what: 'the package install' },
];

// Piping a downloaded script straight into a shell. `curl -fsSLO ... && sh script.sh` is not this:
// the ban is on execution without an intervening check, which is exactly what a pipe removes.
const PIPE_TO_SHELL = /curl[^\n|]*\|\s*(sudo\s+)?(ba|z|d)?sh\b/;

function sources(dir) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...sources(p));
    else if (/\.(astro|md|mdx|ts|json)$/.test(entry.name)) out.push(p);
  }
  return out;
}

/**
 * Only the CODE a page renders, never its prose.
 *
 * The first version of this guard matched the whole file and fired six times, every one of them on
 * a sentence explaining the rule: "Pavois will never ask you to curl | sh" is not a page telling
 * anyone to curl | sh. A checker that cannot tell an instruction from a description of an
 * instruction reports the documentation as the defect, and the reader learns to ignore it.
 *
 * So the scan is limited to the shell blocks, which in this site means the backtick literal passed
 * to highlight(). A block built purely from `${install.x.code(fr)}` interpolations has no literal
 * command left in it and passes, which is exactly the shape being asked for.
 */
function shellBlocks(text) {
  const out = [];
  const re = /highlight\(\s*`([\s\S]*?)`/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    const upto = text.slice(0, m.index);
    out.push({ code: m[1], line: upto.split('\n').length });
  }
  return out;
}

const files = sources(src);
const problems = [];
let scanned = 0;
let blocks = 0;

for (const file of files) {
  const rel = relative('.', file);
  const text = readFileSync(file, 'utf8');
  scanned += 1;

  // The source module is allowed to hold the commands: that is its whole job. Its own prose
  // mentions `curl | sh` to explain why it is refused, so it is skipped entirely.
  if (rel === SOURCE || rel.endsWith(SOURCE)) continue;

  for (const { code, line } of shellBlocks(text)) {
    blocks += 1;

    if (PIPE_TO_SHELL.test(code)) {
      problems.push(
        `${rel}:${line}  a shell block pipes a download straight into a shell. The site tells ` +
          `readers Pavois will never ask for that; download, verify the checksum, then run.`,
      );
    }

    for (const { re, what } of COMMANDS) {
      if (!re.test(code)) continue;
      problems.push(
        `${rel}:${line}  a shell block writes ${what} as a literal. Render it from ` +
          `src/data/install.ts instead, so there is one copy to keep true.`,
      );
    }
  }
}

if (problems.length) {
  console.log(`install-single-source: ${problems.length} place(s) keep their own copy\n`);
  for (const p of problems) console.log(`  ${p}`);
  console.log(
    '\nsrc/data/install.ts holds the blocks. A page renders them; it does not retype them.',
  );
  process.exit(1);
}

// An empty sweep is not a clean sweep: a moved directory or a changed highlight() call would leave
// nothing to inspect and this would announce success having looked at nothing.
if (blocks === 0) {
  console.log(`install-single-source: no shell block found under ${src}/, so nothing was verified`);
  process.exit(1);
}

console.log(`install-single-source: ${scanned} source file(s), ${blocks} shell block(s) checked`);
console.log('install-single-source: the install commands have exactly one home');
