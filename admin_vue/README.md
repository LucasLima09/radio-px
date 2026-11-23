# Radio PX · Admin (Vue)

Painel administrativo em Vue 3. O build é embutido no binário Go e servido em `/admin`
(veja `backend/ADMIN.md`).

## Scripts

```bash
npm install
npm run dev        # http://localhost:5173/admin/
npm run test       # vitest
npm run build      # vue-tsc + vite build -> ../backend/internal/infrastructure/http/adminui/dist
npm run preview    # serve o build com base /admin/
```

Em dev, o campo **Servidor** do login vem preenchido com `http://localhost:8080`
(suba o backend com `cd ../backend && make dev`). No build servido pelo backend, a API é a mesma origem.

## Estrutura

```
src/
  core/         config, storage seguro, client HTTP (refresh automático, 401/403 centralizado)
  services/     uma função por endpoint da API
  stores/       Pinia: sessão (auth) e tema
  composables/  usePolling, useFeedback, useNow, useLeafletMap
  router/       rotas + guard; adminPages é a fonte única de rotas, sidebar e breadcrumb
  layouts/      AdminLayout (sidebar + topbar)
  components/   componentes compartilhados (MapView, DataTable, PageHeader, ...)
  features/     uma pasta por tela, com a lógica num composable (useUsers, useChannels, ...)
  styles/       CSS dividido por área (tokens, layout, tabelas, mapa, ...)
```

Fluxo: view → composable da feature → service → `core/http/client`.
Quando a sessão é recusada, o client limpa a sessão no store e o router volta para `/login`.
