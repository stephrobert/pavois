import { coverageLevel, type Coverage } from '../data/coverage';

/**
 * Domain hubs, the middle floor of the control catalogue.
 *
 * Why this exists at all. `/rules/` is a windowed table: it server-renders 60 rows and builds the
 * other 730 client-side from an embedded JSON blob, which is right for the reader and wrong for a
 * crawler. Measured on the published site: 60 of 790 fiches were reachable through an `<a href>`,
 * and 400 fiches (200 per language) had NO inbound internal link at all except their counterpart
 * in the other language. Those fiches existed only in the sitemap, which is the weakest discovery
 * channel there is, and Google duly stalled: 1100 of 1700 URLs processed, then a plateau.
 *
 * A hub per domain fixes the cause rather than the symptom. Every fiche gains a crawlable parent
 * that lists it, the catalogue gains 34 links instead of 790, and the depth from the home page
 * stays at three clicks. The hubs are not doorways: a domain is the unit this corpus is actually
 * organised by (`domain` is a first-class field of every rule), so the page has real facts to
 * state, all of them derived from the corpus rather than written by hand.
 *
 * Everything here is a pure function over the rule collection, so the sitemap, the catalogue, the
 * hubs and the fiches all compute the same slugs from the same place. A second implementation of
 * `domainSlug` somewhere else is how a fiche ends up linking to a hub that was never generated.
 */

/** The slice of a rule's data this module needs. Generic callers keep their own richer type. */
export type RuleData = {
  id: string;
  domain?: string | null;
  severity: string;
  supported_os: string[];
  norms: Record<string, string | string[]>;
  evidence_type?: string | null;
  title: { en: string; fr: string };
};

/** Severity, most serious first. The display order of every severity list on the hubs. */
export const SEVERITY_ORDER = ['critical', 'high', 'medium', 'low', 'unknown'] as const;

/** Standards, in the order the rest of the site lists them. */
export const NORM_ORDER = ['cis', 'bp28', 'nist', 'pci-dss', 'stig'] as const;

const severityRank = (s: string): number => {
  const i = (SEVERITY_ORDER as readonly string[]).indexOf(s);
  return i < 0 ? SEVERITY_ORDER.length : i;
};

/**
 * The hub URL segment for a domain name.
 *
 * Domain names are display strings holding spaces, ampersands, slashes and parentheses
 * (`Kernel & network (sysctl)`, `Cron/at access control`), so the slug is derived, never authored:
 * one authored list to keep in sync with 34 domains is one list that drifts.
 */
