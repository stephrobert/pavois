import type { Lang } from '../i18n/ui';

/**
 * Evidence type: what a check actually proves, and the reserve that comes with it.
 *
 * This is the keystone of the project's honesty about "effective configuration". Pavois reads the
 * resolved running state wherever a service exposes one, and says so; where it cannot, it says
 * that too rather than letting the headline claim cover everything.
 *
 * It lived inside the fiche template, which was fine while the fiche was the only page that needed
 * it. The domain hubs state which evidence types a domain's checks gather, so the map moved here:
 * one definition, two readers, no chance of a hub and a fiche describing `effective-runtime`
 * differently.
 */
export type EvidenceType =
  | 'effective-runtime'
  | 'persistent-config'
  | 'inventory-state'
  | 'filesystem-state'
  | 'manual'
  | 'behavioral';

export const EVIDENCE: Record<EvidenceType, { label: Record<Lang, string>; blurb: Record<Lang, string> }> = {
  'effective-runtime': {
    label: { en: 'effective runtime', fr: 'runtime effectif' },
    blurb: {
      en: 'Checked against the resolved running state (e.g. sshd -T, sysctl, systemctl show), catches drop-ins and Includes a file read would miss. Caveat: runtime ≠ persistence; a value correct now may not survive a reboot.',
      fr: 'Vérifié sur l’état résolu en cours d’exécution (ex. sshd -T, sysctl, systemctl show), attrape les drop-ins et Include qu’une lecture de fichier raterait. Réserve : runtime ≠ persistance ; une valeur correcte maintenant peut ne pas survivre à un redémarrage.',
    },
  },
  'persistent-config': {
    label: { en: 'persistent config', fr: 'config persistante' },
    blurb: {
      en: 'Checked against the content of a persistent configuration file, the source of truth that survives reboots.',
      fr: 'Vérifié sur le contenu d’un fichier de configuration persistant, la source de vérité qui survit aux redémarrages.',
    },
  },
  'inventory-state': {
    label: { en: 'inventory state', fr: 'état d’inventaire' },
    blurb: {
      en: 'Checked against what is installed or registered, packages present/absent, account databases.',
      fr: 'Vérifié sur ce qui est installé ou enregistré, paquets présents/absents, bases de comptes.',
    },
  },
  'filesystem-state': {
    label: { en: 'filesystem state', fr: 'état du système de fichiers' },
    blurb: {
      en: 'Checked against a path’s metadata, mode, owner, group, SUID/SGID.',
      fr: 'Vérifié sur les métadonnées d’un chemin, mode, propriétaire, groupe, SUID/SGID.',
    },
  },
  manual: {
    label: { en: 'manual', fr: 'manuel' },
    blurb: {
      en: 'No machine check, requires human judgement and business context.',
      fr: 'Pas de vérification automatique, jugement humain et contexte métier requis.',
    },
  },
  behavioral: {
    label: { en: 'behavioral', fr: 'comportemental' },
    blurb: {
      en: 'Verified by actively attempting a forbidden action.',
      fr: 'Vérifié en tentant réellement une action interdite.',
    },
  },
};

/** The display label of an evidence type, falling back to the raw key for an unmapped one. */
export const evidenceLabel = (key: string, lang: Lang): string =>
  EVIDENCE[key as EvidenceType]?.label[lang] ?? key;
