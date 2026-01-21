// lib/core/user_fields/hr_policy.dart
// Policy per campo HR: visibilita' e modificabilita' (multi-area, multi-filiale, ruoli, comparti, uids, emails)

enum HrVisibilityScope {
  selfOnly,
  publicLeague,
  publicGlobal,
  restricted,
}

enum HrEditScope {
  none,
  self,
  restricted, // ruoli/comparti/aree/filiali/uids/emails (+ owner/admin sempre)
}

class HrFieldPolicy {
  final HrVisibilityScope visibility;

  /// Se vuoto/null -> tutte le aree.
  final List<String> areas;

  /// Se vuoto/null -> tutte le filiali. Se presente -> almeno una deve matchare.
  final List<String> branches;

  /// Chi puo' vedere (solo se visibility == restricted)
  final List<String> roles;
  final List<String> comparti;
  final List<String> uids;
  final List<String> emailsLower;

  /// Modifica
  final HrEditScope editScope;
  final List<String> editAreas;
  final List<String> editRoles;
  final List<String> editCompartI;
  final List<String> editUids;
  final List<String> editEmailsLower;
  final List<String> editBranches;

  const HrFieldPolicy({
    required this.visibility,
    this.areas = const [],
    this.branches = const [],
    this.roles = const [],
    this.comparti = const [],
    this.uids = const [],
    this.emailsLower = const [],
    this.editScope = HrEditScope.none,
    this.editAreas = const [],
    this.editRoles = const [],
    this.editCompartI = const [],
    this.editUids = const [],
    this.editEmailsLower = const [],
    this.editBranches = const [],
  });

  factory HrFieldPolicy.defaultForNonSensitive({
    bool allowLeague = true,
  }) {
    return HrFieldPolicy(
      visibility: allowLeague ? HrVisibilityScope.publicLeague : HrVisibilityScope.selfOnly,
      editScope: HrEditScope.self,
    );
  }

  factory HrFieldPolicy.defaultForSensitive() {
    return const HrFieldPolicy(
      visibility: HrVisibilityScope.restricted,
      editScope: HrEditScope.restricted,
    );
  }

  Map<String, dynamic> toMap() => {
    'visibility': visibility.name,
    'areas': areas,
    'branches': branches,
    'roles': roles,
    'comparti': comparti,
    'uids': uids,
    'emailsLower': emailsLower,
    'editScope': editScope.name,
    'editAreas': editAreas,
    'editRoles': editRoles,
    'editCompartI': editCompartI,
    'editUids': editUids,
    'editEmailsLower': editEmailsLower,
    'editBranches': editBranches,
  };

  static HrFieldPolicy fromMap(dynamic raw, {HrFieldPolicy? fallback}) {
    if (raw is! Map) return fallback ?? HrFieldPolicy.defaultForNonSensitive();
    String s(dynamic v) => (v ?? '').toString();
    List<String> ls(dynamic v) =>
        (v is List) ? v.map((e) => e.toString()).toList() : <String>[];

    HrVisibilityScope vis = HrVisibilityScope.publicLeague;
    final visStr = s(raw['visibility']);
    for (final e in HrVisibilityScope.values) {
      if (e.name == visStr) vis = e;
    }

    HrEditScope edit = HrEditScope.none;
    final editStr = s(raw['editScope']);
    for (final e in HrEditScope.values) {
      if (e.name == editStr) edit = e;
    }

    return HrFieldPolicy(
      visibility: vis,
      areas: ls(raw['areas']),
      branches: ls(raw['branches']),
      roles: ls(raw['roles']),
      comparti: ls(raw['comparti']),
      uids: ls(raw['uids']),
      emailsLower: ls(raw['emailsLower']),
      editScope: edit,
      editAreas: ls(raw['editAreas']),
      editRoles: ls(raw['editRoles']),
      editCompartI: ls(raw['editCompartI']),
      editUids: ls(raw['editUids']),
      editEmailsLower: ls(raw['editEmailsLower']),
      editBranches: ls(raw['editBranches']),
    );
  }
}
