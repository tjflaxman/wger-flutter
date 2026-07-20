/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2020 - 2026 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'package:flutter_riverpod/misc.dart' as riverpod;
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wger/core/network/network_provider.dart';
import 'package:wger/core/shared_preferences.dart';
import 'package:wger/core/widgets/error.dart';
import 'package:wger/features/exercises/providers/exercise_repository.dart';
import 'package:wger/features/exercises/providers/exercises_notifier.dart';
import 'package:wger/features/exercises/widgets/exercises.dart';
import 'package:wger/features/routines/models/repetition_unit.dart';
import 'package:wger/features/routines/models/session.dart';
import 'package:wger/features/routines/models/weight_unit.dart';
import 'package:wger/features/routines/providers/gym_state.dart';
import 'package:wger/features/routines/providers/routines_notifier.dart';
import 'package:wger/features/routines/providers/routines_repository.dart';
import 'package:wger/features/routines/providers/workout_logs_repository.dart';
import 'package:wger/features/routines/providers/workout_session_repository.dart';
import 'package:wger/features/routines/screens/gym_mode.dart';
import 'package:wger/features/routines/screens/routine_screen.dart';
import 'package:wger/features/routines/services/rest_timer_notification_service.dart';
import 'package:wger/features/routines/widgets/gym_mode/active_workout_screen.dart';
import 'package:wger/features/routines/widgets/gym_mode/session_page.dart';
import 'package:wger/features/routines/widgets/gym_mode/start_page.dart';
import 'package:wger/features/routines/widgets/gym_mode/summary.dart';
import 'package:wger/features/trophies/providers/trophy_repository.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

import '../../../../test_data/exercises.dart';
import '../../../../test_data/routines.dart';
import '../../../fake_connectivity.dart';
import 'gym_mode_test.mocks.dart';

