# Radio PX local

Inicie com `powershell -ExecutionPolicy Bypass -File .\iniciar.ps1`.
O computador precisa permanecer ligado e conectado a mesma rede do celular.

- Painel no computador: http://localhost:8080/admin
- Painel na rede: http://192.168.1.101:8080/admin
- APK: http://192.168.1.101:8080/downloads/radio-px.apk
- Arquivo do APK: `dist/radio-px.apk`

As credenciais iniciais foram entregues na conversa. O aplicativo permite
cadastrar outras contas. Somente a conta configurada em
`.runtime/settings.json`, campo `ADMIN_USER_IDS`, tem acesso ao painel.

O APK usa `http://192.168.1.101:8080` como servidor inicial. Se o IP do
computador mudar, ajuste o servidor nas configuracoes do aplicativo.
Este acesso e local; nao foi publicado na internet.

Se o firewall bloquear o celular, execute em PowerShell como administrador:

```powershell
New-NetFirewallRule -DisplayName 'Radio PX API local' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8080 -RemoteAddress LocalSubnet
```

O banco exclusivo do projeto fica em `.runtime/pgdata`, na porta 55432,
acessivel apenas por este computador. Os logs ficam em `.runtime`.
Mantenha essa pasta para preservar contas, canais e configuracoes.

Para recompilar com Flutter e SDK Android configurados:

```powershell
cd front_mobile
flutter pub get
flutter build apk --release --dart-define=SERVER_URL=http://192.168.1.101:8080
```

Esta compilacao usa a assinatura de desenvolvimento definida no projeto,
adequada para instalacao direta. Uma publicacao em loja exige assinatura propria.
