/**
 * "N thing" or "N things".
 *
 * A generated page states counts constantly, and the count is not always plural: a domain holding
 * a single control rendered "1 contrôles de durcissement Linux" in its H1, its `<title>` and its
 * meta description, on the page and in the search result alike. Both languages of this site
 * pluralise by picking a different word, so one helper covers them.
 *
 * Sentences are written to avoid agreement beyond the noun ("sur 1 système et 2 normes" rather
 * than "mappés sur…"), because a helper cannot inflect the verb and the adjective too.
 */
export const count = (n: number, one: string, many: string): string => `${n} ${n === 1 ? one : many}`;
