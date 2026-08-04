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
import 'package:flutter/material.dart';
import 'package:wger/core/uuid.dart';
import 'package:wger/features/exercises/models/exercise.dart';
import 'package:wger/features/routines/models/day_data.dart';
import 'package:wger/features/routines/models/routine.dart';
import 'package:wger/features/routines/models/set_config_data.dart';

const DEFAULT_DURATION = Duration(hours: 5);

const PREFS_SHOW_EXERCISES = 'showExercisePrefs';
const PREFS_SHOW_TIMER = 'showTimerPrefs';
const PREFS_ALERT_COUNTDOWN = 'alertCountdownPrefs';
const PREFS_USE_COUNTDOWN_BETWEEN_SETS = 'useCountdownBetweenSetsPrefs';
const PREFS_COUNTDOWN_DURATION = 'countdownDurationSecondsPrefs';
const PREFS_LOG_SCOPE_WEEKS = 'logScopeWeeksPrefs';
const PREFS_SHOW_DISTINCT_LOGS = 'showDistinctLogsPrefs';
const PREFS_SHOW_WORKOUT_DURATION = 'showWorkoutDurationPrefs';

/// In seconds
const DEFAULT_COUNTDOWN_DURATION = 180;
const MIN_COUNTDOWN_DURATION = 10;
const MAX_COUNTDOWN_DURATION = 1800;

/// One set within an [ExerciseSlotEntry], i.e. one row in the active-workout
/// scroll screen. Replaces the old SlotPageEntry (which additionally tracked
/// a `type`/`pageIndex` for a PageView -- meaningless once every set is a row
/// in a scrolling list rather than its own page).
class SetRowEntry {
  final String uuid;

  /// 0-based position of this set within its own exercise's sets (e.g. "set
  /// 2 of 4"), not a global position across the whole workout.
  final int setIndex;

  final bool logDone;

  final SetConfigData setConfigData;

  /// Weight/reps actually entered for this set, distinct from
  /// setConfigData's planned/target values. Null means "use the plan's
  /// value as the default" -- the UI falls back to setConfigData.weight /
  /// .repetitions until the user edits the field.
  final num? enteredWeight;
  final num? enteredReps;

  /// The id of the persisted Log this set was saved as, once completed --
  /// lets deleting the row also delete the log it created instead of
  /// leaving an orphaned entry behind.
  final String? loggedEntryId;

  SetRowEntry({
    required this.setIndex,
    required this.setConfigData,
    this.logDone = false,
    this.enteredWeight,
    this.enteredReps,
    this.loggedEntryId,
    String? uuid,
  }) : uuid = uuid ?? uuidV4();

  SetRowEntry copyWith({
    String? uuid,
    int? setIndex,
    SetConfigData? setConfigData,
    bool? logDone,
    num? enteredWeight,
    num? enteredReps,
    String? loggedEntryId,
  }) {
    return SetRowEntry(
      uuid: uuid ?? this.uuid,
      setIndex: setIndex ?? this.setIndex,
      setConfigData: setConfigData ?? this.setConfigData,
      logDone: logDone ?? this.logDone,
      enteredWeight: enteredWeight ?? this.enteredWeight,
      enteredReps: enteredReps ?? this.enteredReps,
      loggedEntryId: loggedEntryId ?? this.loggedEntryId,
    );
  }

  num? get displayWeight => enteredWeight ?? setConfigData.weight;

  num? get displayReps => enteredReps ?? setConfigData.repetitions;

  @override
  String toString() =>
      'SetRowEntry(uuid: $uuid, setIndex: $setIndex, logDone: $logDone)';
}

/// One exercise-section in the active-workout scroll screen, corresponding
/// to one routine "slot" (more than one exercise means a superset).
/// Replaces the old PageEntry (which existed purely to flatten the routine
/// into a 1-D page index a PageController could jump to -- there's no such
/// index in a scrolling list).
class ExerciseSlotEntry {
  final String uuid;
  final List<Exercise> exercises;
  final List<SetRowEntry> setRows;

  /// How long to rest after a set in this exercise, in seconds. Seeded from
  /// the routine's configured rest time (if any) or the global default, and
  /// adjustable per-exercise from the active-workout screen (tap to open a
  /// duration picker), mirroring Hevy's per-exercise rest timer.
  final int restDurationSeconds;

  /// When set, a rest period is actively counting down to this time.
  final DateTime? restEndTime;

  ExerciseSlotEntry({
    required this.exercises,
    this.setRows = const [],
    required this.restDurationSeconds,
    this.restEndTime,
    String? uuid,
  }) : uuid = uuid ?? uuidV4();

  ExerciseSlotEntry copyWith({
    String? uuid,
    List<Exercise>? exercises,
    List<SetRowEntry>? setRows,
    int? restDurationSeconds,
    DateTime? restEndTime,
    bool clearRestEndTime = false,
  }) {
    return ExerciseSlotEntry(
      uuid: uuid ?? this.uuid,
      exercises: exercises ?? this.exercises,
      setRows: setRows ?? this.setRows,
      restDurationSeconds: restDurationSeconds ?? this.restDurationSeconds,
      restEndTime: clearRestEndTime ? null : (restEndTime ?? this.restEndTime),
    );
  }

  bool get isResting => restEndTime != null;

