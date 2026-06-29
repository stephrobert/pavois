// Lighthouse over the whole site (every route), headless. Run against the built preview
// (`mise run site:preview`) for production-accurate scores: `mise run site:perf`.
export default {
  puppeteerOptions: {
    executablePath: '/usr/bin/chromium-browser',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-gpu'],
  },
  scanner: {
    device: 'desktop',
    // sample a few URLs per dynamic route group so the 1600+ rule/glossary pages aren't all scanned
    dynamicSampling: 3,
    // pre-launch robots.txt blocks everything and the sitemap carries the prod origin — ignore both
    // so the local preview is crawled.
    robotsTxt: false,
    sitemap: false,
  },
};
