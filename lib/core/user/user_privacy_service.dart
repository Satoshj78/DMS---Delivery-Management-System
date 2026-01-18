// lib/core/user/user_privacy_service.dart
// Gestione centralizzata della privacy e propagazione dati utente

import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_field_definition.dart';

/// Livelli di destinazione dati (dove scrivere)
enum UserPrivacyTarget {
  users,               // Users/{uid}
  usersPublic,         // UsersPublic/{uid}
  leagueMember,        // Leagues/{leagueId}/members/{uid}
  sharedProfiles,      // Users/{uid}/sharedProfiles/{target}
  sharedProfilesAll,   // Users/{uid}/sharedProfilesAll
}

/// Servizio che decide DOVE e COME salvare un campo
class UserPrivacyService {
  final FirebaseFirestore _db;

  UserPrivacyService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Applica la visibilità di un campo scrivendo nei punti corretti
  ///
  /// NOTA:
  /// - non cancella dati storici non gestiti
  /// - è pensato per convivere con la tua logica attuale
  Future<void> applyFieldVisibility({
    required String userId,
    required String leagueId,
    required String fieldKey,
    required dynamic value,
    required UserFieldVisibility visibility,
    List<String>? sharedWithUserIds,
  }) async {
    final batch = _db.batch();

    final userRef = _db.collection('Users').doc(userId);
    final memberRef = _db
        .collection('Leagues')
        .doc(leagueId)
        .collection('members')
        .doc(userId);
    final usersPublicRef = _db.collection('UsersPublic').doc(userId);

    // 1️⃣ SEMPRE: Users (profilo completo)
    batch.set(
      userRef,
      {fieldKey: value},
      SetOptions(merge: true),
    );

    // 2️⃣ VISIBILITÀ PUBLIC
    if (visibility == UserFieldVisibility.public) {
      batch.set(
        usersPublicRef,
        {fieldKey: value},
        SetOptions(merge: true),
      );
    } else {
      // Non pubblico → rimuovi da UsersPublic
      batch.update(usersPublicRef, {fieldKey: FieldValue.delete()});
    }

    // 3️⃣ VISIBILITÀ SHARED (lega)
    if (visibility == UserFieldVisibility.shared) {
      batch.set(
        memberRef,
        {fieldKey: value},
        SetOptions(merge: true),
      );
    } else {
      // Non condiviso → rimuovi da member
      batch.update(memberRef, {fieldKey: FieldValue.delete()});
    }

    // 4️⃣ SHARED PROFILES (specifici)
    if (sharedWithUserIds != null && sharedWithUserIds.isNotEmpty) {
      for (final targetUid in sharedWithUserIds) {
        final sharedRef = userRef
            .collection('sharedProfiles')
            .doc(targetUid);

        batch.set(
          sharedRef,
          {fieldKey: value},
          SetOptions(merge: true),
        );
      }
    }

    await batch.commit();
  }

  /// Salva la mappa delle visibilità (per UI / restore stato)
  Future<void> saveVisibilityMap({
    required String userId,
    required Map<String, UserFieldVisibility> visibilityMap,
  }) async {
    final data = <String, String>{};

    for (final entry in visibilityMap.entries) {
      data[entry.key] = entry.value.name;
    }

    await _db.collection('Users').doc(userId).set(
      {'_fieldVisibility': data},
      SetOptions(merge: true),
    );
  }

  /// Carica la mappa delle visibilità (se presente)
  Future<Map<String, UserFieldVisibility>> loadVisibilityMap(
      String userId) async {
    final snap = await _db.collection('Users').doc(userId).get();
    final raw = snap.data()?['_fieldVisibility'];

    if (raw is! Map<String, dynamic>) return {};

    final Map<String, UserFieldVisibility> result = {};

    raw.forEach((key, value) {
      final v = UserFieldVisibility.values
          .where((e) => e.name == value)
          .toList();
      if (v.isNotEmpty) {
        result[key] = v.first;
      }
    });

    return result;
  }
}
