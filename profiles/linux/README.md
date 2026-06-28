# profiles/linux/ — corpus multi-normes par OS (RENDU depuis la référence)

Chaque `<os>/controls/*.rb` est un **artefact rendu** depuis la référence pavois,
pas du code écrit à la main. **On ne l'édite jamais à la main** : on édite la
référence, puis on rend.

## Source de vérité
- `docs/reference/pavois-content/<os>.yml` — **la référence pavois** : une entrée
  par contrôle (check effectif + mappings de normes + niveaux + titre + sévérité +
  domaine). Pavois-owned, maintenue directement (SSG abandonné).
- `tools/render_reference.py` / `tools/render.sh` — rendent la référence → corpus.

Deux contrôles « identiques » diffèrent par leurs tags/valeurs selon l'OS, donc le
`.rb` reste par OS. La maintenance réelle = **la référence**, pas les milliers de
contrôles rendus.

## Rendre / valider
```bash
tools/render.sh <os>          # ex. tools/render.sh ubuntu2204
tools/render.sh               # tous les OS ayant une référence
tools/validate.sh             # intégrité + fidélité référence==corpus, ruby/cinc/go, note
```

## Ajouter un OS
1. créer `docs/reference/pavois-content/<os>.yml` (partir d'un OS proche, ajuster
   les contrôles/mappings/valeurs spécifiques) ;
2. `tools/render.sh <os>` ;
3. écrire `profiles/linux/<os>/inspec.yml` (copier un existant, ajuster `supports:`
   platform/release).

## Profils présents
| Profil | Cible | Famille |
|--------|-------|---------|
| `debian12` | Debian 12 | apt |
| `debian13` | Debian 13 | apt |
| `ubuntu2404` | Ubuntu 24.04 LTS | apt |
| `ubuntu2204` | Ubuntu 22.04 LTS | apt |
| `rhel9` | RHEL 9 / Rocky 9 | dnf |
| `rhel8` | RHEL 8 / Rocky 8 / AlmaLinux 8 | dnf |
| `almalinux9` | AlmaLinux 9 | dnf |
| `fedora` | Fedora courante (42/43) | dnf |

Les clones binaires de RHEL (Rocky, AlmaLinux 8) s'auditent avec le profil
`rhel8`/`rhel9` — pas de profil dupliqué. La détection d'OS (`cinc-auditor detect`)
choisit automatiquement le bon profil, avec repli sur la version mineure la plus
proche de la même famille.
