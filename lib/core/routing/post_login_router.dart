/*


import 'package:dms_app/access/league_picker_page.dart';
import 'package:dms_app/access/service/push_tokens_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';


import 'service/deep_link_service.dart';

class PostLoginRouter extends StatefulWidget {
  final Widget Function(String leagueId) leagueHomeBuilder;

  const PostLoginRouter({super.key, required this.leagueHomeBuilder});

  @override
  State<PostLoginRouter> createState() => _PostLoginRouterState();
}

class _PostLoginRouterState extends State<PostLoginRouter> {
  final _deepLinks = DeepLinkService();
  final _pushTokens = PushTokensService();

  String? _forceLeagueId;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _pushTokens.ensurePermissionsAndSaveToken();

    // se l’app è stata aperta con /l/<leagueId>, entra diretto
    await _deepLinks.startListening((leagueId) async {
      await _deepLinks.setPendingLeagueId(leagueId);
      if (mounted) setState(() => _forceLeagueId = leagueId);
    });

    // pending da cold start precedente
    final pending = await _deepLinks.consumePendingLeagueId();
    if (pending != null && mounted) setState(() => _forceLeagueId = pending);
  }

  @override
  void dispose() {
    _deepLinks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data as User?;
        if (user == null) {
          // QUI metti la tua login page
          return const Scaffold(body: Center(child: Text('LOGIN PAGE QUI')));
        }

        if (_forceLeagueId != null) {
          return widget.leagueHomeBuilder(_forceLeagueId!);
        }

        return const LeaguePickerPage();

      },
    );
  }
}


*/

