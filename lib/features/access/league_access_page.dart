
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dms_app/core/service/auth/auth_service.dart';
import 'package:dms_app/core/service/league/dms_league_api.dart';
import 'package:dms_app/core/service/user/user_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'qr_scan_page.dart';

class LeagueAccessPage extends StatefulWidget {
  final bool startInCreate;
  const LeagueAccessPage({super.key, this.startInCreate = false});

  @override
  State<LeagueAccessPage> createState() => _LeagueAccessPageState();
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

class _LeagueAccessPageState extends State<LeagueAccessPage> with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _api = DmsLeagueApi(region: 'europe-west1');

  bool _showCreate = false;
  bool _isLoading = false;

  // expander
  bool _joinExpanded = false;
  bool _inviteExpanded = false;

  // join
  final _joinCodeCtrl = TextEditingController();

  // invite
  final _inviteCtrl = TextEditingController();
  bool _acceptingInvite = false;

  // create
  final _creatorNomeCtrl = TextEditingController();
  final _creatorCognomeCtrl = TextEditingController();
  final _createNameCtrl = TextEditingController();
  Uint8List? _logoBytes;

  final FocusNode _fnNome = FocusNode();
  final FocusNode _fnCognome = FocusNode();
  final FocusNode _fnNomeLega = FocusNode();

  // selection (via finestra)
  String? _selectedLeagueId;

  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _showCreate = widget.startInCreate;
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

    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<Map<String, dynamic>> _loadLists() => _api.listLeaguesForUser();

  Future<void> _enterLeague(String leagueId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);
    try {
      await _api.setActiveLeague(leagueId: leagueId);

      // ✅ safety: assicuro che il member esista (se la function/flow ha ritardi)
      final memRef = _db
          .collection('Leagues')
          .doc(leagueId)
          .collection('members')
          .doc(user.uid);

      // retry veloce (max ~1.2s)
      for (int i = 0; i < 6; i++) {
        final snap = await memRef.get();
        if (snap.exists) break;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      _toast('Errore entra lega: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  // ---------------- JOIN (espandibile) ----------------
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

    setState(() => _isLoading = true);
    try {
      final res = await _api.requestJoinByCode(joinCode: code);

      final leagueId = (res['leagueId'] ?? '').toString().trim();
      final alreadyMember = res['alreadyMember'] == true;
      final alreadyRequested = res['alreadyRequested'] == true;

      if (alreadyMember) {
        _toast('Sei già membro di questa lega.');
        if (leagueId.isNotEmpty) {
          await _enterLeague(leagueId);
        }
      } else if (alreadyRequested) {
        _toast('Richiesta già inviata. Attendi approvazione.');
      } else {
        _toast('Richiesta inviata! Attendi approvazione.');
      }

      if (mounted) {
        setState(() {
          _joinExpanded = false;
          _tick++;
        });
      }
    } catch (e) {
      _toast('Errore richiesta join: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------- INVITE (espandibile) ----------------
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

  Future<void> _joinWithInviteManual() async {
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
    final leagueId = parts[0].trim();
    final inviteId = parts.length > 1 ? parts[1].trim() : '';
    if (leagueId.isEmpty || inviteId.isEmpty) {
      _toast('Codice invito non valido.');
      return;
    }

    setState(() {
      _acceptingInvite = true;
      _isLoading = true;
    });

    try {
      final res = await _api.acceptInvite(leagueId: leagueId, inviteId: inviteId);
      final lid = (res['leagueId'] ?? leagueId).toString().trim();
      await _enterLeague(lid);
    } catch (e) {
      _toast('Errore invito: $e');
    } finally {
      if (mounted) {
        setState(() {
          _acceptingInvite = false;
          _isLoading = false;
          _inviteExpanded = false;
          _tick++;
        });
      }
    }
  }

  Future<void> _acceptInviteFromList(_LeagueCardItem item) async {
    if (item.inviteId == null || item.inviteId!.isEmpty) return;

    setState(() {
      _acceptingInvite = true;
      _isLoading = true;
    });

    try {
      final res = await _api.acceptInvite(
        leagueId: item.leagueId,
        inviteId: item.inviteId!,
      );

      final lid = (res['leagueId'] ?? item.leagueId).toString().trim();
      await _enterLeague(lid);
    } catch (e) {
      _toast('Errore accettazione invito: $e');
    } finally {
      if (mounted) {
        setState(() {
          _acceptingInvite = false;
          _isLoading = false;
          _tick++;
        });
      }
    }
  }

  // ---------------- CREATE ----------------
  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;

    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() => _logoBytes = bytes);
  }

  Future<void> _createLeague() async {
    final user = _auth.currentUser;
    if (user == null) {
      _toast('Devi prima fare login.');
      return;
    }

    final nomeCreatore = _creatorNomeCtrl.text.trim();
    final cognomeCreatore = _creatorCognomeCtrl.text.trim();
    if (nomeCreatore.isEmpty || cognomeCreatore.isEmpty) {
      _toast('Inserisci Nome e Cognome del creatore.');
      return;
    }

    final nomeLega = _createNameCtrl.text.trim();
    if (nomeLega.isEmpty) {
      _toast('Inserisci il nome della lega.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      // ✅ NON bloccare la creazione lega se il sync profilo fallisce
      try {
        final uSnap = await _db.collection('Users').doc(user.uid).get();
        final uData = uSnap.data() ?? {};
        final profile = UserService.buildProfileFromUserDoc(uData);
        profile['nome'] = nomeCreatore;
        profile['cognome'] = cognomeCreatore;
        await UserService.updateMyGlobalProfileAndSync(profile: profile);
      } catch (e) {
        debugPrint('Sync profilo fallito (continuo): $e');
      }

      final res = await _api.createLeague(
        nome: nomeLega,
        creatorNome: nomeCreatore,
        creatorCognome: cognomeCreatore,
        logoBytes: _logoBytes,
      );

      final leagueId = (res['leagueId'] ?? '').toString().trim();
      if (leagueId.isNotEmpty) {
        await _enterLeague(leagueId);
      } else {
        _toast('Lega creata, ma leagueId vuoto.');
      }
    } catch (e) {
      _toast('Errore creazione: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  // ---------------- UI HELPERS ----------------
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
                    onPressed: _isLoading ? null : _pasteJoinCode,
                    icon: const Icon(Icons.content_paste),
                  ),
                  IconButton(
                    tooltip: 'Scansiona QR',
                    onPressed: _isLoading ? null : _scanQrJoin,
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
              onPressed: _isLoading ? null : _joinWithCode,
              icon: _isLoading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.arrow_forward),
              label: Text(_isLoading ? 'Attendi...' : 'INVIA RICHIESTA'),
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
                    onPressed: _isLoading ? null : _pasteInviteCode,
                    icon: const Icon(Icons.content_paste),
                  ),
                  IconButton(
                    tooltip: 'Scansiona QR',
                    onPressed: _isLoading ? null : _scanInvite,
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
              onPressed: (_isLoading || _acceptingInvite) ? null : _joinWithInviteManual,
              icon: (_isLoading || _acceptingInvite)
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text((_isLoading || _acceptingInvite) ? 'Attendi...' : 'ACCETTA INVITO'),
            ),
          ),
        ],
      ),
    );
  }

