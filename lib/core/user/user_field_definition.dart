// lib/core/user/user_field_definition.dart
// Catalogo centrale dei campi utente (HR-ready)

enum UserFieldType {
  text,
  multiline,
  date,
  number,
  email,
  phone,
  image,
  file,
}

enum UserFieldVisibility {
  private,
  shared,
  public,
}

/// Definizione descrittiva di un campo utente
class UserFieldDefinition {
  final String key;
  final String label;
  final UserFieldType type;

  /// Categoria logica (Anagrafica, Contatti, Documenti, HR, ecc.)
  final String category;

  /// Visibilità di default
  final UserFieldVisibility defaultVisibility;

  /// Campo obbligatorio
  final bool required;

  /// Può essere modificato dall’utente
  final bool editable;

  /// Suggerimento UI (placeholder / hint)
  final String? hint;

  /// Ordine di visualizzazione nella categoria
  final int order;

  const UserFieldDefinition({
    required this.key,
    required this.label,
    required this.type,
    required this.category,
    required this.defaultVisibility,
    this.required = false,
    this.editable = true,
    this.hint,
    this.order = 0,
  });
}

/// ===============================
/// CATALOGO CAMPI UTENTE
/// ===============================
///
/// Tutti i campi del profilo utente DEVONO stare qui.
/// La UI legge questo elenco e si costruisce da sola.
final List<UserFieldDefinition> userFieldDefinitions = [
  // ----------------------------
  // ANAGRAFICA
  // ----------------------------
  UserFieldDefinition(
    key: 'lastName',
    label: 'Cognome',
    type: UserFieldType.text,
    category: 'Anagrafica',
    defaultVisibility: UserFieldVisibility.public,
    required: true,
    order: 2,
  ),
  UserFieldDefinition(
    key: 'firstName',
    label: 'Nome',
    type: UserFieldType.text,
    category: 'Anagrafica',
    defaultVisibility: UserFieldVisibility.public,
    required: true,
    order: 1,
  ),
  UserFieldDefinition(
    key: 'nickname',
    label: 'Nickname',
    type: UserFieldType.text,
    category: 'Anagrafica',
    defaultVisibility: UserFieldVisibility.public,
    order: 3,
  ),
  UserFieldDefinition(
    key: 'birthDate',
    label: 'Data di nascita',
    type: UserFieldType.date,
    category: 'Anagrafica',
    defaultVisibility: UserFieldVisibility.private,
    order: 4,
  ),

  // ----------------------------
  // CONTATTI
  // ----------------------------
  UserFieldDefinition(
    key: 'email',
    label: 'Email',
    type: UserFieldType.email,
    category: 'Contatti',
    defaultVisibility: UserFieldVisibility.shared,
    editable: false,
    order: 1,
  ),
  UserFieldDefinition(
    key: 'phone',
    label: 'Telefono',
    type: UserFieldType.phone,
    category: 'Contatti',
    defaultVisibility: UserFieldVisibility.shared,
    order: 2,
  ),

  // ----------------------------
  // DOCUMENTI
  // ----------------------------
  UserFieldDefinition(
    key: 'profilePhoto',
    label: 'Foto profilo',
    type: UserFieldType.image,
    category: 'Documenti',
    defaultVisibility: UserFieldVisibility.public,
    editable: true,
    order: 1,
  ),
  UserFieldDefinition(
    key: 'idDocument',
    label: 'Documento di identità',
    type: UserFieldType.file,
    category: 'Documenti',
    defaultVisibility: UserFieldVisibility.private,
    order: 2,
  ),

  // ----------------------------
  // NOTE / HR
  // ----------------------------
  UserFieldDefinition(
    key: 'notes',
    label: 'Note',
    type: UserFieldType.multiline,
    category: 'HR',
    defaultVisibility: UserFieldVisibility.private,
    order: 1,
  ),
];

/// ===============================
/// HELPERS
/// ===============================

/// Ritorna tutte le categorie presenti
List<String> getUserFieldCategories() {
  return userFieldDefinitions
      .map((e) => e.category)
      .toSet()
      .toList();
}

/// Ritorna i campi di una categoria, ordinati
List<UserFieldDefinition> getFieldsByCategory(String category) {
  return userFieldDefinitions
      .where((f) => f.category == category)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));
}

/// Lookup rapido per key
UserFieldDefinition? getFieldByKey(String key) {
  try {
    return userFieldDefinitions.firstWhere((f) => f.key == key);
  } catch (_) {
    return null;
  }
}
