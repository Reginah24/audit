class Employee {
  final String id;
  final String name;
  final String department;
  final String? pin;

  Employee({
    required this.id,
    required this.name,
    required this.department,
    this.pin,
  });

  factory Employee.fromFirestore(String id, Map<String, dynamic> data) {
    return Employee(
      id: id,
      name: (data['name'] ?? '').toString(),
      department: (data['department'] ?? '').toString(),
      pin: data['pin'] as String?,
    );
  }
}
