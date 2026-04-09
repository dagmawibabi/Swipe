import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swipe/main.dart';

void main() {
  testWidgets('feed refresh, horizontal switching, and search timeline work', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = SwipeController(preferences);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: SwipeShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('0'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('For You'), findsOneWidget);

    final beforeRefreshColor = tester
        .widget<ColoredBox>(find.byKey(const ValueKey('for-you-page-0')))
        .color;

    await tester.fling(
      find.byKey(const ValueKey('for-you-timeline')),
      const Offset(0, 320),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    final afterRefreshColor = tester
        .widget<ColoredBox>(find.byKey(const ValueKey('for-you-page-0')))
        .color;

    expect(afterRefreshColor, isNot(equals(beforeRefreshColor)));
    expect(controller.sessionSwipes, 0);

    Text followingLabel = tester.widget(find.text('Following'));
    Text forYouLabel = tester.widget(find.text('For You'));
    expect(followingLabel.style?.color, Colors.white70);
    expect(forYouLabel.style?.color, Colors.black);

    await tester.drag(
      find.byKey(const ValueKey('home-tab-pager')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();

    followingLabel = tester.widget(find.text('Following'));
    forYouLabel = tester.widget(find.text('For You'));
    expect(followingLabel.style?.color, Colors.black);
    expect(forYouLabel.style?.color, Colors.white70);

    await tester.drag(
      find.byKey(const ValueKey('following-timeline')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(controller.sessionSwipes, 1);
    expect(find.text('1'), findsOneWidget);

    final feedCenter = tester.getCenter(
      find.byKey(const ValueKey('following-timeline')),
    );
    for (var index = 0; index < 5; index += 1) {
      await tester.tapAt(feedCenter);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(feedCenter);
      await tester.pump();
    }

    expect(controller.sessionLikes, 5);
    expect(find.text('SUPER LIKE'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    final heartIcon = tester.widget<Icon>(find.byIcon(Icons.favorite));
    expect(heartIcon.color, Colors.red);

    final edgeGesture = await tester.startGesture(const Offset(8, 300));
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Video is playing 2x the speed'), findsOneWidget);

    await edgeGesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(SearchColorTile), findsWidgets);
    expect(find.text('Rose'), findsNothing);

    await tester.enterText(find.byType(TextField), 'rose');
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SearchColorTile>(find.byType(SearchColorTile).first)
          .entry
          .name,
      'Rose',
    );

    await tester.tap(find.byType(SearchColorTile).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('search-timeline')), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('search-timeline')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(controller.sessionSwipes, 2);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Show counter'), findsOneWidget);
    expect(find.text('Show top tabs'), findsOneWidget);
    expect(find.text('Stats'), findsOneWidget);
    expect(find.text('Guide'), findsOneWidget);

    await tester.tap(find.text('Show counter'));
    await tester.pumpAndSettle();

    expect(controller.showCounter, isFalse);

    await tester.tap(find.text('Show top tabs'));
    await tester.pumpAndSettle();

    expect(controller.showFeedTabs, isFalse);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.text('Following'), findsNothing);
    expect(find.text('For You'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();

    expect(find.text('Current session'), findsOneWidget);
    expect(find.text('Across days'), findsOneWidget);
    expect(find.text('Swipes'), findsWidgets);
    expect(find.text('Likes'), findsWidgets);

    final restoredController = SwipeController(preferences);
    addTearDown(restoredController.dispose);
    expect(restoredController.showCounter, isFalse);
    expect(restoredController.showFeedTabs, isFalse);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Guide'));
    await tester.pumpAndSettle();

    expect(find.text('Gestures'), findsOneWidget);
    final featuresFinder = find.text('Features', skipOffstage: false);
    await tester.ensureVisible(featuresFinder);
    await tester.pumpAndSettle();
    expect(find.text('Features'), findsOneWidget);
    final refreshGuideFinder = find.text(
      '- Pull down at the very start to refresh and reshuffle the current timeline.',
      skipOffstage: false,
    );
    await tester.ensureVisible(refreshGuideFinder);
    await tester.pumpAndSettle();
    expect(
      find.text(
        '- Pull down at the very start to refresh and reshuffle the current timeline.',
      ),
      findsOneWidget,
    );
  });
}
