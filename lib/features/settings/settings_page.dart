import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dms_app/core/service/auth/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';



class SettingsPage extends StatelessWidget {
  final String leagueId;
  const SettingsPage({super.key, required this.leagueId});

  Future<void> _leaveLeagueOnly() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    await FirebaseFirestore.instance.collection('Users').doc(u.uid).set(
      {
        'activeLeagueId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    // RootGate intercetta activeLeagueId null e ti porta alla scelta lega
  }

  Future<void> _logout() async {
    await AuthService().logout(clearActiveLeague: true);

    // opzionale: se vuoi chiudere eventuali pagine aperte
    // RootGate comunque ti porta ad AuthPage automaticamente.
    // if (!context.mounted) return;
    // Navigator.of(context).popUntil((route) => route.isFirst);
  }




  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Impostazioni',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),

        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('Leagues').doc(leagueId).snapshots(),
          builder: (context, snap) {
            final nome = snap.data?.data()?['nome']?.toString().trim();
            final leagueName = (nome == null || nome.isEmpty) ? 'League' : nome;

            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LEAGUE', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      leagueName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await _leaveLeagueOnly();
                              if (!context.mounted) return;
                              Navigator.of(context).popUntil((route) => route.isFirst);
                            },
                            icon: const Icon(Icons.swap_horiz),
                            label: const Text('CAMBIA LEAGUE'),
                          ),

                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await _leaveLeagueOnly();
                              if (!context.mounted) return;
                              Navigator.of(context).popUntil((route) => route.isFirst);
                            },

                            icon: const Icon(Icons.logout),
                            label: const Text('ESCI DALLA LEAGUE'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ACCOUNT', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(u?.email ?? 'Email non disponibile'),
                  subtitle: Text('UID: ${u?.uid ?? '-'}'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('LOGOUT'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
