/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2020, 2025 wger Team
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wger/core/shared_preferences.dart';
import 'package:wger/features/routines/providers/gym_state.dart';
import 'package:wger/features/routines/providers/gym_state_notifier.dart';

import '../../../../test_data/exercises.dart';
import '../../../../test_data/routines.dart';

void main() {
  late GymStateNotifier notifier;
  late ProviderContainer container;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    container = ProviderContainer.test();
    notifier = container.read(gymStateProvider.notifier);
    notifier.state = notifier.state.copyWith(
      showExercisePages: true,
      showTimerPages: true,
      dayId: 1,
      iteration: 1,
      routine: getTestRoutine(),
    );
    notifier.buildWorkoutStructure();
  });

  group('GymStateNotifier.buildWorkoutStructure', () {
    test('Correctly builds exercise slots and set rows', () {
      // Day 1/iteration 1 has 2 slots, each a single (non-superset) exercise
      // with 3 sets -- see test_data/routines.dart.
      final slots = notifier.state.exerciseSlots;
      expect(slots.length, 2, reason: 'Two exercise slots for day 1');

      for (final slot in slots) {
        expect(slot.exercises.length, 1, reason: 'Neither slot is a superset');
        expect(slot.isSuperset, false);
        expect(slot.setRows.length, 3, reason: 'Three sets per slot');
        expect(
          slot.setRows.map((r) => r.setIndex).toList(),
          [0, 1, 2],
          reason: 'Sets are numbered per-exercise starting at 0',
        );
        expect(slot.setRows.every((r) => !r.logDone), true, reason: 'Nothing done initially');
      }

      expect(notifier.state.totalSets, 6);
      expect(notifier.state.completedSets, 0);
      expect(notifier.state.ratioCompleted, 0.0);
    });
  });

  group('GymStateNotifier.markSetRowAsDone', () {
    test('Correctly changes the flag and updates ratioCompleted', () {
      // Arrange
      final row = notifier.state.exerciseSlots[0].setRows[1];
      expect(
        notifier.state.exerciseSlots.every((s) => s.setRows.every((r) => !r.logDone)),
        true,
        reason: 'All set rows are initially not done',
      );

      // Act
      notifier.markSetRowAsDone(row.uuid, isDone: true);

      // Assert
      for (final slot in notifier.state.exerciseSlots) {
        for (final r in slot.setRows) {
          if (r.uuid == row.uuid) {
            expect(r.logDone, true);
          } else {
            expect(r.logDone, false);
          }
        }
      }
      expect(notifier.state.completedSets, 1);
      expect(notifier.state.ratioCompleted, closeTo(1 / 6, 0.0001));
    });
  });

  group('GymStateNotifier.replaceExercises', () {
    test('Correctly swaps an exercise', () {
      // Arrange
      final slot = notifier.state.exerciseSlots[0];
      final originalExerciseId = slot.exercises.first.id;

      // Act
      notifier.replaceExercises(
        slot.uuid,
        originalExerciseId: originalExerciseId,
        newExercise: testSquats,
      );

      // Assert
      final updatedSlot = notifier.state.getSlotByUUID(slot.uuid)!;
      expect(updatedSlot.exercises.first.id, testSquats.id);
      expect(updatedSlot.setRows.every((r) => r.setConfigData.exercise.id == testSquats.id), true);
    });
  });

  group('GymStateNotifier.addExerciseAfterSlot', () {
    test('Inserts a new slot with 4 blank sets right after the given one', () {
      // Arrange
      final firstSlot = notifier.state.exerciseSlots[0];
      final originalSlotCount = notifier.state.exerciseSlots.length;

      // Act
      notifier.addExerciseAfterSlot(firstSlot.uuid, newExercise: testSquats);

      // Assert
      final slots = notifier.state.exerciseSlots;
      expect(slots.length, originalSlotCount + 1);
      expect(slots[0].uuid, firstSlot.uuid);
      expect(slots[1].exercises.single.id, testSquats.id);
      expect(slots[1].setRows.length, 4);
    });
  });

  group('GymStateNotifier.setLogScopeWeeks', () {
    test('Sets the scope and persists it', () async {
      // Act
      notifier.setLogScopeWeeks(12);
      await pumpEventQueue();

      // Assert
      expect(notifier.state.logScopeWeeks, 12);
      expect(await PreferenceHelper.asyncPref.getInt(PREFS_LOG_SCOPE_WEEKS), 12);
    });

    test('Resets the scope to the current routine', () async {
      // Arrange
      notifier.setLogScopeWeeks(12);
      await pumpEventQueue();

      // Act
      notifier.setLogScopeWeeks(null);
      await pumpEventQueue();

      // Assert
      expect(notifier.state.logScopeWeeks, isNull);
      expect(await PreferenceHelper.asyncPref.getInt(PREFS_LOG_SCOPE_WEEKS), isNull);
    });
  });

  group('GymModeState.copyWith', () {
    test('Keeps the log scope when it is not passed', () {
      final state = notifier.state.copyWith(logScopeWeeks: 8);

      expect(state.copyWith(showDistinctLogs: false).logScopeWeeks, 8);
    });

    test('Clears the log scope on clearLogScopeWeeks', () {
      final state = notifier.state.copyWith(logScopeWeeks: 8);

      expect(state.copyWith(clearLogScopeWeeks: true).logScopeWeeks, isNull);
    });
  });
}
