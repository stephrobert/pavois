// Blog helpers — modelled on devsecops-2026's src/lib/blog.ts, adapted to pavois (bilingual).
import type { Lang } from '../i18n/ui';

export const POSTS_PER_PAGE = 9;

// Editorial categories (slug -> bilingual label). Used by the breadcrumb, filters and the
// articleSection in the Article JSON-LD.
export const BLOG_CATEGORIES: Record<string, { en: string; fr: string }> = {
  release: { en: 'Release notes', fr: 'Notes de version' },
  methodology: { en: 'Methodology', fr: 'Méthodologie' },
  'field-notes': { en: 'Field notes', fr: 'Retours de terrain' },
  tutorial: { en: 'Tutorial', fr: 'Tutoriel' },
};

export function categoryLabel(slug: string | undefined, lang: Lang): string {
  if (!slug) return lang === 'fr' ? 'Article' : 'Article';
  return BLOG_CATEGORIES[slug]?.[lang] ?? slug;
}

// Reading time at ~200 wpm (rounded up, min 1). Counts whitespace-separated tokens.
export function readingTimeMinutes(body: string | undefined): number {
  if (!body) return 1;
  const words = body.trim().split(/\s+/).filter(Boolean).length;
  return Math.max(1, Math.round(words / 200));
}

// Localised date label from a YYYY-MM-DD string (no timezone math, no Date.now).
export function formatDate(iso: string, lang: Lang): string {
  const [y, m, d] = iso.split('-').map(Number);
  const months = {
    en: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
    fr: ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'],
  };
  const mn = months[lang][(m || 1) - 1];
  return lang === 'fr' ? `${d} ${mn} ${y}` : `${mn} ${d}, ${y}`;
}
