import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/fulfilment/excise_stamp.dart';

/// Asks for one excise stamp and returns the canonical value.
///
/// Returns null when the user cancels. The confirm action stays disabled
/// until the field is a valid stamp. Lowercase Latin letters are shown and
/// returned in uppercase.
Future<String?> showExciseStampDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _ExciseStampDialog(),
  );
}

class _ExciseStampDialog extends StatefulWidget {
  const _ExciseStampDialog();

  @override
  State<_ExciseStampDialog> createState() => _ExciseStampDialogState();
}

class _ExciseStampDialogState extends State<_ExciseStampDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _error = _message(value, reportEmpty: false));
  }

  void _confirm() {
    final normalized = ExciseStamp.normalize(_controller.text);
    if (normalized == null) {
      setState(() => _error = _message(_controller.text, reportEmpty: true));
      return;
    }
    Navigator.of(context).pop(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final normalized = ExciseStamp.normalize(_controller.text);
    return AlertDialog(
      key: const Key('excise-stamp-dialog'),
      title: const Text(AppStrings.exciseStampTitle),
      content: TextField(
        key: const Key('excise-stamp-field'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: const [ExciseStampInputFormatter()],
        onChanged: _onChanged,
        onSubmitted: (_) {
          if (normalized != null) _confirm();
        },
        decoration: InputDecoration(
          labelText: AppStrings.exciseStampLabel,
          hintText: AppStrings.exciseStampHint,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          key: const Key('excise-stamp-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.exciseStampCancel),
        ),
        FilledButton(
          key: const Key('excise-stamp-confirm'),
          onPressed: normalized == null ? null : _confirm,
          child: const Text(AppStrings.exciseStampConfirm),
        ),
      ],
    );
  }
}

String? _message(String value, {required bool reportEmpty}) {
  if (value.isEmpty) {
    return reportEmpty ? AppStrings.exciseStampMissing : null;
  }
  if (ExciseStamp.normalize(value) == null) {
    return AppStrings.exciseStampInvalid;
  }
  return null;
}

/// Keeps an excise stamp field in the shape `AAAA999999` while it is typed.
///
/// Positions 1–4 accept Latin letters and show them in uppercase. Positions
/// 5–10 accept digits. Anything else is dropped, including Cyrillic letters
/// and spaces. The field never grows past 10 characters. A deletion or
/// replacement in one section leaves the other section in place.
class ExciseStampInputFormatter extends TextInputFormatter {
  const ExciseStampInputFormatter();

  static const letterSlots = 4;
  static const digitSlots = 6;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text == oldValue.text) return newValue;

    final oldText = oldValue.text;
    final edit = _span(oldText, newValue.text);
    final pasted = _fromScratch(edit.inserted);
    if (ExciseStamp.isValid(pasted.text)) {
      return _collapsed(pasted.text, pasted.cursor);
    }

    final letters = _lettersOf(oldText);
    final digits = oldText.substring(letters.length);
    if (oldText.isEmpty || (edit.start == 0 && edit.oldEnd == oldText.length)) {
      return _collapsed(pasted.text, pasted.cursor);
    }

    final spansBoth =
        edit.start < letters.length && edit.oldEnd > letters.length;
    if (spansBoth) {
      final built = _applySpan(
        letters: letters,
        digits: digits,
        start: edit.start,
        oldEnd: edit.oldEnd,
        inserted: edit.inserted,
      );
      if (built.text == oldText) return oldValue;
      return _collapsed(built.text, built.cursor);
    }

    final atBoundary =
        edit.start == letters.length && edit.oldEnd == letters.length;
    final intoLetters =
        edit.oldEnd <= letters.length &&
        (!atBoundary || _startsWithLetter(edit.inserted));
    if (intoLetters) {
      final applied = _applySegment(
        current: letters,
        max: letterSlots,
        localStart: edit.start,
        localEnd: edit.oldEnd,
        inserted: edit.inserted,
        accept: _letter,
      );
      final text = applied.text + digits;
      if (text == oldText) return oldValue;
      return _collapsed(text, applied.cursor);
    }

    final applied = _applySegment(
      current: digits,
      max: digitSlots,
      localStart: edit.start - letters.length,
      localEnd: edit.oldEnd - letters.length,
      inserted: edit.inserted,
      accept: _digit,
    );
    final text = letters + applied.text;
    if (text == oldText) return oldValue;
    return _collapsed(text, letters.length + applied.cursor);
  }
}

TextEditingValue _collapsed(String text, int cursor) {
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: cursor.clamp(0, text.length)),
  );
}

