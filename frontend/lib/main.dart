import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_client.dart';
import 'auth/auth_gate.dart';
import 'auth/auth_session.dart';
import 'config.dart';
import 'locations_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AuthSession? session;
  String? configError;
  if (AppConfig.authEnabled) {
    if (!isPublicSupabaseKey(AppConfig.supabaseAnonKey)) {
      configError =
          'This build has a server-only Supabase key. Rebuild it with the '
          'public publishable/anon key.';
    } else {
      try {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          publishableKey: AppConfig.supabaseAnonKey,
        );
        session = AuthSession(
          SupabaseAuthClient(
            Supabase.instance.client.auth,
            emailRedirectTo: kIsWeb ? Uri.base.origin : null,
          ),
        );
        AuthSession.current = session;
      } catch (_) {
        configError = 'Sign-in could not start. Please reload the app.';
      }
    }
  }
  runApp(LagawApp(session: session, configError: configError));
}

/// Refuses service-role/secret keys so they can never back the app's
/// Supabase client, even if misconfigured. [S3-16]
bool isPublicSupabaseKey(String key) {
  if (key.startsWith('sb_secret_')) return false;
  if (key.startsWith('sb_publishable_')) return true;
  final parts = key.split('.');
  if (parts.length != 3) return false;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final role = (jsonDecode(payload) as Map<String, dynamic>)['role'];
    return role == 'anon';
  } catch (_) {
    return false;
  }
}

class LagawApp extends StatefulWidget {
  /// Null in local demo builds without Supabase configuration.
  final AuthSession? session;
  final String? configError;

  const LagawApp({super.key, this.session, this.configError});

  @override
  State<LagawApp> createState() => _LagawAppState();
}

class _LagawAppState extends State<LagawApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final error = widget.configError;
    return MaterialApp(
      title: 'Lagaw Bacolod',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorKey: _navigatorKey,
      builder: session == null
          ? null
          : (context, child) => SessionExpiredBanner(
              session: session,
              navigatorKey: _navigatorKey,
              child: child!,
            ),
      home: error != null
          ? Scaffold(body: Center(child: Text(error)))
          : session == null
          ? const LocationsScreen()
          : AuthGate(session: session, signedIn: () => const LocationsScreen()),
    );
  }
}
