# pavois

**Scanner de conformité « batteries incluses », au-dessus de CINC Auditor.**

`pavois` vise la simplicité d'usage de **Lynis** et la rigueur profil-driven
d'**OpenSCAP**, sans leurs angles morts : il audite la **configuration effective**
(pas seulement les fichiers), fonctionne sur **conteneurs ET VM**, et produit des
**rapports** exploitables. CINC Auditor (le build open source de Chef InSpec)
fait le moteur ; pavois fournit la couche **outil prêt à l'emploi**.

> Nom de travail (`pavois`), à rebrander.

## Pourquoi, face à oscap / lynis

| | OpenSCAP | Lynis | **pavois** (CINC) |
|---|---|---|---|
| Pilotage | profils SCAP/XCCDF | scripts intégrés | **profils as code** (InSpec) |
| Config **effective** (drop-ins, `Include`) | ❌ lit les fichiers | ~ partiel | ✅ `sshd -T`, `sysctl`, `systemctl show` |
| Cibles | hôte | hôte | **conteneur + VM (ssh) + hôte** |
| Sans agent | oui | oui | **oui** (rien à installer sur la cible) |
| Rapport | HTML riche | rapport + score | **HTML chapitré par norme** : score, sévérité, filtres, détail par règle + **JSON** (CI) |
| Prise en main | lourde | simple | **une commande** |

L'angle différenciant assumé : **on audite ce qui tourne, pas ce qui est écrit.**
Un `/etc/ssh/sshd_config` « conforme » surchargé par un drop-in est un faux
négatif classique d'OpenSCAP ; pavois le détecte (profil `effective-config`).

## Prérequis

- **CINC Auditor** en natif (`cinc-auditor`, installé via omnitruck.cinc.sh) —
  comme oscap/lynis, un binaire natif. C'est le mode recommandé : il réutilise
  ton `~/.ssh/config`, ton routage et ton user.
- **Docker** sert seulement de **repli zéro-install** (`--engine docker`) pour
  scanner un conteneur sans rien installer. Il **ne peut pas** auditer l'hôte
  courant (`local`) ni profiter du ssh_config.

Rien à installer **sur la cible** : pavois est sans agent.

## Usage

```bash
# Lister les profils embarqués (et le moteur natif détecté)
bin/pavois profiles

# Scanner l'hôte courant (natif obligatoire) — profil par-OS auto-détecté
bin/pavois scan local --sudo

# Scanner un conteneur (OS détecté, profil choisi tout seul)
bin/pavois scan mon-conteneur

# Scanner une VM / un serveur (transport SSH, ssh_config natif)
bin/pavois scan audit@10.0.0.12 --sudo
```

Sortie : rapport **CLI** + `reports/rapport-<machine>-<transport>-<horodatage>.{html,json}`.

## Profils (sélection par OS, automatique)

Il n'y a **pas de nom de profil à retenir** : Pavois interroge l'OS de la cible
(`cinc detect`, tout transport) et choisit le corpus correspondant sous
`profiles/linux/<os>` (Debian 12/13, Ubuntu 22.04/24.04, RHEL 8/9, AlmaLinux 9,
Fedora), avec repli au plus proche de la même famille si la version exacte n'est
pas embarquée. On ne passe `--profile <chemin|url>` que pour un **profil perso**.

## Architecture

```text
pavois (CLI Python)
   │  choisit le moteur (natif d'abord, docker en repli) et le transport
   │  (local:// | ssh:// | docker://), résout profil + sortie
   ▼
CINC Auditor (binaire natif ; conteneur épinglé par digest en repli)
   │  exécute les contrôles InSpec sur la cible
   ▼
rapports : CLI + HTML chapitré + JSON
```

