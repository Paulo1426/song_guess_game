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
  });
}
