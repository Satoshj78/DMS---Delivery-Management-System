import 'package:dms_app/core/service/user/user_service.dart';
import 'package:flutter/material.dart';


class JoinWithInvitePage extends StatefulWidget {
  final String leagueId;
  const JoinWithInvitePage({super.key, required this.leagueId});

  @override
  State<JoinWithInvitePage> createState() => _JoinWithInvitePageState();
}

class _JoinWithInvitePageState extends State<JoinWithInvitePage> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      _toast('Inserisci il codice invito.');
      return;
    }

    setState(() => _loading = true);
    try {
      final joinedLeagueId = await UserService.acceptInviteCode(code: code);

      if (!mounted) return;
      _toast('Invito accettato! Benvenuto nella lega.');
      Navigator.pop(context, joinedLeagueId); // oppure true
    } catch (e) {
      _toast('Errore: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entra con invito')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Inserisci il codice ricevuto da un manager.\n'
                  'Dopo l’accesso verrai aggiunto automaticamente alla lega.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Codice invito',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _accept,
                icon: _loading
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.check),
                label: Text(_loading ? 'Verifica...' : 'ACCETTA INVITO'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
