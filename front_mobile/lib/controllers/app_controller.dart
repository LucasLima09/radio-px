import 'package:flutter/foundation.dart';

/// Base dos controllers.
///
/// Existe por causa de uma corrida comum: a tela sai enquanto uma
/// requisição ainda está em andamento, e o controller termina o trabalho
/// depois de ter sido descartado. Sem a guarda, o `notifyListeners()` estoura
/// "ChangeNotifier used after being disposed".
abstract class AppController extends ChangeNotifier {
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Avisa as Views — ignora chamadas depois do `dispose`.
  @protected
  void notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
