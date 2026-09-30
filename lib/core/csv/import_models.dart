enum ImportAction { create, update, skip, error }

/// Validation result for one CSV row.
class ImportRowResult {
  const ImportRowResult({
    required this.line,
    required this.action,
    required this.label,
    this.messages = const [],
  });

  final int line;
  final ImportAction action;

  /// Short identification of the row, e.g. "SKU-1 · Tea 500g".
  final String label;
  final List<String> messages;
}

/// Everything shown before the user confirms an import.
class ImportPreview {
  const ImportPreview({required this.rows, this.notes = const []});

  final List<ImportRowResult> rows;

  /// Extra information, e.g. "3 new categories will be created: …".
  final List<String> notes;

  int count(ImportAction action) =>
      rows.where((row) => row.action == action).length;

  bool get hasWork =>
      count(ImportAction.create) + count(ImportAction.update) > 0;
}

class ImportOutcome {
  const ImportOutcome({
    this.created = 0,
    this.updated = 0,
    this.skipped = 0,
    this.extra = const [],
  });
  final int created;
  final int updated;
  final int skipped;
  final List<String> extra;
}

class ImportFormatException implements Exception {
  const ImportFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}