  bool get allLogsDone => setRows.isNotEmpty && setRows.every((row) => row.logDone);

  bool get isSuperset => exercises.length > 1;

  @override
  String toString() => 'ExerciseSlotEntry(uuid: $uuid, exercises: ${exercises.length})';
}

class GymModeState {
  final bool isInitialized;

  final List<ExerciseSlotEntry> exerciseSlots;

  /// Moment the workout was started, with full seconds precision -- set when
  /// gym mode is opened and reset when the user (re)starts.
  final DateTime workoutStart;
  final DateTime validUntil;

  // User settings
  final bool showExercisePages;
  final bool showTimerPages;
  final bool alertOnCountdownEnd;
  final bool useCountdownBetweenSets;
  final Duration countdownDuration;
  final int? logScopeWeeks;
  final bool showDistinctLogs;
  final bool showWorkoutDuration;

  // Routine data
  late final int dayId;
  late final int iteration;
  late final Routine routine;

  GymModeState({
    this.isInitialized = false,
    this.exerciseSlots = const [],

    this.showExercisePages = true,
    this.showTimerPages = true,
    this.alertOnCountdownEnd = true,
    this.useCountdownBetweenSets = false,
    this.countdownDuration = const Duration(seconds: DEFAULT_COUNTDOWN_DURATION),
    this.logScopeWeeks,
    this.showDistinctLogs = true,
    this.showWorkoutDuration = true,
    int? dayId,
    int? iteration,
    Routine? routine,

    DateTime? validUntil,
    DateTime? workoutStart,
  }) : validUntil = validUntil ?? clock.now().add(DEFAULT_DURATION),
       workoutStart = workoutStart ?? clock.now() {
    if (dayId != null) {
      this.dayId = dayId;
    }

    if (iteration != null) {
      this.iteration = iteration;
    }

    if (routine != null) {
      this.routine = routine;
    }
  }

  GymModeState copyWith({
    bool? isInitialized,
    List<ExerciseSlotEntry>? exerciseSlots,

    // Routine data
    int? dayId,
    int? iteration,
    DateTime? validUntil,
    DateTime? workoutStart,
    Routine? routine,

    // User settings
    bool? showExercisePages,
    bool? showTimerPages,
    bool? alertOnCountdownEnd,
    bool? useCountdownBetweenSets,
    int? countdownDuration,
    int? logScopeWeeks,
    bool clearLogScopeWeeks = false,
    bool? showDistinctLogs,
    bool? showWorkoutDuration,
  }) {
    return GymModeState(
      isInitialized: isInitialized ?? this.isInitialized,
      exerciseSlots: exerciseSlots ?? this.exerciseSlots,

      dayId: dayId ?? this.dayId,
      iteration: iteration ?? this.iteration,
      validUntil: validUntil ?? this.validUntil,
      workoutStart: workoutStart ?? this.workoutStart,
      routine: routine ?? this.routine,

      showExercisePages: showExercisePages ?? this.showExercisePages,
      showTimerPages: showTimerPages ?? this.showTimerPages,
      alertOnCountdownEnd: alertOnCountdownEnd ?? this.alertOnCountdownEnd,
      useCountdownBetweenSets: useCountdownBetweenSets ?? this.useCountdownBetweenSets,
      countdownDuration: Duration(
        seconds: countdownDuration ?? this.countdownDuration.inSeconds,
      ),
      showWorkoutDuration: showWorkoutDuration ?? this.showWorkoutDuration,
      logScopeWeeks: clearLogScopeWeeks ? null : (logScopeWeeks ?? this.logScopeWeeks),
      showDistinctLogs: showDistinctLogs ?? this.showDistinctLogs,
    );
  }

  /// The start of the workout as a TimeOfDay, e.g. for the session form.
  TimeOfDay get startTime => TimeOfDay.fromDateTime(workoutStart);

  DayData get dayDataGym =>
      routine.dayDataGym.where((e) => e.iteration == iteration && e.day?.id == dayId).first;

  DayData get dayDataDisplay => routine.dayData.firstWhere(
    (e) => e.iteration == iteration && e.day?.id == dayId,
  );

  ExerciseSlotEntry? getSlotByUUID(String uuid) {
    for (final slot in exerciseSlots) {
      if (slot.uuid == uuid) {
        return slot;
      }
    }
    return null;
  }

  SetRowEntry? getSetRowByUUID(String uuid) {
    for (final slot in exerciseSlots) {
      for (final row in slot.setRows) {
        if (row.uuid == uuid) {
          return row;
        }
      }
    }
    return null;
  }

  int get totalSets => exerciseSlots.fold(0, (sum, slot) => sum + slot.setRows.length);

  int get completedSets => exerciseSlots.fold(
    0,
    (sum, slot) => sum + slot.setRows.where((row) => row.logDone).length,
  );

  double get ratioCompleted {
    if (totalSets == 0) {
      return 0.0;
    }
    return completedSets / totalSets;
  }

  @override
  String toString() {
    return 'GymState('
        'exerciseSlots: ${exerciseSlots.length}, '
        'validUntil: $validUntil '
        'workoutStart: $workoutStart, '
        'showExercisePages: $showExercisePages, '
        'showTimerPages: $showTimerPages, '
        ')';
  }
}
