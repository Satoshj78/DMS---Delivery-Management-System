// lib/features/users/user_detail_page.dart
// Pagina dettaglio utente: profilo (pubblico/lega), avatar/cover, edit e privacy

import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dms_app/core/service/user/user_service.dart';
import 'package:dms_app/core/service/media/dms_fullscreen_images_page.dart';
import 'package:dms_app/core/ui/dms_tabs.dart';
import 'package:dms_app/core/user_fields/hr_field_definition.dart';
import 'package:dms_app/core/user_fields/hr_field_renderer.dart';
import 'package:dms_app/core/user_fields/hr_policy.dart';
import 'package:dms_app/core/user_fields/hr_policy_resolver.dart';
import 'package:dms_app/core/user_fields/hr_policy_dialog.dart';
import 'package:dms_app/core/user_fields/hr_field_types.dart';
import 'dart:typed_data';



class SaveUserDetailIntent extends Intent {
  const SaveUserDetailIntent();
}


class UserDetailPage extends StatefulWidget {
  final String leagueId;
  final String userId;

  /// ✅ Se true: la pagina viene mostrata “dentro” una colonna/pannello desktop,
  /// quindi NON deve avere AppBar propria.
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

class _UserDetailPageState extends State<UserDetailPage> {
  final _nome = TextEditingController();
  final _cognome = TextEditingController();
  final _nickname = TextEditingController();
  final _thought = TextEditingController();
  final _cf = TextEditingController();
  final _ibanDefault = TextEditingController();
  final _tel = TextEditingController();

  final _via = TextEditingController();
  final _cap = TextEditingController();
  final _citta = TextEditingController();
  final _prov = TextEditingController();
  final _naz = TextEditingController();

  // per-lega
  final _org = TextEditingController();
  final _comparto = TextEditingController();
  final _jobRole = TextEditingController();
  final _telLeague = TextEditingController();
  final _ibanLeague = TextEditingController();

  List<String> _emailsExtra = [];
  List<String> _emailsExtraLeague = [];

  Map<String, dynamic> _customGlobal = {};
  Map<String, dynamic> _customLeague = {};

  String? _photoUrl; // ✅ preserva la foto esistente
  final LayerLink _profileLink = LayerLink();
  final ValueNotifier<double> _nameAvoidDy = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _nameAvoidDx = ValueNotifier<double>(0.0);


  bool _inited = false;
  bool _saving = false;
  bool _notSelfSharedLoaded = false;


  final _picker = ImagePicker();

  String? _coverUrl;            // ✅ nuova: copertina
  bool _autoSyncedAuthPhoto = false;

  bool _editMode = false;

  // ================= HR dynamic values =================
  Map<String, dynamic> _userValues = {};
  Map<String, dynamic> _memberValues = {};

  // Alias per compatibilita con chiavi legacy del profilo
  static const Map<String, String> _kHrUserKeyAlias = {
    'firstName': 'nome',
    'lastName': 'cognome',
    'phone': 'telefono',
    'codiceFiscale': 'codiceFiscale',
    'nickname': 'nickname',
    'thought': 'thought',
  };

  static const Map<String, String> _kHrMemberKeyAlias = {
    'emailCompany': 'emailAziendale',
    'hireDate': 'dataAssunzione',
    'contractType': 'tipoContratto',
    'jobRole': 'jobRole',
    'department': 'comparto',
    'employmentStatus': 'statoRapporto',
    'terminationDate': 'dataCessazione',
  };

  String _mapHrKeyToUser(String hrKey) => _kHrUserKeyAlias[hrKey] ?? hrKey;
  String _mapHrKeyToMember(String hrKey) => _kHrMemberKeyAlias[hrKey] ?? hrKey;



  static const double _kExpandedHeight = 300;
  static const double _kTabsAreaH = kTextTabBarHeight; // 48
  static const double _kBottomBarCollapsedH = 108.0; // minimo: top + tabs
  static const double _kBottomBarExpandedH  = 176.0; // spazio “ampio” quando cover è su

  double _pinnedH = _kBottomBarExpandedH; // altezza animata del pinned

  final ValueNotifier<double> _collapseT = ValueNotifier<double>(1.0); // 1=espanso, 0=collassato

  final ScrollController _outerCtrl = ScrollController();


  int _vPhoto = 0;
  int _vCover = 0;

  bool _imageSyncScheduled = false;
  String? _pendingPhoto;
  String? _pendingCover;
  int _pendingPhotoV = 0;
  int _pendingCoverV = 0;





  void _handleSaveShortcut() {
    // evita doppi salvataggi
    if (_saving) return;

    // se hai una variabile tipo _editMode / _isEditing, usa quella:
    // if (!_editMode) return;

    // se la pagina è readOnly quando non-self, blocca:
    // if (_readOnly) return;

    // CHIAMA QUI IL TUO SALVATAGGIO REALE

    _saveAllAndExit(); // <-- cambia con il tuo metodo vero se si chiama diversamente
  }







// privacy per campo (solo per SELF, perché Users è privato)
  Map<String, dynamic> _fieldSharing = {};


  // ✅ SEMPRE PUBBLICI (non possono diventare privati)
  static const Set<String> _kAlwaysPublicFields = {
    'nome',
    'cognome',
    'nickname',
    'thought',
    'photoUrl',
    'photoV',
    'coverUrl',
    'coverV',
  };

  void _enforceAlwaysPublicPrivacy() {
    final next = Map<String, dynamic>.from(_fieldSharing);
    // formato esempio:
    // _fieldSharing['telefono'] = {'mode':'public'}
    // _fieldSharing['ibanDefault'] = {'mode':'private','league':true,'emails':['a@b.it','b@b.it']}

    for (final k in _kAlwaysPublicFields) {
      next[k] = <String, dynamic>{
        'mode': 'public',
        'league': false,
        'allLeagues': false,
        'emails': <String>[],

        // campi extra compatibilità (se il tuo schema li usa)
        'allLeaguesScope': 'ALL_MEMBERS',
        'leagueScopes': <String, String>{},
        'users': <String>[],
        'compartos': <String>[],
      };
    }

    _fieldSharing = next;
  }



  // -------------------- AVATAR DRAG + PINCH --------------------
  final GlobalKey _profileHeaderKey = GlobalKey();

  bool _avatarUserInited = false;
  Offset _avatarUserCenter = Offset.zero; // centro avatar (coordinate header pinned)
  double _avatarUserScale = 1.0;

  Offset _avatarStartCenter = Offset.zero;
  double _avatarStartScale = 1.0;
  Offset _avatarStartFocal = Offset.zero;

  static const double _kAvatarMinScale = 0.65;
  static const double _kAvatarMaxScale = 1.55;




  Widget _avatarOverlayLayer({
    required double t, // 1 espanso, 0 collassato
    required String? photoUrl,
    required bool canEditImages,
    required bool hasCover,
    required String name,
    required String email,
  }) {

    final pinnedCtx = _profileHeaderKey.currentContext;
    if (pinnedCtx == null) return const SizedBox.shrink();

    final pinnedBox = pinnedCtx.findRenderObject() as RenderBox?;
    if (pinnedBox == null || !pinnedBox.hasSize) return const SizedBox.shrink();

    final theme = Theme.of(context);

    final double kTopAreaH = (_pinnedH - _kTabsAreaH).clamp(56.0, 260.0); // area avatar+testi (senza tabs)
    const double rCollapsed = 24.0; // pinned leggermente più grande
    const double rExpandedBase = 80.0;  // grandezza della foto profilo proposta dal sistema

    final w = pinnedBox.size.width;

    // init posizione consigliata (solo una volta)
    if (!_avatarUserInited && w > 0) {
      _avatarUserInited = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _avatarUserCenter = Offset(w / 2, -(rExpandedBase * 0.50)); // altezza della disposizione della foto profilo proposta dal sistema
          _avatarUserScale = 1.0;
        });
      });
    }

    // target collassato: dentro pinned a sinistra
    // ✅ spazio riservato al bottone sinistro nel pinned (solo se esiste)
    final bool showPinnedLeftBtn = (_isSelf && _editMode) || !widget.embedded;

    const double kPinnedOuterPad = 8.0;
    const double kPinnedBtnSlotW = 52.0; // 40 + padding orizzontale (6+6)
    const double kPinnedGapAfterBtn = 8.0;

    final leftSlot = showPinnedLeftBtn
        ? (kPinnedOuterPad + kPinnedBtnSlotW + kPinnedGapAfterBtn)
        : kPinnedOuterPad;

    final collapsedCenter = Offset(leftSlot + rCollapsed, kTopAreaH / 2);



    // target espanso: posizione scelta dall’utente (coordinate pinned)
    final freeCenter = (_avatarUserCenter == Offset.zero)
        ? Offset(w / 2, -(rExpandedBase * 0.55))
        : _avatarUserCenter;

    // radius animato + scala utente
    final baseR = _lerp(rCollapsed, rExpandedBase, t);
    final sc = _lerp(
      1.0,
      _avatarUserScale.clamp(_kAvatarMinScale, _kAvatarMaxScale),
      t,
    );
    final r = baseR * sc;
    final size = r * 2;

    // posizione animata tra pinned(sinistra) e free(utente)
    final center = Offset.lerp(
      collapsedCenter,
      freeCenter,
      Curves.easeOutCubic.transform(t),
    )!;

    Offset clampFreeCenter(Offset candidateCenter, double candidateScale) {
      final s = (rExpandedBase * 2) *
          candidateScale.clamp(_kAvatarMinScale, _kAvatarMaxScale);
      const pad = 8.0;

      final maxUp = hasCover
          ? (_kExpandedHeight - kToolbarHeight - 24).clamp(220.0, 520.0)
          : 18.0;

      final minX = pad + s / 2;
      final maxX = w - pad - s / 2;

      final minY = -maxUp + s / 2;
      final maxY = kTopAreaH - s / 2 - 4;

      return Offset(
        candidateCenter.dx.clamp(minX, maxX).toDouble(),
        candidateCenter.dy.clamp(minY, maxY).toDouble(),
      );
    }

    // gesture attive solo quando abbastanza espanso
    final interactive = t > 0.55;

    // quando entra nel pinned sparisce l'icona modifica
    final showEditIcon = canEditImages && t > 0.60;

    final p = (photoUrl != null && photoUrl.trim().isNotEmpty)
        ? _bust(photoUrl.trim(), _vPhoto)
        : null;

    // 0 quando collassato (pinned), 1 quando espanso
    final tt =
    Curves.easeOutCubic.transform(((t - 0.10) / 0.90).clamp(0.0, 1.0));

    // bordo sottilissimo anche nel pinned: 1px -> 3px
    final borderPx = _lerp(1.0, 3.0, tt);

    // ombra che svanisce verso pinned
    final shadowOpacity = 0.25 * tt;
    final blur = _lerp(0.0, 18.0, tt);
    final dy = _lerp(0.0, 6.0, tt);

    // colore bordo sempre visibile
    final borderColor = theme.brightness == Brightness.dark
        ? Colors.white.withOpacity(_lerp(0.35, 0.95, tt))
        : Colors.white.withOpacity(_lerp(0.55, 1.0, tt));






    // ----------------- AUTO “SCAPPA TESTO” (DY + DX) -----------------
    const double kEdgePad = 8.0; // ✅ “sfiora” il bordo

    final collapsedTextPad = leftSlot + (rCollapsed * 2) + 12;
    final leftPadText = _lerp(
      collapsedTextPad,
      kEdgePad,
      t,
    );


// tienilo un pelo più basso ma NON troppo, così resta margine per DY
    final baseDy = _lerp(0.0, 10.0, t);

// ---- misura reale (non stimata) della larghezza testo ----
    final maxW = (w - (kEdgePad * 2)).clamp(0.0, w);

    final nameStyle = TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: _lerp(16.5, 18.5, t),
    );

    final emailStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    );

    double measure1(String text, TextStyle style) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxW);
      return tp.width;
    }

    final safeName = name.isEmpty ? 'Profilo' : name;
    final nameW = measure1(safeName, nameStyle);
    final emailW = measure1(email, emailStyle);
    final estW = (((nameW > emailW) ? nameW : emailW) + 2.0).clamp(0.0, maxW);

// ---- box testo (più realistico) ----
    const double textH = 42.0; // un pelo più “sicuro” di 36
    final textTop = (kTopAreaH / 2 - textH / 2) + baseDy;

// left interpolato: pinned a sinistra, espanso centrato
    final textLeft = _lerp(leftPadText, (w - estW) / 2, t);

    final textRect = Rect.fromLTWH(
      textLeft,
      textTop,
      estW,
      textH,
    );

    final avatarRect = Rect.fromCenter(
      center: center,
      width: size,
      height: size,
    );

    double extraDy = 0.0;

// 1) provo a scappare in basso (DY)
    if (avatarRect.overlaps(textRect.inflate(2))) {
      final needed = (avatarRect.bottom + 6.0) - textRect.top;
      if (needed > 0) {
        final maxExtra = (kTopAreaH - 4) - textRect.bottom; // non invadere tabs
        extraDy = needed.clamp(0.0, maxExtra > 0 ? maxExtra : 0.0);
      }
    }

// 2) se ancora overlap, scappo in orizzontale (DX)
    final shiftedText = textRect.shift(Offset(0, extraDy));
    double extraDx = 0.0;

    if (avatarRect.overlaps(shiftedText.inflate(2))) {
      final preferRight = avatarRect.center.dx <= w / 2;

      if (preferRight) {
        extraDx = (avatarRect.right + 10.0) - shiftedText.left;
      } else {
        extraDx = (avatarRect.left - 10.0) - shiftedText.right;
      }

      // ✅ clamp dentro i margini kEdgePad (4px), non 16px
      final minDx = kEdgePad - shiftedText.left;
      final maxDx = (w - kEdgePad) - shiftedText.right;

      if (minDx <= maxDx) {
        extraDx = extraDx.clamp(minDx, maxDx).toDouble();
      } else {
        extraDx = 0.0;
      }
    }

