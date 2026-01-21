// lib/core/user_fields/hr_policy_dialog.dart
// Dialog editor policy (ruoli, comparti, filiali, uids, emails) con override esplicito uid/email

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'hr_policy.dart';

class HrPolicyDialog extends StatefulWidget {
  final String leagueId;
  final HrFieldPolicy initial;
  final bool allowGlobal; // se false, non mostra "publicGlobal"
  final bool sensitive;   // se true, limita scelte (no publicGlobal)
  final bool canManage;   // owner/hr: può modificare tutto
  final bool isSelf;      // self: può modificare solo non-sensibili e solo visibilità (opzionale)
  const HrPolicyDialog({
    super.key,
    required this.leagueId,
    required this.initial,
    required this.allowGlobal,
    required this.sensitive,
    required this.canManage,
    required this.isSelf,
  });

  @override
  State<HrPolicyDialog> createState() => _HrPolicyDialogState();
}

class _HrPolicyDialogState extends State<HrPolicyDialog> {
  late HrVisibilityScope _vis;
  late HrEditScope _editScope;

  final List<String> _areas = [];

  final List<String> _branches = [];
  final List<String> _roles = [];
  final List<String> _comparti = [];
  final List<String> _uids = [];
  final List<String> _emails = [];

  final List<String> _editAreas = [];
  final List<String> _editBranches = [];
  final List<String> _editRoles = [];
  final List<String> _editComparti = [];
  final List<String> _editUids = [];
  final List<String> _editEmails = [];

  final _emailCtrl = TextEditingController();
  final _uidCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _vis = p.visibility;
    _editScope = p.editScope;

    _areas.addAll(p.areas);
    _areas.addAll(p.areas);
    _branches.addAll(p.branches);
    _roles.addAll(p.roles);
    _comparti.addAll(p.comparti);
    _uids.addAll(p.uids);
    _emails.addAll(p.emailsLower);

    _editAreas.addAll(p.editAreas);
    _editAreas.addAll(p.editAreas);
    _editBranches.addAll(p.editBranches);
    _editRoles.addAll(p.editRoles);
    _editComparti.addAll(p.editCompartI);
    _editUids.addAll(p.editUids);
    _editEmails.addAll(p.editEmailsLower);

    if (widget.sensitive) {
      // blocca global per sensibili
      if (_vis == HrVisibilityScope.publicGlobal) {
        _vis = HrVisibilityScope.restricted;
      }
    }
    if (!widget.allowGlobal && _vis == HrVisibilityScope.publicGlobal) {
      _vis = HrVisibilityScope.publicLeague;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _uidCtrl.dispose();
    super.dispose();
  }

  HrFieldPolicy _build() {
    return HrFieldPolicy(
      visibility: _vis,
      branches: List<String>.from(_branches),
      roles: List<String>.from(_roles),
      comparti: List<String>.from(_comparti),
      uids: List<String>.from(_uids),
      emailsLower: List<String>.from(_emails),
      editScope: _editScope,
      editRoles: List<String>.from(_editRoles),
      editCompartI: List<String>.from(_editComparti),
      editUids: List<String>.from(_editUids),
      editEmailsLower: List<String>.from(_editEmails),
      editBranches: List<String>.from(_editBranches),
    );
  }

  bool get _canEditPolicyFully => widget.canManage;
  bool get _canChangeVisibilitySelf => widget.isSelf && !widget.sensitive;

