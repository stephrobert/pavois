
var LABELS={bp28:"ANSSI BP-028",cis:"CIS",'pci-dss':"PCI-DSS",nist:"NIST 800-171",stig:"STIG",posture:"Posture"};
// Type de preuve : ce que le check démontre réellement (honnêteté sur « effectif » ≠ universel).
var EVIDENCE={
  'effective-runtime':{l:"Runtime effectif",n:"Vérifié sur l'état résolu en cours d'exécution (sshd -T, sysctl, systemctl show…) — attrape drop-ins et Include. Réserve : runtime ≠ persistance ; une valeur correcte maintenant peut ne pas survivre à un redémarrage."},
  'persistent-config':{l:"Config persistante",n:"Vérifié sur le contenu d'un fichier de configuration persistant — la source de vérité au fil des redémarrages."},
  'inventory-state':{l:"État d'inventaire",n:"Vérifié sur ce qui est installé ou enregistré (paquets présents/absents, bases de comptes)."},
  'filesystem-state':{l:"État du système de fichiers",n:"Vérifié sur les métadonnées d'un chemin (mode, propriétaire, groupe, SUID/SGID)."},
  'manual':{l:"Manuel",n:"Pas de vérification automatique — jugement humain et contexte métier requis."},
  'behavioral':{l:"Comportemental",n:"Vérifié en tentant réellement une action interdite."}
};
var HIER={cis:1,'pci-dss':1,nist:1,stig:1};
var LEVEL_ORDER={bp28:["minimal","intermediary","enhanced","high"],cis:["1","2"]};
var LEVEL_LABEL={minimal:"minimal",intermediary:"intermédiaire",enhanced:"renforcé",high:"élevé","1":"niveau 1","2":"niveau 2"};
var BADGE={passed:'<span class="b ok">PASS</span>',failed:'<span class="b ko">FAIL</span>',
           skipped:'<span class="b sk">N/A</span>',empty:'<span class="b sk">-</span>'};
