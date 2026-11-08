/// Clés Supabase, fournies au lancement avec `--dart-define-from-file=env.json`.
/// Ne jamais mettre la clé "service_role" ici : seulement l'URL et la clé "anon".
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