  // --------- FINESTRA SELEZIONE LEGA (joined) ----------
  Future<String?> _openLeagueSelector({
    required List<_LeagueCardItem> joined,
    required String activeLeagueId,
  }) async {
    String query = '';

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final filtered = joined.where((l) {
              if (query.trim().isEmpty) return true;
              final q = query.toLowerCase().trim();
              return l.nome.toLowerCase().contains(q) || l.joinCode.toLowerCase().contains(q);
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 14,
                right: 14,
                top: 10,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Seleziona lega', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Cerca lega',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setModal(() => query = v),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Nessuna lega trovata'))
                          : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final item = filtered[i];
                          final isActive = item.leagueId == activeLeagueId;
                          final isSelected = item.leagueId == _selectedLeagueId;

                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: ListTile(
                              onTap: () => Navigator.pop(ctx, item.leagueId),
                              leading: CircleAvatar(
                                backgroundImage:
                                item.logoUrl.isNotEmpty ? NetworkImage(item.logoUrl) : null,
                                child: item.logoUrl.isEmpty ? const Icon(Icons.apartment) : null,
                              ),
                              title: Text(item.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: item.joinCode.isNotEmpty ? Text('Codice: ${item.joinCode}') : null,
                              trailing: isActive
                                  ? const Icon(Icons.check_circle, color: Colors.green)
                                  : (isSelected ? const Icon(Icons.radio_button_checked) : const Icon(Icons.chevron_right)),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --------- FINESTRA INVITI (invited) ----------
  Future<void> _openInvitesSheet(List<_LeagueCardItem> invited) async {
    if (invited.isEmpty) {
      _toast('Nessun invito in sospeso.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.70,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Inviti in sospeso (${invited.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    itemCount: invited.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final item = invited[i];
                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundImage: item.logoUrl.isNotEmpty ? NetworkImage(item.logoUrl) : null,
                            child: item.logoUrl.isEmpty ? const Icon(Icons.apartment) : null,
                          ),
                          title: Text(item.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('Invitato${item.roleId != null ? " (ruolo: ${item.roleId})" : ""}'),
                          trailing: TextButton(
                            onPressed: (_isLoading || _acceptingInvite) ? null : () => _acceptInviteFromList(item),
                            child: const Text('ACCETTA'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------- BUILD ----------------
  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DMS - Leagues'),
        actions: [
          IconButton(
            tooltip: _showCreate ? 'Vai a ENTRA' : 'Vai a CREA',
            onPressed: _isLoading ? null : () => setState(() => _showCreate = !_showCreate),
            icon: Icon(_showCreate ? Icons.login : Icons.add_business),
          ),
          IconButton(
            tooltip: 'Aggiorna',
            onPressed: _isLoading ? null : () => setState(() => _tick++),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _isLoading ? null : () async => AuthService().logout(clearActiveLeague: true),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Devi prima fare login.', textAlign: TextAlign.center))
          : AbsorbPointer(
        absorbing: _isLoading,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _showCreate ? _buildCreate() : _buildEnter(),
          ),
        ),
      ),
    );
  }

  Widget _buildEnter() {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(_tick),
      future: _loadLists(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Errore: ${snap.error}'));
        }

        final res = snap.data ?? {};
        final activeLeagueId = (res['activeLeagueId'] ?? '').toString().trim();

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

        // sort joined: active on top
        joined.sort((a, b) {
          final aActive = a.leagueId == activeLeagueId;
          final bActive = b.leagueId == activeLeagueId;
          if (aActive && !bActive) return -1;
          if (bActive && !aActive) return 1;
          return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
        });

        // init selection
        if (joined.isNotEmpty) {
          final hasSelected = _selectedLeagueId != null && joined.any((x) => x.leagueId == _selectedLeagueId);
          if (!hasSelected) {
            final hasActive = activeLeagueId.isNotEmpty && joined.any((x) => x.leagueId == activeLeagueId);
            _selectedLeagueId = hasActive ? activeLeagueId : joined.first.leagueId;
          }
        } else {
          _selectedLeagueId = null;
        }

        final selected =
        (_selectedLeagueId != null) ? joined.firstWhere((x) => x.leagueId == _selectedLeagueId, orElse: () => joined.isNotEmpty ? joined.first : _LeagueCardItem(leagueId: '', nome: '', joinCode: '', logoUrl: '', invited: false)) : null;

        return Column(
          children: [
            _buildJoinExpansion(),
            const SizedBox(height: 10),
            _buildInviteExpansion(),
            const SizedBox(height: 14),

            // --- Le mie leghe (selezione via finestra)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Le mie leghe (${joined.length})',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: (selected != null && selected.logoUrl.isNotEmpty) ? NetworkImage(selected.logoUrl) : null,
                  child: (selected == null || selected.logoUrl.isEmpty) ? const Icon(Icons.apartment) : null,
                ),
                title: Text(
                  (selected == null || selected.nome.isEmpty) ? 'Nessuna lega selezionata' : selected.nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: (selected != null && selected.joinCode.isNotEmpty) ? Text('Codice: ${selected.joinCode}') : null,
                trailing: OutlinedButton.icon(
                  onPressed: joined.isEmpty
                      ? null
                      : () async {
                    final pickedId = await _openLeagueSelector(joined: joined, activeLeagueId: activeLeagueId);
                    if (!mounted) return;
                    if (pickedId != null && pickedId.isNotEmpty) {
                      setState(() => _selectedLeagueId = pickedId);
                    }
                  },
                  icon: const Icon(Icons.search),
                  label: const Text('Seleziona'),
                ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              height: 46,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_selectedLeagueId == null || _selectedLeagueId!.isEmpty) ? null : () => _enterLeague(_selectedLeagueId!),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Entra nella lega selezionata'),
              ),
            ),

            if (invited.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 46,
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openInvitesSheet(invited),
                  icon: const Icon(Icons.mail),
                  label: Text('Gestisci inviti (${invited.length})'),
                ),
              ),
            ],

            const SizedBox(height: 6),
          ],
        );
      },
    );
  }

  Widget _buildCreate() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Crea nuova lega', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),

          const Text('Dati creatore', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),

          Row(
            children: [
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
            onSubmitted: (_) => _isLoading ? null : _createLeague(),
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
                  onPressed: _isLoading ? null : _pickLogo,
                  icon: const Icon(Icons.upload),
                  label: const Text('Scegli logo (opzionale)'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _createLeague,
            icon: const Icon(Icons.add_business),
            label: const Text('Crea lega'),
          ),
        ],
      ),
    );
  }
}
