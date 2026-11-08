// w_banking's page: plain JS (src/app.js) + the board kit (src/kit.css, w_train's, verbatim) + the bank's own sheet
// (src/bank.css). 2.1.0: built with vite like w_chat 1.2.0, so the kit stays a byte-identical copy and every px
// follows the screen (720p .. 8K, ultrawide by height) through ui-scale.cjs at build time.
// Build: `npm run build` in nui/ (it runs the vite in F:/Server RedM/Wraith Core/node_modules, nothing to install).
// Dev page: `npm run dev` -> http://localhost:5303/dev.html?lang=ar|en (src/dev/mock.js).
import uiScale from './ui-scale.cjs';

// Strip crossorigin from the injected <script>/<link> tags -- inside RedM CEF a module request
// can fail in CORS mode over nui:// (the most common cause of a black screen).
const stripCrossorigin = () => ({
  name: 'strip-crossorigin',
  enforce: 'post',
  transformIndexHtml(html) {
    return html.replace(/\s+crossorigin(=("|')?.*?\2)?/g, '');
  },
});

export default {
  plugins: [stripCrossorigin()],
  base: './',
  // dev only (dev.html + src/dev/mock.js): the mock reads the resource's locales one folder up
  server: { fs: { allow: ['..'] } },
  css: { postcss: { plugins: [uiScale()] } },
  build: {
    outDir: 'build',
    emptyOutDir: true,
    // the game browser (CEF 103) -- no syntax newer than it understands
    target: ['chrome87', 'edge88', 'firefox78', 'safari14'],
    minify: true,
    cssCodeSplit: false,
    // fixed names (no hash) so RedM never serves a stale bundle after a rebuild
    rollupOptions: {
      output: {
        entryFileNames: 'assets/app.js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: (info) =>
          info.name && info.name.endsWith('.css') ? 'assets/app.css' : 'assets/[name][extname]',
      },
    },
  },
};
