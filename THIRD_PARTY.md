# Third-party content and attributions

pavois is licensed under the Apache License 2.0 (see `LICENSE`). It builds on, and
references, third-party material. This file records the attributions and license
obligations for that material.

---

## 1. Derived software content (redistributed — attribution required)

### ComplianceAsCode / SCAP Security Guide (SSG)

pavois's control base was bootstrapped from, and remains cross-validated against, the
**ComplianceAsCode/content** project (the "SCAP Security Guide", SSG). Redistributed
material derived from SSG includes control **titles**, **rationale** text, **severity**,
the per-control `ssg:` identifier, and the standard-to-control **reference mappings**
(CIS / NIST / PCI-DSS / STIG / ANSSI section numbers). pavois's InSpec checks are
original re-implementations that audit the *effective* configuration and are not copied
from SSG's OVAL.

- Project: https://github.com/ComplianceAsCode/content
- License: **BSD-3-Clause**
- Copyright (c) Red Hat, Inc. and the ComplianceAsCode project contributors.

```
Redistribution and use in source and binary forms, with or without modification, are
permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of
   conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of
   conditions and the following disclaimer in the documentation and/or other materials
   provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used
   to endorse or promote products derived from this software without specific prior
   written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### Ansible Lockdown

pavois cross-validates its mappings against the **ansible-lockdown** `<OS>-CIS` projects.

- Project: https://github.com/ansible-lockdown
- License: **MIT**
- Copyright (c) MindPoint Group / Ansible Lockdown contributors.

```
Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
```

### Runtime engine

pavois shells out to **CINC Auditor** (the open-source distribution of Chef InSpec,
Apache-2.0). CINC is not bundled; it is installed separately by the user.

---

## 2. Standards referenced (numbers/identifiers only — not redistributed as text)

pavois maps each control to standard **reference numbers** (facts), inherited from SSG.
It does **not** reproduce the prose of these standards' documents.

| Standard | Status | How pavois uses it |
|---|---|---|
| **NIST SP 800-53 / 800-171, OSCAL** | U.S. Government work — **public domain** | control identifiers + cross-validation |
| **DISA STIG** | U.S. Government work — **public domain** | STIG identifiers |
| **ANSSI-BP-028** | Licence Ouverte / Etalab (open reuse) | R-numbers |
| **CIS Benchmarks™** | © Center for Internet Security — restrictive EULA, trademark | section **numbers** only (via SSG); no benchmark text reproduced |
| **PCI DSS** | © PCI Security Standards Council — trademark | requirement **numbers** only; no requirement text reproduced |

**CIS Benchmarks**, **PCI DSS**, **STIG** and **NIST** are trademarks of their respective
owners. pavois is **not affiliated with, endorsed by, or sponsored by** the Center for
Internet Security, the PCI Security Standards Council, NIST, or DISA.

---

## 3. Build-time only (not redistributed in the product)

### intuitem / ciso-assistant-community

The `tools/norm_studio/` content-engineering tooling fetches framework libraries from
**intuitem/ciso-assistant-community** at build/validation time, to cross-validate
pavois's PCI-DSS and NIST mappings against the canonical requirement sets.

- Project: https://github.com/intuitem/ciso-assistant-community
- License: **AGPL-3.0**

This material is used **only by the offline tooling** and is **never bundled** into the
shipped pavois binary or the published site. ciso-assistant code is not incorporated,
imported, or conveyed. Do not bundle its library files into the product, or the AGPL
copyleft would apply.
