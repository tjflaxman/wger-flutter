/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2026 wger Team
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

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wger/features/exercises/widgets/exercises.dart';
import 'package:wger/features/routines/models/log.dart';
import 'package:wger/features/routines/providers/gym_state.dart';
import 'package:wger/features/routines/providers/gym_state_notifier.dart';
import 'package:wger/features/routines/providers/workout_logs_notifier.dart';
import 'package:wger/features/routines/services/rest_timer_notification_service.dart';
import 'package:wger/features/routines/widgets/gym_mode/workout_menu.dart';
import 'package:wger/theme/motion.dart';
import 'package:wger/theme/spacing.dart';
import 'package:wger/theme/theme.dart';

/// The single scrolling "active workout" screen: every exercise in the day's
/// routine as a section with an always-visible set table (Hevy-style: SET /
/// PREVIOUS / KG / REPS / done-checkbox) and its own rest timer -- replaces
/// the old per-set/per-exercise/per-timer full-screen PageView pages.
class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  final PageController controller;

  const ActiveWorkoutScreen(this.controller, {super.key});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  StreamSubscription<RestTimerAction>? _actionsSubscription;

  @override
  void initState() {
    super.initState();
    // Routes +15s/skip taps from the live countdown notification to the same
    // gym-state methods the in-app banner buttons call, so both paths
    // converge on one source of truth.
    _actionsSubscription = ref.read(restTimerNotificationServiceProvider).actions.listen((
      action,
    ) async {
      final notifier = ref.read(gymStateProvider.notifier);
      final notificationService = ref.read(restTimerNotificationServiceProvider);
      final id = _slotNotificationId(action.slotUuid);

      if (action.type == RestTimerActionType.skip) {
        notifier.endRest(action.slotUuid);
        await notificationService.cancel(id);
        return;
      }

      notifier.extendRest(action.slotUuid, 15);
      final updated = ref.read(gymStateProvider).getSlotByUUID(action.slotUuid);
      final endTime = updated?.restEndTime;
      if (endTime != null) {
        await notificationService.showLiveCountdown(
          id: id,
          slotUuid: action.slotUuid,
          endTime: endTime,
        );
        if (ref.read(gymStateProvider).alertOnCountdownEnd) {
          await notificationService.scheduleRestEnd(id: id, endTime: endTime);
        }
      }
    });
  }

  @override
  void dispose() {
    _actionsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gymState = ref.watch(gymStateProvider);
    final controller = widget.controller;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Workout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => showDialog(
              context: context,
              builder: (ctx) => WorkoutMenuDialog(controller),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: gymState.ratioCompleted,
            minHeight: 4,
            backgroundColor: wgerPrimaryColor.withValues(alpha: 0.15),
            valueColor: const AlwaysStoppedAnimation<Color>(wgerPrimaryColor),
          ),
        ),
      ),
      body: gymState.exerciseSlots.isEmpty
          ? const Center(child: Text('Nothing to log today'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl * 2),
              itemCount: gymState.exerciseSlots.length,
              itemBuilder: (context, index) {
                final slot = gymState.exerciseSlots[index];
                return ExerciseSectionWidget(
                  key: ValueKey('section-${slot.uuid}'),
                  slotUuid: slot.uuid,
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('finish-workout-button'),
        onPressed: () {
          controller.nextPage(duration: AppMotion.standard, curve: AppMotion.standardCurve);
        },
        icon: const Icon(Icons.check),
        label: const Text('Finish workout'),
      ),
    );
  }
}

/// One exercise section: name + rest timer + an always-visible set table.
/// Exercise instructions/images are a separate, smaller expand toggle --
/// unlike the table, they're not needed to actually log a set. Looked up by
/// slot UUID rather than list index, matching the pattern the old per-page
/// widgets already used, so identity survives list rebuilds.
class ExerciseSectionWidget extends ConsumerStatefulWidget {
  final String slotUuid;

  const ExerciseSectionWidget({required this.slotUuid, super.key});

  @override
  ConsumerState<ExerciseSectionWidget> createState() => _ExerciseSectionWidgetState();
}

class _ExerciseSectionWidgetState extends ConsumerState<ExerciseSectionWidget> {
  bool _showDetail = false;

