class Category {
  final String id;
  final String name;
  final String? description;
  final String color; // Couleur hexadécimale pour l'affichage
  final int order; // Ordre d'affichage

  Category({
    required this.id,
    required this.name,
    this.description,
    required this.color,
    required this.order,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'order_index': order,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      color: map['color'] ?? '#6366F1', // Couleur par défaut
      order: map['order_index'] ?? 0,
    );
  }

  factory Category.empty() =>
      Category(id: '', name: '', description: '', color: '#6366F1', order: 0);

  Category copyWith({
    String? id,
    String? name,
    String? description,
    String? color,
    int? order,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      order: order ?? this.order,
    );
  }
}
