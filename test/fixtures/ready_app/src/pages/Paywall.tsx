import { Purchases } from '@revenuecat/purchases-capacitor';

export async function buy(pkg: any) {
  return Purchases.purchasePackage({ aPackage: pkg });
}
