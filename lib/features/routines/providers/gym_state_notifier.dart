/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c)  2026 wger Team
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
import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wger/core/shared_preferences.dart';
import 'package:wger/features/exercises/models/exercise.dart';
import 'package:wger/features/routines/models/routine.dart';
import 'package:wger/features/routines/models/set_config_data.dart';
import 'package:wger/features/routines/providers/gym_state.dart';

part 'gym_state_notifier.g.dart';

@Riverpod(keepAlive: true)
class GymStateNotifier extends _$GymStateNotifier {
  final _logger = Logger('GymStateNotifier');

  @override
  GymModeState build() {
    _logger.finer('Initializing GymStateNotifier');
    return GymModeState();
  }

  Future<void> loadPrefs() async {
    final prefs = PreferenceHelper.asyncPref;

    final showExercise = await prefs.getBool(PREFS_SHOW_EXERCISES);
    if (showExercise != null && showExercise != state.showExercisePages) {
      state = state.copyWith(showExercisePages: showExercise);
    }

    final showTimer = await prefs.getBool(PREFS_SHOW_TIMER);
    if (showTimer != null && showTimer != state.showTimerPages) {
      state = state.copyWith(showTimerPages: showTimer);
    }

    final alertOnCountdownEnd = await prefs.getBool(PREFS_ALERT_COUNTDOWN);
    if (alertOnCountdownEnd != null && alertOnCountdownEnd != state.alertOnCountdownEnd) {
      state = state.copyWith(alertOnCountdownEnd: alertOnCountdownEnd);
    }

    final useCountdownBetweenSets = await prefs.getBool(PREFS_USE_COUNTDOWN_BETWEEN_SETS);
    if (useCountdownBetweenSets != null &&
        useCountdownBetweenSets != state.useCountdownBetweenSets) {
      state = state.copyWith(useCountdownBetweenSets: useCountdownBetweenSets);
    }

    final defaultCountdownDurationSeconds = await prefs.getInt(PREFS_COUNTDOWN_DURATION);
    if (defaultCountdownDurationSeconds != null &&
        defaultCountdownDurationSeconds != state.countdownDuration.inSeconds) {
      state = state.copyWith(
        countdownDuration: defaultCountdownDurationSeconds,
      );
    }

    final logScopeWeeks = await prefs.getInt(PREFS_LOG_SCOPE_WEEKS);
    if (logScopeWeeks != null && logScopeWeeks != state.logScopeWeeks) {
      state = state.copyWith(logScopeWeeks: logScopeWeeks);
    }

    final showDistinctLogs = await prefs.getBool(PREFS_SHOW_DISTINCT_LOGS);
    if (showDistinctLogs != null && showDistinctLogs != state.showDistinctLogs) {
      state = state.copyWith(showDistinctLogs: showDistinctLogs);
    }

    _logger.finer(
      'Loaded saved preferences: '
      'showExercise=$showExercise '
      'showTimer=$showTimer '
      'alertOnCountdownEnd=$alertOnCountdownEnd '
      'useCountdownBetweenSets=$useCountdownBetweenSets '
      'defaultCountdownDurationSeconds=$defaultCountdownDurationSeconds'
      'logScopeWeeks=$logScopeWeeks '
      'showDistinctLogs=$showDistinctLogs ',
    );
  }

