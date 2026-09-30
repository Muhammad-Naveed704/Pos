import 'package:csv/csv.dart';

import '../money/money_format.dart';

/// A decoded CSV file with normalised headers.
class CsvTable {
  const CsvTable(this.headers, this.rows);

  /// Normalised header names (lower_snake_case).
  final List<String> headers;

  /// Each row keyed by normalised header. Missing cells are absent.
  final List<CsvRow> rows;

  bool has(String header) => headers.contains(header);
}

class CsvRow {
  const CsvRow(this.line, this.values);

  /// 1-based line number in the source file (header is line 1).
  final int line;
  final Map<String, String> values;

  String text(String key) => (values[key] ?? '').trim();

  String? optional(String key) {
    final value = text(key);
    return value.isEmpty ? null : value;
  }

  /// Parses a number; CSV files may use either `.` or `,` as decimal mark.
  double? number(String key) {
    final value = text(key);
    if (value.isEmpty) return null;
    return parseAmount(value, decimalSeparator: '.');
  }

  /// Accepts yes/no, true/false, 1/0, y/n, active/inactive.
  bool? flag(String key) {
    final value = text(key).toLowerCase();
    if (value.isEmpty) return null;
    if (const {'yes', 'y', 'true', '1', 'active', 'on'}.contains(value)) {
      return true;
    }
    if (const {'no', 'n', 'false', '0', 'inactive', 'off'}.contains(value)) {
      return false;
    }
    return null;
  }

  bool get isBlank => values.values.every((value) => value.trim().isEmpty);
}

String normalizeHeader(String header) => header
    .replaceAll('﻿', '')
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

/// Decodes CSV text. [aliases] maps alternative header spellings to the
/// canonical header, e.g. `{'price': 'sale_price'}`.
CsvTable parseCsvTable(String text, {Map<String, String> aliases = const {}}) {
  final source = text.startsWith('﻿') ? text.substring(1) : text;
  final decoded = Csv(skipEmptyLines: true).decode(source);
  if (decoded.isEmpty) return const CsvTable([], []);
  final headers = [
    for (final cell in decoded.first)
      () {
        final normalized = normalizeHeader('$cell');
        return aliases[normalized] ?? normalized;
      }(),
  ];
  final rows = <CsvRow>[];
  for (var index = 1; index < decoded.length; index++) {
    final cells = decoded[index];
    final values = <String, String>{};
    for (var column = 0; column < headers.length; column++) {
      if (column < cells.length && headers[column].isNotEmpty) {
        values[headers[column]] = '${cells[column] ?? ''}';
      }
    }
    final row = CsvRow(index + 1, values);
    if (!row.isBlank) rows.add(row);
  }
  return CsvTable(headers, rows);
}

/// Encodes rows as Excel-friendly CSV (UTF-8 BOM, CRLF).
String encodeCsv(List<List<Object?>> rows) => Csv(addBom: true).encode([
  for (final row in rows) [for (final cell in row) cell ?? ''],
]);
