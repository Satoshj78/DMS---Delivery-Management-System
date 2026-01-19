// lib/features/users/users_detail_page.dart
// Pagina dettaglio utente: header profilo animato (cover + avatar che scivola nello scroll)
// + tab Profilo + tab HR con policy per campo

import 'dart:typed_data';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'package:dms_app/core/user_fields/hr_field_definition.dart';
import 'package:dms_app/core/user_fields/hr_field_renderer.dart';
import 'package:dms_app/core/user_fields/hr_field_types.dart';
import 'package:dms_app/core/user_fields/hr_policy.dart';
import 'package:dms_app/core/user_fields/hr_policy_dialog.dart';
import 'package:dms_app/core/user_fields/hr_policy_resolver.dart';
import 'package:dms_app/features/users/widgets/user_profile_header_sliver.dart';









class UserDetailPage extends StatefulWidget {
  final String leagueId;
  final String userId;

  /// Se true: la pagina è mostrata dentro un pannello desktop
  final bool embedded;

  const UserDetailPage({
    super.key,
    required this.leagueId,
    required this.userId,
    this.embedded = false,
  });

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage>
    with TickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _picker = ImagePicker();
  final ScrollController _scroll = ScrollController();


  late final TabController _tab;

  bool _editMode = false;
  bool _savingImage = false;

  Map<String, dynamic> _userValues = {};
  Map<String, dynamic> _memberValues = {};
  Map<String, dynamic> _viewerMember = {};

  String get _viewerUid => _auth.currentUser?.uid ?? '';
  String get _viewerEmailLower =>
      (_auth.currentUser?.email ?? '').toLowerCase();

  bool get _isSelf => _viewerUid == widget.userId;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('Users').doc(uid);

  DocumentReference<Map<String, dynamic>> _memberRef(String uid) => _db
      .collection('Leagues')
      .doc(widget.leagueId)
      .collection('members')
      .doc(uid);

  DocumentReference<Map<String, dynamic>>? get _viewerMemberRef {
    if (_viewerUid.isEmpty) return null;
    return _memberRef(_viewerUid);
  }

  // ------------------------------------------------------------
  // ViewerContext (permessi / ruoli / comparti)
  // ------------------------------------------------------------
  HrViewerContext _viewerContext({required String targetUid}) {
    List<String> ls(dynamic v) =>
        (v is List) ? v.map((e) => e.toString()).toList() : <String>[];

    final m = _viewerMember;

    final roles = ls(m['roles']).isNotEmpty
        ? ls(m['roles'])
        : (m['role'] != null ? [m['role'].toString()] : <String>[]);

    final comparti = ls(m['comparti']).isNotEmpty
        ? ls(m['comparti'])
        : (m['comparto'] != null ? [m['comparto'].toString()] : <String>[]);

    final branches = ls(m['branches']).isNotEmpty
        ? ls(m['branches'])
        : (m['branchId'] != null ? [m['branchId'].toString()] : <String>[]);

    final eff =
    ls(m['effectivePerms']).isNotEmpty ? ls(m['effectivePerms']) : ls(m['perms']);

    final permsMap = (m['permissions'] is Map<String, dynamic>)
        ? (m['permissions'] as Map<String, dynamic>)
        : <String, dynamic>{};

    bool hasPerm(String k) => eff.contains(k) || permsMap[k] == true;

    final isOwnerOrAdmin = (m['isOwner'] == true) ||
        roles.contains('OWNER') ||
        hasPerm('hr_admin') ||
        hasPerm('hr_manage') ||
        hasPerm('members_manage');

    return HrViewerContext(
      uid: _viewerUid,
      emailLower: _viewerEmailLower,
      isSelf: _viewerUid == targetUid,
      isOwnerOrAdmin: isOwnerOrAdmin,
      roles: roles,
      comparti: comparti,
      branches: branches,
      effectivePerms: eff,
    );
  }

