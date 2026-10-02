import '../models/nivel.dart';
import 'supabase_nivel_repository.dart';

abstract class NivelRepository {
  Future<List<Nivel>> nivelesDe(Dificultad dificultad);
  Future<Nivel> obtener(String nivelId);
}

class SupabaseNivelRepositoryAdapter implements NivelRepository {
  final SupabaseNivelRepository _repository;

  SupabaseNivelRepositoryAdapter([SupabaseNivelRepository? repository])
      : _repository = repository ?? SupabaseNivelRepository();

  @override
  Future<List<Nivel>> nivelesDe(Dificultad dificultad) =>
      _repository.nivelesDe(dificultad);

  @override
  Future<Nivel> obtener(String nivelId) => _repository.obtener(nivelId);
}