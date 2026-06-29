// Per-domain coverage depth, the honest edges, mirrored from /handbook/coverage. Three levels:
//   deep   , audited thoroughly, lean on it alone.
//   partial, audited beyond mere presence, but with named gaps (e.g. journald flags, no remote
//             log integrity); usable, read the caveat.
//   shallow, presence / default only, not enough to lean on alone (e.g. firewall presence, no
//             ruleset audit; time sync present, no source/drift policy).
// Single source for the /rules badge, the fiche caveat and the standards pages.
export type Coverage = 'deep' | 'partial' | 'shallow';

export const SHALLOW_DOMAINS = new Set<string>([
  'Firewall',
  'Time synchronization',
]);

export const PARTIAL_DOMAINS = new Set<string>([
  'Logging (journald)',
  'Logging',
]);

export function coverageLevel(domain: string | null | undefined): Coverage {
  if (!domain) return 'deep';
  if (SHALLOW_DOMAINS.has(domain)) return 'shallow';
  if (PARTIAL_DOMAINS.has(domain)) return 'partial';
  return 'deep';
}

export const coverageLabel: Record<Coverage, { en: string; fr: string }> = {
  deep: { en: 'in depth', fr: 'en profondeur' },
  partial: { en: 'partial', fr: 'partielle' },
  shallow: { en: 'shallow', fr: 'superficielle' },
};
