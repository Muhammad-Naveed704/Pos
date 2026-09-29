import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../products/data/product_repository.dart';
import '../domain/pos_cart.dart';

final cartControllerProvider = NotifierProvider<CartController, PosCart>(
  CartController.new,
);

class CartController extends Notifier<PosCart> {
  @override
  PosCart build() => const PosCart();

  void add(CatalogProduct product) {
    final lines = [...state.lines];
    final index = lines.indexWhere(
      (line) => line.productId == product.product.id,
    );
    if (index == -1) {
      lines.add(CartLine(catalogProduct: product));
    } else {
      lines[index] = lines[index].copyWith(
        quantityMilli: lines[index].quantityMilli + 1000,
      );
    }
    state = state.copyWith(lines: lines);
  }

  void setQuantity(int index, double quantity) {
    final milli = (quantity * 1000).round();
    if (milli <= 0) return remove(index);
    final lines = [...state.lines];
    lines[index] = lines[index].copyWith(quantityMilli: milli);
    state = state.copyWith(lines: lines);
  }

  void remove(int index) {
    final lines = [...state.lines]..removeAt(index);
    state = state.copyWith(lines: lines);
  }

  void setLineDiscount(
    int index, {
    Money fixed = Money.zero,
    double percent = 0,
  }) {
    final lines = [...state.lines];
    lines[index] = lines[index].copyWith(
      manualDiscount: fixed,
      manualDiscountPercent: percent,
    );
    state = state.copyWith(lines: lines);
  }

  void overridePrice(int index, Money price) {
    final lines = [...state.lines];
    lines[index] = lines[index].copyWith(overrideUnitPrice: price);
    state = state.copyWith(lines: lines);
  }

  void clearPriceOverride(int index) {
    final lines = [...state.lines];
    lines[index] = lines[index].copyWith(clearPriceOverride: true);
    state = state.copyWith(lines: lines);
  }

  void setSaleDiscount({Money fixed = Money.zero, double percent = 0}) {
    state = state.copyWith(saleDiscount: fixed, saleDiscountPercent: percent);
  }

  void selectCustomer(String? id) {
    state = id == null
        ? state.copyWith(clearCustomer: true)
        : state.copyWith(customerId: id);
  }

  void setNotes(String value) => state = state.copyWith(notes: value);
  void replace(PosCart value) => state = value;
  void clear() => state = const PosCart();
}
