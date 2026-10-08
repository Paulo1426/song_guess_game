import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_guess_game/main.dart';
import 'package:song_guess_game/screens/home_screen.dart';

void main() {
  testWidgets('muestra la pantalla inicial', (tester) async {
    await tester.pumpWidget(
      SongGuessApp(
        home: HomeScreen(authStateChanges: Stream<User?>.value(null)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Adivina la canción'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Jugar sin registrarme'), findsOneWidget);
  });

  testWidgets('informa que Firebase no esta configurado para Web', (
    tester,
  ) async {
    await tester.pumpWidget(const SongGuessApp(firebaseSupported: false));

    expect(
      find.text('Firebase solo está configurado para Android e iOS.'),
      findsOneWidget,
    );
  });
}