// IMPORTANT: non notificare durante build → post-frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if ((_nameAvoidDy.value - extraDy).abs() > 0.5) {
        _nameAvoidDy.value = extraDy;
      }
      if ((_nameAvoidDx.value - extraDx).abs() > 0.5) {
        _nameAvoidDx.value = extraDx;
      }
    });
// ------------------------------------------------------



    return CompositedTransformFollower(
      link: _profileLink,
      showWhenUnlinked: false,
      offset: Offset(center.dx - size / 2, center.dy - size / 2),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openImagesFullScreen(initialIndex: 1),
              onScaleStart: interactive
                  ? (d) {
                _avatarStartScale = _avatarUserScale;
                _avatarStartCenter = _avatarUserCenter;
                _avatarStartFocal = pinnedBox.globalToLocal(d.focalPoint);
              }
                  : null,
              onScaleUpdate: interactive
                  ? (d) {
                final localFocal = pinnedBox.globalToLocal(d.focalPoint);
                final delta = localFocal - _avatarStartFocal;

                final nextScale = (_avatarStartScale * d.scale)
                    .clamp(_kAvatarMinScale, _kAvatarMaxScale);

                final nextCenter = _avatarStartCenter + delta;
                final clamped = clampFreeCenter(nextCenter, nextScale);

                setState(() {
                  _avatarUserScale = nextScale;
                  _avatarUserCenter = clamped;
                });
              }
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    if (tt > 0.01)
                      BoxShadow(
                        blurRadius: blur,
                        spreadRadius: 1 * tt,
                        offset: Offset(0, dy),
                        color: Colors.black.withOpacity(shadowOpacity),
                      ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: borderColor,
                  ),
                  padding: EdgeInsets.all(borderPx),
                  child: ClipOval(
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: _smartImage(
                        p,
                        fit: BoxFit.cover,
                        placeholder: Center(child: Icon(Icons.person, size: r)),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (showEditIcon)
              Positioned(
                right: -12,
                bottom: 12,
                child: PopupMenuButton<String>(
                  tooltip: 'Foto profilo',
                  onSelected: (v) {
                    if (v == 'view') _openImagesFullScreen(initialIndex: 1);
                    if (v == 'edit') _pickUploadAndSetImage(isCover: false);
                    if (v == 'remove') _removeImage(isCover: false);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'view', child: Text('Visualizza')),
                    PopupMenuItem(value: 'edit', child: Text('Modifica')),
                    PopupMenuItem(value: 'remove', child: Text('Rimuovi')),
                  ],
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor:
                    theme.colorScheme.primaryContainer.withOpacity(0.95),
                    child: const Icon(Icons.camera_alt, size: 18),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }




  Widget _whiteRingIcon({
    required ThemeData theme,
    required IconData icon,
    double radius = 18,
  }) {
    const ring = 2.5;

    return Container(
      padding: const EdgeInsets.all(ring),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.95),
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            offset: const Offset(0, 4),
            color: Colors.black.withOpacity(0.18),
          ),
        ],
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: theme.colorScheme.primaryContainer.withOpacity(0.95),
        child: Icon(
          icon,
          size: radius, // proporzionato
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
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


  final Map<String, String> _resolvedHttpUrlCache = {}; // cache risoluzione

  Future<String?> _resolveToHttpUrl(String raw) async {
    final u = raw.trim();
    if (u.isEmpty) return null;

    // già http/https
    if (u.startsWith('http://') || u.startsWith('https://')) return u;

    // cache
    final cached = _resolvedHttpUrlCache[u];
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      // gs://bucket/path...
      if (u.startsWith('gs://')) {
        final httpUrl = await FirebaseStorage.instance.refFromURL(u).getDownloadURL();
        _resolvedHttpUrlCache[u] = httpUrl;
        return httpUrl;
      }

      // path tipo: users/<uid>/profile.jpg oppure leagues/<leagueId>/members/<uid>/profile.jpg
      final httpUrl = await FirebaseStorage.instance.ref().child(u).getDownloadURL();
      _resolvedHttpUrlCache[u] = httpUrl;
      return httpUrl;
    } catch (_) {
      return null;
    }
  }





// per "Annulla" (ripristino valori)
  Map<String, dynamic>? _lastUserData;
  Map<String, dynamic>? _lastMemberData;

  void _enterEditMode() {
    setState(() => _editMode = true);
  }

  void _cancelEdit() {
    // ripristina i controller senza ricaricare schermata
    final u = _lastUserData ?? {};
    final m = _lastMemberData ?? {};
    _initFromUserAndMember(u, m);
    setState(() => _editMode = false);
  }

  Future<void> _saveAllAndExit() async {
    // salva quello che vuoi salvare (globale + lega) e poi esce
    await _saveGlobal();
    await _saveLeague();
    if (mounted) setState(() => _editMode = false);
  }






  bool _isFirebaseStorageUrl(String url) {
    final u = url.trim();
    return u.startsWith('gs://') ||
        u.contains('firebasestorage.googleapis.com') ||
        u.contains('firebasestorage.app') ||
        u.contains('storage.googleapis.com');
  }





  Widget _smartImage(
      String? url, {
        required BoxFit fit,
        Widget? placeholder,
      }) {
    final raw = (url ?? '').trim();
    final ph = placeholder ?? const Center(child: Icon(Icons.camera_alt, size: 60));
    if (raw.isEmpty) return ph;

    Widget cached(String httpUrl) {
      final u = httpUrl.trim();
      if (u.isEmpty) return ph;

      return CachedNetworkImage(
        imageUrl: u,
        fit: fit,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => ph,
        errorWidget: (_, __, ___) => ph,
      );

    }

    // 1) http/https -> cached diretto
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return cached(raw);
    }

    // 2) gs:// o path -> risolvo a https una volta e poi cached
    if (_isFirebaseStorageUrl(raw)) {
      return FutureBuilder<String?>(
        future: _resolveToHttpUrl(raw),
        builder: (context, snap) {
          final httpUrl = (snap.data ?? '').trim();
          if (httpUrl.isEmpty) return ph;
          return cached(httpUrl);
        },
      );
    }

    return ph;
  }




  // ==========================================================
// ✅ UPDATE SOLO SU Users/{uid} (NO members)
// ==========================================================

// Campi “globali” che vogliamo mantenere coerenti sia a root che in profile.<field>
// (così il tuo codice che legge da user['profile'] continua a funzionare)
  static const Set<String> _kMirrorToProfileFields = {
    'nome',
    'cognome',
    'nickname',
    'photoUrl',
    'coverUrl',
    'photoV',
    'coverV',
  };

  Map<String, dynamic> _nestPath(String path, dynamic value) {
    final parts = path.split('.').where((p) => p.trim().isNotEmpty).toList();
    if (parts.isEmpty) return <String, dynamic>{};

    Map<String, dynamic> out = <String, dynamic>{};
    Map<String, dynamic> cur = out;

    for (int i = 0; i < parts.length; i++) {
      final k = parts[i];
      if (i == parts.length - 1) {
        cur[k] = value;
      } else {
        final next = <String, dynamic>{};
        cur[k] = next;
        cur = next;
      }
    }
    return out;
  }

  Map<String, dynamic> _deepMergeMap(Map<String, dynamic> base, Map<String, dynamic> add) {
    final out = Map<String, dynamic>.from(base);
    add.forEach((k, v) {
      final cur = out[k];
      if (cur is Map && v is Map) {
        out[k] = _deepMergeMap(
          Map<String, dynamic>.from(cur as Map),
          Map<String, dynamic>.from(v as Map),
        );
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  Future<void> _updateUserField(String field, dynamic value) async {
    final uid = widget.userId;
    final ref = FirebaseFirestore.instance.collection('Users').doc(uid);

    // payload base
    Map<String, dynamic> payload = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // 1) scrivo il campo richiesto (supporta anche "a.b.c" come path reale via nested map)
    payload = _deepMergeMap(payload, _nestPath(field, value));

    // 2) se è un campo “globale”, lo specchio anche in profile.<field>
    final isAlreadyProfilePath = field.startsWith('profile.');
    if (!isAlreadyProfilePath && _kMirrorToProfileFields.contains(field)) {
      payload = _deepMergeMap(payload, _nestPath('profile.$field', value));
    }

    await ref.set(payload, SetOptions(merge: true));
  }




  String _s(dynamic v) => (v ?? '').toString().trim();
  String? _nullIfEmpty(String v) => v.trim().isEmpty ? null : v.trim();

  Map<String, dynamic> _map(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }

  List<String> _listStr(dynamic v) {
    if (v is List) return v.map((e) => _s(e)).where((e) => e.isNotEmpty).toList();
    return <String>[];
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool get _isSelf {
    final me = FirebaseAuth.instance.currentUser;
    return me != null && me.uid == widget.userId;
  }



  void _onOuterScroll() {
    final maxCollapse = (_kExpandedHeight - kToolbarHeight).clamp(1.0, double.infinity);
    final c = (_outerCtrl.hasClients ? (_outerCtrl.offset / maxCollapse) : 0.0)
        .clamp(0.0, 1.0);

    final t = (1.0 - c).clamp(0.0, 1.0);
    _collapseT.value = t;

    // ✅ altezza pinned: grande con cover, minima a cover sparita
    final desiredH = _lerp(_kBottomBarCollapsedH, _kBottomBarExpandedH, t);
    if ((desiredH - _pinnedH).abs() > 0.5) {
      if (!mounted) return;
      setState(() => _pinnedH = desiredH);
    }

  }





  @override
  void initState() {
    super.initState();
    _outerCtrl.addListener(_onOuterScroll);
  }


  @override
  void dispose() {
    _nome.dispose();
    _cognome.dispose();
    _nickname.dispose();
    _thought.dispose();
    _cf.dispose();
    _ibanDefault.dispose();
    _tel.dispose();
    _via.dispose();
    _cap.dispose();
    _citta.dispose();
    _prov.dispose();
    _naz.dispose();

    _org.dispose();
    _comparto.dispose();
    _jobRole.dispose();
    _telLeague.dispose();
    _ibanLeague.dispose();

    _collapseT.dispose();
    _outerCtrl.dispose();
    _nameAvoidDy.dispose();
    _nameAvoidDx.dispose();

    super.dispose();
  }

  Future<void> _launchMaps() async {
    final address = [
      _via.text.trim(),
      _cap.text.trim(),
      _citta.text.trim(),
      _prov.text.trim(),
      _naz.text.trim(),
    ].where((e) => e.isNotEmpty).join(', ');

    if (address.isEmpty) {
      _toast('Indirizzo non compilato.');
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}',
    );

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _toast('Impossibile aprire Google Maps.');
    }
  }

  void _initFromMemberOnly(Map<String, dynamic> member) {
    final org = _map(member['org']);
    final overrides = _map(member['overrides']);
    final oRec = _map(overrides['recapiti']);
    final oAna = _map(overrides['anagrafica']);

    _org.text = _s(org['organizzazione']);
    _comparto.text = _s(org['comparto']);
    _jobRole.text = _s(org['jobRole']);

    _telLeague.text = _s(oRec['telefono']);
    _emailsExtraLeague = _listStr(oRec['emailSecondarie']);
    _ibanLeague.text = _s(oAna['iban']);

    _customLeague = _map(member['custom']);
  }

  void _initFromUserAndMember(Map<String, dynamic> user, Map<String, dynamic> member) {
    final p = _map(user['profile']); // ✅ profilo FLAT (ma supporta legacy annidato)

    // legacy sections (se presenti)
    final recap = _map(p['recapiti']);
    final ana = _map(p['anagrafica']);
    final res = _map(p['residenza']);

    _nome.text = _s(p['nome']);
    _cognome.text = _s(p['cognome']);
    _nickname.text = _s(p['nickname']);
    _thought.text = _s(p['thought']);

    // ✅ FLAT preferred (fallback legacy)
    _tel.text = _s(p['telefono'] ?? recap['telefono']);
    _emailsExtra = _listStr(p['emailSecondarie'] ?? recap['emailSecondarie']);

    _cf.text = _s(p['codiceFiscale'] ?? ana['codiceFiscale']);
    _ibanDefault.text = _s(p['iban'] ?? p['ibanDefault'] ?? ana['ibanDefault']);

    _via.text = _s(p['residenzaVia'] ?? res['via']);
    _cap.text = _s(p['residenzaCap'] ?? res['cap']);
    _citta.text = _s(p['residenzaCitta'] ?? res['citta']);
    _prov.text = _s(p['residenzaProvincia'] ?? res['provincia']);
    _naz.text = _s(p['residenzaNazione'] ?? res['nazione']);

    _customGlobal = _map(p['custom']);

    // ✅ Sync valori HR (flat) da controllers + profile
    _userValues = Map<String, dynamic>.from(p);
    // keep legacy mapped fields in sync
    _userValues['nome'] = _nome.text.trim();
    _userValues['cognome'] = _cognome.text.trim();
    _userValues['nickname'] = _nickname.text.trim();
    _userValues['thought'] = _thought.text.trim();
    _userValues['telefono'] = _tel.text.trim();
    _userValues['codiceFiscale'] = _cf.text.trim();
    _userValues['ibanDefault'] = _ibanDefault.text.trim();
    _userValues['emailSecondarie'] = List<String>.from(_emailsExtra);
    _userValues['addressResidence'] = {
      'formatted': [
        _via.text.trim(),
        _cap.text.trim(),
        _citta.text.trim(),
        _prov.text.trim(),
        _naz.text.trim(),
      ].where((e) => e.isNotEmpty).join(', '),
      'street': _via.text.trim(),
      'zip': _cap.text.trim(),
      'city': _citta.text.trim(),
      'province': _prov.text.trim(),
      'country': _naz.text.trim(),
    };

    // ✅ Foto profilo (priorità: profile.photoUrl > user.photoUrl)
    _photoUrl = _nullIfEmpty(_s(p['photoUrl'] ?? user['photoUrl']));

    // ✅ Cover (priorità: profile.coverUrl > user.coverUrl)
    _coverUrl = _nullIfEmpty(_s(p['coverUrl'] ?? user['coverUrl']));

    // ✅ PRIVACY / FIELD SHARING
    final rawPrivacy = _map(p['privacy']);
    final legacy1 = _map(p['_fieldSharing']);
    final legacy2 = _map(p['fieldSharing']);
    final legacy3 = _map(user['_fieldSharing']);

    final toUse = rawPrivacy.isNotEmpty
        ? rawPrivacy
        : (legacy1.isNotEmpty
        ? legacy1
        : (legacy2.isNotEmpty ? legacy2 : legacy3));

    _fieldSharing = UserService.normalizePrivacy(toUse);

    // ✅ Nome/Cognome sempre pubblici
    _enforceAlwaysPublicPrivacy();

    // ✅ inizializza la parte lega
    _initFromMemberOnly(member);

    // ✅ auto-sync foto profilo dall'account (Google/Facebook/Apple) se manca
    if (!_autoSyncedAuthPhoto) {
      _autoSyncedAuthPhoto = true;
      final authUrl = FirebaseAuth.instance.currentUser?.photoURL;

      if ((_photoUrl == null || _photoUrl!.isEmpty) && authUrl != null && authUrl.isNotEmpty) {
        // aggiorno local (UI)
        _photoUrl = authUrl;

        scheduleMicrotask(() async {
          try {
            // ✅ SOLO Users (NO members)
            await _updateUserField('photoUrl', authUrl);

            // (opzionale ma consigliato) bump versione per bust cache
            final v = DateTime.now().millisecondsSinceEpoch;
            await _updateUserField('photoV', v);
          } catch (_) {
            // se regole bloccano, non rompo la UI
          }
          if (mounted) setState(() {});
        });
      }
    }

    // ✅ Sync valori HR di lega (flat)
    _memberValues = Map<String, dynamic>.from(member);
    _memberValues['org'] = _map(member['org']);
    _memberValues['overrides'] = _map(member['overrides']);

  }






  Future<void> _saveGlobal() async {
    if (!_isSelf) {
      _toast('Puoi salvare l’anagrafica globale solo del tuo profilo.');
      return;
    }

    final nome = _nome.text.trim();
    final cognome = _cognome.text.trim();

    if (nome.isEmpty || cognome.isEmpty) {
      _toast('Nome e Cognome sono obbligatori.');
      return;
    }

    setState(() => _saving = true);
    try {
      final profile = _currentProfilePayloadForSync();

      // ✅ Nome/Cognome sempre pubblici
      _enforceAlwaysPublicPrivacy();


      // ✅ IMPORTANTISSIMO: salva anche la privacy per campo
      await UserService.updateMyGlobalProfileAndSync(
        profile: profile,
        privacy: _fieldSharing, // <-- FIX
      );

      _toast('Anagrafica globale salvata.');
    } catch (e) {
      _toast('Errore salvataggio: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }



  Map<String, dynamic> _currentProfilePayloadForSync() {
    // ✅ PROFILO FLAT (no più anidamenti: anagrafica/recapiti/residenza ecc.)
    // ✅ Manteniamo comunque i delete dei vecchi rami legacy per migrazione.
    return {
      // sempre pubblici (enforced server-side)
      'nome': _nome.text.trim(),
      'cognome': _cognome.text.trim(),
      'nickname': _nullIfEmpty(_nickname.text),
      'thought': _nullIfEmpty(_thought.text),

      'photoUrl': _photoUrl,
      'coverUrl': _coverUrl,
      'photoV': _vPhoto,
      'coverV': _vCover,

      // contatti
      'telefono': _nullIfEmpty(_tel.text),
      'emailSecondarie': _emailsExtra,

      // anagrafica (sensibili di default in privacy UI)
      'codiceFiscale': _nullIfEmpty(_cf.text),
      'iban': _nullIfEmpty(_ibanDefault.text),

      // residenza
      'residenzaVia': _nullIfEmpty(_via.text),
      'residenzaCap': _nullIfEmpty(_cap.text),
      'residenzaCitta': _nullIfEmpty(_citta.text),
      'residenzaProvincia': _nullIfEmpty(_prov.text),
      'residenzaNazione': _nullIfEmpty(_naz.text),

      // custom (campi dinamici)
      'custom': _customGlobal,

      // 🧹 pulizia legacy (se in passato avevi profilo annidato)
      'recapiti': FieldValue.delete(),
      'anagrafica': FieldValue.delete(),
      'residenza': FieldValue.delete(),
    };
  }

  Future<void> _saveLeague() async {
    setState(() => _saving = true);
    try {
      final overrides = <String, dynamic>{
        'recapiti': {
          'telefono': _nullIfEmpty(_telLeague.text),
          'emailSecondarie': _emailsExtraLeague,
        },
        'anagrafica': {
          'iban': _nullIfEmpty(_ibanLeague.text),
        },
      };

      final org = <String, dynamic>{
        'organizzazione': _nullIfEmpty(_org.text),
        'comparto': _nullIfEmpty(_comparto.text),
        'jobRole': _nullIfEmpty(_jobRole.text),
      };

      await UserService.updateMemberData(
        leagueId: widget.leagueId,
        uid: widget.userId,
        overrides: overrides,
        org: org,
        custom: _customLeague,
      );

      _toast('Dati lega salvati.');
    } catch (e) {
      _toast('Errore salvataggio lega: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _canEditTarget() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return false;
    return UserService.canEditMember(
      leagueId: widget.leagueId,
      actorUid: me.uid,
      targetUid: widget.userId,
    );
  }




  // ✅ Carica SOLO i campi "shared" visibili quando NON sei self
  Future<void> _loadVisibleSharedFieldsForNotSelf({
    required String leagueId,
    required String targetUid,
  }) async {
    try {
      final res = await UserService.fetchVisibleFieldsForViewer(
        leagueId: leagueId,
        targetUid: targetUid,
      );

      final shared = (res['sharedFields'] as Map?)?.cast<String, dynamic>() ?? {};

      // (opzionale) pulisco prima, così se non ho accesso restano vuoti
      _tel.text = '';
      _ibanDefault.text = '';
      _cf.text = '';
      _via.text = '';
      _cap.text = '';
      _citta.text = '';
      _prov.text = '';
      _naz.text = '';

      // telefono
      if (shared.containsKey('telefono')) {
        _tel.text = (shared['telefono'] ?? '').toString();
      }

      // iban
      if (shared.containsKey('ibanDefault')) {
        _ibanDefault.text = (shared['ibanDefault'] ?? '').toString();
      }

      // codice fiscale
      if (shared.containsKey('codiceFiscale')) {
        _cf.text = (shared['codiceFiscale'] ?? '').toString();
      }

      // residenza
      if (shared['residenza'] is Map) {
        final r = Map<String, dynamic>.from(shared['residenza']);
        _via.text = (r['via'] ?? '').toString();
        _cap.text = (r['cap'] ?? '').toString();
        _citta.text = (r['citta'] ?? '').toString();
        _prov.text = (r['provincia'] ?? '').toString();
        _naz.text = (r['nazione'] ?? '').toString();
      }

      if (mounted) setState(() {});
    } catch (e) {
      // non blocco la UI se qualcosa non è disponibile
      if (kDebugMode) {
        debugPrint('[_loadVisibleSharedFieldsForNotSelf] errore: $e');
      }
    }
  }

// ✅ La chiamo UNA SOLA VOLTA quando entro nel ramo "non self"
  void _kickLoadSharedNotSelfOnce() {
    if (_isSelf) return;
    if (_notSelfSharedLoaded) return;

    _notSelfSharedLoaded = true; // set subito per evitare doppie chiamate

    scheduleMicrotask(() async {
      await _loadVisibleSharedFieldsForNotSelf(
        leagueId: widget.leagueId,
        targetUid: widget.userId,
      );
    });
  }






  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final mRef = FirebaseFirestore.instance
        .collection('Leagues')
        .doc(widget.leagueId)
        .collection('members')
        .doc(widget.userId);

    final uRef = FirebaseFirestore.instance.collection('Users').doc(widget.userId);

    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    final viewerRef = viewerUid == null
        ? null
        : FirebaseFirestore.instance
        .collection('Leagues')
        .doc(widget.leagueId)
        .collection('members')
        .doc(viewerUid);


    // =========================
    // Ctrl+Enter / Cmd+Enter (Salva)
    // =========================
    void handleSaveShortcut() {
      if (_saving) return;
      if (!_isSelf) return;
      if (!_editMode) return;
      _saveAllAndExit();
    }


    final body = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: mRef.snapshots(),
      builder: (context, mSnap) {
        if (!mSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final member = mSnap.data!.data() ?? {};

        // ✅ NON SELF: non leggere Users/{uid}
        if (!_isSelf) {
          if (!_inited) {
            _initFromMemberOnly(member);

            // nome/foto per header
            _nome.text = _s(member['displayNome'] ?? member['nome']);
            _cognome.text = _s(member['displayCognome'] ?? member['cognome']);
            _photoUrl = _nullIfEmpty(_s(member['photoUrl']));
            _coverUrl = _nullIfEmpty(_s(member['coverUrl']));

            int asInt(dynamic v) {
              if (v is int) return v;
              if (v is num) return v.toInt();
              return int.tryParse((v ?? '').toString()) ?? 0;
            }

            _vPhoto = asInt(member['photoV']);
            _vCover = asInt(member['coverV']);

            _inited = true;

            // ✅ carica visibili (una sola volta)
            _kickLoadSharedNotSelfOnce();
          }

          final emailLogin = _s(member['emailLogin'] ?? member['email']);

          return FutureBuilder<bool>(
            future: _canEditTarget(),
            builder: (context, canSnap) {
              final canEditImages = canSnap.data ?? false;

              return _buildNormalScaffold(
                member: member,
                emailLogin: emailLogin,
                readOnly: true,
                canEditImages: canEditImages,
              );
            },
          );
        }

        // ✅ SELF: ok leggere Users/{uid}
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: uRef.snapshots(),
          builder: (context, uSnap) {
            if (!uSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final user = uSnap.data!.data() ?? {};
            final emailLogin = _s(user['email']);

            _syncImagesFromSnapshots(user: user, member: member);

            _lastUserData = user;
            _lastMemberData = member;
            _viewerMemberData = member;

            if (!_inited) {
              _initFromUserAndMember(user, member);
              _inited = true;
            }

            return _buildNormalScaffold(
              member: member,
              emailLogin: emailLogin,
              readOnly: !_editMode,
              canEditImages: true, // self -> sempre
            );
          },
        );
      },
    );

    final content = AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: theme.colorScheme.surface,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: theme.colorScheme.surface,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: body,
    );

    // ✅ Se embedded: NON creare Scaffold (lo farà il pannello padre)
    //    MA aggiungiamo comunque shortcuts
    if (widget.embedded) {
      return Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter, control: true): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter, meta: true): ActivateIntent(),

          // (opzionale) Ctrl+S / Cmd+S - su Web può essere catturato dal browser
          SingleActivator(LogicalKeyboardKey.keyS, control: true): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.keyS, meta: true): ActivateIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<Intent>(
              onInvoke: (intent) {
                handleSaveShortcut();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: content,
          ),
        ),
      );
    }

    // ✅ Se NON embedded: 1 SOLO Scaffold (questo)
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter, control: true): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter, meta: true): ActivateIntent(),

        // (opzionale) Ctrl+S / Cmd+S - su Web può essere catturato dal browser
        SingleActivator(LogicalKeyboardKey.keyS, control: true): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, meta: true): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<Intent>(
            onInvoke: (intent) {
              handleSaveShortcut();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(body: content),
        ),
      ),
    );
  }




  Widget _buildNormalScaffold({
    required Map<String, dynamic> member,
    required String emailLogin,
    required bool readOnly,
    required bool canEditImages,
  }) {
    final theme = Theme.of(context);

    final fullName = ('${_cognome.text} ${_nome.text}').trim();

    final coverBusted = (_coverUrl != null && _coverUrl!.trim().isNotEmpty)
        ? _bust(_coverUrl!.trim(), _vCover)
        : null;

    final hasCover = (coverBusted ?? '').trim().isNotEmpty;

    // --- misure bottoni compatte ---
    const double btnW = 40;
    const double btnH = 34;
    const double r = 14;

    // t = 1 espanso (cover visibile), t = 0 collassato (cover sparita)
    Widget coverGlassBtn({
      required double t,
      required IconData icon,
      required String tooltip,
      required VoidCallback? onTap,
    }) {
      final exp = t.clamp(0.0, 1.0);

      final bg = Colors.black.withOpacity(0.22 + (0.10 * exp));
      final border = Colors.white.withOpacity(0.18 + (0.10 * exp));
      final shadow = Colors.black.withOpacity(0.22);

      return Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              boxShadow: [
                BoxShadow(
                  color: shadow,
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(r),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    child: Container(
                      width: btnW,
                      height: btnH,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(r),
                        border: Border.all(color: border, width: 1),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AbsorbPointer(
      absorbing: _saving,
      child: DefaultTabController(
        length: 2,
        child: SafeArea(
          top: true,
          bottom: true,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              NestedScrollView(
                controller: _outerCtrl,
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    // ✅ SliverAppBar “solo cover”: collassa a 0 e sparisce
                    AnimatedBuilder(
                      animation: _collapseT,
                      builder: (_, __) {
                        final t = _collapseT.value.clamp(0.0, 1.0);

                        final coverBtnsOpacity = Curves.easeOutCubic.transform(
                          ((t - 0.35) / 0.65).clamp(0.0, 1.0),
                        );

                        return SliverAppBar(
                          primary: false,
                          pinned: false,
                          floating: false,
                          snap: false,
                          elevation: 0,
                          backgroundColor: Colors.transparent,
                          surfaceTintColor: Colors.transparent,
                          expandedHeight: _kExpandedHeight,
                          collapsedHeight: 0,
                          toolbarHeight: 0,
                          flexibleSpace: FlexibleSpaceBar(
                            collapseMode: CollapseMode.parallax,
                            background: Stack(
                              fit: StackFit.expand,
                              children: [
                                _coverOnly(
                                  coverUrl: coverBusted,
                                  canEdit: canEditImages,
                                ),

                                Positioned(
                                  top: 8,
                                  left: 8,
                                  right: 8,
                                  child: IgnorePointer(
                                    ignoring: coverBtnsOpacity < 0.05,
                                    child: AnimatedOpacity(
                                      duration: const Duration(milliseconds: 120),
                                      opacity: coverBtnsOpacity,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          // ✅ BACK solo se NON embedded
                                          if (!widget.embedded)
                                            coverGlassBtn(
                                              t: t,
                                              icon: Icons.arrow_back,
                                              tooltip: 'Indietro',
                                              onTap: () => Navigator.of(context).maybePop(),
                                            )
                                          else
                                            const SizedBox(width: btnW + 12),

                                          if (_isSelf)
                                            Row(
                                              children: [
                                                if (!_editMode)
                                                  coverGlassBtn(
                                                    t: t,
                                                    icon: Icons.edit,
                                                    tooltip: 'Modifica',
                                                    onTap: _enterEditMode,
                                                  )
                                                else ...[
                                                  coverGlassBtn(
                                                    t: t,
                                                    icon: Icons.close,
                                                    tooltip: 'Annulla',
                                                    onTap: _cancelEdit,
                                                  ),
                                                  coverGlassBtn(
                                                    t: t,
                                                    icon: Icons.check,
                                                    tooltip: 'Salva',
                                                    onTap: _saveAllAndExit,
                                                  ),
                                                ],
                                              ],
                                            )
                                          else
                                            const SizedBox(width: btnW + 12),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    // ✅ pinned header
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _NotifierHeaderDelegate(
                        height: _pinnedH,
                        notifier: _collapseT,
                        builder: (ctx, t) {
                          return _pinnedProfileAndTabs(
                            t: t,
                            name: fullName,
                            email: emailLogin,
                            photoUrl: _photoUrl,
                            canEditImages: canEditImages,
                            hasCover: hasCover,
                          );
                        },
                      ),
                    ),
                  ];
                },

                body: TabBarView(
                  children: [
                    _tabPersonaleTabs(
                      emailLogin: emailLogin,
                      readOnly: readOnly,
                    ),
                    _tabDiLega(
                      userUid: widget.userId,
                      readOnly: readOnly,
                    ),
                  ],
                ),
              ),

              // ✅ AVATAR sempre sopra
              ValueListenableBuilder<double>(
                valueListenable: _collapseT,
                builder: (_, t, __) => _avatarOverlayLayer(
                  t: t,
                  photoUrl: _photoUrl,
                  canEditImages: canEditImages,
                  hasCover: hasCover,
                  name: fullName,
                  email: emailLogin,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }






  Widget _tabPersonaleTabs({
    required String emailLogin,
    required bool readOnly,
  }) {
    final isSelf = _isSelf;

    // ✅ NON-SELF: una sola tab “Visibili”
    if (!isSelf) {
      return DmsTabbedSection(
        tabs: [
          DmsTabSpec(
            id: 'visibili',
            tab: const Tab(child: _TabLabel(icon: Icons.visibility, text: 'Visibili')),
            view: _tabVisibiliNotSelfReadOnly(emailLogin: emailLogin),
          ),
        ],
      );
    }

    // ✅ SELF: tab unica HR
    return DmsTabbedSection(
      tabs: [
        DmsTabSpec(
          id: 'hr',
          tab: const Tab(child: _TabLabel(icon: Icons.badge_outlined, text: 'HR')),
          view: _tabHr(readOnly: readOnly),
        ),
      ],
    );
  }





  Widget _tabVisibiliNotSelfReadOnly({required String emailLogin}) {
    final address = [
      _via.text.trim(),
      _cap.text.trim(),
      _citta.text.trim(),
      _prov.text.trim(),
      _naz.text.trim(),
    ].where((e) => e.isNotEmpty).join(', ');

    final recapiti = <_InfoItem>[];
    if (_tel.text.trim().isNotEmpty) recapiti.add(_InfoItem('Telefono', _tel.text.trim()));
    if (_emailsExtra.isNotEmpty) recapiti.add(_InfoItem('Email secondarie', _emailsExtra.join(', ')));

    final anagrafica = <_InfoItem>[];
    if (_cf.text.trim().isNotEmpty) anagrafica.add(_InfoItem('Codice fiscale', _cf.text.trim()));
    if (_ibanDefault.text.trim().isNotEmpty) anagrafica.add(_InfoItem('IBAN default', _ibanDefault.text.trim()));

    final residenza = <_InfoItem>[];
    if (address.trim().isNotEmpty) residenza.add(_InfoItem('Indirizzo', address));

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _readOnlySectionCard('DATI BASE', [
          _InfoItem('Nome', _nome.text.trim()),
          _InfoItem('Cognome', _cognome.text.trim()),
          _InfoItem('Email login', emailLogin),
        ]),

        if (recapiti.isNotEmpty) _readOnlySectionCard('RECAPITI (VISIBILI)', recapiti),
        if (anagrafica.isNotEmpty) _readOnlySectionCard('ANAGRAFICA (VISIBILE)', anagrafica),
        if (residenza.isNotEmpty) _readOnlySectionCard('RESIDENZA (VISIBILE)', residenza),

        const SizedBox(height: 18),
      ],
    );
  }


  // [REMOVED] _tabPrivate (replaced by HR renderer)

  ) {
  // Stesse chiavi usate sopra
  const kNome = 'nome';
  const kCognome = 'cognome';

  const kTel = 'telefono';
  const kEmailsExtra = 'emailSecondarie';

  const kCf = 'codiceFiscale';
  const kIban = 'ibanDefault';

  const kVia = 'residenza.via';
  const kCap = 'residenza.cap';
  const kCitta = 'residenza.citta';
  const kProv = 'residenza.provincia';
  const kNaz = 'residenza.nazione';

  final privateCustom = _customByPrivacy(wantPrivate: true);

  // ---------- READ ONLY: solo private non vuoti + “con chi è condiviso” ----------
  if (readOnly) {
  final base = <_InfoItem>[];
  if (_isPrivateField(kNome)) base.add(_InfoItem('Nome', _nome.text, fieldKey: kNome));
  if (_isPrivateField(kCognome)) base.add(_InfoItem('Cognome', _cognome.text, fieldKey: kCognome));

  final recapiti = <_InfoItem>[];
  if (_isPrivateField(kTel)) recapiti.add(_InfoItem('Telefono', _tel.text, fieldKey: kTel));
  if (_isPrivateField(kEmailsExtra)) {
  recapiti.add(_InfoItem('Email 2°', _emailsExtra.join(', '), fieldKey: kEmailsExtra));
  }

  final anagrafica = <_InfoItem>[];
  if (_isPrivateField(kCf)) anagrafica.add(_InfoItem('Cod. fiscale', _cf.text, fieldKey: kCf));
  if (_isPrivateField(kIban)) anagrafica.add(_InfoItem('IBAN', _ibanDefault.text, fieldKey: kIban));

  final residenza = <_InfoItem>[];
  if (_isPrivateField(kVia)) residenza.add(_InfoItem('Via', _via.text, fieldKey: kVia));
  if (_isPrivateField(kCap)) residenza.add(_InfoItem('CAP', _cap.text, fieldKey: kCap));
  if (_isPrivateField(kCitta)) residenza.add(_InfoItem('Città', _citta.text, fieldKey: kCitta));
  if (_isPrivateField(kProv)) residenza.add(_InfoItem('Provincia', _prov.text, fieldKey: kProv));
  if (_isPrivateField(kNaz)) residenza.add(_InfoItem('Nazione', _naz.text, fieldKey: kNaz));

  final extra = privateCustom.entries
      .map((e) => _InfoItem(e.key, (e.value ?? '').toString(), fieldKey: 'custom.${e.key}'))
      .toList();

  return ListView(
  padding: const EdgeInsets.all(14),
  children: [
  _readOnlyPrivateCard('DATI BASE (PRIVATE)', base),
  _readOnlyPrivateCard('RECAPITI (PRIVATE)', recapiti),
  _readOnlyPrivateCard('ANAGRAFICA (PRIVATE)', anagrafica),
  _readOnlyPrivateCard('RESIDENZA (PRIVATE)', residenza),
  _readOnlyPrivateCard('CAMPI EXTRA (PRIVATE)', extra),
  const SizedBox(height: 18),
  ],
  );
  }

  // ---------- EDIT MODE: form solo dei campi PRIVATE (anche vuoti) ----------
  return ListView(
  padding: const EdgeInsets.all(14),
  children: [
  const Text('PRIVATE', style: TextStyle(fontWeight: FontWeight.w900)),
  const SizedBox(height: 8),
  const Text(
  'Qui trovi i campi marcati come privati e puoi vedere/modificare la condivisione.',
  style: TextStyle(fontWeight: FontWeight.w600),
  ),
  const SizedBox(height: 16),

  const Text('DATI BASE', style: TextStyle(fontWeight: FontWeight.w800)),
  const SizedBox(height: 10),

  if (_isPrivateField(kNome))
  TextField(
  controller: _nome,
  decoration: InputDecoration(
  labelText: 'Nome *',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kNome, readOnly),
  ),
  ),
  if (_isPrivateField(kNome)) const SizedBox(height: 10),

  if (_isPrivateField(kCognome))
  TextField(
  controller: _cognome,
  decoration: InputDecoration(
  labelText: 'Cognome *',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kCognome, readOnly),
  ),
  ),

  const SizedBox(height: 16),
  const Text('RECAPITI', style: TextStyle(fontWeight: FontWeight.w800)),
  const SizedBox(height: 10),

  if (_isPrivateField(kTel))
  TextField(
  controller: _tel,
  decoration: InputDecoration(
  labelText: 'Telefono',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kTel, readOnly),
  ),
  ),
  if (_isPrivateField(kTel)) const SizedBox(height: 10),

  if (_isPrivateField(kEmailsExtra))
  Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
  Row(
  children: [
  const Expanded(
  child: Text('Email secondarie (PRIVATE)', style: TextStyle(fontWeight: FontWeight.w700)),
  ),
  IconButton(
  tooltip: 'Privacy / Condivisione',
  icon: const Icon(Icons.lock),
  onPressed: () => _editFieldSharing(kEmailsExtra),
  ),
  ],
  ),
  _EmailsEditor(
  title: '',
  emails: _emailsExtra,
  enabled: true,
  onChanged: (v) => setState(() => _emailsExtra = v),
  ),
  ],
  ),

  const SizedBox(height: 16),
  const Text('ANAGRAFICA', style: TextStyle(fontWeight: FontWeight.w800)),
  const SizedBox(height: 10),

  if (_isPrivateField(kCf))
  TextField(
  controller: _cf,
  decoration: InputDecoration(
  labelText: 'Codice fiscale',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kCf, readOnly),
  ),
  ),
  if (_isPrivateField(kCf)) const SizedBox(height: 10),

  if (_isPrivateField(kIban))
  TextField(
  controller: _ibanDefault,
  decoration: InputDecoration(
  labelText: 'IBAN (default)',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kIban, readOnly),
  ),
  ),

  const SizedBox(height: 16),
  const Text('RESIDENZA', style: TextStyle(fontWeight: FontWeight.w800)),
  const SizedBox(height: 10),

  if (_isPrivateField(kVia))
  TextField(
  controller: _via,
  decoration: InputDecoration(
  labelText: 'Via',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kVia, readOnly),
  ),
  ),
  if (_isPrivateField(kVia)) const SizedBox(height: 10),

  Row(
  children: [
  if (_isPrivateField(kCap))
  Expanded(
  child: TextField(
  controller: _cap,
  decoration: InputDecoration(
  labelText: 'CAP',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kCap, readOnly),
  ),
  ),
  ),
  if (_isPrivateField(kCap)) const SizedBox(width: 10),
  if (_isPrivateField(kCitta))
  Expanded(
  child: TextField(
  controller: _citta,
  decoration: InputDecoration(
  labelText: 'Città',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kCitta, readOnly),
  ),
  ),
  ),
  ],
  ),
  const SizedBox(height: 10),

  Row(
  children: [
  if (_isPrivateField(kProv))
  Expanded(
  child: TextField(
  controller: _prov,
  decoration: InputDecoration(
  labelText: 'Provincia',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kProv, readOnly),
  ),
  ),
  ),
  if (_isPrivateField(kProv)) const SizedBox(width: 10),
  if (_isPrivateField(kNaz))
  Expanded(
  child: TextField(
  controller: _naz,
  decoration: InputDecoration(
  labelText: 'Nazione',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kNaz, readOnly),
  ),
  ),
  ),
  ],
  ),

  const SizedBox(height: 16),
  _CustomFieldsEditor(
  title: 'Campi extra (PRIVATE)',
  data: privateCustom,
  enabled: true,
  onChanged: (m) => _mergeCustomFromEditor(m, subsetIsPrivate: true),
  ),

  const SizedBox(height: 16),
  SizedBox(
  height: 48,
  child: ElevatedButton.icon(
  onPressed: _saveGlobal,
  icon: const Icon(Icons.save),
  label: const Text('SALVA (PUBLIC + PRIVATE)'),
  ),
  ),

  const SizedBox(height: 18),
  ],
  );
  }


  // [REMOVED] _tabAnagrafica (replaced by HR renderer)

  ) {
  // Chiavi campo (sharing)
  const kNome = 'nome';
  const kCognome = 'cognome';

  const kTel = 'telefono';
  const kEmailsExtra = 'emailSecondarie';

  const kCf = 'codiceFiscale';
  const kIban = 'ibanDefault';

  const kVia = 'residenza.via';
  const kCap = 'residenza.cap';
  const kCitta = 'residenza.citta';
  const kProv = 'residenza.provincia';
  const kNaz = 'residenza.nazione';

  final address = [
  _via.text.trim(),
  _cap.text.trim(),
  _citta.text.trim(),
  _prov.text.trim(),
  _naz.text.trim(),
  ].where((e) => e.isNotEmpty).join(', ');

  final publicCustom = _customByPrivacy(wantPrivate: false);

  // ---------- READ ONLY (pulito, non cliccabile, solo non vuoti) ----------
  if (readOnly) {
  final base = <_InfoItem>[];
  if (_isPublicField(kNome)) base.add(_InfoItem('Nome', _nome.text));
  if (_isPublicField(kCognome)) base.add(_InfoItem('Cognome', _cognome.text));
  base.add(_InfoItem('Email login', emailLogin)); // sempre visibile

  final recapiti = <_InfoItem>[];
  if (_isPublicField(kTel)) recapiti.add(_InfoItem('Telefono', _tel.text));
  if (_isPublicField(kEmailsExtra)) recapiti.add(_InfoItem('Email 2°', _emailsExtra.join(', ')));

  final anagrafica = <_InfoItem>[];
  if (_isPublicField(kCf)) anagrafica.add(_InfoItem('Cod. fiscale', _cf.text));
  if (_isPublicField(kIban)) anagrafica.add(_InfoItem('IBAN', _ibanDefault.text));

  final residenza = <_InfoItem>[];
  if (_isPublicField(kVia)) residenza.add(_InfoItem('Via', _via.text));
  if (_isPublicField(kCap)) residenza.add(_InfoItem('CAP', _cap.text));
  if (_isPublicField(kCitta)) residenza.add(_InfoItem('Città', _citta.text));
  if (_isPublicField(kProv)) residenza.add(_InfoItem('Provincia', _prov.text));
  if (_isPublicField(kNaz)) residenza.add(_InfoItem('Nazione', _naz.text));

  final extra = <_InfoItem>[
  ...publicCustom.entries.map((e) => _InfoItem(e.key, (e.value ?? '').toString())),
  ];

  return ListView(
  padding: const EdgeInsets.all(14),
  children: [
  _readOnlyCard('DATI BASE', base),
  _readOnlyCard('RECAPITI', recapiti),
  _readOnlyCard('ANAGRAFICA', anagrafica),
  _readOnlyCard('RESIDENZA', residenza),
  _readOnlyCard('CAMPI EXTRA (PUBLIC)', extra),

  // niente cliccabile in readOnly → bottone disabilitato (o rimuovilo se preferisci)
  if (address.trim().isNotEmpty)
  OutlinedButton.icon(
  onPressed: null, // readOnly = non cliccabile
  icon: const Icon(Icons.navigation),
  label: const Text('AVVIA NAVIGAZIONE (Google Maps)'),
  ),

  const SizedBox(height: 18),
  ],
  );
  }

  // ---------- EDIT MODE (form, mostra anche campi vuoti, solo PUBLIC) ----------
  return ListView(
  padding: const EdgeInsets.all(14),
  children: [
  const Text('DATI BASE', style: TextStyle(fontWeight: FontWeight.w800)),
  const SizedBox(height: 10),

  if (_isPublicField(kNome))
  TextField(
  controller: _nome,
  readOnly: readOnly,
  decoration: InputDecoration(
  labelText: 'Nome *',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kNome, readOnly),
  ),
  ),
  if (_isPublicField(kNome)) const SizedBox(height: 10),

  if (_isPublicField(kCognome))
  TextField(
  controller: _cognome,
  readOnly: readOnly,
  decoration: InputDecoration(
  labelText: 'Cognome *',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kCognome, readOnly),
  ),
  ),
  if (_isPublicField(kCognome)) const SizedBox(height: 10),

  TextField(
  controller: _nickname,
  readOnly: readOnly,
  decoration: const InputDecoration(
  labelText: 'Nickname',
  border: OutlineInputBorder(),
  // niente suffix privacy: è pubblico fisso
  ),
  ),
  const SizedBox(height: 10),


  TextFormField(
  readOnly: true,
  initialValue: emailLogin,
  decoration: const InputDecoration(labelText: 'Email login', border: OutlineInputBorder()),
  ),

  const SizedBox(height: 16),
  const Text('RECAPITI', style: TextStyle(fontWeight: FontWeight.w800)),
  const SizedBox(height: 10),

  if (_isPublicField(kTel))
  TextField(
  controller: _tel,
  readOnly: readOnly,
  decoration: InputDecoration(
  labelText: 'Telefono',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kTel, readOnly),
  ),
  ),
  if (_isPublicField(kTel)) const SizedBox(height: 10),

  if (_isPublicField(kEmailsExtra))
  Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
  Row(
  children: [
  const Expanded(
  child: Text('Email secondarie (globali)', style: TextStyle(fontWeight: FontWeight.w700)),
  ),
  IconButton(
  tooltip: 'Privacy / Condivisione',
  icon: Icon(_isPrivateField(kEmailsExtra) ? Icons.lock : Icons.public),
  onPressed: () => _editFieldSharing(kEmailsExtra),
  ),
  ],
  ),
  _EmailsEditor(
  title: '',
  emails: _emailsExtra,
  enabled: !readOnly,
  onChanged: (v) => setState(() => _emailsExtra = v),
  ),
  ],
  ),

  const SizedBox(height: 16),
  const Text('ANAGRAFICA', style: TextStyle(fontWeight: FontWeight.w800)),
  const SizedBox(height: 10),

  if (_isPublicField(kCf))
  TextField(
  controller: _cf,
  readOnly: readOnly,
  decoration: InputDecoration(
  labelText: 'Codice fiscale',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kCf, readOnly),
  ),
  ),
  if (_isPublicField(kCf)) const SizedBox(height: 10),

  if (_isPublicField(kIban))
  TextField(
  controller: _ibanDefault,
  readOnly: readOnly,
  decoration: InputDecoration(
  labelText: 'IBAN (default)',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kIban, readOnly),
  ),
  ),

  const SizedBox(height: 16),
  const Text('RESIDENZA', style: TextStyle(fontWeight: FontWeight.w800)),
  const SizedBox(height: 10),

  if (_isPublicField(kVia))
  TextField(
  controller: _via,
  readOnly: readOnly,
  decoration: InputDecoration(
  labelText: 'Via',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kVia, readOnly),
  ),
  ),
  if (_isPublicField(kVia)) const SizedBox(height: 10),

  Row(
  children: [
  if (_isPublicField(kCap))
  Expanded(
  child: TextField(
  controller: _cap,
  readOnly: readOnly,
  decoration: InputDecoration(
  labelText: 'CAP',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kCap, readOnly),
  ),
  ),
  ),
  if (_isPublicField(kCap)) const SizedBox(width: 10),
  if (_isPublicField(kCitta))
  Expanded(
  child: TextField(
  controller: _citta,
  readOnly: readOnly,
  decoration: InputDecoration(
  labelText: 'Città',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kCitta, readOnly),
  ),
  ),
  ),
  ],
  ),
  const SizedBox(height: 10),

  Row(
  children: [
  if (_isPublicField(kProv))
  Expanded(
  child: TextField(
  controller: _prov,
  readOnly: readOnly,
  decoration: InputDecoration(
  labelText: 'Provincia',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kProv, readOnly),
  ),
  ),
  ),
  if (_isPublicField(kProv)) const SizedBox(width: 10),
  if (_isPublicField(kNaz))
  Expanded(
  child: TextField(
  controller: _naz,
  readOnly: readOnly,
  decoration: InputDecoration(
  labelText: 'Nazione',
  border: const OutlineInputBorder(),
  suffixIcon: _privacySuffix(kNaz, readOnly),
  ),
  ),
  ),
  ],
  ),
  const SizedBox(height: 10),

  // In edit mode rimane cliccabile
  OutlinedButton.icon(
  onPressed: _launchMaps,
  icon: const Icon(Icons.navigation),
  label: const Text('AVVIA NAVIGAZIONE (Google Maps)'),
  ),

  const SizedBox(height: 16),
  _CustomFieldsEditor(
  title: 'Campi extra (PUBLIC)',
  data: publicCustom,
  enabled: !readOnly,
  onChanged: (m) => _mergeCustomFromEditor(m, subsetIsPrivate: false),
  ),

  const SizedBox(height: 16),

  // bottone SALVA solo in edit mode
  if (!readOnly)
  SizedBox(
  height: 48,
  child: ElevatedButton.icon(
  onPressed: _saveGlobal,
  icon: const Icon(Icons.save),
  label: const Text('SALVA ANAGRAFICA'),
  ),
  ),

  const SizedBox(height: 18),
  ],
  );
  }



  // ================= HR TAB (dinamico) =================
  Widget _tabHr({required bool readOnly}) {
    final viewerUid2 = FirebaseAuth.instance.currentUser?.uid ?? '';
    final viewerEmailLower = (FirebaseAuth.instance.currentUser?.email ?? '').toLowerCase();
    final viewer = _buildViewerContext(
      viewerUid: viewerUid2,
      viewerEmailLower: viewerEmailLower,
      targetUid: widget.userId,
    );

    // editMode abilita UI edit, ma i permessi reali per campo vengono dal resolver


    final categories = HrFieldCatalog.fields
        .map((f) => f.category)
        .toSet()
        .toList()
      ..sort();

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final cat in categories) ...[
          _sectionHeader(cat),
          const SizedBox(height: 6),
          ...HrFieldCatalog.fields.where((f) => f.category == cat).map((field) {
            final isUser = field.target == HrTarget.user;
            final storageKey = isUser ? _mapHrKeyToUser(field.key) : _mapHrKeyToMember(field.key);
            final current = isUser ? _userValues[storageKey] : _memberValues[storageKey];

            final policy = _getPolicyForField(
              isUser: isUser,
              storageKey: storageKey,
              fieldSensitive: field.sensitive,
            );
            final canView = HrPolicyResolver.canView(policy: policy, viewer: viewer);
            if (!canView) {
              return const SizedBox.shrink();
            }
            final canEdit = _editMode && HrPolicyResolver.canEdit(policy: policy, viewer: viewer);

            final canManagePolicy = _canManagePolicy(viewer, fieldSensitive: field.sensitive);

            final fieldWidget = HrFieldRenderer(

              field: field,
              value: current,
              editable: canEdit,
              onChanged: (hrKey, newValue) {
                setState(() {
                  if (isUser) {
                    final k = _mapHrKeyToUser(hrKey);
                    _userValues[k] = newValue;
                    // mirror legacy controllers for core fields
                    if (k == 'nome') _nome.text = (newValue ?? '').toString();
                    if (k == 'cognome') _cognome.text = (newValue ?? '').toString();
                    if (k == 'nickname') _nickname.text = (newValue ?? '').toString();
                    if (k == 'thought') _thought.text = (newValue ?? '').toString();
                    if (k == 'telefono') _tel.text = (newValue ?? '').toString();
                    if (k == 'codiceFiscale') _cf.text = (newValue ?? '').toString();
                    if (k == 'ibanDefault') _ibanDefault.text = (newValue ?? '').toString();
                    if (k == 'addressResidence' && newValue is Map) {
                      _via.text = (newValue['street'] ?? '').toString();
                      _cap.text = (newValue['zip'] ?? '').toString();
                      _citta.text = (newValue['city'] ?? '').toString();
                      _prov.text = (newValue['province'] ?? '').toString();
                      _naz.text = (newValue['country'] ?? '').toString();
                    }
                  } else {
                    final k = _mapHrKeyToMember(hrKey);
                    _memberValues[k] = newValue;
                  }
                });
              },
            );
          }),
          const SizedBox(height: 18),
        ],
      ],
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }


