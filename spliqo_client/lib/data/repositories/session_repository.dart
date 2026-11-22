import 'package:spliqo/core/errors/failures.dart';
import 'package:spliqo/data/datasources/api_client.dart';
import 'package:spliqo/domain/models/session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository managing sessions, bill items, item claims, and participants.
/// Implements Two-Path Architecture: Direct Path (Supabase) + Backend Path (FastAPI).
class SessionRepository {
  new({
    required this._apiClient,
    required this._supabaseClient,
  });

  final ApiClient _apiClient;
  final SupabaseClient _supabaseClient;

  // ---------------------------------------------------------------------------
  // Backend Path Operations (FastAPI)
  // ---------------------------------------------------------------------------

  /// Upload receipt image and parse via Gemini Vision (Screen 1).
  Future<Map<String, dynamic>> parseReceipt({
    required List<int> imageBytes,
    required String filename,
    required String hostDisplayName,
  }) async {
    return await _apiClient.postMultipart(
      '/sessions/parse',
      fileBytes: imageBytes,
      filename: filename,
      fieldName: 'file',
      fields: {'host_display_name': hostDisplayName},
    );
  }

  /// Create a draft session manually (Screen 1 fallback).
  Future<SessionModel> createDraftSession(Map<String, dynamic> draftData) async {
    final response = await _apiClient.post('/sessions/draft', body: draftData);
    return SessionModel.fromJson(response);
  }

  /// Host updates draft session items and adjustments (Screen 1).
  Future<SessionModel> updateDraftSession(
    String sessionId,
    Map<String, dynamic> draftData,
  ) async {
    final response = await _apiClient.put(
      '/sessions/$sessionId/draft',
      body: draftData,
    );
    return SessionModel.fromJson(response);
  }

  /// Host activates draft session -> active (Screen 1 CTA).
  Future<SessionModel> activateSession(String sessionId) async {
    final response = await _apiClient.post('/sessions/$sessionId/activate');
    return SessionModel.fromJson(response);
  }

  /// Host bulk resolves unclaimed items during reviewing phase (Screen 3).
  Future<Map<String, dynamic>> resolveUnclaimed({
    required String sessionId,
    required String action,
    String? targetParticipantId,
    List<String>? itemIds,
  }) async {
    final body = <String, dynamic>{
      'action': action,
      'target_participant_id': ?targetParticipantId,
      'item_ids': ?itemIds,
    };
    return await _apiClient.post('/sessions/$sessionId/resolve-unclaimed', body: body);
  }

  /// Host authoritatively finalizes session and settles shares (Screen 3 CTA).
  Future<Map<String, dynamic>> finalizeSession(String sessionId) async {
    return await _apiClient.post('/sessions/$sessionId/finalize');
  }

  // ---------------------------------------------------------------------------
  // Direct Path Operations (Supabase PostgREST & RPC)
  // ---------------------------------------------------------------------------

  /// Fetch full session details directly through RLS.
  Future<SessionModel> fetchSession(String sessionId) async {
    try {
      final sessionRow = await _supabaseClient
          .from('sessions')
          .select()
          .eq('id', sessionId)
          .single();

      final itemsRows = await _supabaseClient
          .from('bill_items')
          .select()
          .eq('session_id', sessionId)
          .order('position');

      final fullData = Map<String, dynamic>.from(sessionRow);
      fullData['items'] = itemsRows;
      return SessionModel.fromJson(fullData);
    } catch (e) {
      throw Failure(
        code: 'session_fetch_failed',
        message: 'Could not fetch session: $e',
      );
    }
  }

  /// Fetch participants in a session.
  Future<List<ParticipantModel>> fetchParticipants(String sessionId) async {
    try {
      final rows = await _supabaseClient
          .from('session_participants')
          .select()
          .eq('session_id', sessionId)
          .order('joined_at');

      return (rows as List<dynamic>)
          .map((r) => ParticipantModel.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Failure(
        code: 'participants_fetch_failed',
        message: 'Could not fetch participants: $e',
      );
    }
  }

  /// Fetch all active item claims for a session.
  Future<List<ClaimModel>> fetchClaims(String sessionId) async {
    try {
      final rows = await _supabaseClient
          .from('item_claims')
          .select()
          .eq('session_id', sessionId);

      return (rows as List<dynamic>)
          .map((r) => ClaimModel.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Failure(
        code: 'claims_fetch_failed',
        message: 'Could not fetch claims: $e',
      );
    }
  }

  /// Fetch settlement rows for a session.
  Future<List<SettlementModel>> fetchSettlements(String sessionId) async {
    try {
      final rows = await _supabaseClient
          .from('participant_settlements')
          .select()
          .eq('session_id', sessionId);

      return (rows as List<dynamic>)
          .map((r) => SettlementModel.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Failure(
        code: 'settlements_fetch_failed',
        message: 'Could not fetch settlements: $e',
      );
    }
  }

  /// Direct-path claim insertion guarded by database RLS and triggers.
  Future<void> claimItem({
    required String sessionId,
    required String itemId,
    required String participantId,
  }) async {
    try {
      await _supabaseClient.from('item_claims').insert({
        'session_id': sessionId,
        'item_id': itemId,
        'participant_id': participantId,
      });
    } catch (e) {
      throw Failure(
        code: 'claim_rejected',
        message: 'Claim could not be saved: $e',
      );
    }
  }

  /// Direct-path claim removal guarded by database RLS.
  Future<void> unclaimItem({
    required String sessionId,
    required String itemId,
    required String participantId,
  }) async {
    try {
      await _supabaseClient.from('item_claims').delete().match({
        'session_id': sessionId,
        'item_id': itemId,
        'participant_id': participantId,
      });
    } catch (e) {
      throw Failure(
        code: 'unclaim_rejected',
        message: 'Claim removal could not be saved: $e',
      );
    }
  }

  /// Atomic RPC: freezes current user's selections and auto-advances to reviewing if last.
  Future<void> completeMySelection(String sessionId) async {
    try {
      await _supabaseClient.rpc<void>(
        'complete_my_selection',
        params: {'p_session_id': sessionId},
      );
    } catch (e) {
      throw Failure(
        code: 'complete_selection_failed',
        message: 'Could not complete selection: $e',
      );
    }
  }
}
