// The install instructions, once.
//
// They used to live in three places: README.md, the installation page and the get-started page.
// They drifted, as duplicated instructions always do. The get-started page led with a build from
// source and said no release existed; the installation page led with a binary; one of them told the
// reader to pipe a script into a shell while the other said, correctly, that a hardening tool whose
// first line is `curl | sh` has already lost the argument. Every one of those was a separate fix.
//
// This project already answers this for its rule base: one source in rules.yml, every per-OS file
// generated from it. The install commands get the same treatment. A page renders these blocks, it
// does not retype them, and `mise run lint:install-docs` (in prepush) fails the build if a page
// grows its own copy, pipes a download into a shell, or renders a block that is not exported here.
// That linter is itself proven by tools/lint_install_docs_test.py, which plants each defect in a
// copy of the tree and demands a rejection: this comment claimed the guard existed long before it
// did, and an unproven guard is how that happens.
//
// VERSION is the one value to bump per release.

export const VERSION = 'v0.1.7';
export const REPO = 'stephrobert/pavois';
export const RELEASE_BASE = `https://github.com/${REPO}/releases/download/${VERSION}`;

type Bi = { en: string; fr: string };

/** A block of shell, with the trailing comments localized. */
export type Block = { id: string; code: (fr: boolean) => string };

const t = (fr: boolean, s: Bi) => (fr ? s.fr : s.en);

/**
 * Download and verify the static binary. curl is the entire dependency list, because the rule
 * corpus is embedded in the binary.
 *
 * Downloading a file and then checking its hash is NOT piping a script into a shell: nothing runs
 * until sha256sum has confirmed the published checksum. That distinction is why this block is the
 * primary path everywhere, and why no page may offer `curl ... | sh` for anything.
 */
export const binaryCurl: Block = {
  id: 'binary-curl',
  code: (fr) => `BASE=${RELEASE_BASE}
curl -fsSLO $BASE/pavois-linux-amd64 && curl -fsSLO $BASE/checksums.txt
sha256sum --ignore-missing --check checksums.txt   # ${t(fr, { en: 'integrity', fr: 'intégrité' })}
sudo install -m 0755 pavois-linux-amd64 /usr/local/bin/pavois
pavois doctor                            # ${t(fr, { en: 'corpus embedded, ready to scan', fr: 'corpus embarqué, prêt à scanner' })}`,
};

/**
 * The provenance check alone, to be shown AFTER an install the reader has already done.
 *
 * It is one line on purpose. Offering the whole gh download path as the primary route puts a tool
 * between the reader and the binary for no gain: gh downloads the same file curl does. What gh adds
 * is this, and only this, so this is what gets shown next to the words that explain it.
 */
export const provenance: Block = {
  id: 'provenance',
  code: (fr) => `gh attestation verify pavois-linux-amd64 --repo ${REPO}   # ${t(fr, { en: 'who built it', fr: 'qui l’a construit' })}`,
};

/** The same, through GitHub CLI, which additionally proves WHO built the file. */
export const binaryGh: Block = {
  id: 'binary-gh',
  code: (fr) => `gh release download --repo ${REPO} \\
  --pattern 'pavois-linux-amd64' --pattern 'checksums.txt'
sha256sum --ignore-missing --check checksums.txt   # ${t(fr, { en: 'integrity', fr: 'intégrité' })}
gh attestation verify pavois-linux-amd64 --repo ${REPO}   # ${t(fr, { en: 'SLSA provenance', fr: 'provenance SLSA' })}
sudo install -m 0755 pavois-linux-amd64 /usr/local/bin/pavois && pavois version`,
};

export const packages: Block = {
  id: 'packages',
  code: () => `curl -fsSLO $BASE/pavois_${VERSION.slice(1)}_amd64.deb && sudo dpkg -i pavois_${VERSION.slice(1)}_amd64.deb
curl -fsSLO $BASE/pavois-${VERSION.slice(1)}.amd64.rpm && sudo rpm -i pavois-${VERSION.slice(1)}.amd64.rpm`,
};

