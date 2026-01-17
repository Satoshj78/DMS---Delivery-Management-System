import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';

class UserService {
  static final _db = FirebaseFirestore.instance;

  // ---------------- refs ----------------
  static DocumentReference<Map<String, dynamic>> userRef(String uid) =>
      _db.collection('Users').doc(uid);

  static DocumentReference<Map<String, dynamic>> usersPublicRef(String uid) =>
      _db.collection('UsersPublic').doc(uid);

  static CollectionReference<Map<String, dynamic>> membersCol(String leagueId) =>
      _db.collection('Leagues').doc(leagueId).collection('members');

  static DocumentReference<Map<String, dynamic>> memberRef(String leagueId, String uid) =>
      membersCol(leagueId).doc(uid);

  static CollectionReference<Map<String, dynamic>> rolesCol(String leagueId) =>
      _db.collection('Leagues').doc(leagueId).collection('roles');

  static CollectionReference<Map<String, dynamic>> sharedToCol(String ownerUid) =>
      _db.collection('Users').doc(ownerUid).collection('sharedTo');

  static DocumentReference<Map<String, dynamic>> sharedToRef(String ownerUid, String viewerUid) =>
      sharedToCol(ownerUid).doc(viewerUid);

  static DocumentReference<Map<String, dynamic>> leagueSharedProfileRef(String leagueId, String targetUid) =>
      _db.collection('Leagues').doc(leagueId).collection('sharedProfiles').doc(targetUid);

