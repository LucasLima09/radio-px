# Revisão e canais próximos

## Comportamento implementado

- Flutter consulta o GPS ao abrir a lista, atualizar ou criar um canal.
- Próximos usa raio padrão de 50 km, ajustável entre 5 e 500 km, e ordena pela menor distância.
- Atualização a cada 30 segundos enquanto a tela está visível e o aplicativo está em primeiro plano. Não há rastreamento em segundo plano.
- A referência do canal é fixa: posição de quem o criou naquele momento. A distância é em linha reta (Haversine), não por estrada nem até participantes ativos.
- Todos preserva a listagem anterior, incluindo canais antigos sem coordenadas. A criação pelo aplicativo exige localização; clientes antigos da API ainda podem criar sem coordenadas.
- Coordenadas do motorista são usadas na consulta, sem tabela de histórico. A resposta pública informa somente a distância, sem expor coordenadas do canal.

## API e banco

`POST /api/v1/channels` aceita `latitude` e `longitude` opcionais, sempre em conjunto.

`GET /api/v1/channels?latitude=-23.55&longitude=-46.63&radiusKm=50` retorna canais públicos geolocalizados dentro do raio com `distanceKm`. Sem parâmetros, mantém a listagem anterior. Coordenadas inválidas e raios fora de `(0, 500]` retornam 400.

A migração `0002_channel_location` adiciona coordenadas opcionais e restrição de validade. O servidor já executa migrações na inicialização. Dados antigos não recebem localização fictícia.

## Validação e execução

- Backend: `cd backend` e `go test ./...`.
- Flutter: `cd front_mobile`, `flutter pub get`, `dart format lib`, `flutter analyze` e `flutter test`.
- A dependência de localização segue a [documentação do Geolocator](https://pub.dev/packages/geolocator). Permissões de uso foram adicionadas para Android e iOS. No navegador, usar HTTPS ou localhost.
- Validar em aparelho: permitir/recusar GPS, GPS desligado, criação, mudança de raio, deslocamento, atualização e retorno de uma sala.
- Flutter não foi encontrado neste ambiente; análise, build e testes do aplicativo precisam ser executados em ambiente com o SDK. A migração não foi executada contra um PostgreSQL nesta revisão.

## Achados da revisão que permanecem

- `IsPrivate` não constitui controle de acesso: a listagem geral e o fluxo Join existentes permitem descobrir/entrar em canais privados. A busca próxima exclui esses canais, mas o fluxo privado completo precisa de autorização por convite.
- A listagem carrega os canais e conta membros individualmente. Para grande volume, mover o filtro geográfico e a contagem para consulta paginada com índice espacial.
- Criação do canal e inclusão do proprietário são operações separadas; uma transação evitaria canais parcialmente criados em caso de falha.
- O logger HTTP existente registra URLs; parâmetros de localização e tokens WebSocket devem ser removidos dos logs antes de usar esses logs em produção.

A base `feature/localizacao` já inclui Geolocator e seu lockfile; a integração reutiliza essa dependência e preserva o mapa dos integrantes.
