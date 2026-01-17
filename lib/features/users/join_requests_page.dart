import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/service/league/dms_league_api.dart';

class JoinRequestsPage extends StatelessWidget {
  final String leagueId;
  const JoinRequestsPage({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance
        .collection('Leagues')
        .doc(leagueId)
        .collection('joinRequests')
        .where('status', isEqualTo: 'pending');

    return Scaffold(
      appBar: AppBar(title: const Text('Richieste di accesso')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Permessi mancanti o errore.'));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Nessuna richiesta in sospeso.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final d = docs[i];
              final data = d.data();
              final emailLower = (data['emailLower'] ?? '').toString();
              final uid = (data['uid'] ?? '').toString();

              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  title: Text(emailLower.isNotEmpty ? emailLower : uid),
                  subtitle: Text('uid: $uid'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Rifiuta',
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () async {
                          await DmsLeagueApi().respondToJoinRequest(
                            leagueId: leagueId,
                            requestId: d.id,
                            accept: false,
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Accetta',
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () async {
                          await DmsLeagueApi().respondToJoinRequest(
                            leagueId: leagueId,
                            requestId: d.id,
                            accept: true,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
