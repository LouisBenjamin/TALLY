import 'package:decimal/decimal.dart';

// One line of a group's activity feed. Written only by database triggers
// (0016), with names baked into [summary] when the change happened.
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.summary,
    this.amount,
    required this.createdAt,
  });

  final String id;
  final String summary;
  final Decimal? amount;
  final DateTime createdAt;

  factory ActivityEntry.fromJson(Map<String, dynamic> json) => ActivityEntry(
        id: json['id'] as String,
        summary: json['summary'] as String,
        amount: json['amount'] == null
            ? null
            : Decimal.parse(json['amount'].toString()),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
