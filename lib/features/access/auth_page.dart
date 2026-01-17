import 'package:dms_app/core/service/auth/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _authService = AuthService();

  bool _isLogin = true;
  bool _loading = false;

  // ✅ Ricorda email (solo email/password o quando premi USA)
  bool _rememberEmail = false;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();

  final FocusNode _passwordFocus = FocusNode();

  // Ultimo accesso (sempre salvato)
  String _lastProvider = '';
  String _lastEmail = '';

  // Apple placeholders (se non lo usi ora, lascia pure)
  static const String _appleServiceId = 'com.TUO.SERVICE.ID';
  static final Uri _appleRedirectUri = Uri.parse('https://TUO_DOMINIO/__/auth/handler');

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    final savedRemembered = prefs.getString('remembered_email') ?? '';
    final lastProv = prefs.getString('last_login_provider') ?? '';
    final lastMail = prefs.getString('last_login_email') ?? '';

    if (!mounted) return;

    setState(() {
      _lastProvider = lastProv.trim();
      _lastEmail = lastMail.trim();

      if (savedRemembered.trim().isNotEmpty) {
        _rememberEmail = true;
        _email.text = savedRemembered.trim();
      } else {
        _rememberEmail = false;
      }
    });
  }

  Future<void> _persistRememberedEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final e = email.trim();

    if (_rememberEmail && e.isNotEmpty) {
      await prefs.setString('remembered_email', e);
    } else {
      await prefs.remove('remembered_email');
    }
  }

  Future<void> _persistLastAccess({required String provider, required String email}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_login_provider', provider.trim());
    await prefs.setString('last_login_email', email.trim());

    if (!mounted) return;
    setState(() {
      _lastProvider = provider.trim();
      _lastEmail = email.trim();
    });
  }

  String _extractBestEmail(User? u) {
    final direct = (u?.email ?? '').trim();
    if (direct.isNotEmpty) return direct;

    final data = u?.providerData ?? const [];
    for (final p in data) {
      final e = (p.email ?? '').trim();
      if (e.isNotEmpty) return e;
    }
    return '';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _password2.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Email non valida.';
      case 'user-not-found':
        return 'Utente non trovato.';
      case 'wrong-password':
        return 'Password errata.';
      case 'email-already-in-use':
        return 'Email già registrata.';
      case 'weak-password':
        return 'Password troppo debole (min 6 caratteri).';
      case 'operation-not-allowed':
        return 'Metodo non abilitato su Firebase.';
      case 'too-many-requests':
        return 'Troppi tentativi. Riprova più tardi.';
      default:
        return e.message ?? 'Errore di autenticazione.';
    }
  }

  Future<void> _submitEmail() async {
    final email = _email.text.trim();
    final pass = _password.text;

    if (email.isEmpty || pass.isEmpty) {
      _toast('Inserisci email e password.');
      return;
    }

    if (!_isLogin) {
      final pass2 = _password2.text;
      if (pass2.isEmpty) return _toast('Conferma la password.');
      if (pass != pass2) return _toast('Le password non coincidono.');
    }

    setState(() => _loading = true);
    try {
      if (_isLogin) {
        await _authService.signInWithEmail(email, pass);
      } else {
        await _authService.signUpWithEmail(email, pass);
      }

      await _persistLastAccess(provider: 'Email', email: email);
      await _persistRememberedEmail(email);
    } on FirebaseAuthException catch (e) {
      _toast(_friendlyAuthError(e));
    } catch (e) {
      _toast('Errore: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _social({
    required String providerLabel,
    required Future<UserCredential?> Function() action,
  }) async {
    setState(() => _loading = true);
    try {
      final cred = await action();
      if (cred == null) return; // annullato

      final socialEmail = _extractBestEmail(cred.user);

      await _persistLastAccess(provider: providerLabel, email: socialEmail);

      if (_rememberEmail && socialEmail.isNotEmpty) {
        _email.text = socialEmail;
        await _persistRememberedEmail(socialEmail);
      }
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      _toast('Login Google fallito.');
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return;
      _toast('Login Apple fallito.');
    } on FirebaseAuthException catch (e) {
      _toast(_friendlyAuthError(e));
    } catch (e) {
      _toast('Errore: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// ✅ Fix punto spinoso: password reset completo (web redirect incluso)
  Future<void> _forgotPassword() async {
    String email = _email.text.trim();

    if (email.isEmpty) {
      final controller = TextEditingController();
      final res = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recupero password'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Inserisci la tua email'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Invia'),
            ),
          ],
        ),
      );

      if (res == null || res.trim().isEmpty) return;
      email = res.trim();
    }

    setState(() => _loading = true);
    try {
      // ✅ su Web: redirect dopo reset al dominio corrente (Hosting)
      final continueUrl = kIsWeb ? Uri.base.origin : null;

      await _authService.sendPasswordReset(
        email,
        continueUrl: continueUrl,
      );

      _toast('Email di reimpostazione inviata a $email');
    } on FirebaseAuthException catch (e) {
      _toast(_friendlyAuthError(e));
    } catch (e) {
      _toast('Errore: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _useLastAccessEmail() async {
    final e = _lastEmail.trim();
    if (e.isEmpty) {
      _toast('Nessuna email salvata per l’ultimo accesso.');
      return;
    }

    setState(() => _email.text = e);

    await _persistRememberedEmail(e);

    FocusScope.of(context).requestFocus(_passwordFocus);
  }

  @override
  Widget build(BuildContext context) {
    final showApple = kIsWeb || Theme.of(context).platform == TargetPlatform.iOS;
    final w = MediaQuery.of(context).size.width;
    final maxW = w > 520 ? 520.0 : w;

    return Scaffold(
      resizeToAvoidBottomInset: true, // ✅ Fix overflow keyboard
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: bottomInset),
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxW),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 16),
                          const Text(
                            'DMS',
                            style: TextStyle(fontSize: 42, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 24),

                          // Segmented
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: const [
                                BoxShadow(
                                  blurRadius: 12,
                                  offset: Offset(0, 6),
                                  color: Color(0x14000000),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _segBtn(
                                    label: 'Accedi',
                                    active: _isLogin,
                                    onTap: () => setState(() => _isLogin = true),
                                  ),
                                ),
                                Expanded(
                                  child: _segBtn(
                                    label: 'Crea account',
                                    active: !_isLogin,
                                    onTap: () => setState(() => _isLogin = false),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 18),

                          // Ultimo accesso
                          if (_lastProvider.trim().isNotEmpty || _lastEmail.trim().isNotEmpty) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Ultimo accesso: ${_lastProvider.trim().isEmpty ? '-' : _lastProvider}',
                                        style: const TextStyle(color: Colors.grey),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _lastEmail.trim().isEmpty ? '-' : _lastEmail,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  onPressed: _loading ? null : _useLastAccessEmail,
                                  child: const Text('USA'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                          ],

                          _field(
                            label: 'Email',
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => FocusScope.of(context).requestFocus(_passwordFocus),
                          ),
                          const SizedBox(height: 14),

                          _field(
                            label: 'Password',
                            controller: _password,
                            obscure: true,
                            focusNode: _passwordFocus,
                            textInputAction: _isLogin ? TextInputAction.done : TextInputAction.next,
                            onSubmitted: (_) {
                              if (_isLogin && !_loading) _submitEmail();
                            },
                          ),

                          if (!_isLogin) ...[
                            const SizedBox(height: 14),
                            _field(
                              label: 'Conferma Password',
                              controller: _password2,
                              obscure: true,
                              textInputAction: TextInputAction.done,
                            ),
                          ],

                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberEmail,
                                onChanged: _loading
                                    ? null
                                    : (v) async {
                                  setState(() => _rememberEmail = v ?? false);
                                  await _persistRememberedEmail(_email.text.trim());
                                },
                              ),
                              const Expanded(
                                child: Text('Ricorda email', overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submitEmail,
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                                  : Text(_isLogin ? 'ACCEDI' : 'CREA ACCOUNT'),
                            ),
                          ),

                          const SizedBox(height: 12),

                          if (_isLogin) ...[
                            Align(
                              alignment: Alignment.center,
                              child: TextButton(
                                onPressed: _loading ? null : _forgotPassword,
                                child: const Text('Password dimenticata?'),
                              ),
                            ),
                          ],

                          const SizedBox(height: 18),

                          const Text(
                            "oppure ACCEDI con:",
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _socialIcon(
                                icon: FontAwesomeIcons.google,
                                color: Colors.red,
                                onPressed: _loading
                                    ? null
                                    : () => _social(
                                  providerLabel: 'Google',
                                  action: () => _authService.signInWithGoogle(),
                                ),
                              ),


                            // PER ABILITARE FACEBOOK TOGLI IL COMMENTO qui e in AUTH SERVICE e inserisci: flutter_facebook_auth: ^7.1.2 nel PUBSPEK.YAML
/*
                              _socialIcon(
                                icon: FontAwesomeIcons.facebook,
                                color: Colors.blue,
                                onPressed: _loading
                                    ? null
                                    : () => _social(
                                  providerLabel: 'Facebook',
                                  action: () async => _authService.signInWithFacebook(),
                                ),
                              ),


*/

                              _socialIcon(
                                icon: FontAwesomeIcons.facebook,
                                color: Colors.blue,
                                onPressed: _loading ? null : () => _toast('Facebook non ancora disponibile.'),
                              ),


                              if (showApple)
                                _socialIcon(
                                  icon: FontAwesomeIcons.apple,
                                  color: Colors.black,
                                  onPressed: _loading
                                      ? null
                                      : () => _social(
                                    providerLabel: 'Apple',
                                    action: () async => _authService.signInWithApple(
                                      webClientId: _appleServiceId,
                                      webRedirectUri: _appleRedirectUri,
                                    ),
                                  ),
                                ),
                              _socialIcon(
                                icon: FontAwesomeIcons.instagram,
                                color: Colors.pink,
                                onPressed: _loading ? null : () => _toast('Instagram non ancora disponibile.'),
                              ),
                              _socialIcon(
                                icon: FontAwesomeIcons.twitter,
                                color: Colors.blue,
                                onPressed: _loading ? null : () => _toast('Twitter non ancora disponibile.'),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _socialIcon({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: FaIcon(icon, color: color, size: 22),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      splashRadius: 22,
      tooltip: 'Accedi',
    );
  }

  Widget _segBtn({required String label, required bool active, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE9E6EF) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    bool obscure = false,
    TextInputType? keyboardType,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      focusNode: focusNode,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.black.withOpacity(0.25)),
        ),
      ),
    );
  }
}
