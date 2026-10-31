import '../data/cashier_kds_database.dart';
import 'cashier_kds_models.dart';

/// The single mutation boundary used by LAN, diagnostics and local UI actions.
class LocalKdsCommandService {
  const LocalKdsCommandService(this._database);

  final CashierKdsDatabase _database;

  LocalKdsCommandResult execute(LocalKdsCommand command) =>
      _database.executeKdsCommand(command);
}
