// lib/features/users/widgets/user_profile_header_sliver.dart
// Header profilo DMS con avatar animato (centrale → AppBar, senza sovrapposizioni)

import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class UserProfileHeaderSliver extends StatelessWidget {
  final String displayName;
  final String? photoUrl;
  final String? coverUrl;

  final bool canEdit;

  final VoidCallback onOpenAvatar;
  final VoidCallback onEditAvatar;
  final VoidCallback onEditCover;

  const UserProfileHeaderSliver({
    super.key,
    required this.displayName,
    required this.photoUrl,
    required this.coverUrl,
    required this.canEdit,
    required this.onOpenAvatar,
    required this.onEditAvatar,
    required this.onEditCover,
  });

  static const double _expandedHeight = 300;   // ingrandisce la cover
  static const double _avatarMax = 128;
  static const double _avatarMin = 40;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: _expandedHeight,
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      leading: const BackButton(),
      actions: [
        if (canEdit)
          IconButton(
            tooltip: 'Cambia cover',
            icon: const Icon(Icons.photo),
            onPressed: onEditCover,
          ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final maxH = constraints.maxHeight;
          final minH = kToolbarHeight + topPadding;

          final t =
          ((maxH - minH) / (_expandedHeight - minH)).clamp(0.0, 1.0);

          // Avatar
          final avatarSize = lerpDouble(_avatarMin, _avatarMax, t)!;

          // POSIZIONE AVATAR
          final avatarLeftExpanded =
              (MediaQuery.of(context).size.width - avatarSize) / 2;

          final avatarLeftCollapsed = 56.0; // 👉 a destra della back button

          final avatarLeft =
          lerpDouble(avatarLeftCollapsed, avatarLeftExpanded, t)!;

          final avatarBottom = lerpDouble(10, 8, t)!;




          return Stack(
            fit: StackFit.expand,
            children: [
              // COVER
              coverUrl == null || coverUrl!.isEmpty
                  ? Container(color: Colors.grey.shade800)
                  : CachedNetworkImage(
                imageUrl: coverUrl!,
                fit: BoxFit.cover,
              ),

              // overlay
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black54, Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),




            ],
          );
        },
      ),
    );
  }
}


class ProfileIdentityBlock extends StatelessWidget {
  final String displayName;
  final String? nickname;
  final String? email;

  const ProfileIdentityBlock({
    super.key,
    required this.displayName,
    this.nickname,
    this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 88, 16, 16), // spazio per avatar sopra
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Text(
            displayName,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          if (nickname != null && nickname!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(nickname!,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          if (email != null && email!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                email!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}



class UserFloatingIdentity extends StatelessWidget {
  final ScrollController controller;
  final String displayName;
  final String? photoUrl;

  const UserFloatingIdentity({
    super.key,
    required this.controller,
    required this.displayName,
    this.photoUrl,
  });

  static const double expandedAvatar = 120;
  static const double collapsedAvatar = 36;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final offset = controller.hasClients ? controller.offset : 0;
        final t = (offset / 220).clamp(0.0, 1.0);

        final avatarSize =
        lerpDouble(expandedAvatar, collapsedAvatar, t)!;

        final left =
        lerpDouble(
          (MediaQuery.of(context).size.width - avatarSize) / 2,
          56,
          t,
        )!;

        final topPos =
        lerpDouble(
          280,
          top + (kToolbarHeight - avatarSize) / 2,
          t,
        )!;

        return Positioned(
          top: topPos,
          left: left,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: avatarSize / 2,
                backgroundImage:
                photoUrl != null ? CachedNetworkImageProvider(photoUrl!) : null,
                child: photoUrl == null ? const Icon(Icons.person) : null,
              ),
              if (t > 0.9) ...[
                const SizedBox(width: 12),
                Text(
                  displayName,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}




