interface OrderItem {
    productId: string;
    name: string;
    brand: string;
    url: string;
    quantity: number;
    price: number;
}
interface ShippingAddress {
    fullName: string;
    line1: string;
    line2?: string;
    city: string;
    state: string;
    zip: string;
    country?: string;
}
interface OrderRequest {
    userId: string;
    items: OrderItem[];
    shippingAddress: ShippingAddress;
}
interface OrderResult {
    success: boolean;
    orderId?: string;
    confirmationHash?: string;
    totalCost: number;
    shippingCost: number;
    markup: number;
    logs: string[];
    error?: string;
}
export declare class FulfillmentAgent {
    private static MARKUP_PERCENTAGE;
    private static FREE_SHIPPING_THRESHOLD;
    static setupSession(): Promise<{
        success: boolean;
        message: string;
    }>;
    static isSessionValid(): Promise<boolean>;
    static processOrder(order: OrderRequest): Promise<OrderResult>;
}
export {};
//# sourceMappingURL=fulfillment.d.ts.map