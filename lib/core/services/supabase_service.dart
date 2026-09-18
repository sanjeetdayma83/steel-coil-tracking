import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
}