var SEVCLS={critique:'c',haute:'h',moyenne:'m',basse:'b'};
function sevBadge(s){return '<span class="sv '+(SEVCLS[s]||'b')+'">'+s+'</span>';}
// Note A->E façon Plumber : poids par sévérité, malus critique (plafond 30 -> E).
// Sévérité = échelle RÉELLE des normes (3 niveaux : haute/moyenne/basse). Le SSG
// ne classe pas en « Critical » et les normes ne surchargent pas la sévérité ;
// on note donc sur 3 tiers, sans rang fantôme.
var GW={critique:25,haute:15,moyenne:6,basse:3};
var GCAP={critique:Infinity,haute:60,moyenne:20,basse:10};   // plafond de perte par sévérité
var GBAND={A:'Excellent',B:'Bon',C:'Moyen',D:'Faible',E:'Critique'};
// PASSED : ensemble GLOBAL des contrôles qui passent (toutes vues), pour résoudre les
// compagnons persistants indépendamment du filtre norme/niveau. Miroir de la pré-passe Go.
var PASSED={};
(typeof CFDATA!=='undefined'?CFDATA:[]).forEach(function(c){ if(c.status==='passed')PASSED[c.id]=true; });
// fullPass : un PASS compte-t-il comme PLEIN ? Le tag reboot (axe persistance) prime ; sinon on
// se rabat sur le type de preuve. Un contrôle live redevient plein si son compagnon passe.
// Miroir exact de audit.fullPassFor côté Go (source unique de la politique).
function fullPass(c){
  if(c.reboot==='yes')return true;
  if(c.reboot==='no'||c.reboot==='unknown')return !!(c.companion&&PASSED[c.companion]);
  return c.evidence==='persistent-config'||c.evidence==='inventory-state'||c.evidence==='filesystem-state';
}
function grade(set){
  // On part de 100 et on RETRANCHE poids x nombre d'ÉCHECS, plafonné par
  // sévérité. >= 1 critique -> plafond 30 (malus de risque, bande E).
  var counts={critique:0,haute:0,moyenne:0,basse:0},qualified=0;
  set.forEach(function(c){
    if(c.status==='failed')counts[c.sev]++;
    else if(c.status==='passed'&&!fullPass(c))qualified++; // PASS runtime-only sans compagnon
  });
  var loss=Math.min(GW.critique*counts.critique,GCAP.critique)
          +Math.min(GW.haute*counts.haute,GCAP.haute)
          +Math.min(GW.moyenne*counts.moyenne,GCAP.moyenne)
          +Math.min(GW.basse*counts.basse,GCAP.basse);
  var fin=Math.max(0,Math.round(100-loss));
  if(counts.critique>0&&fin>30)fin=30;
  var L=fin>=90?'A':fin>=71?'B':fin>=51?'C':fin>=31?'D':'E';
  // Plafond du verdict qualifié : un A ne se gagne pas sur des PASS runtime-only à
  // persistance non prouvée. Les points sont inchangés — seule la lettre est plafonnée.
  var rq=qualified>0;
  if(rq&&L==='A')L='B';
  return {letter:L,final:fin,counts:counts,qualified:qualified,rq:rq};
}
function esc(s){return (s==null?'':''+s).replace(/[&<>"]/g,function(c){
  return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
function applicable(c,norm){return norm==='all'||(c.norms&&c.norms[norm]!=null);}
function inLevel(c,norm,lvl){
  if(lvl==='all')return true;
  var order=LEVEL_ORDER[norm];if(!order)return true;
  var cl=c.levels&&c.levels[norm];if(cl==null)return true;// pas de niveau = inclus
  return order.indexOf(cl)<=order.indexOf(lvl);   // cumulatif : niveau ≤ choisi
}
function populateLevels(norm){
  var sel=document.getElementById('cf-lvl'),wrap=document.getElementById('cf-lvl-wrap');
  var order=LEVEL_ORDER[norm];
  if(!order){wrap.style.display='none';sel.innerHTML='';return;}
  var present={};
  CFDATA.forEach(function(c){if(applicable(c,norm)&&c.levels&&c.levels[norm]!=null)present[c.levels[norm]]=1;});
  var lvls=order.filter(function(l){return present[l];});
  if(!lvls.length){wrap.style.display='none';sel.innerHTML='';return;}
  sel.innerHTML='<option value="all">Tous niveaux</option>'+lvls.map(function(l){
    return '<option value="'+l+'">'+(LEVEL_LABEL[l]||l)+'</option>';}).join('');
  wrap.style.display='';
}
function onStd(){populateLevels(document.getElementById('cf-std').value);render();}
function chapterOf(c,norm){
  if(norm==='all')return c.domain||'Divers';
  var num=String(c.norms[norm]);
  if(HIER[norm]){
    // normes hiérarchiques : chapitrer à la SOUS-SECTION (parent de la règle).
    // ex. CIS 2.2.4 -> "CIS 2.2" ; NIST 3.1.13 -> "NIST 800-171 3.1".
    var p=num.split('.');
    var sub=p.length>1?p.slice(0,-1).join('.'):num;
    return LABELS[norm]+' '+sub;
  }
  return LABELS[norm]+' '+num;
}
function detail(c,norm){
  var h='';
  if(c.desc)h+='<p class="desc">'+esc(c.desc)+'</p>';
  if(c.evidence&&EVIDENCE[c.evidence]){
    var ev=EVIDENCE[c.evidence];
    h+='<p class="evid evid-'+c.evidence+'"><span class="evid-k">Preuve</span> <b>'+esc(ev.l)+'</b> — '+esc(ev.n)+'</p>';
  }
  // mappings normatifs : la norme active est mise en avant
  var tags='';
  for(var k in c.norms){tags+='<span class="tag'+(k===norm?' on':'')+'">'+esc(LABELS[k]||k)+' '+esc(c.norms[k])+'</span>';}
  if(tags)h+='<p class="refs"><b>Normes</b> : '+tags+'</p>';
  if(c.refs&&c.refs.length)h+='<p class="refs"><b>Références</b> : '+c.refs.map(esc).join(' &middot; ')+'</p>';
  if(c.checks&&c.checks.length){
    h+='<ul class="checks">';
    c.checks.forEach(function(r){
      var cls=({passed:'ok',failed:'ko',skipped:'sk'})[r.st]||'sk';
      var line=esc(r.desc);if(r.msg)line+='<div class="msg">'+esc(r.msg)+'</div>';
      h+='<li class="'+cls+'">'+line+'</li>';
    });
    h+='</ul>';
  }
  return h||'<p class="desc">Aucun détail.</p>';
}
// Fusion des frères splittés par valeur (umask-…-bp28 / -cis) en UNE entrée
// citant les deux normes, en vue « toutes normes ». Statut = pire (toutes
// normes = satisfaire chacune) ; titre = base + « (bp28 077 · cis 027) ».
function _sevRank(s){return {basse:0,moyenne:1,haute:2,critique:3}[s]||0;}
function _valOf(c){var m=(c.title||'').match(/\(([^)]+)\)\s*$/);return m?m[1]:'';}
function mergeControls(base,sibs){
  var status='passed',sev='basse',norms={},levels={},checks=[];
  sibs.forEach(function(c){
    if(c.status==='failed')status='failed';else if(c.status==='skipped'&&status==='passed')status='skipped';
    if(_sevRank(c.sev)>_sevRank(sev))sev=c.sev;
    for(var k in c.norms)norms[k]=c.norms[k];
    for(var k in c.levels)levels[k]=c.levels[k];
    checks=checks.concat(c.checks||[]);
  });
  var title=(sibs[0].title||base).replace(/\s*\([^)]*\)\s*$/,'');
  var cite=sibs.map(function(c){return Object.keys(c.norms).join('/')+' '+_valOf(c);}).join(' · ');
  return {id:base,title:title+(cite?' ('+cite+')':''),impact:sibs[0].impact,sev:sev,status:status,
          domain:sibs[0].domain,evidence:sibs[0].evidence,norms:norms,levels:levels,refs:[],checks:checks,merge:base};
}
function mergeAll(set){
  var byG={},out=[];
  set.forEach(function(c){
    if(!c.merge){out.push(c);return;}
    if(!byG[c.merge]){byG[c.merge]=[];out.push({__m:c.merge});}
    byG[c.merge].push(c);
  });
  return out.map(function(x){return x.__m?mergeControls(x.__m,byG[x.__m]):x;});
}
function render(){
  var norm=document.getElementById('cf-std').value;
  var lvlSel=document.getElementById('cf-lvl');
  var lvl=(lvlSel&&document.getElementById('cf-lvl-wrap').style.display!=='none')?lvlSel.value:'all';
  var set=CFDATA.filter(function(c){return applicable(c,norm)&&inLevel(c,norm,lvl);});
  if(norm==='all')set=mergeAll(set);   // vue « toutes normes » : fusionne les frères splittés
  // score sur l'ensemble applicable à la norme
  var p=0,f=0,s=0,sev={critique:0,haute:0,moyenne:0,basse:0};
  var ep={runtime:0,persistent:0,state:0};   // qualité de preuve des PASS
  set.forEach(function(c){
    if(c.status==='passed'){p++;
      if(c.evidence==='effective-runtime'||c.evidence==='behavioral')ep.runtime++;
      else if(c.evidence==='persistent-config')ep.persistent++;
      else if(c.evidence==='inventory-state'||c.evidence==='filesystem-state')ep.state++;
    }else if(c.status==='failed'){f++;sev[c.sev]++;}else if(c.status==='skipped')s++;
  });
  var scored=p+f,pct=scored?Math.round(100*p/scored):0;
  var g=grade(set);
  var gradeHtml='<div class="grade g-'+g.letter+'">'
    +'<div class="gletter">'+g.letter+'</div>'
    +'<div class="ginfo">'
      +'<div class="gpts">'+g.final+' <span>/ 100 pts</span></div>'
      +'<div class="gband">'+GBAND[g.letter]+(g.rq?' &middot; <span class="rq" title="La note ne peut pas être un A net : '+g.qualified+' PASS reposent sur une preuve runtime-only (actif prouvé, persistance non vérifiée).">runtime-qualifiée</span>':'')+'</div>'
      +'<div class="gsev">'
        +'<span class="sd critique"></span>critique '+g.counts.critique
        +'<span class="sd haute"></span>haute '+g.counts.haute
        +'<span class="sd moyenne"></span>moyenne '+g.counts.moyenne
        +'<span class="sd basse"></span>basse '+g.counts.basse+'</div>'
    +'</div></div>';
  document.getElementById('cf-score').innerHTML=
    gradeHtml
    +'<div class="score">'
    +'<div><div class="big">'+pct+'%</div><div class="muted">conforme ('+p+'/'+scored+')</div></div>'
    +'<div class="bar"><i style="width:'+pct+'%"></i></div>'
    +'<div><span class="chip ok">'+p+' PASS</span><span class="chip ko">'+f+' FAIL</span><span class="chip sk">'+s+' N/A</span></div>'
    +'</div>'
    +'<div class="sevline">Sévérité des échecs : haute <b>'+sev.haute+'</b> &middot; moyenne <b>'+sev.moyenne+'</b> &middot; basse <b>'+sev.basse+'</b></div>'
    +(p?'<div class="evline" title="Ce qu\'un PASS prouve. Un PASS runtime-only sans compagnon persistant ne prouve pas la survie au reboot et plafonne la note sous A (verdict qualifié)."><b>'+g.qualified+'</b> PASS runtime-only <span class="muted">(persistance non prouvée → plafonne sous A)</span> &middot; <b>'+(p-g.qualified)+'</b> PASS durables <span class="muted">(survivent au reboot)</span></div>':'')
    +'<div class="muted" style="margin-top:.5rem">Vue : <b class="pill">'+(norm==='all'?'Toutes normes':LABELS[norm]||norm)+'</b>'
    +(lvl!=='all'?' &middot; niveau <b class="pill">'+(LEVEL_LABEL[lvl]||lvl)+'</b> et inférieurs':'')
    +' &middot; '+set.length+' contrôles applicables</div>';
  // chapitres
  var chaps={},order=[];
  set.forEach(function(c){var ch=chapterOf(c,norm);if(!chaps[ch]){chaps[ch]=[];order.push(ch);}chaps[ch].push(c);});
  order.sort(function(a,b){return a.replace(/\d+/g,function(n){return n.padStart(6,'0');})
                            .localeCompare(b.replace(/\d+/g,function(n){return n.padStart(6,'0');}));});
  var showLvl=!!LEVEL_ORDER[norm];   // colonne Niveau seulement si la norme en a
  var cspan=showLvl?5:4;
  var out='';
  order.forEach(function(ch){
    var ctrls=chaps[ch];
    var cp=ctrls.filter(function(c){return c.status==='passed';}).length;
    var cf=ctrls.filter(function(c){return c.status==='failed';}).length;
    out+='<section><h2><span>'+esc(ch)+'</span><span class="muted">'+cp+' OK / '+cf+' échec</span></h2><table>'
        +'<tr><th>Règle</th><th>Contrôle</th>'+(showLvl?'<th>Niveau (norme)</th>':'')+'<th>Sévérité (impact)</th><th>État</th></tr>';
    ctrls.forEach(function(c){
      var lvlCell='';
      if(showLvl){var cl=c.levels&&c.levels[norm];
        lvlCell='<td>'+(cl?'<span class="lvl">'+(LEVEL_LABEL[cl]||cl)+'</span>':'—')+'</td>';}
      out+='<tr class="rule" data-status="'+c.status+'" data-sev="'+c.sev+'" onclick="cfToggle(this)">'
          +'<td class="cid">'+esc(c.id)+'</td><td>'+esc(c.title)+'</td>'+lvlCell
          +'<td>'+sevBadge(c.sev)+'</td><td>'+(BADGE[c.status]||'')+'</td></tr>'
          +'<tr class="det" style="display:none"><td colspan="'+cspan+'">'+detail(c,norm)+'</td></tr>';
    });
    out+='</table></section>';
  });
  document.getElementById('cf-sections').innerHTML=out||'<p class="muted">Aucun contrôle pour cette norme.</p>';
  cfApply();
}
function cfApply(){
  var q=(document.getElementById('cf-q').value||'').toLowerCase();
  var r=document.querySelector('input[name=cf-res]:checked').value;
  var sv=document.getElementById('cf-sev').value;
  var SVRANK={basse:0,moyenne:1,haute:2,critique:3};
  document.querySelectorAll('tr.rule').forEach(function(row){
    var okR=(r==='all')||row.dataset.status===r;
    var okS=(sv==='all')||SVRANK[row.dataset.sev]>=SVRANK[sv];   // seuil : >= sévérité min.
    var okQ=row.textContent.toLowerCase().indexOf(q)>=0;
    var show=okR&&okS&&okQ;row.style.display=show?'':'none';
    var d=row.nextElementSibling;
    if(d&&d.classList.contains('det')&&!show)d.style.display='none';
  });
  // masquer les chapitres sans aucune règle visible (recherche/filtre)
  document.querySelectorAll('section').forEach(function(sec){
    var rows=sec.querySelectorAll('tr.rule'),vis=0,i;
    for(i=0;i<rows.length;i++){if(rows[i].style.display!=='none'){vis++;break;}}
    sec.style.display=vis?'':'none';
  });
}
function cfToggle(row){
  var d=row.nextElementSibling;
  if(d&&d.classList.contains('det'))d.style.display=(d.style.display==='none'||!d.style.display)?'table-row':'none';
}
document.addEventListener('DOMContentLoaded',onStd);
