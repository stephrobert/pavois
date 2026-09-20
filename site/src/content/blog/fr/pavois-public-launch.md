---
lang: fr
title: "De la première publication à une chaîne de livraison vérifiée"
description: "Pavois est public depuis le 16 septembre 2026. Les premières versions ont révélé un écart entre des tests lancés depuis le dépôt et l'artefact autonome livré sur une machine vierge. Voici ce que cet écart a changé dans la chaîne de livraison, et ce qui est désormais vérifié mécaniquement."
datePublished: "2026-09-18"
dateModified: "2026-09-18"
category: project
tags: ["pavois", "conformité", "durcissement", "open source", "CINC"]
keywords: ["scanner de conformité Linux", "configuration effective", "alternative OpenSCAP", "durcissement Linux", "lancement open source"]
featured: true
---

Le 16 septembre 2026, Pavois est passé de dépôt privé à projet public. C'est un **scanner de conformité Linux** qui audite la configuration **effective** d'une machine plutôt que ses fichiers de configuration, note de A à E par norme (ANSSI BP-028, CIS, PCI DSS, NIST, STIG), et sait appliquer puis **annuler** son propre durcissement. Ce billet raconte pourquoi il est resté privé si longtemps, ce que les premières 48 heures ont cassé, et ce que je veux en faire.

## Pourquoi c'est resté privé

Le code était prêt bien avant. Ce qui ne l'était pas, c'était moi. J'ai repoussé l'échéance un nombre de fois que je n'ai pas compté, et pour une raison simple : la peur du ridicule. Publier un outil de conformité, c'est s'exposer à ce que quelqu'un le lance sur sa machine et découvre que le verdict est faux. Dans ce domaine, **un outil qui se trompe est pire qu'inutile** : il délivre une fausse confiance, et une fausse confiance sur un serveur de production a un coût réel.

Ce raisonnement a une faille, et elle m'a coûté des mois : un outil qui reste privé ne se trompe jamais publiquement, mais il ne s'améliore pas non plus. Aucune quantité de tests écrits par la personne qui a écrit le code ne remplace un utilisateur qui ne sait pas ce qu'on attend de lui.

## Ce que les 48 premières heures ont prouvé

Cinq versions en trois jours. Ces cinq versions ne correspondent pas à cinq refontes du produit : elles retracent surtout la stabilisation de sa chaîne de livraison. Ce qui était en cause tenait en une phrase.

**v0.1.0 et v0.1.1 ont livré un binaire incapable de faire son travail.** Les deux fois pour la même raison : tous mes tests tournaient **dans le dépôt**, là où les profils de règles et la référence sont sur le disque. Le binaire publié, lui, arrive seul sur une machine neuve. Les deux fois, c'est un utilisateur sur une VM vierge qui l'a trouvé, pas moi. La v0.1.2 a fait pire dans un autre registre : trois répertoires embarqués vides, ce qui n'est **pas une erreur de compilation**. Ça compile, ça se publie, et le seul symptôme est une phrase que l'utilisateur découvre à la première commande : `this binary embeds none and none is on disk`.

La correction n'a pas été un correctif, ça a été une échelle de vérification dont chaque barreau attrape une classe d'erreurs que le précédent ne peut pas voir :

| barreau | ce qu'il attrape |
|---|---|
| `prepush` | tout ce qu'une PR refuserait, hors ligne |
| `release:standalone` | un chemin résolu contre le répertoire courant |
| `release:ci-build` | ce que construit la **release**, pas ce que je construis |
| `release:preflight` | le paquet, extrait et exécuté |
| `release:scenario` | le scénario complet sur une **VM vierge** |
| `release:published` | l'artefact que GitHub a **réellement** publié |

Le barreau du scénario porte **une assertion par issue de premier contact fermée**. Une issue fermée qui n'existe que dans un changelog revient ; une issue fermée qui a une ligne dans un harnais ne revient pas.

En trois jours, des inconnus ont trouvé ce que des mois de peur n'avaient pas permis de corriger. C'est l'argument le plus solide que je connaisse contre le fait de garder un projet privé.

## Ce que fait Pavois, en une idée

**On audite l'état résolu, pas les fichiers.** Un scanner qui lit `/etc/ssh/sshd_config` rate les `Include`, les drop-ins, et tout ce qu'un paquet de distribution ajoute par-dessus. Pavois demande au démon ce qu'il applique vraiment :

```bash
# ce que font la plupart des scanners
grep PermitRootLogin /etc/ssh/sshd_config

# ce que fait Pavois
sshd -T | grep permitrootlogin
```

Même principe partout : `sysctl -a` pour le noyau, `systemctl show` pour les unités, `nginx -T` et `apachectl -S` pour les serveurs web. C'est plus cher (il faut root, donc `--sudo`) et c'est la seule lecture qui décrit la machine telle qu'elle tourne.

```bash
pavois scan local --sudo          # note A à E + rapport HTML autoporté
pavois harden plan user@host --sudo --key ~/.ssh/id_ed25519
pavois harden apply plan.yml --reboot --scan   # un PASS après reboot est prouvé
```

## « J'ai déjà Ansible et un scanner. Pourquoi ajouter Pavois ? »

C'est la question que je me suis le plus souvent entendu poser, et la réponse honnête commence par ce que Pavois **ne** demande **pas**.

Votre gestion de configuration reste la source de l'état voulu. Ansible, Puppet ou Packer décrivent ce que la machine **devrait** être ; Pavois relit ce qu'elle a **réellement** résolu, ce qui n'est ni la même question ni la même réponse. Un playbook qui a convergé sans erreur ne dit pas qu'un drop-in ajouté ensuite n'a pas défait son travail.

