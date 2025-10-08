class Course {
  final String id;
  final String name;
  final String? description;
  final String? categoryId; // Référence vers la catégorie

  Course({
    required this.id,
    required this.name,
    this.description,
    this.categoryId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'categoryId': categoryId,
    };
  }

  factory Course.fromMap(Map<String, dynamic> map) {
    return Course(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      categoryId: map['categoryId'],
    );
  }

  factory Course.empty() =>
      Course(id: '', name: '', description: '', categoryId: null);

  Course copyWith({
    String? id,
    String? name,
    String? description,
    String? categoryId,
  }) {
    return Course(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
    );
  }
}
