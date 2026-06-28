# Contribuer à pavois

pavois est un **scanner de conformité communautaire**. Le cœur du projet est sa
**bibliothèque de règles** : des contrôles InSpec qui auditent la **configuration
effective** d'un système (pas les fichiers), mappés aux normes (CIS, ANSSI BP-028,
STIG) et taggés par **niveau**. C'est là qu'on a besoin de la communauté.

Pourquoi pas OpenSCAP : oscap lit des fichiers de configuration fixes et **rate
les `Include`, les drop-ins et la config appliquée**. pavois interroge l'état
**résolu**. Une règle qui ne respecte pas ce principe n'a pas sa place ici.

## Une règle = un contrôle, N normes

Un même contrôle technique appartient souvent à plusieurs réglementations
(CIS, ANSSI BP-028, PCI-DSS, NIST…). On ne le duplique pas par norme : il porte
un **identifiant interne stable et neutre** (slug `domaine-objet`) et tous ses
**mappings normatifs en tags**. La « norme » est une *vue* : le rapport HTML
laisse choisir la réglementation et recompose chapitres et score (tout est
embarqué côté client).

```ruby
control "ssh-permitrootlogin" do        # ID pavois, neutre vis-à-vis des normes
  impact 1.0
  title "SSH : connexion root désactivée"
  desc  "Un drop-in dans sshd_config.d peut réactiver root ; on audite l'état " \
        "effectif via sshd -T, pas le fichier."
  tag domain: "SSH"          # chapitrage neutre (vue « Toutes » / ANSSI)
  tag cis:       "5.2.10"    # mappings de normes (autant que pertinent)
  tag bp28:      "R36"
  tag 'pci-dss': "2.2.4"
  tag ssg: "sshd_disable_root_login"   # traçabilité vers la source de référence

  describe command("sshd -T") do
    its("stdout") { should match(/^permitrootlogin no$/i) }
  end
end
```

**Aucune référence inventée** : les numéros de norme proviennent de la **référence
pavois** (`docs/reference/pavois-content/`), jamais de mémoire.

### Règles d'or

1. **Config effective, jamais le fichier** pour un service :
   `command("sshd -T")`, `command("sysctl -a")`, `command("systemctl show u")`,
   `command("nginx -T")`... Interdit : `file("/etc/ssh/sshd_config")` pour vérifier
   une directive de service.
2. **Métadonnées obligatoires** : `impact`, `title`, `desc`, `tag domain:`, et
   **au moins un mapping de norme** (`cis:`/`bp28:`/`pci-dss:`/`nist:`/`stig:`).
   Niveau **par norme** quand il existe (`tag level_bp28:` minimal..high,
   `tag level_cis:` 1/2) — il alimente le sélecteur de niveau (cumulatif) du
   rapport. Ces tags alimentent les vues, chapitres et filtres.
3. **Portabilité** : garder par `os.family` / `only_if` ce qui est spécifique à
   une distribution ou à un init (systemd vs OpenRC).
4. **Tester pour de vrai** avant la PR (conteneur jetable ou VM), pas en théorie.
5. **Versions épinglées** (`@sha256:` pour les images, tags pour les profils).

## Structure : corpus par domaine, normes en tags

On range les contrôles **par domaine technique**, pas par norme (la norme est une
vue, cf. ci-dessus) :

```text
profiles/linux/<cible>/
├── inspec.yml            # name, title, version, supports, input 'level'
└── controls/
    ├── services.rb       # un fichier par domaine (services, ssh, sysctl, comptes…)
    ├── ssh.rb
    └── sysctl.rb
```

Exemple en place : `profiles/linux/debian12/controls/services.rb` (famille de
services réseau hérités, mappée ANSSI R62 / CIS / PCI-DSS / NIST).

### La référence pavois (source des contrôles)

Tous les contrôles, mappings de normes, niveaux et valeurs vivent dans **la
référence pavois** : `docs/reference/pavois-content/<os>.yml` (une entrée par
contrôle : check effectif + normes + niveaux + titre + sévérité + domaine).
Elle est **pavois-owned** et maintenue directement — on ne mine plus le SSG.

Le corpus InSpec exécuté par le scanner est **rendu** depuis la référence :

```bash
tools/render.sh <os>      # docs/reference/pavois-content/<os>.yml -> profiles/linux/<os>/controls
tools/validate.sh         # intégrité + fidélité référence==corpus, ruby/cinc/go, note
```

Pour ajouter/modifier un contrôle : éditer son entrée dans la référence (check
**effectif** `kernel_parameter`/`sshd -T`, mappings de normes, niveau), puis
`tools/render.sh <os>`. Le `describe` effectif reste relu/validé domaine par domaine.

## Tester sa contribution

```bash
bin/pavois scan pavois@<ip> --key ~/.ssh/id_ed25519 --sudo \
  --profile profiles/linux/debian12
bin/pavois serve                                 # rapport multi-normes
```

Dans le rapport : changer la **réglementation** dans la liste ; le contrôle doit
apparaître dans le **bon chapitre** de chaque norme où il est mappé, avec sa
**sévérité**, ses **mappings**, et le **détail** (vérification effective) au clic.
Le `--sudo` est requis dès qu'un contrôle interroge un service (`sshd -T`…).

## Checklist de PR

- [ ] Audit de la config **effective** (pas de lecture de fichier de service).
- [ ] ID slug neutre, `impact`, `title`, `desc`, `tag domain:`, ≥ 1 mapping de norme.
- [ ] Numéros de norme **sourcés** (référence pavois `docs/reference/pavois-content/`), pas de mémoire.
- [ ] Testé sur une cible réelle (préciser laquelle).
- [ ] Portabilité gardée (`os.family` / `only_if`) si nécessaire.
- [ ] Pas de secret en dur ; versions épinglées.
