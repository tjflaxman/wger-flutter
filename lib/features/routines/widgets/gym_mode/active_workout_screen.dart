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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wger/features/exercises/widgets/exercises.dart';
import 'package:wger/features/routines/providers/gym_state.dart';
import 'package:wger/features/routines/providers/gym_state_notifier.dart';
import 'package:wger/features/routines/widgets/gym_mode/workout_menu.dart';
import 'package:wger/theme/motion.dart';
import 'package:wger/theme/spacing.dart';
import 'package:wger/theme/theme.dart';

/// The single scrolling "active workout" screen: every exercise in the day's
/// routine as a collapsible section, each with its sets as compact rows --
/// replaces the old per-set/per-exercise/per-timer full-screen PageView
/// pages. This build is display-only (Phase 2 of the redesign); inline
/// editing and the rest-timer banner land in later phases.
class ActiveWorkoutScreen extends ConsumerWidget {
  final PageController controller;

  const ActiveWorkoutScreen(this.controller, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gymState = ref.watch(gymStateProvider);

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

/// One exercise section: a collapsible header (expandable for exercise
/// instructions/images, collapsed by default) plus its set rows. Looked up
/// by slot UUID rather than list index, matching the pattern the old
/// per-page widgets already used, so identity survives list rebuilds.
class ExerciseSectionWidget extends ConsumerStatefulWidget {
  final String slotUuid;

  const ExerciseSectionWidget({required this.slotUuid, super.key});

  @override
  ConsumerState<ExerciseSectionWidget> createState() => _ExerciseSectionWidgetState();
}

class _ExerciseSectionWidgetState extends ConsumerState<ExerciseSectionWidget> {
  bool _expanded = false;

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
            trailing: AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: AppMotion.fast,
              child: const Icon(Icons.expand_more),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                children: [
                  for (final exercise in slot.exercises) ExerciseDetail(exercise),
                  const Divider(),
                ],
              ),
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: AppMotion.standard,
          ),
          for (final row in slot.setRows)
            SetRowWidget(key: ValueKey('set-row-${row.uuid}'), setRowUuid: row.uuid),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// One set, shown as a compact row. Read-only for now (Phase 2); inline
/// weight/reps/RiR editing lands in the next phase.
class SetRowWidget extends ConsumerWidget {
  final String setRowUuid;

  const SetRowWidget({required this.setRowUuid, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = ref.watch(gymStateProvider).getSetRowByUUID(setRowUuid);
    if (row == null) {
      return const SizedBox.shrink();
    }

    return ListTile(
      key: ValueKey('set-row-tile-${row.uuid}'),
      dense: true,
      leading: Icon(
        row.logDone ? Icons.check_circle : Icons.circle_outlined,
        color: row.logDone ? Colors.green : null,
        size: 20,
      ),
      title: Text('Set ${row.setIndex + 1}'),
      subtitle: Text(row.setConfigData.textReprWithType),
    );
  }
}