({int start, int oldEnd, String inserted}) _span(
  String oldText,
  String newText,
) {
  var start = 0;
  final oldLength = oldText.length;
  final newLength = newText.length;
  while (start < oldLength &&
      start < newLength &&
      oldText.codeUnitAt(start) == newText.codeUnitAt(start)) {
    start++;
  }
  var oldEnd = oldLength;
  var newEnd = newLength;
  while (oldEnd > start &&
      newEnd > start &&
      oldText.codeUnitAt(oldEnd - 1) == newText.codeUnitAt(newEnd - 1)) {
    oldEnd--;
    newEnd--;
  }
  return (
    start: start,
    oldEnd: oldEnd,
    inserted: newText.substring(start, newEnd),
  );
}

String _lettersOf(String value) {
  var count = 0;
  while (count < value.length &&
      count < ExciseStampInputFormatter.letterSlots &&
      _letter(value.codeUnitAt(count)) == value.codeUnitAt(count)) {
    count++;
  }
  return value.substring(0, count);
}

bool _startsWithLetter(String value) {
  if (value.isEmpty) return false;
  return _letter(value.codeUnitAt(0)) != null;
}

int? _letter(int code) {
  if (code >= 0x61 && code <= 0x7A) return code - 0x20;
  if (code >= 0x41 && code <= 0x5A) return code;
  return null;
}

int? _digit(int code) {
  if (code >= 0x30 && code <= 0x39) return code;
  return null;
}

({String text, int cursor}) _fromScratch(String raw) {
  final letters = StringBuffer();
  final digits = StringBuffer();
  var digitsStarted = false;
  for (final code in raw.codeUnits) {
    if (!digitsStarted &&
        letters.length < ExciseStampInputFormatter.letterSlots) {
      final letter = _letter(code);
      if (letter != null) {
        letters.writeCharCode(letter);
        continue;
      }
      final digit = _digit(code);
      if (digit != null && letters.isNotEmpty) {
        digitsStarted = true;
        digits.writeCharCode(digit);
      }
      continue;
    }
    digitsStarted = true;
    final digit = _digit(code);
    if (digit != null && digits.length < ExciseStampInputFormatter.digitSlots) {
      digits.writeCharCode(digit);
    }
  }
  final text = letters.toString() + digits.toString();
  return (text: text, cursor: text.length);
}

({String text, int cursor}) _applySegment({
  required String current,
  required int max,
  required int localStart,
  required int localEnd,
  required String inserted,
  required int? Function(int code) accept,
}) {
  final start = localStart.clamp(0, current.length);
  final end = localEnd.clamp(start, current.length);
  final prefix = current.substring(0, start);
  final suffix = current.substring(end);
  final available = max - prefix.length - suffix.length;
  if (available <= 0 && start == end) {
    return (text: current, cursor: start);
  }
  final accepted = StringBuffer();
  for (final code in inserted.codeUnits) {
    if (accepted.length >= available) break;
    final mapped = accept(code);
    if (mapped == null) continue;
    accepted.writeCharCode(mapped);
  }
  return (
    text: prefix + accepted.toString() + suffix,
    cursor: prefix.length + accepted.length,
  );
}

({String text, int cursor}) _applySpan({
  required String letters,
  required String digits,
  required int start,
  required int oldEnd,
  required String inserted,
}) {
  final letterPrefix = letters.substring(0, start);
  final removedDigits = oldEnd - letters.length;
  final digitSuffix = digits.substring(removedDigits.clamp(0, digits.length));
  final letterRoom =
      ExciseStampInputFormatter.letterSlots - letterPrefix.length;
  final acceptedLetters = StringBuffer();
  final codes = inserted.codeUnits;
  var index = 0;
  while (index < codes.length && acceptedLetters.length < letterRoom) {
    final letter = _letter(codes[index]);
    if (letter != null) {
      acceptedLetters.writeCharCode(letter);
      index++;
      continue;
    }
    if (_digit(codes[index]) != null) break;
    index++;
  }
  final digitRoom = ExciseStampInputFormatter.digitSlots - digitSuffix.length;
  final acceptedDigits = StringBuffer();
  while (index < codes.length && acceptedDigits.length < digitRoom) {
    final digit = _digit(codes[index]);
    if (digit != null) acceptedDigits.writeCharCode(digit);
    index++;
  }
  final nextLetters = letterPrefix + acceptedLetters.toString();
  final nextDigits = acceptedDigits.toString() + digitSuffix;
  return (
    text: nextLetters + nextDigits,
    cursor: nextLetters.length + acceptedDigits.length,
  );
}
