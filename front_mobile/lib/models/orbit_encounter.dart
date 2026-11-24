/// Orbit cadastrado no painel admin. Todos os apps recebem a mesma lista da
/// API, então ninguém precisa parear o dispositivo.
class RegisteredOrbit {
  const RegisteredOrbit({
    required this.id,
    required this.name,
    required this.identifier,
  });

  factory RegisteredOrbit.fromJson(Map<String, dynamic> json) =>
      RegisteredOrbit(
        id: json['id'] as String,
        name: json['name'] as String,
        identifier: json['identifier'] as String,
      );

  final String id;
  final String name;

  /// Nome que o dispositivo anuncia no Bluetooth. É por ele que o app
  /// reconhece o Orbit.
  final String identifier;
}

/// Um anúncio Bluetooth recebido de um Orbit cadastrado.
class OrbitSighting {
  const OrbitSighting({required this.orbit, required this.at, this.rssi});

  final RegisteredOrbit orbit;
  final DateTime at;

  /// Intensidade do sinal em dBm; nulo quando o navegador não informa.
  final int? rssi;
}

enum EncounterStatus {
  /// Guardado no aparelho, esperando internet para ir à central.
  queued,
  sent,

  /// Recusado de vez (ex.: Orbit desativado) ou sem localização.
  failed,
}

/// Um encontro com um Orbit. Fica guardado no aparelho até ser entregue à
/// central, para não se perder quando não há internet.
class OrbitEncounter {
  const OrbitEncounter({
    required this.id,
    required this.orbit,
    required this.at,
    this.rssi,
    this.lat,
    this.lng,
    this.status = EncounterStatus.queued,
    this.error,
  });

  factory OrbitEncounter.fromJson(Map<String, dynamic> json) => OrbitEncounter(
    id: json['id'] as String,
    orbit: RegisteredOrbit.fromJson(json['orbit'] as Map<String, dynamic>),
    at: DateTime.parse(json['at'] as String),
    rssi: json['rssi'] as int?,
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
  );

  /// Gerado no aparelho; o servidor ignora um segundo envio com o mesmo id.
  final String id;
  final RegisteredOrbit orbit;

  /// Hora do encontro no aparelho (não a hora em que chegou na central).
  final DateTime at;
  final int? rssi;
  final double? lat;
  final double? lng;
  final EncounterStatus status;

  /// Motivo da falha, quando [status] é [EncounterStatus.failed].
  final String? error;

  bool get sent => status == EncounterStatus.sent;
  bool get queued => status == EncounterStatus.queued;

  OrbitEncounter withStatus(EncounterStatus status, {String? error}) =>
      OrbitEncounter(
        id: id,
        orbit: orbit,
        at: at,
        rssi: rssi,
        lat: lat,
        lng: lng,
        status: status,
        error: error,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'orbit': {
      'id': orbit.id,
      'name': orbit.name,
      'identifier': orbit.identifier,
    },
    'at': at.toUtc().toIso8601String(),
    'rssi': ?rssi,
    'lat': ?lat,
    'lng': ?lng,
  };
}
