import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) {
    if (url.isEmpty || anonKey.isEmpty) {
      throw ArgumentError('Configura SUPABASE_URL y SUPABASE_ANON_KEY');
    }
    return Supabase.initialize(url: url, publishableKey: anonKey);
  }
}

class AuthService {
  final SupabaseClient _client;

  AuthService([SupabaseClient? client])
      : _client = client ?? SupabaseService.client;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
  User? get currentUser => _client.auth.currentUser;

  Future<AuthResponse> registrar({
    required String email,
    required String password,
    String? nombre,
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: nombre == null ? null : {'nombre': nombre.trim()},
    );
  }

  Future<AuthResponse> iniciarSesion({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> cerrarSesion() => _client.auth.signOut();
}