  @override
  Widget build(BuildContext context) {
    final allowGlobal = widget.allowGlobal && !widget.sensitive;

    return AlertDialog(
      title: const Text('Privacy campo'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Visibilità', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              _radioVis(
                title: 'Solo io',
                value: HrVisibilityScope.selfOnly,
                enabled: _canEditPolicyFully || _canChangeVisibilitySelf,
              ),
              _radioVis(
                title: 'Tutta la lega',
                value: HrVisibilityScope.publicLeague,
                enabled: _canEditPolicyFully || _canChangeVisibilitySelf,
              ),
              _radioVis(
                title: 'Pubblico globale (ricerca globale)',
                value: HrVisibilityScope.publicGlobal,
                enabled: allowGlobal && (_canEditPolicyFully || _canChangeVisibilitySelf),
              ),
              _radioVis(
                title: 'Ristretto (ruoli/comparti/filiali/utenti/email)',
                value: HrVisibilityScope.restricted,
                enabled: _canEditPolicyFully, // ristretto lo decide owner/hr
              ),
              const SizedBox(height: 12),

              if (_vis == HrVisibilityScope.restricted) ...[
                const Divider(),
                const Text('Ambito aree', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                _AreasPicker(
                  leagueId: widget.leagueId,
                  selected: _areas,
                  enabled: _canEditPolicyFully,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 10),
                const Text('Ambito filiali', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                _BranchesPicker(
                  leagueId: widget.leagueId,
                  selected: _branches,
                  enabled: _canEditPolicyFully,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 10),

                const Text('Condividi con comparti (viewer in quei comparti)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                _chipsEditor(
                  label: 'Comparti',
                  values: _comparti,
                  enabled: _canEditPolicyFully,
                  hint: 'es. HR, MOVIMENTAZIONE',
                ),
                const SizedBox(height: 10),

                const Text('Condividi con ruoli', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                _chipsEditor(
                  label: 'Ruoli',
                  values: _roles,
                  enabled: _canEditPolicyFully,
                  hint: 'es. OWNER, HR, ADMIN',
                ),
                const SizedBox(height: 10),

                const Text('Override esplicito (vince su tutto)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                _chipsEditor(
                  label: 'UID autorizzati',
                  values: _uids,
                  enabled: _canEditPolicyFully,
                  hint: 'Incolla UID o seleziona da lista (sotto)',
                ),
                const SizedBox(height: 6),
                _memberPickerButton(
                  context,
                  title: 'Seleziona utenti dalla lega',
                  enabled: _canEditPolicyFully,
                  onPick: (uid) => setState(() {
                    if (!_uids.contains(uid)) _uids.add(uid);
                  }),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _emailCtrl,
                        enabled: _canEditPolicyFully,
                        decoration: const InputDecoration(
                          labelText: 'Aggiungi email (override)',
                          hintText: 'es. consulente@studio.it',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: !_canEditPolicyFully
                          ? null
                          : () {
                        final e = _emailCtrl.text.trim().toLowerCase();
                        if (e.isEmpty) return;
                        setState(() {
                          if (!_emails.contains(e)) _emails.add(e);
                          _emailCtrl.clear();
                        });
                      },
                      child: const Text('Aggiungi'),
                    )
                  ],
                ),
                Wrap(
                  spacing: 6,
                  children: _emails
                      .map((e) => Chip(
                    label: Text(e),
                    onDeleted: _canEditPolicyFully
                        ? () => setState(() => _emails.remove(e))
                        : null,
                  ))
                      .toList(),
                ),

                const SizedBox(height: 14),
                const Divider(),
                const Text('Modificabilità (edit)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButton<HrEditScope>(
                  value: _editScope,
                  onChanged: _canEditPolicyFully
                      ? (v) => setState(() => _editScope = v ?? HrEditScope.none)
                      : null,
                  items: const [
                    DropdownMenuItem(value: HrEditScope.none, child: Text('Nessuno')),
                    DropdownMenuItem(value: HrEditScope.self, child: Text('Solo utente')),
                    DropdownMenuItem(value: HrEditScope.restricted, child: Text('Ristretto (ruoli/comparti/filiali/override)')),
                  ],
                ),
                if (_editScope == HrEditScope.restricted) ...[
                  const SizedBox(height: 10),
                  const Text('Aree per edit (vuoto = eredita aree visibilita)', style: TextStyle(fontWeight: FontWeight.bold)),
                  _AreasPicker(
                    leagueId: widget.leagueId,
                    selected: _editAreas,
                    enabled: _canEditPolicyFully,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 10),

                  const Text('Filiali per edit (vuoto = eredita filiali visibilità)', style: TextStyle(fontWeight: FontWeight.bold)),
                  _BranchesPicker(
                    leagueId: widget.leagueId,
                    selected: _editBranches,
                    enabled: _canEditPolicyFully,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  _chipsEditor(
                    label: 'Comparti edit',
                    values: _editComparti,
                    enabled: _canEditPolicyFully,
                    hint: 'es. HR',
                  ),
                  const SizedBox(height: 10),
                  _chipsEditor(
                    label: 'Ruoli edit',
                    values: _editRoles,
                    enabled: _canEditPolicyFully,
                    hint: 'es. HR, ADMIN',
                  ),
                  const SizedBox(height: 10),
                  _chipsEditor(
                    label: 'UID edit (override)',
                    values: _editUids,
                    enabled: _canEditPolicyFully,
                    hint: 'UID autorizzati a modificare',
                  ),
                  const SizedBox(height: 6),
                  _memberPickerButton(
                    context,
                    title: 'Seleziona utenti edit dalla lega',
                    enabled: _canEditPolicyFully,
                    onPick: (uid) => setState(() {
                      if (!_editUids.contains(uid)) _editUids.add(uid);
                    }),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _uidCtrl,
                          enabled: _canEditPolicyFully,
                          decoration: const InputDecoration(
                            labelText: 'Aggiungi email edit (override)',
                            hintText: 'es. hr@azienda.it',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: !_canEditPolicyFully
                            ? null
                            : () {
                          final e = _uidCtrl.text.trim().toLowerCase();
                          if (e.isEmpty) return;
                          setState(() {
                            if (!_editEmails.contains(e)) _editEmails.add(e);
                            _uidCtrl.clear();
                          });
                        },
                        child: const Text('Aggiungi'),
                      )
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    children: _editEmails
                        .map((e) => Chip(
                      label: Text(e),
                      onDeleted: _canEditPolicyFully
                          ? () => setState(() => _editEmails.remove(e))
                          : null,
                    ))
                        .toList(),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _build()),
          child: const Text('Salva'),
        ),
      ],
    );
  }

  Widget _radioVis({
    required String title,
    required HrVisibilityScope value,
    required bool enabled,
  }) {
    return RadioListTile<HrVisibilityScope>(
      title: Text(title),
      value: value,
      groupValue: _vis,
      onChanged: enabled ? (v) => setState(() => _vis = v!) : null,
    );
  }

  Widget _chipsEditor({
    required String label,
    required List<String> values,
    required bool enabled,
    required String hint,
  }) {
    final ctrl = TextEditingController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          children: values
              .map((v) => Chip(
            label: Text(v),
            onDeleted: enabled ? () => setState(() => values.remove(v)) : null,
          ))
              .toList(),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                enabled: enabled,
                decoration: InputDecoration(labelText: label, hintText: hint),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: !enabled
                  ? null
                  : () {
                final t = ctrl.text.trim();
                if (t.isEmpty) return;
                setState(() {
                  if (!values.contains(t)) values.add(t);
                  ctrl.clear();
                });
              },
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _memberPickerButton(
      BuildContext context, {
        required String title,
        required bool enabled,
        required void Function(String uid) onPick,
      }) {
    return ElevatedButton.icon(
      onPressed: !enabled
          ? null
          : () async {
        final uid = await showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _MemberPickerSheet(leagueId: widget.leagueId),
        );
        if (uid != null) onPick(uid);
      },
      icon: const Icon(Icons.person_add),
      label: Text(title),
    );
  }
}

class _AreasPicker extends StatefulWidget {
  final String leagueId;
  final List<String> selected;
  final bool enabled;
  final VoidCallback onChanged;
  const _AreasPicker({
    required this.leagueId,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_AreasPicker> createState() => _AreasPickerState();
}

class _AreasPickerState extends State<_AreasPicker> {
  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('Leagues')
        .doc(widget.leagueId)
        .collection('areas');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 38, child: Center(child: CircularProgressIndicator()));
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Text('Nessuna area definita. (Owner: crea areas in Leagues/{leagueId}/areas)');
        }

        return Wrap(
          spacing: 8,
          runSpacing: 6,
          children: docs.map((d) {
            final data = d.data();
            final id = d.id;
            final label = (data['name'] ?? id).toString();
            final isSel = widget.selected.contains(id);
            return FilterChip(
              label: Text(label),
              selected: isSel,
              onSelected: !widget.enabled
                  ? null
                  : (v) {
                setState(() {
                  if (v) {
                    if (!widget.selected.contains(id)) widget.selected.add(id);
                  } else {
                    widget.selected.remove(id);
                  }
                });
                widget.onChanged();
              },
            );
          }).toList(),
        );
      },
    );
  }
}

