class LocationConfig {
  const LocationConfig({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.active,
  });

  final String id;
  final String code;
  final String name;
  final String type;
  final bool active;

  factory LocationConfig.fromJson(Map<String, dynamic> json) {
    return LocationConfig(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      type: json['type'] as String? ?? 'Area',
      active: json['active'] as bool? ?? true,
    );
  }
}

class MachineConfig {
  const MachineConfig({
    required this.id,
    required this.code,
    required this.name,
    required this.active,
  });

  final String id;
  final String code;
  final String name;
  final bool active;

  factory MachineConfig.fromJson(Map<String, dynamic> json) {
    return MachineConfig(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      active: json['active'] as bool? ?? true,
    );
  }
}

class LineConfig {
  const LineConfig({
    required this.id,
    required this.code,
    required this.name,
    required this.machineId,
    required this.active,
  });

  final String id;
  final String code;
  final String name;
  final String machineId;
  final bool active;

  factory LineConfig.fromJson(Map<String, dynamic> json) {
    return LineConfig(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      machineId: json['machineId'] as String,
      active: json['active'] as bool? ?? true,
    );
  }
}