  Future<void> _savePrefs() async {
    final prefs = PreferenceHelper.asyncPref;
    await prefs.setBool(PREFS_SHOW_EXERCISES, state.showExercisePages);
    await prefs.setBool(PREFS_SHOW_TIMER, state.showTimerPages);
    await prefs.setBool(PREFS_ALERT_COUNTDOWN, state.alertOnCountdownEnd);
    await prefs.setBool(PREFS_USE_COUNTDOWN_BETWEEN_SETS, state.useCountdownBetweenSets);
    await prefs.setInt(
      PREFS_COUNTDOWN_DURATION,
      state.countdownDuration.inSeconds,
    );
    if (state.logScopeWeeks != null) {
      await prefs.setInt(PREFS_LOG_SCOPE_WEEKS, state.logScopeWeeks!);
    } else {
      await prefs.remove(PREFS_LOG_SCOPE_WEEKS);
    }
    await prefs.setBool(PREFS_SHOW_DISTINCT_LOGS, state.showDistinctLogs);

    _logger.finer(
      'Saved preferences: '
      'showExercise=${state.showExercisePages} '
      'showTimer=${state.showTimerPages} '
      'alertOnCountdownEnd=${state.alertOnCountdownEnd} '
      'useCountdownBetweenSets=${state.useCountdownBetweenSets} '
      'defaultCountdownDuration=${state.countdownDuration.inSeconds}'
      'logScopeWeeks=${state.logScopeWeeks} '
      'showDistinctLogs=${state.showDistinctLogs} ',
    );
  }

  /// Projects the routine's day data into the flat list of exercise
  /// sections + set rows the active-workout scroll screen renders.
  void buildWorkoutStructure() {
    final List<ExerciseSlotEntry> slots = [];

    for (final slotData in state.dayDataGym.slots) {
      // Resolve the slot's exercises in the order they appear, deduplicated,
      // for the section header (more than one means a superset).
      final exercises = <Exercise>[];
      for (final exerciseId in slotData.exerciseIds) {
        final setConfig = slotData.setConfigs.firstWhereOrNull(
          (c) => c.exerciseId == exerciseId,
        );
        if (setConfig == null) {
          _logger.warning('Exercise with ID $exerciseId not found in slotData!!');
          continue;
        }
        exercises.add(setConfig.exercise);
      }

      // Number each exercise's sets independently ("set 2 of 4" per
      // exercise), not globally across a superset -- more useful once every
      // exercise gets its own section with its own set list, rather than a
      // single flattened page sequence.
      final setIndexByExercise = <int, int>{};
      final setRows = slotData.setConfigs.map((config) {
        final setIndex = setIndexByExercise.update(
          config.exerciseId,
          (i) => i + 1,
          ifAbsent: () => 0,
        );
        return SetRowEntry(setIndex: setIndex, setConfigData: config);
      }).toList();

      // Seed this exercise's rest duration from its own configured rest time
      // if the routine specifies one, otherwise the user's global default.
      final configuredRest = slotData.setConfigs
          .map((c) => c.restTime)
          .firstWhereOrNull((r) => r != null);
      final restDurationSeconds =
          configuredRest?.toInt() ?? state.countdownDuration.inSeconds;

      slots.add(
        ExerciseSlotEntry(
          exercises: exercises,
          setRows: setRows,
          restDurationSeconds: restDurationSeconds,
        ),
      );
    }

    state = state.copyWith(exerciseSlots: slots);
    _logger.finer('Built workout structure: ${state.exerciseSlots.length} exercise slots');
  }

  int initData(Routine routine, int dayId, int iteration) {
    final validUntil = state.validUntil;

    final shouldReset =
        (!state.isInitialized || state.isInitialized && dayId != state.dayId) ||
        validUntil.isBefore(DateTime.now());
    if (shouldReset) {
      _logger.fine('Day ID mismatch or expired validUntil date. Resetting.');
    }

    state = state.copyWith(
      isInitialized: true,
      dayId: dayId,
      routine: routine,
      iteration: iteration,
    );

    // Note that this is only done if we need to reset, otherwise we keep the
    // existing state like the exercises that have already been done
    if (shouldReset) {
      buildWorkoutStructure();
    }

    _logger.fine('Initialized GymModeState');
    // Index into GymMode's fixed [StartPage, ActiveWorkoutScreen, SessionPage,
    // WorkoutSummary] PageView: land back on the workout screen when resuming
    // an in-progress session, otherwise start from the beginning.
    return shouldReset ? 0 : 1;
  }

