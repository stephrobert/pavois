# Gabarit de contrôle pavois. Copier, adapter, puis tester sur une cible réelle.
# Règle d'or : auditer la config EFFECTIVE (état résolu), jamais le fichier.

level = input("level", value: 1)

control "norme-x.y-identifiant-court" do
  impact 1.0                       # 0.7+ haute, 0.4-0.7 moyenne, <0.4 basse
  title "Intitulé clair et actionnable"
  desc  "Pourquoi cette règle, et pourquoi on lit l'état effectif et non le fichier."

  tag section: "Chapitre de la norme"   # -> regroupement dans le rapport
  tag cis: "x.y.z"                       # ou tag bp28: "..." / tag stig: "..."
  tag level: 1
  ref  "Référence de la norme (CIS / ANSSI BP-028 / STIG)"

  only_if("ne s'applique qu'au niveau demandé") { level.to_i >= 1 }

  # Exemple : état SSH effectif (résout Include + drop-ins), pas le fichier.
  describe command("sshd -T") do
    its("stdout") { should match(/^permitrootlogin no$/i) }
  end
end
