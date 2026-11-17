import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Local Offline Search Tests', () {
    final mockInboxItems = [
      {'id': '1', 'raw_text': 'Buy teff from Mercato', 'category': 'task'},
      {
        'id': '2',
        'raw_text': 'Pay Ethio Telecom fiber bill',
        'category': 'expense'
      },
      {'id': '3', 'raw_text': 'የአማርኛ ንባብ ማስታወሻ', 'category': 'note'},
    ];

    test('Searches English text case-insensitively', () {
      const query = 'mercato';
      final matches = mockInboxItems
          .where((i) => (i['raw_text'] as String)
              .toLowerCase()
              .contains(query.toLowerCase()))
          .toList();

      expect(matches.length, 1);
      expect(matches.first['id'], '1');
    });

    test('Searches Amharic Unicode text faithfully', () {
      const query = 'ማስታወሻ';
      final matches = mockInboxItems
          .where((i) => (i['raw_text'] as String).contains(query))
          .toList();

      expect(matches.length, 1);
      expect(matches.first['id'], '3');
    });
  });
}
