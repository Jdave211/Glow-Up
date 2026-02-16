"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.FulfillmentAgent = void 0;
const playwright_1 = require("playwright");
const path = __importStar(require("path"));
const fs = __importStar(require("fs"));
// ═══════════════════════════════════════════════════════════════
// ULTA FULFILLMENT AGENT — Real Purchasing Automation (Safari)
// ═══════════════════════════════════════════════════════════════
//
// Flow:
//   1.  Setup (once) — launch visible Safari, user logs into Ulta,
//       session is saved to disk so future runs are already authenticated.
//   2.  Purchase — headless Safari reuses saved session:
//       a. For each item → navigate to buy_link → click "Add to Bag"
//       b. Go to cart → proceed to checkout
//       c. Fill / confirm shipping address
//       d. Use saved payment method
//       e. Place order
//   3.  Return order confirmation details to the app.
//
// ═══════════════════════════════════════════════════════════════
const SESSION_DIR = path.resolve(__dirname, '../../.browser-session');
const STORAGE_STATE_PATH = path.join(SESSION_DIR, 'storage-state.json');
const NAV_TIMEOUT_MS = 30000;
const CHECKOUT_SETTLE_MS = 2500;
const UI_SETTLE_MS = 800;
class FulfillmentAgent {
    // ─────────────────────────────────────────────────
    // SETUP: Launch visible Safari for manual Ulta login
    // Run this ONCE to save the session.
    // ─────────────────────────────────────────────────
    static async setupSession() {
        // Ensure session dir exists
        if (!fs.existsSync(SESSION_DIR)) {
            fs.mkdirSync(SESSION_DIR, { recursive: true });
        }
        console.log('🔐 Launching visible Safari for Ulta login...');
        console.log(`   Session will be saved to: ${STORAGE_STATE_PATH}`);
        let browser = null;
        let context = null;
        try {
            browser = await playwright_1.webkit.launch({
                headless: false, // VISIBLE so user can log in
            });
            context = await browser.newContext({
                viewport: { width: 1280, height: 900 },
                userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15'
            });
            const page = await context.newPage();
            // Navigate to Ulta home page first (more natural, avoids blocking)
            console.log('Navigating to Ulta home page...');
            await page.goto('https://www.ulta.com', {
                waitUntil: 'domcontentloaded',
                timeout: 30000
            });
            await delay(3000); // Wait for page to fully load
            // Check if we hit the "will be back shortly" page
            const pageContent = await page.evaluate(() => document.body?.innerText || '');
            if (pageContent.toLowerCase().includes('will be back shortly') ||
                pageContent.toLowerCase().includes('maintenance') ||
                pageContent.toLowerCase().includes('temporarily unavailable')) {
                console.log('⚠️ Detected maintenance page. Waiting 5 seconds and retrying...');
                await delay(5000);
                await page.reload({ waitUntil: 'domcontentloaded', timeout: 30000 });
                await delay(3000);
            }
            // Try to click through to login naturally
            console.log('Looking for sign-in link...');
            const signInSelectors = [
                'a[href*="login"]',
                'a[href*="sign-in"]',
                'a[href*="myaccount"]',
                'button:has-text("Sign In")',
                'a:has-text("Sign In")',
                'a:has-text("Account")'
            ];
            let clickedSignIn = false;
            for (const selector of signInSelectors) {
                try {
                    const link = await page.$(selector);
                    if (link) {
                        await link.click();
                        clickedSignIn = true;
                        console.log(`✅ Clicked sign-in link: ${selector}`);
                        await delay(3000);
                        break;
                    }
                }
                catch (e) {
                    // Try next selector
                }
            }
            // If we couldn't click through, navigate directly to login
            if (!clickedSignIn) {
                console.log('Navigating directly to login page...');
                await page.goto('https://www.ulta.com/u/login', {
                    waitUntil: 'domcontentloaded',
                    timeout: 30000
                });
                await delay(3000);
            }
            console.log('');
            console.log('═══════════════════════════════════════════════════');
            console.log('  🔐 ULTA LOGIN REQUIRED');
            console.log('  A Safari window has opened.');
            console.log('  1. Log into your Ulta account');
            console.log('  2. Complete any 2FA if prompted');
            console.log('  3. Once you see the homepage or "My Account", come back here');
            console.log('  4. The session will be saved automatically');
            console.log('═══════════════════════════════════════════════════');
            console.log('');
            console.log('⏳ Waiting for you to complete login...');
            console.log('   (Press Ctrl+C when done, or wait 3 minutes)');
            // Wait up to 3 minutes for user to log in
            const startTime = Date.now();
            const TIMEOUT = 180000; // 3 minutes
            while (Date.now() - startTime < TIMEOUT) {
                try {
                    const currentUrl = page.url();
                    const pageInfo = await page.evaluate(() => {
                        const body = (document.body?.innerText || '').toLowerCase();
                        const title = (document.title || '').toLowerCase();
                        return {
                            hasSignOut: body.includes('sign out'),
                            hasMyAccount: body.includes('my account') || body.includes('myaccount'),
                            hasHi: body.includes('hi,') || body.includes('hi '),
                            hasLogin: body.includes('sign in') || body.includes('log in') || title.includes('login') || title.includes('sign in'),
                            hasOrderHistory: body.includes('order history'),
                            hasMaintenance: body.includes('will be back shortly') ||
                                body.includes('maintenance') ||
                                body.includes('temporarily unavailable')
                        };
                    });
                    // Check if stuck on maintenance page
                    if (pageInfo.hasMaintenance) {
                        console.log('⚠️ Still seeing maintenance page. You may need to manually navigate to login.');
                    }
                    // Check if logged in (multiple indicators)
                    // URL check is strongest signal
                    const isUrlLoggedIn = currentUrl.includes('/myaccount') ||
                        (currentUrl.includes('/account') && !currentUrl.includes('/login'));
                    const isTextLoggedIn = pageInfo.hasSignOut ||
                        pageInfo.hasMyAccount ||
                        pageInfo.hasHi ||
                        pageInfo.hasOrderHistory;
                    // Also check if still on login page
                    const isOnLoginPage = currentUrl.includes('/login') ||
                        currentUrl.includes('/u/login') ||
                        (pageInfo.hasLogin && !isUrlLoggedIn);
                    if ((isUrlLoggedIn || isTextLoggedIn) && !isOnLoginPage) {
                        console.log('✅ Login detected! Stabilizing session...');
                        // Wait for cookies to settle
                        await delay(3000);
                        // Verify session by navigating to account page
                        try {
                            console.log('   Verifying session persistence...');
                            await page.goto('https://www.ulta.com/myaccount', { waitUntil: 'domcontentloaded', timeout: 15000 });
                            await delay(2000);
                            const currentUrlAfterNav = page.url();
                            if (currentUrlAfterNav.includes('/login') || currentUrlAfterNav.includes('/u/login')) {
                                console.log('⚠️ Session verification failed - redirected to login. Continuing to wait...');
                                continue;
                            }
                        }
                        catch (e) {
                            console.log('⚠️ Verification navigation timed out, but assuming logged in.');
                        }
                        console.log(`✅ Session verified! Saving storage state...`);
                        console.log(`   Final URL: ${page.url()}`);
                        // Save storage state (cookies, localStorage, etc.)
                        await context.storageState({ path: STORAGE_STATE_PATH });
                        await browser.close();
                        return { success: true, message: 'Session saved. Future orders will use this login.' };
                    }
                    // Debug logs every 10s
                    const elapsed = Math.floor((Date.now() - startTime) / 1000);
                    if (elapsed % 10 === 0 && elapsed > 0) {
                        console.log(`   Waiting... (${elapsed}s) URL: ${currentUrl}`);
                    }
                }
                catch (e) {
                    // Page navigation in progress or other error
                }
                await delay(2000);
            }
            await browser.close();
            return { success: false, message: 'Timeout waiting for login. Try again.' };
        }
        catch (error) {
            if (browser)
                await browser.close();
            return { success: false, message: `Setup failed: ${error}` };
        }
    }
    // ─────────────────────────────────────────────────
    // CHECK: Is session still valid?
    // ─────────────────────────────────────────────────
    static async isSessionValid() {
        if (!fs.existsSync(STORAGE_STATE_PATH))
            return false;
        let browser = null;
        try {
            browser = await playwright_1.webkit.launch({ headless: true });
            const context = await browser.newContext({
                storageState: STORAGE_STATE_PATH,
                userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15'
            });
            const page = await context.newPage();
            await page.goto('https://www.ulta.com/ulta/myaccount/index.jsp', {
                waitUntil: 'domcontentloaded',
                timeout: 20000
            });
            const loggedIn = await page.evaluate(() => {
                const body = document.body?.innerText || '';
                return body.includes('Sign Out') || body.includes('My Account') || body.includes('Order History');
            });
            await browser.close();
            return loggedIn;
        }
        catch (err) {
            if (browser)
                await browser.close();
            return false;
        }
    }
    // ─────────────────────────────────────────────────
    // PURCHASE: Full automated order flow
    // ─────────────────────────────────────────────────
    static async processOrder(order) {
        const logs = [];
        const log = (msg) => { logs.push(msg); console.log(`  🤖 ${msg}`); };
        log(`Agent initialized for user ${order.userId}`);
        log(`Processing ${order.items.length} item(s)...`);
        // Filter to only Ulta items (have ulta.com in URL)
        const ultaItems = order.items.filter(i => i.url && i.url.includes('ulta.com'));
        const nonUltaItems = order.items.filter(i => !i.url || !i.url.includes('ulta.com'));
        if (nonUltaItems.length > 0) {
            log(`⚠️ ${nonUltaItems.length} item(s) are not from Ulta — skipping: ${nonUltaItems.map(i => i.name).join(', ')}`);
        }
        if (ultaItems.length === 0) {
            return {
                success: false,
                totalCost: 0,
                shippingCost: 0,
                markup: 0,
                logs,
                error: 'No Ulta products in cart'
            };
        }
        // Ensure session exists
        if (!fs.existsSync(STORAGE_STATE_PATH)) {
            return {
                success: false,
                totalCost: 0,
                shippingCost: 0,
                markup: 0,
                logs: [...logs, '❌ No browser session found. Run setup first.'],
                error: 'No Ulta session. Call POST /api/orders/setup-session first.'
            };
        }
        let browser = null;
        try {
            log('Launching Safari with saved session...');
            browser = await playwright_1.webkit.launch({
                headless: true,
            });
            const context = await browser.newContext({
                storageState: STORAGE_STATE_PATH,
                viewport: { width: 1280, height: 900 },
                userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15'
            });
            const page = await context.newPage();
            // ── Step 1: Verify we're logged in ──
            log('Checking login status...');
            await page.goto('https://www.ulta.com', { waitUntil: 'domcontentloaded', timeout: NAV_TIMEOUT_MS });
            await delay(UI_SETTLE_MS);
            const isLoggedIn = await page.evaluate(() => {
                const body = document.body?.innerText || '';
                return body.includes('Sign Out') || body.includes('Hi,');
            });
            if (!isLoggedIn) {
                log('❌ Not logged in — session may have expired');
                await browser.close();
                return {
                    success: false,
                    totalCost: 0,
                    shippingCost: 0,
                    markup: 0,
                    logs: [...logs, '❌ Session expired. Run POST /api/orders/setup-session to re-login.'],
                    error: 'Session expired. Please re-authenticate.'
                };
            }
            log('✅ Logged into Ulta');
            // ── Step 2: Clear existing cart ──
            log('Clearing existing Ulta cart...');
            await page.goto('https://www.ulta.com/bag', { waitUntil: 'domcontentloaded', timeout: NAV_TIMEOUT_MS });
            await delay(UI_SETTLE_MS);
            // Try to remove all existing items
            let attempts = 0;
            while (attempts < 10) {
                const removeBtn = await page.$('[data-test="bag-item-remove"], .js-remove-product, button[aria-label*="Remove"]');
                if (!removeBtn)
                    break;
                await removeBtn.click();
                await delay(700);
                attempts++;
            }
            log('Cart cleared');
            // ── Step 3: Add each product to cart ──
            let subtotal = 0;
            let addedCount = 0;
            for (const item of ultaItems) {
                log(`Adding: ${item.name} (${item.brand}) x${item.quantity}`);
                try {
                    await page.goto(item.url, { waitUntil: 'domcontentloaded', timeout: NAV_TIMEOUT_MS });
                    await delay(UI_SETTLE_MS);
                    // Check stock
                    const pageText = await page.evaluate(() => document.body?.innerText || '');
                    if (pageText.toLowerCase().includes('out of stock') || pageText.toLowerCase().includes('sold out')) {
                        log(`⚠️ "${item.name}" is OUT OF STOCK — skipping`);
                        continue;
                    }
                    // Set quantity if > 1
                    if (item.quantity > 1) {
                        const qtySelector = 'select[data-test="item-quantity"], select.js-quantity, select[name="quantity"]';
                        const qtySelect = await page.$(qtySelector);
                        if (qtySelect) {
                            await page.selectOption(qtySelector, String(item.quantity));
                            log(`  Set quantity to ${item.quantity}`);
                            await delay(500);
                        }
                    }
                    // Click "Add to Bag"
                    const addSelectors = [
                        'button[data-test="add-to-bag"]',
                        'button#add-to-bag',
                        'button.ProductDetail__addToCart',
                        'button[aria-label*="Add to bag"]',
                        'button[aria-label*="Add to Bag"]',
                        'button.js-add-to-bag',
                        'button.ProductHero__addToCart'
                    ];
                    let clicked = await clickFirstEnabled(page, addSelectors);
                    if (clicked) {
                        log(`  ✅ Added to Ulta bag`);
                        addedCount++;
                        subtotal += item.price * item.quantity;
                    }
                    if (!clicked) {
                        // Fallback: try any button containing "Add to Bag" text
                        const fallback = await page.evaluate(() => {
                            const buttons = Array.from(document.querySelectorAll('button'));
                            const addBtn = buttons.find(b => b.innerText.toLowerCase().includes('add to bag') && !b.disabled);
                            if (addBtn) {
                                addBtn.click();
                                return true;
                            }
                            return false;
                        });
                        if (fallback) {
                            log(`  ✅ Added to Ulta bag (fallback)`);
                            addedCount++;
                            subtotal += item.price * item.quantity;
                        }
                        else {
                            log(`  ❌ Could not find "Add to Bag" button for "${item.name}"`);
                        }
                    }
                    await delay(1000); // Wait for bag update
                }
                catch (err) {
                    log(`  ⚠️ Error adding "${item.name}": ${err}`);
                }
            }
            if (addedCount === 0) {
                await browser.close();
                return {
                    success: false,
                    totalCost: 0,
                    shippingCost: 0,
                    markup: 0,
                    logs: [...logs, '❌ Could not add any products to Ulta bag'],
                    error: 'Failed to add products to cart'
                };
            }
            log(`${addedCount}/${ultaItems.length} items added to Ulta bag`);
            // ── Step 4: Navigate to checkout ──
            log('Navigating to checkout...');
            await page.goto('https://www.ulta.com/bag', { waitUntil: 'domcontentloaded', timeout: NAV_TIMEOUT_MS });
            await delay(UI_SETTLE_MS);
            // Click checkout button
            const checkoutSelectors = [
                'button[data-test="checkout-button"]',
                'a[data-test="checkout-button"]',
                'button.js-checkout',
                'a.js-checkout',
                'a[href*="checkout"]',
                'button[aria-label*="Checkout"]'
            ];
            let checkoutClicked = await clickFirstEnabled(page, checkoutSelectors);
            if (checkoutClicked)
                log('  Proceeding to checkout...');
            if (!checkoutClicked) {
                // Fallback: click any element with "Checkout" text
                await page.evaluate(() => {
                    const els = Array.from(document.querySelectorAll('a, button'));
                    const checkoutEl = els.find(e => e.textContent?.toLowerCase().includes('checkout') &&
                        !e.textContent?.toLowerCase().includes('guest'));
                    if (checkoutEl)
                        checkoutEl.click();
                });
                log('  Proceeding to checkout (fallback)...');
            }
            await delay(CHECKOUT_SETTLE_MS); // Wait for checkout page to load
            await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => { });
            // ── Step 5: Shipping address ──
            log('Handling shipping...');
            const addr = order.shippingAddress;
            // Check if we need to enter a new address or if saved address is available
            const hasExistingAddress = await page.evaluate(() => {
                const body = document.body?.innerText || '';
                return body.includes('Ship to this address') || body.includes('Selected shipping address');
            });
            if (!hasExistingAddress && addr.line1) {
                log('  Entering shipping address...');
                // Common Ulta checkout shipping field selectors
                const fields = {
                    '#shipping-firstName, input[name="firstName"], input[name="shipping.firstName"]': addr.fullName.split(' ')[0] || '',
                    '#shipping-lastName, input[name="lastName"], input[name="shipping.lastName"]': addr.fullName.split(' ').slice(1).join(' ') || '',
                    '#shipping-address1, input[name="address1"], input[name="shipping.address1"]': addr.line1,
                    '#shipping-address2, input[name="address2"], input[name="shipping.address2"]': addr.line2 || '',
                    '#shipping-city, input[name="city"], input[name="shipping.city"]': addr.city,
                    '#shipping-zip, input[name="postalCode"], input[name="shipping.postalCode"]': addr.zip,
                };
                for (const [selectors, value] of Object.entries(fields)) {
                    if (!value)
                        continue;
                    for (const sel of selectors.split(', ')) {
                        const field = await page.$(sel);
                        if (field) {
                            await field.click({ clickCount: 3 }); // Select all
                            await field.fill(value);
                            break;
                        }
                    }
                }
                // Select state
                const stateSelectors = ['#shipping-state, select[name="state"], select[name="shipping.state"]'];
                for (const sel of stateSelectors[0].split(', ')) {
                    const stateField = await page.$(sel);
                    if (stateField) {
                        await page.selectOption(sel, addr.state);
                        break;
                    }
                }
                await delay(UI_SETTLE_MS);
                // Click "Continue" or "Use this address"
                const continueSelectors = [
                    'button[data-test="shipping-continue"]',
                    'button.js-continue-shipping',
                    'button[type="submit"]'
                ];
                await clickFirstEnabled(page, continueSelectors);
                await delay(CHECKOUT_SETTLE_MS);
                log('  ✅ Shipping address entered');
            }
            else {
                log('  ✅ Using saved shipping address');
            }
            // ── Step 6: Payment — use saved card ──
            log('Confirming payment method...');
            await delay(UI_SETTLE_MS);
            const hasSavedPayment = await page.evaluate(() => {
                const body = document.body?.innerText || '';
                return body.includes('ending in') || body.includes('****') || body.includes('Visa') ||
                    body.includes('Mastercard') || body.includes('American Express');
            });
            if (hasSavedPayment) {
                log('  ✅ Using saved payment method');
            }
            else {
                log('  ⚠️ No saved payment method detected — order may need manual payment entry');
            }
            // ── Step 7: Place order ──
            log('Placing order...');
            const placeOrderSelectors = [
                'button[data-test="place-order"]',
                'button.js-place-order',
                'button[aria-label*="Place Order"]',
                'button[aria-label*="Place order"]',
                '#place-order'
            ];
            let orderPlaced = await clickFirstEnabled(page, placeOrderSelectors);
            if (!orderPlaced) {
                // Fallback: click any button with "Place Order" text
                orderPlaced = await page.evaluate(() => {
                    const buttons = Array.from(document.querySelectorAll('button'));
                    const btn = buttons.find(b => b.innerText.toLowerCase().includes('place order') && !b.disabled);
                    if (btn) {
                        btn.click();
                        return true;
                    }
                    return false;
                });
            }
            if (orderPlaced) {
                log('  ⏳ Waiting for order confirmation...');
                await Promise.race([
                    page.waitForURL(/order|confirmation|thank-you/i, { timeout: 8000 }).catch(() => null),
                    delay(8000)
                ]);
                // Try to extract order confirmation number
                const orderConfirmation = await page.evaluate(() => {
                    const body = document.body?.innerText || '';
                    // Look for order number patterns
                    const match = body.match(/order\s*(?:number|#|confirmation)[:\s]*([A-Z0-9-]+)/i);
                    return match ? match[1] : null;
                });
                if (orderConfirmation) {
                    log(`  ✅ ORDER CONFIRMED! Order #${orderConfirmation}`);
                }
                else {
                    log('  ✅ Order submitted (confirmation number not detected)');
                }
                // Calculate costs
                const shippingCost = subtotal >= this.FREE_SHIPPING_THRESHOLD ? 0 : 5.95;
                const markup = subtotal * this.MARKUP_PERCENTAGE;
                const totalCost = subtotal + shippingCost + markup;
                log(`💰 Subtotal: $${subtotal.toFixed(2)}`);
                log(`🚚 Shipping: ${shippingCost === 0 ? 'FREE' : '$' + shippingCost.toFixed(2)}`);
                log(`📈 Service fee: $${markup.toFixed(2)}`);
                log(`💳 Total: $${totalCost.toFixed(2)}`);
                await browser.close();
                return {
                    success: true,
                    orderId: orderConfirmation || `GLOWUP-${Date.now()}`,
                    totalCost,
                    shippingCost,
                    markup,
                    logs
                };
            }
            else {
                log('⚠️ Could not click "Place Order" — checkout may require manual review');
                // Take screenshot for debugging
                const screenshotPath = path.resolve(__dirname, '../../checkout-debug.png');
                await page.screenshot({ path: screenshotPath, fullPage: true });
                log(`📸 Debug screenshot saved: ${screenshotPath}`);
                await browser.close();
                return {
                    success: false,
                    totalCost: subtotal,
                    shippingCost: 0,
                    markup: 0,
                    logs,
                    error: 'Could not complete checkout automatically. Check debug screenshot.'
                };
            }
        }
        catch (error) {
            if (browser) {
                try {
                    const pages = browser.contexts().flatMap(c => c.pages());
                    if (pages.length > 0) {
                        const screenshotPath = path.resolve(__dirname, '../../checkout-error.png');
                        await pages[0].screenshot({ path: screenshotPath, fullPage: true });
                        log(`📸 Error screenshot saved: ${screenshotPath}`);
                    }
                }
                catch { /* ignore screenshot errors */ }
                await browser.close();
            }
            console.error('Fulfillment Error:', error);
            return {
                success: false,
                totalCost: 0,
                shippingCost: 0,
                markup: 0,
                logs: [...logs, `❌ Fatal error: ${error}`],
                error: `Agent failed: ${error}`
            };
        }
    }
}
exports.FulfillmentAgent = FulfillmentAgent;
FulfillmentAgent.MARKUP_PERCENTAGE = 0.15; // 15% service fee
FulfillmentAgent.FREE_SHIPPING_THRESHOLD = 35; // Ulta free shipping over $35
function delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}
async function clickFirstEnabled(page, selectors) {
    for (const sel of selectors) {
        const btn = await page.$(sel);
        if (!btn)
            continue;
        const isDisabled = await page.evaluate(el => el.hasAttribute('disabled'), btn);
        if (!isDisabled) {
            await btn.click();
            return true;
        }
    }
    return false;
}
