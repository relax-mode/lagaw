import 'package:flutter/material.dart';

/// Pick 1–5 stars; pops the count, or null on cancel. [S3-11, S4-10]
class RatingDialog extends StatefulWidget {
  final String name;

  const RatingDialog({super.key, required this.name});

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _stars = 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rate ${widget.name}'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              key: ValueKey('rating-star-$i'),
              tooltip: '$i star${i == 1 ? '' : 's'}',
              onPressed: () => setState(() => _stars = i),
              icon: Icon(
                i <= _stars ? Icons.star_rounded : Icons.star_border_rounded,
                color: const Color(0xFFF59E0B),
                size: 32,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('rating-submit'),
          onPressed: _stars == 0
              ? null
              : () => Navigator.of(context).pop(_stars),
          child: const Text('Rate'),
        ),
      ],
    );
  }
}
