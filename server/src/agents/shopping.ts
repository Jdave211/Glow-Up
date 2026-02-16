import { FullRoutine, ShoppingCart, Product, CartItem } from '../types';

export class ShoppingAgent {
  async buildCart(routine: FullRoutine): Promise<ShoppingCart> {
    const products = new Map<string, Product>();

    // Aggregate products from all routines
    const allSteps = [...routine.skincareAM, ...routine.skincarePM, ...routine.haircare];
    
    allSteps.forEach(step => {
      if (step.product) {
        products.set(step.product.id, step.product);
      }
    });

    const items: CartItem[] = Array.from(products.values()).map(p => ({
      product: p,
      quantity: 1
    }));

    const totalPrice = items.reduce((sum, item) => sum + item.product.price, 0);

    // Group links by retailer
    // In a real app, this would use deep linking or affiliate API generation
    const retailerGroups = new Map<string, string[]>();
    items.forEach(item => {
      const retailer = item.product.retailer;
      if (!retailerGroups.has(retailer)) {
        retailerGroups.set(retailer, []);
      }
      retailerGroups.get(retailer)?.push(item.product.buyLink);
    });

    const retailerLinks = Array.from(retailerGroups.entries()).map(([retailer, links]) => ({
      retailer,
      // Mocking a cart URL by just taking the first link or a generic "cart" link
      cartUrl: links[0] 
    }));

    return {
      items,
      totalPrice,
      currency: 'USD',
      retailerLinks
    };
  }
}