  void setShowExercisePages(bool value) {
    state = state.copyWith(showExercisePages: value);
    _savePrefs();
  }

  void setShowTimerPages(bool value) {
    state = state.copyWith(showTimerPages: value);
    _savePrefs();
  }

  void setAlertOnCountdownEnd(bool value) {
    state = state.copyWith(alertOnCountdownEnd: value);
    _savePrefs();
  }

  void setUseCountdownBetweenSets(bool value) {
    state = state.copyWith(useCountdownBetweenSets: value);
    _savePrefs();
  }

  void setCountdownDuration(int duration) {
    state = state.copyWith(countdownDuration: duration);
    _savePrefs();
  }

  /// Passing null resets the scope to the current routine
  void setLogScopeWeeks(int? weeks) {
    state = state.copyWith(logScopeWeeks: weeks, clearLogScopeWeeks: weeks == null);
    _savePrefs();
  }

  void setShowDistinctLogs(bool value) {
    state = state.copyWith(showDistinctLogs: value);
    _savePrefs();
  }

  void markSetRowAsDone(String uuid, {required bool isDone}) {
    final row = state.getSetRowByUUID(uuid);
    if (row == null) {
      _logger.warning('No set row found for UUID $uuid');
      return;
    }

    final updatedSlots = state.exerciseSlots.map((slot) {
      final updatedRows = slot.setRows.map((r) {
        if (r.uuid == uuid) {
          return r.copyWith(logDone: isDone);
        }
        return r;
      }).toList();
      return slot.copyWith(setRows: updatedRows);
    }).toList();

    state = state.copyWith(exerciseSlots: updatedSlots);
    _logger.fine('Set logDone=$isDone for set row UUID $uuid');
  }

  /// Appends one more set to [slotUuid], templated off the last set for
  /// that exercise (same planned config, pre-filled with its weight/reps)
  /// -- lets the user log an extra set beyond what the routine planned.
  void addSetToSlot(String slotUuid) {
    final slot = state.getSlotByUUID(slotUuid);
    if (slot == null || slot.setRows.isEmpty) {
      _logger.warning('No slot/sets found for UUID $slotUuid');
      return;
    }

    final lastRow = slot.setRows.last;
    final nextIndexForExercise = slot.setRows
        .where((r) => r.setConfigData.exerciseId == lastRow.setConfigData.exerciseId)
        .length;

    final newRow = SetRowEntry(
      setIndex: nextIndexForExercise,
      setConfigData: lastRow.setConfigData,
      enteredWeight: lastRow.displayWeight,
      enteredReps: lastRow.displayReps,
    );

    final updatedSlots = state.exerciseSlots.map((s) {
      if (s.uuid != slotUuid) {
        return s;
      }
      return s.copyWith(setRows: [...s.setRows, newRow]);
    }).toList();

    state = state.copyWith(exerciseSlots: updatedSlots);
    _logger.fine('Added a set to slot $slotUuid');
  }

  void updateSetRowValues(String uuid, {num? weight, num? reps}) {
    final updatedSlots = state.exerciseSlots.map((slot) {
      final updatedRows = slot.setRows.map((r) {
        if (r.uuid == uuid) {
          return r.copyWith(enteredWeight: weight, enteredReps: reps);
        }
        return r;
      }).toList();
      return slot.copyWith(setRows: updatedRows);
    }).toList();

    state = state.copyWith(exerciseSlots: updatedSlots);
  }

  void setSlotRestDuration(String slotUuid, int seconds) {
    final updatedSlots = state.exerciseSlots.map((slot) {
      if (slot.uuid != slotUuid) {
        return slot;
      }
      return slot.copyWith(restDurationSeconds: seconds);
    }).toList();

    state = state.copyWith(exerciseSlots: updatedSlots);
    _logger.fine('Set rest duration for slot $slotUuid to ${seconds}s');
  }

