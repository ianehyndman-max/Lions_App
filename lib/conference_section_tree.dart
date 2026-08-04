int? _coerceSectionInt(dynamic value) => int.tryParse(value?.toString() ?? '');

Map<String, dynamic> _copySection(Map<String, dynamic> section) {
  final copy = Map<String, dynamic>.from(section);
  copy['children'] = <Map<String, dynamic>>[];
  return copy;
}

List<Map<String, dynamic>> buildConferenceSectionTree(
  List<Map<String, dynamic>> sections, {
  bool includeArchived = false,
  bool includeChildren = true,
  int? parentId,
}) {
  final filtered = sections.where((section) {
    if (!includeArchived) {
      final status = (section['status'] ?? 'draft').toString().toLowerCase();
      if (status == 'archived') return false;
    }
    if (parentId == null) {
      return _coerceSectionInt(section['parent_id']) == null;
    }
    return _coerceSectionInt(section['parent_id']) == parentId;
  }).toList();

  filtered.sort((a, b) {
    final aOrder = _coerceSectionInt(a['sort_order']) ?? 1 << 30;
    final bOrder = _coerceSectionInt(b['sort_order']) ?? 1 << 30;
    if (aOrder != bOrder) return aOrder.compareTo(bOrder);

    final aId = _coerceSectionInt(a['id']) ?? 1 << 30;
    final bId = _coerceSectionInt(b['id']) ?? 1 << 30;
    return aId.compareTo(bId);
  });

  final normalized = filtered.map(_copySection).toList();

  if (!includeChildren) {
    return normalized;
  }

  final childrenByParent = <int, List<Map<String, dynamic>>>{};
  for (final section in normalized) {
    final sectionId = _coerceSectionInt(section['id']);
    if (sectionId == null) continue;

    final childSections = buildConferenceSectionTree(
      sections,
      includeArchived: includeArchived,
      includeChildren: true,
      parentId: sectionId,
    );
    if (childSections.isNotEmpty) {
      childrenByParent[sectionId] = childSections;
    }
  }

  return normalized.map((section) {
    final sectionId = _coerceSectionInt(section['id']);
    if (sectionId == null) {
      return section;
    }
    final children = childrenByParent[sectionId] ?? <Map<String, dynamic>>[];
    section['children'] = children;
    return section;
  }).toList();
}
