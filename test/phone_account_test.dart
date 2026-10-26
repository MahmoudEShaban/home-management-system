import 'package:flutter_test/flutter_test.dart';
import 'package:homemanagement/data/phone_account.dart';

void main() {
  test('normalizes phone numbers', () {
    expect(normalizePhone('01001234567'), '201001234567');
    expect(normalizePhone('+20 100 123 4567'), '201001234567');
    expect(normalizePhone('00201001234567'), '201001234567');
    expect(normalizePhone('٠١٠٠١٢٣٤٥٦٧'), '201001234567');
    expect(normalizePhone('+44 7700 900123'), '447700900123');
    expect(normalizePhone('12ab'), isNull);
    expect(normalizePhone('123'), isNull);
  });

  test('phone sign-in address round trip', () {
    expect(phoneSignInAddress('201001234567'), 'p201001234567@phone.homemanagement.app');
    expect(displayPhone('201001234567'), '+201001234567');
  });
}
