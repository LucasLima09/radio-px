# front_mobile

## Fluxo do Radio PX

- Login validado pelo servidor antes de abrir os canais.
- Lista de canais com criação, atualização e entrada no canal escolhido.
- Dentro do canal: participantes conectados, quem está gravando e quem está
  sendo ouvido, além do número de falas aguardando reprodução neste aparelho.
- A fala em reprodução aparece separada e não entra no contador da fila.
- Segure o botão para falar e solte para enviar; o menu também permite usar
  toque para iniciar e encerrar a gravação.

O endereço definido por `--dart-define=SERVER_URL=...` é aplicado uma vez ao
instalar uma compilação com um novo servidor. Depois disso, o campo
**Configurar servidor** permite alterar o endereço manualmente.

## Arquitetura

O app segue MVC com camadas explícitas. A regra de dependência é sempre
**views → controllers → services → models**: nada sobe na hierarquia.

```
lib/
├── main.dart            Bootstrap: liga as dependências e sobe o app.
├── app.dart             MaterialApp, tema e ciclo de vida.
├── routes.dart          Tabela de rotas e seus argumentos.
├── di.dart              AppDependencies (o que existe desde o boot) + AppScope.
├── models/              Dados puros. Não conhecem Flutter nem HTTP.
├── services/            Efeitos colaterais: HTTP, disco, socket, áudio, GPS.
├── controllers/         Estado das telas + regras de negócio.
├── views/               Widgets. Desenham e repassam comandos.
└── theme/               Cores e tema do Material.
```

### models/

Entidades serializáveis, uma por arquivo. `active_session.dart` é a exceção:
agrega o `ApiClient` já apontado para o servidor escolhido e o usuário
autenticado — é o que a tela de login entrega para o resto do app.

### services/

| Pasta | Responsabilidade |
| --- | --- |
| `api/` | Cliente HTTP e o ciclo de vida do token de acesso. |
| `storage/` | Preferências do aparelho: servidor, modo de gravação, cursor de áudio e sessão salva. |
| `platform/` | Ponte por plataforma (áudio e WebSocket), com variantes `io`/`web`/`stub`. |
| `location/` | Rastreio de GPS com `distanceFilter` e heartbeat. |
| `beacon/` | Serviço de foreground e o handler executado em isolado próprio. |
| `radio/` | O núcleo do canal, dividido em quatro peças. |

O `radio/` é a parte que era um único arquivo:

- `playback_cursor.dart` — até onde este aparelho já ouviu (`last_heard_seq`).
- `radio_channel.dart` — WebSocket: handshake, reconexão, presença e montagem
  dos clipes recebidos. Emite `RadioEvent`.
- `clip_recorder.dart` — grava a fala e envia para o canal.
- `playback_queue.dart` — fila e reprodução local dos clipes.

Os quatro não se conhecem: quem os costura é o `RoomController`, que também
decide o que fazer quando chega um `recording_stop` do servidor.

### controllers/

Cada controller é um `ChangeNotifier`. A tela observa com `ListenableBuilder`
e manda comandos de volta. `TextEditingController` e o `MapController` ficam
nas Views: eles são estado de widget, não de negócio.

`app_controller.dart` é a base de todos: ela ignora o `notifyListeners()`
quando a tela já saiu e a requisição ainda está em andamento.

| Controller | Tela |
| --- | --- |
| `auth_controller.dart` | Login e registro. |
| `channel_list_controller.dart` | Lista de canais. |
| `profile_controller.dart` | Perfil. |
| `room_controller.dart` | Sala. |

### views/

- `views/screens/` — uma tela por arquivo, sem lógica de negócio.
- `views/widgets/` — widgets reaproveitados, que recebem dados prontos em vez
  de controllers.

## Contratos que não devem quebrar

- **Chaves de SharedPreferences**: `server_url`, `compiled_server_url`,
  `record_mode`, `last_heard_<channelId>`, `auth_session`.
- **Handshake do WebSocket**: `token`, `channel_id`, `last_heard_seq`.
- **Protocolo**: `recording_start`, `recording_stop`, `clip_start`, `clip_end`,
  `location`, `leave`.
- **Entry point do beacon**: `beaconCallback` precisa continuar sendo uma
  função top-level com `@pragma('vm:entry-point')`, e a cadeia de imports até
  `beacon_task.dart` precisa continuar viva para o/tree-shaker.

## Testes

Os testes espelham `lib/`:

```
test/
├── services/   Armazenamento e API.
└── views/      Widgets.
```

```bash
flutter analyze   # deve terminar sem nenhum aviso
flutter test
flutter build apk --debug
flutter build web
```