  // ------------------------------------------------------------
  // HR policy helpers
  // ------------------------------------------------------------
  HrFieldPolicy _getPolicy({
    required bool isUserTarget,
    required String fieldKey,
    required bool sensitive,
  }) {
    final key = '${fieldKey}__policy';
    final raw = isUserTarget ? _userValues[key] : _memberValues[key];

    final fallback = sensitive
        ? HrFieldPolicy.defaultForSensitive()
        : HrFieldPolicy.defaultForNonSensitive(allowLeague: true);

    return HrFieldPolicy.fromMap(raw, fallback: fallback);
  }

  void _setPolicy({
    required bool isUserTarget,
    required String fieldKey,
    required HrFieldPolicy policy,
  }) {
    final key = '${fieldKey}__policy';
    if (isUserTarget) {
      _userValues[key] = policy.toMap();
    } else {
      _memberValues[key] = policy.toMap();
    }
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final userStream = _userRef(widget.userId).snapshots();
    final memberStream = _memberRef(widget.userId).snapshots();
    final viewerMemberStream = _viewerMemberRef?.snapshots();

    final body = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: memberStream,
      builder: (context, memberSnap) {
        if (!memberSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final member = memberSnap.data!.data() ?? {};

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: userStream,
          builder: (context, userSnap) {
            if (!userSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final user = userSnap.data!.data() ?? {};

            if (viewerMemberStream == null) {
              return _buildPage(context, user: user, member: member);
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: viewerMemberStream,
              builder: (context, vSnap) {
                _viewerMember = vSnap.data?.data() ?? {};
                return _buildPage(context, user: user, member: member);
              },
            );
          },
        );
      },
    );

    if (widget.embedded) return body;
    return Scaffold(body: body);
  }

