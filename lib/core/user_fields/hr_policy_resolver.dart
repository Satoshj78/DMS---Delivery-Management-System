// lib/core/user_fields/hr_policy_resolver.dart
// Resolver autorizzazioni: canView/canEdit con override esplicito (uids/emails) che vince su filiali/ruoli/comparti

import 'hr_policy.dart';

class HrViewerContext {
  final String uid;
  final String emailLower;
  final bool isSelf;
  final bool isOwnerOrAdmin;

  final List<String> roles;
  final List<String> comparti;
  final List<String> branches;
  final List<String> effectivePerms;

  const HrViewerContext({
    required this.uid,
    required this.emailLower,
    required this.isSelf,
    required this.isOwnerOrAdmin,
    this.roles = const [],
    this.comparti = const [],
    this.branches = const [],
    this.effectivePerms = const [],
  });
}

bool _listHasAny(List<String> a, List<String> b) {
  for (final x in a) {
    if (b.contains(x)) return true;
  }
  return false;
}

bool _branchOk(List<String> policyBranches, List<String> viewerBranches) {
  if (policyBranches.isEmpty) return true; // tutte
  for (final b in policyBranches) {
    if (viewerBranches.contains(b)) return true;
  }
  return false;
}

/// Override esplicito: uid/email vince su tutto (come hai richiesto)
bool _explicitOverride({
  required HrFieldPolicy p,
  required HrViewerContext v,
  required bool forEdit,
}) {
  if (!forEdit) {
    if (p.uids.contains(v.uid)) return true;
    if (p.emailsLower.contains(v.emailLower)) return true;
  } else {
    if (p.editUids.contains(v.uid)) return true;
    if (p.editEmailsLower.contains(v.emailLower)) return true;
  }
  return false;
}

class HrPolicyResolver {
  static bool canView({
    required HrFieldPolicy policy,
    required HrViewerContext viewer,
  }) {
    if (viewer.isOwnerOrAdmin) return true;

    // 1) override esplicito
    if (_explicitOverride(p: policy, v: viewer, forEdit: false)) return true;

    switch (policy.visibility) {
      case HrVisibilityScope.publicGlobal:
        return true;
      case HrVisibilityScope.publicLeague:
        return true; // membership già richiesta a monte nella UI
      case HrVisibilityScope.selfOnly:
        return viewer.isSelf;
      case HrVisibilityScope.restricted:
        if (!_branchOk(policy.branches, viewer.branches)) return false;
        if (_listHasAny(policy.roles, viewer.roles)) return true;
        if (_listHasAny(policy.comparti, viewer.comparti)) return true;
        return false;
    }
  }

  static bool canEdit({
    required HrFieldPolicy policy,
    required HrViewerContext viewer,
  }) {
    if (viewer.isOwnerOrAdmin) return true;

    // override esplicito per edit
    if (_explicitOverride(p: policy, v: viewer, forEdit: true)) return true;

    switch (policy.editScope) {
      case HrEditScope.none:
        return false;
      case HrEditScope.self:
        return viewer.isSelf;
      case HrEditScope.restricted:
        if (!_branchOk(policy.editBranches.isEmpty ? policy.branches : policy.editBranches, viewer.branches)) {
          return false;
        }
        if (_listHasAny(policy.editRoles, viewer.roles)) return true;
        if (_listHasAny(policy.editCompartI, viewer.comparti)) return true;
        return false;
    }
  }
}