Votre scanner de conformité peut rester en place. Le premier pas utile n'est pas un remplacement, c'est une comparaison : une seule image, les deux outils côte à côte, et on regarde ce que chacun a mesuré et avec quelle preuve. C'est peu coûteux, c'est réversible, et ça décide sur des faits plutôt que sur une promesse.

Ce que Pavois apporte de spécifique tient en trois choses : il lit l'état **effectif** plutôt que les fichiers, il dit si un PASS **survit au reboot**, et il produit une preuve exportable en OSCAL, SARIF ou JSON. Si ces trois-là ne vous manquent pas, gardez ce que vous avez.

## « Faut-il adopter plusieurs référentiels ? »

Non. C'est une confusion que le site entretenait, et elle méritait d'être corrigée.

Les correspondances multiples appartiennent au **corpus** de Pavois : un contrôle neutre porte tous ses mappings CIS, ANSSI BP-028, NIST, PCI DSS et STIG, ce qui évite d'écrire cinq fois la même vérification. C'est une propriété de la base de règles, pas une obligation pour vous.

Si votre organisation ne répond qu'à l'ANSSI, n'auditez que l'ANSSI :

```bash
pavois scan local --sudo --standard bp28
```

`--standard` filtre ce que le **moteur exécute**, pas l'affichage du rapport. Et `pavois harden apply` l'accepte aussi, pour les valeurs de remédiation qui diffèrent d'une norme à l'autre.

Une dernière précision qui compte : un mapping n'est pas une certification. Qu'un contrôle porte la référence CIS 5.2.1 signifie qu'il mesure ce que ce paragraphe demande, pas que votre machine est certifiée CIS. Pavois produit la preuve ; l'auditeur rend le verdict.

## Ce que je veux en faire

L'objectif n'est pas de multiplier les contrôles. C'est de faire de Pavois une **référence méthodologique opposable** : un outil dont on peut discuter les verdicts parce qu'ils sont motivés, sourcés et reproductibles.

**Un verdict qualifié plutôt qu'un feu vert.** Un PASS doit dire deux choses : le réglage est actif maintenant, et il survit au reboot. Ce sont deux axes indépendants, et la note en tient compte. C'est déjà en place, et [expliqué ici](/fr/handbook/qualified-verdict/).

**Trois états, pas deux.** ALLOWED, BLOCKED et **UNKNOWN**. Une absence de preuve n'est jamais une preuve d'absence. Un contrôle que Pavois ne peut pas mesurer doit dire qu'il ne peut pas le mesurer, et ce verdict ne doit pas compter comme une réussite. `UNKNOWN` vaut mieux qu'une fausse confiance, et c'est le chantier en cours.

**Dire ce qu'on ne sait pas corriger.** Un système de fichiers séparé se décide à l'installation, une option KSPP absente exige un noyau recompilé, un mot de passe GRUB peut vous verrouiller dehors. Ces trois classes ne se règlent pas par un `apply`, donc le rapport affiche **deux notes** : la note brute, et la posture remédiable, c'est-à-dire ce que Pavois peut atteindre par lui-même.

**Savoir revenir en arrière.** Parmi les outils qui remédient (OpenSCAP, l'USG d'Ubuntu, les CIS Build Kits, ansible-lockdown), aucun ne livre l'inverse de sa propre remédiation. Pavois le fait, à 96 % mesurés sur une Debian 12 neuve, et **publie les 4 % qui ne reviennent pas**, un par un. Un rollback n'est pas une opération neutre, et le manifeste le dit avant que vous ne confirmiez.

**Une sortie que d'autres outils peuvent lire.** Le référentiel s'exporte en OSCAL, les résultats en SARIF, JUnit, JSON et CSV. Une preuve de conformité qui ne sort pas de son propre outil n'est pas une preuve, c'est une capture d'écran.

## Ce qui n'est pas vrai aujourd'hui

Pavois couvre **neuf systèmes** Linux. **Deux** sont passés par la campagne complète sur VM vierge : Debian 12 et Debian 13. Les sept autres sont curatés et validés statiquement, mais aucune campagne n'a tourné dessus : traitez-les comme expérimentaux. « 9 systèmes supportés » et « 9 systèmes prouvés » ne sont pas la même phrase, et une seule des deux est vraie.

Il n'y a pas non plus d'agrégation de flotte. Un run audite une cible. Une boucle et un dossier de rapports suffisent, parce que chaque scan émet un JSON complet, mais c'est un manque assumé, pas une fonction cachée.

## À retenir

- Pavois est public depuis le 16 septembre 2026, sous licence Apache-2.0.
- Il audite la configuration **effective** (`sshd -T`, `sysctl`, `systemctl show`), pas les fichiers.
- L'écart qui comptait n'était pas dans les contrôles mais dans l'emballage : des tests lancés depuis le dépôt ne voient pas ce qu'un artefact autonome fait sur une machine vierge. Cinq versions en trois jours ont servi à fermer ce trou, et chaque barreau de l'échelle en est la trace.
- La direction : un verdict qualifié, trois états dont `UNKNOWN`, deux notes dont la posture remédiable, et un rollback qui publie ses propres limites.

## Prochaines étapes

- [Démarrer](/fr/start/) : du téléchargement vérifié au premier verdict.
- [Parcourir les contrôles](/fr/rules/) et leur type de preuve.
- [Comment la note est calculée](/fr/handbook/scoring-methodology/).
- Un bug, une machine qui réagit mal ? `pavois support` prépare le rapport, sans l'identité de votre machine.
- Pour le durcissement Linux au sens large, mes guides sur [blog.stephane-robert.info](https://blog.stephane-robert.info/docs/securiser/).