  Widget _buildPage(
      BuildContext context, {
        required Map<String, dynamic> user,
        required Map<String, dynamic> member,
      }) {
    _userValues = Map<String, dynamic>.from(user);
    _memberValues = Map<String, dynamic>.from(member);

    final viewer = _viewerContext(targetUid: widget.userId);
    final canEditImages = viewer.isOwnerOrAdmin || viewer.isSelf;

    final displayName = _displayNameFromUser(_userValues);

    final storedPhoto = (_userValues['photoUrl'] ?? '').toString().trim();
    final providerPhoto = (_userValues['providerPhotoUrl'] ?? '').toString().trim();
    final authProvider = (_auth.currentUser?.photoURL ?? '').toString().trim();

    // ✅ Provider SOLO fallback (e authProvider SOLO se sto guardando me stesso)
    final effectivePhotoUrl = storedPhoto.isNotEmpty
        ? storedPhoto
        : (providerPhoto.isNotEmpty ? providerPhoto : (_isSelf ? authProvider : ''));

    final coverUrl = (_userValues['coverUrl'] ?? '').toString().trim();

    final topPadding = MediaQuery.of(context).padding.top;

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelW = constraints.maxWidth; // ✅ larghezza reale del pannello detail

        return Scaffold(
          body: Stack(
            children: [
              /// CONTENUTO SCROLLABILE
              NestedScrollView(
                controller: _scroll,
                headerSliverBuilder: (context, _) => [
                  /// COVER (SOLO COVER)
                  UserProfileHeaderSliver(
                    displayName: displayName,
                    photoUrl: null,
                    coverUrl: coverUrl.isEmpty ? null : coverUrl,
                    canEdit: canEditImages,
                    onOpenAvatar: () {},
                    onEditAvatar: () {},
                    onEditCover: canEditImages
                        ? () => _pickAndUploadImage(isCover: true)
                        : () {},
                  ),

                  /// SPAZIO TRA COVER E TAB (si azzera mentre il blocco identità si sposta)
                  SliverToBoxAdapter(
                    child: AnimatedBuilder(
                      animation: _scroll,
                      builder: (context, _) {
                        final offset = _scroll.hasClients ? _scroll.offset : 0.0;
                        final t = (offset / 260).clamp(0.0, 1.0);

                        const moveStart = 0.15;
                        const moveEnd = 0.85;

                        final uRaw = ((t - moveStart) / (moveEnd - moveStart))
                            .clamp(0.0, 1.0);
                        final u = Curves.easeInOutCubic.transform(uRaw);

                        const spacerMax = 120.0;
                        final h = spacerMax * (1.0 - u);

                        return Container(
                          color: Theme.of(context).colorScheme.surface,
                          child: SizedBox(height: h < 0.5 ? 0 : h),
                        );
                      },
                    ),
                  ),

                  /// TAB BAR (PINNED)
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabsHeaderDelegate(
                      TabBar(
                        controller: _tab,
                        tabs: const [
                          Tab(text: 'Profilo'),
                          Tab(text: 'HR'),
                        ],
                      ),
                    ),
                  ),
                ],

                /// BODY
                body: TabBarView(
                  controller: _tab,
                  children: [
                    _buildProfileTab(viewer),
                    _buildHrTab(viewer),
                  ],
                ),
              ),

              /// AVATAR + IDENTITÀ (LAYER SUPERIORE)
              AnimatedBuilder(
                animation: _scroll,
                builder: (context, _) {
                  final offset = _scroll.hasClients ? _scroll.offset : 0.0;
                  final t = (offset / 260).clamp(0.0, 1.0);

                  final avatarSize = lerpDouble(150, 36, t)!;

                  final avatarTop = lerpDouble(
                    250,
                    topPadding + (kToolbarHeight - avatarSize) / 2,
                    t,
                  )!;

                  // ✅ left basato sul pannello (non su tutta la finestra) + clamp
                  final avatarLeftExpanded = (panelW - avatarSize) / 2;
                  const avatarLeftCollapsed = 56.0;

                  final avatarLeftRaw =
                  lerpDouble(avatarLeftExpanded, avatarLeftCollapsed, t)!;

                  final maxAvatarLeft = panelW - avatarSize - 8.0;
                  final avatarLeft = avatarLeftRaw.clamp(
                    8.0,
                    maxAvatarLeft < 8.0 ? 8.0 : maxAvatarLeft,
                  );

                  final hasPhoto = effectivePhotoUrl.isNotEmpty;

                  return Stack(
                    children: [
                      /// AVATAR
                      Positioned(
                        top: avatarTop,
                        left: avatarLeft,
                        child: Stack(
                          children: [

                        Container(
                          width: avatarSize,
                          height: avatarSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey.shade400,
                            image: hasPhoto
                                ? DecorationImage(
                              image: CachedNetworkImageProvider(effectivePhotoUrl),
                              fit: BoxFit.cover,
                            )
                                : null,
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          child: !hasPhoto
                              ? Icon(Icons.person, size: avatarSize * 0.5, color: Colors.white)
                              : null,
                        ),


                          if (canEditImages && t < 0.4)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: GestureDetector(
                                  onTap: () => _pickAndUploadImage(isCover: false),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.black87,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.edit,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      /// ✅ BLOCCO IDENTITÀ CHE SI SPOSTA (sotto -> fianco)
                      Builder(
                        builder: (context) {
                          final wScreen = panelW; // ✅ pannello, non finestra intera

                          const moveStart = 0.15;
                          const moveEnd = 0.85;

                          final uRaw = ((t - moveStart) / (moveEnd - moveStart))
                              .clamp(0.0, 1.0);
                          final u = Curves.easeInOutCubic.transform(uRaw);

                          final nick = (_userValues['nickname'] ??
                              _userValues['nickName'] ??
                              _userValues['Nickname'] ??
                              '')
                              .toString()
                              .trim();

                          final mail = ((_userValues['email'] ?? '').toString().isNotEmpty
                              ? (_userValues['email'] ?? '').toString()
                              : (_auth.currentUser?.email ?? '').toString())
                              .trim();

                          final nameFs = lerpDouble(20, 16, u)!;
                          final textColor =
                          Color.lerp(Colors.black87, Colors.white, u)!;

                          final expandedW = (wScreen - 32).clamp(0.0, 520.0);

                          final collapsedX = avatarLeft + avatarSize + 12;
                          final collapsedW =
                          (wScreen - collapsedX - 16).clamp(0.0, wScreen);

                          double xExpanded =
                              avatarLeft + (avatarSize / 2) - (expandedW / 2);
                          xExpanded = xExpanded.clamp(
                            16.0,
                            (wScreen - expandedW - 16.0).clamp(16.0, wScreen),
                          );

                          final wwRaw = lerpDouble(expandedW, collapsedW, u)!;
                          final maxW = (wScreen - 16.0);
                          final ww = wwRaw.clamp(0.0, maxW < 0 ? 0.0 : maxW);

                          final xRaw = lerpDouble(xExpanded, collapsedX, u)!;
                          final maxX = wScreen - ww - 8.0;
                          final x = xRaw.clamp(
                            8.0,
                            maxX < 8.0 ? 8.0 : maxX,
                          );

                          const extraDown = 18.0;
                          final yExpanded = avatarTop + avatarSize + extraDown;
                          final yCollapsed = avatarTop + (avatarSize - 20) / 2;
                          final y = lerpDouble(yExpanded, yCollapsed, u)!;

                          final subOpacity = Curves.easeOutQuad
                              .transform((1.0 - uRaw).clamp(0.0, 1.0));

                          final a =
                          Alignment.lerp(Alignment.center, Alignment.centerLeft, u)!;

                          return Positioned(
                            top: y,
                            left: x,
                            child: IgnorePointer(
                              child: SizedBox(
                                width: ww,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Align(
                                      alignment: a,
                                      child: Text(
                                        displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.left,
                                        style: TextStyle(
                                          fontSize: nameFs,
                                          fontWeight: FontWeight.w800,
                                          color: textColor,
                                        ),
                                      ),
                                    ),

                                    if (nick.isNotEmpty)
                                      Opacity(
                                        opacity: subOpacity,
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Align(
                                            alignment: a,
                                            child: Text(
                                              nick,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.left,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(color: Colors.black54),
                                            ),
                                          ),
                                        ),
                                      ),

                                    if (mail.isNotEmpty)
                                      Opacity(
                                        opacity: subOpacity,
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Align(
                                            alignment: a,
                                            child: Text(
                                              mail,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.left,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(color: Colors.grey),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }



  String _displayNameFromUser(Map<String, dynamic> u) {
    final fn = (u['firstName'] ?? u['nome'] ?? '').toString().trim();
    final ln = (u['lastName'] ?? u['cognome'] ?? '').toString().trim();
    final name = ('$fn $ln').trim();
    return name.isEmpty ? 'Utente' : name;
  }

  // ------------------------------------------------------------
  // TAB PROFILO
  // ------------------------------------------------------------
  Widget _buildProfileTab(HrViewerContext viewer) {
    final thought = (_userValues['thought'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Text(
              viewer.isSelf ? 'Il tuo profilo' : 'Profilo membro',
              style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(_editMode ? Icons.check : Icons.edit),
              onPressed: () => setState(() => _editMode = !_editMode),
            ),
          ],
        ),
        _simpleRow('Email', (_userValues['email'] ?? '').toString()),
        _simpleRow('Telefono',
            (_userValues['phone'] ?? _userValues['telefono'] ?? '').toString()),
        if (thought.isNotEmpty) ...[
          const Divider(),
          const Text('Pensiero',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(thought),
        ],
      ],
    );
  }

  Widget _simpleRow(String label, String value) {
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(value.isEmpty ? '—' : value),
    );
  }

  // ------------------------------------------------------------
  // TAB HR
  // ------------------------------------------------------------
  Widget _buildHrTab(HrViewerContext viewer) {
    final categories =
    HrFieldCatalog.fields.map((f) => f.category).toSet().toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final cat in categories) ...[
          Text(cat,
              style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ..._buildHrCategory(viewer, cat),
          const Divider(),
        ]
      ],
    );
  }

  List<Widget> _buildHrCategory(HrViewerContext viewer, String category) {
    final fields =
    HrFieldCatalog.fields.where((f) => f.category == category).toList();

    return fields.map((field) {
      final isUserTarget = field.target == HrTarget.user;
      final policy = _getPolicy(
        isUserTarget: isUserTarget,
        fieldKey: field.key,
        sensitive: field.sensitive,
      );

      if (!HrPolicyResolver.canView(policy: policy, viewer: viewer)) {
        return const SizedBox.shrink();
      }

      final canEdit =
          _editMode && HrPolicyResolver.canEdit(policy: policy, viewer: viewer);

      final value =
      isUserTarget ? _userValues[field.key] : _memberValues[field.key];

      final row = HrFieldRenderer(
        field: field,
        value: value,
        editable: canEdit,
        onChanged: (k, v) async {
          setState(() {
            if (isUserTarget) {
              _userValues[k] = v;
            } else {
              _memberValues[k] = v;
            }
          });
          await _persistField(isUserTarget, k, v);
        },
      );

      final canManagePolicy =
          viewer.isOwnerOrAdmin || (viewer.isSelf && !field.sensitive);

      if (!canManagePolicy) return row;

      return Stack(
        children: [
          row,
          Positioned(
            right: 4,
            top: 0,
            child: IconButton(
              icon: const Icon(Icons.shield_outlined, size: 18),
              onPressed: () async {
                final updated = await showDialog<HrFieldPolicy>(
                  context: context,
                  builder: (_) => HrPolicyDialog(
                    leagueId: widget.leagueId,
                    initial: policy,
                    allowGlobal: true,
                    sensitive: field.sensitive,
                    canManage: viewer.isOwnerOrAdmin,
                    isSelf: viewer.isSelf,
                  ),
                );
                if (updated != null) {
                  _setPolicy(
                    isUserTarget: isUserTarget,
                    fieldKey: field.key,
                    policy: updated,
                  );
                  await _persistField(
                    isUserTarget,
                    '${field.key}__policy',
                    updated.toMap(),
                  );
                }
              },
            ),
          ),
        ],
      );
    }).toList();
  }

  Future<void> _persistField(bool isUserTarget, String key, dynamic value) async {
    final ref =
    isUserTarget ? _userRef(widget.userId) : _memberRef(widget.userId);
    await ref.set({key: value}, SetOptions(merge: true));
  }

  // ------------------------------------------------------------
  // AVATAR FULLSCREEN
  // ------------------------------------------------------------
  Future<void> _openAvatarFullscreen(String url) async {
    if (url.isEmpty) return;
    await showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // IMAGE UPLOAD
  // ------------------------------------------------------------
  Future<void> _pickAndUploadImage({required bool isCover}) async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (_) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Fotocamera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Galleria'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      final picked = await _picker.pickImage(source: source, imageQuality: 95);
      if (picked == null) return;

      setState(() => _savingImage = true);

      final bytes = await picked.readAsBytes();
      final jpeg = await compute(_compressToJpeg, bytes);

      final uid = widget.userId;
      final path = isCover ? 'users/$uid/cover.jpg' : 'users/$uid/photo.jpg';

      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(jpeg, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      final field = isCover ? 'coverUrl' : 'photoUrl';
      await _userRef(uid).set({field: url}, SetOptions(merge: true));
      await _memberRef(uid).set({field: url}, SetOptions(merge: true));

      setState(() => _userValues[field] = url);
    } finally {
      if (mounted) setState(() => _savingImage = false);
    }
  }
}

Uint8List _compressToJpeg(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) return input;
  final resized =
  img.copyResize(decoded, width: decoded.width > 1280 ? 1280 : decoded.width);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
}


class _TabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabsHeaderDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeaderDelegate oldDelegate) => false;
}
