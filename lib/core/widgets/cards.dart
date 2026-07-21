/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2020, 2020- wger Team
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

class InfoCard extends StatelessWidget {
  final String text;

  const InfoCard({super.key, this.text = ''});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.info, color: theme.colorScheme.primary),
        title: Text(text),
      ),
    );
  }
}

/// A small title/value stat card (e.g. "Personal records: 3"), optionally
/// tinted -- distinct from [InfoCard] above, which is a message banner with
/// fixed styling, not a labelled number.
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color? color;

  const StatCard({required this.title, required this.value, this.color, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}

class WarningCard extends StatelessWidget {
  final String text;

  const WarningCard({super.key, this.text = ''});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.errorContainer,
      child: ListTile(
        dense: true,
        leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
        title: Text(text),
      ),
    );
  }
}
