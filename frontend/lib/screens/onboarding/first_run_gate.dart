import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/discovery_service.dart';
import '../../services/onboarding_repository.dart';
import 'discovery_screen.dart';
import 'onboarding_flow.dart';

/// Opens travel preferences as a pop-up over the blurred app. Signed-in builds use the real #102/#103 APIs
/// and continue to recommendations; builds without Supabase use the mock.
/// [S4-04]
Future<void> openTravelPreferences(
  BuildContext context, {
  bool allowSkip = false,
  DiscoveryService? service,
}) {
  final OnboardingRepository repository;
  WidgetBuilder? next;
  if (service != null || AppConfig.authEnabled) {
    final discovery = service ?? DiscoveryService();
    repository = discovery;
    next = (_) => DiscoveryScreen(service: discovery);
  } else {
    repository = MockOnboardingRepository.shared;
  }
  return showPreferencesPopup<void>(
    context,
    OnboardingFlow(repository: repository, next: next, allowSkip: allowSkip),
  );
}

/// Sends a signed-in user with no saved preferences to onboarding once per
/// app run. If the check fails the app opens normally; preferences stay
/// reachable from the account sheet. [S4-04]
class FirstRunGate extends StatefulWidget {
  /// Identifies the signed-in account, so each account is checked once.
  final String accountKey;
  final DiscoveryService Function() service;
  final Widget child;

  const FirstRunGate({
    super.key,
    required this.accountKey,
    required this.service,
    required this.child,
  });

  /// Accounts already checked (or skipped) in this app run.
  static final Set<String> checked = {};

  @override
  State<FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends State<FirstRunGate> {
  @override
  void initState() {
    super.initState();
    if (FirstRunGate.checked.add(widget.accountKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    final service = widget.service();
    try {
      final prefs = await service.load();
      if (!mounted || !prefs.isUnset) return;
      await openTravelPreferences(context, allowSkip: true, service: service);
    } on Object {
      // Not knowing must not block the app.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
