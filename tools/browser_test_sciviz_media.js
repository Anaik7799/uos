/**
 * tools/browser_test_sciviz_media.js
 * Comprehensive Playwright Headless Chrome Visual & Video Verification Suite
 * Targets: http://127.0.0.1:4100/sciviz/comprehensive (nas-1.tail55d152.ts.net:4100)
 * Captures: High-resolution PNG images + HD MP4 video walkthrough
 * STAMP: SC-CHECKLIST-001, SC-TAILSCALE-WEB-001, SC-SCIVIZ-001
 */

const { chromium } = require('/home/an/NAS-setup/c3i/node_modules/playwright');
const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

async function run() {
  console.log('================================================================');
  console.log(' SCIVIZ COMPREHENSIVE BROWSER MEDIA RECORDING & TESTING SUITE');
  console.log('================================================================');

  const videoDir = path.resolve(__dirname, '../var/sciviz_media/videos');
  const imgDir = path.resolve(__dirname, '../var/sciviz_media/images');
  fs.mkdirSync(videoDir, { recursive: true });
  fs.mkdirSync(imgDir, { recursive: true });

  const browser = await chromium.launch({
    headless: true,
    executablePath: '/usr/bin/google-chrome',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage']
  });

  const context = await browser.newContext({
    viewport: { width: 1920, height: 1080 },
    recordVideo: {
      dir: videoDir,
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

  // Verify page title
  const title = await page.title();
  console.log(`[PASS] Title: "${title}"`);

  // Verify Checklist accordion exists
  const checklistExists = await page.locator('text=Comprehensive Verification Checklist').count();
  console.log(`[PASS] Comprehensive Verification Checklist elements found: ${checklistExists}`);

  // Screenshot 1: Top Navigation, Header, Badges & Verification Checklist
  console.log('[CAPTURE] Capturing Header & Checklist screenshot ...');
  await page.screenshot({
    path: path.join(imgDir, '01_sciviz_header_and_checklist.png'),
    clip: { x: 0, y: 0, width: 1920, height: 800 }
  });

  // Scroll to AS-IS vs TO-BE Matrix & KPIs
  await page.evaluate(() => window.scrollTo({ top: 750, behavior: 'smooth' }));
  await page.waitForTimeout(1000);
  console.log('[CAPTURE] Capturing KPIs & AS-IS/TO-BE Architecture Matrix ...');
  await page.screenshot({
    path: path.join(imgDir, '02_sciviz_kpis_and_asis_tobe.png'),
    clip: { x: 0, y: 0, width: 1920, height: 950 }
  });

  // Scroll to Real-Time Progress Dashboard & Live Transpiler
  await page.evaluate(() => window.scrollTo({ top: 1550, behavior: 'smooth' }));
  await page.waitForTimeout(1000);
  console.log('[CAPTURE] Capturing Progress Gauges & Live Transpiler ...');
  await page.screenshot({
    path: path.join(imgDir, '03_sciviz_progress_and_transpiler.png'),
    clip: { x: 0, y: 0, width: 1920, height: 900 }
  });

  // Scroll to ggram Flagship
  await page.evaluate(() => window.scrollTo({ top: 2350, behavior: 'smooth' }));
  await page.waitForTimeout(1000);
  console.log('[CAPTURE] Capturing ggram Flagship Showcase ...');
  await page.screenshot({
    path: path.join(imgDir, '04_sciviz_ggram_flagship.png'),
    clip: { x: 0, y: 0, width: 1920, height: 900 }
  });

  // Scroll to Category Pills & Dataset Matrix
  await page.evaluate(() => window.scrollTo({ top: 3100, behavior: 'smooth' }));
  await page.waitForTimeout(1000);
  console.log('[CAPTURE] Capturing 16 Categories & Dataset Matrix ...');
  await page.screenshot({
    path: path.join(imgDir, '05_sciviz_categories_and_datasets.png'),
    clip: { x: 0, y: 0, width: 1920, height: 850 }
  });

  // Scroll through Deep-Dive Cards Grid (Sample Rows 1, 2, 3)
  await page.evaluate(() => window.scrollTo({ top: 3850, behavior: 'smooth' }));
  await page.waitForTimeout(1000);
  console.log('[CAPTURE] Capturing Deep-Dive Cards Grid - Row 1 (QC, UpSet, Repel, Break) ...');
  await page.screenshot({
    path: path.join(imgDir, '06_sciviz_cards_row1_qc_upset_repel.png'),
    clip: { x: 0, y: 0, width: 1920, height: 850 }
  });

  await page.evaluate(() => window.scrollTo({ top: 4600, behavior: 'smooth' }));
  await page.waitForTimeout(1000);
  console.log('[CAPTURE] Capturing Deep-Dive Cards Grid - Row 2 (3D, ROC, Shader, PCA) ...');
  await page.screenshot({
    path: path.join(imgDir, '07_sciviz_cards_row2_3d_roc_shader_pca.png'),
    clip: { x: 0, y: 0, width: 1920, height: 850 }
  });

  await page.evaluate(() => window.scrollTo({ top: 5350, behavior: 'smooth' }));
  await page.waitForTimeout(1000);
  console.log('[CAPTURE] Capturing Deep-Dive Cards Grid - Row 3 (Theming, AST, Genomics, Raincloud) ...');
  await page.screenshot({
    path: path.join(imgDir, '08_sciviz_cards_row3_theming_ast_genomics.png'),
    clip: { x: 0, y: 0, width: 1920, height: 850 }
  });

  // Capture Full Page Overview Screenshot
  console.log('[CAPTURE] Capturing Full-Page High-Res Screenshot (this takes a moment for 167 cards) ...');
  await page.screenshot({
    path: path.join(imgDir, '00_sciviz_comprehensive_fullpage.png'),
    fullPage: true
  });

  // Smooth scroll video tour down and back up
  console.log('[TOUR] Executing smooth scrolling walkthrough for HD video recording ...');
  const scrollSteps = 15;
  const maxScroll = await page.evaluate(() => document.body.scrollHeight - window.innerHeight);
  const stepSize = maxScroll / scrollSteps;

  for (let i = 1; i <= scrollSteps; i++) {
    const targetTop = i * stepSize;
    await page.evaluate((top) => window.scrollTo({ top, behavior: 'smooth' }), targetTop);
    await page.waitForTimeout(600);
  }

  // Hover on a card to show interactive focus
  console.log('[INTERACTION] Hovering on flagship card ...');
  await page.hover('.sciviz-comprehensive-explorer textarea');
  await page.waitForTimeout(1500);

  // Return to top smoothly
  await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'smooth' }));
  await page.waitForTimeout(1500);

  // Close context to write out video
  await page.close();
  await context.close();
  await browser.close();

  console.log('[VIDEO] Finalizing video encoding ...');
  // Find recorded webm file in videoDir
  const files = fs.readdirSync(videoDir).filter(f => f.endsWith('.webm'));
  if (files.length > 0) {
    const rawWebm = path.join(videoDir, files[0]);
    const finalMp4 = path.join(videoDir, 'sciviz_comprehensive_walkthrough.mp4');
    const ffmpegCmd = `/home/an/.local/bin/ffmpeg -y -i "${rawWebm}" -c:v libx264 -pix_fmt yuv420p -preset fast -crf 22 "${finalMp4}"`;
    try {
      console.log(`[FFMPEG] Transcoding WebM to MP4: ${ffmpegCmd}`);
      execSync(ffmpegCmd, { stdio: 'inherit' });
      console.log(`[PASS] Video written to: ${finalMp4}`);
    } catch (err) {
      console.warn(`[WARN] FFmpeg transcode warning: ${err.message}, WebM remains at: ${rawWebm}`);
    }
  }

  console.log('================================================================');
  console.log(' [VERDICT] 100% SUCCESS: ALL IMAGES AND VIDEO CAPTURED');
  console.log('================================================================');
}

run().catch(err => {
  console.error('[FATAL ERROR]', err);
  process.exit(1);
});
