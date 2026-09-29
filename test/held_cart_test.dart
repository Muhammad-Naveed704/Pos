import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/features/pos/data/held_cart_repository.dart';
import 'package:storeflow_pos/features/pos/domain/pos_cart.dart';
import 'package:storeflow_pos/features/products/data/product_repository.dart';

import 'support/storeflow_fixture.dart';

void main() {
  test(
    'held cart saves, restores and removes without changing stock',
    () async {
      final fixture = StoreFlowFixture();
      addTearDown(fixture.close);
      final session = await fixture.initialize();
      final products = ProductRepository(fixture.database);
      final id = await products.save(
        session: session,
        input: const ProductInput(
          sku: 'HOLD',
          name: 'Held Product',
          salePrice: 10,
          stockQty: 8,
        ),
      );
      final product = (await products.byId(
        storeId: session.store.id,
        productId: id,
      ))!;
      final repository = HeldCartRepository(fixture.database, products);
      final heldId = await repository.save(
        session,
        PosCart(
          lines: [CartLine(catalogProduct: product, quantityMilli: 3000)],
        ),
        label: 'Counter two',
      );
      final held = await repository
          .watch(session)
          .first
          .then((rows) => rows.single);
      final restored = await repository.restore(session, held);

      expect(held.id, heldId);
      expect(restored.lines.single.quantityMilli, 3000);
      expect(
        (await fixture.database
                .select(fixture.database.productStores)
                .getSingle())
            .stockQty,
        8,
      );
      await repository.remove(session, heldId);
      expect(await repository.watch(session).first, isEmpty);
    },
  );
}
