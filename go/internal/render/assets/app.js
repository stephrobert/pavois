
var LABELS={bp28:"ANSSI BP-028",cis:"CIS",'pci-dss':"PCI-DSS",nist:"NIST 800-171",stig:"STIG",posture:"Posture"};
// Evidence type: what the check actually demonstrates (honest about "effective" != universal).
var EVIDENCE={
  'effective-runtime':{l:"Effective runtime",n:"Verified against the resolved state at runtime (sshd -T, sysctl, systemctl show…) — catches drop-ins and Include. Caveat: runtime != persistence; a value that is correct now may not survive a reboot."},
  'persistent-config':{l:"Persistent config",n:"Verified against the content of a persistent configuration file — the source of truth across reboots."},
  'inventory-state':{l:"Inventory state",n:"Verified against what is installed or registered (packages present/absent, account databases)."},
  'filesystem-state':{l:"Filesystem state",n:"Verified against a path's metadata (mode, owner, group, SUID/SGID)."},
  'manual':{l:"Manual",n:"No automated check — human judgement and business context required."},
  'behavioral':{l:"Behavioral",n:"Verified by actually attempting a forbidden action."}
};
var HIER={cis:1,'pci-dss':1,nist:1,stig:1};
var LEVEL_ORDER={bp28:["minimal","intermediary","enhanced","high"],cis:["1","2"]};
var LEVEL_LABEL={minimal:"minimal",intermediary:"intermediary",enhanced:"enhanced",high:"high","1":"level 1","2":"level 2"};
var BADGE={passed:'<span class="b ok">PASS</span>',failed:'<span class="b ko">FAIL</span>',
           skipped:'<span class="b sk">N/A</span>',empty:'<span class="b sk">-</span>'};
