import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dms_app/core/service/auth/auth_service.dart';
import 'package:dms_app/core/service/league/dms_league_api.dart';
import 'package:dms_app/core/service/user/user_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/service/league/league_picker_prefs.dart';
import 'league_access_page.dart';
import 'qr_scan_page.dart';


class LeaguePickerPage extends StatefulWidget {
  /// Se lo passi (da RootGate), il picker delega a questa callback l'apertura lega.
  /// (utile per “entra diretto” da link/push)
  final Future<void> Function(String leagueId)? onOpenLeague;

  const LeaguePickerPage({super.key, this.onOpenLeague});

  @override
  State<LeaguePickerPage> createState() => _LeaguePickerPageState();
}

class _InviteRec {
  final String leagueId;
  final String inviteId;
  final String? roleId;

  _InviteRec({required this.leagueId, required this.inviteId, this.roleId});
}

class _LeagueCardItem {
  final String leagueId;
  final String nome;
  final String joinCode;
  final String logoUrl;
  final bool invited;
  final String? inviteId;
  final String? roleId;

  _LeagueCardItem({
    required this.leagueId,
    required this.nome,
    required this.joinCode,
    required this.logoUrl,
    required this.invited,
    this.inviteId,
    this.roleId,
  });
}

class _LeaguePickerPageState extends State<LeaguePickerPage> with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // ---- prefs inner tabs (Tutte/Partecipante/Invitato)
  final _prefs = LeaguePickerPrefs();
  List<String> _tabOrder = const ['all', 'joined', 'invited'];
  String _defaultTab = 'all';
  late TabController _subTabController;

  // ---- JOIN/INVITE expander
  bool _joinExpanded = false;
  bool _inviteExpanded = false;

  // ---- join
  final _joinCodeCtrl = TextEditingController();
  bool _joining = false;

  // ---- invite manual
  final _inviteCtrl = TextEditingController();
  bool _acceptingInvite = false;

  // ---- create league (2a tab principale)
  final _creatorNomeCtrl = TextEditingController();
  final _creatorCognomeCtrl = TextEditingController();
  final _createNameCtrl = TextEditingController();
  Uint8List? _logoBytes;

  final FocusNode _fnNome = FocusNode();
  final FocusNode _fnCognome = FocusNode();
  final FocusNode _fnNomeLega = FocusNode();

  bool _creating = false;

  // ---- refresh trigger
  int _refreshTick = 0;

  // ---- memo future (evita “1 secondo di loading” quando fai setState per espandere)
  Future<Map<String, List<_LeagueCardItem>>>? _listsFuture;
  String _listsFutureKey = '';

  @override
  void initState() {
    super.initState();

    // init immediato (poi lo aggiorniamo con prefs)
    _subTabController = TabController(length: _tabOrder.length, vsync: this);

    _initPrefs();
  }

  Future<void> _initPrefs() async {
    final pref = await _prefs.load();
    final order = List<String>.from(pref['tabOrder'] ?? ['all', 'joined', 'invited']);
    final def = (pref['defaultTab'] ?? 'all').toString();

    if (!mounted) return;

    setState(() {
      _tabOrder = order;
      _defaultTab = def;
      _subTabController.dispose();
      _subTabController = TabController(
        length: _tabOrder.length,
        vsync: this,
        initialIndex: _tabOrder.indexOf(_defaultTab).clamp(0, _tabOrder.length - 1),
      );
    });
  }

  @override
  void dispose() {
    _joinCodeCtrl.dispose();
    _inviteCtrl.dispose();

    _creatorNomeCtrl.dispose();
    _creatorCognomeCtrl.dispose();
    _createNameCtrl.dispose();
    _fnNome.dispose();
    _fnCognome.dispose();
    _fnNomeLega.dispose();

    _subTabController.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  final _api = DmsLeagueApi(region: 'europe-west1');

  Future<void> _openLeague(String leagueId) async {
    if (widget.onOpenLeague != null) {
      await widget.onOpenLeague!(leagueId);
      return;
    }
    await _api.setActiveLeague(leagueId: leagueId);
  }


  // ---------- LEAGUES GET BY ID (no query) ----------
  Future<List<_LeagueCardItem>> _fetchJoinedLeagueItems({
    required List<String> leagueIds,
    required String activeLeagueId,
  }) async {
    if (leagueIds.isEmpty) return [];

    final col = _db.collection('Leagues');
    final items = <_LeagueCardItem>[];

    const chunkSize = 10;
    for (var i = 0; i < leagueIds.length; i += chunkSize) {
      final chunk = leagueIds.sublist(i, (i + chunkSize).clamp(0, leagueIds.length));
      final snaps = await Future.wait(chunk.map((id) => col.doc(id).get()));

      for (final snap in snaps) {
        if (!snap.exists) continue;
        final d = snap.data() ?? {};

        items.add(_LeagueCardItem(
          leagueId: snap.id,
          nome: (d['nome'] ?? 'League').toString(),
          joinCode: (d['joinCode'] ?? '').toString(),
          logoUrl: (d['logoUrl'] ?? '').toString(),
          invited: false,
        ));
      }
    }

    // attiva in alto, poi alfabetico
    items.sort((a, b) {
      final aActive = a.leagueId == activeLeagueId;
      final bActive = b.leagueId == activeLeagueId;
      if (aActive && !bActive) return -1;
      if (bActive && !aActive) return 1;
      return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });

    return items;
  }


  // ---------- INVITES ----------
  Future<List<_InviteRec>> _fetchInvitesForEmailLower(String emailLower) async {
    final out = <_InviteRec>[];
    final seen = <String>{};

    Future<void> runQuery(String field) async {
      try {
        final qs = await _db.collectionGroup('invites').where(field, isEqualTo: emailLower).get();
        for (final doc in qs.docs) {
          final data = doc.data();
          final status = (data['status'] ?? 'pending').toString().toLowerCase().trim();
          if (status == 'revoked' || status == 'deleted') continue;

          final leagueRef = doc.reference.parent.parent;
          if (leagueRef == null) continue;

          final leagueId = leagueRef.id;
          final inviteId = doc.id;
          final key = '$leagueId/$inviteId';
          if (seen.contains(key)) continue;
          seen.add(key);

          out.add(_InviteRec(
            leagueId: leagueId,
            inviteId: inviteId,
            roleId: data['roleId']?.toString(),
          ));
        }
      } catch (_) {
        // se regole/field non consentono, non rompo UI
      }
    }

    await runQuery('emailLower');
    await runQuery('toEmailLower');
    await runQuery('invitedEmailLower');

    return out;
  }

  Future<Map<String, List<_LeagueCardItem>>> _loadLeagueLists({
    required List<String> joinedLeagueIds, // (non usato, lo lasciamo per compat)
    required String emailLower,            // (non usato, lo lasciamo per compat)
    required String activeLeagueId,
  }) async {
    final res = await _api.listLeaguesForUser();



    final joinedRaw = (res['joined'] is List) ? (res['joined'] as List) : [];
    final invitedRaw = (res['invited'] is List) ? (res['invited'] as List) : [];

    final joined = joinedRaw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return _LeagueCardItem(
        leagueId: (m['leagueId'] ?? '').toString(),
        nome: (m['nome'] ?? 'League').toString(),
        joinCode: (m['joinCode'] ?? '').toString(),
        logoUrl: (m['logoUrl'] ?? '').toString(),
        invited: false,
      );
    }).toList();

    final invited = invitedRaw.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return _LeagueCardItem(
        leagueId: (m['leagueId'] ?? '').toString(),
        nome: (m['nome'] ?? 'Lega').toString(),
        joinCode: '',
        logoUrl: (m['logoUrl'] ?? '').toString(),
        invited: true,
        inviteId: (m['inviteId'] ?? '').toString(),
        roleId: (m['roleId'] ?? '').toString().isEmpty ? null : (m['roleId'] ?? '').toString(),
      );
    }).toList();

    joined.sort((a, b) {
      final aActive = a.leagueId == activeLeagueId;
      final bActive = b.leagueId == activeLeagueId;
      if (aActive && !bActive) return -1;
      if (bActive && !aActive) return 1;
      return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });

    invited.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

    return {'joined': joined, 'invited': invited};
  }




  Future<Map<String, List<_LeagueCardItem>>> _getListsFuture({
    required List<String> joinedLeagueIds,
    required String emailLower,
    required String activeLeagueId,
  }) {
    final sorted = [...joinedLeagueIds]..sort();
    final key = '${sorted.join(",")}::$emailLower::$activeLeagueId::$_refreshTick';

    if (_listsFuture == null || _listsFutureKey != key) {
      _listsFutureKey = key;
      _listsFuture = _loadLeagueLists(
        joinedLeagueIds: sorted,
        emailLower: emailLower,
        activeLeagueId: activeLeagueId,
      );
    }
    return _listsFuture!;
  }

  String _labelOf(String key) {
    switch (key) {
      case 'joined':
        return 'Partecipante';
      case 'invited':
        return 'Invitato';
      case 'all':
      default:
        return 'Tutte';
    }
  }

  List<_LeagueCardItem> _itemsForTab(String tabKey, List<_LeagueCardItem> joined, List<_LeagueCardItem> invited) {
    if (tabKey == 'joined') return joined;
    if (tabKey == 'invited') return invited;
    return [...joined, ...invited];
  }

  // ---------------- JOIN CODE (espandibile) ----------------
  Future<void> _pasteJoinCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = (data?.text ?? '').trim();
    if (t.isEmpty) return;
    setState(() => _joinCodeCtrl.text = t.toUpperCase());
  }

  Future<void> _scanQrJoin() async {
    final code = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    final v = (code ?? '').trim();
    if (v.isEmpty) return;
    setState(() => _joinCodeCtrl.text = v.toUpperCase());
  }

  Future<void> _joinWithCode() async {
    final user = _auth.currentUser;
    if (user == null) {
      _toast('Devi prima fare login.');
      return;
    }

    final code = _joinCodeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      _toast('Inserisci un JoinCode.');
      return;
    }

    setState(() => _joining = true);
    try {
      // ✅ CORRETTO: invia richiesta join
      final res = await _api.requestJoinByCode(joinCode: code);

      final leagueId = (res['leagueId'] ?? '').toString().trim();
      final alreadyMember = res['alreadyMember'] == true;
      final alreadyRequested = res['alreadyRequested'] == true;

      if (alreadyMember) {
        _toast('Sei già membro di questa lega.');
        if (leagueId.isNotEmpty) {
          await _openLeague(leagueId);
          setState(() => _refreshTick++);
        }
      } else if (alreadyRequested) {
        _toast('Richiesta già inviata. Attendi approvazione.');
      } else {
        _toast('Richiesta inviata! Attendi approvazione.');
      }

      setState(() => _joinExpanded = false);
    } catch (e) {
      _toast('Errore richiesta: $e');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }



  // ---------------- INVITE MANUAL (espandibile) ----------------
  Future<void> _pasteInviteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = (data?.text ?? '').trim();
    if (t.isEmpty) return;
    setState(() => _inviteCtrl.text = t);
  }

  Future<void> _scanInvite() async {
    final code = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    final v = (code ?? '').trim();
    if (v.isEmpty) return;
    setState(() => _inviteCtrl.text = v);
  }

  Future<void> _joinWithInvite() async {
    final user = _auth.currentUser;
    if (user == null) {
      _toast('Devi prima fare login.');
      return;
    }

    final code = _inviteCtrl.text.trim();
    if (code.isEmpty || !code.contains(':')) {
      _toast('Inserisci un codice invito valido (leagueId:inviteId).');
      return;
    }

    final parts = code.split(':');
    if (parts.length < 2) {
      _toast('Codice invito non valido.');
      return;
    }

    final leagueId = parts[0].trim();
    final inviteId = parts[1].trim();

    setState(() => _acceptingInvite = true);
    try {
      final res = await _api.acceptInvite(leagueId: leagueId, inviteId: inviteId);


      final lid = (res['leagueId'] ?? leagueId).toString().trim();
      await _openLeague(lid);

      if (mounted) {
        setState(() {
          _inviteExpanded = false;
          _refreshTick++;
        });
      }
      _toast('Invito accettato!');
    } catch (e) {
      _toast('Errore invito: $e');
    } finally {
      if (mounted) setState(() => _acceptingInvite = false);
    }
  }


  Future<void> _acceptInviteFromList(_LeagueCardItem item) async {
    if (item.inviteId == null || item.inviteId!.isEmpty) return;

    try {
      final res = await _api.acceptInvite(
        leagueId: item.leagueId,
        inviteId: item.inviteId!,
      );

      final leagueId = (res['leagueId'] ?? item.leagueId).toString().trim();
      await _openLeague(leagueId);
      _toast('Invito accettato!');
    } catch (e) {
      _toast('Errore accettazione invito: $e');
    } finally {
      setState(() => _refreshTick++);
    }
  }



  // ---------------- CREATE LEAGUE (2a TAB) ----------------
  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;

    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() => _logoBytes = bytes);
  }


  Future<void> _bootstrapMyMemberDocAfterCreate({
    required String leagueId,
    required User user,
    required String nome,
    required String cognome,
  }) async {
    final memberRef = _db
        .collection('Leagues')
        .doc(leagueId)
        .collection('members')
        .doc(user.uid);

    // Leggo l'esistente (creato dalla function) per NON sovrascrivere createdAt se già presente
    Map<String, dynamic> existing = {};
    try {
      final snap = await memberRef.get();
      existing = snap.data() ?? {};
    } catch (_) {}

    final email = (user.email ?? '').trim();
    final emailLower = email.toLowerCase().trim();

    final nomeClean = nome.trim();
    final cognomeClean = cognome.trim();
    final nomeLower = nomeClean.toLowerCase();
    final cognomeLower = cognomeClean.toLowerCase();

    // Provo a recuperare la foto dal globale Users/{uid} (se esiste)
    String photoUrl = '';
    try {
      final uSnap = await _db.collection('Users').doc(user.uid).get();
      final uData = uSnap.data() ?? {};
      final profile = (uData['profile'] is Map)
          ? Map<String, dynamic>.from(uData['profile'])
          : <String, dynamic>{};

      photoUrl = (profile['photoUrl'] ?? uData['photoUrl'] ?? '').toString().trim();
    } catch (_) {}

    // Campo robusto per ordinamenti/ricerche future (se decidi di usarlo)
    final sortKey = ('$cognomeLower $nomeLower'.trim().isNotEmpty)
        ? '$cognomeLower $nomeLower'.trim()
        : (emailLower.isNotEmpty ? emailLower : user.uid);

    final payload = <String, dynamic>{
      'uid': user.uid,

      // email (per compat: alcuni punti usano emailLogin, altri email)
      if (email.isNotEmpty) 'email': email,
      if (email.isNotEmpty) 'emailLogin': email,
      if (emailLower.isNotEmpty) 'emailLower': emailLower,

      // campi “display” che spesso servono alla lista utenti
      'displayNome': nomeClean,
      'displayCognome': cognomeClean,
      'displayNomeLower': nomeLower,
      'displayCognomeLower': cognomeLower,

      // opzionali ma utili
      'sortKey': sortKey,
      if (photoUrl.isNotEmpty) 'photoUrl': photoUrl,

      // default safe (non danno fastidio e ti evitano filtri che tagliano fuori l’owner)
      'isActive': true,
      'deleted': false,

      // strutture attese in UserDetail / UI
      'org': existing['org'] is Map
          ? existing['org']
          : <String, dynamic>{'organizzazione': null, 'comparto': null, 'jobRole': null},
      'overrides': existing['overrides'] is Map
          ? existing['overrides']
          : <String, dynamic>{
        'recapiti': <String, dynamic>{'telefono': null, 'emailSecondarie': <String>[]},
        'anagrafica': <String, dynamic>{'iban': null},
      },
      'custom': existing['custom'] is Map ? existing['custom'] : <String, dynamic>{},

      // timestamp
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // non sovrascrivo createdAt se già esiste
    if (!existing.containsKey('createdAt')) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }

    // merge: NON tocchiamo roleId (owner) già creato dalla function
    await memberRef.set(payload, SetOptions(merge: true));
  }




  Future<void> _createLeague() async {
    final user = _auth.currentUser;
    if (user == null) {
      _toast('Devi prima fare login.');
      return;
    }

    // ✅ ordine: Cognome + Nome (come vuoi tu)
    final cognomeCreatore = _creatorCognomeCtrl.text.trim();
    final nomeCreatore = _creatorNomeCtrl.text.trim();

    if (cognomeCreatore.isEmpty || nomeCreatore.isEmpty) {
      _toast('Inserisci Cognome e Nome del creatore.');
      return;
    }

    final nomeLega = _createNameCtrl.text.trim();
    if (nomeLega.isEmpty) {
      _toast('Inserisci il nome della lega.');
      return;
    }

    setState(() => _creating = true);
    try {
      // ✅ 1) creo la lega via callable (la function crea members + aggiorna Users)
      final res = await _api.createLeague(
        nome: nomeLega,
        logoBytes: _logoBytes,
        creatorNome: nomeCreatore,
        creatorCognome: cognomeCreatore,
      );

      final leagueId = (res['leagueId'] ?? '').toString().trim();
      if (leagueId.isEmpty) {
        _toast('Errore: leagueId vuoto.');
        return;
      }

      // ❌ NO bootstrap member dal client (lo fa già la function)
      // await _bootstrapMyMemberDocAfterCreate(...);

      // ✅ 2) apro lega (callable setActiveLeague) — opzionale ma ok
      await _openLeague(leagueId);

      _toast('Lega creata!');
      _createNameCtrl.clear();

      if (mounted) {
        setState(() {
          _logoBytes = null;
          _refreshTick++;
        });
      }
    } catch (e) {
      _toast('Errore creazione: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }




  // ---------------- PREFERENZE SOTTOTAB ----------------
  Future<void> _openPrefsDialog() async {
    final tmpOrder = [..._tabOrder];
    var tmpDefault = _defaultTab;

    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Preferenze schede'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(alignment: Alignment.centerLeft, child: Text('Scheda di default:')),
                const SizedBox(height: 6),
                DropdownButton<String>(
                  value: tmpDefault,
                  items: tmpOrder.map((k) => DropdownMenuItem(value: k, child: Text(_labelOf(k)))).toList(),
                  onChanged: (v) => setState(() => tmpDefault = v ?? 'all'),
                ),
                const SizedBox(height: 14),
                const Align(alignment: Alignment.centerLeft, child: Text('Ordine schede (trascina):')),
                const SizedBox(height: 8),
                Flexible(
                  child: ReorderableListView(
                    shrinkWrap: true,
                    onReorder: (oldIndex, newIndex) {
                      if (newIndex > oldIndex) newIndex--;
                      final item = tmpOrder.removeAt(oldIndex);
                      tmpOrder.insert(newIndex, item);
                      setState(() {});
                    },
                    children: [
                      for (final k in tmpOrder)
                        ListTile(
                          key: ValueKey(k),
                          title: Text(_labelOf(k)),
                          trailing: const Icon(Icons.drag_handle),
                        )
                    ],
                  ),
                )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
            ElevatedButton(
              onPressed: () async {
                await _prefs.save(tabOrder: tmpOrder, defaultTab: tmpDefault);
                if (!mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Salva'),
            )
          ],
        );
      },
    );

    await _initPrefs();
  }

  // ---------------- UI PIECES ----------------
  Widget _buildLeagueTile(_LeagueCardItem item, String activeLeagueId) {
    final isActive = !item.invited && item.leagueId == activeLeagueId;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: item.invited ? null : () => _openLeague(item.leagueId),
        leading: CircleAvatar(
          backgroundImage: item.logoUrl.isNotEmpty ? NetworkImage(item.logoUrl) : null,
          child: item.logoUrl.isEmpty ? const Icon(Icons.apartment) : null,
        ),
        title: Text(item.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: item.invited
            ? Text('Invitato${item.roleId != null ? " (ruolo: ${item.roleId})" : ""}')
            : (item.joinCode.isNotEmpty ? Text('Codice: ${item.joinCode}') : null),
        trailing: item.invited
            ? TextButton(
          onPressed: () => _acceptInviteFromList(item),
          child: const Text('ACCETTA'),
        )
            : (isActive ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.chevron_right)),
      ),
    );
  }

  Widget _fastExpandableCard({
    required bool expanded,
    required VoidCallback onToggle,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.expand_more),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: child,
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinExpansion() {
    return _fastExpandableCard(
      expanded: _joinExpanded,
      onToggle: () {
        setState(() {
          _joinExpanded = !_joinExpanded;
          if (_joinExpanded) _inviteExpanded = false;
        });
      },
      title: 'Entra con JoinCode',
      icon: Icons.vpn_key,
      child: Column(
        children: [
          TextField(
            controller: _joinCodeCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'JoinCode',
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Incolla',
                    onPressed: _joining ? null : _pasteJoinCode,
                    icon: const Icon(Icons.content_paste),
                  ),
                  IconButton(
                    tooltip: 'Scansiona QR',
                    onPressed: _joining ? null : _scanQrJoin,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ],
              ),
            ),
            onChanged: (v) {
              final up = v.toUpperCase();
              if (up != v) {
                _joinCodeCtrl.value = _joinCodeCtrl.value.copyWith(
                  text: up,
                  selection: TextSelection.collapsed(offset: up.length),
                );
              }
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _joining ? null : _joinWithCode,
              icon: _joining
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.arrow_forward),
              label: Text(_joining ? 'Attendi...' : 'ENTRA'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteExpansion() {
    return _fastExpandableCard(
      expanded: _inviteExpanded,
      onToggle: () {
        setState(() {
          _inviteExpanded = !_inviteExpanded;
          if (_inviteExpanded) _joinExpanded = false;
        });
      },
      title: 'Entra con Invito',
      icon: Icons.mail,
      child: Column(
        children: [
          TextField(
            controller: _inviteCtrl,
            decoration: InputDecoration(
              labelText: 'Codice invito (leagueId:inviteId)',
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Incolla',
                    onPressed: _acceptingInvite ? null : _pasteInviteCode,
                    icon: const Icon(Icons.content_paste),
                  ),
                  IconButton(
                    tooltip: 'Scansiona QR',
                    onPressed: _acceptingInvite ? null : _scanInvite,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _acceptingInvite ? null : _joinWithInvite,
              icon: _acceptingInvite
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_acceptingInvite ? 'Attendi...' : 'ACCETTA INVITO'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Crea nuova lega', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const Text('Dati creatore', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _creatorCognomeCtrl,
                  focusNode: _fnCognome,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_fnNomeLega),
                  decoration: const InputDecoration(labelText: 'Cognome', border: OutlineInputBorder()),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _creatorNomeCtrl,
                  focusNode: _fnNome,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).requestFocus(_fnCognome),
                  decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          TextField(
            controller: _createNameCtrl,
            focusNode: _fnNomeLega,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _creating ? null : _createLeague(),
            decoration: const InputDecoration(labelText: 'Nome lega', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundImage: _logoBytes != null ? MemoryImage(_logoBytes!) : null,
                child: _logoBytes == null ? const Icon(Icons.image) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _creating ? null : _pickLogo,
                  icon: const Icon(Icons.upload),
                  label: const Text('Scegli logo (opzionale)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _creating ? null : _createLeague,
              icon: _creating
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_business),
              label: Text(_creating ? 'Attendi...' : 'CREA LEGA'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = _auth.currentUser;
    if (u == null) {
      return const Scaffold(body: Center(child: Text('Utente non loggato')));
    }

    final userRef = _db.collection('Users').doc(u.uid);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('DMS - Leagues'),
          actions: [
            IconButton(
              tooltip: 'Gestisci Leagues',
              icon: const Icon(Icons.list_alt),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LeagueAccessPage()));
              },
            ),
            IconButton(
              tooltip: 'Preferenze schede',
              icon: const Icon(Icons.tune),
              onPressed: _openPrefsDialog,
            ),
            IconButton(
              tooltip: 'Aggiorna',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() => _refreshTick++),
            ),
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: () async => AuthService().logout(clearActiveLeague: true),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'LE TUE LEGHE'),
              Tab(text: 'CREA NUOVA LEGA'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ---------------- TAB 1: LE TUE LEGHE ----------------
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: userRef.snapshots(),
              builder: (context, userSnap) {
                if (userSnap.hasError) return const Center(child: Text('Errore nel caricamento utente'));
                if (!userSnap.hasData) return const Center(child: CircularProgressIndicator());

                final data = userSnap.data!.data() ?? {};
                final activeLeagueId = (data['activeLeagueId'] is String) ? (data['activeLeagueId'] as String).trim() : '';

                final leagueIdsRaw = (data['leagueIds'] is List) ? data['leagueIds'] as List : [];
                final leagueIds = leagueIdsRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();

                final emailLower = ((u.email ?? '').toLowerCase()).trim();

                return FutureBuilder<Map<String, List<_LeagueCardItem>>>(
                  future: _getListsFuture(
                    joinedLeagueIds: leagueIds,
                    emailLower: emailLower,
                    activeLeagueId: activeLeagueId,
                  ),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('Errore: ${snap.error}'));
                    }

                    final waiting = snap.connectionState == ConnectionState.waiting;
                    final joined = snap.data?['joined'] ?? <_LeagueCardItem>[];
                    final invited = snap.data?['invited'] ?? <_LeagueCardItem>[];
                    final totalAll = joined.length + invited.length;

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                          child: _buildJoinExpansion(),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                          child: _buildInviteExpansion(),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Le tue leghe ($totalAll)',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // SOTTOTAB sotto “Le tue leghe”
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: TabBar(
                            controller: _subTabController,
                            tabs: _tabOrder.map((k) => Tab(text: _labelOf(k))).toList(),
                          ),
                        ),
                        const Divider(height: 1),

                        Expanded(
                          child: waiting
                              ? const Center(child: CircularProgressIndicator())
                              : TabBarView(
                            controller: _subTabController,
                            children: _tabOrder.map((k) {
                              final items = _itemsForTab(k, joined, invited);
                              if (items.isEmpty) {
                                return Center(child: Text('Nessuna lega in "${_labelOf(k)}"'));
                              }
                              return ListView.separated(
                                padding: const EdgeInsets.all(14),
                                itemCount: items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, i) => _buildLeagueTile(items[i], activeLeagueId),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),

            // ---------------- TAB 2: CREA NUOVA LEGA ----------------
            _buildCreateTab(),
          ],
        ),
      ),
    );
  }
}
