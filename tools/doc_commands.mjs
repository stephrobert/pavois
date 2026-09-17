// Print the commands the documentation actually tells a reader to run, by block id and language.
//
// WHY: the install pages are rendered from site/src/data/install.ts, and a verification harness
// that retypes those commands is a second copy that drifts. `tools/release/scenario.sh` used to
// carry its own hand-written engine install, so the day the page changed, the scenario would have
// kept proving the old one. Here the documentation IS the test input: whatever the reader is told
// to run is exactly what gets run on the VM.
//
// The source is the right place to read from rather than the built HTML: tools/lint_install_docs.py
// already fails the build if a page grows its own copy of a command, so validating the source
// validates every page that renders it. And the HTML is syntax-highlighted into spans, which would
// mean parsing colour markup to recover a shell line.
//
// Usage:
//   node --experimental-strip-types tools/doc_commands.mjs --list
//   node --experimental-strip-types tools/doc_commands.mjs --id engine-install [--lang fr]
//   node --experimental-strip-types tools/doc_commands.mjs --check      (fr and en run the same thing)

import * as install from '../site/src/data/install.ts';

const args = process.argv.slice(2);
const opt = (name, fallback = null) => {
  const i = args.indexOf(name);
  return i === -1 ? fallback : args[i + 1];
};
const has = (name) => args.includes(name);

const blocks = install.ALL;

if (has('--list')) {
  for (const b of blocks) console.log(b.id);
  process.exit(0);
}

if (has('--check')) {
  // A command is not a translation. Only the trailing comment may differ between languages: the
  // commands themselves must be byte-identical, or a French reader and an English reader are being
  // told to run two different things.
  // Drop whole-line comments as well as trailing ones. A line that is only a comment carries no
  // command, and French typography puts a space before a colon, so `# Fedora / RHEL :` and
  // `# Fedora / RHEL:` would otherwise be reported as two different commands.
  const strip = (s) =>
    s
      .split('\n')
      .filter((l) => !/^\s*#/.test(l))
      .map((l) => l.replace(/\s+#.*$/, '').trimEnd())
      .join('\n');
  let bad = 0;
  for (const b of blocks) {
    const en = strip(b.code(false));
    const fr = strip(b.code(true));
    if (en !== fr) {
      bad++;
      console.error(`${b.id}: the two languages run different commands`);
      console.error(`  en: ${en.replace(/\n/g, ' | ')}`);
      console.error(`  fr: ${fr.replace(/\n/g, ' | ')}`);
    }
  }
  if (bad) {
    console.error(`\n${bad} block(s) differ beyond their comments.`);
    process.exit(1);
  }
  console.log(`doc commands: ${blocks.length} block(s), both languages run the same commands`);
  process.exit(0);
}

const id = opt('--id');
if (!id) {
  console.error('usage: --list | --check | --id <block-id> [--lang fr]');
  process.exit(2);
}
const block = blocks.find((b) => b.id === id);
if (!block) {
  console.error(`no block ${JSON.stringify(id)}. Known: ${blocks.map((b) => b.id).join(', ')}`);
  process.exit(1);
}
console.log(block.code(opt('--lang', 'en') === 'fr'));