class _BranchesPicker extends StatefulWidget {
  final String leagueId;
  final List<String> selected;
  final bool enabled;
  final VoidCallback onChanged;
  const _BranchesPicker({
    required this.leagueId,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_BranchesPicker> createState() => _BranchesPickerState();
}

class _BranchesPickerState extends State<_BranchesPicker> {
  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('Leagues')
        .doc(widget.leagueId)
        .collection('branches');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 42, child: Center(child: CircularProgressIndicator()));
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Text('Nessuna filiale definita. (Owner: crea branches in Leagues/{leagueId}/branches)');
        }
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: docs.map((d) {
            final code = (d.id).toString();
            final name = (d.data()['name'] ?? '').toString();
            final label = name.isEmpty ? code : '$code - $name';
            final selected = widget.selected.contains(code);
            return FilterChip(
              label: Text(label),
              selected: selected,
              onSelected: !widget.enabled
                  ? null
                  : (v) {
                setState(() {
                  if (v) {
                    if (!widget.selected.contains(code)) widget.selected.add(code);
                  } else {
                    widget.selected.remove(code);
                  }
                  widget.onChanged();
                });
              },
            );
          }).toList(),
        );
      },
    );
  }
}

class _MemberPickerSheet extends StatefulWidget {
  final String leagueId;
  const _MemberPickerSheet({required this.leagueId});

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('Leagues')
        .doc(widget.leagueId)
        .collection('members');

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cerca membro (nome/cognome/email/uid)',
              ),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ref.limit(300).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;

                final filtered = docs.where((d) {
                  if (_q.isEmpty) return true;
                  final data = d.data();
                  final s = '${d.id} ${(data['nome'] ?? '')} ${(data['cognome'] ?? '')} ${(data['email'] ?? '')} ${(data['displayNome'] ?? '')} ${(data['displayCognome'] ?? '')}'
                      .toLowerCase();
                  return s.contains(_q);
                }).toList();

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final d = filtered[i];
                    final data = d.data();
                    final title = '${(data['displayNome'] ?? data['nome'] ?? '')} ${(data['displayCognome'] ?? data['cognome'] ?? '')}'.trim();
                    final subtitle = (data['email'] ?? d.id).toString();
                    return ListTile(
                      title: Text(title.isEmpty ? d.id : title),
                      subtitle: Text(subtitle),
                      onTap: () => Navigator.pop(context, d.id),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
    );
  }
}
