class InventoryItem {
  final int? id;
  final String category;
  final String name;
  final int quantity;
  final String? location;
  final String? itemCondition; // ex: Neuf, Bon, Usé, Cassé
  final double? value;
  final String? supplier;
  final String? purchaseDate; // ISO8601
  final String? className; // optionnel: rattachement à une classe
  final String academicYear;

  InventoryItem({
    this.id,
    required this.category,
    required this.name,
    required this.quantity,
    this.location,
    this.itemCondition,
    this.value,
    this.supplier,
    this.purchaseDate,
    this.className,
    required this.academicYear,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'category': category,
      'name': name,
      'quantity': quantity,
      'location': location,
      'itemCondition': itemCondition,
      'value': value,
      'supplier': supplier,
      'purchaseDate': purchaseDate,
      'className': className,
      'academicYear': academicYear,
    };
  }

  factory InventoryItem.fromMap(Map<String, dynamic> map) {
    return InventoryItem(
      id: map['id'] as int?,
      category: map['category'] ?? '',
      name: map['name'] ?? '',
      quantity: (map['quantity'] ?? 0) is int
          ? map['quantity'] as int
          : int.tryParse(map['quantity'].toString()) ?? 0,
      location: map['location'],
      itemCondition: map['itemCondition'],
      value: map['value'] == null
          ? null
          : (map['value'] is int)
              ? (map['value'] as int).toDouble()
              : (map['value'] as num).toDouble(),
      supplier: map['supplier'],
      purchaseDate: map['purchaseDate'],
      className: map['className'],
      academicYear: map['academicYear'] ?? '',
    );
  }
}

