import { test, expect } from '@playwright/test';

const BASE = 'http://localhost:4100';

test.describe('Allium Specification Index (/allium)', () => {
  test('page loads with title', async ({ page }) => {
    await page.goto(`${BASE}/allium`);
    await expect(page).toHaveTitle(/C3I/);
    const h1 = page.locator('h1');
    await expect(h1).toContainText('Allium');
  });

  test('shows specification count', async ({ page }) => {
    await page.goto(`${BASE}/allium`);
    await expect(page.getByText('36 specification files')).toBeAttached();
    await expect(page.getByText('9,841 lines')).toBeAttached();
  });

  test('has spec table with rows', async ({ page }) => {
    await page.goto(`${BASE}/allium`);
    const rows = page.locator('tbody tr');
    const count = await rows.count();
    expect(count).toBeGreaterThanOrEqual(14);
  });

  test('table has View links', async ({ page }) => {
    await page.goto(`${BASE}/allium`);
    const viewLinks = page.locator('a.badge');
    const count = await viewLinks.count();
    expect(count).toBeGreaterThanOrEqual(10);
  });

  test('ignition spec link navigates to viewer', async ({ page }) => {
    await page.goto(`${BASE}/allium`);
    await page.click('a[href="/allium/ignition"]');
    await expect(page).toHaveURL(/\/allium\/ignition/);
    await expect(page.locator('h1')).toContainText('ignition');
  });

  test('API access section shows endpoints', async ({ page }) => {
    await page.goto(`${BASE}/allium`);
    const body = await page.textContent('body');
    expect(body).toContain('/api/v1/allium');
  });
});

test.describe('Allium Spec Viewer (/allium/:name)', () => {
  test('ignition spec page loads', async ({ page }) => {
    await page.goto(`${BASE}/allium/ignition`);
    await expect(page).toHaveTitle(/C3I.*ignition/);
    await expect(page.locator('h1')).toContainText('ignition');
  });

  test('shows file path', async ({ page }) => {
    await page.goto(`${BASE}/allium/ignition`);
    const body = await page.textContent('body');
    expect(body).toContain('ignition.allium');
  });

  test('has back link to index', async ({ page }) => {
    await page.goto(`${BASE}/allium/ignition`);
    const backLink = page.locator('a[href="/allium"]');
    await expect(backLink).toBeAttached();
  });

  test('content container exists with data-spec', async ({ page }) => {
    await page.goto(`${BASE}/allium/ignition`);
    const content = page.locator('#allium-content');
    await expect(content).toBeAttached();
    await expect(content).toHaveAttribute('data-spec', 'ignition');
  });

  test('JS fetches and renders spec content', async ({ page }) => {
    await page.goto(`${BASE}/allium/ignition`);
    // Wait for JS to fetch and populate
    await page.waitForFunction(() => {
      const el = document.getElementById('allium-content');
      return el && el.textContent && el.textContent.length > 100 && !el.textContent.includes('Loading');
    }, null, { timeout: 10000 });
    const content = await page.textContent('#allium-content');
    expect(content!.length).toBeGreaterThan(500);
    // Should contain Allium keywords after syntax highlighting
    expect(content).toContain('contract');
  });

  test('syntax highlighting applied (colored spans)', async ({ page }) => {
    await page.goto(`${BASE}/allium/ignition`);
    await page.waitForFunction(() => {
      const el = document.getElementById('allium-content');
      return el && el.innerHTML && el.innerHTML.includes('<span');
    }, null, { timeout: 10000 });
    const html = await page.innerHTML('#allium-content');
    expect(html).toContain('<span');
    expect(html).toContain('color:');
  });

  test('gleam_webui spec loads', async ({ page }) => {
    await page.goto(`${BASE}/allium/gleam_webui_comprehensive`);
    await page.waitForFunction(() => {
      const el = document.getElementById('allium-content');
      return el && el.textContent && el.textContent.length > 100;
    }, null, { timeout: 10000 });
    const content = await page.textContent('#allium-content');
    expect(content!.length).toBeGreaterThan(200);
  });

  test('zmof spec loads', async ({ page }) => {
    await page.goto(`${BASE}/allium/zmof`);
    await expect(page.locator('#allium-content')).toBeAttached();
  });
});

test.describe('Allium API Endpoints', () => {
  test('/api/v1/allium returns spec list', async ({ request }) => {
    const res = await request.get(`${BASE}/api/v1/allium`);
    expect(res.ok()).toBeTruthy();
    const data = await res.json();
    expect(data.total_specs).toBe(36);
    expect(data.total_lines).toBe(9841);
    expect(data.specs.length).toBeGreaterThanOrEqual(10);
  });

  test('each spec has name, description, lines, url', async ({ request }) => {
    const res = await request.get(`${BASE}/api/v1/allium`);
    const data = await res.json();
    for (const spec of data.specs) {
      expect(spec.name).toBeTruthy();
      expect(spec.description).toBeTruthy();
      expect(spec.lines).toBeGreaterThan(0);
      expect(spec.url).toMatch(/^\/allium\//);
      expect(spec.api_url).toMatch(/^\/api\/v1\/allium\//);
    }
  });

  test('/api/v1/allium/ignition returns spec content', async ({ request }) => {
    const res = await request.get(`${BASE}/api/v1/allium/ignition`);
    expect(res.ok()).toBeTruthy();
    const data = await res.json();
    expect(data.name).toBe('ignition');
    expect(data.lines).toBeGreaterThan(2000);
    expect(data.content.length).toBeGreaterThan(10000);
    expect(data.content).toContain('contract');
    expect(data.content).toContain('entity');
    expect(data.viewer_url).toBe('/allium/ignition');
  });

  test('/api/v1/allium/nonexistent returns error JSON', async ({ request }) => {
    const res = await request.get(`${BASE}/api/v1/allium/nonexistent_spec_xyz`);
    // Server returns 200 with error JSON (not 404)
    const text = await res.text();
    expect(text).toContain('error');
  });

  test('/api/v1/allium/zmof has valid content', async ({ request }) => {
    const res = await request.get(`${BASE}/api/v1/allium/zmof`);
    const data = await res.json();
    expect(data.name).toBe('zmof');
    expect(data.lines).toBeGreaterThan(50);
  });
});

test.describe('Component Demo — Allium Links', () => {
  test('has Allium spec links on demo page', async ({ page }) => {
    await page.goto(`${BASE}/components`);
    const alliumLinks = page.locator('a[href^="/allium"]');
    const count = await alliumLinks.count();
    expect(count).toBeGreaterThanOrEqual(3);
  });

  test('ignition.allium link navigates correctly', async ({ page }) => {
    await page.goto(`${BASE}/components`);
    await page.click('a[href="/allium/ignition"]');
    await expect(page).toHaveURL(/\/allium\/ignition/);
  });

  test('All Specs link navigates to index', async ({ page }) => {
    await page.goto(`${BASE}/components`);
    await page.click('a[href="/allium"]');
    await expect(page).toHaveURL(/\/allium$/);
  });
});