  /// Starts (or restarts) the rest countdown for [slotUuid], using that
  /// exercise's configured restDurationSeconds.
  void startRest(String slotUuid) {
    final slot = state.getSlotByUUID(slotUuid);
    if (slot == null) {
      _logger.warning('No slot found for UUID $slotUuid');
      return;
    }

    final endTime = clock.now().add(Duration(seconds: slot.restDurationSeconds));
    final updatedSlots = state.exerciseSlots.map((s) {
      if (s.uuid != slotUuid) {
        return s;
      }
      return s.copyWith(restEndTime: endTime);
    }).toList();

    state = state.copyWith(exerciseSlots: updatedSlots);
  }

  /// Adds (or removes, for a negative value) time to an in-progress rest
  /// period. No-op if [slotUuid] isn't currently resting.
  void extendRest(String slotUuid, int additionalSeconds) {
    final updatedSlots = state.exerciseSlots.map((s) {
      if (s.uuid != slotUuid || s.restEndTime == null) {
        return s;
      }
      return s.copyWith(restEndTime: s.restEndTime!.add(Duration(seconds: additionalSeconds)));
    }).toList();

    state = state.copyWith(exerciseSlots: updatedSlots);
  }

  /// Ends the rest period for [slotUuid], whether because it finished
  /// naturally or the user skipped it.
  void endRest(String slotUuid) {
    final updatedSlots = state.exerciseSlots.map((s) {
      if (s.uuid != slotUuid) {
        return s;
      }
      return s.copyWith(clearRestEndTime: true);
    }).toList();

    state = state.copyWith(exerciseSlots: updatedSlots);
  }

  void replaceExercises(
    String slotUUID, {
    required int originalExerciseId,
    required Exercise newExercise,
  }) {
    final updatedSlots = state.exerciseSlots.map((slot) {
      if (slot.uuid != slotUUID) {
        return slot;
      }

      final updatedExercises = slot.exercises
          .map((e) => e.id == originalExerciseId ? newExercise : e)
          .toList();

      final updatedRows = slot.setRows.map((row) {
        if (row.setConfigData.exercise.id == originalExerciseId) {
          final updatedSetConfigData = row.setConfigData.copyWith(
            exerciseId: newExercise.id,
            exercise: newExercise,
          );
          return row.copyWith(setConfigData: updatedSetConfigData);
        }
        return row;
      }).toList();

      return slot.copyWith(exercises: updatedExercises, setRows: updatedRows);
    }).toList();

    // replace and update new immutable routine instance
    final updatedRoutine = state.routine.replaceExercise(originalExerciseId, newExercise);
    state = state.copyWith(
      exerciseSlots: updatedSlots,
      routine: updatedRoutine,
    );
    _logger.fine('Replaced exercise $originalExerciseId with ${newExercise.id}');
  }

  void addExerciseAfterSlot(
    String slotUUID, {
    required Exercise newExercise,
  }) {
    final List<ExerciseSlotEntry> slots = [];
    for (final slot in state.exerciseSlots) {
      slots.add(slot);

      if (slot.uuid == slotUUID) {
        final referenceSetConfig = slot.setRows.first.setConfigData;

        final newRows = List.generate(4, (i) {
          return SetRowEntry(
            setIndex: i,
            setConfigData: SetConfigData(
              textRepr: '-/-',
              exerciseId: newExercise.id,
              exercise: newExercise,
              slotEntryId: referenceSetConfig.slotEntryId,
            ),
          );
        });

        slots.add(
          ExerciseSlotEntry(
            exercises: [newExercise],
            setRows: newRows,
            restDurationSeconds: state.countdownDuration.inSeconds,
          ),
        );
      }
    }

    state = state.copyWith(exerciseSlots: slots);
    _logger.fine('Added exercise ${newExercise.id} after slot $slotUUID');
  }

  void clear() {
    _logger.fine('Clearing state');
    state = state.copyWith(
      isInitialized: false,
      exerciseSlots: [],

      validUntil: clock.now().add(DEFAULT_DURATION),
      startTime: null,
    );
  }
}
