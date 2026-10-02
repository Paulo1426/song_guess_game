abstract class ValidationService {
  Future<bool> validar(String nivelId, String respuesta);
}

class LocalValidationService implements ValidationService {
  final Future<String> Function(String nivelId) _tituloDe;

  LocalValidationService(this._tituloDe);

  @override
  Future<bool> validar(String nivelId, String respuesta) async {
    final titulo = await _tituloDe(nivelId);
    return _normalizar(titulo) == _normalizar(respuesta);
  }

  String _normalizar(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâ]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöô]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}