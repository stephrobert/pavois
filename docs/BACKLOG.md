# Backlog pavois — pistes à traiter

Idées issues de l'analyse d'outils open source de référence (gardés en
référence locale, hors dépôt).

## 1. Axe « posture / durcissement » (index de durcissement synthétique)

Un audit de durcissement de référence couvre des domaines **que le SSG ne
sélectionne pas** et **sans numéro de norme** → ils n'augmentent pas le % de
conformité, mais formalisent une **posture de durcissement** complémentaire.

Domaines à ajouter (mécanisme effectif déjà identifié) :

| Domaine | Sonde effective |
|---|---|
| Pare-feu actif | `nft list ruleset` / `firewall-cmd --state` / iptables chargé |
| Synchro temps | `timedatectl` (NTPSynchronized) / `chronyc tracking` |
| Intégrité fichiers | AIDE/tripwire installé + base initialisée |
| Certificats | `openssl x509 -checkend` (expiration) |
| Anti-malware | présence d'un scanner (clamav, rkhunter) |
| Homedirs / bannières | perms des homedirs, `/etc/issue(.net)` |

Livrable visé : un **domaine « Durcissement »** + un **score de posture**
synthétique, affiché à côté du score de conformité par norme.

## 2. Pousser encore le % des normes (SSG)

Mécanismes **confirmés par des baselines InSpec de référence** (
contrôles InSpec, Apache) — directement transposables :

- **`file_permissions`/`owner` à boucle** (var/log, cron.d) : générer un contrôle
  InSpec **dynamique** qui itère le `find` au runtime, puis applique nos bits
  interdits. Exemple :
  ```ruby
  command('find /var/log -type f').stdout.split.each do |f|
    describe file(f) do
      it { should_not be_writable.by 'group' }
      it { should_not be_readable.by 'other' }
    end
  end
  ```
- **`audit_rules` par syscall** : construire la ligne attendue
  dynamiquement (ex. `find / -perm -4000` → `-a always,exit -F path=… -F perm=x …`)
  et la matche. Plus précis que notre match par clé. NB : pavois garde `auditctl
  -l` (chargé) au lieu de lire `/etc/audit/audit.rules` (plus effectif).
- **ssh crypto** : listes d'algos valides (ciphers/macs/kex)
  comparées à `sshd -T` — mais SANS mapping ANSSI/CIS dans le SSG (cf. discussion
  SSH). Utile pour l'axe posture.
- `grub2` mot de passe, `sudoers` Defaults, `selinux`/`sebool` (RHEL).

## 3. Autres outils à analyser
- Baselines InSpec de référence — contrôles directement comparables.
- Benchmarks conteneurs/Kubernetes — si cibles concernées.
