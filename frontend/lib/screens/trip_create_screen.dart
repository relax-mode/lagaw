import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/preference_service.dart';
import '../services/trip_service.dart';
import '../widgets/status_banner.dart';
import '../widgets/trip_form/trip_form.dart';
import 'trip_detail_screen.dart';
import '../widgets/popup_route.dart';

/// Create a trip through `POST /api/v1/trips`, as a pop-up over the app.
/// On success it replaces itself with the saved trip's detail page.
/// Open it with [blurPopupRoute]. [S2-04, home v3]
class TripCreateScreen extends StatefulWidget {
  final TripService service;

  /// Backs "Describe your trip"; defaults to the live extraction API.
  final PreferenceService? preferenceService;

  const TripCreateScreen({
    super.key,
    required this.service,
    this.preferenceService,
  });

  @override
  State<TripCreateScreen> createState() => _TripCreateScreenState();
}

class _TripCreateScreenState extends State<TripCreateScreen> {
  bool _submitting = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};
  TripDraft? _lastDraft;

  Future<void> _create(TripDraft draft) async {
    setState(() {
      _submitting = true;
      _error = null;
      _fieldErrors = const {};
      _lastDraft = draft;
    });
    try {
      final trip = await widget.service.createTrip(draft);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TripDetailScreen(
            service: widget.service,
            tripId: trip.id,
            initial: trip,
            notice: 'Trip saved! You can find it anytime in My Trips.',
          ),
        ),
        result: true,
      );
    } on TripApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _fieldErrors = e.fieldErrors;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Field-level 422 problems are shown on the fields; keep retry for the rest.
    final canRetry = _fieldErrors.isEmpty && _lastDraft != null;

    // A pop-up over the app, like travel preferences. [home v3]
    return PopupCard(
      eyebrow: 'New trip',
      title: 'Plan a trip',
      subtitle: 'Set the basics, and Lagaw fills in the stops later.',
      busy: _submitting,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              StatusBanner(
                key: const ValueKey('create-error'),
                tone: StatusTone.error,
                message: _error!,
                actionLabel: canRetry ? 'Retry' : null,
                onAction: canRetry && !_submitting
                    ? () => _create(_lastDraft!)
                    : null,
              ),
              const SizedBox(height: 16),
            ],
            TripForm(
              submitLabel: 'Create trip',
              isSubmitting: _submitting,
              fieldErrors: _fieldErrors,
              onSubmit: _create,
              preferenceService: widget.preferenceService,
              flat: true,
            ),
          ],
        ),
      ),
    );
  }
}