@GenerateMocks([
  WorkoutSessionRepository,
  ExerciseRepository,
  RoutinesRepository,
  TrophyRepository,
  WorkoutLogRepository,
])
void main() {
  installFakeConnectivity();

  final key = GlobalKey<NavigatorState>();

  final testRoutine = getTestRoutine();
  final testExercises = getTestExercises();

  final mockSessionRepo = MockWorkoutSessionRepository();
  final mockExerciseRepo = MockExerciseRepository();
  final mockRoutinesRepo = MockRoutinesRepository();
  final mockLogRepo = MockWorkoutLogRepository();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    when(mockSessionRepo.watchAllDrift()).thenAnswer(
      (_) => Stream<List<WorkoutSession>>.multi((controller) {
        controller.add(testRoutine.sessions);
      }),
    );
    when(
      mockExerciseRepo.watchAllDrift(),
    ).thenAnswer((_) => Stream.value(ExerciseState(testExercises)));

    // Drift the test routine in via the routines repository, the real
    // [RoutinesRiverpod] picks it up and exposes it through state.
    when(
      mockRoutinesRepo.watchAllDrift(),
    ).thenAnswer((_) => Stream.value([testRoutine]));
    // [fetchAndSetRoutineFull] (called by [GymMode._loadGymState] before the
    // page tree is built) goes back to the server in production; here we
    // just hand back the same test routine.
    when(
      mockRoutinesRepo.fetchAndSetRoutineFullServer(any),
    ).thenAnswer((_) async => testRoutine);

    // Past logs on the log page come from this stream (per exercise). Reuse the
    // test routine's logs so the assertions on previous entries keep working.
    when(
      mockLogRepo.watchLogsByExerciseDrift(
        routineId: anyNamed('routineId'),
        exerciseId: anyNamed('exerciseId'),
      ),
    ).thenAnswer((invocation) {
      final exerciseId = invocation.namedArguments[#exerciseId] as int;
      return Stream.value(testRoutine.filterLogsByExercise(exerciseId));
    });

    // Completing a set in the active-workout screen saves a Log entry.
    when(mockLogRepo.addLocalDrift(any)).thenAnswer((_) async {});
  });

  Widget renderGymMode({
    locale = 'en',
    bool isOnline = true,
    List<riverpod.Override> extraOverrides = const [],
  }) {
    return riverpod.ProviderScope(
      overrides: [
        networkStatusProvider.overrideWithValue(isOnline),
        routinesRepositoryProvider.overrideWithValue(mockRoutinesRepo),
        exerciseRepositoryProvider.overrideWithValue(mockExerciseRepo),
        workoutSessionRepositoryProvider.overrideWithValue(mockSessionRepo),
        workoutLogRepositoryProvider.overrideWithValue(mockLogRepo),
        // No native plugin channels are available under flutter_test; the
        // real service would throw MissingPluginException as soon as gym
        // mode is entered.
        restTimerNotificationServiceProvider.overrideWithValue(
          const NoopRestTimerNotificationService(),
        ),
        ...extraOverrides,
        // The repetition + weight unit catalogues are tiny direct-Drift
        // stream providers, overriding them inline is the established
        // pattern (see also [exerciseCategoriesProvider] etc.).
        routineRepetitionUnitProvider.overrideWith(
          (ref) => Stream<List<RepetitionUnit>>.value(testRepetitionUnits),
        ),
        routineWeightUnitProvider.overrideWith(
          (ref) => Stream<List<WeightUnit>>.value(testWeightUnits),
        ),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: key,
        home: TextButton(
          onPressed: () => key.currentState!.push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(arguments: GymModeArguments(1, 1, 1)),
              builder: (_) => const GymModeScreen(),
            ),
          ),
          child: const SizedBox(),
        ),
        routes: {RoutineScreen.routeName: (ctx) => const RoutineScreen()},
      ),
    );
  }

  testWidgets(
    'Walks through the gym mode flow: start -> active workout -> session -> summary',
    (WidgetTester tester) async {
      await withClock(Clock.fixed(DateTime(2025, 3, 29, 14, 33)), () async {
        await tester.pumpWidget(renderGymMode());
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();

        //
        // Start page
        //
        expect(find.byType(StartPage), findsOneWidget);
        expect(find.text('Your workout today'), findsOneWidget);
        expect(find.text('Bench press'), findsOneWidget);
        expect(find.text('Side raises'), findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);
        expect(find.byIcon(Icons.menu), findsOneWidget);
        expect(find.byIcon(Icons.chevron_left), findsNothing);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();

        //
        // Active workout screen: both exercises show as sections with their
        // full set table already visible (no expand needed to log a set --
        // only the exercise instructions/images are collapsed by default).
        //
        expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
        expect(find.byType(ExerciseSectionWidget), findsNWidgets(2));
        expect(find.text('Bench press'), findsOneWidget);
        expect(find.text('Side raises'), findsOneWidget);
        expect(find.text('0/3 sets'), findsNWidgets(2));
        expect(find.byType(SetRowWidget), findsNWidgets(6), reason: '3 sets x 2 exercises');
        expect(find.byType(Checkbox), findsNWidgets(6));
        // Exercise instructions are collapsed by default.
        expect(find.byType(ExerciseDetail), findsNothing);

        // Expand the "Bench press" section's instructions via its info toggle.
        await tester.tap(find.byIcon(Icons.info_outline).first);
        await tester.pumpAndSettle();
        expect(find.byType(ExerciseDetail), findsOneWidget);

        // Complete the first set: the rest timer for that exercise should
        // start automatically.
        expect(find.textContaining('Rest:'), findsNWidgets(2), reason: 'both exercises idle');
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();
        expect(find.text('0/3 sets'), findsOneWidget, reason: 'one exercise now has a set done');
        expect(find.text('1/3 sets'), findsOneWidget);
        expect(find.textContaining('Rest:'), findsOneWidget, reason: 'the other exercise is idle');

        // Finish the workout.
        await tester.tap(find.byKey(const ValueKey('finish-workout-button')));
        await tester.pumpAndSettle();

        //
        // Session
        //
        expect(find.text('Workout session'), findsOneWidget);
        expect(find.byType(SessionPage), findsOneWidget);
        expect(find.byType(Form), findsOneWidget);
        expect(find.byIcon(Icons.sentiment_very_dissatisfied), findsOneWidget);
        expect(find.byIcon(Icons.sentiment_neutral), findsOneWidget);
        expect(find.byIcon(Icons.sentiment_very_satisfied), findsOneWidget);
        expect(
          find.text('2:33 PM'),
          findsNWidgets(2),
          reason: 'start and end time are the same',
        );
        final toggleButtons = tester.widget<ToggleButtons>(find.byType(ToggleButtons));
        expect(toggleButtons.isSelected[1], isTrue);
        expect(find.byIcon(Icons.chevron_left), findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsOneWidget);
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();

        //
        // Workout summary
        //
        expect(find.byType(WorkoutSummary), findsOneWidget);
        expect(find.byIcon(Icons.chevron_left), findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);
        expect(find.byIcon(Icons.chevron_right), findsNothing);
      });
    },
    semanticsEnabled: false,
  );

  testWidgets('loads offline from the cached routine', (WidgetTester tester) async {
    // Offline, gym mode uses the already-downloaded (hydrated) routine.
    when(mockRoutinesRepo.watchAllDrift()).thenAnswer(
      (_) => Stream.value([testRoutine]),
    );

    await withClock(Clock.fixed(DateTime(2025, 3, 29, 14, 33)), () async {
      await tester.pumpWidget(renderGymMode(isOnline: false));
      await tester.pumpAndSettle();

      // Gym mode is always reached from a screen that has already populated
      // data, build and settle it here too. A keepAlive stream notifier needs
      // an explicit listener to emit its first value, a bare read leaves it
      // stuck in loading.
      final container = riverpod.ProviderScope.containerOf(
        tester.element(find.byType(TextButton)),
      );
      container.listen(routinesRiverpodProvider, (_, _) {});
      await tester.pumpAndSettle();

      // The mock is shared across tests; only the gym-mode open below must
      // stay clear of server calls.
      clearInteractions(mockRoutinesRepo);

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(find.byType(StreamErrorIndicator), findsNothing);
      expect(find.byType(StartPage), findsOneWidget);
      verifyNever(mockRoutinesRepo.fetchAndSetRoutineFullServer(any));
    });
  });

  testWidgets('offline summary shows the local session stats', (WidgetTester tester) async {
    // The trophy fetch is REST-only; offline it is skipped so the locally
    // stored session stats (duration, volume) render right away instead of
    // waiting behind a doomed network request. The clock matches a session in
    // the test routine so there is data to show.
    await withClock(Clock.fixed(DateTime(2021, 5, 1, 14, 33)), () async {
      await tester.pumpWidget(renderGymMode(isOnline: false));
      await tester.pumpAndSettle();

      // Prime the keepAlive routines stream (see the offline test above).
      final container = riverpod.ProviderScope.containerOf(
        tester.element(find.byType(TextButton)),
      );
      container.listen(routinesRiverpodProvider, (_, _) {});
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      // Jump straight to the summary via the menu's "End workout" shortcut.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End workout'));
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutSummary), findsOneWidget);
      expect(find.byType(StreamErrorIndicator), findsNothing);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
    });
  });

  testWidgets('summary surfaces an unexpected trophy-fetch error', (WidgetTester tester) async {
    // Network/server errors are swallowed by the repository, so an error that
    // does reach the summary is a genuine exception and must be shown, not
    // hidden behind the stats.
    final mockTrophyRepo = MockTrophyRepository();
    when(mockTrophyRepo.fetchTrophies(language: anyNamed('language'))).thenAnswer((_) async => []);
    when(
      mockTrophyRepo.fetchProgression(
        filterQuery: anyNamed('filterQuery'),
        language: anyNamed('language'),
      ),
    ).thenAnswer((_) async => []);
    when(
      mockTrophyRepo.fetchUserTrophies(
        filterQuery: anyNamed('filterQuery'),
        language: anyNamed('language'),
      ),
    ).thenThrow(Exception('unexpected'));

    await withClock(Clock.fixed(DateTime(2021, 5, 1, 14, 33)), () async {
      await tester.pumpWidget(
        renderGymMode(
          extraOverrides: [trophyRepositoryProvider.overrideWithValue(mockTrophyRepo)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      // Jump straight to the summary via the menu's "End workout" shortcut.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End workout'));
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutSummary), findsOneWidget);
      expect(find.byType(StreamErrorIndicator), findsOneWidget);
      expect(find.text('Duration'), findsNothing);
    });
  });

  testWidgets(
    'renders the active workout screen without crashing regardless of showExercisePages',
    (WidgetTester tester) async {
      // showExercisePages predates this screen (it used to toggle a separate
      // full-page exercise overview between the start page and the first log
      // page); it's kept as a setting for now but should no longer affect
      // whether the active workout screen renders correctly.
      await PreferenceHelper.asyncPref.setBool(PREFS_SHOW_EXERCISES, false);

      await withClock(Clock.fixed(DateTime(2025, 3, 29, 14, 33)), () async {
        await tester.pumpWidget(renderGymMode());
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();

        expect(find.byType(StartPage), findsOneWidget);

        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(ActiveWorkoutScreen), findsOneWidget);
        expect(find.text('Bench press'), findsOneWidget);
      });
    },
    semanticsEnabled: false,
  );
}
