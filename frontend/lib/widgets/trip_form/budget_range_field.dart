import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tactile_text_field.dart';
import 'trip_form_validators.dart';

/// Side-by-side min/max PHP budget inputs. [S2-04]
class BudgetRangeField extends StatelessWidget {
  final TextEditingController minController;
  final TextEditingController maxController;
  final String? minServerError;
  final String? maxServerError;

  const BudgetRangeField({
    super.key,
    required this.minController,
    required this.maxController,
    this.minServerError,
    this.maxServerError,
  });

  static final List<TextInputFormatter> _formatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TactileTextField(
            key: const ValueKey('trip-budget-min'),
            label: 'Min budget',
            controller: minController,
            hintText: '500',
            prefixText: '₱ ',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _formatters,
            textInputAction: TextInputAction.next,
            validator: TripFormValidators.budget,
            serverError: minServerError,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TactileTextField(
            key: const ValueKey('trip-budget-max'),
            label: 'Max budget',
            controller: maxController,
            hintText: '2,000',
            prefixText: '₱ ',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _formatters,
            textInputAction: TextInputAction.next,
            validator: (value) =>
                TripFormValidators.budgetMax(value, minController.text),
            serverError: maxServerError,
          ),
        ),
      ],
    );
  }
}
