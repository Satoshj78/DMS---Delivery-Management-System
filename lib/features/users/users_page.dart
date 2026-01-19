// lib/features/users/users_page.dart
// (lista utenti navigabile da tastiera: ↑ ↓ Enter + Ctrl+F/Ctrl+L/Ctrl+K)
// ✅ LISTA LEGA: legge SOLO /Leagues/{leagueId}/members
// ✅ RICERCA GLOBALE on-demand: query mirate su /UsersPublic (solo quando apri il dialog)

import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/service/user/user_service.dart';
import '../../core/widgets/keyboard_selectable_list.dart';
import 'inviti/inviti_pending_page.dart';
import 'users_detail_page.dart';

class UsersPage extends StatefulWidget {
  final String leagueId;

  // ✅ modalità “embedded” desktop (3 colonne)
  final bool embedded;
  final String? selectedUserId;
  final ValueChanged<String>? onSelectUser;

  const UsersPage({
    super.key,
    required this.leagueId,
    this.embedded = false,
    this.selectedUserId,
    this.onSelectUser,
  });

  @override
  State<UsersPage> createState() => _UsersPageState();
}

// -------------------------------
// INTENTS (Shortcuts locali UsersPage)
// -------------------------------
class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _FocusListIntent extends Intent {
  const _FocusListIntent();
}

class _ClearSearchIntent extends Intent {
  const _ClearSearchIntent();
}

class _UsersPageState extends State<UsersPage> {
  String _q = '';
  final _searchFocus = FocusNode();
  final _listFocus = FocusNode();
  final _listScroll = ScrollController();

  User? get _authUser => FirebaseAuth.instance.currentUser;

  String _authDisplayName() => (_authUser?.displayName ?? '').trim();
  String _authPhotoUrl() => (_authUser?.photoURL ?? '').trim();
  String _authEmail() => (_authUser?.email ?? '').trim();

  String _createdByUid = '';
  bool _stickerMode = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _selfUserSub;
  String _selfUserPhotoUrl = '';
  int _selfUserPhotoV = 0;


  // cache: uids membri della lega corrente (per capire se un risultato globale è già membro)
  Set<String> _memberUidSet = {};

