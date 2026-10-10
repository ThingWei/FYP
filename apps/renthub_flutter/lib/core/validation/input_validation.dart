import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum InputKind {
  text,
  email,
  password,
  integer,
  decimal,
  money,
  phone,
  digits,
  referral,
  date,
  time,
  licenceClasses,
  rewards
}

/// A field's format and business limits, independent of its presentation.
class InputRule {
  const InputRule(this.label,
      {this.kind = InputKind.text,
      this.optional = false,
      this.minLength = 1,
      this.maxLength = 2000,
      this.min = 0,
      this.max,
      this.exactLength});
  final String label;
  final InputKind kind;
  final bool optional;
  final int minLength;
  final int maxLength;
  final num min;
  final num? max;
  final int? exactLength;

  String? validate(String? input) {
    final raw = input ?? '';
    final value = kind == InputKind.password ? raw : raw.trim();
    if (value.isEmpty) return optional ? null : '$label is required';
    if (value.runes.length > maxLength) {
      return '$label must be at most $maxLength characters';
    }
    if (value.runes.length < minLength) {
      return '$label needs at least $minLength characters';
    }
    if (RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]').hasMatch(value)) {
      return '$label contains unsupported control characters';
    }
    switch (kind) {
      case InputKind.integer:
      case InputKind.decimal:
      case InputKind.money:
        final pattern = kind == InputKind.integer
            ? r'^\d+$'
            : kind == InputKind.money
                ? r'^\d+(?:\.\d{1,2})?$'
                : r'^\d+(?:\.\d+)?$';
        final number = num.tryParse(value);
        if (!RegExp(pattern).hasMatch(value) ||
            number == null ||
            !number.isFinite) {
          return kind == InputKind.integer
              ? 'Enter a whole number for $label'
              : kind == InputKind.money
                  ? 'Enter $label with at most 2 decimal places'
                  : 'Enter a valid number for $label';
        }
        if (kind == InputKind.money && number * 100 > 9007199254740991) {
          return '$label is too large to represent safely';
        }
        if (kind == InputKind.integer && number > 9007199254740991) {
          return '$label must be a safely representable whole number';
        }
        if (number < min || max != null && number > max!) {
          return max == null
              ? '$label must be at least $min'
              : '$label must be between $min and $max';
        }
      case InputKind.email:
        if (!InputValidation.isEmail(value)) {
          return 'Enter a valid email address';
        }
      case InputKind.phone:
        if (!InputValidation.isMalaysianMobile(value)) {
          return 'Enter a valid Malaysian mobile number (01… or +601…)';
        }
      case InputKind.digits:
        if (!RegExp(r'^\d+$').hasMatch(value) ||
            exactLength != null && value.length != exactLength) {
          return '$label must contain ${exactLength ?? 'only'} digits';
        }
      case InputKind.referral:
        if (!RegExp(r'^RH-[A-Z0-9]{5,20}$').hasMatch(value.toUpperCase())) {
          return 'Enter a code such as RH-MEMBER1234';
        }
      case InputKind.date:
        final parsed = DateTime.tryParse(value);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
            parsed == null ||
            '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}' !=
                value) {
          return 'Enter a valid date as YYYY-MM-DD';
        }
      case InputKind.time:
        if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
          return 'Enter a valid time as HH:MM';
        }
      case InputKind.licenceClasses:
        final classes = value
            .toUpperCase()
            .split(RegExp(r'[,/\s]+'))
            .where((c) => c.isNotEmpty)
            .toList();
        const allowed = {
          'A',
          'A1',
          'B',
          'B1',
          'B2',
          'C',
          'D',
          'DA',
          'E',
          'E1',
          'E2',
          'F',
          'G',
          'H',
          'I'
        };
        if (classes.isEmpty ||
            classes.any((c) => !allowed.contains(c)) ||
            classes.toSet().length != classes.length) {
          return 'Enter valid, unique licence classes, such as D, B2';
        }
      case InputKind.rewards:
        if (!InputValidation.validRewards(value)) {
          return 'Use 1–10 unique points:RM pairs, such as 500:5, 1000:10';
        }
      case InputKind.text:
      case InputKind.password:
        break;
    }
    return null;
  }

  List<TextInputFormatter> get formatters => switch (kind) {
        InputKind.integer => [
            StrictInputFormatter(r'^\d*$', maxLength: maxLength)
          ],
        InputKind.digits => [
            StrictInputFormatter(r'^\d*$', maxLength: exactLength ?? maxLength)
          ],
        InputKind.money => [
            StrictInputFormatter(r'^\d*(?:\.\d{0,2})?$', maxLength: maxLength)
          ],
        InputKind.decimal => [
            StrictInputFormatter(r'^\d*(?:\.\d*)?$', maxLength: maxLength)
          ],
        InputKind.phone => [
            StrictInputFormatter(r'^\+?[0-9 -]*$', maxLength: maxLength)
          ],
        InputKind.date => [StrictInputFormatter(r'^[0-9-]*$', maxLength: 10)],
        InputKind.time => [StrictInputFormatter(r'^[0-9:]*$', maxLength: 5)],
        _ => const [],
      };
}

