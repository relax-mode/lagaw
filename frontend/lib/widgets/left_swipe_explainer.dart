import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'confirm_dialog.dart';

const _seenKey = 'lagaw.discovery.leftSwipeExplained';

/// Before the first left swipe on this device, explains that it means "not
/// for me" and is permanent. True when the swipe should go ahead. [S4-10]
Future<bool> confirmLeftSwipeOnce(BuildContext context) async {
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seenKey) ?? false) return true;
  } on Object {
    // No storage (e.g. private browsing): explain every time instead.
  }
  if (!context.mounted) return false;
  final ok = await showTactileConfirmDialog(
    context,
    title: 'Not for you?',
    message:
        'Swiping left means "not for me". We won’t recommend this place '
        'again, and this can’t be undone. We’ll only ask once.',
    confirmLabel: 'Got it, pass',
    icon: Icons.thumb_down_alt_rounded,
  );
  if (ok) {
    try {
      await prefs?.setBool(_seenKey, true);
    } on Object {
      // Not remembered; the explainer shows again next time.
    }
  }
  return ok;
}
