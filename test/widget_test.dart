import 'package:flutter_test/flutter_test.dart';
import 'package:song_guess_game/main.dart';

void main() {
  testWidgets('muestra la pantalla inicial', (tester) async {
    await tester.pumpWidget(const SongGuessApp());
    expect(find.text('Adivina la canción'), findsOneWidget);
  });
}
