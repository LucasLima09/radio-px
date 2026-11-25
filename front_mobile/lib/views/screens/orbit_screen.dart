import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../controllers/orbit_controller.dart';
import '../../models/orbit_encounter.dart';
import '../../theme/app_colors.dart';

/// Encontro com os Orbits via Bluetooth. A detecção é automática: aqui só se
/// acompanha o que foi ouvido e enviado.
class OrbitScreen extends StatelessWidget {
  const OrbitScreen({super.key, required this.controller});

  final OrbitController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => RefreshIndicator(
        onRefresh: controller.load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: controller.isSupported
                      ? _content(context)
                      : const [
                          _Notice(
                            icon: Icons.bluetooth_disabled,
                            text:
                                'Bluetooth indisponível aqui. No navegador, '
                                'use o Chrome em localhost ou HTTPS.',
                          ),
                        ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    if (!controller.isReady && !controller.isWatching) {
      return const [Center(child: CircularProgressIndicator())];
    }
    final sightings = controller.sightings;
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    return [
      _StatusCard(controller: controller),
      if (kIsWeb) ...[
        const SizedBox(height: 16),
        _Notice(
          icon: Icons.info_outline,
          text: controller.canWatch
              ? 'No navegador a busca começa no primeiro toque em qualquer '
                    'lugar do app. Autorize o Bluetooth quando o Chrome pedir.'
              : 'Detecção indisponível: rode o Chrome com '
                    '--enable-experimental-web-platform-features.',
        ),
      ],
      if (controller.error != null) ...[
        const SizedBox(height: 16),
        Text(controller.error!, style: const TextStyle(color: pxDanger)),
      ],
      if (controller.sendError != null) ...[
        const SizedBox(height: 16),
        Text(
          'Último envio: ${controller.sendError}',
          style: const TextStyle(color: pxDanger),
        ),
      ],
      if (controller.isDeaf) ...[
        const SizedBox(height: 16),
        const _Notice(
          icon: Icons.bluetooth_disabled,
          text:
              'Nenhum sinal Bluetooth ouvido até agora. Confira se o '
              'Bluetooth está ligado e se o Radio PX tem permissão de '
              'Bluetooth nos ajustes do aparelho.',
        ),
      ],
      const SizedBox(height: 32),
      Text('Orbits por perto', style: titleStyle),
      const SizedBox(height: 8),
      if (sightings.isEmpty)
        const Text(
          'Nenhum Orbit ouvido nesta sessão.',
          style: TextStyle(color: pxMuted),
        )
      else
        for (final s in sightings)
          _OrbitTile(name: controller.nameOf(s.signal), sighting: s),
      const SizedBox(height: 32),
      Text('Envios recentes', style: titleStyle),
      const SizedBox(height: 8),
      if (controller.encounters.isEmpty)
        const Text('Nenhum encontro ainda.', style: TextStyle(color: pxMuted))
      else
        for (final e in controller.encounters)
          _EncounterTile(name: controller.nameOf(e.signal), encounter: e),
      const SizedBox(height: 32),
      Row(
        children: [
          Expanded(child: Text('Detecção ao vivo', style: titleStyle)),
          TextButton(
            onPressed: controller.logs.isEmpty ? null : controller.clearLogs,
            child: const Text('Limpar'),
          ),
        ],
      ),
      if (controller.logs.isEmpty)
        const Text('Nada ainda.', style: TextStyle(color: pxMuted))
      else
        for (final l in controller.logs)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${_time(l.at)}  ${l.message}',
              style: const TextStyle(color: pxMuted, fontSize: 13),
            ),
          ),
    ];
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final OrbitController controller;

  @override
  Widget build(BuildContext context) {
    final watching = controller.isWatching;
    return Card(
      color: pxCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: pxBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  watching ? Icons.bluetooth_connected : Icons.bluetooth,
                  color: watching ? pxOnline : pxAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    watching
                        ? 'Procurando Orbits por perto'
                        : 'Detecção parada',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (controller.isSending)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _line('Servidor', controller.api.baseUrl),
            _line(
              'Chave dos Orbits',
              controller.hasKey ? 'carregada' : 'não carregada',
            ),
            _line('Sinais BLE ouvidos', '${controller.heardCount}'),
            _line('No formato Orbit', '${controller.fragmentCount}'),
            _line('Assinatura válida', '${controller.validCount}'),
            _line('Recusados', '${controller.rejectedCount}'),
            _line(
              'Regra',
              '1 envio por Orbit a cada '
                  '${OrbitController.cooldown.inSeconds} s',
            ),
            if (controller.pendingCount > 0)
              _line(
                'Fila',
                '${controller.pendingCount} '
                    '${controller.pendingCount == 1 ? 'encontro guardado' : 'encontros guardados'}'
                    '${controller.isOffline ? ', aguardando internet' : ', enviando'}',
              ),
          ],
        ),
      ),
    );
  }
}

class _OrbitTile extends StatelessWidget {
  const _OrbitTile({required this.name, required this.sighting});

  final String name;
  final OrbitSighting sighting;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.sensors, color: pxOnline),
      title: Text(name),
      subtitle: Text(
        '${sighting.signal.identifier} · ${_coords(sighting.signal)}\n'
        'último sinal ${_time(sighting.at)}${_dbm(sighting.rssi)}',
      ),
    );
  }
}

class _EncounterTile extends StatelessWidget {
  const _EncounterTile({required this.name, required this.encounter});

  final String name;
  final OrbitEncounter encounter;

  @override
  Widget build(BuildContext context) {
    final e = encounter;
    final details = '${_time(e.at)} · ${_coords(e.signal)}${_dbm(e.rssi)}';
    final (icon, color, subtitle) = switch (e.status) {
      EncounterStatus.sent => (Icons.check_circle_outline, pxSuccess, details),
      EncounterStatus.queued => (
        Icons.schedule,
        pxMuted,
        '$details · na fila, envia quando houver internet',
      ),
      EncounterStatus.failed => (
        Icons.error_outline,
        pxDanger,
        '${_time(e.at)} · ${e.error}',
      ),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(name),
      subtitle: Text(subtitle),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: pxMuted, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: pxMuted)),
        ),
      ],
    );
  }
}

Widget _line(String label, String value) => Padding(
  padding: const EdgeInsets.only(top: 4),
  child: Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label: ',
          style: const TextStyle(color: pxMuted),
        ),
        TextSpan(text: value),
      ],
    ),
  ),
);

String _coords(OrbitSignal s) =>
    '${s.lat.toStringAsFixed(5)}, ${s.lng.toStringAsFixed(5)}';

String _dbm(int? rssi) => rssi == null ? '' : ' · $rssi dBm';

String _time(DateTime utcOrLocal) {
  final at = utcOrLocal.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(at.day)}/${two(at.month)} '
      '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
}
