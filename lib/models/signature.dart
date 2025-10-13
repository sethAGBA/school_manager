class Signature {
  final String id;
  final String name;
  final String type; // 'signature' ou 'cachet'
  final String? imagePath; // Chemin vers l'image de la signature/cachet
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Signature({
    required this.id,
    required this.name,
    required this.type,
    this.imagePath,
    this.description,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'imagePath': imagePath,
      'description': description,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Signature.fromMap(Map<String, dynamic> map) {
    return Signature(
      id: map['id'],
      name: map['name'],
      type: map['type'],
      imagePath: map['imagePath'],
      description: map['description'],
      isActive: (map['isActive'] as int) == 1,
      createdAt: DateTime.parse(map['createdAt']),
      updatedAt: DateTime.parse(map['updatedAt']),
    );
  }

  Signature copyWith({
    String? id,
    String? name,
    String? type,
    String? imagePath,
    String? description,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Signature(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      imagePath: imagePath ?? this.imagePath,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Signature.empty() => Signature(
    id: '',
    name: '',
    type: 'signature',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}