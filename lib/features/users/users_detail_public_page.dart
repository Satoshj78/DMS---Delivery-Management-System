// lib/features/users/users_detail_public_page.dart
// Pagina profilo PUBBLICO (sola lettura)
// - legge SOLO da /UsersPublic/{uid}
// - stessa UI della UserDetailPage (cover + avatar animati)
// - nessuna dipendenza da lega o members

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dms_app/features/users/widgets/user_profile_header_sliver.dart';
import 'package:flutter/material.dart';

class UsersDetailPublicPage extends StatelessWidget {
  final String userId;

  const UsersDetailPublicPage({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final userPublicRef =
    FirebaseFirestore.instance.collection('UsersPublic').doc(userId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userPublicRef.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data!.data() ?? {};

        final displayName =
        (data['displayName'] ?? '').toString().trim();
        final photoUrl =
        (data['photoUrl'] ?? '').toString().trim();
        final coverUrl =
        (data['coverUrl'] ?? '').toString().trim();

        return Scaffold(
          body: Stack(
            children: [
              NestedScrollView(
                headerSliverBuilder: (_, __) => [
                  UserProfileHeaderSliver(
                    displayName:
                    displayName.isNotEmpty ? displayName : userId,
                    photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
                    coverUrl: coverUrl.isNotEmpty ? coverUrl : null,
                    canEdit: false, // 🔒 PUBBLICO
                    onOpenAvatar: () {},
                    onEditAvatar: () {},
                    onEditCover: () {},
                  ),
                ],
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Profilo pubblico',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),

                    if (data['email'] != null)
                      ListTile(
                        leading: const Icon(Icons.email_outlined),
                        title: Text(data['email']),
                      ),

                    if (data['nickname'] != null)
                      ListTile(
                        leading: const Icon(Icons.alternate_email),
                        title: Text(data['nickname']),
                      ),

                    if (data['pensiero'] != null)
                      ListTile(
                        leading: const Icon(Icons.format_quote),
                        title: Text(data['pensiero']),
                      ),
                  ],
                ),
              ),

              // ✅ RIUSA ANCHE L’IDENTITÀ FLOTTANTE
              UserFloatingIdentity(
                controller: ScrollController(),
                displayName:
                displayName.isNotEmpty ? displayName : userId,
                photoUrl: photoUrl.isNotEmpty ? photoUrl : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