// ==========================================================
// ✅ TAB “DI LEGA” — visualizzazione multipla (responsive)
// ==========================================================
  Widget _tabDiLega({
    required String userUid,
    required bool readOnly,
  }) {
    if (!_isSelf) {
      // utente non self → una sola lega
      final mRef = FirebaseFirestore.instance
          .collection('Leagues')
          .doc(widget.leagueId)
          .collection('members')
          .doc(userUid);

      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: mRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Errore lettura membership: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return const Center(child: Text('Nessuna membership trovata in questa lega.'));
          }

          final member = snap.data!.data() ?? {};
          final leagueId = widget.leagueId;

          return _buildLeagueCardGrid([
            {'leagueId': leagueId, 'member': member}
          ], readOnly);
        },
      );
    }

    // ✅ SELF: tutte le membership in griglia
    final stream = FirebaseFirestore.instance
        .collectionGroup('members')
        .where(FieldPath.documentId, isEqualTo: userUid) // ✅ docId = uid
        .snapshots()
        .map((qs) {
      final memberships = <Map<String, dynamic>>[];

      for (final d in qs.docs) {
        final leagueId = d.reference.parent.parent?.id ?? 'UNKNOWN';
        memberships.add({
          'leagueId': leagueId,
          'member': d.data(),
        });
      }

      memberships.sort(
            (a, b) => (a['leagueId'] as String).compareTo(b['leagueId'] as String),
      );

      return memberships;
    });


    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Errore lettura leghe: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final memberships = snap.data!;
        if (memberships.isEmpty) {
          return const Center(child: Text('Nessuna lega trovata per questo utente.'));
        }

        return _buildLeagueCardGrid(memberships, readOnly);
      },
    );
  }

  /// ✅ Layout responsive a griglia (1, 2 o 3 colonne)
  Widget _buildLeagueCardGrid(List<Map<String, dynamic>> memberships, bool readOnly) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1600 ? 3 : width >= 1000 ? 2 : 1;

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 580, // altezza singolo pannello
          ),
          itemCount: memberships.length,
          itemBuilder: (context, i) {
            final m = memberships[i];
            final leagueId = m['leagueId'] as String;
            final member = m['member'] as Map<String, dynamic>;

            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.apartment, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            leagueId,
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _buildLeagueInnerTabs(
                        leagueId: leagueId,
                        member: member,
                        readOnly: readOnly,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }










  Future<ImageSource?> _askImageSource({required bool allowCamera}) async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galleria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (allowCamera)
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Fotocamera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Annulla'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }




  void _syncImagesFromSnapshots({
    required Map<String, dynamic> user,
    required Map<String, dynamic> member,
  }) {
    final p = _map(user['profile']);

    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse((v ?? '').toString()) ?? 0;
    }

    final newPhoto = _nullIfEmpty(_s(p['photoUrl'] ?? user['photoUrl'] ?? member['photoUrl']));
    final newCover = _nullIfEmpty(_s(p['coverUrl'] ?? user['coverUrl'] ?? member['coverUrl']));

    final newPhotoV = asInt(p['photoV'] ?? user['photoV'] ?? member['photoV'] ?? 0);
    final newCoverV = asInt(p['coverV'] ?? user['coverV'] ?? member['coverV'] ?? 0);


    // ✅ Se non cambia nulla: stop (evita loop)
    if (newPhoto == _photoUrl &&
        newCover == _coverUrl &&
        newPhotoV == _vPhoto &&
        newCoverV == _vCover) {
      return;
    }

    // ✅ Accumulo i valori “da applicare”
    _pendingPhoto = newPhoto;
    _pendingCover = newCover;
    _pendingPhotoV = newPhotoV;
    _pendingCoverV = newCoverV;

    // ✅ Programmo UN SOLO setState dopo il frame corrente
    if (_imageSyncScheduled) return;
    _imageSyncScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _imageSyncScheduled = false;
      if (!mounted) return;

      final pPhoto = _pendingPhoto;
      final pCover = _pendingCover;
      final pPhotoV = _pendingPhotoV;
      final pCoverV = _pendingCoverV;

      // ricontrollo: se nel frattempo è già tutto allineato, non faccio nulla
      if (pPhoto == _photoUrl &&
          pCover == _coverUrl &&
          pPhotoV == _vPhoto &&
          pCoverV == _vCover) {
        return;
      }

      setState(() {
        _photoUrl = pPhoto;
        _coverUrl = pCover;
        _vPhoto = pPhotoV;
        _vCover = pCoverV;
      });
    });
  }




