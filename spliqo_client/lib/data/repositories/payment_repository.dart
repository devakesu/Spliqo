import 'package:spliqo/data/datasources/api_client.dart';
import 'package:spliqo/domain/models/session.dart';

/// Repository managing payment intents, preference updates, and host confirmations.
class PaymentRepository {
  new({required this._apiClient});

  final ApiClient _apiClient;

  /// Fetch server-assembled upi://pay URI intent (Section 11.2 of Standards).
  Future<String> getPaymentIntent(String sessionId) async {
    final response = await _apiClient.get('/sessions/$sessionId/payment-intent');
    return response['intent_uri'] as String;
  }

  /// Update payment preference (self_pay or host_pays).
  Future<SettlementModel> updatePaymentPreference({
    required String sessionId,
    required PayPreference preference,
  }) async {
    final response = await _apiClient.patch(
      '/sessions/$sessionId/payment-preference',
      body: {'preference': preference.toApiString()},
    );
    return SettlementModel.fromJson(response);
  }

  /// Participant marks 'I have paid' for host verification.
  Future<SettlementModel> markPaymentPending(String sessionId) async {
    final response = await _apiClient.post('/sessions/$sessionId/payment-pending');
    return SettlementModel.fromJson(response);
  }

  /// Host confirms receipt (paid) or waives participant share.
  Future<SettlementModel> confirmPayment({
    required String sessionId,
    required String targetParticipantId,
    required String action, // 'confirm_paid' or 'confirm_waived'
  }) async {
    final response = await _apiClient.post(
      '/sessions/$sessionId/payment-confirm',
      body: {
        'target_participant_id': targetParticipantId,
        'action': action,
      },
    );
    return SettlementModel.fromJson(response);
  }

  /// Host saves encrypted payout UPI ID via Backend FLE table.
  Future<void> setPayoutProfile(String upiId) async {
    await _apiClient.post(
      '/payout-profile',
      body: {'upi_id': upiId},
    );
  }
}
