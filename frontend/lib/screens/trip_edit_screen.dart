import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/trip_service.dart';
import '../widgets/status_banner.dart';
import '../widgets/trip_form/trip_form.dart';
import 'trip_page_scaffold.dart';

/// Edit a saved trip: loads it through `GET /api/v1/trips/{id}` and saves
/// only the changed fields through `PATCH /api/v1/trips/{id}`.
/// Pops `true` once a save succeeds. [S2-04]
class TripEditScreen extends StatefulWidget {
  final TripService service;
  final String tripId;

  const TripEditScreen({
    super.key,
    required this.service,
    required this.tripId,
  });

  @override
  State<TripEditScreen> createState() => _TripEditScreenState();
}

class _TripEditScreenState extends State<TripEditScreen> {
  Trip? _trip;
  String? _loadError;
  bool _submitting = false;
  Map<String, String> _fieldErrors = const {};
  ({StatusTone tone, String message})? _status;

  /// After a 409 the saved trip moved on; reloading resets the form to it.
  bool _offerReload = false;
  int _formVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final trip = await widget.service.getTrip(widget.tripId);
      if (mounted) {
        setState(() {
          _trip = trip;
          _formVersion++;
        });
      }
    } on TripApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  Future<void> _save(TripDraft draft) async {
    if (draft.changedFieldsFrom(_trip!).isEmpty) {
      setState(
        () => _status = (
          tone: StatusTone.info,
          message: 'No changes to save yet.',
        ),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _status = null;
      _offerReload = false;
      _fieldErrors = const {};
    });
    try {
      await widget.service.updateTrip(widget.tripId, draft, original: _trip);
      if (mounted) Navigator.of(context).pop(true);
    } on TripApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _fieldErrors = e.fieldErrors;
        _status = (tone: StatusTone.error, message: e.message);
        _offerReload = e.statusCode == 409;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    final status = _status;

    return TripPageScaffold(
      title: 'edit trip',
      subtitle: trip?.title,
      children: [
        if (_loadError != null)
          StatusBanner(
            key: const ValueKey('edit-load-error'),
            tone: StatusTone.error,
            message: _loadError!,
            actionLabel: 'Retry',
            onAction: _load,
          )
        else if (trip == null)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        else ...[
          if (status != null) ...[
            StatusBanner(
              key: ValueKey('edit-status-${status.message}'),
              tone: status.tone,
              message: status.message,
              actionLabel: _offerReload ? 'Reload' : null,
              onAction: _offerReload
                  ? () {
                      setState(() {
                        _status = null;
                        _offerReload = false;
                      });
                      _load();
                    }
                  : null,
            ),
            const SizedBox(height: 16),
          ],
          TripForm(
            key: ValueKey('edit-form-${trip.id}-$_formVersion'),
            initial: trip,
            submitLabel: 'Save changes',
            isSubmitting: _submitting,
            fieldErrors: _fieldErrors,
            onSubmit: _save,
          ),
        ],
      ],
    );
  }
}
