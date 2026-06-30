---
lang: fr
title: "Conformité reboot-proof : ce qu'un PASS Linux prouve vraiment"
description: "Un feu vert n'est pas binaire. Pavois note désormais si un PASS survit au reboot, pour qu'un A net n'aille qu'à un hôte durci ET reboot-proof, pas seulement actif à l'instant T."
datePublished: "2026-06-28"
dateModified: "2026-06-28"
category: methodology
tags: ["conformité", "durcissement", "sysctl", "auditd", "CINC"]
keywords: ["reboot-proof", "configuration effective", "runtime vs persistance", "durcissement Linux", "score de conformité"]
featured: true
---

Un contrôle qui passe devrait dire deux choses, pas une : que le réglage est **actif maintenant**, et qu'il **survit au reboot**. La plupart des scanners ne prouvent que la première. Pavois prouve désormais les deux, et sa note A à E reflète l'écart. Un PASS runtime-only (une valeur `sysctl` vivante non épinglée sur disque) ne décroche plus un **A** net : la note est plafonnée et marquée **runtime-qualifiée** tant que la persistance n'est pas prouvée. Cet article explique pourquoi cette distinction compte et comment Pavois la mesure.

## Le piège : runtime n'est pas persistance

`sysctl net.ipv4.conf.all.rp_filter` peut renvoyer `1` à l'instant parce que quelqu'un a lancé `sysctl -w` après le démarrage. Rien dans `/etc/sysctl.d` ne l'épingle. Le contrôle passe aujourd'hui et **régresse au prochain reboot**. Un scanner qui rapporte un PASS plat cache ce risque derrière un feu vert. La réponse honnête est : actif oui, survie au reboot inconnue.

Pavois sépare le verdict en deux axes indépendants. Le **type de preuve** dit ce que le check lit (l'état résolu en cours d'exécution, un fichier de config persistant, l'inventaire de paquets, des métadonnées de fichier). La **survie au reboot** dit si un PASS prouve un état durable. Les deux sont indépendants : la `kconfig` compilée d'un noyau est une lecture runtime mais reboot-proof, alors qu'une option de montage vivante peut ne pas l'être.

## Comment Pavois prouve la persistance

Partout où il existe une source de vérité propre, le check vérifie à la fois la valeur vivante et son ancrage persistant :

- **sysctl** vérifie la valeur vivante avec `kernel_parameter` **et** qu'elle est épinglée dans un fichier sous `/etc/sysctl.d`.
- **options de montage** vérifient l'option active **et** une entrée dans `/etc/fstab` ou une unité systemd `.mount`.
- **ligne de commande noyau** vérifie `/proc/cmdline` **et** le paramètre dans la config du bootloader.
- **règles audit** vérifient que la règle est chargée via `auditctl -l` **et** présente dans `/etc/audit/rules.d`.

Vérifie-le sur une cible :

```bash
pavois harden plan user@host --sudo
# passe quelques contrôles à apply: true, puis converge et re-scanne
pavois harden apply hardening-plan.yml --reboot --scan
```

Avec `--reboot`, Pavois converge les correctifs, redémarre l'hôte, attend son retour, et re-scanne. Un contrôle qui passe dans ce rapport est **reboot-proven** : il a survécu à un vrai démarrage, pas seulement à une écriture vivante.

## À retenir

- Un PASS indique désormais **actif maintenant** versus **survit au reboot**, sur la fiche, dans le rapport, dans l'export JSON et le catalogue OSCAL.
- Une note n'atteint un **A** net que si les contrôles conformes prouvent la persistance, pas seulement l'état vivant.
- `pavois harden apply --reboot --scan` transforme cette affirmation en résultat empirique, reboot-proven.

## Prochaines étapes

- Lis la méthode : [le verdict qualifié](/fr/handbook/qualified-verdict/) et [comment la note est calculée](/fr/handbook/scoring-methodology/).
- Parcours les contrôles et leur type de preuve dans l'[explorateur de contrôles](/fr/rules/).
- Approfondis le durcissement Linux avec les guides de l'auteur sur [blog.stephane-robert.info](https://blog.stephane-robert.info/docs/securiser/).
