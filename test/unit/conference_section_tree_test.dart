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

    test('excludes archived sections by default, includes with flag', () {
      final sections = [
        {'id': 1, 'section_title': 'Active', 'sort_order': 0, 'status': 'draft', 'parent_id': null},
        {'id': 2, 'section_title': 'Archived', 'sort_order': 1, 'status': 'archived', 'parent_id': null},
        {'id': 3, 'section_title': 'Archived caps', 'sort_order': 2, 'status': 'ARCHIVED', 'parent_id': null},
      ];

      final tree = buildConferenceSectionTree(sections);
      expect(tree.map((s) => s['id']), [1]);

      final withArchived =
          buildConferenceSectionTree(sections, includeArchived: true);
      expect(withArchived.map((s) => s['id']), [1, 2, 3]);
    });

    test('archived parent hides its subtree from the top level', () {
      final sections = [
        {'id': 1, 'section_title': 'Archived parent', 'sort_order': 0, 'status': 'archived', 'parent_id': null},
        {'id': 2, 'section_title': 'Child of archived', 'sort_order': 0, 'status': 'draft', 'parent_id': 1},
      ];

      final tree = buildConferenceSectionTree(sections);
      expect(tree, isEmpty);
    });

    test('includeChildren: false returns a flat top level', () {
      final sections = [
        {'id': 1, 'section_title': 'Parent', 'sort_order': 0, 'status': 'draft', 'parent_id': null},
        {'id': 2, 'section_title': 'Child', 'sort_order': 0, 'status': 'draft', 'parent_id': 1},
      ];

      final tree =
          buildConferenceSectionTree(sections, includeChildren: false);
      expect(tree.length, 1);
      expect(tree.first['children'], isEmpty);
    });

    test('parentId selects the children of that parent', () {
      final sections = [
        {'id': 1, 'section_title': 'Parent', 'sort_order': 0, 'status': 'draft', 'parent_id': null},
        {'id': 2, 'section_title': 'Child B', 'sort_order': 1, 'status': 'draft', 'parent_id': 1},
        {'id': 3, 'section_title': 'Child A', 'sort_order': 0, 'status': 'draft', 'parent_id': 1},
      ];

      final children = buildConferenceSectionTree(sections, parentId: 1);
      expect(children.map((s) => s['section_title']), ['Child A', 'Child B']);
    });

    test('coerces string ids/orders and defaults missing fields', () {
      final sections = [
        // String sort_order and id (as the API may return them).
        {'id': '20', 'section_title': 'Second', 'sort_order': '1', 'parent_id': null},
        {'id': '10', 'section_title': 'First', 'sort_order': '0', 'parent_id': null},
        // Missing sort_order sorts last; missing status defaults to draft.
        {'id': 5, 'section_title': 'No order', 'parent_id': null},
        // String parent_id attaches to the right parent.
        {'id': 30, 'section_title': 'Child', 'sort_order': 0, 'parent_id': '10'},
      ];

      final tree = buildConferenceSectionTree(sections);
      expect(tree.map((s) => s['section_title']), ['First', 'Second', 'No order']);
      expect(tree.first['children'].single['section_title'], 'Child');
    });

    test('equal sort orders fall back to id order', () {
      final sections = [
        {'id': 7, 'section_title': 'B', 'sort_order': 0, 'parent_id': null},
        {'id': 3, 'section_title': 'A', 'sort_order': 0, 'parent_id': null},
      ];

      final tree = buildConferenceSectionTree(sections);
      expect(tree.map((s) => s['id']), [3, 7]);
    });

    test('orphan children do not appear at the top level', () {
      final sections = [
        {'id': 1, 'section_title': 'Top', 'sort_order': 0, 'parent_id': null},
        {'id': 2, 'section_title': 'Orphan', 'sort_order': 0, 'parent_id': 999},
      ];

      final tree = buildConferenceSectionTree(sections);
      expect(tree.map((s) => s['id']), [1]);
    });

    test('does not mutate the input sections', () {
      final section = {
        'id': 1,
        'section_title': 'Parent',
        'sort_order': 0,
        'status': 'draft',
        'parent_id': null,
      };
      final sections = [
        section,
        {'id': 2, 'section_title': 'Child', 'sort_order': 0, 'status': 'draft', 'parent_id': 1},
      ];

      buildConferenceSectionTree(sections);

      expect(section.containsKey('children'), isFalse);
      expect(sections.length, 2);
    });
  });
}