export function domainSlug(domain: string): string {
  return domain
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

export type DomainGroup<T extends RuleData = RuleData> = {
  /** The canonical English domain name. It stays the identifier: filters, sorts, data attributes. */
  domain: string;
  slug: string;
  /** The domain's controls, most severe first, then by English title so the order is stable. */
  rules: T[];
};

/**
 * Group the corpus by domain, severity-sorted, with the slugs proven unique.
 *
 * The uniqueness check throws instead of warning. Two domains sharing a slug would quietly serve
 * one hub for both, which drops a whole domain's fiches out of the internal link graph: exactly
 * the failure this module exists to undo, and invisible in any report short of a crawl.
 */
export function groupByDomain<T extends RuleData>(rules: T[]): DomainGroup<T>[] {
  const by = new Map<string, T[]>();
  for (const r of rules) {
    // A rule with no domain belongs to no hub. The catalogue and the sitemap still carry it, so it
    // is not lost, it simply has no parent to be filed under. Today there are none.
    const d = r.domain ?? '';
    if (!d) continue;
    by.set(d, [...(by.get(d) ?? []), r]);
  }

  const groups = [...by.entries()]
    .map(([domain, rs]) => ({
      domain,
      slug: domainSlug(domain),
      rules: [...rs].sort(
        (a, b) => severityRank(a.severity) - severityRank(b.severity) || a.title.en.localeCompare(b.title.en)
      ),
    }))
    .sort((a, b) => a.domain.localeCompare(b.domain));

  const seen = new Map<string, string>();
  for (const g of groups) {
    const clash = seen.get(g.slug);
    if (clash) {
      throw new Error(
        `Domain slug collision: "${clash}" and "${g.domain}" both resolve to "${g.slug}". ` +
          'Rename one domain in site/src/content/rules/*.json, or the two hubs merge silently.'
      );
    }
    seen.set(g.slug, g.domain);
  }
  return groups;
}

export type DomainFacts = {
  total: number;
  /** Severity counts, most serious first, empty buckets omitted. */
  severities: { key: string; count: number }[];
  /** The standards this domain maps to, with the real references found in the corpus. */
  norms: { key: string; refs: string[] }[];
  /** Evidence types the checks gather, most frequent first. */
  evidence: { key: string; count: number }[];
  /** Every OS at least one control of this domain applies to. */
  oses: string[];
  coverage: Coverage;
};

/** A norm field is a string on some rules and an array on others, per the content schema. */
const refsOf = (v: string | string[] | undefined): string[] =>
  v == null ? [] : Array.isArray(v) ? v : v === '' ? [] : [v];

/**
 * Everything a hub states about its domain, computed from the corpus.
 *
 * No prose is generated here and none is authored per domain: a hub asserts counts, severities,
 * standard references, evidence types, OS coverage and the depth the coverage page already
 * declares. Those are checkable facts, which is what an answer engine can quote and what an
 * auditor can verify. Thirty-four hand-written domain essays would be thirty-four unsourced
 * claims, and the project does not publish those.
 */
export function domainFacts(rules: RuleData[]): DomainFacts {
  const sevCount = new Map<string, number>();
  const evCount = new Map<string, number>();
  const normRefs = new Map<string, Set<string>>();
  const oses = new Set<string>();

  for (const r of rules) {
    sevCount.set(r.severity, (sevCount.get(r.severity) ?? 0) + 1);
    if (r.evidence_type) evCount.set(r.evidence_type, (evCount.get(r.evidence_type) ?? 0) + 1);
    for (const os of r.supported_os) oses.add(os);
    for (const [k, v] of Object.entries(r.norms ?? {})) {
      const refs = refsOf(v);
      if (!refs.length) continue;
      const set = normRefs.get(k) ?? new Set<string>();
      for (const ref of refs) set.add(ref);
      normRefs.set(k, set);
    }
  }

  // R8 must sort before R11, so the comparison is numeric-aware rather than lexicographic.
  const natural = (a: string, b: string) => a.localeCompare(b, undefined, { numeric: true });

  return {
    total: rules.length,
    severities: SEVERITY_ORDER.filter((s) => sevCount.has(s)).map((s) => ({ key: s, count: sevCount.get(s)! })),
    norms: [...normRefs.entries()]
      .sort(
        (a, b) =>
          (NORM_ORDER as readonly string[]).indexOf(a[0]) - (NORM_ORDER as readonly string[]).indexOf(b[0])
      )
      .map(([key, set]) => ({ key, refs: [...set].sort(natural) })),
    evidence: [...evCount.entries()].sort((a, b) => b[1] - a[1]).map(([key, count]) => ({ key, count })),
    oses: [...oses].sort(),
    coverage: coverageLevel(rules[0]?.domain),
  };
}

/**
 * The related-controls window shown on a fiche.
 *
 * A fixed "first N of the domain" would hand every sibling link in a 128-control domain to the
 * same N controls and starve the other 116, which is the very imbalance this change is undoing.
 * The window is instead the N controls FOLLOWING this one, wrapping around: on a cycle, every
 * control appears in exactly N other blocks, so the sibling links are spread evenly by
 * construction rather than by review.
 */
export function relatedWindow<T extends RuleData>(rules: T[], id: string, size = 12): T[] {
  const i = rules.findIndex((r) => r.id === id);
  if (i < 0 || rules.length < 2) return [];
  const n = Math.min(size, rules.length - 1);
  return Array.from({ length: n }, (_, k) => rules[(i + 1 + k) % rules.length]);
}
