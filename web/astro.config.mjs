import { defineConfig } from 'astro/config';
import svelte from '@astrojs/svelte';

export default defineConfig({
  site: 'https://qobilidop.github.io',
  base: '/sail-xisa',
  integrations: [svelte()],
  vite: {
    server: {
      fs: { allow: ['..'] },
    },
  },
});
