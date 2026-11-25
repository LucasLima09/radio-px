import 'dart:convert';
import 'dart:typed_data';

/// Um anúncio BLE qualquer, de qualquer aparelho, com os dados de fabricante
/// do company id usado pelos Orbits.
class OrbitAdvertisement {
  const OrbitAdvertisement({required this.data, required this.at, this.rssi});

  final List<int> data;
  final DateTime at;

  /// Intensidade do sinal em dBm; nulo quando o navegador não informa.
  final int? rssi;
}

/// Conteúdo do sinal de um Orbit: tudo aqui veio do próprio dispositivo.
///
/// `id(8) | hora unix em s(4) | lat×1e7(4) | lng×1e7(4) | assinatura(64)`, em
/// big-endian. O mesmo formato está em `signal.go`, no backend.
class OrbitSignal {
  OrbitSignal._({
    required this.raw,
    required this.identifier,
    required this.at,
    required this.lat,
    required this.lng,
  });

  /// Lê o sinal sem conferir a assinatura (isso é do `OrbitDecoder`).
  factory OrbitSignal.parse(List<int> bytes) {
    if (bytes.length != size) {
      throw const FormatException('sinal de Orbit com tamanho inválido');
    }
    final raw = Uint8List.fromList(bytes);
    final data = ByteData.sublistView(raw);
    return OrbitSignal._(
      raw: raw,
      identifier: [
        for (final b in raw.sublist(0, 8)) b.toRadixString(16).padLeft(2, '0'),
      ].join().toUpperCase(),
      at: DateTime.fromMillisecondsSinceEpoch(
        data.getUint32(8) * 1000,
        isUtc: true,
      ),
      lat: data.getInt32(12) / 1e7,
      lng: data.getInt32(16) / 1e7,
    );
  }

  static const bodySize = 20;
  static const size = bodySize + 64;

  /// Os bytes como transmitidos; é isso que vai para a central.
  final Uint8List raw;
  final String identifier;
  final DateTime at;
  final double lat;
  final double lng;

  String get base64 => base64Encode(raw);
}

/// Um sinal com assinatura conferida.
class OrbitSighting {
  const OrbitSighting({required this.signal, required this.at, this.rssi});

  final OrbitSignal signal;

  /// Hora em que o app ouviu o sinal.
  final DateTime at;
  final int? rssi;
}

/// O que o app precisa do servidor para reconhecer os Orbits.
class OrbitConfig {
  const OrbitConfig({required this.publicKey, required this.names});

  factory OrbitConfig.fromJson(Map<String, dynamic> json) => OrbitConfig(
    publicKey: base64Decode(json['publicKey'] as String? ?? ''),
    names: {
      for (final o in (json['orbits'] as List? ?? const []))
        (o as Map<String, dynamic>)['identifier'] as String:
            o['name'] as String,
    },
  );

  /// Chave pública Ed25519; vazia se o servidor não tem uma configurada.
  final List<int> publicKey;

  /// Nome de cada Orbit conhecido, só para exibição.
  final Map<String, String> names;
}

enum EncounterStatus {
  /// Guardado no aparelho, esperando internet para ir à central.
  queued,
  sent,

  /// Recusado de vez pela central (ex.: Orbit desativado).
  failed,
}

/// Um encontro com um Orbit. Fica guardado no aparelho até ser entregue à
/// central, para não se perder quando não há internet.
class OrbitEncounter {
  const OrbitEncounter({
    required this.id,
    required this.signal,
    required this.at,
    this.rssi,
    this.status = EncounterStatus.queued,
    this.error,
  });

  factory OrbitEncounter.fromJson(Map<String, dynamic> json) => OrbitEncounter(
    id: json['id'] as String,
    signal: OrbitSignal.parse(base64Decode(json['signal'] as String)),
    at: DateTime.parse(json['at'] as String),
    rssi: json['rssi'] as int?,
  );

  /// Gerado no aparelho; o servidor ignora um segundo envio com o mesmo id.
  final String id;
  final OrbitSignal signal;

  /// Hora em que o app ouviu o sinal (não a hora em que chegou na central).
  final DateTime at;
  final int? rssi;
  final EncounterStatus status;

  /// Motivo da falha, quando [status] é [EncounterStatus.failed].
  final String? error;

  bool get sent => status == EncounterStatus.sent;
  bool get queued => status == EncounterStatus.queued;

  OrbitEncounter withStatus(EncounterStatus status, {String? error}) =>
      OrbitEncounter(
        id: id,
        signal: signal,
        at: at,
        rssi: rssi,
        status: status,
        error: error,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'signal': signal.base64,
    'at': at.toUtc().toIso8601String(),
    'rssi': ?rssi,
  };
}

/// Linha do diagnóstico na tela do Orbit.
class OrbitLog {
  const OrbitLog(this.at, this.message);

  final DateTime at;
  final String message;
}
