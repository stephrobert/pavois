import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';

// GEO: an llms.txt index (https://llmstxt.org), a curated, link-rich map of the site for
// generative engines. Generated from the collections so it stays current. English canonical.
export const GET: APIRoute = async ({ site }) => {
  const origin = (site?.toString() ?? 'https://pavois.dev/').replace(/\/$/, '');
  const handbook = (await getCollection('handbook')).sort(
    (a, b) => (a.data.order || 0) - (b.data.order || 0)
  );
  const rules = await getCollection('rules');

  const lines: string[] = [];
  lines.push('# Pavois');
  lines.push('');
  lines.push(
    '> Effective Linux compliance. Pavois audits the resolved running configuration (sshd -T, ' +
      'sysctl, systemctl show, auditctl -l) over CINC/InSpec, maps each control to CIS, ANSSI ' +
      'BP-028, NIST, PCI-DSS and STIG at once, grades the result A to E, and hardens it as code ' +
      'with a state-aware Chef plan. A PASS carries a qualified verdict: running now versus ' +
      'reboot-survivable, so the grade only reaches a clean A when persistence is proven.'
  );
  lines.push('');
  lines.push(`The control base spans ${rules.length} neutral control ids across 8 Linux targets.`);
  lines.push('');

  lines.push('## Handbook');
  for (const h of handbook) {
    const s = h.data.summary?.en ? `: ${h.data.summary.en}` : '';
    lines.push(`- [${h.data.title.en}](${origin}/en/handbook/${h.data.id}/)${s}`);
  }
  lines.push('');

  lines.push('## Standards (one check, every standard)');
  for (const [k, name] of [
    ['cis', 'CIS Benchmarks'],
    ['bp28', 'ANSSI BP-028'],
    ['nist', 'NIST SP 800-53 / 800-171'],
    ['pci-dss', 'PCI DSS'],
    ['stig', 'DISA STIG'],
  ]) {
    lines.push(`- [${name}](${origin}/en/standards/${k}/)`);
  }
  lines.push('');

  lines.push('## Key pages');
  lines.push(`- [How it works](${origin}/en/docs/)`);
  lines.push(`- [Tool comparison by evidence type](${origin}/en/docs/tools/)`);
  lines.push(`- [Browse all controls](${origin}/en/rules/)`);
  lines.push(`- [OSCAL downloads](${origin}/en/downloads/)`);
  lines.push('');

  return new Response(lines.join('\n') + '\n', {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
};
