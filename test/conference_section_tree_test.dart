import 'package:flutter_test/flutter_test.dart';
import 'package:lions_app_3/conference_section_tree.dart';

void main() {
  group('buildConferenceSectionTree', () {
    test('builds parent-child nesting and keeps sort order', () {
      final sections = [
        {
          'id': 10,
          'section_title': 'Parent 1',
          'sort_order': 0,
          'status': 'draft',
          'parent_id': null,
        },
        {
          'id': 11,
          'section_title': 'Child 1',
          'sort_order': 0,
          'status': 'draft',
          'parent_id': 10,
        },
        {
          'id': 12,
          'section_title': 'Child 2',
          'sort_order': 1,
          'status': 'draft',
          'parent_id': 10,
        },
        {
          'id': 13,
          'section_title': 'Parent 2',
          'sort_order': 1,
          'status': 'draft',
          'parent_id': null,
        },
      ];

      final tree = buildConferenceSectionTree(sections);

      expect(tree.length, 2);
      expect(tree.first['section_title'], 'Parent 1');
      expect(tree.first['children'].length, 2);
      expect(tree.first['children'].first['section_title'], 'Child 1');
      expect(tree.first['children'].last['section_title'], 'Child 2');
      expect(tree.last['section_title'], 'Parent 2');
    });
  });
}
