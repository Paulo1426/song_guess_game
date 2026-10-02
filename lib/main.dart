import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty) {
    await SupabaseService.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
    );
  }
  runApp(const ProviderScope(child: SongGuessApp()));
}

class SongGuessApp extends StatelessWidget {
  const SongGuessApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Adivina la Canción',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const HomeScreen(),
      );
}