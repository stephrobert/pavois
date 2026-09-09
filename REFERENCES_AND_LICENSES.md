# References and licences

What Pavois takes from each external source, under what terms, and how that is kept true.

This file exists because "we only map reference numbers" is a licensing position, not a slogan,
and a position has to be checkable. It is: `mise run lint:norm-refs` walks every mapping in
`docs/reference/rules.yml` and fails if one holds anything but an identifier. At the time of
writing that is **5348 mappings across five catalogues, all identifiers, no prose.**

## The short version

Pavois stores **section numbers**. It does not store, and does not publish, the wording of any
benchmark: no descriptions, no rationales, no remediation text lifted from a standard.

A section number is a fact. "CIS Debian 12 benchmark, section 5.4.2.1" is a citation in the same
way a page number is, and citing is not copying. The sentence in that section explaining what it
requires is the benchmark's own text, and reproducing it would need permission that Pavois does
not have and has not asked for.

Everything a reader sees on a rule page that is NOT a number is Pavois's own: the title, the
check, the remediation, the risk note.

## Per catalogue

| Catalogue | What Pavois stores | Version | Terms |
|---|---|---|---|
| CIS Benchmarks | section numbers | one per OS, listed on the standards page | [CIS terms](https://www.cisecurity.org/terms-and-conditions-table-of-contents) |
| ANSSI-BP-028 | recommendation ids (R33, R68...) | 2.0 | [Etalab Open Licence 2.0](https://www.etalab.gouv.fr/licence-ouverte-open-licence/) |
| NIST SP 800-53 / 800-171 | control ids (AC-17(a), 3.1.1...) | Rev 5 / Rev 2 | US Government work, public domain in the US |
| PCI DSS | requirement numbers | 4.0.1 | [PCI SSC document library](https://www.pcisecuritystandards.org/document_library/) |
| DISA STIG | rule and group ids | per product release | US Government work, public domain in the US |

Two of them deserve a sentence rather than a row.

**CIS.** Free availability is not free redistribution. The benchmarks can be downloaded at no cost
after accepting terms, and those terms are not an open licence. Pavois's position rests entirely
on storing numbers and nothing else, which is why the check above exists. CIS also publishes a
single benchmark per OS **and** per version, so a single "CIS version" for the whole project would
be false: the version targeted is recorded per OS in `site/src/data/benchmarks.json`, generated
from `docs/reference/norms.yml`.

**PCI DSS.** The PCI SSC sets specific conditions on copying, modification and derivative works.
The same rule applies and for the same reason: numbers only.

## Where the controls came from

The control base was **seeded once** from [ComplianceAsCode / SCAP Security
Guide](https://github.com/ComplianceAsCode/content) (**BSD-3-Clause**) and cross-checked against
[ansible-lockdown](https://github.com/ansible-lockdown) (**MIT**). 772 of 789 rules still carry
their originating `ssg:` identifier, so the provenance of each one is traceable rather than
asserted. The base is now Pavois-owned and maintained directly; the SSG datastreams are no longer
a dependency at runtime.

Titles derived from SSG rule names are used under BSD-3-Clause, which permits redistribution with
attribution. That attribution is on [/attribution](https://pavois.dev/en/attribution/) and here.

## Build-time only

`tools/` queries [intuitem/ciso-assistant](https://github.com/intuitem/ciso-assistant-community)
(**AGPL-3.0**) to cross-validate mappings. It runs at build time on a maintainer's machine, and
none of it is embedded in the binary, the profiles or the site.

## Trademarks, and what Pavois does not claim

**CIS Benchmarks**, **PCI DSS**, **DISA STIG** and **NIST** are trademarks of their respective
owners. Pavois is **not affiliated with, endorsed by, or certified by** any of them.

A mapping states a technical relationship between a Pavois control and a requirement. It is not a
certification, not a validation, and not a statement that the requirement is satisfied: a
requirement can have organisational or procedural parts that no scanner reaches. "Mapped to" is
the claim; "satisfies" and "certified against" are not.

## If something here is wrong

Open an issue. Where a redistribution right is unclear, the rule this project follows is to
**remove or reduce the content rather than guess**, and that has cost nothing so far because
numbers were always enough.
