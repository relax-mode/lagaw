import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/preference_service.dart';
import '../services/trip_service.dart';
import '../widgets/confirm_dialog.dart';
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
  final _form = GlobalKey<TripFormState>();
  bool _submitting = false;
  bool _done = false;

  /// Closing with something filled in asks first, so nothing is lost by a
  /// stray tap.
  Future<void> _confirmClose() async {
    final discard = await showTactileConfirmDialog(
      context,
      title: 'Discard this trip?',
      message: 'You haven’t created it yet. What you filled in will be lost.',
      confirmLabel: 'Discard',
      icon: Icons.delete_outline_rounded,
    );
    if (discard && mounted) {
      setState(() => _done = true);
      Navigator.of(context).pop();
    }
  }

  String? _error;

  /// The last save may have gone through; point to My Trips, not Retry.
  bool _uncertain = false;
  Map<String, String> _fieldErrors = const {};
  TripDraft? _lastDraft;

  Future<void> _create(TripDraft draft) async {
    setState(() {
      _submitting = true;
      _error = null;
      _uncertain = false;
      _fieldErrors = const {};
      _lastDraft = draft;
    });
    try {
      final trip = await widget.service.createTrip(draft);
      if (!mounted) return;
      _done = true;
      // The new trip opens in the same pop-up style.
      Navigator.of(context).pushReplacement(
        blurPopupRoute(
          (_) => TripDetailScreen(
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
        _uncertain = e.uncertain;
      });
    } catch (_) {
      // Never leave the form stuck on its spinner.
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = TripService.uncertainSaveMessage;
        _uncertain = true;
      });
    }
  }

  /// Closes Plan a trip and shows My Trips (reloaded), where the trip is if
  /// the uncertain save went through.
  void _openMyTrips() {
    setState(() => _done = true);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    // Field-level 422 problems are shown on the fields; keep retry for the rest.
    final canRetry = _fieldErrors.isEmpty && _lastDraft != null && !_uncertain;

    // A pop-up over the app, like travel preferences. [home v3]
    return PopScope(
      // Decided when closing, since what's filled in lives in the form.
      canPop: _done,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _submitting) return;
        if (_form.currentState?.isDirty ?? false) {
          _confirmClose();
        } else {
          setState(() => _done = true);
          Navigator.of(context).pop();
        }
      },
      child: PopupCard(
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
                  actionLabel: _uncertain
                      ? 'Open My Trips'
                      : canRetry
                      ? 'Retry'
                      : null,
                  onAction: _submitting
                      ? null
                      : _uncertain
                      ? _openMyTrips
                      : canRetry
                      ? () => _create(_lastDraft!)
                      : null,
                ),
                const SizedBox(height: 16),
              ],
              TripForm(
                key: _form,
                stepped: true,
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
      ),
    );
  }
}
