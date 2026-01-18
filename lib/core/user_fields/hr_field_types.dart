// lib/core/user_fields/hr_field_types.dart
// Definizioni base dei tipi di campo HR

enum HrFieldType {
  text,
  multiline,
  date,
  number,
  money,
  select,
  boolean,
  file,
  address,
}

enum HrTarget {
  user,   // Users/{uid}
  member, // Leagues/{leagueId}/members/{uid}
}

class HrField {
  final String key;
  final String label;
  final String category;
  final HrFieldType type;
  final HrTarget target;

  final bool required;
  final bool sensitive;
  final List<String>? options;

  const HrField({
    required this.key,
    required this.label,
    required this.category,
    required this.type,
    required this.target,
    this.required = false,
    this.sensitive = false,
    this.options,
  });
}
