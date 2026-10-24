// Present so `flutter create .` does not generate its default counter-app test.
import 'package:flutter_test/flutter_test.dart';
import 'package:homemanagement/l10n/strings.dart';
import 'package:homemanagement/ui/common.dart';

void main() {
  test('Arabic and English strings differ', () {
    expect(const L10n(false).expenses, 'Expenses');
    expect(const L10n(true).expenses, 'المصروفات');
    expect(const L10n(true).developedBy, 'تم التطوير بواسطة محمود عصام');
  });

  test('parses Arabic-Indic digits and thousands separators', () {
    expect(parseNumber('١٢٬٥٠٠'), 12500);
    expect(parseNumber('1,250.5'), 1250.5);
    expect(parseNumber('abc'), isNull);
  });
}
