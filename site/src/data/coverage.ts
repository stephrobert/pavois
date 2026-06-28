// Per-domain coverage depth — the honest edges, mirrored from /handbook/coverage. A `shallow`
// domain exists in the base but is not deep enough to lean on alone (e.g. firewall presence only,
// no ruleset audit); everything else is audited in depth. Single source for the /rules badge, the
// fiche caveat and the standards pages.
export type Coverage = 'deep' | 'shallow';

export const SHALLOW_DOMAINS = new Set<string>([
  'Firewall',
  'Logging (journald)',
  'Logging',
  'Time synchronization',
]);

export function coverageLevel(domain: string | null | undefined): Coverage {
  return domain && SHALLOW_DOMAINS.has(domain) ? 'shallow' : 'deep';
}

export const coverageLabel: Record<Coverage, { en: string; fr: string }> = {
  deep: { en: 'in depth', fr: 'en profondeur' },
  shallow: { en: 'shallow', fr: 'superficiel' },
};
