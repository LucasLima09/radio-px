import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  // O painel é servido pelo backend Go em /admin.
  base: '/admin/',
  build: {
    // Gerado dentro do pacote Go que faz o embed do binário.
    outDir: '../backend/internal/infrastructure/http/adminui/dist',
    emptyOutDir: true,
    rollupOptions: {
      output: {
        // Nomes com hash de conteúdo: cada build gera URLs novas, então o
        // cache immutable dos assets nunca serve um bundle antigo.
        entryFileNames: 'assets/app-[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
      },
    },
  },
  server: {
    port: 5173,
  },
});
