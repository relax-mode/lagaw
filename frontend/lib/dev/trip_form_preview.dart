import 'package:flutter/material.dart';
import '../models/trip.dart';
import '../theme.dart';
import '../widgets/trip_form/trip_form.dart';

/// Dev-only preview of the reusable trip form until the real screens land
/// in Milestone 3. Run: flutter run -d chrome -t lib/dev/trip_form_preview.dart
void main() => runApp(const _TripFormPreview());

class _TripFormPreview extends StatefulWidget {
  const _TripFormPreview();

  @override
  State<_TripFormPreview> createState() => _TripFormPreviewState();
}

class _TripFormPreviewState extends State<_TripFormPreview> {
  bool _editMode = false;
  String _lastSubmitted = '';

  static final _sample = TripDraft(
    title: 'Weekend food crawl',
    startDate: DateTime.now().add(const Duration(days: 7)),
    endDate: DateTime.now().add(const Duration(days: 8)),
    budgetMin: 1500,
    budgetMax: 3000,
    transportationMode: 'jeepney',
    groupType: 'friends',
    preferredTags: const ['food', 'cafe'],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.skyTop, AppTheme.skyMid, AppTheme.skyBottom],
              stops: [0.0, 0.48, 1.0],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _editMode ? 'edit trip' : 'plan a trip',
                            style: const TextStyle(
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w900,
                              fontSize: 30,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Vector3DButton(
                          onTap: () => setState(() => _editMode = !_editMode),
                          backgroundColor: Colors.white,
                          shadowColor: const Color(0xFFCBD5E1),
                          borderColor: const Color(0xFFE2E8F0),
                          child: Text(_editMode ? 'Show create' : 'Show edit'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TripForm(
                      key: ValueKey(_editMode),
                      initial: _editMode ? _sample : null,
                      submitLabel: _editMode ? 'Save changes' : 'Create trip',
                      onSubmit: (draft) => setState(
                        () => _lastSubmitted = draft.toJson().toString(),
                      ),
                    ),
                    if (_lastSubmitted.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: GlassContainer(child: Text(_lastSubmitted)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