  // ---------------- streams ----------------
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMembers(String leagueId) {
    return membersCol(leagueId)
        .orderBy('displayCognomeLower')
        .orderBy('displayNomeLower')
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamRoles(String leagueId) {
    return rolesCol(leagueId).orderBy('tier').snapshots();
  }

  // ---------- helpers ----------
  static String _s(dynamic v) => (v ?? '').toString().trim();
  static String? _nullIfEmpty(String v) => v.trim().isEmpty ? null : v.trim();

  static Map<String, dynamic> _map(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  static List<String> _listStr(dynamic v) {
    if (v is List) {
      return v.map((e) => _s(e)).where((e) => e.isNotEmpty).toList();
    }
    return <String>[];
  }

  /// Profilo completo (PRIVATO) dal doc Users/{uid}
  static Map<String, dynamic> buildProfileFromUserDoc(Map<String, dynamic> userData) {
    final p = _map(userData['profile']);
    final recapiti = _map(p['recapiti']);
    final anagrafica = _map(p['anagrafica']);
    final residenza = _map(p['residenza']);
    final custom = _map(p['custom']);

    return {
      'nome': _nullIfEmpty(_s(p['nome'])),
      'cognome': _nullIfEmpty(_s(p['cognome'])),
      'photoUrl': _nullIfEmpty(_s(p['photoUrl'] ?? userData['photoUrl'])),
      'coverUrl': _nullIfEmpty(_s(p['coverUrl'] ?? userData['coverUrl'])),

      // ⚠️ questi sono PRIVATI (restano in Users/{uid})
      'recapiti': {
        'telefono': _nullIfEmpty(_s(recapiti['telefono'])),
        'emailSecondarie': (recapiti['emailSecondarie'] is List)
            ? (recapiti['emailSecondarie'] as List)
            .map((e) => _s(e))
            .where((e) => e.isNotEmpty)
            .toList()
            : <String>[],
      },
      'anagrafica': {
        'codiceFiscale': _nullIfEmpty(_s(anagrafica['codiceFiscale'])),
        'ibanDefault': _nullIfEmpty(_s(anagrafica['ibanDefault'])),
      },
      'residenza': {
        'via': _nullIfEmpty(_s(residenza['via'])),
        'cap': _nullIfEmpty(_s(residenza['cap'])),
        'citta': _nullIfEmpty(_s(residenza['citta'])),
        'provincia': _nullIfEmpty(_s(residenza['provincia'])),
        'nazione': _nullIfEmpty(_s(residenza['nazione'])),
      },
      'custom': custom,
    };
  }


  /// ✅ Profilo “league-safe” e SEMPRE pubblico per questi campi:
  /// nome, cognome, photoUrl, coverUrl
  static Map<String, dynamic> buildPublicProfile(Map<String, dynamic> fullProfile) {
    final nome = _s(fullProfile['nome']);
    final cognome = _s(fullProfile['cognome']);
    final photoUrl = _s(fullProfile['photoUrl']);
    final coverUrl = _s(fullProfile['coverUrl']);

    return {
      'nome': _nullIfEmpty(nome),
      'cognome': _nullIfEmpty(cognome),
      'photoUrl': photoUrl.isEmpty ? null : photoUrl,
      'coverUrl': coverUrl.isEmpty ? null : coverUrl,
    };
  }


  // ==========================================================
  // ✅ Legge UNA SOLA VOLTA meta lega (joinCode + createdByUid)
  // ==========================================================
  static Future<_LeagueMeta> _getLeagueMeta(String leagueId) async {
    final snap = await _db.collection('Leagues').doc(leagueId).get();
    final data = snap.data() ?? {};

    final joinCode = _s(data['joinCode']).toUpperCase();
    final createdByUid = _s(data['createdByUid']);

    if (joinCode.isEmpty) {
      throw StateError('JoinCode mancante per leagueId=$leagueId');
    }
    return _LeagueMeta(joinCode: joinCode, createdByUid: createdByUid);
  }

  static Future<String> _requireJoinCode(String leagueId) async {
    final meta = await _getLeagueMeta(leagueId);
    return meta.joinCode;
  }

  // ==========================================================
  // ✅ GUARD-RAILS: Users/{uid} è PRIVATO -> solo self
  // ==========================================================
  static String _requireLoggedUid() {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw StateError('Not logged');
    return me.uid;
  }

  static void _assertSelfUid(String uid) {
    final meUid = FirebaseAuth.instance.currentUser?.uid;
    if (meUid == null) throw StateError('Not logged');
    if (meUid != uid) {
      throw StateError(
        'Operazione non consentita: Users/$uid è privato. '
            'Questo metodo può essere chiamato solo per l’utente corrente ($meUid).',
      );
    }
  }

  // ==========================================================
// PRIVACY / SHARING HELPERS
// ==========================================================
  /// privacy map supportato (NUOVO):
  /// {
  ///  "telefono":    {"mode":"public"},
  ///  "ibanDefault": {
  ///    "mode":"shared",
  ///    "leagueScopes":{"L1":"PRIVILEGED","L2":"ALL_MEMBERS"},
  ///    "allLeagues": false,
  ///    "allLeaguesScope": "ALL_MEMBERS", // o "PRIVILEGED"
  ///    "users":[],
  ///    "emails":[],
  ///    "compartos":[]
  ///  },
  ///  "cf":         {"mode":"private"}
  /// }
  ///
  /// BACKWARD COMPAT:
  /// - se trovi "leagues":[...] lo interpreto come PRIVILEGED (vecchio comportamento)
  /// - se trovi "mode" come stringa diretta (es: "public") lo accetto
  /// - se trovi "league": true lo interpreto come allLeagues=true (default ALL_MEMBERS)
  static Map<String, dynamic> normalizePrivacy(Map<String, dynamic>? privacy) {
    String audNorm(String raw) {
      final u = _s(raw).toUpperCase().trim();
      if (u == 'ALL_MEMBERS' || u == 'MEMBERS' || u == 'ALL' || u == 'PUBLIC') return 'ALL_MEMBERS';
      if (u == 'PRIVILEGED' || u == 'ADMINS' || u == 'MANAGERS' || u == 'OWNER') return 'PRIVILEGED';
      return '';
    }

    final out = <String, dynamic>{};
    final src = privacy ?? {};

    for (final e in src.entries) {
      final k = _s(e.key);
      if (k.isEmpty) continue;

      // supporto: valore stringa diretto (es: "public")
      if (e.value is String) {
        final modeS = _s(e.value).toLowerCase();
        if (modeS == 'public' || modeS == 'shared' || modeS == 'private') {
          out[k] = {
            'mode': modeS,
            'leagueScopes': <String, String>{},
            'allLeagues': false,
            'allLeaguesScope': 'ALL_MEMBERS',
            'users': <String>[],
            'emails': <String>[],
            'compartos': <String>[],
          };
        }
        continue;
      }

      final m = _map(e.value);
      final mode = _s(m['mode']).toLowerCase();
      if (mode != 'public' && mode != 'shared' && mode != 'private') continue;

      final leagueScopes = <String, String>{};

      final rawScopes = m['leagueScopes'];
      if (rawScopes is Map) {
        rawScopes.forEach((lid, aud) {
          final id = _s(lid);
          final a = audNorm(_s(aud));
          if (id.isEmpty) return;
          if (a.isEmpty) return;
          leagueScopes[id] = a;
        });
      } else {
        // compat: vecchio "leagues": [...] => PRIVILEGED
        for (final lid in _listStr(m['leagues'])) {
          if (lid.isEmpty) continue;
          leagueScopes[lid] = 'PRIVILEGED';
        }
      }

      var allLeagues = (m['allLeagues'] == true);
      var allLeaguesScope = audNorm(_s(m['allLeaguesScope']));
      if (allLeaguesScope.isEmpty) allLeaguesScope = 'ALL_MEMBERS';

      // compat legacy: "league": true
      if (!allLeagues && m['league'] == true) {
        allLeagues = true;
        final legacyAud = audNorm(_s(m['audience']));
        if (legacyAud.isNotEmpty) allLeaguesScope = legacyAud;
      }

      final users = <String>{
        ..._listStr(m['users']).map((x) => x.trim()),
        ..._listStr(m['uids']).map((x) => x.trim()),
      }..removeWhere((x) => x.isEmpty);
      final usersList = users.toList();

      final compartos = _listStr(m['compartos']);
      final emails = _listStr(m['emails'])
          .map((x) => x.toLowerCase().trim())
          .where((x) => x.isNotEmpty)
          .toList();

      out[k] = {
        'mode': mode,
        'leagueScopes': leagueScopes,
        'allLeagues': allLeagues,
        'allLeaguesScope': allLeaguesScope,
        'users': users,
        'emails': emails,
        'compartos': compartos,
        'users': usersList,
        'uids': usersList,

      };
    }

    // ✅ FORZA: questi campi possono essere SOLO pubblici
    const alwaysPublicKeys = <String>[
      'nome',
      'cognome',
      'nickname',
      'thought',
      'photoUrl',
      'coverUrl',
      'photoV',
      'coverV',
    ];

    for (final k in alwaysPublicKeys) {
      out[k] = {
        'mode': 'public',
        'leagueScopes': <String, String>{},
        'allLeagues': false,
        'allLeaguesScope': 'ALL_MEMBERS',
        'users': <String>[],
        'emails': <String>[],
        'compartos': <String>[],
      };
    }

    return out;
  }







  static dynamic _extractFieldValue(Map<String, dynamic> profile, String key) {
    final recapiti = _map(profile['recapiti']);
    final anagrafica = _map(profile['anagrafica']);
    final residenza = _map(profile['residenza']);

    switch (key) {
    // ✅ SEMPRE PUBBLICI
      case 'nome':
        return _nullIfEmpty(_s(profile['nome']));
      case 'cognome':
        return _nullIfEmpty(_s(profile['cognome']));
      case 'photoUrl':
        return _nullIfEmpty(_s(profile['photoUrl']));
      case 'coverUrl':
        return _nullIfEmpty(_s(profile['coverUrl']));

    // altri campi
      case 'telefono':
        return _nullIfEmpty(_s(recapiti['telefono']));
      case 'ibanDefault':
        return _nullIfEmpty(_s(anagrafica['ibanDefault']));
      case 'codiceFiscale':
        return _nullIfEmpty(_s(anagrafica['codiceFiscale']));
      case 'residenza':
        final r = Map<String, dynamic>.from(residenza);
        r.removeWhere((k, v) => _s(v).isEmpty);
        return r.isEmpty ? null : r;

      default:
        return null;
    }
  }


  static Map<String, dynamic> _buildUsersPublicDoc({
    required String uid,
    required Map<String, dynamic> profile,
    required Map<String, dynamic> privacy,
  }) {
    final nome = _s(profile['nome']);
    final cognome = _s(profile['cognome']);
    final photoUrl = _s(profile['photoUrl']);
    final coverUrl = _s(profile['coverUrl']);

    final fields = <String, dynamic>{};

    // ✅ questi 4 sono SEMPRE pubblici (li metto anche in fields)
    final coreKeys = <String>['nome', 'cognome', 'photoUrl', 'coverUrl'];
    for (final k in coreKeys) {
      final v = _extractFieldValue(profile, k);
      if (v != null) fields[k] = v;
    }

    // Altri campi: SOLO mode=public
    for (final e in privacy.entries) {
      final key = _s(e.key);
      if (coreKeys.contains(key)) continue; // già gestiti
      final mode = _s(_map(e.value)['mode']).toLowerCase();
      if (mode != 'public') continue;

      final val = _extractFieldValue(profile, key);
      if (val != null) fields[key] = val;
    }

    return {
      'uid': uid,

      // Root convenience (sempre pubblici)
      'displayNome': _nullIfEmpty(nome),
      'displayCognome': _nullIfEmpty(cognome),
      'displayNomeLower': nome.toLowerCase(),
      'displayCognomeLower': cognome.toLowerCase(),
      'photoUrl': photoUrl.isEmpty ? null : photoUrl,
      'coverUrl': coverUrl.isEmpty ? null : coverUrl,

      'fields': fields,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }


  // ==========================================================
  // API “comode”
  // ==========================================================
  static Future<void> ensureMyMemberDoc({required String leagueId}) async {
    final myUid = _requireLoggedUid();
    return ensureMemberDoc(leagueId: leagueId, uid: myUid);
  }

  static Future<void> updateMyGlobalProfileAndSync({
    required Map<String, dynamic> profile,
    Map<String, dynamic>? privacy,
  }) async {
    final myUid = _requireLoggedUid();
    return updateGlobalProfileAndSync(uid: myUid, profile: profile, privacy: privacy);
  }

// ==========================================================
// ✅ members: SOLO PUBLIC PROFILE (no sensibili)
//    + nome/cognome/photo/cover SEMPRE pubblici
// ==========================================================


// ==========================================================
// ✅ VERIFICA DOCUMENTO MEMBRO IN UNA LEGA (NO WRITE DA CLIENT)
// - Con la tua architettura: members li creano solo le callable (invite/join) e li aggiorna onUserProfileWrite
// - Questo metodo serve solo come "guard": se non esiste, non sei membro.
// ==========================================================
  static Future<void> ensureMemberDoc({
    required String leagueId,
    required String uid,
  }) async {
    final db = FirebaseFirestore.instance;
    final memberRef = db.collection('Leagues').doc(leagueId).collection('members').doc(uid);
    final memberSnap = await memberRef.get();

    if (!memberSnap.exists) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-a-member',
        message: 'Non risulti membro della lega ($leagueId).',
      );
    }
  }





// ==========================================================
// ✅ Users (privato) + sharedTo + sharedToEmails
// Tutta la propagazione (UsersPublic, members, sharedProfiles, sharedProfilesAll)
// viene gestita automaticamente dalla Cloud Function onUserProfileWrite.
// ==========================================================
  static Future<void> updateGlobalProfileAndSync({
    required String uid,
    required Map<String, dynamic> profile,
    Map<String, dynamic>? privacy,
  }) async {
    _assertSelfUid(uid);

    const corePublicKeys = <String>{'nome', 'cognome', 'photoUrl', 'coverUrl'};

    final uRef = userRef(uid);
    final snap = await uRef.get();
    final data = snap.data() ?? {};

    final leagueIds = (data['leagueIds'] is List)
        ? (data['leagueIds'] as List)
        .map((e) => _s(e))
        .where((e) => e.isNotEmpty)
        .toList()
        : <String>[];

    final prevProfile = _map(data['profile']);
    final prevPrivacy = normalizePrivacy(_map(prevProfile['privacy']));

    // ✅ se privacy è null NON azzerare
    final nextPrivacy = (privacy == null) ? prevPrivacy : normalizePrivacy(privacy);

    // ✅ merge profilo (non perdere campi non passati)
    final nextProfile = Map<String, dynamic>.from(prevProfile);
    nextProfile.addAll(profile);
    nextProfile['privacy'] = nextPrivacy;

    final publicProfile = buildPublicProfile(nextProfile);

    // -------------------------
    // Helpers locali
    // -------------------------
    String audNorm(String raw) {
      final u = _s(raw).toUpperCase().trim();
      if (u == 'ALL_MEMBERS' || u == 'MEMBERS' || u == 'ALL' || u == 'PUBLIC') return 'ALL_MEMBERS';
      return 'PRIVILEGED';
    }

    Map<String, String> effectiveLeagueScopes(Map<String, dynamic> m) {
      final out = <String, String>{};
      final allLeagues = (m['allLeagues'] == true);
      if (allLeagues) {
        final scopeRaw = _s(m['allLeaguesScope']);
        final aud = audNorm(scopeRaw.isEmpty ? 'ALL_MEMBERS' : scopeRaw);
        for (final lid in leagueIds) {
          if (lid.isNotEmpty) out[lid] = aud;
        }
      }
      final scopes = _map(m['leagueScopes']);
      for (final e in scopes.entries) {
        final lid = _s(e.key);
        if (lid.isEmpty) continue;
        out[lid] = audNorm(_s(e.value));
      }
      return out;
    }

    // ==========================
    // PREV destinations (per delete)
    // ==========================
    final prevUserDests = <String>{};
    final prevEmailDests = <String>{};

    for (final e in prevPrivacy.entries) {
      final m = _map(e.value);
      if (_s(m['mode']).toLowerCase() != 'shared') continue;
      prevUserDests.addAll(_listStr(m['users']));
      prevEmailDests.addAll(
        _listStr(m['emails']).map((x) => x.toLowerCase()).where((x) => x.isNotEmpty),
      );
    }

    // ==========================
    // BUILD next docs (solo sharedTo e sharedToEmails)
    // ==========================
    final userToFields = <String, Map<String, dynamic>>{};
    final emailToFields = <String, Map<String, dynamic>>{};

    for (final e in nextPrivacy.entries) {
      final key = e.key;
      if (corePublicKeys.contains(key)) continue;

      final m = _map(e.value);
      final mode = _s(m['mode']).toLowerCase();
      if (mode != 'shared') continue;

      final value = _extractFieldValue(nextProfile, key);
      if (value == null) continue;

      final users = _listStr(m['users']);
      final emails = _listStr(m['emails'])
          .map((x) => x.toLowerCase())
          .where((x) => x.isNotEmpty)
          .toList();

      for (final vu in users) {
        userToFields.putIfAbsent(vu, () => <String, dynamic>{});
        userToFields[vu]![key] = value;
      }

      for (final em in emails) {
        emailToFields.putIfAbsent(em, () => <String, dynamic>{});
        emailToFields[em]![key] = value;
      }
    }

    final nextUserDests = userToFields.keys.toSet();
    final nextEmailDests = emailToFields.keys.toSet();

    final batch = _db.batch();

    // 1️⃣ Users (privato)
    batch.set(
      uRef,
      {
        'profile': nextProfile,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // 2️⃣ sharedTo per utenti specifici
    for (final viewerUid in nextUserDests) {
      final fields = userToFields[viewerUid] ?? <String, dynamic>{};
      batch.set(
        sharedToRef(uid, viewerUid),
        {
          'ownerUid': uid,
          'viewerUid': viewerUid,
          'fields': fields,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    for (final oldViewer in prevUserDests.difference(nextUserDests)) {
      batch.delete(sharedToRef(uid, oldViewer));
    }

    // 3️⃣ sharedToEmails
    final sharedToEmailsCol = userRef(uid).collection('sharedToEmails');
    for (final emailLower in nextEmailDests) {
      final fields = emailToFields[emailLower] ?? <String, dynamic>{};
      batch.set(
        sharedToEmailsCol.doc(emailLower),
        {
          'ownerUid': uid,
          'viewerEmailLower': emailLower,
          'fields': fields,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    for (final oldEmail in prevEmailDests.difference(nextEmailDests)) {
      batch.delete(sharedToEmailsCol.doc(oldEmail));
    }

    await batch.commit();

    // ✅ STOP QUI
    // Niente più scritture su sharedProfiles, sharedProfilesAll o members:
    // vengono aggiornate automaticamente dal trigger onUserProfileWrite.
  }




  /// Estrae i campi condivisibili in base alla privacy.
  static Map<String, dynamic> _extractSharedFields(
      Map<String, dynamic> profile,
      Map<String, dynamic> privacy,
      ) {
    final out = <String, dynamic>{};
    void add(String key, dynamic value) {
      if (value != null && value.toString().trim().isNotEmpty) out[key] = value;
    }

    bool isShared(String key) {
      final p = (privacy[key] ?? {}) as Map;
      final mode = (p['mode'] ?? 'public').toString();
      final league = (p['league'] == true);
      final emails = (p['emails'] ?? []) as List;
      return mode == 'public' || league || emails.isNotEmpty;
    }

    // esempio minimo — puoi ampliare con gli altri campi che vuoi condividere
    if (isShared('telefono')) add('telefono', profile['recapiti']?['telefono']);
    if (isShared('ibanDefault')) add('ibanDefault', profile['anagrafica']?['ibanDefault']);
    if (isShared('codiceFiscale')) add('codiceFiscale', profile['anagrafica']?['codiceFiscale']);
    if (isShared('residenza')) add('residenza', profile['residenza']);
    return out;
  }




  // ==========================================================
  // ✅ leggere dati “visibili” quando NON sei self
  // priority: sharedTo > leagueShared > UsersPublic
  // ==========================================================
  static Future<Map<String, dynamic>> fetchVisibleFieldsForViewer({
    required String leagueId,
    required String targetUid,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw StateError('Not logged');

    if (me.uid == targetUid) {
      // self: leggi completo dal profilo privato
      final uSnap = await userRef(targetUid).get();
      final uData = uSnap.data() ?? {};
      final full = buildProfileFromUserDoc(uData);
      return {
        'profile': full,
        'sharedFields': <String, dynamic>{},
      };
    }

    Map<String, dynamic> publicFields = {};
    Map<String, dynamic> leagueAllFields = {};
    Map<String, dynamic> leaguePrivFields = {};
    Map<String, dynamic> directFields = {};

    // UsersPublic (safe)
    try {
      final p = await usersPublicRef(targetUid).get();
      publicFields = _map(p.data()?['fields']);
    } catch (_) {}

    // shared in league (ALL MEMBERS)
    try {
      final a = await leagueSharedProfileAllRef(leagueId, targetUid).get();
      leagueAllFields = _map(a.data()?['fields']);
    } catch (_) {}

    // shared in league (PRIVILEGED / allowlist / comparti speciali)
    try {
      final l = await leagueSharedProfileRef(leagueId, targetUid).get();
      leaguePrivFields = _map(l.data()?['fields']);
    } catch (_) {}

    // direct share (1-to-1)
    try {
      final d = await sharedToRef(targetUid, me.uid).get();
      directFields = _map(d.data()?['fields']);
    } catch (_) {}

    // merge priority: public < leagueAll < leaguePriv < direct
    final merged = <String, dynamic>{};
    merged.addAll(publicFields);
    merged.addAll(leagueAllFields);
    merged.addAll(leaguePrivFields);
    merged.addAll(directFields);

    return {
      'profile': <String, dynamic>{}, // non self: profilo privato non leggibile
      'sharedFields': merged,
    };
  }



  // ==========================================================
  // Refs
  // ==========================================================
  static DocumentReference<Map<String, dynamic>> leagueSharedProfileAllRef(
      String leagueId,
      String targetUid,
      ) =>
      _db
          .collection('Leagues')
          .doc(leagueId)
          .collection('sharedProfilesAll')
          .doc(targetUid);



  // ==========================================================
  // updateMemberData (immutato)
  // ==========================================================
  static Future<void> updateMemberData({
    required String leagueId,
    required String uid,
    Map<String, dynamic>? overrides,
    Map<String, dynamic>? org,
    Map<String, dynamic>? custom,
  }) async {
    // ❌ Non scrivere su Firestore: la Cloud Function aggiorna members
    debugPrint(
        '⚠️ updateMemberData ignorato lato client — gestito da Cloud Function.');
  }


  // ==========================================================
  // ROLES - PIRAMIDE DINAMICA (tier) (immutato)
  // ==========================================================
  static Future<void> migrateRolesRankToTierIfNeeded(String leagueId) async {
    final col = rolesCol(leagueId);
    final snap = await col.get();

    final batch = _db.batch();
    bool changed = false;

    for (final d in snap.docs) {
      final data = d.data();
      final hasTier = data.containsKey('tier');
      final rank = (data['rank'] as num?)?.toInt();

      if (!hasTier && rank != null) {
        batch.set(d.reference, {'tier': rank}, SetOptions(merge: true));
        changed = true;
      }
    }

    if (changed) await batch.commit();
  }

  static Future<void> createDefaultOwnerRoleIfMissing(String leagueId) async {
    final ref = rolesCol(leagueId).doc('OWNER');
    final snap = await ref.get();
    if (snap.exists) return;

    await ref.set({
      'name': 'OWNER',
      'tier': 1,
      'comparto': 'direzione',
      'permissions': {
        'invites_manage': true,
        'roles_manage': true,
        'members_manage': true,

        // ✅ nuovo
        'members_sensitive_read': true,

        'programmi_read': true,
        'programmi_write': true,
        'manutenzioni_read': true,
        'manutenzioni_write': true,
      },
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<String> insertRoleAtTier({
    required String leagueId,
    required int tier,
    required String name,
    String? comparto,
    Map<String, dynamic> permissions = const {},
  }) async {
    final col = rolesCol(leagueId);
    final newRef = col.doc();

    final toShift = await col.where('tier', isGreaterThanOrEqualTo: tier).get();

    await _db.runTransaction((tx) async {
      for (final d in toShift.docs) {
        final snap = await tx.get(d.reference);
        final data = snap.data() ?? {};
        final cur = (data['tier'] as num?)?.toInt() ?? 999999;
        tx.update(d.reference, {'tier': cur + 1});
      }

      tx.set(newRef, {
        'name': name.trim(),
        'tier': tier,
        'comparto': (comparto ?? '').trim().isEmpty ? null : comparto!.trim(),
        'permissions': permissions,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });

    return newRef.id;
  }

  static Future<void> moveRoleToTier({
    required String leagueId,
    required String roleId,
    required int newTier,
  }) async {
    final col = rolesCol(leagueId);
    final roleRef = col.doc(roleId);

    final roleSnap0 = await roleRef.get();
    if (!roleSnap0.exists) throw StateError('Ruolo non trovato: $roleId');

    final curTier0 = (roleSnap0.data()?['tier'] as num?)?.toInt() ?? 999999;
    if (newTier == curTier0) return;

    if (roleId == 'OWNER' && newTier != 1) {
      throw StateError('Il ruolo OWNER deve restare a tier 1.');
    }

    QuerySnapshot<Map<String, dynamic>> q;
    if (newTier < curTier0) {
      q = await col
          .where('tier', isGreaterThanOrEqualTo: newTier)
          .where('tier', isLessThan: curTier0)
          .get();
    } else {
      q = await col
          .where('tier', isGreaterThan: curTier0)
          .where('tier', isLessThanOrEqualTo: newTier)
          .get();
    }

    await _db.runTransaction((tx) async {
      final roleSnap = await tx.get(roleRef);
      if (!roleSnap.exists) throw StateError('Ruolo non trovato: $roleId');

      for (final d in q.docs) {
        if (d.id == roleId) continue;

        final s = await tx.get(d.reference);
        final data = s.data() ?? {};
        final t = (data['tier'] as num?)?.toInt() ?? 999999;

        if (newTier < curTier0) {
          tx.update(d.reference, {'tier': t + 1});
        } else {
          tx.update(d.reference, {'tier': t - 1});
        }
      }

      tx.update(roleRef, {'tier': newTier});
    });
  }

  static Future<void> insertRoleAtRank({
    required String leagueId,
    required int rank,
    required String name,
    String? comparto,
    Map<String, dynamic> permissions = const {},
  }) async {
    await insertRoleAtTier(
      leagueId: leagueId,
      tier: rank,
      name: name,
      comparto: comparto,
      permissions: permissions,
    );
  }

  static Future<int> _tierOfRole(String leagueId, String roleId) async {
    final r = await rolesCol(leagueId).doc(roleId).get();
    final data = r.data() ?? {};

    final tier = (data['tier'] as num?)?.toInt();
    if (tier != null) return tier;

    return (data['rank'] as num?)?.toInt() ?? 999999;
  }

  static Future<bool> canEditMember({
    required String leagueId,
    required String actorUid,
    required String targetUid,
  }) async {
    if (actorUid == targetUid) return true;

    final a = await memberRef(leagueId, actorUid).get();
    final t = await memberRef(leagueId, targetUid).get();
    if (!a.exists || !t.exists) return false;

    final aRole = _s(a.data()?['roleId']);
    final tRole = _s(t.data()?['roleId']);
    if (aRole.isEmpty || tRole.isEmpty) return false;

    final aTier = await _tierOfRole(leagueId, aRole);
    final tTier = await _tierOfRole(leagueId, tRole);

    return aTier < tTier;
  }

  static Future<void> setMemberRole({
    required String leagueId,
    required String targetUid,
    required String roleId,
  }) async {
    await memberRef(leagueId, targetUid).set({
      'roleId': roleId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ==========================================================
  // INVITES (metodi come tuoi, ma patchati per NON scrivere profilo sensibile in members)
  // ==========================================================
  static CollectionReference<Map<String, dynamic>> invitesCol(String leagueId) =>
      _db.collection('Leagues').doc(leagueId).collection('invites');

  static DocumentReference<Map<String, dynamic>> inviteRef(String leagueId, String inviteId) =>
      invitesCol(leagueId).doc(inviteId);

  static Future<String> createInvite({
    required String leagueId,
    required String email,
    String roleId = 'member',
    String? prefillNome,
    String? prefillCognome,
    String? prefillFiliale,
    String? prefillComparto,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw StateError('Not logged');

    final doc = invitesCol(leagueId).doc();

    await doc.set({
      'emailLower': email.trim().toLowerCase(),
      'roleId': roleId,
      'prefill': {
        'nome': _nullIfEmpty(_s(prefillNome)),
        'cognome': _nullIfEmpty(_s(prefillCognome)),
        'filiale': _nullIfEmpty(_s(prefillFiliale)),
        'comparto': _nullIfEmpty(_s(prefillComparto)),
      },
      'status': 'pending',
      'createdBy': me.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'acceptedByUid': null,
      'acceptedAt': null,
    });

    return doc.id;
  }

  static Future<void> acceptInvite({
    required String leagueId,
    required String inviteId,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw StateError('Not logged');

    final myEmailLower = (me.email ?? '').trim().toLowerCase();

    final iRef = inviteRef(leagueId, inviteId);
    final iSnap = await iRef.get();
    if (!iSnap.exists) throw StateError('Invito non trovato.');

    final iData = iSnap.data() ?? {};
    final status = _s(iData['status']);
    if (status != 'pending') throw StateError('Invito non valido (stato: $status).');

    final inviteEmailLower = _s(iData['emailLower']).toLowerCase();
    if (inviteEmailLower.isNotEmpty &&
        myEmailLower.isNotEmpty &&
        inviteEmailLower != myEmailLower) {
      throw StateError('Questo invito è associato a un’altra email.');
    }

    final roleId = _s(iData['roleId']).isEmpty ? 'member' : _s(iData['roleId']);
    final prefill = _map(iData['prefill']);
    final preNome = _s(prefill['nome']);
    final preCognome = _s(prefill['cognome']);
    final preFiliale = _s(prefill['filiale']);
    final preComparto = _s(prefill['comparto']);

    final uRef = userRef(me.uid);
    final uSnap = await uRef.get();
    final uData = uSnap.data() ?? {};

    final existingProfile = buildProfileFromUserDoc(uData);

    final rawProfile = _map(uData['profile']);
    existingProfile['privacy'] = normalizePrivacy(_map(rawProfile['privacy']));


    if (_s(existingProfile['nome']).isEmpty && preNome.isNotEmpty) {
      existingProfile['nome'] = preNome;
    }
    if (_s(existingProfile['cognome']).isEmpty && preCognome.isNotEmpty) {
      existingProfile['cognome'] = preCognome;
    }

    final meta = await _getLeagueMeta(leagueId);
    final joinCode = meta.joinCode;

    final publicProfile = buildPublicProfile(existingProfile);

    final nome = _s(publicProfile['nome']);
    final cognome = _s(publicProfile['cognome']);
    final photoUrl = _s(publicProfile['photoUrl']);

    final mRef = memberRef(leagueId, me.uid);

    final batch = _db.batch();

    final userPayload = <String, dynamic>{
      'uid': me.uid,
      'email': me.email,
      'emailLower': myEmailLower,
      'activeLeagueId': leagueId,
      'leagueIds': FieldValue.arrayUnion([leagueId]),
      'profile': existingProfile, // privato
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!uSnap.exists) {
      userPayload['createdAt'] = FieldValue.serverTimestamp();
    }

    batch.set(uRef, userPayload, SetOptions(merge: true));

    // ✅ member: solo safe
    batch.set(mRef, {
      'uid': me.uid,
      'emailLogin': _s(me.email),
      'displayNome': nome,
      'displayCognome': cognome,
      'displayNomeLower': nome.toLowerCase(),
      'displayCognomeLower': cognome.toLowerCase(),
      'photoUrl': photoUrl.isEmpty ? null : photoUrl,

      'baseProfile': publicProfile,
      'baseProfilePublic': publicProfile,

      'inviteId': inviteId,
      'joinCode': joinCode,
      'overrides': <String, dynamic>{},
      'custom': <String, dynamic>{},
      'org': {
        'organizzazione': null,
        'filiale': _nullIfEmpty(preFiliale),
        'comparto': _nullIfEmpty(preComparto),
        'jobRole': null,
      },
      'roleId': roleId,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.update(iRef, {
      'status': 'accepted',
      'acceptedByUid': me.uid,
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> streamPendingInvites(String leagueId) {
    return invitesCol(leagueId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<void> revokeInvite({
    required String leagueId,
    required String inviteId,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw StateError('Not logged');

    await inviteRef(leagueId, inviteId).set({
      'status': 'revoked',
      'revokedBy': me.uid,
      'revokedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<bool> canManageInvites({required String leagueId}) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return false;

    final leagueSnap = await _db.collection('Leagues').doc(leagueId).get();
    final createdByUid = _s(leagueSnap.data()?['createdByUid']);
    if (createdByUid == me.uid) return true;

    final mSnap = await memberRef(leagueId, me.uid).get();
    if (!mSnap.exists) return false;

    final roleId = _s(mSnap.data()?['roleId']);
    if (roleId.isEmpty) return false;

    final tier = await _tierOfRole(leagueId, roleId);
    return tier <= 5;
  }

  // ==========================================================
  // INVITE CODE HELPERS (immutati)
  // ==========================================================
  static Map<String, String>? parseInvitePayload(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;

    final uri = Uri.tryParse(t);
    if (uri != null) {
      final qp = uri.queryParameters;
      final leagueId = (qp['leagueId'] ?? qp['league'] ?? '').trim();
      final inviteId = (qp['inviteId'] ?? qp['invite'] ?? qp['viteId'] ?? '').trim();
      if (leagueId.isNotEmpty && inviteId.isNotEmpty) {
        return {'leagueId': leagueId, 'inviteId': inviteId};
      }
    }

    if (t.contains('=') && t.contains('&')) {
      final u = Uri.tryParse('dms://invite?$t');
      if (u != null) {
        final qp = u.queryParameters;
        final leagueId = (qp['leagueId'] ?? qp['league'] ?? '').trim();
        final inviteId = (qp['inviteId'] ?? qp['invite'] ?? qp['viteId'] ?? '').trim();
        if (leagueId.isNotEmpty && inviteId.isNotEmpty) {
          return {'leagueId': leagueId, 'inviteId': inviteId};
        }
      }
    }

    if (t.contains(':') && !t.contains('://')) {
      final p = t.split(':').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (p.length >= 2) {
        final leagueId = p[0];
        final inviteId = p[1];
        if (leagueId.isNotEmpty && inviteId.isNotEmpty) {
          return {'leagueId': leagueId, 'inviteId': inviteId};
        }
      }
    }

    final parts = t
        .split(RegExp(r'[\|\;\,\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (parts.length >= 2) {
      final leagueId = parts[0];
      final inviteId = parts[1];
      if (leagueId.isNotEmpty && inviteId.isNotEmpty) {
        return {'leagueId': leagueId, 'inviteId': inviteId};
      }
    }

    return null;
  }

  static Future<String> acceptInviteCode({required String code}) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) throw StateError('Not logged');

    final parsed = parseInvitePayload(code);
    if (parsed == null) {
      throw StateError(
        'Codice invito incompleto/non valido. Incolla il testo completo o scansiona il QR.',
      );
    }

    final leagueId = parsed['leagueId']!.trim();
    final inviteId = parsed['inviteId']!.trim();

    if (leagueId.isEmpty || inviteId.isEmpty || leagueId.contains('/') || inviteId.contains('/')) {
      throw StateError('Codice invito non valido (leagueId/inviteId).');
    }

    await acceptInvite(leagueId: leagueId, inviteId: inviteId);
    return leagueId;
  }

  static String buildInvitePayload({
    required String leagueId,
    required String inviteId,
  }) {
    final uri = Uri(
      scheme: 'dms',
      host: 'invite',
      queryParameters: {
        'leagueId': leagueId.trim(),
        'inviteId': inviteId.trim(),
      },
    );
    return uri.toString();
  }
}

class _LeagueMeta {
  final String joinCode;
  final String createdByUid;
  const _LeagueMeta({required this.joinCode, required this.createdByUid});
}