/// Rejects the entire invalid edit, including mixed pastes. Each field owns its
/// formatter instance so IME composition can return to its last committed value.
class StrictInputFormatter extends TextInputFormatter {
  StrictInputFormatter(String pattern, {this.maxLength = 30})
      : pattern = RegExp(pattern);
  final RegExp pattern;
  final int maxLength;
  TextEditingValue? _committed;
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (oldValue.composing.isCollapsed &&
        pattern.hasMatch(oldValue.text) &&
        oldValue.text.length <= maxLength) {
      _committed = oldValue;
    }
    if (!newValue.composing.isCollapsed) return newValue;
    if (newValue.text.length <= maxLength && pattern.hasMatch(newValue.text)) {
      _committed = newValue;
      return newValue;
    }
    return _committed ?? const TextEditingValue();
  }
}

class InputValidation {
  // Numeric formatters enforce edit lengths themselves. Text/password length
  // errors must not silently truncate pasted content or active composition.
  static const lengthEnforcement = MaxLengthEnforcement.none;

  /// Wait until a dialog's widgets are unmounted before its caller disposes
  /// local controllers. TextFormField can rebuild during the exit animation.
  static Future<T?> showFormDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    );
    final result = await navigator.push(route);
    await route.completed;
    return result;
  }

  static final _formatters = Expando<Map<String, List<TextInputFormatter>>>();
  static List<TextInputFormatter> formatters(
      InputRule rule, TextEditingController? controller) {
    if (controller == null) return rule.formatters;
    final cache = _formatters[controller] ??= {};
    final key = '${rule.kind}:${rule.maxLength}:${rule.exactLength}';
    return cache.putIfAbsent(key, () => rule.formatters);
  }

  static bool isEmail(String value) {
    if (value.length > 254 || RegExp(r'\s').hasMatch(value)) return false;
    final parts = value.split('@');
    if (parts.length != 2 ||
        parts[0].isEmpty ||
        parts[0].length > 64 ||
        parts[0].startsWith('.') ||
        parts[0].endsWith('.') ||
        parts[0].contains('..') ||
        !RegExp(r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+$").hasMatch(parts[0])) {
      return false;
    }
    final labels = parts[1].split('.');
    return labels.length >= 2 &&
        RegExp(r'^[a-zA-Z]{2,63}$').hasMatch(labels.last) &&
        labels.every((label) =>
            RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$')
                .hasMatch(label));
  }

  static bool isMalaysianMobile(String value) =>
      RegExp(r'^(\+?60|0)1(([0145]\d{7,8})|([236-9]\d{7}))$')
          .hasMatch(value.replaceAll(RegExp(r'[ -]'), ''));

  static bool validRewards(String value) {
    final rows = value.split(',');
    if (rows.isEmpty || rows.length > 10) return false;
    final costs = <int>{};
    for (final row in rows) {
      final parts = row.split(':');
      if (parts.length != 2 ||
          const InputRule('Points',
                      kind: InputKind.integer, min: 1, max: 100000)
                  .validate(parts[0]) !=
              null ||
          const InputRule('Reward',
                      kind: InputKind.money, min: 0.01, max: 10000)
                  .validate(parts[1]) !=
              null) {
        return false;
      }
      if (!costs.add(int.parse(parts[0].trim()))) return false;
    }
    return true;
  }

  static FormFieldValidator<String> compose(FormFieldValidator<String> first,
          FormFieldValidator<String>? second) =>
      (value) => second?.call(value) ?? first(value);

  /// Validates standalone fields in a page/dialog as well as fields in Forms.
  /// Call before closing a dialog or performing a mutation, never on Cancel.
  static bool validate(BuildContext context) {
    var valid = true;
    void visit(Element element) {
      if (element is StatefulElement && element.state is FormFieldState) {
        final field = element.state as FormFieldState;
        if (field.widget.enabled && !field.validate()) valid = false;
      } else {
        element.visitChildren(visit);
      }
    }

    (context as Element).visitChildren(visit);
    return valid;
  }

  static void popIfValid<T>(BuildContext context, T result) {
    if (validate(context)) Navigator.pop(context, result);
  }
}
