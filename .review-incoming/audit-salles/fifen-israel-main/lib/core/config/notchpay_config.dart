class NotchPayConfig {
  static const String publicKey = String.fromEnvironment(
    'NOTCHPAY_PUBLIC_KEY',
    defaultValue: '',
  );

  static const String apiUrl = 'https://api.notchpay.co';

  static bool get isConfigured => publicKey.isNotEmpty;
}
