# Painel admin

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
