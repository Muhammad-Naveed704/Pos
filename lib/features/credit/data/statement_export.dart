import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money_format.dart';
import '../../reports/data/report_export.dart';
import '../domain/credit.dart';
import 'credit_service.dart';

const statementHeaders = [
  'Date',
  'Type',
  'Reference',
  'Debit',
  'Credit',
  'Balance',
  'User',
];

/// Customer ledger rows as text, opening balance first.
List<List<String>> statementRows(LedgerPage page, MoneyFormatter money) {
  final date = DateFormat('d MMM y HH:mm');
  return [
    ['', 'Opening balance', '', '', '', money.format(page.opening), ''],
    for (final row in page.rows)
      [
        date.format(row.entry.createdAt),
        LedgerType.label(row.entry.type),
        [
          row.entry.referenceNumber,
          if (row.entry.note.isNotEmpty) row.entry.note,
        ].where((s) => s.isNotEmpty).join(' · '),
        row.debit.minorUnits == 0 ? '' : money.format(row.debit),
        row.credit.minorUnits == 0 ? '' : money.format(row.credit),
        money.format(row.balance),
        row.userName ?? '',
      ],
  ];
}

/// Customer statement PDF (A4), rendered off the UI isolate.
Future<Uint8List> buildStatementPdf({
  required String businessName,
  required String storeName,
  required String period,
  required CustomerBalance balance,
  required LedgerPage page,
  required MoneyFormatter money,
}) {
  final customer = balance.customer;
  return generateReportPdf(
    ReportPdfData(
      title: 'Statement · ${customer.name}',
      businessName: businessName,
      storeName: storeName,
      period: period,
      kpis: [
        ('Opening balance', money.format(page.opening)),
        ('Charges', money.format(page.debit)),
        ('Payments & credits', money.format(page.credit)),
        ('Closing balance', money.format(page.closing)),
        ('Overdue now', money.format(balance.overdue)),
        (
          'Credit limit',
          '${money.format(balance.creditLimit)} (available ${money.format(balance.availableCredit)})',
        ),
      ],
      headers: statementHeaders,
      numeric: const [false, false, false, true, true, true, false],
      rows: statementRows(page, money),
      footnote: [
        if (customer.phone?.isNotEmpty ?? false) 'Phone ${customer.phone}',
        if (customer.address.isNotEmpty) customer.address,
        'Positive balance = amount owed to $businessName.',
      ].join(' · '),
    ),
  );
}
