# Painel admin

## Mapa dos motoristas

O mapa aparece acima das listas, com nome do motorista, canal e horário da
última posição. O painel consulta `/api/v1/admin/locations` a cada 2 segundos
(a cada 10 segundos quando a aba está em segundo plano). A rota exige login
administrativo e não permite cache.

O aplicativo já envia GPS ao entrar em um canal, com permissão de localização:
ao se mover cerca de 10 metros e a cada 30 segundos quando parado. O mapa
mostra somente conexões que enviaram posição; ao desconectar, o marcador sai.
Posições com mais de 90 segundos ficam amarelas. Se uma conta estiver em
vários aparelhos ou canais, aparece somente sua posição mais recente.

Clique no motorista para aproximar o mapa ou em **Ver todos** para enquadrar
a frota. Sem motoristas, o painel mostra uma orientação para habilitar o GPS.
A biblioteca Leaflet está incorporada ao backend; as imagens do mapa vêm do
OpenStreetMap e exigem conexão com a internet. A licença está em
`internal/infrastructure/http/adminui/LEAFLET-LICENSE.txt`.

O backend serve o painel em `http://localhost:8080/admin`, sem instalação de frontend separada. Os arquivos estão incorporados ao binário Go.

Funções: consultar totais, buscar usuários, buscar canais e excluir canais. A exclusão exige confirmação e é bloqueada enquanto houver participantes conectados. As listas têm paginação de 20 registros.

## Autorizar uma conta

Use uma conta existente do Radio PX. Obtenha seu UUID no campo `user.id` da resposta de login ou consulte o banco:

```sql
SELECT id, username FROM users ORDER BY created_at;
```

Defina `ADMIN_USER_IDS` no ambiente do backend com os UUIDs autorizados, separados por vírgula. No Docker Compose, adicione a variável ao arquivo `.env` local:

```dotenv
ADMIN_USER_IDS=UUID_DA_SUA_CONTA
```

Reinicie o backend após configurar. O painel usa o login e a renovação de sessão já existentes. Sem essa variável, nenhuma conta tem acesso administrativo. Usuários comuns recebem HTTP 403 nas rotas `/api/v1/admin/*`. As senhas e seus hashes nunca fazem parte das respostas administrativas.

Os tokens ficam apenas na memória da página: recarregar ou fechar a aba exige um novo login. As métricas contam registros do banco, não presença em tempo real. A exclusão remove também os vínculos e localizações associados ao canal; usuários não são excluídos.
