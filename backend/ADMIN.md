# Painel admin

O painel é a aplicação React em `admin_web`. Ela é compilada para
`internal/infrastructure/http/adminui/dist` e embutida no binário Go via
`//go:embed`, sendo servida em `http://localhost:8080/admin` (e também na rede
local, ex.: `http://<ip>:8080/admin`), sem precisar de servidor de frontend
separado. É o painel principal de administração.

## Como recompilar o painel

Sempre que algo em `admin_web` mudar, gere o build antes de compilar o backend:

```bash
cd admin_web
npm install
npm run build   # gera ../backend/internal/infrastructure/http/adminui/dist
```

Ou, a partir de `backend/`:

```bash
make web
```

O backend embute o conteúdo de `dist/`; o `go build` depende desse diretório
existir. No ambiente Docker (`make dev`), o Air observa `js`, `css` e `html`
do diretório embutido e recompila sozinho após um novo `npm run build`.

## Recursos

- **Visão geral**: totais de usuários e de localizações reportadas, com mapa resumido.
- **Mapa ao vivo**: últimas posições via `/api/v1/admin/locations`, atualizado a cada 5 segundos.
- **Usuários**: listar, renomear, alterar `role` (`user`/`admin`) e **excluir** contas. A exclusão remove também canais, posições e tokens do usuário e não pode ser desfeita.
- **Canais**: listagem de canais, quantidade de pessoas online agora e exclusão (bloqueada quando há participantes conectados).

Todas as rotas `/api/v1/admin/*` exigem login administrativo e aceitam
administradores por `role=admin` ou pelos UUIDs configurados em `ADMIN_USER_IDS`.

## Mapa dos motoristas

O mapa usa a biblioteca Leaflet empacotada pelo próprio bundle React; as imagens
do mapa vêm do OpenStreetMap e exigem conexão com a internet. A licença está em
`admin_web/public/LEAFLET-LICENSE.txt` (servida em `/admin/LEAFLET-LICENSE.txt`).

O aplicativo envia GPS ao entrar em um canal, com permissão de localização: ao se
mover cerca de 10 metros e a cada 30 segundos quando parado. O mapa mostra
somente conexões que enviaram posição; ao desconectar, o marcador sai. Posições
sem atualização recente aparecem em vermelho.

## Autorizar uma conta

Use uma conta existente do Radio PX. Obtenha seu UUID no campo `user.id` da resposta de login ou consulte o banco:

```sql
SELECT id, username FROM users ORDER BY created_at;
```

Defina `ADMIN_USER_IDS` no ambiente do backend com os UUIDs autorizados, separados por vírgula. No Docker Compose, adicione a variável ao arquivo `.env` local:

```dotenv
ADMIN_USER_IDS=UUID_DA_SUA_CONTA
```

Reinicie o backend após configurar. Sem essa variável, apenas contas com
`role=admin` têm acesso. Usuários comuns recebem HTTP 403 nas rotas
`/api/v1/admin/*`. As senhas e seus hashes nunca fazem parte das respostas
administrativas.

A sessão (access/refresh token) é guardada no `localStorage` do navegador e
renovada automaticamente, então recarregar a página mantém o login. As métricas
contam registros do banco, não presença em tempo real.
