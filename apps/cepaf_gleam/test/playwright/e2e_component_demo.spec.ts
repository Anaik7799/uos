import { test, expect } from '@playwright/test';

const BASE = 'http://localhost:4100';

test.describe('ComponentDemo Page — Comprehensive Verification', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(`${BASE}/components`);
  });

  // === PAGE STRUCTURE ===
  test('page loads with correct title', async ({ page }) => {
    await expect(page).toHaveTitle(/C3I/);
    const h1 = page.locator('h1');
    await expect(h1).toContainText('Component Demo');
  });

  test('has 13+ sections', async ({ page }) => {
    const sections = page.locator('.section-title');
    const count = await sections.count();
    expect(count).toBeGreaterThanOrEqual(13);
  });

  test('has 70+ component cards', async ({ page }) => {
    const cards = page.locator('.card');
    const count = await cards.count();
    expect(count).toBeGreaterThanOrEqual(70);
  });

  // === LIVE RUNTIME DATA (NIF-backed) ===
  test('shows live container count from NIF', async ({ page }) => {
    const content = await page.textContent('body');
    // Should show "X/Y" format for containers (from NIF, not hardcoded)
    expect(content).toMatch(/\d+\/\d+/);
  });

  test('shows cockpit mode from NIF', async ({ page }) => {
    const content = await page.textContent('body');
    expect(content).toMatch(/dark|dim|normal|bright|emergency/);
  });

  test('shows OODA phase from NIF', async ({ page }) => {
    const content = await page.textContent('body');
    expect(content).toMatch(/observe|orient|decide|act/);
  });

  test('shows threat level from NIF', async ({ page }) => {
    const content = await page.textContent('body');
    expect(content).toMatch(/nominal|elevated|critical/);
  });

  // === CONTAINER GENOME GRID ===
  test('genome grid has 16 container cells', async ({ page }) => {
    const cells = page.locator('.genome-cell');
    // At least one genome grid (may have 16 or 32 if shown twice)
    const count = await cells.count();
    expect(count).toBeGreaterThanOrEqual(16);
  });

  test('genome cells have LED indicators', async ({ page }) => {
    const leds = page.locator('.genome-led');
    const count = await leds.count();
    expect(count).toBeGreaterThanOrEqual(16);
  });

  test('genome cells show container names', async ({ page }) => {
    const names = page.locator('.genome-name');
    const first = await names.first().textContent();
    expect(first).toBeTruthy();
    // Should include known container names
    const allText = await page.textContent('.genome-grid');
    expect(allText).toContain('zenoh-router');
    expect(allText).toContain('db-prod');
  });

  test('genome grid shows degraded container (cortex)', async ({ page }) => {
    const degradedCells = page.locator('.genome-cell.genome-degraded');
    const count = await degradedCells.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  test('genome grid shows critical container (ml-runner-2)', async ({ page }) => {
    const criticalCells = page.locator('.genome-cell.genome-critical');
    const count = await criticalCells.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  // === OODA 5-TIER RING ===
  test('OODA 5-tier ring present with 5 tiers', async ({ page }) => {
    const ring = page.locator('.ooda-5tier');
    await expect(ring).toBeAttached();
    const tiers = ring.locator('.ooda-tier');
    await expect(tiers).toHaveCount(5);
  });

  test('OODA tiers show latency budgets', async ({ page }) => {
    const budgets = page.locator('.ooda-budget');
    const count = await budgets.count();
    expect(count).toBe(5);
  });

  test('at least one OODA tier is active', async ({ page }) => {
    const active = page.locator('.ooda-tier.active');
    const count = await active.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  // === PROOF CHAIN ===
  test('proof chain has verified blocks', async ({ page }) => {
    const blocks = page.locator('.proof-block.verified');
    const count = await blocks.count();
    expect(count).toBeGreaterThanOrEqual(5);
  });

  test('proof blocks show hash fragments', async ({ page }) => {
    const firstBlock = page.locator('.proof-block').first();
    const text = await firstBlock.textContent();
    expect(text!.length).toBeGreaterThan(4);
  });

  // === AG-UI EVENT STREAM ===
  test('event stream widget shows events', async ({ page }) => {
    const body = await page.textContent('body');
    expect(body).toContain('AG-UI Event Stream');
    expect(body).toContain('RunStarted');
    expect(body).toContain('StateSnapshot');
  });

  // === DATA TABLE ===
  test('data components table has sortable headers', async ({ page }) => {
    const headers = page.locator('th');
    const count = await headers.count();
    expect(count).toBeGreaterThanOrEqual(4);
  });

  test('data table has component rows', async ({ page }) => {
    const rows = page.locator('tbody tr');
    const count = await rows.count();
    expect(count).toBeGreaterThanOrEqual(8);
  });

  // === CATEGORY SECTIONS ===
  test('has Status Components section', async ({ page }) => {
    await expect(page.getByText('Status Components')).toBeAttached();
  });

  test('has Data Components section', async ({ page }) => {
    await expect(page.getByText('Data Components')).toBeAttached();
  });

  test('has Visualization Components section', async ({ page }) => {
    await expect(page.getByText('Visualization Components')).toBeAttached();
  });

  test('has Interactive Components section', async ({ page }) => {
    await expect(page.getByText('Interactive Components')).toBeAttached();
  });

  test('has OODA Decision Brain section', async ({ page }) => {
    await expect(page.getByText('OODA Decision Brain')).toBeAttached();
  });

  test('has Agent Components section', async ({ page }) => {
    await expect(page.getByText('Agent Components')).toBeAttached();
  });

  test('has Safety Components section', async ({ page }) => {
    await expect(page.getByText('Safety Components')).toBeAttached();
  });

  test('has Layout Components section', async ({ page }) => {
    await expect(page.getByText('Layout Components')).toBeAttached();
  });

  // === USE CASE SECTIONS ===
  test('has Container Fleet use case', async ({ page }) => {
    await expect(page.getByText('Use Case: Container Fleet')).toBeAttached();
  });

  test('has Real-Time Monitors use case', async ({ page }) => {
    await expect(page.getByText('Real-Time Monitors')).toBeAttached();
  });

  test('has Zenoh Mesh use case', async ({ page }) => {
    const body = await page.textContent('body');
    expect(body).toContain('Zenoh Mesh');
  });

  test('has Rule Engine use case', async ({ page }) => {
    const body = await page.textContent('body');
    expect(body).toContain('Rule Engine');
  });

  test('has Planning use case', async ({ page }) => {
    await expect(page.getByText('Use Case: Planning')).toBeAttached();
  });

  test('has Recovery use case', async ({ page }) => {
    await expect(page.getByText('Use Case: Recovery')).toBeAttached();
  });

  // === CATALOG SUMMARY ===
  test('summary shows total components count', async ({ page }) => {
    const body = await page.textContent('body');
    expect(body).toContain('233');
  });

  test('summary shows MCP tools count', async ({ page }) => {
    const body = await page.textContent('body');
    expect(body).toContain('MCP');
  });

  test('summary shows fractal layers', async ({ page }) => {
    const body = await page.textContent('body');
    expect(body).toContain('Fractal');
  });

  // === LIVE RUNTIME DATA SECTION ===
  test('Live Runtime Data section exists', async ({ page }) => {
    await expect(page.getByText('Live Runtime Data')).toBeAttached();
  });

  test('shows "podman ps via NIF" attribution', async ({ page }) => {
    await expect(page.getByText('podman ps via NIF')).toBeAttached();
  });

  test('shows Zenoh connection attribution', async ({ page }) => {
    const body = await page.textContent('body');
    expect(body).toContain('Zenoh');
  });
});

test.describe('ComponentDemo API — /api/v1/components', () => {
  test('returns 233 total components', async ({ request }) => {
    const res = await request.get(`${BASE}/api/v1/components`);
    expect(res.ok()).toBeTruthy();
    const data = await res.json();
    expect(data.total_components).toBe(233);
  });

  test('has 22 category domains', async ({ request }) => {
    const res = await request.get(`${BASE}/api/v1/components`);
    const data = await res.json();
    expect(Object.keys(data.categories).length).toBe(22);
  });

  test('has 3 render targets', async ({ request }) => {
    const res = await request.get(`${BASE}/api/v1/components`);
    const data = await res.json();
    expect(data.render_targets.length).toBe(3);
  });

  test('includes live system health', async ({ request }) => {
    const res = await request.get(`${BASE}/api/v1/components`);
    const data = await res.json();
    expect(data.live_system_health).toBeTruthy();
  });

  test('226 isomorphic components', async ({ request }) => {
    const res = await request.get(`${BASE}/api/v1/components`);
    const data = await res.json();
    expect(data.isomorphic_count).toBe(226);
  });
});

test.describe('ComponentDemo Navigation', () => {
  test('Components link appears in nav bar', async ({ page }) => {
    await page.goto(`${BASE}/dashboard`);
    const navLink = page.locator('nav a[href="/components"]');
    await expect(navLink).toBeAttached();
    await expect(navLink).toContainText('Components');
  });

  test('can navigate from Dashboard to Components', async ({ page }) => {
    await page.goto(`${BASE}/dashboard`);
    await page.click('nav a[href="/components"]');
    await expect(page).toHaveURL(/\/components/);
    await expect(page.locator('h1')).toContainText('Component Demo');
  });

  test('Components page is in /api/v1/pages list', async ({ request }) => {
    const res = await request.get(`${BASE}/api/v1/pages`);
    const data = await res.json();
    const found = data.pages.find((p: any) => p.path === '/components');
    expect(found).toBeTruthy();
    expect(found.label).toBe('Component Demo');
  });
});
