/// ISBN is an identifier, not a number: keep leading zeros and the ISBN-10 X.
String? validateOptionalIsbn(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final isbn = value.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (RegExp(r'^\d{9}[\dX]$').hasMatch(isbn)) {
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      sum += (isbn[i] == 'X' ? 10 : int.parse(isbn[i])) * (10 - i);
    }
    if (sum % 11 == 0) return null;
  }
  if (RegExp(r'^97[89]\d{10}$').hasMatch(isbn)) {
    var sum = 0;
    for (var i = 0; i < 13; i++) {
      sum += int.parse(isbn[i]) * (i.isOdd ? 3 : 1);
    }
    if (sum % 10 == 0) return null;
  }
  return 'Enter a valid ISBN-10 or ISBN-13, or leave this empty.';
}
