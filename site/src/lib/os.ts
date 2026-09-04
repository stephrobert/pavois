// The one place an OS id becomes a human label.
//
// Every page that showed a target used to hold its own list: the downloads page hardcoded seven
// (RHEL 10 had an OSCAL profile nobody linked), llms.txt hardcoded "8 Linux targets" while the base
// covered nine, and the rule fiches printed the raw id (`ubuntu2604`). A target must appear on the
// site by EXISTING in the rule base, not by someone remembering to add it in three files.
//
// The ids come from docs/reference/rules.yml (applicable_os); an unknown id falls back to itself,
// so a new target is never hidden: at worst it shows up unpolished.
export const OS_LABEL: Record<string, string> = {
  debian12: 'Debian 12',
  debian13: 'Debian 13',
  ubuntu2204: 'Ubuntu 22.04',
  ubuntu2404: 'Ubuntu 24.04',
  ubuntu2604: 'Ubuntu 26.04',
  rhel8: 'RHEL 8 / Rocky 8 / AlmaLinux 8',
  rhel9: 'RHEL 9 / Rocky 9 / AlmaLinux 9',
  rhel10: 'RHEL 10 / Rocky 10 / AlmaLinux 10',
  fedora: 'Fedora',
};

export const osLabel = (id: string): string => OS_LABEL[id] ?? id;
