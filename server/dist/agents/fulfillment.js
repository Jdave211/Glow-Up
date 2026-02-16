"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.FulfillmentAgent = void 0;
const puppeteer_1 = __importDefault(require("puppeteer"));
const path_1 = __importDefault(require("path"));
const fs_1 = __importDefault(require("fs"));
// ═══════════════════════════════════════════════════════════════
// ULTA FULFILLMENT AGENT — Real Purchasing Automation
// ═══════════════════════════════════════════════════════════════
//
// Flow:
//   1.  Setup (once) — launch visible browser, user logs into Ulta,
//       session is saved to disk so future runs are already authenticated.
//   2.  Purchase — headless browser reuses saved session:
//       a. For each item → navigate to buy_link → click "Add to Bag"
//       b. Go to cart → proceed to checkout
//       c. Fill / confirm shipping address
//       d. Use saved payment method
//       e. Place order
//   3.  Return order confirmation details to the app.
//
// ═══════════════════════════════════════════════════════════════
const SESSION_DIR = path_1.default.resolve(__dirname, '../../.browser-session');
// Pending orders waiting for confirmation
const pendingOrders = new Map();
class FulfillmentAgent {
    // ─────────────────────────────────────────────────
    // SETUP: Launch visible browser for manual Ulta login
    // Run this ONCE to save the session.
    // ─────────────────────────────────────────────────
    static async setupSession() {
        // Ensure session dir exists
        if (!fs_1.default.existsSync(SESSION_DIR)) {
            fs_1.default.mkdirSync(SESSION_DIR, { recursive: true });
        }
        console.log('🔐 Launching visible browser for Ulta login...');
        console.log(`   Session will be saved to: ${SESSION_DIR}`);
        const browser = await puppeteer_1.default.launch({
            headless: false, // VISIBLE so user can log in
            userDataDir: SESSION_DIR,
            args: [
                '--no-sandbox',
                '--disable-setuid-sandbox',
                '--window-size=1280,900'
            ],
            defaultViewport: { width: 1280, height: 900 }
        });
        const page = await browser.newPage();
        await page.setUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        // Navigate to Ulta sign-in page
        await page.goto('https://www.ulta.com/ulta/myaccount/login.jsp', {
            waitUntil: 'networkidle2',
            timeout: 30000
        });
        console.log('');
        console.log('═══════════════════════════════════════════════════');
        console.log('  🔐 ULTA LOGIN REQUIRED');
        console.log('  A browser window has opened.');
        console.log('  1. Log into your Ulta account');
        console.log('  2. Complete any 2FA if prompted');
        console.log('  3. Once you see the homepage, come back here');
        console.log('  4. The session will be saved automatically');
        console.log('═══════════════════════════════════════════════════');
        console.log('');
        console.log('⏳ Waiting for you to complete login...');
        console.log('   (Press Ctrl+C when done, or wait 3 minutes)');
        // Wait up to 3 minutes for user to log in
        // We'll check for the "My Account" or signed-in indicator
        const startTime = Date.now();
        const TIMEOUT = 180000; // 3 minutes
        while (Date.now() - startTime < TIMEOUT) {
            try {
                const loggedIn = await page.evaluate(() => {
                    // Ulta shows "Hi, [Name]" or "Sign Out" when logged in
                    const body = document.body?.innerText || '';
                    return body.includes('Sign Out') || body.includes('My Account') || body.includes('Hi,');
                });
                if (loggedIn) {
                    console.log('✅ Login detected! Session saved.');
                    await browser.close();
                    return { success: true, message: 'Session saved. Future orders will use this login.' };
                }
            }
            catch { /* page navigation in progress */ }
            await new Promise(r => setTimeout(r, 2000));
        }
        await browser.close();
        return { success: false, message: 'Timeout waiting for login. Try again.' };
    }
    // ─────────────────────────────────────────────────
    // CHECK: Is session still valid?
    // ─────────────────────────────────────────────────
    static async isSessionValid() {
        if (!fs_1.default.existsSync(SESSION_DIR))
            return false;
        let browser = null;
        try {
            browser = await puppeteer_1.default.launch({
                headless: true,
                userDataDir: SESSION_DIR,
                args: ['--no-sandbox', '--disable-setuid-sandbox']
            });
            const page = await browser.newPage();
            await page.setUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
            await page.goto('https://www.ulta.com/ulta/myaccount/index.jsp', {
                waitUntil: 'networkidle2',
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
        // Ensure session directory exists
        if (!fs_1.default.existsSync(SESSION_DIR)) {
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
            log('Launching browser with saved session...');
            browser = await puppeteer_1.default.launch({
                headless: true,
                userDataDir: SESSION_DIR,
                args: [
                    '--no-sandbox',
                    '--disable-setuid-sandbox',
                    '--disable-blink-features=AutomationControlled'
                ],
                defaultViewport: { width: 1280, height: 900 }
            });
            const page = await browser.newPage();
            await page.setUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
            // Stealth: remove webdriver flag
            await page.evaluateOnNewDocument(() => {
                Object.defineProperty(navigator, 'webdriver', { get: () => false });
            });
            // ── Step 1: Verify we're logged in ──
            log('Checking login status...');
            await page.goto('https://www.ulta.com', { waitUntil: 'networkidle2', timeout: 30000 });
            await delay(2000);
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
            await page.goto('https://www.ulta.com/bag', { waitUntil: 'networkidle2', timeout: 30000 });
            await delay(2000);
            // Try to remove all existing items
            let attempts = 0;
            while (attempts < 10) {
                const removeBtn = await page.$('[data-test="bag-item-remove"], .js-remove-product, button[aria-label*="Remove"]');
                if (!removeBtn)
                    break;
                await removeBtn.click();
                await delay(1500);
                attempts++;
            }
            log('Cart cleared');
            // ── Step 3: Add each product to cart ──
            let subtotal = 0;
            let addedCount = 0;
            for (const item of ultaItems) {
                log(`Adding: ${item.name} (${item.brand}) x${item.quantity}`);
                try {
                    await page.goto(item.url, { waitUntil: 'networkidle2', timeout: 30000 });
                    await delay(2000);
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
                            await page.select(qtySelector, String(item.quantity));
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
                    let clicked = false;
                    for (const sel of addSelectors) {
                        const btn = await page.$(sel);
                        if (btn) {
                            const isDisabled = await page.evaluate(el => el.disabled, btn);
                            if (!isDisabled) {
                                await btn.click();
                                clicked = true;
                                log(`  ✅ Added to Ulta bag`);
                                addedCount++;
                                subtotal += item.price * item.quantity;
                                break;
                            }
                        }
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
                    await delay(2000); // Wait for bag update
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
            await page.goto('https://www.ulta.com/bag', { waitUntil: 'networkidle2', timeout: 30000 });
            await delay(2000);
            // Click checkout button
            const checkoutSelectors = [
                'button[data-test="checkout-button"]',
                'a[data-test="checkout-button"]',
                'button.js-checkout',
                'a.js-checkout',
                'a[href*="checkout"]',
                'button[aria-label*="Checkout"]'
            ];
            let checkoutClicked = false;
            for (const sel of checkoutSelectors) {
                const btn = await page.$(sel);
                if (btn) {
                    await btn.click();
                    checkoutClicked = true;
                    log('  Proceeding to checkout...');
                    break;
                }
            }
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
            await delay(5000); // Wait for checkout page to load
            await page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 15000 }).catch(() => { });
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
                            await field.type(value, { delay: 30 });
                            break;
                        }
                    }
                }
                // Select state
                const stateSelectors = ['#shipping-state, select[name="state"], select[name="shipping.state"]'];
                for (const sel of stateSelectors[0].split(', ')) {
                    const stateField = await page.$(sel);
                    if (stateField) {
                        await page.select(sel, addr.state);
                        break;
                    }
                }
                await delay(1000);
                // Click "Continue" or "Use this address"
                const continueSelectors = [
                    'button[data-test="shipping-continue"]',
                    'button.js-continue-shipping',
                    'button[type="submit"]'
                ];
                for (const sel of continueSelectors) {
                    const btn = await page.$(sel);
                    if (btn) {
                        await btn.click();
                        break;
                    }
                }
                await delay(3000);
                log('  ✅ Shipping address entered');
            }
            else {
                log('  ✅ Using saved shipping address');
            }
            // ── Step 6: Payment — use saved card ──
            log('Confirming payment method...');
            await delay(2000);
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
            let orderPlaced = false;
            for (const sel of placeOrderSelectors) {
                const btn = await page.$(sel);
                if (btn) {
                    const isDisabled = await page.evaluate(el => el.disabled, btn);
                    if (!isDisabled) {
                        await btn.click();
                        orderPlaced = true;
                        break;
                    }
                }
            }
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
                await delay(8000);
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
                const screenshotPath = path_1.default.resolve(__dirname, '../../checkout-debug.png');
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
                    const page = (await browser.pages())[0];
                    if (page) {
                        const screenshotPath = path_1.default.resolve(__dirname, '../../checkout-error.png');
                        await page.screenshot({ path: screenshotPath, fullPage: true });
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
