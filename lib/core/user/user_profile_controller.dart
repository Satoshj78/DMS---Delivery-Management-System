// lib/core/user/user_profile_controller.dart
// Controller del profilo utente: logica business + orchestrazione

import 'package:flutter/foundation.dart';

import 'user_profile_state.dart';
import 'user_field_definition.dart';

/// Controller del profilo utente
/// - NON contiene UI
/// - NON usa setState
/// - coordina carico / modifica / salvataggio
class UserProfileController extends ChangeNotifier {
  UserProfileState _state = UserProfileState.initial();

  UserProfileState get state => _state;

  /// ----------------------------
  /// LOAD
  /// ----------------------------

  /// Inizializza lo stato a partire dai dati Firestore
  /// [userData] = mappa raw (Users / Members)
  /// [visibilityData] = visibilità per campo (se presente)
  void loadFromData({
    required Map<String, dynamic> userData,
    Map<String, UserFieldVisibility>? visibilityData,
  }) {
    _state = UserProfileState(
      values: Map<String, dynamic>.from(userData),
      visibility: visibilityData ?? {},
      isLoading: false,
      hasUnsavedChanges: false,
    );
    notifyListeners();
  }

  /// ----------------------------
  /// UPDATE
  /// ----------------------------

  void updateField(String key, dynamic value) {
    final def = getFieldByKey(key);
    if (def == null || !def.editable) return;

    _state = _state.updateFieldValue(key, value);
    notifyListeners();
  }

  void updateVisibility(String key, UserFieldVisibility visibility) {
    _state = _state.updateFieldVisibility(key, visibility);
    notifyListeners();
  }

  /// ----------------------------
  /// VALIDATION
  /// ----------------------------

  bool validate() {
    for (final field in userFieldDefinitions) {
      if (field.required) {
        final value = _state.values[field.key];
        if (value == null || value.toString().trim().isEmpty) {
          return false;
        }
      }
    }
    return true;
  }

  /// ----------------------------
  /// SAVE
  /// ----------------------------

  /// Prepara i dati da salvare (non scrive ancora su Firestore)
  Map<String, dynamic> buildSavePayload() {
    final Map<String, dynamic> payload = {};

    for (final entry in _state.values.entries) {
      payload[entry.key] = entry.value;
    }

    return payload;
  }

  /// Prepara la mappa delle visibilità
  Map<String, String> buildVisibilityPayload() {
    final Map<String, String> payload = {};

    for (final entry in _state.visibility.entries) {
      payload[entry.key] = entry.value.name;
    }

    return payload;
  }

  /// Segna come salvato (dopo successo Firestore)
  void markSaved() {
    _state = _state.copyWith(hasUnsavedChanges: false);
    notifyListeners();
  }
}
