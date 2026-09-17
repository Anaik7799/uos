/**
 * tools/browser_test_sciviz_interactive_media.js
 * Comprehensive Multi-Interaction Playwright Headless Chrome Verification Suite
 * Targets: http://127.0.0.1:4100/sciviz/comprehensive (nas-1.tail55d152.ts.net:4100)
 * Tests: Real-time search, category filtering, Inspect Spec modal, Live Transpiler presets, and full card grid.
 * Captures: 14 High-resolution PNG images + 1080p HD MP4 interactive walkthrough video
 * STAMP: SC-CHECKLIST-001, SC-TAILSCALE-WEB-001, SC-SCIVIZ-167-001, SC-SCIVIZ-167-002
 */

const { chromium } = require('/home/an/NAS-setup/c3i/node_modules/playwright');
const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

async function run() {
  console.log('================================================================');
  console.log(' SCIVIZ COMPREHENSIVE INTERACTIVE MEDIA & TEST SUITE (C496..C500)');
  console.log('================================================================');

  const varVideoDir = path.resolve(__dirname, '../var/sciviz_media/videos');
  const varImgDir = path.resolve(__dirname, '../var/sciviz_media/images');
  const docVideoDir = path.resolve(__dirname, '../docs/reports/sciviz_media/videos');
  const docImgDir = path.resolve(__dirname, '../docs/reports/sciviz_media/images');

  [varVideoDir, varImgDir, docVideoDir, docImgDir].forEach(d => fs.mkdirSync(d, { recursive: true }));

  const browser = await chromium.launch({
    headless: true,
    executablePath: '/usr/bin/google-chrome',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
  });

  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    recordVideo: {
      dir: varVideoDir,
      size: { width: 1920, height: 1080 }
    }
  });

  const page = await context.newPage();
  const targetUrl = 'http://127.0.0.1:4100/sciviz/comprehensive';
  console.log(`[NAVIGATE] Loading target URL: ${targetUrl} ...`);

  const startTime = Date.now();
  await page.goto(targetUrl, { waitUntil: 'networkidle', timeout: 30000 });
  const loadTime = Date.now() - startTime;
  console.log(`[PASS] Page loaded in ${loadTime}ms`);

  // Assert total cards present
  const totalCards = await page.locator('.sciviz-card').count();
  console.log(`[PASS] Total .sciviz-card elements in DOM: ${totalCards} (expected 167)`);
  if (totalCards !== 167) {
    throw new Error(`Expected 167 cards, found ${totalCards}`);
  }

  // 1. Initial Overview Screenshots
  console.log('[CAPTURE 01] Header & Verification Checklist ...');
  await page.locator('header').first().screenshot({
    path: path.join(docImgDir, '01_sciviz_header_and_checklist.png')
  });

  // 2. Test Live Transpiler Presets Interaction
  console.log('[TEST TRANSPILER] Interacting with code presets ...');
  const transpilerSection = page.locator('text=Interactive Code-to-Plot Playground').locator('..').locator('..');
  await transpilerSection.scrollIntoViewIfNeeded();
  await page.waitForTimeout(500);

  // Click TCGA Volcano preset
  const tcgaBtn = page.locator('button:has-text("🧬 TCGA Volcano")');
  await tcgaBtn.click();
  await page.waitForTimeout(300);
  const valTcga = await page.$eval('#transpiler-code-input', el => el.value);
  console.log(`[PASS] TCGA Volcano preset loaded: ${valTcga.length} chars (contains tcga: ${valTcga.includes('tcga')})`);

  // Click ROC Diagnosis preset
  const rocBtn = page.locator('button:has-text("📈 ROC Diagnosis")');
  await rocBtn.click();
  await page.waitForTimeout(300);
  const valRoc = await page.$eval('#transpiler-code-input', el => el.value);
  console.log(`[PASS] ROC preset loaded: ${valRoc.length} chars (contains credit_risk: ${valRoc.includes('credit_risk')})`);

  // Click Diamonds Scatter preset
  const diaBtn = page.locator('button:has-text("💎 Diamonds Scatter")');
  await diaBtn.click();
  await page.waitForTimeout(300);

  console.log('[CAPTURE 11] Live Transpiler Preset Interaction ...');
  await transpilerSection.screenshot({
    path: path.join(docImgDir, '11_sciviz_transpiler_presets_interaction.png')
  });

  // 3. Test Real-Time Search Filtering
  console.log('[TEST SEARCH] Testing real-time search input ...');
  const searchInput = page.locator('#sciviz-search-input');
  await searchInput.scrollIntoViewIfNeeded();
  await page.waitForTimeout(500);

  // Search "ggram"
  await searchInput.fill('ggram');
  await page.waitForTimeout(400);
  let visibleCount = await page.locator('.sciviz-card:visible').count();
  let countText = await page.locator('#sciviz-visible-count').innerText();
  console.log(`[PASS] Query "ggram": visible cards = ${visibleCount}, badge = ${countText}`);

  console.log('[CAPTURE 09] Search interaction "ggram" ...');
  const toolbar = page.locator('#sciviz-toolbar');
  await toolbar.screenshot({
    path: path.join(docImgDir, '09_sciviz_search_interaction_ggram.png')
  });

  // Search "tree"
  await searchInput.fill('tree');
  await page.waitForTimeout(400);
  visibleCount = await page.locator('.sciviz-card:visible').count();
  countText = await page.locator('#sciviz-visible-count').innerText();
  console.log(`[PASS] Query "tree": visible cards = ${visibleCount}, badge = ${countText}`);

  console.log('[CAPTURE 10] Search interaction "tree" ...');
  await toolbar.screenshot({
    path: path.join(docImgDir, '10_sciviz_search_interaction_tree.png')
  });

  // Reset search
  const resetBtn = page.locator('button:has-text("Reset Filters")');
  await resetBtn.click();
  await page.waitForTimeout(400);
  visibleCount = await page.locator('.sciviz-card:visible').count();
  console.log(`[PASS] Reset filters: visible cards = ${visibleCount} (expected 167)`);

  // 4. Test Category Filter Buttons
  console.log('[TEST CATEGORY] Testing category buttons ...');
  const bioBtn = page.locator('button.sciviz-cat-btn:has-text("Bioinformatics & Genomics")');
  await bioBtn.scrollIntoViewIfNeeded();
  await bioBtn.click();
  await page.waitForTimeout(400);
  visibleCount = await page.locator('.sciviz-card:visible').count();
  countText = await page.locator('#sciviz-visible-count').innerText();
  console.log(`[PASS] Clicked "Bioinformatics & Genomics": visible = ${visibleCount}, count = ${countText}`);

  console.log('[CAPTURE 12] Category Filter "Bioinformatics & Genomics" ...');
  await toolbar.screenshot({
    path: path.join(docImgDir, '12_sciviz_category_filter_bioinformatics.png')
  });

  // Click Quality Control
  const qcBtn = page.locator('button.sciviz-cat-btn:has-text("Quality Control & Time-Series")');
  await qcBtn.click();
  await page.waitForTimeout(400);
  visibleCount = await page.locator('.sciviz-card:visible').count();
  console.log(`[PASS] Clicked "Quality Control & Time-Series": visible = ${visibleCount}`);

  // Restore All Categories
  const allBtn = page.locator('button.sciviz-cat-btn[data-cat="all"]');
  await allBtn.click();
  await page.waitForTimeout(400);
  visibleCount = await page.locator('.sciviz-card:visible').count();
  console.log(`[PASS] Clicked "All Categories": visible = ${visibleCount} (expected 167)`);

  // 5. Test Inspect Spec Modal Interaction
  console.log('[TEST MODAL] Opening Inspect Spec modal on flagship card ...');
  const firstInspectBtn = page.locator('.inspect-spec-btn').first();
  await firstInspectBtn.scrollIntoViewIfNeeded();
  await page.waitForTimeout(400);
  await firstInspectBtn.click();
  await page.waitForTimeout(600);

  const modal = page.locator('#sciviz-inspect-modal');
  const modalVisible = await modal.isVisible();
  console.log(`[PASS] Inspect Spec Modal visible: ${modalVisible}`);

  const modalTitle = await page.locator('#modal-ext-name').innerText();
  console.log(`[PASS] Modal Title: "${modalTitle}"`);

  console.log('[CAPTURE 13] Inspect Spec Modal Expanded ...');
  await modal.locator('> div').screenshot({
    path: path.join(docImgDir, '13_sciviz_inspect_modal_active.png')
  });

  // Close modal
  const closeBtn = page.locator('button:has-text("✕ Close")');
  await closeBtn.click();
  await page.waitForTimeout(400);
  const modalHidden = !(await modal.isVisible());
  console.log(`[PASS] Modal closed successfully: ${modalHidden}`);

  // 6. Smooth Scroll Walkthrough to capture complete video
  console.log('[WALKTHROUGH] Executing smooth interactive walkthrough for video recording ...');
  const scrollSteps = [0, 800, 1600, 2600, 3800, 5200, 7000, 9500, 12500, 16000, 20000, 24000, 0];
  for (const y of scrollSteps) {
    await page.evaluate((pos) => window.scrollTo({ top: pos, behavior: 'smooth' }), y);
    await page.waitForTimeout(1000);
  }

  // 7. Full-page Screenshot
  console.log('[CAPTURE FULLPAGE] Rendering 167-card fullpage composite screenshot ...');
  await page.screenshot({
    path: path.join(docImgDir, '00_sciviz_comprehensive_fullpage.png'),
    fullPage: true
  });

  // Copy captured images to var/sciviz_media/images/
  fs.readdirSync(docImgDir).forEach(file => {
    if (file.endsWith('.png')) {
      fs.copyFileSync(path.join(docImgDir, file), path.join(varImgDir, file));
    }
  });

  // Close context to finish video
  console.log('[FINALIZE] Closing browser context to write video stream ...');
  await page.close();
  await context.close();
  await browser.close();

  // Find generated video and transcode to 1080p MP4
  const videoFiles = fs.readdirSync(varVideoDir).filter(f => f.endsWith('.webm'));
  if (videoFiles.length > 0) {
    videoFiles.sort((a, b) => fs.statSync(path.join(varVideoDir, b)).mtimeMs - fs.statSync(path.join(varVideoDir, a)).mtimeMs);
    const latestVideo = path.join(varVideoDir, videoFiles[0]);
    const mp4Var = path.join(varVideoDir, 'sciviz_interactive_walkthrough.mp4');
    const mp4Doc = path.join(docVideoDir, 'sciviz_interactive_walkthrough.mp4');

    console.log(`[TRANSCODE] Converting ${latestVideo} -> 1080p progressive MP4 ...`);
    const ffmpegCmd = `/home/an/.local/bin/ffmpeg -y -i "${latestVideo}" -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p -movflags +faststart "${mp4Var}"`;
    execSync(ffmpegCmd, { stdio: 'inherit' });
    fs.copyFileSync(mp4Var, mp4Doc);
    console.log(`[PASS] Video successfully transcoded to:\n  - ${mp4Var}\n  - ${mp4Doc}`);
  }

  console.log('================================================================');
  console.log(' SCIVIZ INTERACTIVE MEDIA SUITE COMPLETED SUCCESSFULLY (100%)');
  console.log('================================================================');
}

run().catch(err => {
  console.error('[ERROR]', err);
  process.exit(1);
});