  @override
  Widget build(BuildContext context) {
    final slot = ref.watch(gymStateProvider).getSlotByUUID(widget.slotUuid);
    if (slot == null) {
      return const SizedBox.shrink();
    }

    final languageCode = Localizations.localeOf(context).languageCode;
    final title = slot.isSuperset
        ? slot.exercises
              .asMap()
              .entries
              .map(
                (e) =>
                    '${String.fromCharCode(65 + e.key)}: '
                    '${e.value.getTranslation(languageCode).name}',
              )
              .join('  +  ')
        : slot.exercises.first.getTranslation(languageCode).name;

    final doneCount = slot.setRows.where((r) => r.logDone).length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Column(
        children: [
          ListTile(
            key: ValueKey('section-header-${slot.uuid}'),
            leading: Icon(
              slot.allLogsDone ? Icons.check_circle : Icons.circle_outlined,
              color: slot.allLogsDone ? Colors.green : null,
            ),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('$doneCount/${slot.setRows.length} sets'),
            trailing: IconButton(
              key: ValueKey('exercise-detail-toggle-${slot.uuid}'),
              icon: Icon(_showDetail ? Icons.info : Icons.info_outline),
              tooltip: 'Exercise instructions',
              onPressed: () => setState(() => _showDetail = !_showDetail),
            ),
          ),
          // Deliberately not AnimatedCrossFade: it lays out both branches at
          // once (needed to interpolate between their sizes), and doing that
          // for exercise-description HTML content (rendered via flutter_html)
          // triggers a known flutter_html layout bug -- negative width
          // constraints computed from AnimatedCrossFade's intrinsic-sizing
          // pass, even while "collapsed". A plain conditional avoids ever
          // laying it out until it's actually shown, at the cost of a snap
          // instead of a cross-fade for this specific toggle.
          if (_showDetail)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                children: [
                  for (final exercise in slot.exercises) ExerciseDetail(exercise),
                  const Divider(),
                ],
              ),
            ),

          _RestTimerRow(slotUuid: slot.uuid),

          const _SetTableHeaderRow(),
          for (final row in slot.setRows)
            SetRowWidget(
              key: ValueKey('set-row-${row.uuid}'),
              slotUuid: slot.uuid,
              setRowUuid: row.uuid,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('add-set-${slot.uuid}'),
              onPressed: () => ref.read(gymStateProvider.notifier).addSetToSlot(slot.uuid),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add set'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _SetTableHeaderRow extends StatelessWidget {
  const _SetTableHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text('SET', style: style)),
          Expanded(flex: 3, child: Text('PREVIOUS', style: style, textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('KG', style: style, textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('REPS', style: style, textAlign: TextAlign.center)),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

/// One row in the set table: set number, previous performance, editable
/// weight/reps, and a checkbox that saves the log, marks the set done, and
/// starts the rest timer for this exercise.
class SetRowWidget extends ConsumerStatefulWidget {
  final String slotUuid;
  final String setRowUuid;

  const SetRowWidget({required this.slotUuid, required this.setRowUuid, super.key});

  @override
  ConsumerState<SetRowWidget> createState() => _SetRowWidgetState();
}

class _SetRowWidgetState extends ConsumerState<SetRowWidget> {
  late final TextEditingController _weightController;
  late final TextEditingController _repsController;
  @override
  void initState() {
    super.initState();
    final row = ref.read(gymStateProvider).getSetRowByUUID(widget.setRowUuid);
    _weightController = TextEditingController(text: row?.displayWeight?.toString() ?? '');
    _repsController = TextEditingController(text: row?.displayReps?.toString() ?? '');
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    super.dispose();
  }

  Future<void> _onSetComplete(bool? checked, SetRowEntry row) async {
    if (checked != true) {
      ref.read(gymStateProvider.notifier).markSetRowAsDone(row.uuid, isDone: false);
      return;
    }

    final gymState = ref.read(gymStateProvider);
    final weight = num.tryParse(_weightController.text);
    final reps = num.tryParse(_repsController.text);

    final log = Log.fromSetConfigData(
      row.setConfigData,
      routineId: gymState.routine.id,
      iteration: gymState.iteration,
    ).copyWith(weight: weight, repetitions: reps);

    await ref.read(workoutLogProvider).addEntry(log);
    if (!mounted) {
      return;
    }

    final notifier = ref.read(gymStateProvider.notifier);
    notifier.updateSetRowValues(row.uuid, weight: weight, reps: reps);
    notifier.markSetRowAsDone(row.uuid, isDone: true);

    final slot = ref.read(gymStateProvider).getSlotByUUID(widget.slotUuid);
    if (slot == null) {
      return;
    }

    notifier.startRest(widget.slotUuid);
    final endTime = ref.read(gymStateProvider).getSlotByUUID(widget.slotUuid)?.restEndTime;
    if (endTime == null) {
      return;
    }

    final notificationService = ref.read(restTimerNotificationServiceProvider);
    final id = _slotNotificationId(widget.slotUuid);
    // The live countdown is quiet on its own (see the dedicated notification
    // channel) so it's shown regardless; the alarm is what actually alerts
    // at zero, gated by the existing user setting like before.
    await notificationService.showLiveCountdown(
      id: id,
      slotUuid: widget.slotUuid,
      endTime: endTime,
    );
    if (gymState.alertOnCountdownEnd) {
      await notificationService.scheduleRestEnd(id: id, endTime: endTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gymState = ref.watch(gymStateProvider);
    final row = gymState.getSetRowByUUID(widget.setRowUuid);
    if (row == null) {
      return const SizedBox.shrink();
    }

    final routineId = gymState.routine.id;
    final pastLogs = routineId == null
        ? const AsyncValue<List<Log>>.data([])
        : ref.watch(
            pastExerciseLogsProvider(
              routineId: routineId,
              exerciseId: row.setConfigData.exerciseId,
              weeksBack: gymState.logScopeWeeks,
              distinct: gymState.showDistinctLogs,
            ),
          );
    final previousLog = pastLogs.value?.firstOrNull;
    final previousText = previousLog == null
        ? '-'
        : '${previousLog.weight ?? '-'}×${previousLog.repetitions ?? '-'}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(width: 32, child: Text('${row.setIndex + 1}')),
          Expanded(
            flex: 3,
            child: Text(previousText, textAlign: TextAlign.center, style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
          ),
          Expanded(
            flex: 2,
            child: TextField(
              key: ValueKey('set-row-weight-${row.uuid}'),
              controller: _weightController,
              enabled: !row.logDone,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            flex: 2,
            child: TextField(
              key: ValueKey('set-row-reps-${row.uuid}'),
              controller: _repsController,
              enabled: !row.logDone,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            ),
          ),
          SizedBox(
            width: 40,
            child: Checkbox(
              key: ValueKey('set-row-checkbox-${row.uuid}'),
              value: row.logDone,
              onChanged: (checked) => _onSetComplete(checked, row),
            ),
          ),
        ],
      ),
    );
  }
}

int _slotNotificationId(String slotUuid) => slotUuid.hashCode & 0x7fffffff;

/// Shows this exercise's rest timer: idle (tap to adjust the duration via a
/// rolling minutes/seconds picker) or an active countdown with +15s/skip,
/// mirroring Hevy's per-exercise rest timer at the top of each movement.
class _RestTimerRow extends ConsumerStatefulWidget {
  final String slotUuid;

  const _RestTimerRow({required this.slotUuid});

  @override
  ConsumerState<_RestTimerRow> createState() => _RestTimerRowState();
}

class _RestTimerRowState extends ConsumerState<_RestTimerRow> {
  // Drives the once-per-second rebuild while resting. Deliberately not a
  // long-lived Ticker/AnimationController spanning the whole rest period --
  // see timer.dart's TimerCountdownWidget for why that trips up widget
  // tests' pumpAndSettle().
  Timer? _uiTimer;

  void _ensureTicker(bool resting) {
    if (resting && _uiTimer == null) {
      _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (!resting && _uiTimer != null) {
      _uiTimer!.cancel();
      _uiTimer = null;
    }
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  String _format(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _showDurationPicker(int currentSeconds) async {
    var minutes = currentSeconds ~/ 60;
    var quarterMinutes = (currentSeconds % 60) ~/ 15;

    final result = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) {
        return SizedBox(
          height: 260,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Text('Rest duration'),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(initialItem: minutes),
                        itemExtent: 36,
                        onSelectedItemChanged: (i) => minutes = i,
                        children: List.generate(11, (i) => Center(child: Text('$i min'))),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: quarterMinutes,
                        ),
                        itemExtent: 36,
                        onSelectedItemChanged: (i) => quarterMinutes = i,
                        children: List.generate(4, (i) => Center(child: Text('${i * 15} sec'))),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: FilledButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(minutes * 60 + quarterMinutes * 15),
                  child: const Text('Set'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result != null && result > 0 && mounted) {
      ref.read(gymStateProvider.notifier).setSlotRestDuration(widget.slotUuid, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slot = ref.watch(gymStateProvider).getSlotByUUID(widget.slotUuid);
    if (slot == null) {
      return const SizedBox.shrink();
    }

    _ensureTicker(slot.isResting);

    if (!slot.isResting) {
      return ListTile(
        key: ValueKey('rest-timer-idle-${slot.uuid}'),
        dense: true,
        leading: const Icon(Icons.timer_outlined),
        title: Text('Rest: ${_format(slot.restDurationSeconds)}'),
        onTap: () => _showDurationPicker(slot.restDurationSeconds),
      );
    }

    // clock.now(), not DateTime.now(): restEndTime was computed from
    // clock.now() in startRest() (gym_state_notifier.dart), which tests
    // override via withClock() to a fixed date. Comparing against real
    // wall-clock time here would make the countdown read as already
    // expired the moment a fixed test clock isn't "now" -- which is
    // exactly what was happening (this is the fix for the "the other
    // exercise is idle" / 2 idle rows test failure).
    final remaining = slot.restEndTime!.difference(clock.now());
    final remainingSeconds = remaining.inSeconds <= 0 ? 0 : remaining.inSeconds;

    if (remainingSeconds == 0) {
      // Can't mutate provider state synchronously during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(gymStateProvider.notifier).endRest(widget.slotUuid);
          // If alertOnCountdownEnd is off, no zero-alert was ever scheduled
          // to replace/dismiss the ongoing chronometer notification -- it
          // would otherwise sit there frozen at 0:00 indefinitely.
          ref
              .read(restTimerNotificationServiceProvider)
              .cancel(_slotNotificationId(widget.slotUuid));
        }
      });
    }

    return ListTile(
      key: ValueKey('rest-timer-active-${slot.uuid}'),
      dense: true,
      tileColor: wgerPrimaryColor.withValues(alpha: 0.08),
      leading: const Icon(Icons.timer, color: wgerPrimaryColor),
      title: Text(
        _format(remainingSeconds),
        style: const TextStyle(color: wgerPrimaryColor, fontWeight: FontWeight.bold),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            key: ValueKey('rest-timer-add15-${slot.uuid}'),
            onPressed: () async {
              ref.read(gymStateProvider.notifier).extendRest(widget.slotUuid, 15);
              final updated = ref.read(gymStateProvider).getSlotByUUID(widget.slotUuid);
              final endTime = updated?.restEndTime;
              if (endTime == null) {
                return;
              }
              final notificationService = ref.read(restTimerNotificationServiceProvider);
              final id = _slotNotificationId(widget.slotUuid);
              await notificationService.showLiveCountdown(
                id: id,
                slotUuid: widget.slotUuid,
                endTime: endTime,
              );
              if (ref.read(gymStateProvider).alertOnCountdownEnd) {
                await notificationService.scheduleRestEnd(id: id, endTime: endTime);
              }
            },
            child: const Text('+15s'),
          ),
          IconButton(
            key: ValueKey('rest-timer-skip-${slot.uuid}'),
            icon: const Icon(Icons.close),
            tooltip: 'Skip rest',
            onPressed: () {
              ref.read(gymStateProvider.notifier).endRest(widget.slotUuid);
              ref
                  .read(restTimerNotificationServiceProvider)
                  .cancel(_slotNotificationId(widget.slotUuid));
            },
          ),
        ],
      ),
    );
  }
}
