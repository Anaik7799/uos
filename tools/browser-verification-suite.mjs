// tools/browser-verification-suite.mjs
// STAMP: SC-CHECKLIST-001, SC-TAILSCALE-WEB-001, SC-SA-PLAN-001
import { spawn } from 'node:child_process';
import http from 'node:http';

const CHROME_PORT = 9222;
const CHROME_FLAGS = [
  '--headless=new',
  `--remote-debugging-port=${CHROME_PORT}`,
  '--disable-gpu',
  '--no-sandbox',
  '--disable-dev-shm-usage',
  '--user-data-dir=/tmp/chrome-browser-verify-profile',
  'about:blank'
];

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function fetchJson(url, options = {}) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const req = http.request({
      hostname: parsed.hostname,
      port: parsed.port,
      path: parsed.pathname + parsed.search,
      method: options.method || 'GET'
    }, res => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(data ? JSON.parse(data) : {});
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    req.end();
  });
}


class CdpClient {
  constructor(wsUrl) {
    this.wsUrl = wsUrl;
    this.ws = null;
    this.msgId = 1;
    this.pending = new Map();
    this.events = [];
    this.consoleLogs = [];
    this.exceptions = [];
  }

  async connect() {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(this.wsUrl);
      this.ws.onopen = () => resolve();
      this.ws.onerror = err => reject(err);
      this.ws.onmessage = evt => {
        const msg = JSON.parse(evt.data);
        if (msg.id && this.pending.has(msg.id)) {
          const { resolve, reject } = this.pending.get(msg.id);
          this.pending.delete(msg.id);
          if (msg.error) reject(new Error(msg.error.message || JSON.stringify(msg.error)));
          else resolve(msg.result);
        } else if (msg.method) {
          if (msg.method === 'Runtime.consoleAPICalled') {
            this.consoleLogs.push(msg.params);
          } else if (msg.method === 'Runtime.exceptionThrown') {
            this.exceptions.push(msg.params);
          }
          this.events.push(msg);
        }
      };
    });
  }

  send(method, params = {}) {
    const id = this.msgId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  async eval(expression) {
    const res = await this.send('Runtime.evaluate', {
      expression,
      returnByValue: true,
      awaitPromise: true
    });
    if (res.exceptionDetails) {
      throw new Error(`Eval failed: ${JSON.stringify(res.exceptionDetails)}`);
    }
    return res.result ? res.result.value : undefined;
  }

  close() {
    if (this.ws) {
      try { this.ws.close(); } catch (_) {}
    }
  }
}

