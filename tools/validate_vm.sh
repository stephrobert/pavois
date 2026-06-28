#!/usr/bin/env bash
# Tier VM de validation — la garantie SÉMANTIQUE (nécessite Incus + la flotte).
#
#   L5 EXÉCUTION : scan réel d'une VM -> 0 erreur d'exécution InSpec (aucun
#                  backtrace ruby / undefined method ; les échecs de contrôle
#                  sont normaux).
#   L6 ROUND-TRIP EFFECTIF : on applique une valeur en EFFECTIF (sysctl -w, SANS
#                  toucher au moindre fichier) sur un contrôle en échec, puis on
#                  re-scanne : il DOIT basculer en succès. Cela prouve que pavois
#                  lit la config appliquée (un audit fichier resterait en échec).
#                  Protégé par snapshot Incus (restauration garantie).
#
# Usage : tools/validate_vm.sh <incus-vm> <profile> [--roundtrip]
#   ex.  : tools/validate_vm.sh pavois-debian profiles/linux/debian12 --roundtrip
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
vm="${1:?usage: validate_vm.sh <incus-vm> <profile> [--roundtrip]}"
profile="${2:?profil requis}"
roundtrip=0; [ "${3:-}" = "--roundtrip" ] && roundtrip=1
key="$HOME/.ssh/id_ed25519"; user="pavois"
fail=0
ok(){ printf '  \033[32m✔\033[0m %s\n' "$1"; }
ko(){ printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }

command -v incus >/dev/null || { echo "incus requis"; exit 2; }
ip="$(incus list "$vm" -f csv -c 4 2>/dev/null | head -1 | awk '{print $1}')"
[ -n "$ip" ] || { echo "VM '$vm' sans IPv4 (démarrée ?)"; exit 2; }

# scan live -> pavois écrit le rapport InSpec JSON dans reports/ (le -f json
# live est pollué par la sortie de cinc ; on lit donc le fichier de rapport).
slug="$(echo "$ip" | tr . -)"
run_scan(){ CHEF_LICENSE=accept-silent bin/pavois scan "$user@$ip" --key "$key" --sudo \
              --profile "$profile" >/dev/null 2>&1; }
latest_report(){ ls -t "reports/rapport-$slug-ssh-"*.json 2>/dev/null | head -1; }

# ── L5 — exécution ─────────────────────────────────────────────────────────
echo "L5 — exécution réelle ($vm @ $ip)"
run_scan
rep="$(latest_report)"
if [ -z "$rep" ]; then ko "aucun rapport produit (scan échoué)"; else
  python3 - "$rep" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
sig = ("undefined method", "NoMethodError", "uninitialized constant",
       "execution expired", "wrong number of arguments", "stack backtrace",
       "Errno::", "can't modify")
results = [(c.get("id"), r) for p in d.get("profiles", []) for c in p.get("controls", [])
           for r in c.get("results", [])]
errs = [(cid, r) for cid, r in results
        if any(s in (r.get("message") or "") for s in sig)]
print(f"  {len(d.get('profiles',[{}])[0].get('controls',[]))} contrôles, "
      f"{len(results)} résultats, {len(errs)} erreur(s) d'exécution")
for cid, r in errs[:5]:
    print(f"    ✗ {cid}: {(r.get('message') or '')[:90]}")
sys.exit(1 if errs else 0)
PY
  [ $? -eq 0 ] && ok "0 erreur d'exécution" || ko "erreurs d'exécution"
fi

# ── L6 — round-trip effectif (sysctl -w, sans fichier) ─────────────────────
if [ "$roundtrip" = 1 ]; then
  echo "L6 — round-trip effectif (preuve config appliquée)"
  # choisir un contrôle sysctl EN ÉCHEC + sa clé/valeur cible (depuis le rapport)
  probe="$(python3 - "$rep" <<'PY'
import json, sys, re
d = json.load(open(sys.argv[1]))
for p in d.get("profiles", []):
  for c in p.get("controls", []):
    if not (c.get("id") or "").startswith("sysctl-"):
      continue
    for r in c.get("results", []):
      if r.get("status") == "failed":
        m = re.search(r"Kernel Parameter (\S+) value is expected to cmp == (\S+)",
                      r.get("code_desc") or "")
        if m:
          print(f"{c['id']}\t{m.group(1)}\t{m.group(2)}"); sys.exit(0)
PY
)"
  if [ -z "$probe" ]; then
    echo "  (aucun contrôle sysctl en échec exploitable — round-trip sauté)"
  else
    cid="$(echo "$probe" | cut -f1)"; pkey="$(echo "$probe" | cut -f2)"; pval="$(echo "$probe" | cut -f3)"
    echo "  sonde : $cid  ($pkey -> $pval)"
    snap="validate-rt-$$"
    incus snapshot create "$vm" "$snap" >/dev/null 2>&1 || true
    # appliquer en EFFECTIF uniquement (sysctl -w) — aucun fichier modifié
    incus exec "$vm" -- sysctl -w "$pkey=$pval" >/dev/null 2>&1
    run_scan; rep2="$(latest_report)"
    after="$(python3 - "$rep2" "$cid" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); cid = sys.argv[2]
st = "pass"
for p in d.get("profiles", []):
  for c in p.get("controls", []):
    if c.get("id") == cid:
      st = "fail" if any(r.get("status") == "failed" for r in c.get("results", [])) else "pass"
print(st)
PY
)"
    incus snapshot restore "$vm" "$snap" >/dev/null 2>&1 || true
    incus snapshot delete "$vm" "$snap" >/dev/null 2>&1 || true
    if [ "$after" = "pass" ]; then
      ok "$cid bascule fail->pass après sysctl -w (pavois lit l'EFFECTIF, pas le fichier)"
    else
      ko "$cid reste en échec après application effective (faux négatif ?)"
    fi
  fi
fi

echo
[ "$fail" = 0 ] && printf '\033[32mTIER VM OK\033[0m\n' || printf '\033[31m%d gate(s) en échec\033[0m\n' "$fail"
exit $((fail > 0 ? 1 : 0))
