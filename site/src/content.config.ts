import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

// One entry per (OS, control), the rich, bilingual per-rule record. The base (check, norms,
// remediation, title/rationale/severity/references) is mined by the norm-studio from Pavois's
// reference + the SSG datastream; the OPERATIONAL fields (verify, logs, remediation_note, impact)
// are Pavois-authored expertise, the "info that exists nowhere else". Every text field is FR/EN.
const localized = z.object({ en: z.string(), fr: z.string() });

const rules = defineCollection({
  loader: glob({ pattern: '**/*.json', base: './src/content/rules' }),
  schema: z.object({
    id: z.string(),
    // Hand-maintained editorial dates (YYYY-MM-DD), the site is generated from data, so these
    // are NOT git/build dates: the author sets/bumps them on a real content change. Optional.
    datePublished: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    dateModified: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    // One fiche per (neutral) control id; the OSes that ship it + their CIS benchmark version.
    supported_os: z.array(z.string()).default([]),
    os_versions: z.record(z.string(), z.string()).default({}),
    domain: z.string().optional().nullable(),
    severity: z.enum(['low', 'medium', 'high', 'critical', 'unknown']).default('unknown'),
    // What kind of evidence the check actually gathers (honesty over the blanket "effective" claim).
    evidence_type: z
      .enum([
        'effective-runtime',
        'persistent-config',
        'inventory-state',
        'filesystem-state',
        'manual',
        'behavioral',
      ])
      .optional()
      .nullable(),
    // Whether a PASS proves a reboot-survivable state (the persistence axis of the qualified
    // verdict). 'yes' = the check folds a persistence proof; 'no' = runtime-only; 'unknown'.
    reboot_survivable: z.enum(['yes', 'no', 'unknown']).optional().nullable(),

    // Which standards require it (merged across OSes).
    norms: z.record(z.string(), z.union([z.string(), z.array(z.string())])).default({}),
    references: z.record(z.string(), z.array(z.string())).default({}),

    // Bilingual content.
    title: localized,
    summary: localized.optional(), // one-line
    rationale: localized.optional(), // why this rule, the risk
    check_note: localized.optional(), // what Pavois verifies (effective-config advantage)
    verify: localized.optional(), // how to verify it is applied (command + expected output)
    logs: localized.optional(), // which logs confirm it / show related events
    remediation_note: localized.optional(), // what the remediation actually does
    impact: localized.optional(), // consequences of the misconfig AND precautions before applying

    // Machine-runnable bits.
    check: z.array(z.string()).default([]), // the InSpec effective-config control
    // Pavois's own remediation: the structured `harden` plan (resource + value + notify…),
    // applied by `pavois harden apply`, NOT SSG bash/ansible.
    remediation: z.record(z.string(), z.any()).default({}),

    // Honesty flags, both written by tools/generate_rule_pages.py. They were being dropped: the
    // generator has been emitting `needs_translation` on 785 fiches, the schema did not declare it,
    // so Astro stripped it at load and no page could ever show it — the label was even sitting
    // unused in i18n/ui.ts. A gap you cannot query is a gap you never close.
    needs_authoring: z.array(z.string()).optional(), // rich prose still to write
    needs_translation: z.array(z.string()).optional(), // FR field still echoing the EN one
  }),
});

// Bilingual glossary, mined from the devsecops-2026 glossary (FR), English added by a translation
// pass (en_status). Each term explains a security / Linux / compliance concept behind the rules.
const bilingual = z.object({ short: z.string().default(''), full: z.string().default('') });
const glossary = defineCollection({
  loader: glob({ pattern: '**/*.json', base: './src/content/glossary' }),
  schema: z.object({
    term: z.string(),
    slug: z.string(),
    category: z.string(),
    tags: z.array(z.string()).default([]),
    aliases: z.array(z.string()).default([]),
    related: z.array(z.string()).default([]),
    fr: bilingual.extend({ translation: z.string().default('') }),
    en: bilingual.default({ short: '', full: '' }),
    en_status: z.string().optional(),
  }),
});

// The hardening handbook, original bilingual content (threats → why harden → defense
// principles → what Pavois audits), per topic. It CITES (never copies) external deep-dive
// guides, and links the pavois rules of its domain.
const handbook = defineCollection({
  loader: glob({ pattern: '**/*.json', base: './src/content/handbook' }),
  schema: z.object({
    id: z.string(),
    // Hand-maintained editorial dates (YYYY-MM-DD), author-set on real content changes. Optional.
    datePublished: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    dateModified: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    section: z.enum(['foundations', 'domains', 'tooling']),
    order: z.number().default(0),
    domain: z.string().optional(), // Pavois rule domain this maps to
    title: localized,
    summary: localized.optional(),
    body: localized, // Markdown
    cite: z
      .array(z.object({ url: z.string(), label: z.string() }))
      .default([]), // external deep-dive references (e.g. the blog guides)
  }),
});

// Blog, field-experience / release notes / deep-dives, modelled on the devsecops-2026 blog
// (category + tags + keywords + reading time + Article schema) but bilingual: one Markdown file
// per language, tagged `lang`, listed under its language. Dates are hand-maintained (no git).
const blog = defineCollection({
  loader: glob({ pattern: '**/[^_]*.md', base: './src/content/blog' }),
  schema: z.object({
    lang: z.enum(['en', 'fr']),
    title: z.string().min(5).max(150),
    description: z.string().min(20).max(300),
    datePublished: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    dateModified: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    author: z.string().default('stephane-robert'),
    category: z.string().optional(),
    tags: z.array(z.string()).default([]),
    keywords: z.array(z.string()).default([]),
    image: z.string().optional(),
    draft: z.boolean().default(false),
    featured: z.boolean().default(false),
  }),
});

export const collections = { rules, glossary, handbook, blog };
