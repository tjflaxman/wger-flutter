/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (C) 2020, 2025 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * wger Workout Manager is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:wger/features/exercises/widgets/autocompleter.dart';
import 'package:wger/features/routines/providers/gym_state.dart';
import 'package:wger/features/routines/providers/gym_state_notifier.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

/// A single overview of the workout's progress + inline exercise swap/add.
/// Used to be one of two tabs alongside a "jump to page" checklist
/// (NavigationTab) -- that's gone now that the whole workout is visible by
/// scrolling on one screen, so there's nothing left to jump to.
class WorkoutMenu extends StatelessWidget {
  final PageController _controller;

  const WorkoutMenu(this._controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return ProgressionTab(_controller);
  }
}

class ProgressionTab extends ConsumerStatefulWidget {
  final _logger = Logger('ProgressionTab');
  final PageController _controller;

  ProgressionTab(this._controller, {super.key});

  @override
  ConsumerState<ProgressionTab> createState() => _ProgressionTabState();
}

class _ProgressionTabState extends ConsumerState<ProgressionTab> {
  String? showSwapWidgetToSlot;
  String? showAddExerciseWidgetToSlot;
  _ProgressionTabState();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gymStateProvider);
    final theme = Theme.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Column(
          children: [
            ...state.exerciseSlots.map((slot) {
              if (slot.exercises.isEmpty) {
                widget._logger.warning('Slot ${slot.uuid} has no exercises, skipping');
                return Container();
              }

              // For supersets, prefix the exercise with A, B, C so it can be identified
              // in the set list below
              final isSuperset = slot.isSuperset;
              final slotExerciseTitle = isSuperset
                  ? slot.exercises
                        .asMap()
                        .entries
                        .map((entry) {
                          final label = String.fromCharCode(65 + entry.key);
                          final name = entry.value
                              .getTranslation(Localizations.localeOf(context).languageCode)
                              .name;
                          return '$label: $name';
                        })
                        .join('\n')
                  : slot.exercises.first.getTranslation(languageCode).name;

              return Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slotExerciseTitle, style: Theme.of(context).textTheme.bodyLarge),
                  ...slot.setRows.map((row) {
                    String setPrefix = '';
                    if (isSuperset) {
                      final exerciseIndex = slot.exercises.indexWhere(
                        (ex) => ex.id == row.setConfigData.exercise.id,
                      );
                      if (exerciseIndex != -1) {
                        setPrefix = '${String.fromCharCode(65 + exerciseIndex)}: ';
                      }
                    }

                    // Sets that are done are marked with a strikethrough
                    final decoration = row.logDone
                        ? TextDecoration.lineThrough
                        : TextDecoration.none;

                    // Sets that are done have a lighter color
                    final color = row.logDone
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.6)
                        : null;

                    final icon = row.logDone ? Icons.check_circle_rounded : Icons.circle_outlined;

                    return Row(
                      children: [
                        Icon(icon, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '$setPrefix${row.setConfigData.textReprWithType}',
                          style: theme.textTheme.bodyMedium!.copyWith(
                            decoration: decoration,
                            color: color,
                          ),
                        ),
                      ],
                    );
                  }),

                  Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      IconButton(
                        onPressed: slot.allLogsDone
                            ? null
                            : () {
                                if (showSwapWidgetToSlot == slot.uuid) {
                                  setState(() {
                                    showSwapWidgetToSlot = null;
                                  });
                                } else {
                                  setState(() {
                                    showSwapWidgetToSlot = slot.uuid;
                                    showAddExerciseWidgetToSlot = null;
                                  });
                                }
                              },
                        icon: Icon(
                          key: ValueKey('swap-icon-${slot.uuid}'),
                          showSwapWidgetToSlot == slot.uuid
                              ? Icons.change_circle
                              : Icons.change_circle_outlined,
                        ),
                      ),
                      IconButton(
                        onPressed: slot.allLogsDone
                            ? null
                            : () {
                                if (showAddExerciseWidgetToSlot == slot.uuid) {
                                  setState(() {
                                    showAddExerciseWidgetToSlot = null;
                                  });
                                } else {
                                  setState(() {
                                    showAddExerciseWidgetToSlot = slot.uuid;
                                    showSwapWidgetToSlot = null;
                                  });
                                }
                              },
                        icon: Icon(
                          key: ValueKey('add-icon-${slot.uuid}'),
                          showAddExerciseWidgetToSlot == slot.uuid
                              ? Icons.add_circle
                              : Icons.add,
                        ),
                      ),
                    ],
                  ),
                  if (showSwapWidgetToSlot == slot.uuid)
                    ExerciseSwapWidget(
                      slot.uuid,
                      onDone: () {
                        setState(() {
                          showSwapWidgetToSlot = null;
                        });
                      },
                    ),
                  if (showAddExerciseWidgetToSlot == slot.uuid)
                    ExerciseAddWidget(
                      slot.uuid,
                      onDone: () {
                        setState(() {
                          showAddExerciseWidgetToSlot = null;
                        });
                      },
                    ),
                  const SizedBox(height: 8),
                ],
              );
            }),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Swapping or adding an exercise only affects the current workout, '
                'no changes are saved.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExerciseSwapWidget extends ConsumerWidget {
  final _logger = Logger('ExerciseSwapWidget');

  final String slotUUID;
  final VoidCallback? onDone;

  ExerciseSwapWidget(this.slotUUID, {this.onDone, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gymStateProvider);
    final gymProvider = ref.read(gymStateProvider.notifier);
    final slot = state.exerciseSlots.firstWhere((s) => s.uuid == slotUUID);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Column(
            children: [
              ...slot.exercises.map((e) {
                return Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Text(
                      e.getTranslation(Localizations.localeOf(context).languageCode).name,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const Icon(Icons.swap_vert),
                    ExerciseAutocompleter(
                      onExerciseSelected: (exercise) {
                        gymProvider.replaceExercises(
                          slot.uuid,
                          originalExerciseId: e.id,
                          newExercise: exercise,
                        );
                        onDone?.call();
                        _logger.fine('Replaced exercise ${e.id} with ${exercise.id}');
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class ExerciseAddWidget extends ConsumerWidget {
  final _logger = Logger('ExerciseAddWidget');

  final String slotUUID;
  final VoidCallback? onDone;

  ExerciseAddWidget(this.slotUUID, {this.onDone, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gymProvider = ref.read(gymStateProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Column(
            children: [
              ExerciseAutocompleter(
                onExerciseSelected: (exercise) {
                  gymProvider.addExerciseAfterSlot(
                    slotUUID,
                    newExercise: exercise,
                  );
                  onDone?.call();
                  _logger.fine('Added exercise ${exercise.id} after slot $slotUUID');
                },
              ),
              const Icon(Icons.arrow_downward),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class WorkoutMenuDialog extends ConsumerWidget {
  final PageController controller;
  final bool showEndWorkoutButton;

  const WorkoutMenuDialog(
    this.controller, {
    super.key,
    this.showEndWorkoutButton = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final endWorkoutButton = showEndWorkoutButton
        ? TextButton(
            child: Text(AppLocalizations.of(context).endWorkout),
            onPressed: () {
              // GymMode's outer PageView is a fixed [Start, ActiveWorkout,
              // Session, Summary] -- index 3 (WorkoutSummary) matches the
              // previous behavior, which animated to an intentionally
              // out-of-range page index that PageView clamped to its last
              // valid page.
              controller.animateToPage(
                3,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );

              Navigator.of(context).pop();
            },
          )
        : null;

    return AlertDialog(
      title: Text(
        AppLocalizations.of(context).jumpTo,
        textAlign: TextAlign.center,
      ),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: double.maxFinite,
        child: WorkoutMenu(controller),
      ),
      actions: [
        ?endWorkoutButton,
        TextButton(
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
