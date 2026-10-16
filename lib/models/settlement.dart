import 'package:decimal/decimal.dart';

// A recorded payment between two members ("settle up").
class Settlement {
  const Settlement({
    required this.id,
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
    required this.occurredOn,
  });

  final String id;
  final String fromMemberId; // paid
  final String toMemberId; // received
  final Decimal amount;
  final DateTime occurredOn;

  factory Settlement.fromJson(Map<String, dynamic> json) => Settlement(
        id: json['id'] as String,
        fromMemberId: json['from_member'] as String,
        toMemberId: json['to_member'] as String,
        amount: Decimal.parse(json['amount'].toString()),
        occurredOn: DateTime.parse(json['occurred_on'] as String),
      );
}
