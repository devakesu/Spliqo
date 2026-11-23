/// Server-assembled UPI Payment Intent payload conforming to STANDARDS.md Section 11.2.
class PaymentIntentModel {
  const new({
    required this.upiUri,
    required this.hostVpa,
    required this.amountPaise,
    required this.formattedAmount,
    required this.payeeName,
  });

  factory fromJson(Map<String, dynamic> json) {
    return PaymentIntentModel(
      upiUri: (json['upi_uri'] ?? json['intent_uri'] ?? '') as String,
      hostVpa: (json['host_vpa'] ?? '') as String,
      amountPaise: (json['amount_paise'] as num?)?.toInt() ?? 0,
      formattedAmount: (json['formatted_amount'] ?? '') as String,
      payeeName: (json['payee_name'] ?? '') as String,
    );
  }

  final String upiUri;
  final String hostVpa;
  final int amountPaise;
  final String formattedAmount;
  final String payeeName;
}