  Map<String, dynamic> _map(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  String _s(dynamic v) => (v ?? '').toString().trim();
  String _roleIdNorm(String raw) => raw.trim().toUpperCase();

  String _initials(String fullNameOrEmail) {
    final s = fullNameOrEmail.trim();
    if (s.isEmpty) return '?';
    final parts = s.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return s[0].toUpperCase();
  }

  String _bust(String url, int v) {
    final u = url.trim();
    if (u.isEmpty || v == 0) return u;

    try {
      final uri = Uri.parse(u);
      final qp = Map<String, String>.from(uri.queryParameters);
      qp['v'] = v.toString();
      return uri.replace(queryParameters: qp).toString();
    } catch (_) {
      final sep = u.contains('?') ? '&' : '?';
      return '$u${sep}v=$v';
    }
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? 0;
  }

  Future<void> _precacheIfAny(BuildContext context, String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    try {
      await precacheImage(CachedNetworkImageProvider(u), context);
    } catch (_) {}
  }

  Future<void> _openUserDetailWithPrecache({
    required BuildContext context,
    required String uid,
    required Map<String, dynamic> memberData,
  }) async {
    // FOTO: usa members.photoUrl, altrimenti (solo self) Users.photoUrl, e solo se manca anche quello -> provider
    final rawPhoto = _displayPhotoUrl(uid, memberData);

    final isSelf = uid == _authUser?.uid;
    final memberHasPhoto = _s(memberData['photoUrl']).isNotEmpty;

    // ✅ photoV corretto anche quando il fallback arriva da Users/{uid}
    final photoV = (isSelf && !memberHasPhoto && _selfUserPhotoUrl.isNotEmpty)
        ? _selfUserPhotoV
        : _asInt(memberData['photoV']);

    final photo = rawPhoto.isNotEmpty ? _bust(rawPhoto, photoV) : '';

    final rawCover = _s(memberData['coverUrl']);
    final coverV = _asInt(memberData['coverV']);
    final cover = rawCover.isNotEmpty ? _bust(rawCover, coverV) : '';

    await Future.wait([
      if (photo.isNotEmpty) _precacheIfAny(context, photo),
      if (cover.isNotEmpty) _precacheIfAny(context, cover),
    ]);

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserDetailPage(
          leagueId: widget.leagueId,
          userId: uid,
        ),
      ),
    );
  }


  @override
  void initState() {
    super.initState();
    _loadCreatedByUid();
    _listenSelfUserDoc(); // ✅ prende la foto “vera” da Users/{uid}
  }



  @override
  void dispose() {
    _selfUserSub?.cancel();
    _searchFocus.dispose();
    _listFocus.dispose();
    _listScroll.dispose();
    super.dispose();
  }


  Future<void> _loadCreatedByUid() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('Leagues')
          .doc(widget.leagueId)
          .get();

      final d = snap.data() ?? {};
      final createdByUid = (d['createdByUid'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() => _createdByUid = createdByUid);
    } catch (_) {}
  }

  // -----------------------------
  // ✅ Helpers display (member doc)
  // (ora arrivano direttamente da members grazie alla Cloud Function)
  // -----------------------------
  String _displayNome(String uid, Map<String, dynamic> data) {
    final nome = _s(data['displayNome'] ?? data['nome']);
    if (nome.isNotEmpty) return nome;

    if (uid == _authUser?.uid) {
      final parts = _authDisplayName().split(' ');
      return parts.isNotEmpty ? parts.last : '';
    }
    return '';
  }

  String _displayCognome(String uid, Map<String, dynamic> data) {
    final cognome = _s(data['displayCognome'] ?? data['cognome']);
    if (cognome.isNotEmpty) return cognome;

    if (uid == _authUser?.uid) {
      final parts = _authDisplayName().split(' ');
      return parts.isNotEmpty ? parts.first : '';
    }
    return '';
  }

  String _displayFullName(String uid, Map<String, dynamic> data) {
    // 1) migliore: displayName dal member doc (aggiornato dal trigger)
    final dn = _s(data['displayName']);
    if (dn.isNotEmpty) return dn;

    // 2) fallback: campi separati (se presenti)
    final cognome = _displayCognome(uid, data);
    final nome = _displayNome(uid, data);
    return [cognome, nome].where((s) => s.trim().isNotEmpty).join(' ').trim();
  }

  String _displayPhotoUrl(String uid, Map<String, dynamic> data) {
    final memberPhoto = _s(data['photoUrl']);
    if (memberPhoto.isNotEmpty) return memberPhoto;

    // ✅ Solo per me: prima usa la foto salvata su Users/{uid}
    if (uid == _authUser?.uid) {
      if (_selfUserPhotoUrl.isNotEmpty) return _selfUserPhotoUrl;

      // ✅ Ultimo fallback: provider SOLO se non esiste una foto profilo salvata
      return _authPhotoUrl();
    }

    return '';
  }


  String _displayEmail(String uid, Map<String, dynamic> data) {
    final fromData = _s(data['emailLogin'] ?? data['email']);
    if (fromData.isNotEmpty) return fromData;

    if (uid == _authUser?.uid) return _authEmail();
    return '';
  }

  String _displayEmailLower(String uid, Map<String, dynamic> data) {
    final fromData = _s(data['emailLower']);
    if (fromData.isNotEmpty) return fromData;

    final email = _displayEmail(uid, data);
    return email.isNotEmpty ? email.toLowerCase() : '';
  }

  String _roleNameFrom({
    required String uid,
    required Map<String, dynamic> member,
    required Map<String, String> roleNameById,
  }) {
    final rawRoleId = _s(member['roleId']);
    var roleId = _roleIdNorm(rawRoleId);

    if (roleId.isEmpty && _createdByUid.isNotEmpty && uid == _createdByUid) {
      roleId = 'OWNER';
    }

    if (roleId.isEmpty) return 'Member';
    return roleNameById[roleId] ?? roleId;
  }

  // -----------------------------
