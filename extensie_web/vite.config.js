
import { defineConfig } from 'vite';
import { viteStaticCopy } from 'vite-plugin-static-copy';

export default defineConfig({
  plugins: [
    viteStaticCopy({
      targets: [
        { src: 'manifest.json', dest: '.' },
        // background.js removed from here, now built via rollup
        { src: 'blocked.html', dest: '.' },
        { src: 'icon.png', dest: '.' },
        { src: 'style.css', dest: '.' },
        { src: 'auth.css', dest: '.' },
        { src: 'auth/*', dest: 'auth' }
      ]
    })
  ],
  build: {
    minify: true, // Enable minification for performance
    rollupOptions: {
      input: {
        popup: 'popup.html',
        'auth-login': 'auth/login.html',
        background: 'background.js' 
      },
      output: {
        entryFileNames: '[name].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]'
      }
    },
    outDir: 'dist',
    emptyOutDir: true
  }
});