/**
 * Install the scan engine, the one prerequisite no package manager can fetch.
 *
 * Why this block exists. The installation page used to say "the cinc-auditor binary, which you
 * install yourself: pavois doctor prints the omnitruck command when it is missing", and then never
 * printed the command. The page explained the requirement and sent the reader to a tool to find out
 * how to satisfy it. A field report of "missing dependencies on AlmaLinux" was exactly this: the
 * package installs, nothing is missing, and the first scan stops on an engine nobody was told to
 * install.
 *
 * Why NOT the omnitruck one-liner that upstream documents. It is
 * `curl -L https://omnitruck.cinc.sh/install.sh | sudo bash -s -- -P cinc-auditor`, a script piped
 * into a root shell, which is the one thing this site says it will never ask for. The same endpoint
 * also publishes the package URL and its sha256, so the rule costs nothing here: download, verify,
 * install with the system package manager, and nothing executes until sha256sum has agreed.
 *
 * Why the platform keys are DERIVED and not written in the snippet (#390). They used to be
 * `p=el&pv=9`, hardcoded, with the Debian answer demoted to a trailing comment that said
 * "Debian/Ubuntu: sudo apt install ./<file>". A reader on Ubuntu 24.04 did exactly what the block
 * said, and the block handed them `cinc-auditor-7.2.1-1.el9.x86_64.rpm`: an RPM, on Ubuntu,
 * because the URL above the comment never changed. The comment described a choice the command did
 * not offer.
 *
 * So the block now reads `/etc/os-release` and derives p, pv AND the package manager together, on
 * one line each, which is what makes them impossible to disagree. The p/pv keys are omnitruck's
 * own: el/8, el/9, debian/12, debian/13, ubuntu/22.04, ubuntu/24.04. AlmaLinux, Rocky and CentOS
 * declare as `el`, as they do for Pavois's own profile detection.
 *
 * Fedora is deliberately absent from the case, and the `${P:?…}` guard is why that is safe rather
 * than merely incomplete. Asked for `p=fedora&pv=40`, omnitruck answers with
 * `cinc-auditor-6.6.0-1.el7.x86_64.rpm`: a four-major-versions-old build for el7. A snippet that
 * mapped Fedora would install that silently. Unset `P` makes the command refuse, with a message,
 * leaving an interactive shell alive.
 *
 * The guard's message stays English in both languages on purpose: it is output of a command, not
 * page copy, and `scripts/shell-blocks-parity.mjs` requires the EN and FR blocks to run the same
 * commands, with only the trailing comments translated.
 */
export const engineInstall: Block = {
  id: 'engine-install',
  code: (fr) => `. /etc/os-release                                    # ${t(fr, { en: 'the platform keys, read from the system', fr: 'les clés de plateforme, lues sur le système' })}
case $ID in
  debian|ubuntu) P=$ID PV=$VERSION_ID PKG=apt ;;
  rhel|almalinux|rocky|centos) P=el PV=\${VERSION_ID%%.*} PKG=dnf ;;
esac
META="https://omnitruck.cinc.sh/stable/cinc-auditor/metadata?p=\${P:?unsupported platform, see the keys below}&pv=$PV&m=x86_64"
URL=$(curl -sS "$META" | awk '/^url/{print $2}')     # ${t(fr, { en: 'the package for THIS platform', fr: 'le paquet de CETTE plateforme' })}
SUM=$(curl -sS "$META" | awk '/^sha256/{print $2}')  # ${t(fr, { en: 'and its published checksum', fr: 'et son empreinte publiée' })}
curl -fsSLO "$URL"
echo "$SUM  \${URL##*/}" | sha256sum --check         # ${t(fr, { en: 'integrity, before anything runs', fr: 'intégrité, avant toute exécution' })}
sudo $PKG install -y "./\${URL##*/}"                 # ${t(fr, { en: 'apt on Debian/Ubuntu, dnf on the el family', fr: 'apt sur Debian/Ubuntu, dnf sur la famille el' })}
pavois doctor                                        # ${t(fr, { en: 'CINC engine (native): /usr/bin/cinc-auditor', fr: 'moteur CINC (natif) : /usr/bin/cinc-auditor' })}`,
};

/**
 * mise, from a SIGNED repository. extrepo enables mise's APT repository and verifies its key.
 * There is deliberately no `curl https://mise.run | sh` here, however convenient: the get-started
 * page states the rule, so no page of this site may break it.
 */
export const miseInstall: Block = {
  id: 'mise-install',
  code: (fr) => `sudo apt install -y extrepo && sudo extrepo enable mise   # ${t(fr, { en: 'a signed repository, never a piped script', fr: 'dépôt signé, jamais un script tubé' })}
sudo apt update && sudo apt install -y mise
# ${t(fr, { en: 'Fedora / RHEL:', fr: 'Fedora / RHEL :' })} dnf copr enable jdxcode/mise && dnf install mise
# ${t(fr, { en: 'macOS:', fr: 'macOS :' })} brew install mise`,
};

/** Build from source. For contributors, and only for them. */
export const buildFromSource: Block = {
  id: 'build-from-source',
  code: (fr) => `git clone https://github.com/${REPO}.git && cd pavois
mise trust && mise install   # ${t(fr, { en: 'pinned Go, Node, Python', fr: 'Go, Node, Python épinglés' })}
mise run build               # -> go/pavois
mise run regen               # ${t(fr, { en: 'rule corpus + OSCAL from the reference', fr: 'corpus .rb + OSCAL depuis la référence' })}
./go/pavois doctor           # ${t(fr, { en: 'check CINC, sudo, SSH, OS, corpus', fr: 'vérifie CINC, sudo, SSH, OS, corpus' })}`,
};

/** First scan, appended to the quickstart so a reader reaches a verdict without leaving the page. */
export const firstScan: Block = {
  id: 'first-scan',
  code: (fr) => `pavois scan local --sudo --format html   # ${t(fr, { en: 'audit this host, A to E grade', fr: 'audite cet hôte, note A à E' })}
pavois serve                             # http://localhost:8098`,
};

export const ALL: Block[] = [
  binaryCurl,
  provenance,
  binaryGh,
  packages,
  engineInstall,
  miseInstall,
  buildFromSource,
  firstScan,
];
