// lib/core/user/user_profile_state.dart
// Stato unico del profilo utente (no UI, no Firestore)

import 'user_field_definition.dart';

/// Stato immutabile del profilo utente
class UserProfileState {
  /// Valori correnti dei campi (key -> value)
  final Map<String, dynamic> values;

  /// Visibilità per campo (key -> visibility)
  final Map<String, UserFieldVisibility> visibility;

  /// Stato di caricamento
  final bool isLoading;

  /// Indica se ci sono modifiche non salvate
  final bool hasUnsavedChanges;

  const UserProfileState({
    required this.values,
    required this.visibility,
    this.isLoading = false,
    this.hasUnsavedChanges = false,
  });

  /// Stato iniziale vuoto
  factory UserProfileState.initial() {
    return const UserProfileState(
      values: {},
      visibility: {},
      isLoading: true,
      hasUnsavedChanges: false,
    );
  }

  /// Ritorna una copia aggiornata (immutabilità)
  UserProfileState copyWith({
    Map<String, dynamic>? values,
    Map<String, UserFieldVisibility>? visibility,
    bool? isLoading,
    bool? hasUnsavedChanges,
  }) {
    return UserProfileState(
      values: values ?? this.values,
      visibility: visibility ?? this.visibility,
      isLoading: isLoading ?? this.isLoading,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
    );
  }

  /// Aggiorna il valore di un campo
  UserProfileState updateFieldValue(String key, dynamic value) {
    final newValues = Map<String, dynamic>.from(values);
    newValues[key] = value;

    return copyWith(
      values: newValues,
      hasUnsavedChanges: true,
    );
  }

  /// Aggiorna la visibilità di un campo
  UserProfileState updateFieldVisibility(
      String key,
      UserFieldVisibility newVisibility,
      ) {
    final newVisibilityMap =
    Map<String, UserFieldVisibility>.from(visibility);
    newVisibilityMap[key] = newVisibility;

    return copyWith(
      visibility: newVisibilityMap,
      hasUnsavedChanges: true,
    );
  }

  /// Legge un valore campo in modo sicuro
  dynamic getValue(String key) => values[key];

  /// Legge la visibilità effettiva di un campo
  UserFieldVisibility getVisibility(String key) {
    return visibility[key] ??
        getFieldByKey(key)?.defaultVisibility ??
        UserFieldVisibility.private;
  }
}
