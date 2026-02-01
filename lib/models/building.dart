class Building {
  final String id;
  final String name;
  final int capacity;

  Building({
    required this.id,
    required this.name,
    required this.capacity,
  });

  factory Building.fromFirestore(String id, Map<String, dynamic> data) {
    return Building(
      id: id,
      name: data['name'] ?? '',
      capacity: (data['capacity'] ?? 0) as int,
    );
  }
}
