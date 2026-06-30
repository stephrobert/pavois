// French display labels for control domains. The English domain string stays the canonical
// identifier (filter values, data-domain attributes, search keys, sort); only the *display* is
// translated on FR pages, via domainLabel(). Keep keys in sync with the `domain` field in
// site/src/content/rules/*.json.
export const domainFr: Record<string, string> = {
  Accounts: 'Comptes',
  'Accounts (PAM modules)': 'Comptes (modules PAM)',
  'Accounts (faillock)': 'Comptes (faillock)',
  'Accounts (home dirs)': 'Comptes (répertoires personnels)',
  'Accounts (login.defs)': 'Comptes (login.defs)',
  'Accounts (password history)': 'Comptes (historique des mots de passe)',
  'Accounts (root PATH)': 'Comptes (PATH de root)',
  'Accounts (umask)': 'Comptes (umask)',
  'Audit (auditd daemon)': 'Audit (démon auditd)',
  'Audit (auditd)': 'Audit (auditd)',
  Banners: 'Bannières',
  'Bootloader (grub)': "Chargeur d'amorçage (grub)",
  'Cron/at access control': "Contrôle d'accès cron/at",
  'File ownership': 'Propriété des fichiers',
  'File permissions': 'Permissions des fichiers',
  'Filesystem (scan)': 'Système de fichiers (scan)',
  Firewall: 'Pare-feu',
  'GNOME desktop (dconf)': 'Bureau GNOME (dconf)',
  'Hardening (misc)': 'Durcissement (divers)',
  'Hardening (posture)': 'Durcissement (posture)',
  'Kernel & network (sysctl)': 'Noyau & réseau (sysctl)',
  'Kernel build': 'Compilation du noyau',
  'Kernel command line': 'Ligne de commande du noyau',
  'Kernel modules': 'Modules du noyau',
  Logging: 'Journalisation',
  'Logging (journald)': 'Journalisation (journald)',
  Mounts: 'Montages',
  Packages: 'Paquets',
  'Passwords (pwquality)': 'Mots de passe (pwquality)',
  SSH: 'SSH',
  Sudo: 'Sudo',
  'Time synchronization': 'Synchronisation du temps',
  'systemd services': 'Services systemd',
};

export function domainLabel(domain: string, lang: string): string {
  return lang === 'fr' ? (domainFr[domain] ?? domain) : domain;
}
