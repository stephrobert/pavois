import { defineConfig } from 'astro/config';
import tailwindcss from '@tailwindcss/vite';

// pavois hardening reference — static, bilingual (FR/EN). Reuses the devsecops-2026 design
// system (Tailwind v4 tokens in src/styles/global.css). Content is fed by the norm-studio MCP.
export default defineConfig({
  site: 'https://pavois.dev',
  vite: {
    plugins: [tailwindcss()],
    // allow exposing `astro preview` through a trycloudflare quick tunnel (host changes each run)
    preview: { allowedHosts: ['.trycloudflare.com'] },
  },
});