async function runVerification() {
  console.log('🚀 [BROWSER-VERIFY] Launching Headless Google Chrome with DevTools Protocol...');
  const chromeProcess = spawn('google-chrome', CHROME_FLAGS, { stdio: 'ignore' });

  // Wait for CDP to be ready
  let version = null;
  for (let i = 0; i < 30; i++) {
    await sleep(300);
    try {
      version = await fetchJson(`http://127.0.0.1:${CHROME_PORT}/json/version`);
      if (version && version.webSocketDebuggerUrl) break;
    } catch (_) {}
  }

  if (!version) {
    chromeProcess.kill();
    throw new Error('Chrome CDP failed to start within 10 seconds');
  }

  console.log(`✅ [BROWSER-VERIFY] Chrome running: ${version.Browser} (Protocol ${version['Protocol-Version']})`);

  const pagesToTest = [
    {
      name: 'Live Main Cockpit Dashboard',
      url: 'http://nas-1.tail55d152.ts.net:4100/',
      verify: async (cdp) => {
        const title = await cdp.eval('document.title');
        const brand = await cdp.eval('document.querySelector(".nav-brand")?.innerText');
        
        // Execute dynamic theme switcher state machine
        await cdp.eval('selectTheme("amber")');
        const themeAmber = await cdp.eval('document.body.className');
        await cdp.eval('selectTheme("dark")');
        const themeDark = await cdp.eval('document.body.className');

        // Verify test cycle function
        const hasTestBtn = await cdp.eval('typeof triggerTestCycle === "function"');

        return {
          title,
          brand,
          dynamic_theme_switcher: themeAmber === 'theme-amber' && themeDark === '',
          test_cycle_function_wired: hasTestBtn,
          nav_links_count: await cdp.eval('document.querySelectorAll("nav a").length')
        };
      }
    },
    {
      name: 'Live Planning Cockpit UI',
      url: 'http://nas-1.tail55d152.ts.net:4100/planning',
      verify: async (cdp) => {
        const title = await cdp.eval('document.title');
        const navActive = await cdp.eval('document.querySelector("nav a.active")?.innerText || ""');
        const cardCount = await cdp.eval('document.querySelectorAll(".card").length');
        
        return {
          title,
          nav_active: navActive,
          card_count: cardCount
        };
      }
    },
    {
      name: 'Live Cortex Cockpit UI',
      url: 'http://nas-1.tail55d152.ts.net:4100/cortex',
      verify: async (cdp) => {
        const title = await cdp.eval('document.title');
        const h1 = await cdp.eval('document.querySelector("h1")?.innerText');
        const osLock = await cdp.eval('document.querySelector(".badge-os-lock")?.innerText');
        const jidoka = await cdp.eval('document.querySelector(".badge-jidoka")?.innerText');
        const phaseCards = await cdp.eval('Array.from(document.querySelectorAll(".phase-card h3")).map(e => e.innerText)');
        const dispatched = await cdp.eval('document.querySelectorAll(".metric-val")[0]?.innerText');
        const completed = await cdp.eval('document.querySelectorAll(".metric-val")[1]?.innerText');
        const andon = await cdp.eval('document.querySelectorAll(".metric-val")[2]?.innerText');
        const tiers = await cdp.eval('Array.from(document.querySelectorAll(".tier-list li")).map(e => e.innerText)');

        return {
          title,
          heading: h1,
          storage_interlock_protected: osLock.includes('25503L801736'),
          jidoka_nominal: jidoka.includes('NOMINAL'),
          poodavr_stage_count: phaseCards.length,
          stages: phaseCards,
          metrics: { dispatched, completed, andon },
          hedged_cascade_tiers: tiers.length
        };
      }
    },
    {
      name: 'Live Comprehensive Checklist',
      url: 'http://nas-1.tail55d152.ts.net:4100/checklist',
      verify: async (cdp) => {
        const title = await cdp.eval('document.title');
        const cardCount = await cdp.eval('document.querySelectorAll(".card").length');
        const pageTitle = await cdp.eval('document.querySelector(".page-title")?.innerText || document.querySelector("h1")?.innerText');

        return {
          title,
          page_title: pageTitle,
          card_count: cardCount
        };
      }
    },
    {
      name: 'Master Sa-Plan Integration Design Plan',
      url: 'http://nas-1.tail55d152.ts.net:4100/docs/design/20260912-0504-full-sa-plan-integration-claude-fable-plan.md',
      verify: async (cdp) => {
        const title = await cdp.eval('document.title');
        const docHeader = await cdp.eval('document.querySelector(".doc-header h1")?.innerText');
        const preContent = await cdp.eval('document.querySelector("pre")?.innerText || ""');
        const storageBadge = await cdp.eval('document.querySelector(".badge-storage")?.innerText');
        const checklistBadge = await cdp.eval('document.querySelector(".badge-checklist")?.innerText');

        return {
          title,
          doc_header: docHeader,
          has_master_plan_title: preContent.includes('Full Sa-Plan Integration, Simulation & Sovereign Execution Master Plan'),
          has_claude_fable: preContent.includes('Claude Fable'),
          has_saplan_db: preContent.includes('var/sa-plan/uos.sqlite3'),
          has_ascii_diagram: preContent.includes('+---') || preContent.includes('|'),
          storage_badge: storageBadge,
          checklist_badge: checklistBadge,
          content_length_chars: preContent.length
        };
      }
    },
    {
      name: 'Codex GPT 6 Astra Sovereign Execution Certificate',
      url: 'http://nas-1.tail55d152.ts.net:4100/docs/design/20260912-0610-uos-codex-gpt-6-astra-saplan-execution-certificate.md',
      verify: async (cdp) => {
        const title = await cdp.eval('document.title');
        const docHeader = await cdp.eval('document.querySelector(".doc-header h1")?.innerText');
        const preContent = await cdp.eval('document.querySelector("pre")?.innerText || ""');

        return {
          title,
          doc_header: docHeader,
          has_codex_signature: preContent.includes('SIG-L0CODEX-ASTRA-20260912-RATIFIED'),
          has_plan_id: preContent.includes('uos/sa-plan-full/20260912-0610'),
          has_all_checks_passed: preContent.includes('All Checks Passed'),
          content_length_chars: preContent.length
        };
      }
    },
    {
      name: 'Claude Fable Sovereign Execution Certificate',
      url: 'http://nas-1.tail55d152.ts.net:4100/docs/design/20260912-0556-uos-claude-fable-saplan-full-execution-certificate.md',
      verify: async (cdp) => {
        const title = await cdp.eval('document.title');
        const docHeader = await cdp.eval('document.querySelector(".doc-header h1")?.innerText');
        const preContent = await cdp.eval('document.querySelector("pre")?.innerText || ""');

        return {
          title,
          doc_header: docHeader,
          has_fable_signature: preContent.includes('SIG-L0FABLE-20260912-FULL-SAPLAN-RAT'),
          has_plan_id: preContent.includes('uos/sa-plan-full/20260912-0556'),
          has_all_checks_passed: preContent.includes('All Checks Passed'),
          content_length_chars: preContent.length
        };
      }
    }
  ];

  const results = [];

  for (const page of pagesToTest) {
    process.stdout.write(`\n🔍 [BROWSER-VERIFY] Testing: ${page.name} ... `);
    const startMs = Date.now();

    // Create new tab via CDP
    const tab = await fetchJson(`http://127.0.0.1:${CHROME_PORT}/json/new`, { method: 'PUT' });
    const cdp = new CdpClient(tab.webSocketDebuggerUrl);

    try {
      await cdp.connect();
      await cdp.send('Page.enable');
      await cdp.send('Runtime.enable');
      await cdp.send('DOM.enable');

      // Navigate to URL and wait for DOM readiness
      await cdp.send('Page.navigate', { url: page.url });
      await sleep(1000);

      const verificationData = await page.verify(cdp);
      const latencyMs = Date.now() - startMs;

      const passed = !verificationData.title.includes('Not Found') && cdp.exceptions.length === 0;

      results.push({
        name: page.name,
        url: page.url,
        passed,
        latency_ms: latencyMs,
        exceptions: cdp.exceptions,
        data: verificationData
      });

      console.log(passed ? `✅ PASS (${latencyMs}ms)` : `❌ FAIL (${latencyMs}ms)`);
    } catch (err) {
      console.log(`❌ ERROR: ${err.message}`);
      results.push({
        name: page.name,
        url: page.url,
        passed: false,
        error: err.message
      });
    } finally {
      cdp.close();
      try {
        await fetchJson(`http://127.0.0.1:${CHROME_PORT}/json/close/${tab.id}`);
      } catch (_) {}
    }
  }

  // Terminate Chrome
  chromeProcess.kill('SIGTERM');
  console.log('\n===============================================================================');
  console.log('                 CHROME BROWSER E2E VERIFICATION SUMMARY');
  console.log('===============================================================================');
  let allPass = true;
  for (const r of results) {
    const status = r.passed ? 'PASS' : 'FAIL';
    if (!r.passed) allPass = false;
    console.log(`[${status}] ${r.name}`);
    console.log(`       URL: ${r.url}`);
    if (r.latency_ms) console.log(`       Render Latency: ${r.latency_ms}ms | JS Exceptions: ${r.exceptions?.length || 0}`);
    if (r.exceptions?.length) console.log(`       Exceptions: ${JSON.stringify(r.exceptions)}`);
    if (r.data) console.log(`       Data: ${JSON.stringify(r.data, null, 2).split('\n').join('\n       ')}`);
  }
  console.log('===============================================================================');
  console.log(`OVERALL BROWSER E2E RESULT: ${allPass ? '100% GREEN (ALL PASS)' : 'FAILURES DETECTED'}`);
  console.log('===============================================================================');

  if (!allPass) process.exit(1);
}

runVerification().catch(err => {
  console.error('Fatal verification error:', err);
  process.exit(1);
});
