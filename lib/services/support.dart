import 'package:flutter_rustore_pay/api/flutter_rustore_pay_client.dart';
import 'package:flutter_rustore_pay/model/acknowledgement_state.dart';
import 'package:flutter_rustore_pay/model/preferred_purchase_type.dart';
import 'package:flutter_rustore_pay/model/product.dart';
import 'package:flutter_rustore_pay/model/ru_store_exception.dart';
import 'package:flutter_rustore_pay/model/sdk_theme.dart';

/// Support the author. Everything in the app is free; paying unlocks nothing.

/// The author's tip page (one-off card payment of any amount). Used by the site build.
const supportUrl = 'https://pay.cloudtips.ru/p/16ad28d4';

/// One-off ("consumable") products created in the RuStore Console with these ids.
const supportProductIds = ['support_99', 'support_299', 'support_999'];

class SupportOption {
  const SupportOption({required this.id, required this.title, required this.price, this.amount = 0});
  final String id;
  final String title;

  /// Price as the store formats it, e.g. "299 ₽".
  final String price;

  /// For sorting, in minor units.
  final int amount;
}

enum SupportResult { thanks, cancelled }

/// [code]: `no_store` (RuStore app missing or outdated), `unauthorized` (not signed in to
/// RuStore), `unavailable` (payments not set up for the app), `failed`.
class SupportException implements Exception {
  const SupportException(this.code);
  final String code;
  @override
  String toString() => 'SupportException($code)';
}

abstract class SupportStore {
  Future<List<SupportOption>> options();
  Future<SupportResult> pay(String id, {required bool dark});
  Future<void> signIn();
}

/// Overridable in tests.
SupportStore supportStore = RuStoreSupport();

class RuStoreSupport implements SupportStore {
  RuStorePayClient get _c => RuStorePayClient.instance;

  @override
  Future<List<SupportOption>> options() async {
    try {
      if (!await _c.ruStoreUtils.isRuStoreInstalled()) throw const SupportException('no_store');
      final List<Product> products = await _c.productInteractor.getProducts(supportProductIds);
      final list = [
        for (final p in products)
          SupportOption(id: p.productId, title: p.title, price: p.amountLabel, amount: p.price ?? 0),
      ]..sort((a, b) => a.amount.compareTo(b.amount));
      if (list.isEmpty) throw const SupportException('unavailable');
      return list;
    } on SupportException {
      rethrow;
    } catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<SupportResult> pay(String id, {required bool dark}) async {
    try {
      final r = await _c.purchaseInteractor.purchase(
        id,
        quantity: 1,
        preferredPurchaseType: PreferredPurchaseType.oneStep,
        sdkTheme: dark ? SdkTheme.dark : SdkTheme.light,
      );
      // Bookkeeping only: nothing is unlocked by a purchase.
      try {
        await _c.purchaseInteractor.updateAcknowledgementState(r.purchaseId, AcknowledgementState.acknowledged);
      } catch (_) {}
      return SupportResult.thanks;
    } on RuStorePurchaseCancelledException {
      return SupportResult.cancelled;
    } catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<void> signIn() => _c.ruStoreUtils.openRuStoreAuthorization();

  static SupportException _map(Object e) => switch (e) {
    RuStoreNotInstalledException() || RuStoreOutdatedException() => const SupportException('no_store'),
    RuStoreUserUnauthorizedException() => const SupportException('unauthorized'),
    RuStorePayInvalidConsoleAppId() ||
    RuStoreApplicationBannedException() ||
    ApplicationSchemeWasNotProvided() => const SupportException('unavailable'),
    _ => const SupportException('failed'),
  };
}
