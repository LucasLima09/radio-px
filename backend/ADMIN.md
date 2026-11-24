# Painel admin

O painel é a aplicação Vue 3 em `admin_vue`. Ela é compilada para
`internal/infrastructure/http/adminui/dist` e embutida no binário Go via
`//go:embed`, sendo servida em `http://localhost:8080/admin` (e também na rede
local, ex.: `http://<ip>:8080/admin`), sem precisar de servidor de frontend
separado. É o painel principal de administração.

## Como recompilar o painel

Sempre que algo em `admin_vue` mudar, gere o build antes de compilar o backend:

```bash
cd admin_vue
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
- **Histórico de posições**: registros de posição filtráveis por motorista, via `/api/v1/admin/locations/history`.

Todas as rotas `/api/v1/admin/*` exigem login administrativo e aceitam
administradores por `role=admin` ou pelos UUIDs configurados em `ADMIN_USER_IDS`.

## Mapa dos motoristas

O mapa usa a biblioteca Leaflet empacotada pelo próprio bundle do painel; as imagens
do mapa vêm do OpenStreetMap e exigem conexão com a internet. A licença está em
`admin_vue/public/LEAFLET-LICENSE.txt` (servida em `/admin/LEAFLET-LICENSE.txt`).

A posição vem do Orbit, não do celular: ele transmite por BLE um sinal assinado
com id, hora e localização; o app de quem passa perto confere a assinatura e
repassa à central, que confere de novo. Posições sem atualização recente aparecem
em vermelho.

## Orbits

Não há cadastro: o primeiro sinal válido cria o Orbit. Na tela **Orbits** dá para
renomear e desativar (um Orbit excluído reaparece se voltar a transmitir).

A central precisa da chave pública dos Orbits em `ORBIT_PUBLIC_KEY`. A chave
privada fica só nos Orbits. Para simular um no Linux:

```sh
make orbit-sim
./bin/orbit-sim                          # mostra a chave pública e transmite
./bin/orbit-sim -lat -28.45 -lng -52.19  # em outra posição
./bin/orbit-sim -forge                   # assinatura falsa: o app deve ignorar
```

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