// ---- LIMITI (come mi hai chiesto) ----
  static const int _kProfileMaxBytes = 200 * 1024; // 200 KB
  static const int _kCoverMaxBytes   = 300 * 1024; // 300 KB

// Dimensioni consigliate (lato lungo max)
  static const int _kProfileMaxSide = 768;
  static const int _kCoverMaxSide   = 1600;

// Qualità JPEG
  static const int _kStartQuality = 88;
  static const int _kMinQuality   = 55;

  Future<void> _pickUploadAndSetImage({required bool isCover}) async {
    final canEdit = _isSelf || await _canEditTarget();
    if (!canEdit) {
      _toast('Non hai permessi per modificare le immagini di questo utente.');
      return;
    }

    final src = await _askImageSource(allowCamera: !kIsWeb);
    if (src == null) return;

    // Dialog progress
    final progress = ValueNotifier<double>(0.0);
    final message  = ValueNotifier<String>('Preparazione...');

    void setP(double p, String m) {
      progress.value = p.clamp(0.0, 1.0);
      message.value = m;
    }

    // Mostro dialog (non await)
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        onPopInvoked: (didPop) {},
        child: AlertDialog(
          title: Text(isCover ? 'Aggiornamento copertina' : 'Aggiornamento foto profilo'),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, p, __) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: p == 0 ? null : p),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: message,
                    builder: (_, m, __) => Text(m),
                  ),
                  const SizedBox(height: 6),
                  Text('${(p * 100).toStringAsFixed(0)}%'),
                ],
              );
            },
          ),
        ),
      ),
    );

    try {
      setState(() => _saving = true);

      setP(0.03, 'Selezione immagine...');
      final x = await _picker.pickImage(source: src);
      if (x == null) return;

      setP(0.08, 'Lettura immagine...');
      final inputBytes = await x.readAsBytes();
      if (inputBytes.isEmpty) return;

      // --------------- COMPRESSIONE ---------------
      setP(0.12, 'Ridimensionamento/Compressione...');
      final targetBytes = isCover ? _kCoverMaxBytes : _kProfileMaxBytes;
      final maxSide     = isCover ? _kCoverMaxSide   : _kProfileMaxSide;

      final outBytes = await _compressToTargetJpeg(
        inputBytes,
        maxBytes: targetBytes,
        maxSide: maxSide,
        onProgress: (p, msg) {
          // Compressione = 12% -> 70%
          setP(0.12 + (0.58 * p), msg);
        },
      );

      // --------------- UPLOAD ---------------
      setP(0.70, 'Upload su cloud...');
      final uid = widget.userId;

      final baseRef = FirebaseStorage.instance.ref().child(
        _isSelf ? 'users/$uid' : 'leagues/${widget.leagueId}/members/$uid',
      );

      final fileName = isCover ? 'cover.jpg' : 'profile.jpg';
      final ref = baseRef.child(fileName);

      final task = ref.putData(
        outBytes,
        SettableMetadata(
          contentType: 'image/jpeg',
          cacheControl: 'public, max-age=604800',
        ),
      );

      task.snapshotEvents.listen((snap) {
        final total = snap.totalBytes;
        final sent  = snap.bytesTransferred;
        if (total > 0) {
          final up = (sent / total).clamp(0.0, 1.0);
          // Upload = 70% -> 95%
          setP(0.70 + (0.25 * up), 'Upload su cloud... ${(up * 100).toStringAsFixed(0)}%');
        }
      });

      await task;
      final url = await ref.getDownloadURL();

      // bust cache: uso timestamp
      final v = DateTime.now().millisecondsSinceEpoch;

      // aggiorno subito UI
      if (isCover) {
        _coverUrl = url;
        _vCover = v;
      } else {
        _photoUrl = url;
        _vPhoto = v;
      }
      if (mounted) setState(() {});

      // --------------- FIRESTORE ---------------
      setP(0.96, 'Aggiornamento Firestore...');

      // ✅ SOLO Users/{uid} (NO members)
      if (isCover) {
        await _updateUserField('coverUrl', url);
        await _updateUserField('coverV', v);
      } else {
        await _updateUserField('photoUrl', url);
        await _updateUserField('photoV', v);
      }

      setP(1.0, 'Completato ✅');
      _toast(isCover ? '✅ Copertina aggiornata.' : '✅ Foto profilo aggiornata.');
    } catch (e) {
      _toast('Errore upload: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // chiude dialog
      progress.dispose();
      message.dispose();
    }
  }




  Future<Uint8List> _compressToTargetJpeg(
      Uint8List input, {
        required int maxBytes,
        required int maxSide,
        required void Function(double p, String msg) onProgress,
      }) async {
    onProgress(0.05, 'Decodifica immagine...');
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw Exception('Immagine non valida / non decodificabile.');
    }

    // orientamento corretto (EXIF)
    var im = img.bakeOrientation(decoded);

    onProgress(0.15, 'Ridimensionamento...');
    im = _resizeIfNeeded(im, maxSide);

    int quality = _kStartQuality;
    int attempts = 0;
    int currentMaxSide = maxSide;

    while (true) {
      attempts++;

      // progress “percepito”: ogni tentativo fa avanzare
      final p = (attempts / 14).clamp(0.15, 0.90);
      onProgress(p, 'Compressione... (q=$quality, tentativo $attempts)');

      final out = Uint8List.fromList(img.encodeJpg(im, quality: quality));
      final kb = (out.lengthInBytes / 1024).round();

      if (out.lengthInBytes <= maxBytes) {
        onProgress(1.0, 'Ok: ${kb}KB');
        return out;
      }

      // lascia respirare UI
      await Future<void>.delayed(const Duration(milliseconds: 1));

      // abbasso qualità finché posso
      if (quality > _kMinQuality) {
        quality = (quality - 8).clamp(_kMinQuality, 100);
        continue;
      }

      // se a qualità minima ancora troppo grande: riduco dimensioni
      final nextSide = (currentMaxSide * 0.85).round();
      if (nextSide < 320) {
        throw Exception(
          'Impossibile scendere sotto ${(maxBytes / 1024).toStringAsFixed(0)}KB senza degradare troppo. '
              'Prova un’immagine meno pesante.',
        );
      }

      currentMaxSide = nextSide;
      im = _resizeIfNeeded(im, currentMaxSide);
      quality = _kStartQuality; // riparto con qualità migliore su immagine più piccola
    }
  }

  img.Image _resizeIfNeeded(img.Image im, int maxSide) {
    final w = im.width;
    final h = im.height;

    if (w <= maxSide && h <= maxSide) return im;

    if (w >= h) {
      final newW = maxSide;
      final newH = (h * maxSide / w).round();
      return img.copyResize(im, width: newW, height: newH, interpolation: img.Interpolation.average);
    } else {
      final newH = maxSide;
      final newW = (w * maxSide / h).round();
      return img.copyResize(im, width: newW, height: newH, interpolation: img.Interpolation.average);
    }
  }






  Future<void> _removeImage({required bool isCover}) async {
    final canEdit = _isSelf || await _canEditTarget();
    if (!canEdit) return;

    try {
      setState(() => _saving = true);

      final v = DateTime.now().millisecondsSinceEpoch;

      // aggiorno lo stato locale
      if (isCover) {
        _coverUrl = null;
        _vCover = v;
      } else {
        _photoUrl = null;
        _vPhoto = v;
      }
      if (mounted) setState(() {});

      final keyUrl = isCover ? 'coverUrl' : 'photoUrl';
      final keyV   = isCover ? 'coverV'   : 'photoV';

      // ✅ SOLO Users/{uid} (NO members)
      await _updateUserField(keyUrl, FieldValue.delete());
      await _updateUserField(keyV, v);

      _toast(isCover ? 'Copertina rimossa.' : 'Foto rimossa.');
    } catch (e) {
      _toast('Errore: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }






  Widget _coverOnly({
    required String? coverUrl,
    required bool canEdit,
  }) {
    final theme = Theme.of(context);
    final hasCover = coverUrl != null && coverUrl.trim().isNotEmpty;
    final c = hasCover ? _bust(coverUrl.trim(), _vCover) : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: theme.colorScheme.surfaceContainerHighest),

        // ✅ TAP SEMPRE: anche con gradient sopra e anche se cover mancante
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openImagesFullScreen(initialIndex: 0),
            child: hasCover
                ? _smartImage(
              c!,
              fit: BoxFit.cover,
              placeholder: const Center(child: Icon(Icons.image, size: 60)),
            )
                : const Center(child: Icon(Icons.image, size: 60)),
          ),
        ),

        // ✅ overlay NON deve intercettare tap
        IgnorePointer(
          ignoring: true,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black26, Colors.transparent],
              ),
            ),
          ),
        ),

        // ✅ menu cover (resta cliccabile e NON fa partire il tap fullscreen)
        if (canEdit)
          Positioned(
            right: 12,
            bottom: 12,
            child: PopupMenuButton<String>(
              tooltip: 'Copertina',
              onSelected: (v) {
                if (v == 'view') _openImagesFullScreen(initialIndex: 0);
                if (v == 'edit') _pickUploadAndSetImage(isCover: true);
                if (v == 'remove') _removeImage(isCover: true);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'view', child: Text('Visualizza')),
                PopupMenuItem(value: 'edit', child: Text('Modifica')),
                PopupMenuItem(value: 'remove', child: Text('Rimuovi')),
              ],
              child: _whiteRingIcon(
                theme: theme,
                icon: Icons.photo_camera_back,
                radius: 18,
              ),
            ),
          ),
      ],
    );
  }






  Future<void> _openImagesFullScreen({required int initialIndex}) async {
    final canEditImages = _isSelf || await _canEditTarget();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DmsFullScreenImagesPage(
          initialIndex: initialIndex,
          items: [
            DmsImageViewerItem(
              label: 'Copertina',
              url: _coverUrl,
              canEdit: canEditImages,
              canRemove: canEditImages,
              onEdit: () => _pickUploadAndSetImage(isCover: true),
              onRemove: () => _removeImage(isCover: true),
            ),
            DmsImageViewerItem(
              label: 'Profilo',
              url: _photoUrl, // ✅ qui era _profileUrl
              canEdit: canEditImages,
              canRemove: canEditImages,
              onEdit: () => _pickUploadAndSetImage(isCover: false),
              onRemove: () => _removeImage(isCover: false),
            ),
          ],
        ),
      ),
    );
  }







  double _lerp(double a, double b, double t) => a + (b - a) * t;

  Widget _pinnedProfileAndTabs({
    required double t,
    required String name,
    required String email,
    required String? photoUrl,
    required bool canEditImages,
    required bool hasCover,
  }) {
    final theme = Theme.of(context);

    const double rCollapsed = 24.0; // deve combaciare con overlay

    final double topAreaH = (_pinnedH - _kTabsAreaH).clamp(56.0, 260.0);

    final bool showPinnedLeftBtn = (_isSelf && _editMode) || !widget.embedded;
    final bool showPinnedRightBtn = _isSelf;

    const double kPinnedOuterPad = 8.0;
    const double kPinnedBtnSlotW = 52.0; // 40 + padding orizzontale (6+6)
    const double kPinnedGapAfterBtn = 8.0;

    final double leftTextPadCollapsed = (showPinnedLeftBtn
        ? (kPinnedOuterPad + kPinnedBtnSlotW + kPinnedGapAfterBtn)
        : kPinnedOuterPad) +
        (rCollapsed * 2) +
        12;

    final double rightTextPadCollapsed = showPinnedRightBtn
        ? (kPinnedOuterPad + kPinnedBtnSlotW + kPinnedGapAfterBtn)
        : kPinnedOuterPad;


    final textAlign = Alignment.lerp(Alignment.centerLeft, Alignment.center, t)!;


    return Material(
      elevation: 2,
      color: theme.colorScheme.surface,
      child: CompositedTransformTarget(
        link: _profileLink,
        child: SizedBox(
          key: _profileHeaderKey,
          height: _pinnedH, // ✅ dinamica
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: topAreaH,
                child: Stack(
                  children: [
                    // ---- TESTO (come prima) ----
                    Align(
                      alignment: textAlign,
                      child: Padding(
                        // ✅ più spazio a sinistra quando collassato (per bottone + avatar)
                        padding: EdgeInsets.fromLTRB(
                          _lerp(leftTextPadCollapsed, 16, t),
                          0,
                          _lerp(rightTextPadCollapsed, 16, t),
                          0,
                        ),

                        child: ValueListenableBuilder<double>(
                          valueListenable: _nameAvoidDy,
                          builder: (_, extraDy, __) {
                            return ValueListenableBuilder<double>(
                              valueListenable: _nameAvoidDx,
                              builder: (_, extraDx, __) {
                                final dx = extraDx * t;
                                final dy = extraDy;

                                return Transform.translate(
                                  offset: Offset(dx, dy),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                    t < 0.40 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        name.isEmpty ? 'Profilo' : name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: _lerp(16.5, 18.5, t),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        email,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: theme.colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),

                    // ---- BOTTONI NEL PINNED (solo quando collassato) ----
                    Builder(
                      builder: (_) {
                        // visibile quando t è basso (cover sparita)
                        final pinnedOpacity = Curves.easeOutCubic.transform(
                          ((0.25 - t) / 0.25).clamp(0.0, 1.0),
                        );

                        Widget pinnedBtn({
                          required IconData icon,
                          required String tooltip,
                          required VoidCallback? onTap,
                        }) {
                          return Tooltip(
                            message: tooltip,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Material(
                                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.92),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(color: theme.dividerColor.withOpacity(0.25)),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: onTap,
                                  child: const SizedBox(
                                    width: 40,
                                    height: 34,
                                    child: Center(child: Icon(Icons.circle, color: Colors.transparent)),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        // piccolo trucco: icona dentro senza rifare tutto
                        Widget pinnedIconBtn({
                          required IconData icon,
                          required String tooltip,
                          required VoidCallback? onTap,
                        }) {
                          return Tooltip(
                            message: tooltip,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Material(
                                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.92),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(color: theme.dividerColor.withOpacity(0.25)),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: onTap,
                                  child: SizedBox(
                                    width: 40,
                                    height: 34,
                                    child: Center(
                                      child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        return IgnorePointer(
                          ignoring: pinnedOpacity < 0.05,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 120),
                            opacity: pinnedOpacity,
                            child: Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // SINISTRA:
                                    // - se SELF in edit => Annulla (sempre, anche embedded)
                                    // - altrimenti => Back solo se NON embedded
                                    if (showPinnedLeftBtn)
                                      pinnedIconBtn(
                                        icon: (_isSelf && _editMode) ? Icons.close : Icons.arrow_back,
                                        tooltip: (_isSelf && _editMode) ? 'Annulla' : 'Indietro',
                                        onTap: () {
                                          if (_isSelf && _editMode) {
                                            _cancelEdit();
                                          } else {
                                            Navigator.of(context).maybePop();
                                          }
                                        },
                                      )
                                    else
                                      const SizedBox(width: 52), // placeholder (40 + 6+6)

                                    // DESTRA:
                                    // - self => edit/salva
                                    // - non-self => placeholder per mantenere simmetria
                                    if (showPinnedRightBtn)
                                      pinnedIconBtn(
                                        icon: _editMode ? Icons.check : Icons.edit,
                                        tooltip: _editMode ? 'Salva' : 'Modifica',
                                        onTap: _editMode ? _saveAllAndExit : _enterEditMode,
                                      )
                                    else
                                      const SizedBox(width: 52),
                                  ],
                                ),

                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),


              SizedBox(
                height: _kTabsAreaH,
                child: TabBar(
                  tabs: const [
                    Tab(child: _TabLabel(icon: Icons.person, text: 'Personale')),
                    Tab(child: _TabLabel(icon: Icons.apartment, text: 'Di Lega')),
                  ],
                ),

              ),

            ],
          ),
        ),
      ),
    );
  }






  Widget _buildLeagueInnerTabs({
    required String leagueId,
    required Map<String, dynamic> member,
    required bool readOnly,
  }) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              tabs: [
                Tab(child: _TabLabel(icon: Icons.badge, text: 'Profilo')),
                Tab(child: _TabLabel(icon: Icons.admin_panel_settings, text: 'Permessi')),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _leagueProfileReadOnly(leagueId: leagueId, member: member),
                _tabPermessiForLeague(leagueId: leagueId, member: member),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _leagueProfileReadOnly({
    required String leagueId,
    required Map<String, dynamic> member,
  }) {
    final org = _map(member['org']);
    final overrides = _map(member['overrides']);
    final oRec = _map(overrides['recapiti']);
    final oAna = _map(overrides['anagrafica']);
    final custom = _map(member['custom']);

    final orgItems = <_InfoItem>[
      _InfoItem('Organizzazione', _s(org['organizzazione'])),
      _InfoItem('Comparto', _s(org['comparto'])),
      _InfoItem('Job role', _s(org['jobRole'])),
    ].where((i) => (i.value ?? '').toString().trim().isNotEmpty).toList();

    final overrideItems = <_InfoItem>[
      _InfoItem('Telefono (lega)', _s(oRec['telefono'])),
      _InfoItem('Email 2° (lega)', _listStr(oRec['emailSecondarie']).join(', ')),
      _InfoItem('IBAN (lega)', _s(oAna['iban'])),
    ].where((i) => (i.value ?? '').toString().trim().isNotEmpty).toList();

    final roleId = _s(member['roleId']);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _readOnlySectionCard('LEGA', [
          _InfoItem('LeagueId', leagueId),
          if (roleId.isNotEmpty) _InfoItem('RoleId', roleId),
        ]),

        if (orgItems.isNotEmpty) _readOnlySectionCard('ORGANIZZAZIONE', orgItems),
        if (overrideItems.isNotEmpty) _readOnlySectionCard('OVERRIDE (LEGA)', overrideItems),

        if (custom.isNotEmpty)
          _readOnlySectionCard(
            'CUSTOM (LEGA)',
            custom.entries
                .map((e) => _InfoItem(e.key, (e.value ?? '').toString()))
                .toList(),
          ),

        const SizedBox(height: 18),
      ],
    );
  }



  Future<bool> _canEditTargetForLeague(String leagueId) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return false;

    return UserService.canEditMember(
      leagueId: leagueId,
      actorUid: me.uid,
      targetUid: widget.userId,
    );
  }

  Widget _tabPermessiForLeague({
    required String leagueId,
    required Map<String, dynamic> member,
  }) {
    final currentRoleId = _s(member['roleId']);

    return FutureBuilder<bool>(
      future: _canEditTargetForLeague(leagueId),
      builder: (context, canSnap) {
        final canEdit = canSnap.data ?? false;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: UserService.streamRoles(leagueId),
          builder: (context, rolesSnap) {
            final roles = rolesSnap.data?.docs ?? [];

            return ListView(
              padding: const EdgeInsets.all(14),
              children: [
                const Text('RUOLO PERMESSI (RBAC)', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text('LeagueId: $leagueId'),
                const SizedBox(height: 8),
                Text('RoleId attuale: ${currentRoleId.isEmpty ? "-" : currentRoleId}'),
                const SizedBox(height: 12),

                if (!canEdit) ...[
                  const Text('Non hai permessi per modificare il ruolo in questa lega.'),
                ] else ...[
                  DropdownButtonFormField<String>(
                    value: roles.any((r) => r.id == currentRoleId)
                        ? currentRoleId
                        : (roles.isNotEmpty ? roles.first.id : null),
                    items: roles.map((d) {
                      final name = (d.data()['name'] ?? d.id).toString();
                      final tier = (d.data()['tier'] ?? '').toString();
                      return DropdownMenuItem(
                        value: d.id,
                        child: Text('$name (rank $tier)'),
                      );
                    }).toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      await UserService.setMemberRole(
                        leagueId: leagueId,
                        targetUid: widget.userId,
                        roleId: v,
                      );
                      if (mounted) _toast('Ruolo aggiornato.');
                    },
                    decoration: const InputDecoration(
                      labelText: 'Seleziona ruolo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 10),
                const Text('NOTA GERARCHIA', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text(
                  'I permessi dipendono dal rank del ruolo.\n'
                      'Rank più basso = più potente.\n'
                      'Un utente può modificare solo utenti con rank più alto.',
                ),
              ],
            );
          },
        );
      },
    );
  }





  Map<String, dynamic> _shareCfg(String key) {
    // ✅ hard-force: nome/cognome sempre pubblici
    if (_kAlwaysPublicFields.contains(key)) {
      return {
        'mode': 'public',
        'league': false,
        'emails': <String>[],
      };
    }

    final m = _map(_fieldSharing[key]);

    final rawMode = (m['mode'] ?? 'public').toString();
    final mode = (rawMode == 'private') ? 'private' : 'public';

    // ✅ compatibilità: alcune versioni usano 'league', altre 'allLeagues'
    final league = (m['league'] == true) || (m['allLeagues'] == true);

    return {
      'mode': mode,
      'league': league,
      'emails': _listStr(m['emails']),
    };
  }


// alias: mantiene la tua API esistente
  Map<String, dynamic> _sharingOf(String fieldKey) => _shareCfg(fieldKey);

  String _sharingMode(String fieldKey) {
    final mode = _shareCfg(fieldKey)['mode'];
    return (mode == 'private') ? 'private' : 'public';
  }





  void _setShareCfg(String fieldKey, Map<String, dynamic> patch) {
    // ✅ hard-force: nome/cognome sempre pubblici
    if (_kAlwaysPublicFields.contains(fieldKey)) {
      _enforceAlwaysPublicPrivacy();
      return;
    }

    final current = _map(_fieldSharing[fieldKey]);

    final rawMode = (patch['mode'] ?? current['mode'] ?? 'public').toString();
    final mode = (rawMode == 'private') ? 'private' : 'public';

    final bool league = (mode == 'private')
        ? ((patch['league'] == true) ||
        (patch['allLeagues'] == true) ||
        (current['league'] == true) ||
        (current['allLeagues'] == true))
        : false;

    final List<String> emails =
    (mode == 'private') ? _listStr(patch['emails'] ?? current['emails']) : <String>[];

    final entry = <String, dynamic>{
      ...current,

      'mode': mode,
      'league': league,
      'allLeagues': league,
      'emails': emails,

      'allLeaguesScope': current['allLeaguesScope'] ?? 'ALL_MEMBERS',
      'leagueScopes': current['leagueScopes'] is Map ? current['leagueScopes'] : <String, String>{},
      'users': current['users'] is List ? current['users'] : <String>[],
      'compartos': current['compartos'] is List ? current['compartos'] : <String>[],
    };

    if (mode == 'public') {
      entry['league'] = false;
      entry['allLeagues'] = false;
      entry['emails'] = <String>[];
    }

    _fieldSharing = Map<String, dynamic>.from(_fieldSharing);
    _fieldSharing[fieldKey] = entry;

    // ✅ ribadisco sempre
    _enforceAlwaysPublicPrivacy();
  }









  List<String> _parseEmails(String raw) {
    final parts = raw
        .split(RegExp(r'[,\n; ]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // dedup + filtro minimo
    final seen = <String>{};
    final out = <String>[];
    for (final e in parts) {
      final low = e.toLowerCase();
      if (!low.contains('@')) continue;
      if (seen.add(low)) out.add(e);
    }
    return out;
  }

  Future<void> _editFieldSharing(String fieldKey) async {
    // ✅ privacy globale sta in Users/{uid} → solo self
    if (!_isSelf) {
      _toast('Solo l’utente può modificare la privacy dei propri campi.');
      return;
    }

    // ✅ Nome/Cognome non modificabili come privacy
    if (_kAlwaysPublicFields.contains(fieldKey)) {
      _toast('Nome e Cognome sono sempre pubblici.');
      return;
    }


    final current = _shareCfg(fieldKey);
    String mode = current['mode'] as String;
    bool shareLeague = current['league'] == true;
    final initialEmails = (current['emails'] as List<String>? ?? const <String>[]);
    final emailsCtrl = TextEditingController(text: initialEmails.join(', '));

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text('Privacy: $fieldKey'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<String>(
                      value: 'public',
                      groupValue: mode,
                      title: const Text('Pubblico'),
                      onChanged: (v) => setLocal(() {
                        mode = 'public';
                        shareLeague = false;
                        emailsCtrl.text = '';
                      }),
                    ),
                    RadioListTile<String>(
                      value: 'private',
                      groupValue: mode,
                      title: const Text('Privato / Condiviso'),
                      onChanged: (v) => setLocal(() {
                        mode = 'private';
                      }),
                    ),

                    if (mode == 'private') ...[
                      const SizedBox(height: 6),
                      SwitchListTile(
                        title: const Text('Condividi con la lega'),
                        subtitle: const Text('Visibile a tutti i membri della lega'),
                        value: shareLeague,
                        onChanged: (v) => setLocal(() => shareLeague = v),
                      ),

                      const SizedBox(height: 8),
                      TextField(
                        controller: emailsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Email specifiche (opzionale)',
                          hintText: 'es: a@b.it, c@d.com',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Se non selezioni “lega” e lasci vuoto, resta visibile solo a te.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Annulla'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);

                    final emails = _parseEmails(emailsCtrl.text);

                    // ✅ entry compatibile: scrivo sia league che allLeagues
                    final entry = <String, dynamic>{
                      'mode': mode,
                      'league': (mode == 'private') ? shareLeague : false,
                      'allLeagues': (mode == 'private') ? shareLeague : false,

                      // campi “estesi” che stai già usando nel tuo schema
                      'allLeaguesScope': 'ALL_MEMBERS',
                      'leagueScopes': <String, String>{},
                      'users': <String>[],
                      'emails': (mode == 'private') ? emails : <String>[],
                      'compartos': <String>[],
                    };

                    // aggiorna in memoria (clona la mappa)
                    _fieldSharing = Map<String, dynamic>.from(_fieldSharing);
                    _fieldSharing[fieldKey] = entry;

                    // ✅ ribadisco: nome/cognome sempre pubblici
                    _enforceAlwaysPublicPrivacy();


                    // salva su Firestore + UsersPublic (come fai già)
                    await UserService.updateMyGlobalProfileAndSync(
                      profile: _currentProfilePayloadForSync(),
                      privacy: _fieldSharing,
                    );

                    if (mounted) setState(() {});
                  },
                  child: const Text('Salva'),
                ),
              ],
            );
          },
        );
      },
    );

    // NON fare dispose qui: durante la chiusura del dialog può ancora rebuildare 1–2 frame
    // e causare "TextEditingController used after disposed".

  }






  Widget _readOnlySectionCard(String title, List<_InfoItem> items) {
    return _readOnlyCard(title, items);
  }







  bool _isEmpty(String s) => s.trim().isEmpty;

  // Default: se non esiste config => PUBLIC
  bool _isPrivateField(String key) {
    if (_kAlwaysPublicFields.contains(key)) return false;
    return (_shareCfg(key)['mode'] ?? 'public') == 'private';
  }

  bool _isPublicField(String key) => !_isPrivateField(key);

  Widget? _privacySuffix(String fieldKey, bool readOnly) {
    if (readOnly) return null;

    // ✅ niente lucchetto/globo su Nome e Cognome
    if (_kAlwaysPublicFields.contains(fieldKey)) return null;

    final priv = _isPrivateField(fieldKey);
    return IconButton(
      tooltip: 'Privacy / Condivisione',
      icon: Icon(priv ? Icons.lock : Icons.public),
      onPressed: () => _editFieldSharing(fieldKey),
    );
  }


  Widget _readOnlyCard(String title, List<_InfoItem> items) {
    final clean = items.where((i) => !_isEmpty(i.value)).toList();
    if (clean.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ...List.generate(clean.length, (i) {
              final it = clean[i];
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 135,
                        child: Text(it.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(it.value, style: const TextStyle(fontWeight: FontWeight.w600))),
                    ],
                  ),
                  if (i != clean.length - 1) const Divider(height: 18),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _readOnlyPrivateCard(String title, List<_InfoItem> items) {
    final clean = items.where((i) => !_isEmpty(i.value)).toList();
    if (clean.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ...List.generate(clean.length, (i) {
              final it = clean[i];
              final key = it.fieldKey ?? '';
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 135,
                        child: Text(it.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(it.value, style: const TextStyle(fontWeight: FontWeight.w600))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (key.isNotEmpty) _sharedWithLine(key),
                  if (i != clean.length - 1) const Divider(height: 18),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _sharedWithLine(String fieldKey) {
    final theme = Theme.of(context);
    final cfg = _shareCfg(fieldKey);
    final league = cfg['league'] == true;
    final emails = (cfg['emails'] as List<String>? ?? const <String>[]);

    // Se non c'è nessuna condivisione, è "solo te"
    if (!league && emails.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          'Condiviso con: solo te',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final chips = <Widget>[
      if (league)
        const Chip(
          label: Text('LEGA'),
          visualDensity: VisualDensity.compact,
        ),
      ...emails.map(
            (e) => Chip(
          label: Text(e),
          visualDensity: VisualDensity.compact,
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: -6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Condiviso con:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          ...chips,
        ],
      ),
    );
  }


// Split custom fields per tab usando chiave sharing: "custom.<key>"
  Map<String, dynamic> _customByPrivacy({required bool wantPrivate}) {
    final out = <String, dynamic>{};
    _customGlobal.forEach((k, v) {
      final fk = 'custom.$k';
      final isPriv = _isPrivateField(fk);
      if (isPriv == wantPrivate) out[k] = v;
    });
    return out;
  }

  void _mergeCustomFromEditor(Map<String, dynamic> editedSubset, {required bool subsetIsPrivate}) {
    // Mantieni gli altri campi custom non toccati
    final next = Map<String, dynamic>.from(_customGlobal);

    // Rimuovi chiavi del subset che sono state eliminate nell’editor
    final oldSubsetKeys = _customByPrivacy(wantPrivate: subsetIsPrivate).keys.toSet();
    for (final k in oldSubsetKeys) {
      if (!editedSubset.containsKey(k)) next.remove(k);
    }

    // Applica subset aggiornato
    editedSubset.forEach((k, v) => next[k] = v);

    // Se sono comparsi nuovi custom, setta privacy di default coerente col tab
    for (final k in editedSubset.keys) {
      final fk = 'custom.$k';
      final cfg = _shareCfg(fk);
      if ((cfg['mode'] ?? 'public') == 'public' && subsetIsPrivate) {
        // se era default public ma stai aggiungendo in tab private, forza private
        _setShareCfg(fk, {
          'mode': 'private',
          'league': false,
          'emails': <String>[],
        });
      }
    }

    setState(() => _customGlobal = next);
  }









}

class _EmailsEditor extends StatelessWidget {
  final String title;
  final List<String> emails;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  const _EmailsEditor({
    required this.title,
    required this.emails,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    Future<void> addEmail() async {
      if (!enabled) return;

      final ctrl = TextEditingController();
      final res = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Inserisci email'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Aggiungi')),
          ],
        ),
      );

      final email = (res ?? '').trim();
      if (email.isEmpty) return;

      final next = [...emails];
      if (!next.contains(email)) next.add(email);
      onChanged(next);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),

          if (emails.isEmpty) const Text('Nessuna email.'),

          if (emails.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: emails.map((e) {
                return Chip(
                  label: Text(e),
                  onDeleted: enabled
                      ? () {
                    final next = [...emails]..remove(e);
                    onChanged(next);
                  }
                      : null, // ✅ niente X se readOnly
                );
              }).toList(),
            ),

          const SizedBox(height: 10),

          if (enabled)
            OutlinedButton.icon(
              onPressed: addEmail,
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi email'),
            ),
        ]),
      ),
    );
  }
}


class _CustomFieldsEditor extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool enabled;

  const _CustomFieldsEditor({
    required this.title,
    required this.data,
    required this.onChanged,
    this.enabled = true,
  });

  String _safeKey(String raw) {
    final k = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
    return k.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),

          if (entries.isEmpty) const Text('Nessun campo extra.'),

          ...entries.map((e) {
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(e.key),
              subtitle: Text((e.value ?? '').toString()),
              trailing: enabled
                  ? Wrap(spacing: 6, children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    final ctrl = TextEditingController(text: (e.value ?? '').toString());
                    final res = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('Modifica "${e.key}"'),
                        content: TextField(controller: ctrl),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Salva')),
                        ],
                      ),
                    );
                    if (res == null) return;
                    final next = Map<String, dynamic>.from(data);
                    next[e.key] = res;
                    onChanged(next);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    final next = Map<String, dynamic>.from(data);
                    next.remove(e.key);
                    onChanged(next);
                  },
                ),
              ])
                  : null,
            );
          }),

          const SizedBox(height: 6),

          if (enabled)
            OutlinedButton.icon(
              onPressed: () async {
                final keyCtrl = TextEditingController();
                final valCtrl = TextEditingController();

                final res = await showDialog<Map<String, String>>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Aggiungi campo'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: 'Nome campo')),
                        TextField(controller: valCtrl, decoration: const InputDecoration(labelText: 'Valore')),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, {
                          'k': keyCtrl.text.trim(),
                          'v': valCtrl.text.trim(),
                        }),
                        child: const Text('Aggiungi'),
                      ),
                    ],
                  ),
                );

                if (res == null) return;
                final rawKey = (res['k'] ?? '').trim();
                if (rawKey.isEmpty) return;

                final k = _safeKey(rawKey);
                if (k.isEmpty) return;

                final next = Map<String, dynamic>.from(data);
                next[k] = (res['v'] ?? '').trim();
                onChanged(next);
              },
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi campo extra'),
            ),
        ]),
      ),
    );
  }
}



