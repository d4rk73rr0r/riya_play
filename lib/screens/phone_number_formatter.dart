import 'package:flutter/services.dart';

class PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length < oldValue.text.length) {
      // Backspace bosilganda eski qiymatni qaytarish
      return newValue;
    }

    String text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 9) text = text.substring(0, 9);

    String formatted = '';
    if (text.isNotEmpty) {
      if (text.length >= 2) {
        formatted += '(${text.substring(0, 2)})';
        if (text.length > 2) {
          formatted += text.substring(2, text.length > 5 ? 5 : text.length);
          if (text.length > 5) {
            formatted += '-${text.substring(5, text.length > 7 ? 7 : text.length)}';
          }
          if (text.length > 7) formatted += '-${text.substring(7)}';
        }
      } else {
        formatted += '(${text}';
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}