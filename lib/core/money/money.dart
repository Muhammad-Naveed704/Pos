import 'dart:math' as math;

/// Money represented as integer minor units (for example, cents or paisa).
///
/// SQLite v1 stores monetary columns as REAL for migration compatibility, but
/// all application arithmetic happens here and is rounded once at the database
/// boundary. This avoids accumulating binary floating-point errors in totals.
class Money implements Comparable<Money> {
  const Money.fromMinor(this.minorUnits);

  factory Money.fromMajor(num value) => Money.fromMinor((value * 100).round());

  static const zero = Money.fromMinor(0);

  final int minorUnits;

  double get majorUnits => minorUnits / 100;

  Money operator +(Money other) =>
      Money.fromMinor(minorUnits + other.minorUnits);
  Money operator -(Money other) =>
      Money.fromMinor(minorUnits - other.minorUnits);
  Money operator -() => Money.fromMinor(-minorUnits);

  Money multiply(num factor) => Money.fromMinor((minorUnits * factor).round());

  Money clamp(Money minimum, Money maximum) =>
      Money.fromMinor(minorUnits.clamp(minimum.minorUnits, maximum.minorUnits));

  Money max(Money other) =>
      Money.fromMinor(math.max(minorUnits, other.minorUnits));

  @override
  int compareTo(Money other) => minorUnits.compareTo(other.minorUnits);

  @override
  bool operator ==(Object other) =>
      other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;

  @override
  String toString() => majorUnits.toStringAsFixed(2);
}