class _NotifierHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final ValueListenable<double> notifier;
  final Widget Function(BuildContext context, double t) builder;

  _NotifierHeaderDelegate({
    required this.height,
    required this.notifier,
    required this.builder,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ValueListenableBuilder<double>(
      valueListenable: notifier,
      builder: (context, t, _) => SizedBox.expand(child: builder(context, t)),
    );
  }

  @override
  bool shouldRebuild(covariant _NotifierHeaderDelegate oldDelegate) {
    return oldDelegate.height != height ||
        oldDelegate.notifier != notifier ||
        oldDelegate.builder != builder;
  }
}





class AppBarIconChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  const AppBarIconChip({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: Colors.black.withOpacity(0.45), // sfondo
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withOpacity(0.20)), // bordo
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            height: 38,
            width: 42,
            child: Tooltip(
              message: tooltip ?? '',
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}


class GlassAppBarIconButton extends StatelessWidget {
  final double t; // 0 = cover visibile, 1 = appbar collassata
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const GlassAppBarIconButton({
    super.key,
    required this.t,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Background e colori “adattivi” (cover -> scuro, appbar -> surface)
    final bg = Color.lerp(
      Colors.black.withOpacity(0.40),
      theme.colorScheme.surface.withOpacity(0.92),
      t.clamp(0.0, 1.0),
    )!;

    final border = Color.lerp(
      Colors.white.withOpacity(0.20),
      theme.dividerColor.withOpacity(0.25),
      t.clamp(0.0, 1.0),
    )!;

    final iconColor = Color.lerp(
      Colors.white,
      theme.colorScheme.onSurface,
      t.clamp(0.0, 1.0),
    )!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: tooltip,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Material(
              color: bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: border),
              ),
              child: InkWell(
                onTap: onPressed,
                child: SizedBox(
                  width: 44,
                  height: 38,
                  child: Icon(icon, color: iconColor, size: 22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}



class _InfoItem {
  final String label;
  final String value;
  final String? fieldKey; // se serve per private sharing
  const _InfoItem(this.label, this.value, {this.fieldKey});
}


class _TabLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TabLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(text),
      ],
    );
  }

  // =========================
  // HR POLICY HELPERS
  // =========================

  HrViewerContext _buildViewerContext({
    required String viewerUid,
    required String viewerEmailLower,
    required String targetUid,
  }) {
    final isSelf = viewerUid.isNotEmpty && viewerUid == targetUid;

    final m = _viewerMemberData;
    List<String> ls(dynamic v) => (v is List) ? v.map((e) => e.toString()).toList() : <String>[];
    Map<String, dynamic> map(dynamic v) => (v is Map<String, dynamic>) ? v : <String, dynamic>{};

    final roles = ls(m['roles']).isNotEmpty ? ls(m['roles']) : (m['role'] != null ? [m['role'].toString()] : <String>[]);
    final comparti = ls(m['comparti']).isNotEmpty ? ls(m['comparti']) : (m['comparto'] != null ? [m['comparto'].toString()] : <String>[]);
    final branches = ls(m['branches']).isNotEmpty ? ls(m['branches']) : (m['branchId'] != null ? [m['branchId'].toString()] : <String>[]);

    final perms = ls(m['effectivePerms']).isNotEmpty ? ls(m['effectivePerms']) : ls(m['perms']);
    final permsMap = map(m['permissions']);

    bool hasPerm(String k) => perms.contains(k) || (permsMap[k] == true);

    final isOwner = (m['isOwner'] == true) ||
        roles.contains('OWNER') ||
        (m['roleId']?.toString() == 'OWNER') ||
        hasPerm('hr_admin') ||
        hasPerm('members_manage') ||
        hasPerm('hr_manage');

    return HrViewerContext(
      uid: viewerUid,
      emailLower: viewerEmailLower,
      isSelf: isSelf,
      isOwnerOrAdmin: isOwner,
      roles: roles,
      comparti: comparti,
      branches: branches,
      effectivePerms: perms,
    );
  }

  HrFieldPolicy _getPolicyForField({
    required bool isUser,
    required String storageKey,
    required bool fieldSensitive,
  }) {
    final key = '${storageKey}__policy';
    final raw = isUser ? _userValues[key] : _memberValues[key];
    final fallback = fieldSensitive
        ? HrFieldPolicy.defaultForSensitive()
        : HrFieldPolicy.defaultForNonSensitive(allowLeague: true);
    return HrFieldPolicy.fromMap(raw, fallback: fallback);
  }

  void _setPolicyForField({
    required bool isUser,
    required String storageKey,
    required HrFieldPolicy policy,
  }) {
    final key = '${storageKey}__policy';
    if (isUser) {
      _userValues[key] = policy.toMap();
    } else {
      _memberValues[key] = policy.toMap();
    }
  }

  bool _canManagePolicy(HrViewerContext viewer, {required bool fieldSensitive}) {
    if (viewer.isOwnerOrAdmin) return true;
    // self può cambiare visibilità solo per non sensibili (gestito nel dialog)
    if (viewer.isSelf && !fieldSensitive) return true;
    return false;
  }


}




typedef LeaguePermessiBuilder = Widget Function(
    BuildContext context,
    String leagueId,
    DocumentSnapshot<Map<String, dynamic>> memberDoc,
    bool readOnly,
    );

