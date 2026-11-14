/// Presentation only. Saved provenance, amounts and history stay unchanged.
String displayCopy(String value) => value
    .replaceAll(RegExp(r'\[(?:demo|sample)\]\s*', caseSensitive: false), '')
    .replaceAll('Demo payment', 'Payment')
    .replaceAll('demo payment', 'payment')
    .replaceAll('Demo Card', 'Card')
    .replaceAll('Demo FPX', 'FPX')
    .replaceAll('Demo Wallet', 'Wallet')
    .replaceAll('demo protection pool', 'protection fund')
    .replaceAll('local demonstration network', 'local test network');
