import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dms_app/features/access/league_picker_page.dart';
import 'package:dms_app/core/service/session/active_league_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';


import '../../shell/home_shell.dart';
import '../../features/access/auth_page.dart';


import 'deep_link_service.dart';
import '../service/notification/push_tokens_service.dart';

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  String? _initUid;
  Future<void>? _initFuture;

  final _session = ActiveLeagueService();
  final _deepLinks = DeepLinkService();
  final _pushTokens = PushTokensService();

  bool _handlersReady = false;

  /// ✅ init sessione:
  /// - crea Users/{uid} se manca
  /// - NON azzera activeLeagueId
  /// - valida activeLeagueId
  /// - se c’è un pendingLeagueId (da link/push), prova ad entrarci
  Future<void> _initSessionOncePerLogin() async {
    await _session.ensureUserDocForCurrentUser();
    await _pushTokens.ensurePermissionsAndSaveToken();
    await _session.ensureActiveLeagueIsValid();

    // Se ho pending league (link/push) lo consumo e provo ad entrarci subito
    final pending = await _deepLinks.consumePendingLeagueId();
    if (pending != null && pending.trim().isNotEmpty) {
      await _session.setActiveLeagueIfMember(pending.trim());
    }
  }

  @override
  void initState() {
    super.initState();
    _setupEntryHandlersOnce();
  }

  Future<void> _setupEntryHandlersOnce() async {
    if (_handlersReady) return;
    _handlersReady = true;

    // 1) WEB: se apro /l/<leagueId> lo leggo da Uri.base
    if (kIsWeb) {
      final id = _deepLinks.extractLeagueIdFromUri(Uri.base);
      if (id != null) {
        await _deepLinks.setPendingLeagueId(id);
      }
    }

    // 2) MOBILE: app links / universal links
    await _deepLinks.startListening((leagueId) async {
      await _handleIncomingLeagueId(leagueId);
    });

    // 3) PUSH TAP: app chiusa (initial message)
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        final id = _leagueIdFromMessage(initial);
        if (id != null) await _handleIncomingLeagueId(id);
      }
    } catch (_) {
      // ignore
    }

    // 4) PUSH TAP: app in background
    FirebaseMessaging.onMessageOpenedApp.listen((msg) async {
      final id = _leagueIdFromMessage(msg);
      if (id != null) await _handleIncomingLeagueId(id);
    });

    // 5) PUSH in FOREGROUND: mostra snack con bottone ACCEDI
    FirebaseMessaging.onMessage.listen((msg) async {
      final id = _leagueIdFromMessage(msg);
      final action = (msg.data['action'] ?? '').toString();

      if (!mounted) return;

      if (action == 'join_approved' && id != null && id.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Richiesta approvata!'),
            action: SnackBarAction(
              label: 'ACCEDI',
              onPressed: () => _handleIncomingLeagueId(id),
            ),
          ),
        );
      }
    });



  }

  String? _leagueIdFromMessage(RemoteMessage msg) {
    final data = msg.data;
    final leagueId = (data['leagueId'] ?? '').toString().trim();
    if (leagueId.isNotEmpty) return leagueId;

    // fallback: se arriva un link completo
    final link = (data['link'] ?? '').toString().trim();
    if (link.isNotEmpty) {
      final uri = Uri.tryParse(link);
      if (uri != null) {
        return _deepLinks.extractLeagueIdFromUri(uri);
      }
    }
    return null;
  }

  Future<void> _handleIncomingLeagueId(String leagueId) async {
    final id = leagueId.trim();
    if (id.isEmpty) return;

    // salvo sempre pending: se non è loggato, lo userò dopo login
    await _deepLinks.setPendingLeagueId(id);

    // se già loggato, provo a entrare subito
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _session.setActiveLeagueIfMember(id);
      // non serve setState: la UI cambia via stream su Users/{uid}
    }
  }

  @override
  void dispose() {
    _deepLinks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _SplashLoading();
        }

        final user = authSnap.data;

        // logout -> reset init cache (NON cancello pending link)
        if (user == null) {
          _initUid = null;
          _initFuture = null;
          return const AuthPage();
        }

        final userRef = FirebaseFirestore.instance.collection('Users').doc(user.uid);

        // init UNA volta per login
        if (_initUid != user.uid) {
          _initUid = user.uid;
          _initFuture = _initSessionOncePerLogin();
        }

        return FutureBuilder<void>(
          future: _initFuture,
          builder: (context, initSnap) {
            if (initSnap.connectionState == ConnectionState.waiting) {
              return const _SplashLoading();
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: userRef.snapshots(),
              builder: (context, userSnap) {
                if (userSnap.hasError) {
                  return const Scaffold(
                    body: Center(child: Text('Errore nel caricamento utente')),
                  );
                }
                if (!userSnap.hasData) {
                  return const _SplashLoading();
                }

                final data = userSnap.data!.data() ?? {};
                final raw = data['activeLeagueId'];
                final activeLeagueId = (raw is String) ? raw.trim() : '';

                if (activeLeagueId.isEmpty) {
                  return const LeaguePickerPage();

                }


                return HomeShell(
                  key: ValueKey(activeLeagueId),
                  leagueId: activeLeagueId,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SplashLoading extends StatelessWidget {
  const _SplashLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
