import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dms_app/core/service/user/user_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class InvitiPendingPage extends StatelessWidget {
  final String leagueId;
  const InvitiPendingPage({super.key, required this.leagueId});

  static bool _openingInviteDialog = false;
  static bool _openingRoleDialog = false;

  String _s(dynamic v) => (v ?? '').toString().trim();

  void _snack(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _payload(String inviteId) {
    return UserService.buildInvitePayload(leagueId: leagueId, inviteId: inviteId);
  }

  String _shareMessage({
    required String payload,
    required String inviteId,
    required String email,
    required String roleId,
    required String prefillFull,
    String filiale = '',
    String comparto = '',
  }) {
    return [
      'INVITO DMS',
      if (email.isNotEmpty) 'Per: $email',
      if (prefillFull.isNotEmpty) 'Nome: $prefillFull',
      if (filiale.trim().isNotEmpty) 'Filiale: ${filiale.trim()}',
      if (comparto.trim().isNotEmpty) 'Comparto: ${comparto.trim()}',
      'Ruolo: ${roleId.isEmpty ? 'member' : roleId}',
      '',
      'Apri app → Entra con invito → Scansiona QR oppure incolla:',
      payload,
      '',
      'InviteId: $inviteId',
    ].join('\n');
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack(context, 'Copiato negli appunti.');
  }

  Future<void> _share(BuildContext context, String text) async {
    try {
      if (kIsWeb) {
        await _copy(context, text);
        _snack(context, 'Share non disponibile su Web: testo copiato.');
        return;
      }
      await Share.share(text, subject: 'Invito DMS');
    } catch (_) {
      await _copy(context, text);
      _snack(context, 'Condivisione non riuscita: testo copiato.');
    }
  }

  // ==========================================================
  // ✅ FIX OVERFLOW: QR dialog ora usa _dialogShell (scroll + tastiera)
  // ==========================================================
  Future<void> _showQrDialog(
      BuildContext context,
      String inviteId, {
        String? email,
        String? roleId,
        String? prefillFull,
        String? filiale,
        String? comparto,
      }) async {
    // chiudi eventuale tastiera prima di aprire il QR
    FocusScope.of(context).unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final payload = _payload(inviteId);

    final msg = _shareMessage(
      payload: payload,
      inviteId: inviteId,
      email: (email ?? '').trim(),
      roleId: (roleId ?? '').trim(),
      prefillFull: (prefillFull ?? '').trim(),
      filiale: (filiale ?? '').trim(),
      comparto: (comparto ?? '').trim(),
    );

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (ctx) {
        final shortest = MediaQuery.of(ctx).size.shortestSide;
        final qrSize = (shortest - 160).clamp(170.0, 260.0).toDouble();

        final body = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: QrImageView(data: payload, size: qrSize)),
            const SizedBox(height: 12),
            SelectableText(
              payload,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'Inquadra il QR oppure copia/incolla il codice invito.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        );

        return _dialogShell(
          ctx,
          title: 'Invito (QR)',
          saving: false,
          body: body,
          actions: [
            OutlinedButton.icon(
              onPressed: () => _copy(ctx, payload),
              icon: const Icon(Icons.copy),
              label: const Text('Copia'),
            ),
            ElevatedButton.icon(
              onPressed: () => _share(ctx, msg),
              icon: const Icon(Icons.share),
              label: const Text('Condividi'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(),
              child: const Text('Chiudi'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmAndRevoke(BuildContext context, String inviteId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revocare invito?'),
        content: const Text('L’invito passerà in stato "revoked".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revoca')),
        ],
      ),
    );

    if (ok != true) return;

    await UserService.revokeInvite(leagueId: leagueId, inviteId: inviteId);
    _snack(context, 'Invito revocato.');
  }

  // ==========================================================
  // ✅ SHELL DIALOG “keyboard-safe”
  // ==========================================================
  Widget _dialogShell(
      BuildContext ctx, {
        required String title,
        required Widget body,
        required List<Widget> actions,
        required bool saving,
      }) {
    final mq = MediaQuery.of(ctx);
    final bottomInset = mq.viewInsets.bottom;
    final maxH = mq.size.height - bottomInset - 24;
    final alignment = bottomInset > 0 ? Alignment.topCenter : Alignment.center;

    return PopScope(
      canPop: !saving,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(ctx).unfocus(),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
          child: Align(
            alignment: alignment,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: maxH < 240 ? 240 : maxH,
              ),
              child: Material(
                color: Theme.of(ctx).dialogBackgroundColor,
                elevation: 24,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Chiudi',
                            onPressed: saving
                                ? null
                                : () {
                              FocusScope.of(ctx).unfocus();
                              Navigator.of(ctx, rootNavigator: true).pop();
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: body,
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 10,
                        children: actions,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // ✅ CREATE ROLE dialog (usa SOLO comparto)
  // ==========================================================
  Future<String?> _showCreateRoleDialog(
      BuildContext context, {
        required String implicitCompartoFromInvite,
      }) async {
    if (_openingRoleDialog) return null;
    _openingRoleDialog = true;

    final nameCtrl = TextEditingController();
    final tierCtrl = TextEditingController(text: '2');
    final fnName = FocusNode();
    final fnTier = FocusNode();

    bool saving = false;
    String? createdRoleId;

    bool showAdvanced = false;
    bool showAnchorList = false;
    bool placeAbove = true;
    String? anchorRoleId;

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchRoles() async {
      final snap = await UserService.rolesCol(leagueId).orderBy('tier').get();
      return snap.docs.toList()
        ..sort((a, b) {
          final ta = (a.data()['tier'] as num?)?.toInt() ?? 999999;
          final tb = (b.data()['tier'] as num?)?.toInt() ?? 999999;
          return ta.compareTo(tb);
        });
    }

    int tierOfDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
        (d.data()['tier'] as num?)?.toInt() ?? 999999;

    String labelOfDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      final data = d.data();
      final t = tierOfDoc(d);
      final n = (data['name'] ?? d.id).toString();
      final comp = (data['comparto'] ?? '').toString().trim();
      return comp.isEmpty ? 'Tier $t • $n' : 'Tier $t • $n • $comp';
    }

    int suggestedTierFromAnchor(List<QueryDocumentSnapshot<Map<String, dynamic>>> roles) {
      if (roles.isEmpty) return 2;
      final anchor = roles.firstWhere(
            (d) => d.id == anchorRoleId,
        orElse: () => roles.first,
      );
      final aTier = tierOfDoc(anchor);
      int suggested = placeAbove ? aTier : (aTier + 1);
      if (suggested < 2) suggested = 2;
      return suggested;
    }

    try {
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setSt) {
              Future<void> submit(List<QueryDocumentSnapshot<Map<String, dynamic>>> roles) async {
                final name = nameCtrl.text.trim();
                final tier = int.tryParse(tierCtrl.text.trim());

                if (name.isEmpty) {
                  _snack(context, 'Inserisci il nome del ruolo.');
                  fnName.requestFocus();
                  return;
                }
                if (tier == null || tier < 2) {
                  _snack(context, 'Tier non valido. Usa un numero >= 2 (tier 1 è Owner).');
                  fnTier.requestFocus();
                  return;
                }

                setSt(() => saving = true);
                try {
                  final comp = implicitCompartoFromInvite.trim();

                  final newId = await UserService.insertRoleAtTier(
                    leagueId: leagueId,
                    tier: tier,
                    name: name,
                    comparto: comp.isEmpty ? null : comp,
                    permissions: const {},
                  );

                  createdRoleId = newId;

                  if (!ctx.mounted) return;
                  FocusScope.of(ctx).unfocus();
                  await Future<void>.delayed(const Duration(milliseconds: 20));
                  if (!ctx.mounted) return;
                  Navigator.of(ctx, rootNavigator: true).pop();
                } catch (e) {
                  _snack(context, 'Errore creazione ruolo: $e');
                } finally {
                  if (ctx.mounted) setSt(() => saving = false);
                }
              }

              return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                future: fetchRoles(),
                builder: (context, snap) {
                  final roles = snap.data ?? const [];

                  if (anchorRoleId == null && roles.isNotEmpty) {
                    final nonOwner = roles.where((d) => d.id != 'owner').toList();
                    if (nonOwner.isNotEmpty) anchorRoleId = nonOwner.first.id;
                  }

                  final body = Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        key: const ValueKey('role_name'),
                        controller: nameCtrl,
                        focusNode: fnName,
                        enabled: !saving,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => FocusScope.of(ctx).requestFocus(fnTier),
                        decoration: const InputDecoration(
                          labelText: 'Nome ruolo (es. Preposto)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const ValueKey('role_tier'),
                        controller: tierCtrl,
                        focusNode: fnTier,
                        enabled: !saving,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submit(roles),
                        decoration: const InputDecoration(
                          labelText: 'Tier (2,3,4...)',
                          helperText: 'Numeri più piccoli = più potere. Tier 1 è Owner.',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black.withOpacity(0.08)),
                        ),
                        child: Text(
                          'Comparto (da invito): ${implicitCompartoFromInvite.trim().isEmpty ? '—' : implicitCompartoFromInvite.trim()}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text('Opzioni avanzate', style: TextStyle(fontWeight: FontWeight.w900)),
                                ),
                                Switch(
                                  value: showAdvanced,
                                  onChanged: saving ? null : (v) => setSt(() => showAdvanced = v),
                                ),
                              ],
                            ),
                            if (showAdvanced) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: saving || roles.isEmpty
                                          ? null
                                          : () {
                                        final sug = suggestedTierFromAnchor(roles);
                                        tierCtrl.text = sug.toString();
                                        _snack(context, 'Tier suggerito: $sug');
                                      },
                                      icon: const Icon(Icons.auto_fix_high),
                                      label: const Text('Suggerisci tier'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ToggleButtons(
                                    isSelected: [placeAbove, !placeAbove],
                                    onPressed: saving ? null : (idx) => setSt(() => placeAbove = (idx == 0)),
                                    children: const [
                                      Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 10),
                                        child: Text('Sopra'),
                                      ),
                                      Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 10),
                                        child: Text('Sotto'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: saving || roles.isEmpty
                                      ? null
                                      : () => setSt(() => showAnchorList = !showAnchorList),
                                  icon: Icon(showAnchorList ? Icons.expand_less : Icons.expand_more),
                                  label: const Text('Scegli ruolo di riferimento'),
                                ),
                              ),
                              if (showAnchorList && roles.isNotEmpty) ...[
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 180),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: roles.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (_, i) {
                                      final d = roles[i];
                                      final isOwner = d.id == 'owner';

                                      return RadioListTile<String>(
                                        value: d.id,
                                        groupValue: anchorRoleId,
                                        onChanged: (saving || isOwner) ? null : (v) => setSt(() => anchorRoleId = v),
                                        title: Text(
                                          labelOfDoc(d),
                                          style: TextStyle(fontWeight: isOwner ? FontWeight.w900 : FontWeight.w700),
                                        ),
                                        subtitle: isOwner ? const Text('Owner (tier 1)') : null,
                                        dense: true,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  );

                  return _dialogShell(
                    ctx,
                    title: 'Crea nuovo ruolo',
                    saving: saving,
                    body: body,
                    actions: [
                      TextButton(
                        onPressed: saving
                            ? null
                            : () async {
                          FocusScope.of(ctx).unfocus();
                          await Future<void>.delayed(const Duration(milliseconds: 20));
                          if (!ctx.mounted) return;
                          Navigator.of(ctx, rootNavigator: true).pop();
                        },
                        child: const Text('Annulla'),
                      ),
                      ElevatedButton(
                        onPressed: saving ? null : () => submit(roles),
                        child: saving
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Crea'),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      );
    } finally {
      nameCtrl.dispose();
      tierCtrl.dispose();
      fnName.dispose();
      fnTier.dispose();
      _openingRoleDialog = false;
    }

    return createdRoleId;
  }

  // ==========================================================
  // ✅ CREATE INVITE
  // ==========================================================
  Future<void> _showCreateInviteDialog(BuildContext context) async {
    if (_openingInviteDialog) return;
    _openingInviteDialog = true;

    final emailCtrl = TextEditingController();
    final cognomeCtrl = TextEditingController();
    final nomeCtrl = TextEditingController();
    final filialeCtrl = TextEditingController();
    final compartoCtrl = TextEditingController();

    final fnEmail = FocusNode();
    final fnCognome = FocusNode();
    final fnNome = FocusNode();
    final fnFiliale = FocusNode();
    final fnComparto = FocusNode();

    String selectedRoleId = 'member';

    bool showRoleCreator = false;
    bool creatingRole = false;

    final newRoleNameCtrl = TextEditingController();
    final fnNewRoleName = FocusNode();

    String? anchorRoleId;
    bool placeAbove = true;

    bool savingInvite = false;

    try {
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setSt) {
              Future<void> submitInvite() async {
                final email = emailCtrl.text.trim();
                if (email.isEmpty || !email.contains('@')) {
                  _snack(context, 'Inserisci una email valida.');
                  fnEmail.requestFocus();
                  return;
                }
                if (selectedRoleId.isEmpty) {
                  _snack(context, 'Seleziona un ruolo.');
                  return;
                }
                if (selectedRoleId == 'owner') {
                  _snack(context, 'Non puoi invitare assegnando Owner.');
                  return;
                }

                setSt(() => savingInvite = true);
                try {
                  final inviteId = await UserService.createInvite(
                    leagueId: leagueId,
                    email: email,
                    roleId: selectedRoleId,
                    prefillNome: nomeCtrl.text.trim(),
                    prefillCognome: cognomeCtrl.text.trim(),
                    prefillFiliale: filialeCtrl.text.trim(),
                    prefillComparto: compartoCtrl.text.trim(),
                  );

                  if (!ctx.mounted) return;

                  FocusScope.of(ctx).unfocus();
                  await Future<void>.delayed(const Duration(milliseconds: 30));
                  if (!ctx.mounted) return;

                  Navigator.of(ctx, rootNavigator: true).pop();

                  await Future<void>.delayed(Duration.zero);

                  final prefillFull = [
                    cognomeCtrl.text.trim(),
                    nomeCtrl.text.trim(),
                  ].where((e) => e.isNotEmpty).join(' ');

                  if (context.mounted) {
                    await _showQrDialog(
                      context,
                      inviteId,
                      email: email,
                      roleId: selectedRoleId,
                      prefillFull: prefillFull,
                      filiale: filialeCtrl.text.trim(),
                      comparto: compartoCtrl.text.trim(),
                    );
                  }
                } catch (e) {
                  _snack(context, 'Errore creazione invito: $e');
                } finally {
                  if (ctx.mounted) setSt(() => savingInvite = false);
                }
              }

              Widget rolesSection() {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: UserService.streamRoles(leagueId),
                  builder: (c, snap) {
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      );
                    }

                    final List<QueryDocumentSnapshot<Map<String, dynamic>>> rolesAll =
                    (snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]).toList()
                      ..sort((a, b) {
                        final ta = (a.data()['tier'] as num?)?.toInt() ?? 999999;
                        final tb = (b.data()['tier'] as num?)?.toInt() ?? 999999;
                        return ta.compareTo(tb);
                      });

                    QueryDocumentSnapshot<Map<String, dynamic>>? findRole(String id) {
                      for (final d in rolesAll) {
                        if (d.id == id) return d;
                      }
                      return null;
                    }

                    int tierOf(QueryDocumentSnapshot<Map<String, dynamic>> d) {
                      final data = d.data();
                      return (data['tier'] as num?)?.toInt() ?? (data['rank'] as num?)?.toInt() ?? 999999;
                    }

                    final effectiveAnchorId =
                    (anchorRoleId != null && findRole(anchorRoleId!) != null)
                        ? anchorRoleId!
                        : (rolesAll.isNotEmpty ? rolesAll.first.id : '');

                    final anchorDoc = effectiveAnchorId.isEmpty ? null : findRole(effectiveAnchorId);

                    int computedTier = 2;
                    if (anchorDoc != null) {
                      final anchorTier = tierOf(anchorDoc);
                      if (anchorDoc.id == 'owner') {
                        computedTier = 2;
                      } else {
                        computedTier = placeAbove ? anchorTier : (anchorTier + 1);
                        if (computedTier < 2) computedTier = 2;
                      }
                    }

                    final rolesSelectable = rolesAll.where((d) => d.id != 'owner').toList();

                    final dropdownItems = <DropdownMenuItem<String>>[
                      const DropdownMenuItem(value: 'member', child: Text('Member (base)')),
                      ...rolesSelectable.map((d) {
                        final data = d.data();
                        final tier = (data['tier'] ?? data['rank'] ?? '?').toString();
                        final name = (data['name'] ?? d.id).toString();
                        final comp = (data['comparto'] ?? '').toString().trim();
                        final label = comp.isEmpty ? 'Tier $tier • $name' : 'Tier $tier • $name • $comp';
                        return DropdownMenuItem(value: d.id, child: Text(label));
                      }),
                    ];

                    Future<void> createRoleInline() async {
                      final roleName = newRoleNameCtrl.text.trim();
                      if (roleName.isEmpty) {
                        _snack(context, 'Inserisci il nome del ruolo.');
                        fnNewRoleName.requestFocus();
                        return;
                      }

                      final compInvito = compartoCtrl.text.trim();
                      if (compInvito.isEmpty) {
                        _snack(
                          context,
                          'Prima compila il campo "Comparto (prefill)" dell’invito: verrà usato per il ruolo.',
                        );
                        fnComparto.requestFocus();
                        return;
                      }

                      setSt(() => creatingRole = true);
                      try {
                        final newId = await UserService.insertRoleAtTier(
                          leagueId: leagueId,
                          tier: computedTier,
                          name: roleName,
                          comparto: compInvito,
                          permissions: const {},
                        );

                        setSt(() {
                          selectedRoleId = newId;
                          showRoleCreator = false;
                          creatingRole = false;
                          newRoleNameCtrl.clear();
                        });

                        _snack(context, 'Ruolo creato e selezionato.');
                      } catch (e) {
                        _snack(context, 'Errore creazione ruolo: $e');
                        setSt(() => creatingRole = false);
                      }
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: selectedRoleId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Ruolo da assegnare',
                                  border: OutlineInputBorder(),
                                ),
                                items: dropdownItems,
                                onChanged: (savingInvite || creatingRole)
                                    ? null
                                    : (v) {
                                  if (v == null) return;
                                  setSt(() => selectedRoleId = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: (savingInvite || creatingRole)
                                  ? null
                                  : () {
                                FocusScope.of(ctx).unfocus();
                                setSt(() {
                                  showRoleCreator = !showRoleCreator;
                                  if (showRoleCreator) {
                                    if (selectedRoleId != 'member' && findRole(selectedRoleId) != null) {
                                      anchorRoleId = selectedRoleId;
                                    } else {
                                      anchorRoleId = rolesAll.isNotEmpty ? rolesAll.first.id : null;
                                    }
                                    placeAbove = true;
                                    newRoleNameCtrl.clear();
                                  }
                                });
                              },
                              icon: Icon(showRoleCreator ? Icons.close : Icons.add),
                              label: Text(showRoleCreator ? 'Chiudi' : 'Nuovo ruolo'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Piramide ruoli (tocca per selezionare)',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 180),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: rolesAll.length + 1,
                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                  itemBuilder: (_, i) {
                                    if (i == rolesAll.length) {
                                      final selected = selectedRoleId == 'member';
                                      return InkWell(
                                        onTap: (savingInvite || creatingRole)
                                            ? null
                                            : () => setSt(() => selectedRoleId = 'member'),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: selected ? Colors.black.withOpacity(0.08) : null,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const ListTile(
                                            dense: true,
                                            title: Text('Member (base)', style: TextStyle(fontWeight: FontWeight.w800)),
                                            subtitle: Text('Nessun potere speciale (default)'),
                                          ),
                                        ),
                                      );
                                    }

                                    final d = rolesAll[i];
                                    final data = d.data();
                                    final t = tierOf(d);
                                    final n = (data['name'] ?? d.id).toString();
                                    final comp = (data['comparto'] ?? '').toString().trim();

                                    final isOwner = d.id == 'owner';
                                    final isSelected = (!isOwner && selectedRoleId == d.id);

                                    return InkWell(
                                      onTap: (savingInvite || creatingRole || isOwner)
                                          ? null
                                          : () => setSt(() => selectedRoleId = d.id),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: isSelected ? Colors.black.withOpacity(0.08) : null,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: ListTile(
                                          dense: true,
                                          title: Text(
                                            'Tier $t • $n',
                                            style: TextStyle(fontWeight: isOwner ? FontWeight.w900 : FontWeight.w800),
                                          ),
                                          subtitle: comp.isEmpty ? null : Text(comp),
                                          trailing: isOwner
                                              ? const Text('OWNER', style: TextStyle(fontWeight: FontWeight.w900))
                                              : (isSelected ? const Icon(Icons.check) : null),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showRoleCreator) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black.withOpacity(0.08)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Crea nuovo ruolo', style: TextStyle(fontWeight: FontWeight.w900)),
                                const SizedBox(height: 10),
                                TextField(
                                  key: const ValueKey('invite_new_role_name'),
                                  controller: newRoleNameCtrl,
                                  focusNode: fnNewRoleName,
                                  enabled: !(savingInvite || creatingRole),
                                  textCapitalization: TextCapitalization.words,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => createRoleInline(),
                                  decoration: const InputDecoration(
                                    labelText: 'Nome ruolo (es. Preposto)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Text('Comparto ruolo:', style: TextStyle(fontWeight: FontWeight.w800)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        compartoCtrl.text.trim().isEmpty
                                            ? '(non compilato nell’invito)'
                                            : compartoCtrl.text.trim(),
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: effectiveAnchorId.isEmpty ? null : effectiveAnchorId,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Posiziona rispetto a…',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: rolesAll.map((d) {
                                          final data = d.data();
                                          final t = (data['tier'] ?? data['rank'] ?? '?').toString();
                                          final n = (data['name'] ?? d.id).toString();
                                          final comp = (data['comparto'] ?? '').toString().trim();
                                          final label = comp.isEmpty ? 'Tier $t • $n' : 'Tier $t • $n • $comp';
                                          return DropdownMenuItem(value: d.id, child: Text(label));
                                        }).toList(),
                                        onChanged: (savingInvite || creatingRole)
                                            ? null
                                            : (v) => setSt(() => anchorRoleId = v),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    ToggleButtons(
                                      isSelected: [placeAbove, !placeAbove],
                                      onPressed: (savingInvite || creatingRole)
                                          ? null
                                          : (idx) => setSt(() => placeAbove = (idx == 0)),
                                      children: const [
                                        Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 10),
                                          child: Text('Sopra'),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 10),
                                          child: Text('Sotto'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Tier calcolato automaticamente: $computedTier',
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: (savingInvite || creatingRole)
                                            ? null
                                            : () => setSt(() {
                                          showRoleCreator = false;
                                          newRoleNameCtrl.clear();
                                        }),
                                        child: const Text('Annulla'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: (savingInvite || creatingRole) ? null : createRoleInline,
                                        child: creatingRole
                                            ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                            : const Text('Crea ruolo'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                );
              }

              final body = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const ValueKey('invite_email'),
                    controller: emailCtrl,
                    focusNode: fnEmail,
                    enabled: !savingInvite,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(ctx).requestFocus(fnCognome),
                    decoration: const InputDecoration(
                      labelText: 'Email invitato *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('invite_cognome'),
                    controller: cognomeCtrl,
                    focusNode: fnCognome,
                    enabled: !savingInvite,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(ctx).requestFocus(fnNome),
                    decoration: const InputDecoration(
                      labelText: 'Cognome (prefill)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('invite_nome'),
                    controller: nomeCtrl,
                    focusNode: fnNome,
                    enabled: !savingInvite,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(ctx).requestFocus(fnFiliale),
                    decoration: const InputDecoration(
                      labelText: 'Nome (prefill)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('invite_filiale'),
                    controller: filialeCtrl,
                    focusNode: fnFiliale,
                    enabled: !savingInvite,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(ctx).requestFocus(fnComparto),
                    decoration: const InputDecoration(
                      labelText: 'Filiale (prefill)',
                      hintText: 'Es. Roma, Milano, HUB Nord...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('invite_comparto'),
                    controller: compartoCtrl,
                    focusNode: fnComparto,
                    enabled: !savingInvite,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => submitInvite(),
                    decoration: const InputDecoration(
                      labelText: 'Comparto (prefill)',
                      hintText: 'Es. Operativo, Magazzino, Direzione...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  rolesSection(),
                ],
              );

              return _dialogShell(
                ctx,
                title: 'Crea invito',
                saving: savingInvite,
                body: body,
                actions: [
                  TextButton(
                    onPressed: savingInvite
                        ? null
                        : () async {
                      FocusScope.of(ctx).unfocus();
                      await Future<void>.delayed(const Duration(milliseconds: 20));
                      if (!ctx.mounted) return;
                      Navigator.of(ctx, rootNavigator: true).pop();
                    },
                    child: const Text('Annulla'),
                  ),
                  ElevatedButton(
                    onPressed: savingInvite ? null : submitInvite,
                    child: savingInvite
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Crea invito'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      emailCtrl.dispose();
      cognomeCtrl.dispose();
      nomeCtrl.dispose();
      filialeCtrl.dispose();
      compartoCtrl.dispose();

      fnEmail.dispose();
      fnCognome.dispose();
      fnNome.dispose();
      fnFiliale.dispose();
      fnComparto.dispose();

      newRoleNameCtrl.dispose();
      fnNewRoleName.dispose();

      _openingInviteDialog = false;
    }
  }

  // ==========================================================
  // UI PAGE
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inviti in attesa'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateInviteDialog(context),
            tooltip: 'Crea invito',
          ),
        ],
      ),
      body: FutureBuilder<bool>(
        future: UserService.canManageInvites(leagueId: leagueId),
        builder: (context, snap) {
          final can = snap.data ?? false;

          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!can) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Non hai i permessi per gestire gli inviti.'),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: UserService.streamPendingInvites(leagueId),
            builder: (context, s) {
              if (s.hasError) return const Center(child: Text('Errore caricamento inviti.'));
              if (!s.hasData) return const Center(child: CircularProgressIndicator());

              final docs = s.data!.docs;
              if (docs.isEmpty) return const Center(child: Text('Nessun invito in attesa.'));

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final data = d.data();
                  final inviteId = d.id;

                  final email = _s(data['emailLower']);
                  final roleId = _s(data['roleId']);

                  final prefill = (data['prefill'] is Map)
                      ? Map<String, dynamic>.from(data['prefill'])
                      : <String, dynamic>{};

                  final nome = _s(prefill['nome']);
                  final cognome = _s(prefill['cognome']);
                  final filiale = _s(prefill['filiale']);
                  final comparto = _s(prefill['comparto']);

                  final prefillFull = [cognome, nome].where((e) => e.isNotEmpty).join(' ');
                  final when = (data['createdAt'] as Timestamp?)?.toDate();
                  final payload = _payload(inviteId);

                  final titleText =
                  prefillFull.isNotEmpty ? prefillFull : (email.isNotEmpty ? email : '(utente senza dati)');

                  final showEmailUnderTitle = prefillFull.isNotEmpty && email.isNotEmpty;

                  final msg = _shareMessage(
                    payload: payload,
                    inviteId: inviteId,
                    email: email,
                    roleId: roleId,
                    prefillFull: prefillFull,
                    filiale: filiale,
                    comparto: comparto,
                  );

                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: ExpansionTile(
                      key: PageStorageKey('invite_$inviteId'),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      title: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              titleText,
                              softWrap: true,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _roleChip(roleId),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showEmailUnderTitle)
                              Text(
                                email,
                                softWrap: true,
                                style: const TextStyle(fontWeight: FontWeight.w400),
                              ),
                            if (filiale.isNotEmpty || comparto.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (filiale.isNotEmpty) _miniChip('Filiale: $filiale'),
                                  if (comparto.isNotEmpty) _miniChip('Comparto: $comparto'),
                                ],
                              ),
                            ],
                            if (when != null) ...[
                              const SizedBox(height: 8),
                              Text('Creato: ${when.toLocal()}'),
                            ],
                          ],
                        ),
                      ),
                      children: [
                        const Divider(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            QrImageView(data: payload, size: 95),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Codice invito:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(payload, softWrap: true, style: const TextStyle(fontWeight: FontWeight.w200)),
                                  const SizedBox(height: 8),
                                  Text('InviteId: $inviteId', style: TextStyle(color: Colors.grey.shade700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _copy(context, payload),
                              icon: const Icon(Icons.copy),
                              label: const Text('Copia'),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _share(context, msg),
                              icon: const Icon(Icons.share),
                              label: const Text('Condividi'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _showQrDialog(
                                context,
                                inviteId,
                                email: email,
                                roleId: roleId,
                                prefillFull: prefillFull,
                                filiale: filiale,
                                comparto: comparto,
                              ),
                              icon: const Icon(Icons.qr_code_2),
                              label: const Text('Apri QR'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _confirmAndRevoke(context, inviteId),
                              icon: const Icon(Icons.block),
                              label: const Text('Revoca'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _roleChip(String roleId) {
    final r = roleId.isEmpty ? 'member' : roleId;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(r, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Widget _miniChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.08)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}
