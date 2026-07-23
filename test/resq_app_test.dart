import 'package:flutter_test/flutter_test.dart';
import 'package:resq/main.dart';

void main() {
  testWidgets('shows the offline home dashboard', (tester) async {
    await tester.pumpWidget(const ResQApp(loadDocuments: false));

    expect(find.text('resQ'), findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Ask resQ'), findsOneWidget);
  });
}