`--engine auto` (défaut) = natif si `cinc-auditor`/`inspec` est présent, sinon
docker. La cible `local` impose le natif (un conteneur s'auditerait lui-même).

## Pas d'OpenSCAP sous le capot

pavois **n'embarque pas oscap**. oscap lit des fichiers fixes et rate les
`Include`, drop-ins et la config appliquée : l'utiliser comme moteur trahirait
l'angle du projet. pavois est **100% CINC/InSpec** et porte **ses propres
règles**.

## Gate CI

Filtrer une norme + niveau, exporter pour la CI et bloquer sous un seuil :

```bash
bin/pavois scan pavois@10.0.0.12 --key ~/.ssh/id_ed25519 --sudo \
  --profile profiles/linux/debian12 \
  --standard cis --level 1 --fail-under 80 \
  --junit reports/ci.xml --csv reports/ci.csv
# code de sortie 2 si conformité < 80 % (échec de pipeline), 0 sinon
```

## Workflow de la norme : de l'édition à la publication

La baseline pavois est une **norme versionnée** (`pavois-baseline`) dont la
**source unique** est `docs/reference/rules.yml` — un contrôle par id neutre,
champs partagés écrits une fois + valeurs keyées `@os` là où elles diffèrent. Le
cycle complet, de l'édition à la publication :

1. **Éditer la source** — `docs/reference/rules.yml`, un seul endroit : contrôle
   (titre, domaine, sévérité), mappings de normes (`cis`/`bp28`/`nist`/`pci-dss`/
   `stig`), niveaux, remédiation. Pour les checks récurrents, on pose un
   **template** (`template: {name: sysctl, key: …, value: …}`) plutôt qu'un check
   verbatim — 7 templates couvrent 55 % des contrôles.

2. **Générer les 8 fichiers OS** — `mise run gen`
   (rules.yml → `docs/reference/pavois-content/<os>.yml`, artefacts dérivés).

3. **Vérifier la cohérence** — `mise run gen:verify`
   (les 8 fichiers == render(rules.yml) ; garde-fou CI, doit rester à 100 %).

4. **Rendre le corpus InSpec** — `tools/render.sh`
   (les 8 fichiers → `profiles/linux/<os>/controls/*.rb`).

5. **Valider les mappings** (recoupement multi-sources) — `mise run validate`
   (CIS vs SSG / ansible-lockdown), `mise run validate:bp28` (ANSSI v2.0),
   `mise run validate:mappings` (NIST + PCI vs ciso-assistant).

6. **Tester en réel** — `pavois scan <cible> --profile …` (audit de la config
   effective ; jamais commiter sans avoir scané). Remédiation :
   `pavois harden plan|apply|verify`.

7. **Versionner la norme** — bump `version` dans `docs/reference/baseline.yml`
   (semver : MAJOR = ids retirés, MINOR = contrôles/mappings ajoutés, PATCH =
   corrections) + une entrée dans `CHANGELOG.md`.

8. **Publier** :
   - **OSCAL** — `mise run oscal` (`pavois oscal --out oscal/`) : catalogue +
     8 profils par OS, consommables par tout outil GRC/OSCAL (ciso-assistant).
   - **API** — `pavois norms` (catalogue + couverture live), `pavois rules`
     (base de règles JSON), `pavois oscal` (le standard).
   - **Site** — `mise run site:build` : une fiche par contrôle (bandeau
     *crosswalk* « 1 check effective = N normes » + tampon de version) et une
     page par norme. Fiches enrichies via `tools/generate_rule_pages.py`.

> **Règle d'or** : on édite **`rules.yml`**, jamais les 8 fichiers OS (générés)
> ni le corpus `.rb` (rendu). `gen:verify` casse la CI si la source diverge.

## Roadmap

- [x] **Bibliothèque de règles multi-normes** : 8 OS (~380–720 contrôles chacun),
      ~30 domaines, config effective, mappés CIS / ANSSI BP-028 / PCI-DSS / NIST /
      STIG, taggés par niveau. Source : la **référence pavois**
      (`docs/reference/pavois-content/`, voir `CONTRIBUTING.md`).
- [x] **Sélection norme + niveau** : vues du rapport HTML + gate CI
      (`--standard cis --level 1`).
- [x] **Intégration CI** : code de sortie (`--fail-under`) + exports JUnit / CSV.
- [ ] **Domaines restants** : permissions de fichiers, comptes/PAM, audit.
- [ ] **Score de durcissement** synthétique (façon « hardening index » de Lynis).
- [ ] **WinRM** (Windows), auth SSH par bastion.

## Statut

Fonctionnel : CLI Python (`scan`/`profiles`/`serve`), natif-first (cinc-auditor)
avec repli docker, cibles **local / ssh / docker**, **rapport HTML chapitré par
norme** (caractéristiques, score, sévérité, filtres, détail par règle) + JSON,
nommage `rapport-<machine>-<transport>-<horodatage>`. Validé sur master1 et Docker.

## Licence & attributions

pavois est sous **Apache License 2.0** (voir [`LICENSE`](LICENSE)).

La base de contrôles dérive de **ComplianceAsCode/SSG** (BSD-3-Clause) et est
recoupée avec **ansible-lockdown** (MIT) — voir [`THIRD_PARTY.md`](THIRD_PARTY.md)
pour les attributions et textes de licence complets. pavois ne mappe que les
**numéros de référence** des normes (faits) ; il ne reproduit pas le texte des
documents CIS/PCI. **CIS Benchmarks**, **PCI DSS**, **STIG** et **NIST** sont des
marques de leurs détenteurs ; pavois n'est ni affilié ni approuvé par eux. Le
contenu NIST/STIG est du domaine public US. L'outillage `tools/norm_studio/`
interroge **intuitem/ciso-assistant** (AGPL-3.0) **au build uniquement** — jamais
embarqué dans le binaire ni le site.
