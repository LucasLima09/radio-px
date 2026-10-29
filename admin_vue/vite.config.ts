import { fileURLToPath, URL } from 'node:url';
import { defineConfig } from 'vitest/config';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  // O painel é servido pelo backend Go em /admin.
  base: '/admin/',
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  build: {
    // Gerado dentro do pacote Go que faz o embed do binário.
    outDir: '../backend/internal/infrastructure/http/adminui/dist',
    emptyOutDir: true,
    rollupOptions: {
      output: {
        // Nomes com hash de conteúdo: compatível com o cache immutable do backend.
        entryFileNames: 'assets/app-[hash].js',
        chunkFileNames: 'assets/chunk-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
      },
    },
  },
  server: {
    port: 5173,
  },
  test: {
    environment: 'jsdom',
  },
});