// ✅ Azione unica: apri utente (tap o Enter)
// -----------------------------
  Future<void> _activateUser({
    required BuildContext context,
    required bool isDesktop,
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    final me = FirebaseAuth.instance.currentUser;

    if (me != null && uid == me.uid) {
      try {
        final ms = await _memberRef(uid).get();
        if (!ms.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-a-member',
            message: 'User is not a member of this league.',
          );
        }
      } on FirebaseException catch (e) {
        if (e.code == 'not-a-member') {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Non risulti membro di questa lega.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        } else {
          rethrow;
        }
      }
    }


    if (!context.mounted) return;

    // ✅ DESKTOP embedded: non push → aggiorna pannello destro
    if (widget.embedded && isDesktop && widget.onSelectUser != null) {
      widget.onSelectUser!(uid);
      return;
    }

    // ✅ MOBILE / normale: push come prima
    await _openUserDetailWithPrecache(
      context: context,
      uid: uid,
      memberData: data,
    );
  }


  void _focusSearch() => FocusScope.of(context).requestFocus(_searchFocus);
  void _focusList() => FocusScope.of(context).requestFocus(_listFocus);

  void _clearSearch() {
    setState(() => _q = '');
    _focusSearch();
  }

  // ==========================================================
  // ✅ GLOBAL SEARCH (on-demand) su UsersPublic
  // - min 2 caratteri
  // - debounce 350ms
  // - prefix search su displayNameLower / emailLower / nicknameLower
  // ==========================================================
  Future<List<Map<String, dynamic>>> _globalSearchUsersPublic(String q) async {
    final qq = q.trim().toLowerCase();
    if (qq.length < 2) return [];

    final end = '$qq\uf8ff';
    final col = FirebaseFirestore.instance.collection('UsersPublic');

    final out = <String, Map<String, dynamic>>{};

    Future<void> runQuery(String field) async {
      final qs = await col
          .orderBy(field)
          .startAt([qq])
          .endAt([end])
          .limit(20)
          .get();

      for (final d in qs.docs) {
        out[d.id] = {
          'uid': d.id,
          ...d.data(),
        };
      }
    }

    // 3 query piccole e limitate
    await Future.wait([
      runQuery('displayNameLower'),
      runQuery('emailLower'),
      runQuery('nicknameLower'),
    ]);

    return out.values.toList();
  }

  Future<void> _openGlobalSearchDialog(bool isDesktop) async {
    Timer? debounce;
    String q = '';
    bool loading = false;
    List<Map<String, dynamic>> results = [];

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> doSearch(String v) async {
              q = v.trim().toLowerCase();
              debounce?.cancel();

              if (q.length < 2) {
                setLocal(() {
                  results = [];
                  loading = false;
                });
                return;
              }

              debounce = Timer(const Duration(milliseconds: 350), () async {
                setLocal(() => loading = true);
                try {
                  final r = await _globalSearchUsersPublic(q);
                  setLocal(() {
                    results = r;
                    loading = false;
                  });
                } catch (_) {
                  setLocal(() => loading = false);
                }
              });
            }

            return AlertDialog(
              title: const Text('Ricerca globale utenti'),
              content: SizedBox(
                width: 620,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Cerca per displayName, email o nickname (min 2 caratteri)',
                        prefixIcon: Icon(Icons.travel_explore),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: doSearch,
                    ),
                    const SizedBox(height: 12),
                    if (loading) const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 360,
                      child: results.isEmpty
                          ? const Center(child: Text('Nessun risultato.'))
                          : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (_, i) {
                          final r = results[i];
                          final uid = _s(r['uid']);
                          final displayName = _s(r['displayName']);
                          final nome = _s(r['nome']);
                          final cognome = _s(r['cognome']);
                          final email = _s(r['email']);

                          // ✅ SOLO UsersPublic: niente provider fallback qui
                          final photoUrl = _s(r['photoUrl']);
                          final photoV = _asInt(r['photoV']);
                          final photo = photoUrl.isNotEmpty ? _bust(photoUrl, photoV) : '';

                          final title = displayName.isNotEmpty
                              ? displayName
                              : ([cognome, nome].where((e) => e.trim().isNotEmpty).join(' ')).trim();

                          final inLeague = _memberUidSet.contains(uid);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
                                child: photo.isEmpty ? const Icon(Icons.person) : null,
                              ),
                              title: Text(
                                title.isNotEmpty ? title : uid,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                [
                                  if (email.isNotEmpty) email,
                                  if (_s(r['nickname']).isNotEmpty) 'nickname: ${_s(r['nickname'])}',
                                  inLeague ? '✅ già nella tua lega' : '➕ non è nella tua lega',
                                ].join(' • '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: inLeague
                                  ? const Icon(Icons.chevron_right)
                                  : IconButton(
                                tooltip: 'Copia email',
                                icon: const Icon(Icons.copy),
                                onPressed: () async {
                                  if (email.isEmpty) return;
                                  await Clipboard.setData(ClipboardData(text: email));
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Email copiata negli appunti')),
                                    );
                                  }
                                },
                              ),
                              onTap: () async {
                                if (!inLeague) return;

                                Navigator.of(ctx).pop();

                                // Se è membro della lega, apro/seleleziono
                                if (widget.embedded && isDesktop && widget.onSelectUser != null) {
                                  widget.onSelectUser!(uid);
                                  return;
                                }

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserDetailPage(
                                      leagueId: widget.leagueId,
                                      userId: uid,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },

                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Chiudi'),
                ),
              ],
            );
          },
        );
      },
    );

    debounce?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1100;

    // Shortcuts locali utili in questa pagina
    final shortcuts = <LogicalKeySet, Intent>{
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF): const _FocusSearchIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyL): const _FocusListIntent(),
      LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK): const _ClearSearchIntent(),
    };

    final actions = <Type, Action<Intent>>{
      _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(onInvoke: (_) {
        _focusSearch();
        return null;
      }),
      _FocusListIntent: CallbackAction<_FocusListIntent>(onInvoke: (_) {
        _focusList();
        return null;
      }),
      _ClearSearchIntent: CallbackAction<_ClearSearchIntent>(onInvoke: (_) {
        _clearSearch();
        return null;
      }),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: actions,
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              // SEARCH + INVITES BUTTON
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        focusNode: _searchFocus,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: 'Cerca membri lega: nome, cognome, email, telefono (lega), ruolo...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                        onSubmitted: (_) => _focusList(), // Enter → lista
                      ),
                    ),
                    const SizedBox(width: 8),

                    // ✅ Ricerca globale on-demand
                    IconButton(
                      tooltip: 'Ricerca globale (tutti gli utenti registrati)',
                      icon: const Icon(Icons.travel_explore),
                      onPressed: () => _openGlobalSearchDialog(isDesktop),
                    ),

                    FutureBuilder<bool>(
                      future: UserService.canManageInvites(leagueId: widget.leagueId),
                      builder: (context, snap) {
                        final canInvite = snap.data ?? false;
                        if (!canInvite) return const SizedBox.shrink();

                        return IconButton(
                          tooltip: 'Inviti (in attesa)',
                          icon: const Icon(Icons.person_add_alt_1),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => InvitiPendingPage(leagueId: widget.leagueId),
                              ),
                            );
                          },
                        );
                      },
                    ),

                    IconButton(
                      tooltip: _stickerMode ? 'Mostra foto profilo' : 'Mostra sticker',
                      icon: Icon(_stickerMode ? Icons.face : Icons.local_offer_outlined),
                      onPressed: () => setState(() => _stickerMode = !_stickerMode),
                    ),
                  ],
                ),
              ),

              // ✅ ROLES + MEMBERS (members-only)
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: UserService.streamRoles(widget.leagueId),
                  builder: (context, rolesSnap) {
                    final roleNameById = <String, String>{};
                    if (rolesSnap.hasData) {
                      for (final d in rolesSnap.data!.docs) {
                        final data = d.data();
                        final name = (data['name'] ?? '').toString().trim();
                        roleNameById[d.id.trim().toUpperCase()] = name.isEmpty ? d.id : name;
                      }
                    }

                    final leagueRef = FirebaseFirestore.instance
                        .collection('Leagues')
                        .doc(widget.leagueId);

                    final membersStream = leagueRef.collection('members').snapshots();

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: membersStream,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return const Center(child: Text('Errore caricamento utenti'));
                        }
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final membersDocs = snap.data!.docs;

                        // aggiorno cache uids
                        _memberUidSet = membersDocs.map((d) => d.id).toSet();

                        final docs = membersDocs.map((m) {
                          final uid = m.id;
                          return <String, dynamic>{
                            'uid': uid,
                            ...m.data(),
                          };
                        }).toList();

                        if (docs.isEmpty) {
                          return const Center(child: Text('Nessun utente trovato.'));
                        }

                        // ✅ Filtro client-side (solo lega)
                        final filtered = docs.where((data) {
                          final uid = _s(data['uid']);
                          if (uid.isEmpty) return false;

                          final nome = _displayNome(uid, data);
                          final cognome = _displayCognome(uid, data);
                          final email = _displayEmail(uid, data);
                          final emailLower = _displayEmailLower(uid, data);

                          final overrides = _map(data['overrides']);
                          final recapitiOv = _map(overrides['recapiti']);
                          final tel = _s(recapitiOv['telefono']);

                          final roleName = _roleNameFrom(
                            uid: uid,
                            member: data,
                            roleNameById: roleNameById,
                          );

                          final hay = '$cognome $nome $roleName $email $emailLower $tel'.toLowerCase();
                          return _q.isEmpty || hay.contains(_q);
                        }).toList();

                        if (filtered.isEmpty) {
                          return const Center(child: Text('Nessun utente trovato.'));
                        }

                        // ✅ Lista navigabile da tastiera (↑ ↓ Enter)
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                          child: KeyboardSelectableList(
                            focusNode: _listFocus,
                            autofocus: widget.embedded && isDesktop,
                            scrollController: _listScroll,
                            itemCount: filtered.length,
                            estimatedItemExtent: 104,
                            onActivate: (i) async {
                              final data = filtered[i];
                              final uid = _s(data['uid']);
                              if (uid.isEmpty) return;
                              await _activateUser(
                                context: context,
                                isDesktop: isDesktop,
                                uid: uid,
                                data: data,
                              );
                            },
                            itemBuilder: (context, i, kbdSelected) {
                              final data = filtered[i];
                              final uid = _s(data['uid']);

                              final nome = _displayNome(uid, data);
                              final cognome = _displayCognome(uid, data);
                              final photoUrl = _displayPhotoUrl(uid, data);
                              final email = _displayEmail(uid, data);
                              final emailLower = _displayEmailLower(uid, data);
                              final showEmailLower = email.isEmpty && emailLower.isNotEmpty;

                              final overrides = _map(data['overrides']);
                              final recapitiOv = _map(overrides['recapiti']);
                              final tel = _s(recapitiOv['telefono']);

                              final roleName = _roleNameFrom(
                                uid: uid,
                                member: data,
                                roleNameById: roleNameById,
                              );

                              final fullNameRaw = _displayFullName(uid, data);
                              final fullName = fullNameRaw.isNotEmpty
                                  ? fullNameRaw
                                  : (email.isNotEmpty ? email : uid);



                              final photoV = _asInt(data['photoV']);
                              final photoBusted = photoUrl.isNotEmpty ? _bust(photoUrl, photoV) : '';

                              final leading = _stickerMode
                                  ? Container(
                                width: 42,
                                height: 42,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                ),
                                child: Text(
                                  _initials(fullName),
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                              )
                                  : CircleAvatar(
                                backgroundImage: photoBusted.isNotEmpty
                                    ? CachedNetworkImageProvider(photoBusted)
                                    : null,
                                child: photoBusted.isEmpty ? const Icon(Icons.person) : null,
                              );

                              final isSelected =
                                  widget.selectedUserId != null && widget.selectedUserId == uid;

                              final cardColor = isSelected
                                  ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.28)
                                  : null;

                              final borderColor = kbdSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: borderColor, width: 2),
                                ),
                                color: cardColor,
                                child: ListTile(
                                  leading: leading,
                                  title: Text(
                                    fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        roleName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      if (showEmailLower)
                                        Text(
                                          emailLower,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      Text(
                                        [
                                          if (email.isNotEmpty) email,
                                          if (tel.isNotEmpty) tel,
                                        ].join(' • '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () async {
                                    await _activateUser(
                                      context: context,
                                      isDesktop: isDesktop,
                                      uid: uid,
                                      data: data,
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }




  void _listenSelfUserDoc() {
    final uid = _authUser?.uid;
    if (uid == null || uid.isEmpty) return;

    _selfUserSub?.cancel();
    _selfUserSub = FirebaseFirestore.instance
        .collection('Users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      final d = snap.data() ?? {};
      final url = _s(d['photoUrl']);
      final v = _asInt(d['photoV']);

      if (!mounted) return;
      if (url == _selfUserPhotoUrl && v == _selfUserPhotoV) return;

      setState(() {
        _selfUserPhotoUrl = url;
        _selfUserPhotoV = v;
      });
    });
  }

  DocumentReference<Map<String, dynamic>> _memberRef(String uid) {
    return FirebaseFirestore.instance
        .collection('Leagues')
        .doc(widget.leagueId)
        .collection('members')
        .doc(uid);
  }



}