var SEVCLS={critical:'c',high:'h',medium:'m',low:'b'};
function sevBadge(s){return '<span class="sv '+(SEVCLS[s]||'b')+'">'+s+'</span>';}
// A->E grade Plumber-style: weight per severity, critical penalty (cap 30 -> E).
// Severity = the REAL scale of the standards (3 tiers: high/medium/low). The SSG
// does not classify as "Critical" and standards do not override severity;
// so we grade over 3 tiers, without a phantom rank.
var GW={critical:25,high:15,medium:6,low:3};
var GCAP={critical:Infinity,high:60,medium:20,low:10};   // loss cap per severity
var GBAND={A:'Excellent',B:'Good',C:'Fair',D:'Poor',E:'Critical'};
// PASSED: the GLOBAL set of controls that pass (all views), to resolve persistent
// companions independently of the standard/level filter. Mirror of the Go pre-pass.
var PASSED={};
(typeof CFDATA!=='undefined'?CFDATA:[]).forEach(function(c){ if(c.status==='passed')PASSED[c.id]=true; });
// fullPass: does a PASS count as FULL? The reboot tag (persistence axis) wins; otherwise we
// fall back to the evidence type. A live control becomes full again if its companion passes.
// Exact mirror of audit.fullPassFor on the Go side (single source of policy).
function fullPass(c){
  if(c.reboot==='yes')return true;
  if(c.reboot==='no'||c.reboot==='unknown')return !!(c.companion&&PASSED[c.companion]);
  return c.evidence==='persistent-config'||c.evidence==='inventory-state'||c.evidence==='filesystem-state';
}
function grade(set){
  // We start at 100 and SUBTRACT weight x number of FAILURES, capped by
  // severity. >= 1 critical -> cap 30 (risk penalty, band E).
  var counts={critical:0,high:0,medium:0,low:0},qualified=0;
  set.forEach(function(c){
    if(c.status==='failed')counts[c.sev]++;
    else if(c.status==='passed'&&!fullPass(c))qualified++; // runtime-only PASS without companion
  });
  var loss=Math.min(GW.critical*counts.critical,GCAP.critical)
          +Math.min(GW.high*counts.high,GCAP.high)
          +Math.min(GW.medium*counts.medium,GCAP.medium)
          +Math.min(GW.low*counts.low,GCAP.low);
  var fin=Math.max(0,Math.round(100-loss));
  if(counts.critical>0&&fin>30)fin=30;
  var L=fin>=90?'A':fin>=71?'B':fin>=51?'C':fin>=31?'D':'E';
  // Qualified-verdict cap: an A is not earned on runtime-only PASS with unproven
  // persistence. The points are unchanged — only the letter is capped.
  var rq=qualified>0;
  if(rq&&L==='A')L='B';
  return {letter:L,final:fin,counts:counts,qualified:qualified,rq:rq};
}
// remClass: remediation class (mirror of audit.RemediationClass), for the executive
// summary's posture breakdown. Derived from the id, domain and evidence type.
function remClass(c){
  var id=c.id||'';
  if(id==='kmod-loading-disabled'||id.indexOf('modules-disabled')>=0||id.indexOf('grub-password')>=0||id.indexOf('cmdline-iommu')===0)return 'dangerous';
  var d=(c.domain||'').toLowerCase();
  if(d==='kernel build')return 'kernel-build';
  if(d==='mounts'||id.indexOf('partition-')===0)return 'install-time';
  if(c.evidence==='manual')return 'manual';
  return 'auto';
}
function esc(s){return (s==null?'':''+s).replace(/[&<>"]/g,function(c){
  return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
function applicable(c,norm){return norm==='all'||(c.norms&&c.norms[norm]!=null);}
function inLevel(c,norm,lvl){
  if(lvl==='all')return true;
  var order=LEVEL_ORDER[norm];if(!order)return true;
  var cl=c.levels&&c.levels[norm];if(cl==null)return true;// no level = included
  return order.indexOf(cl)<=order.indexOf(lvl);   // cumulative: level <= selected
}
function populateLevels(norm){
  var sel=document.getElementById('cf-lvl'),wrap=document.getElementById('cf-lvl-wrap');
  var order=LEVEL_ORDER[norm];
  if(!order){wrap.style.display='none';sel.innerHTML='';return;}
  var present={};
  CFDATA.forEach(function(c){if(applicable(c,norm)&&c.levels&&c.levels[norm]!=null)present[c.levels[norm]]=1;});
  var lvls=order.filter(function(l){return present[l];});
  if(!lvls.length){wrap.style.display='none';sel.innerHTML='';return;}
  sel.innerHTML='<option value="all">All levels</option>'+lvls.map(function(l){
    return '<option value="'+l+'">'+(LEVEL_LABEL[l]||l)+'</option>';}).join('');
  wrap.style.display='';
}
function onStd(){populateLevels(document.getElementById('cf-std').value);render();}
function chapterOf(c,norm){
  if(norm==='all')return c.domain||'Misc';
  var num=String(c.norms[norm]);
  if(HIER[norm]){
    // hierarchical standards: chapter at the SUB-SECTION (parent of the rule).
    // e.g. CIS 2.2.4 -> "CIS 2.2"; NIST 3.1.13 -> "NIST 800-171 3.1".
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
    h+='<p class="evid evid-'+c.evidence+'"><span class="evid-k">Evidence</span> <b>'+esc(ev.l)+'</b> — '+esc(ev.n)+'</p>';
  }
  if(c.danger){
    h+='<p class="danger"><span class="danger-k">⚠ Danger</span> '+esc(c.danger)+'</p>';
  }
  // normative mappings: the active standard is highlighted
  var tags='';
  for(var k in c.norms){tags+='<span class="tag'+(k===norm?' on':'')+'">'+esc(LABELS[k]||k)+' '+esc(c.norms[k])+'</span>';}
  if(tags)h+='<p class="refs"><b>Standards</b>: '+tags+'</p>';
  if(c.refs&&c.refs.length)h+='<p class="refs"><b>References</b>: '+c.refs.map(esc).join(' &middot; ')+'</p>';
  if(c.checks&&c.checks.length){
    h+='<ul class="checks">';
    c.checks.forEach(function(r){
      var cls=({passed:'ok',failed:'ko',skipped:'sk'})[r.st]||'sk';
      var line=esc(r.desc);if(r.msg)line+='<div class="msg">'+esc(r.msg)+'</div>';
      h+='<li class="'+cls+'">'+line+'</li>';
    });
    h+='</ul>';
  }
  return h||'<p class="desc">No details.</p>';
}
// Merge value-split siblings (umask-…-bp28 / -cis) into ONE entry citing both
// standards, in the "all standards" view. Status = worst (all standards = satisfy
// each one); title = base + "(bp28 077 · cis 027)".
function _sevRank(s){return {low:0,medium:1,high:2,critical:3}[s]||0;}
function _valOf(c){var m=(c.title||'').match(/\(([^)]+)\)\s*$/);return m?m[1]:'';}
function mergeControls(base,sibs){
  var status='passed',sev='low',norms={},levels={},checks=[];
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
  if(norm==='all')set=mergeAll(set);   // "all standards" view: merge value-split siblings
  // score over the set applicable to the standard
  var p=0,f=0,s=0,sev={critical:0,high:0,medium:0,low:0};
  var ep={runtime:0,persistent:0,state:0};   // evidence quality of the PASS
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
      +'<div class="gband">'+GBAND[g.letter]+(g.rq?' &middot; <span class="rq" title="The grade cannot be a clean A: '+g.qualified+' PASS rely on runtime-only evidence (proven active, persistence not verified).">runtime-qualified</span>':'')+'</div>'
      +'<div class="gsev">'
        +'<span class="sd critical"></span>critical '+g.counts.critical
        +'<span class="sd high"></span>high '+g.counts.high
        +'<span class="sd medium"></span>medium '+g.counts.medium
        +'<span class="sd low"></span>low '+g.counts.low+'</div>'
    +'</div></div>';
  document.getElementById('cf-score').innerHTML=
    gradeHtml
    +'<div class="score">'
    +'<div><div class="big">'+pct+'%</div><div class="muted">compliant ('+p+'/'+scored+')</div></div>'
    +'<div class="bar"><i style="width:'+pct+'%"></i></div>'
    +'<div><span class="chip ok">'+p+' PASS</span><span class="chip ko">'+f+' FAIL</span><span class="chip sk">'+s+' N/A</span></div>'
    +'</div>'
    +'<div class="sevline">Failure severity: high <b>'+sev.high+'</b> &middot; medium <b>'+sev.medium+'</b> &middot; low <b>'+sev.low+'</b></div>'
    +(p?'<div class="evline" title="What a PASS proves. A runtime-only PASS without a persistent companion does not prove reboot survival and caps the grade below A (qualified verdict)."><b>'+g.qualified+'</b> runtime-only PASS <span class="muted">(persistence not proven → caps below A)</span> &middot; <b>'+(p-g.qualified)+'</b> durable PASS <span class="muted">(survive reboot)</span></div>':'')
    +'<div class="muted" style="margin-top:.5rem">View: <b class="pill">'+(norm==='all'?'All standards':LABELS[norm]||norm)+'</b>'
    +(lvl!=='all'?' &middot; level <b class="pill">'+(LEVEL_LABEL[lvl]||lvl)+'</b> and below':'')
    +' &middot; '+set.length+' applicable controls</div>';
  // Executive summary: priority gaps + posture by remediation class + remediable grade.
  (function(){
    var CL=['auto','manual','dangerous','install-time','kernel-build'];
    var HINT={'install-time':'separate partition required','kernel-build':'kernel rebuild required','dangerous':'risky remediation','manual':'manual remediation'};
    var stat={},byCls={};CL.forEach(function(k){stat[k]={p:0,t:0};byCls[k]=[];});
    var rem=[];
    set.forEach(function(c){
      if(c.status!=='passed'&&c.status!=='failed')return;
      var k=remClass(c);if(!stat[k]){stat[k]={p:0,t:0};byCls[k]=[];}
      stat[k].t++;if(c.status==='passed')stat[k].p++;byCls[k].push(c);
      if(k!=='install-time'&&k!=='kernel-build')rem.push(c);
    });
    var rg=grade(rem),remp=rem.filter(function(c){return c.status==='passed';}).length;
    var gaps=set.filter(function(c){return c.status==='failed';})
      .sort(function(a,b){return _sevRank(b.sev)-_sevRank(a.sev);});
    var topN=gaps.slice(0,8);
    var gapsHtml=topN.length
      ?'<ol class="exec-gaps">'+topN.map(function(c){return '<li>'+sevBadge(c.sev)+' <span class="cid">'+esc(c.id)+'</span> '+esc(c.title)+'</li>';}).join('')+'</ol>'+(gaps.length>topN.length?'<div class="muted">+ '+(gaps.length-topN.length)+' more gaps</div>':'')
      :'<p class="muted">No gaps in this view.</p>';
    var posHtml=CL.filter(function(k){return stat[k].t;}).map(function(k){
      var gk=grade(byCls[k]).letter;
      return '<div class="exec-cls"><span>'+k+'</span> <b class="g-'+gk+'">'+gk+'</b> <b>'+stat[k].p+'/'+stat[k].t+'</b>'+(HINT[k]?' <span class="muted">'+HINT[k]+'</span>':'')+'</div>';
    }).join('');
    document.getElementById('cf-exec').innerHTML=
      '<div class="exec-grid">'
      +'<div><h3>Priority gaps</h3>'+gapsHtml+'</div>'
      +'<div><h3>Posture by remediation class</h3>'+posHtml
      +'<div class="exec-rem">Remediable posture: <b class="g-'+rg.letter+'">'+rg.letter+'</b> <span class="muted">('+remp+'/'+rem.length+', excluding install-time + kernel-build)</span></div>'
      +'</div></div>';
  })();
  // chapters
  var chaps={},order=[];
  set.forEach(function(c){var ch=chapterOf(c,norm);if(!chaps[ch]){chaps[ch]=[];order.push(ch);}chaps[ch].push(c);});
  order.sort(function(a,b){return a.replace(/\d+/g,function(n){return n.padStart(6,'0');})
                            .localeCompare(b.replace(/\d+/g,function(n){return n.padStart(6,'0');}));});
  var showLvl=!!LEVEL_ORDER[norm];   // Level column only if the standard has one
  var cspan=showLvl?5:4;
  var out='';
  order.forEach(function(ch){
    var ctrls=chaps[ch];
    var cp=ctrls.filter(function(c){return c.status==='passed';}).length;
    var cf=ctrls.filter(function(c){return c.status==='failed';}).length;
    out+='<section><h2><span>'+esc(ch)+'</span><span class="muted">'+cp+' OK / '+cf+' fail</span></h2><table>'
        +'<tr><th>Rule</th><th>Control</th>'+(showLvl?'<th>Level (standard)</th>':'')+'<th>Severity (impact)</th><th>State</th></tr>';
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
  document.getElementById('cf-sections').innerHTML=out||'<p class="muted">No control for this standard.</p>';
  cfApply();
}
function cfApply(){
  var q=(document.getElementById('cf-q').value||'').toLowerCase();
  var r=document.querySelector('input[name=cf-res]:checked').value;
  var sv=document.getElementById('cf-sev').value;
  var SVRANK={low:0,medium:1,high:2,critical:3};
  document.querySelectorAll('tr.rule').forEach(function(row){
    var okR=(r==='all')||row.dataset.status===r;
    var okS=(sv==='all')||SVRANK[row.dataset.sev]>=SVRANK[sv];   // threshold: >= min. severity
    var okQ=row.textContent.toLowerCase().indexOf(q)>=0;
    var show=okR&&okS&&okQ;row.style.display=show?'':'none';
    var d=row.nextElementSibling;
    if(d&&d.classList.contains('det')&&!show)d.style.display='none';
  });
  // hide chapters with no visible rule (search/filter)
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
