import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spliqo/core/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider for the global SupabaseClient.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  try {
    return Supabase.instance.client;
  } on Object catch (_) {
    // If Supabase.initialize has not completed yet, construct a client instance
    final client = SupabaseClient(
      AppConfig.current.supabaseUrl,
      AppConfig.current.supabasePublishableKey,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    ref.onDispose(client.dispose);
    return client;
  }
});
