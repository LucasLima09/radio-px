import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../controllers/orbit_controller.dart';
import '../../models/orbit_encounter.dart';
import '../../theme/app_colors.dart';

/// Encontro com os Orbits via Bluetooth. A lista vem do painel admin: aqui só
/// se liga a detecção e se acompanham os envios.
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
    final orbits = controller.orbits;
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    if (orbits == null) {
      return const [Center(child: CircularProgressIndicator())];
    }
    final hasOrbits = orbits.isNotEmpty;
    return [
      _StatusCard(controller: controller),
      const SizedBox(height: 16),
      if (controller.isAlwaysOn)
        kIsWeb
            ? const _Notice(
                icon: Icons.info_outline,
                text:
                    'No navegador a busca começa no primeiro toque em qualquer '
                    'lugar do app. Autorize o Bluetooth quando o Chrome pedir.',
              )
            : const SizedBox.shrink()
      else if (controller.canWatch)
        FilledButton.icon(
          onPressed: !hasOrbits
              ? null
              : controller.isWatching
              ? controller.stopWatching
              : controller.startWatching,
          icon: Icon(
            controller.isWatching ? Icons.pause : Icons.bluetooth_searching,
          ),
          label: Text(
            controller.isWatching ? 'Parar detecção' : 'Ativar detecção',
          ),
        )
      else ...[
        FilledButton.icon(
          onPressed: !hasOrbits || controller.isScanning
              ? null
              : controller.scanOnce,
          icon: const Icon(Icons.bluetooth_searching),
          label: Text(
            controller.isScanning ? 'Procurando...' : 'Escanear Orbits',
          ),
        ),
        const SizedBox(height: 16),
        const _Notice(
          icon: Icons.info_outline,
          text:
              'Detecção automática indisponível: rode o Chrome com '
              '--enable-experimental-web-platform-features. Até lá, cada '
              '"Escanear" em que você escolhe um Orbit conta como um encontro.',
        ),
      ],
      if (controller.error != null) ...[
        const SizedBox(height: 16),
        Text(controller.error!, style: const TextStyle(color: pxDanger)),
      ],
      const SizedBox(height: 32),
      Row(
        children: [
          Expanded(child: Text('Orbits cadastrados', style: titleStyle)),
          IconButton(
            tooltip: 'Recarregar lista',
            onPressed: controller.isLoading ? null : controller.load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (!hasOrbits)
        const Text(
          'Nenhum Orbit cadastrado. Peça ao admin para cadastrar no painel.',
          style: TextStyle(color: pxMuted),
        )
      else
        for (final o in orbits) _OrbitTile(controller: controller, orbit: o),
      const SizedBox(height: 32),
      Text('Envios recentes', style: titleStyle),
      const SizedBox(height: 8),
      if (controller.encounters.isEmpty)
        const Text('Nenhum encontro ainda.', style: TextStyle(color: pxMuted))
      else
        for (final e in controller.encounters) _EncounterTile(encounter: e),
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
            _line(
              'Modo',
              controller.isAlwaysOn
                  ? 'sempre ligado'
                  : controller.canWatch
                  ? 'automático (ativado por clique)'
                  : 'manual (botão Escanear)',
            ),
            _line(
              'Regra',
              'sinal ≥ ${OrbitController.rssiThreshold} dBm, '
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
  const _OrbitTile({required this.controller, required this.orbit});

  final OrbitController controller;
  final RegisteredOrbit orbit;

  @override
  Widget build(BuildContext context) {
    final sighting = controller.lastSightingOf(orbit);
    final signal = sighting == null
        ? 'sem sinal nesta sessão'
        : 'último sinal ${_time(sighting.at)}'
              '${sighting.rssi == null ? '' : ' · ${sighting.rssi} dBm'}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.sensors,
        color: sighting == null ? pxMuted : pxOnline,
      ),
      title: Text(orbit.name),
      subtitle: Text('${orbit.identifier} · $signal'),
    );
  }
}

class _EncounterTile extends StatelessWidget {
  const _EncounterTile({required this.encounter});

  final OrbitEncounter encounter;

  @override
  Widget build(BuildContext context) {
    final e = encounter;
    final coords = e.lat == null
        ? ''
        : ' · ${e.lat!.toStringAsFixed(5)}, ${e.lng!.toStringAsFixed(5)}';
    final details =
        '${_time(e.at)}$coords${e.rssi == null ? '' : ' · ${e.rssi} dBm'}';
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
      title: Text(e.orbit.name),
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

String _time(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(at.day)}/${two(at.month)} '
      '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
}
