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

import 'package:flutter/animation.dart';
import 'package:wger/core/consts.dart';

/// Shared motion tokens for the gym-mode reskin. New animated widgets should
/// pick a named constant here instead of inlining a Duration/Curve, so the
/// whole flow's motion stays consistent and easy to retune from one place.
class AppMotion {
  AppMotion._();

  // Durations
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 450);

  // Curves
  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Curves.easeOutBack;

  /// The app-wide default used by existing PageView transitions
  /// (see lib/core/consts.dart). Re-exported here so new code can reach for
  /// AppMotion for everything rather than mixing import sources.
  static const Duration legacyPageDuration = DEFAULT_ANIMATION_DURATION;
  static const Curve legacyPageCurve = DEFAULT_ANIMATION_CURVE;
}
