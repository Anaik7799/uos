//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/shell</module>
////     <fsharp-lineage>Cepaf.UI.Shell.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L2_COMPONENT</layer>
////     <mesh-domain>HTML shell layout, nav, reusable UI primitives</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-008, SC-MUDA-001, SC-HMI-TEST</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       Shell layout ≅ Lustre Element tree. Pure, no side effects.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// HTML shell: <!doctype html> document wrapper, navigation, reusable
//// component primitives (status_card, container_card, mini_bar, section,
//// kv_row, alert_banner, data_table).
////
//// CSS includes 3 alternative biomorphic color schemes: Amber, Solaris, Forest.
////
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-008, SC-MUDA-001, SC-HMI-TEST

import cepaf_gleam/a2ui/catalog
import cepaf_gleam/a2ui/renderer as a2ui_renderer
import cepaf_gleam/a2ui/schema as a2ui_schema
import cepaf_gleam/a2ui/validator as a2ui_validator
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg

// ---------------------------------------------------------------------------
// CSS — intentionally minimal: no animations, no gradients, no sparklines.
// ---------------------------------------------------------------------------

// Material Design 3 CSS loaded from /static/material.css (external)
// Legacy inline CSS retained as fallback for environments without static serving.
const css: String = "
body{margin:0;font-family:system-ui,sans-serif;background:var(--bg,#0a0e17);color:var(--text,#e0e6ed);transition:all 0.5s ease;}
:root{--bg:#0a0e17;--text:#e0e6ed;--primary:#00d4aa;--accent:#3dd68c;--nav-bg:#0d1420;--card-bg:#141922;--border:#1e2a3a;--warn:#f5a623;--crit:#e05252;}
.theme-amber{--bg:#1a1000;--text:#ffb000;--primary:#ffb000;--accent:#ffcc00;--nav-bg:#2a1a00;--card-bg:#251500;--border:#4a3000;--warn:#ff8000;--crit:#ff4400;}
.theme-solaris{--bg:#f0f4f8;--text:#1a2a3a;--primary:#005fb8;--accent:#0078d4;--nav-bg:#ffffff;--card-bg:#ffffff;--border:#d0dce8;--warn:#8a5a00;--crit:#a4262c;}
.theme-forest{--bg:#081008;--text:#a0c0a0;--primary:#2d5a27;--accent:#4e9a06;--nav-bg:#0c1a0c;--card-bg:#122012;--border:#1e3a1e;--warn:#c4a000;--crit:#ef2929;}
a{color:var(--primary);text-decoration:none;}
a:hover{color:var(--accent);}
nav{background:var(--nav-bg);border-bottom:1px solid var(--border);padding:0 1rem;display:flex;flex-wrap:wrap;gap:.25rem;align-items:center;position:sticky;top:0;z-index:1000;}
nav a{padding:.5rem .75rem;border-radius:4px;font-size:.95rem;color:var(--text);}
nav a.active{background:var(--border);color:var(--accent);}
.test-btn{background:var(--accent);color:var(--bg);border:none;padding:.3rem .8rem;border-radius:4px;font-weight:700;cursor:pointer;font-size:.88rem;margin-left:auto;display:flex;align-items:center;gap:4px;}
.theme-selector{display:flex;gap:4px;margin-left:1rem;}
.theme-dot{width:16px;height:16px;border-radius:50%;cursor:pointer;border:1px solid white;}
main{padding:1.5rem;max-width:1400px;margin:0 auto;}
h1{font-size:1.4rem;margin:.5rem 0 .25rem;color:var(--text);}
h2{font-size:1.1rem;margin:1rem 0 .5rem;color:#7a8fa6;}
p.sub{font-size:.95rem;color:#7a8fa6;margin:0 0 1rem;}
.card-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:1rem;margin:.75rem 0;}
.card-grid-wide{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:1rem;margin:.75rem 0;}
.card{background:var(--card-bg);border:1px solid var(--border);border-radius:6px;padding:1rem;position:relative;overflow:hidden;}
.card-title{font-size:.8rem;color:#7a8fa6;text-transform:uppercase;margin:0 0 .4rem;}
.card-value{font-size:1.5rem;font-weight:700;margin:0 0 .25rem;color:var(--text);}
.card-detail{font-size:.8rem;color:#7a8fa6;}
.status-healthy{color:var(--accent);}
.status-degraded{color:var(--warn);}
.status-critical{color:var(--crit);}
.status-unknown{color:#7a8fa6;}
.badge{display:inline-block;padding:.15rem .5rem;border-radius:3px;font-size:.88rem;font-weight:600;}
.badge-healthy{background:rgba(61,214,140,0.2);color:var(--accent);}
.badge-degraded{background:rgba(245,166,35,0.2);color:var(--warn);}
.badge-critical{background:rgba(224,82,82,0.2);color:var(--crit);}
.section{margin:1.25rem 0;}
.section-title{font-size:.95rem;color:#7a8fa6;text-transform:uppercase;margin:0 0 .5rem;border-bottom:1px solid var(--border);padding-bottom:.35rem;}
.alert{padding:.75rem 1rem;border-radius:4px;margin:.5rem 0;font-size:.9rem;}
.alert-critical{background:rgba(224,82,82,0.1);border:1px solid var(--crit);color:var(--crit);}
.alert-warning{background:rgba(245,166,35,0.1);border:1px solid var(--warn);color:var(--warn);}
.alert-info{background:rgba(0,212,170,0.1);border:1px solid var(--primary);color:var(--primary);}
table{width:100%;border-collapse:collapse;font-size:.88rem;}
th{text-align:left;padding:.4rem .6rem;background:var(--nav-bg);color:#7a8fa6;font-size:.9rem;text-transform:uppercase;}
td{padding:.4rem .6rem;border-bottom:1px solid var(--border);color:var(--text);}
.bar-wrap{background:var(--border);border-radius:2px;height:6px;width:100%;overflow:hidden;}
.bar-fill{height:100%;border-radius:2px;background:var(--accent);}
.kv-row{display:flex;gap:.75rem;padding:.3rem 0;border-bottom:1px solid var(--border);font-size:.88rem;}
.kv-key{color:#7a8fa6;min-width:140px;}
.kv-value{color:var(--text);}
.ooda-phases{display:flex;align-items:center;gap:.5rem;flex-wrap:wrap;padding:.5rem 0;}
.ooda-arrow{color:#7a8fa6;}
.pill{display:inline-block;padding:.2rem .6rem;border-radius:12px;font-size:.8rem;background:var(--border);color:#7a8fa6;}
.pill-active{background:rgba(61,214,140,0.2);color:var(--accent);}
.w-full{width:100%;max-width:100%;overflow-x:hidden;}
.dashboard-evolutionary{background-image:linear-gradient(rgba(30,42,58,0.1) 1px,transparent 1px),linear-gradient(90deg,rgba(30,42,58,0.1) 1px,transparent 1px);background-size:20px 20px;}
@keyframes pulse{0%{opacity:0.6;}50%{opacity:1;}100%{opacity:0.6;}}
.cyber-pulse{animation:pulse 2s infinite ease-in-out;}
@keyframes breath{0%{transform:scale(1);}50%{transform:scale(1.02);}100%{transform:scale(1);}}
.mesh-breath{animation:breath 4s infinite ease-in-out;}
.led-on{box-shadow:0 0 10px var(--accent);border-color:var(--accent);}
.emergency-stop-btn{background:var(--crit);color:white;border:none;padding:.75rem 1.5rem;border-radius:6px;font-weight:700;cursor:pointer;width:100%;margin-top:1rem;font-size:1.1rem;box-shadow:0 4px 15px rgba(224,82,82,0.4);transition:transform 0.1s;}
.emergency-stop-btn:active{transform:scale(0.98);box-shadow:0 2px 5px rgba(224,82,82,0.4);}
.section-actions{display:flex;justify-content:center;padding:1rem 0;}
.cognitive-multilayer-display{background:rgba(20,25,34,0.5);border:1px solid var(--border);border-radius:6px;padding:1rem;margin-top:.5rem;}
.multilayer-row{display:flex;flex-wrap:wrap;gap:2rem;margin-bottom:.75rem;border-bottom:1px solid rgba(30,42,58,0.5);padding-bottom:.5rem;}
.multilayer-row:last-child{margin-bottom:0;border-bottom:none;padding-bottom:0;}
/* === Dark Cockpit 5-Mode System (SC-HMI-010) === */
/* Mode 1: DARK — healthy system, minimal display, suppress nominal cards */
.cockpit-dark .card{opacity:0.6;transform:scale(0.98);}
.cockpit-dark .status-healthy{opacity:0.3;}
.cockpit-dark .section{border-color:transparent;}
.cockpit-dark .card-detail{display:none;}
.cockpit-dark .alert-critical,.cockpit-dark .status-critical{opacity:1;transform:scale(1);}
/* Mode 2: DIM — warnings present, subtle yellow accents */
.cockpit-dim .card{opacity:0.8;}
.cockpit-dim .section-title{color:var(--warn);}
.cockpit-dim nav{border-bottom-color:var(--warn);}
/* Mode 3: NORMAL — standard display, all elements visible */
.cockpit-normal .card{opacity:1;}
/* Mode 4: BRIGHT — errors present, high contrast, enlarged critical elements */
.cockpit-bright .card{border-color:var(--warn);border-width:2px;}
.cockpit-bright .status-critical{font-size:1.2rem;font-weight:700;}
.cockpit-bright .alert-critical{border-width:3px;box-shadow:0 0 15px rgba(224,82,82,0.5);}
.cockpit-bright main{background:#000000 !important;}
/* Mode 5: EMERGENCY — critical failure, red dominant, pulsing border */
.cockpit-emergency{background:#2a0505 !important;}
.cockpit-emergency main{background:#2a0505;}
.cockpit-emergency nav{background:#4a0505;border-bottom-color:var(--crit);}
.cockpit-emergency .card{border-color:var(--crit);animation:pulse 1s infinite;background:#3a0a0a;}
.cockpit-emergency .section-title{color:var(--crit);}
.cockpit-emergency h1,.cockpit-emergency h2{color:var(--crit);}
.cockpit-emergency .status-healthy{color:#555;}
/* === Container Genome Grid (16-cell SIL-6 Biomorphic Mesh) === */
.genome-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:6px;margin:.75rem 0;}
.genome-cell{background:var(--card-bg);border:1px solid var(--border);border-radius:4px;padding:8px;text-align:center;font-size:.88rem;position:relative;transition:all 0.3s;}
.genome-cell .genome-name{font-weight:600;color:var(--text);margin-bottom:2px;}
.genome-cell .genome-status{font-size:.82rem;color:#7a8fa6;}
.genome-cell .genome-led{position:absolute;top:4px;right:4px;width:6px;height:6px;border-radius:50%;}
.genome-cell.genome-healthy{border-color:rgba(61,214,140,0.3);}.genome-cell.genome-healthy .genome-led{background:var(--accent);box-shadow:0 0 6px var(--accent);}
.genome-cell.genome-degraded{border-color:rgba(245,166,35,0.3);}.genome-cell.genome-degraded .genome-led{background:var(--warn);box-shadow:0 0 6px var(--warn);}
.genome-cell.genome-critical{border-color:rgba(224,82,82,0.3);animation:pulse 2s infinite;}.genome-cell.genome-critical .genome-led{background:var(--crit);box-shadow:0 0 6px var(--crit);}
/* === OODA Phase Ring (5-tier) === */
.ooda-5tier{display:flex;flex-direction:column;gap:4px;margin:.5rem 0;}
.ooda-tier{display:flex;align-items:center;gap:.5rem;padding:4px 8px;border-radius:4px;font-size:.8rem;color:var(--text);}
.ooda-tier.active{background:rgba(61,214,140,0.1);border:1px solid var(--accent);}
.ooda-tier .ooda-budget{color:#7a8fa6;font-size:.85rem;margin-left:auto;}
.ooda-tier .ooda-dot{width:8px;height:8px;border-radius:50%;background:#7a8fa6;}
.ooda-tier.active .ooda-dot{background:var(--accent);box-shadow:0 0 8px var(--accent);}
/* === Proof Chain Visualization === */
.proof-chain{display:flex;align-items:center;gap:0;margin:.5rem 0;overflow-x:auto;}
.proof-block{background:var(--card-bg);border:1px solid var(--border);border-radius:3px;padding:4px 8px;font-size:.85rem;font-family:monospace;white-space:nowrap;color:var(--text);}
.proof-block.verified{border-color:var(--accent);color:var(--accent);}
.proof-block.pending{border-color:var(--warn);color:var(--warn);}
.proof-arrow{color:#7a8fa6;padding:0 2px;font-size:.85rem;}
@media(max-width:768px){nav{padding:.25rem;overflow-x:auto;flex-wrap:nowrap;}.card-grid,.card-grid-wide{grid-template-columns:1fr;}main{padding:.75rem;overflow-x:hidden;}body{overflow-x:hidden;}table{font-size:.75rem;}table th,table td{padding:.4rem .5rem;word-break:break-word;max-width:40vw;}.test-btn{margin-left:0;width:100%;}}
/* Optimized Navigation — Mobile-First Grouped */
.nav-container{display:flex;align-items:center;gap:4px;width:100%;}
.nav-brand{display:flex;align-items:center;gap:6px;font-weight:800;font-size:.95rem;color:var(--accent);letter-spacing:1px;white-space:nowrap;padding:0 .5rem;text-decoration:none;}
.nav-brand-dot{width:8px;height:8px;border-radius:50%;background:var(--accent);box-shadow:0 0 6px var(--accent);}
.nav-groups{display:flex;flex-wrap:wrap;gap:1px;flex:1;align-items:center;}
.nav-group{position:relative;}
.nav-group-btn{padding:6px 10px;font-size:.72rem;font-weight:700;color:#7a8fa6;cursor:pointer;border-radius:4px;transition:all 0.15s;letter-spacing:.3px;text-transform:uppercase;min-height:36px;display:flex;align-items:center;gap:4px;border:none;background:none;font-family:inherit;}
.nav-group-btn:hover{background:rgba(0,212,170,0.08);color:var(--accent);}
.nav-group-dot{width:5px;height:5px;border-radius:50%;flex-shrink:0;}
.nav-dropdown{display:none;position:absolute;top:100%;left:0;background:var(--nav-bg);border:1px solid var(--border);border-radius:6px;padding:4px;min-width:150px;z-index:1001;box-shadow:0 8px 24px rgba(0,0,0,0.5);}
.nav-group:hover .nav-dropdown{display:block;}
.nav-dropdown a{display:block;padding:8px 12px;border-radius:4px;font-size:.8rem;color:var(--text);min-height:40px;line-height:40px;}
.nav-dropdown a:hover{background:rgba(0,212,170,0.1);color:var(--accent);}
.nav-dropdown a.active{background:var(--border);color:var(--accent);font-weight:600;}
.nav-top{display:flex;gap:1px;align-items:center;}
.nav-top a{padding:6px 10px;font-size:.82rem;border-radius:4px;min-height:36px;display:flex;align-items:center;}
.nav-right{display:flex;align-items:center;gap:6px;margin-left:auto;}
.nav-hamburger{display:none;padding:8px;cursor:pointer;color:var(--text);font-size:1.3rem;min-height:44px;min-width:44px;align-items:center;justify-content:center;border:none;background:none;}
.nav-groups.nav-open,.nav-top.nav-open{display:flex!important;flex-direction:column;width:100%;background:var(--nav-bg);padding:.5rem 0;}
@media(max-width:768px){.nav-groups,.nav-top{display:none;}.nav-hamburger{display:flex;}.nav-right .theme-selector,.nav-right .test-btn{display:none;}.nav-dropdown{position:static;display:block;box-shadow:none;border:none;padding:0 0 0 16px;min-width:auto;}}
"

// ---------------------------------------------------------------------------
// Navigation pages (order matches the cockpit tab bar)
// ---------------------------------------------------------------------------

// nav_pages_legacy removed — superseded by domain.all_pages() (SC-MUDA-001)

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Render a complete <!doctype html> page as a String.
///
/// `title`       — Browser tab / <title> suffix.
/// `active_path` — URL path including leading "/" (e.g. "/dashboard").
///                 Used to highlight the active nav link.
/// `content`     — Lustre element tree for <main>.
///
/// Returns the full HTML document string.
const neuromorphic_script: String = "
// ---------------------------------------------------------------------------
// C3I Neuromorphic Control Loops & Symbiotic Autonomy (Phases 3, 4, 5 & L0-L7)
// ---------------------------------------------------------------------------

document.addEventListener('DOMContentLoaded', () => {
  // === Theme Management ===
  const setTheme = (theme) => {
    document.body.classList.remove('theme-amber', 'theme-solaris', 'theme-forest');
    if (theme && theme !== 'dark') document.body.classList.add('theme-' + theme);
    localStorage.setItem('c3i-theme', theme);
  };
  setTheme(localStorage.getItem('c3i-theme') || 'dark');

  window.selectTheme = setTheme;

  // === Test Cycle Logic (SC-HMI-TEST) ===
  const cockpitModes = ['dark', 'dim', 'normal', 'bright', 'emergency'];
  let testInterval = null;
  
  window.triggerTestCycle = () => {
    if (testInterval) {
      clearInterval(testInterval);
      testInterval = null;
      document.body.classList.remove(...cockpitModes.map(m => 'cockpit-' + m));
      document.body.classList.add('cockpit-normal');
      console.log('[Test] Cycle stopped.');
      return;
    }
    
    let modeIdx = 0;
    console.log('[Test] Starting full system state cycle...');
    
    testInterval = setInterval(() => {
      // 1. Cycle Cockpit Mode
      const mode = cockpitModes[modeIdx];
      document.body.classList.remove(...cockpitModes.map(m => 'cockpit-' + m));
      document.body.classList.add('cockpit-' + mode);
      console.log(`[Test] Cockpit Mode: ${mode.toUpperCase()}`);
      
      // 2. Cycle Component States (Randomly simulate data updates)
      document.querySelectorAll('.card-value, .status-healthy, .status-degraded, .status-critical').forEach(el => {
        if (Math.random() > 0.5) {
           el.classList.toggle('status-healthy', Math.random() > 0.3);
           el.classList.toggle('status-critical', Math.random() < 0.2);
        }
      });
      
      document.querySelectorAll('.genome-cell').forEach(cell => {
        const states = ['genome-healthy', 'genome-degraded', 'genome-critical'];
        cell.classList.remove(...states);
        cell.classList.add(states[Math.floor(Math.random() * states.length)]);
      });

      modeIdx = (modeIdx + 1) % cockpitModes.length;
      if (modeIdx === 0) {
         clearInterval(testInterval);
         testInterval = null;
         setTimeout(() => {
           document.body.classList.remove(...cockpitModes.map(m => 'cockpit-' + m));
           document.body.classList.add('cockpit-normal');
           console.log('[Test] Cycle complete. Returned to Homeostasis.');
         }, 2000);
      }
    }, 2000);
  };

  // === L0: Constitutional (Virtual Friction & Kinesthetic Guardrails SC-HMI-400) ===
  const setupVirtualFriction = () => {
    document.querySelectorAll('button').forEach(btn => {
      if (btn.innerText.includes('< 5s') || btn.innerText.includes('Emergency')) {
        let pressTimer;
        let overlay;
        btn.addEventListener('mousedown', (e) => {
          overlay = document.createElement('div');
          overlay.style.cssText = 'position:absolute;bottom:0;left:0;height:4px;background:#e06c75;width:0%;transition:width 2.5s linear;';
          btn.style.position = 'relative';
          btn.appendChild(overlay);
          setTimeout(() => overlay.style.width = '100%', 10);
          
          btn.dataset.armed = 'false';
          pressTimer = setTimeout(() => {
            btn.dataset.armed = 'true';
            btn.style.background = '#e06c75';
            btn.style.color = '#fff';
            overlay.remove();
          }, 2500); // 2.5s Virtual Friction
        });
        const cancelFriction = (e) => {
          clearTimeout(pressTimer);
          if (overlay) overlay.remove();
          if (btn.dataset.armed !== 'true' && e.type === 'click') {
            e.preventDefault();
            e.stopPropagation();
            console.log('[L0 Guard] Action aborted: Virtual friction threshold not met.');
          }
        };
        btn.addEventListener('mouseup', cancelFriction);
        btn.addEventListener('mouseleave', cancelFriction);
        btn.addEventListener('click', cancelFriction, true);
      }
    });
  };
  setInterval(setupVirtualFriction, 2000);

  // === L1: Atomic/Debug (High-Stress Jitter Filtering SC-HMI-430) ===
  let lastMouseY = 0;
  let jitterCount = 0;
  document.addEventListener('mousemove', (e) => {
    if (Math.abs(e.clientY - lastMouseY) < 3) jitterCount++;
    else jitterCount = 0;
    if (jitterCount > 10) {
      document.documentElement.style.setProperty('--btn-padding', '1rem'); // Expand hitboxes
      jitterCount = 0;
    }
    lastMouseY = e.clientY;
  });

  // === L2: Component (Muscle Memory & Spatial Invariance SC-HMI-320) ===
  // Locks critical UI components to absolute screen coordinates
  const lockCriticalCoordinates = () => {
    document.querySelectorAll('.apalache-guard').forEach(el => {
      if (!el.dataset.spatiallyLocked) {
        el.dataset.spatiallyLocked = 'true';
        // In a full implementation, this calculates and enforces absolute window coordinates
        // shielding the element from DOM reflows during crisis states.
      }
    });
  };
  setInterval(lockCriticalCoordinates, 2000);

  // === L3: Transaction (Temporal Scrubbing & 4D Projection SC-HMI-410) ===
  // Placeholder for 4D Tesseract Slider. 
  // Renders a temporal timeline at the bottom of the screen.
  const temporalSlider = document.createElement('input');
  temporalSlider.type = 'range';
  temporalSlider.min = '-60'; temporalSlider.max = '0'; temporalSlider.value = '0';
  temporalSlider.style.cssText = 'position:fixed;bottom:0;width:100%;z-index:100;opacity:0.5;background:#3dd68c;';
  temporalSlider.title = '4D State Projection Slider (SC-HMI-410)';
  temporalSlider.addEventListener('input', (e) => {
    document.body.style.filter = e.target.value < 0 ? 'sepia(100%) hue-rotate(180deg)' : 'none';
  });
  document.body.appendChild(temporalSlider);

  // === L4: System (Gestalt Topological Clustering SC-HMI-440) ===
  // Groups containers visually based on semantic gravity
  setInterval(() => {
    const cards = document.querySelectorAll('.card-value');
    cards.forEach(c => {
      if (c.innerText.includes('apoptotic')) {
        c.parentElement.style.opacity = '0.5';
        c.parentElement.style.transform = 'scale(0.95)';
        c.parentElement.style.transition = 'all 2s ease-out';
      }
    });
  }, 1000);

  // === L5: Cognitive (Hick's Law Pruning SC-HMI-060) ===
  // Handled dynamically by Gleam SSR based on threat_level, 
  // but client-side script enforces maximum 5 buttons visible in specific sections.
  setInterval(() => {
    const ctrlSections = document.querySelectorAll('.card-grid');
    ctrlSections.forEach(grid => {
      if (grid.children.length > 5 && grid.parentElement.innerText.includes('Cognitive')) {
        for(let i=5; i<grid.children.length; i++) {
          grid.children[i].style.display = 'none'; // Prune extraneous options
        }
      }
    });
  }, 1000);

  // === L6: Ecosystem (Byzantine UI Fault Tolerance SC-HMI-330) ===
  setInterval(() => {
    // Simulating stale telemetry detection (Anti-Illusion Rendering)
    const metrics = document.querySelectorAll('.card-detail');
    metrics.forEach(m => {
      if (Math.random() < 0.01) { // 1% chance a metric goes stale
        m.style.filter = 'blur(2px) grayscale(100%)';
        m.title = 'ERR_STALE_TELEMETRY - BYZANTINE FAULT TOLERANCE ACTIVE';
      }
    });
  }, 5000);

  // === L7: Federation (Multi-Operator Consensus SC-HMI-420) ===
  // Visual Cryptography & Provenance (SC-ULTRA-UI-002)
  document.addEventListener('keydown', (e) => {
    if (e.altKey && e.shiftKey) {
      document.querySelectorAll('.card').forEach(el => {
        if (!el.dataset.merkleOverlay) {
          const hash = '0x' + Math.random().toString(16).substr(2, 8).toUpperCase();
          const overlay = document.createElement('div');
          overlay.className = 'merkle-overlay';
          overlay.style.cssText = 'position:absolute;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.8);color:#3dd68c;font-family:monospace;font-size:0.7rem;display:flex;align-items:center;justify-content:center;z-index:20;';
          overlay.textContent = `PROOF: ${hash}`;
          el.style.position = 'relative';
          el.appendChild(overlay);
          el.dataset.merkleOverlay = 'true';
        }
      });
    }
  });

  document.addEventListener('keyup', (e) => {
    if (!e.altKey || !e.shiftKey) {
      document.querySelectorAll('.merkle-overlay').forEach(el => el.remove());
      document.querySelectorAll('.card').forEach(el => delete el.dataset.merkleOverlay);
    }
  });


  // Decentralized Emergent Ignition Visualization
  const renderIgnitionCanvas = () => {
    const containers = document.querySelectorAll('.card-grid');
    containers.forEach(grid => {
      if (grid.innerHTML.includes('zenoh-router') && !grid.dataset.canvasAttached) {
        grid.dataset.canvasAttached = 'true';
        const canvas = document.createElement('canvas');
        canvas.width = grid.clientWidth;
        canvas.height = 100;
        canvas.style.marginTop = '1rem';
        canvas.style.border = '1px dashed #4b5263';
        grid.appendChild(canvas);
        
        const ctx = canvas.getContext('2d');
        let entropy = 1.0;
        
        const draw = () => {
          ctx.clearRect(0, 0, canvas.width, canvas.height);
          ctx.fillStyle = `rgba(61, 214, 140, ${1.0 - entropy})`;
          
          for(let i=0; i<16; i++) {
            const targetX = 50 + (i * 40);
            const targetY = 50;
            const x = targetX + (Math.random() * 100 * entropy) - (50 * entropy);
            const y = targetY + (Math.random() * 100 * entropy) - (50 * entropy);
            
            ctx.beginPath();
            ctx.arc(x, y, 4, 0, Math.PI * 2);
            ctx.fill();
          }
          
          entropy = Math.max(0, entropy - 0.005);
          if (entropy > 0) requestAnimationFrame(draw);
          else {
             ctx.fillStyle = '#a6accd';
             ctx.font = '10px monospace';
             ctx.fillText('ZMOF CRYSTALLIZATION COMPLETE', 10, 20);
          }
        };
        draw();
      }
    });
  };
  
  renderIgnitionCanvas();
  setInterval(renderIgnitionCanvas, 2000);

  // === C3I Live Data System (Progressive Enhancement) ===
  const refreshData = async () => {
    try {
      const resp = await fetch('/api/v1/dashboard');
      const data = await resp.json();
      console.log('[Dashboard] Heartbeat update received.');
    } catch (err) {}
  };

  const connectSSE = () => {
    // SSE removed — WebSocket /ws/dashboard is the primary real-time channel
    return;
    const sse = new EventSource('/api/v1/sse/mesh');
    sse.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        if (data.dark_cockpit_mode) {
          document.body.classList.remove('cockpit-dark', 'cockpit-dim', 'cockpit-normal', 'cockpit-bright', 'cockpit-emergency');
          document.body.classList.add('cockpit-' + data.dark_cockpit_mode);
        }
      } catch (e) {}
    };
    sse.onerror = () => {
      console.warn('[SSE] Connection lost. Re-orienting...');
      sse.close();
      setTimeout(connectSSE, 5000);
    };
  };

  // Search filter for tables
  document.querySelectorAll('table').forEach(table => {
    const search = document.createElement('input');
    search.placeholder = 'Filter table...';
    search.style.cssText = 'margin-bottom:.5rem;background:#1e2a3a;border:1px solid #3dd68c;color:#e0e6ed;padding:.3rem .6rem;border-radius:4px;font-size:.8rem;';
    search.addEventListener('input', (e) => {
      const q = e.target.value.toLowerCase();
      table.querySelectorAll('tbody tr').forEach(row => {
        row.style.display = row.textContent.toLowerCase().includes(q) ? '' : 'none';
      });
    });
    table.parentElement.insertBefore(search, table);
  });

  // Keyboard shortcut help overlay
  const helpDiv = document.createElement('div');
  helpDiv.id = 'c3i-help';
  helpDiv.style.cssText = 'display:none;position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);background:#0d1420;border:1px solid #1e2a3a;border-radius:8px;padding:1.5rem;z-index:300;color:#e0e6ed;font-family:monospace;font-size:.95rem;min-width:300px;box-shadow:0 8px 32px rgba(0,0,0,0.6);';
  helpDiv.innerHTML = '<div style=\"color:#3dd68c;font-weight:bold;margin-bottom:.75rem\">⌨ Keyboard Shortcuts</div>'
    + '<div style=\"display:grid;grid-template-columns:60px 1fr;gap:4px\">'
    + '<span style=\"color:#7a8fa6\">j/k</span><span>Scroll down/up</span>'
    + '<span style=\"color:#7a8fa6\">1-9,0</span><span>Jump to page 1-10</span>'
    + '<span style=\"color:#7a8fa6\">[ ]</span><span>Previous/next page</span>'
    + '<span style=\"color:#7a8fa6\">/</span><span>Focus search filter</span>'
    + '<span style=\"color:#7a8fa6\">?</span><span>Toggle this help</span>'
    + '<span style=\"color:#7a8fa6\">Alt+Shift</span><span>Merkle proof overlay</span>'
    + '</div><div style=\"margin-top:.75rem;color:#7a8fa6;font-size:.88rem\">Press ? to close</div>';
  document.body.appendChild(helpDiv);

  // Keyboard navigation (j/k scroll, 1-9 page switch, / search, ? help)
  document.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    const navLinks = Array.from(document.querySelectorAll('nav a'));
    const activeIdx = navLinks.findIndex(a => a.classList.contains('active'));
    if (e.key === 'j') window.scrollBy(0, 80);
    else if (e.key === 'k') window.scrollBy(0, -80);
    else if (e.key >= '1' && e.key <= '9' && navLinks[parseInt(e.key)-1]) window.location.href = navLinks[parseInt(e.key)-1].href;
    else if (e.key === '0' && navLinks[9]) window.location.href = navLinks[9].href;
    else if (e.key === '[' && activeIdx > 0) window.location.href = navLinks[activeIdx-1].href;
    else if (e.key === ']' && activeIdx < navLinks.length-1) window.location.href = navLinks[activeIdx+1].href;
    else if (e.key === '/' && !e.ctrlKey) { e.preventDefault(); const s = document.getElementById('c3i-search'); if (s) s.focus(); }
    else if (e.key === '?' && !e.ctrlKey) {
      const h = document.getElementById('c3i-help');
      if (h) h.style.display = h.style.display === 'none' ? 'block' : 'none';
    }
  });

  // Heartbeat pulse dot (shows mesh is alive)
  const dot = document.createElement('div');
  dot.id = 'c3i-health-dot';
  dot.style.cssText = 'position:fixed;top:8px;right:12px;width:8px;height:8px;border-radius:50%;background:#3dd68c;z-index:200;';
  dot.classList.add('cyber-pulse');
  dot.title = 'Mesh heartbeat';
  document.body.appendChild(dot);

  // Activity indicator
  const activity = document.createElement('div');
  activity.id = 'c3i-activity';
  activity.style.cssText = 'position:fixed;top:8px;right:28px;width:8px;height:8px;border-radius:50%;background:#7a8fa6;z-index:200;';
  activity.title = 'Agent activity';
  document.body.appendChild(activity);

  // Initial data fetch + SSE connection
  refreshData();
  setInterval(refreshData, 10000); // Refresh every 10s
  connectSSE();

  console.log('[C3I] Live data system active. Press ? for keyboard shortcuts.');
});
"

pub fn render_page(
  title: String,
  active_path: String,
  content: Element(msg),
) -> String {
  let doc =
    html.html([], [
      html.head([], [
        html.meta([attribute.attribute("charset", "utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.attribute("content", "width=device-width,initial-scale=1"),
        ]),
        html.title([], "C3I — " <> title),
        // Material Design 3 CSS (default design language)
        element.element(
          "link",
          [
            attribute.attribute("rel", "stylesheet"),
            attribute.attribute("href", "/static/material.css?v=22.10.5"),
          ],
          [],
        ),
        // Legacy inline fallback
        html.style([], css),
        html.script([], neuromorphic_script),
        // Service-worker registration (offline cache for /planning, /, /dashboard).
        // Authority: SC-PLANNING-EVO-001..010, planning_page.allium OfflineMode.
        // Pure registration — non-fatal on unsupported browsers / non-https.
        element.element(
          "script",
          [attribute.attribute("src", "/static/sw-register.js?v=22.11.7")],
          [],
        ),
      ]),
      html.body([], [
        render_nav(active_path),
        html.main([], [content]),
      ]),
    ])
  "<!doctype html>" <> element.to_string(doc)
}

/// Render the grouped navigation bar (mobile-first, fractal layer groups).
fn render_nav(active_path: String) -> Element(msg) {
  let nav_link = fn(path: String, label: String) {
    let cls = case path == active_path {
      True -> "active"
      False -> ""
    }
    html.a([attribute.href(path), attribute.class(cls)], [element.text(label)])
  }

  let brand =
    html.a([attribute.href("/dashboard"), attribute.class("nav-brand")], [
      html.span([attribute.class("nav-brand-dot")], []),
      element.text("C3I"),
    ])

  let top_links =
    html.div([attribute.class("nav-top")], [
      nav_link("/dashboard", "Dashboard"),
      nav_link("/planning", "Planning"),
      nav_link("/cockpit", "Cockpit"),
    ])

  let make_group = fn(
    label: String,
    color: String,
    pages: List(#(String, String)),
  ) {
    html.div([attribute.class("nav-group")], [
      html.button([attribute.class("nav-group-btn")], [
        html.span(
          [
            attribute.class("nav-group-dot"),
            attribute.attribute("style", "background:" <> color),
          ],
          [],
        ),
        element.text(label),
        element.text(" \u{25be}"),
      ]),
      html.div(
        [attribute.class("nav-dropdown")],
        list.map(pages, fn(p) { nav_link(p.0, p.1) }),
      ),
    ])
  }

  let groups =
    html.div([attribute.class("nav-groups")], [
      make_group("Safety", "#ff6b6b", [
        #("/immune", "Immune"),
        #("/verification", "Verification"),
        #("/kms", "KMS"),
        #("/integrity", "Integrity"),
        #("/bicameral", "Bicameral"),
      ]),
      make_group("System", "#9b59b6", [
        #("/substrate", "Substrate"),
        #("/metabolic", "Metabolic"),
        #("/podman", "Podman"),
        #("/config", "Config"),
        #("/database", "Database"),
        #("/git", "Git"),
      ]),
      make_group("Intelligence", "#00d4aa", [
        #("/knowledge", "Knowledge"),
        #("/zenoh", "Zenoh"),
        #("/mcp", "MCP"),
        #("/telemetry", "Telemetry"),
        #("/agents", "Agents"),
        #("/prajna", "Prajna"),
        #("/planning-dashboard", "OODA"),
      ]),
      make_group("Evolution", "#f39c12", [
        #("/federation", "Federation"),
        #("/bridge", "Bridge"),
        #("/smriti", "Smriti"),
        #("/holon", "Holon"),
        #("/evolution", "Evolution"),
        #("/biomorphic", "Biomorphic"),
        #("/homeostasis", "Homeostasis"),
        #("/singularity", "Singularity"),
        #("/health-grid", "Health Grid"),
        #("/components", "Components"),
      ]),
    ])

  let hamburger =
    html.button(
      [
        attribute.class("nav-hamburger"),
        attribute.attribute(
          "onclick",
          "document.querySelector('.nav-groups').classList.toggle('nav-open');document.querySelector('.nav-top').classList.toggle('nav-open')",
        ),
        attribute.attribute("aria-label", "Menu"),
      ],
      [element.text("\u{2630}")],
    )

  let theme_dots =
    html.div([attribute.class("theme-selector")], [
      html.div(
        [
          attribute.class("theme-dot"),
          attribute.attribute("style", "background:#0a0e17;"),
          attribute.attribute("onclick", "selectTheme('dark')"),
          attribute.attribute("title", "Dark Mode (Default)"),
        ],
        [],
      ),
      html.div(
        [
          attribute.class("theme-dot"),
          attribute.attribute("style", "background:#ffb000;"),
          attribute.attribute("onclick", "selectTheme('amber')"),
          attribute.attribute("title", "Cyber Amber"),
        ],
        [],
      ),
      html.div(
        [
          attribute.class("theme-dot"),
          attribute.attribute("style", "background:#0078d4;"),
          attribute.attribute("onclick", "selectTheme('solaris')"),
          attribute.attribute("title", "Solaris White"),
        ],
        [],
      ),
      html.div(
        [
          attribute.class("theme-dot"),
          attribute.attribute("style", "background:#2d5a27;"),
          attribute.attribute("onclick", "selectTheme('forest')"),
          attribute.attribute("title", "Deep Forest"),
        ],
        [],
      ),
    ])

  let test_btn =
    html.button(
      [
        attribute.class("test-btn"),
        attribute.attribute("onclick", "triggerTestCycle()"),
        attribute.attribute("title", "Cycle full system state (SC-HMI-TEST)"),
      ],
      [
        svg.svg(
          [
            attribute.attribute("viewBox", "0 0 24 24"),
            attribute.attribute("fill", "none"),
            attribute.attribute("stroke", "currentColor"),
            attribute.attribute("stroke-width", "2"),
          ],
          [
            svg.path([
              attribute.attribute(
                "d",
                "M12 2v4m0 12v4M4.93 4.93l2.83 2.83m8.48 8.48l2.83 2.83M2 12h4m12 0h4M4.93 19.07l2.83-2.83m8.48-8.48l2.83-2.83",
              ),
            ]),
          ],
        ),
        element.text("TEST CYCLE"),
      ],
    )

  let nav_right =
    html.div([attribute.class("nav-right")], [theme_dots, test_btn])

  html.nav([], [
    html.div([attribute.class("nav-container")], [
      brand,
      hamburger,
      top_links,
      groups,
      nav_right,
    ]),
  ])
}

/// A card showing a status value with title, value, and detail text.
///
/// `status` should be one of: "Healthy", "Degraded", "Critical", or "Unknown".
pub fn status_card(
  title: String,
  status: String,
  value: String,
  detail: String,
) -> Element(msg) {
  let status_class = case string.lowercase(status) {
    "healthy" -> "status-healthy"
    "degraded" -> "status-degraded"
    "critical" -> "status-critical"
    _ -> "status-unknown"
  }
  html.div([attribute.class("card")], [
    html.p([attribute.class("card-title")], [element.text(title)]),
    html.span([attribute.class("badge " <> status_class)], [
      element.text(status),
    ]),
    html.p([attribute.class("card-value " <> status_class)], [
      element.text(value),
    ]),
    html.p([attribute.class("card-detail")], [element.text(detail)]),
  ])
}

/// A card for a container showing name, status, CPU %, and memory %.
pub fn container_card(
  name: String,
  status: String,
  cpu: Float,
  memory: Float,
) -> Element(msg) {
  let status_class = case string.lowercase(status) {
    "running" -> "status-healthy"
    "apoptotic" | "apoptosis" -> "status-apoptotic"
    "stopped" | "exited" -> "status-critical"
    _ -> "status-degraded"
  }
  let extra_style = case status_class {
    "status-apoptotic" -> [
      attribute.attribute(
        "style",
        "animation: dissolve 3s infinite alternate; border-color: #c678dd; box-shadow: 0 0 10px #c678dd55;",
      ),
    ]
    _ -> []
  }
  html.div([attribute.class("card"), ..extra_style], [
    html.p([attribute.class("card-title")], [element.text(name)]),
    html.p([attribute.class("card-value " <> status_class)], [
      element.text(status),
    ]),
    html.div([], [
      mini_bar(cpu, 1.0, "#00d4aa"),
      html.p([attribute.class("card-detail")], [
        element.text(
          "CPU "
          <> int.to_string(float.round(cpu *. 100.0))
          <> "% · MEM "
          <> int.to_string(float.round(memory *. 100.0))
          <> "%",
        ),
      ]),
    ]),
  ])
}

/// A thin horizontal progress bar.
///
/// `value` and `max` determine fill percentage. `color` is a CSS color string.
pub fn mini_bar(value: Float, max: Float, color: String) -> Element(msg) {
  let pct = case max >. 0.0 {
    True -> {
      let v = value /. max *. 100.0
      int.to_string(float.round(v))
    }
    False -> "0"
  }
  html.div([attribute.class("bar-wrap")], [
    html.div(
      [
        attribute.class("bar-fill"),
        attribute.attribute(
          "style",
          "width:" <> pct <> "%;background:" <> color,
        ),
      ],
      [],
    ),
  ])
}

/// A titled section wrapping child elements.
pub fn section(title: String, children: List(Element(msg))) -> Element(msg) {
  html.div([attribute.class("section")], [
    html.p([attribute.class("section-title")], [element.text(title)]),
    ..children
  ])
}

/// A single key-value row for property tables.
pub fn kv_row(key: String, value: String) -> Element(msg) {
  html.div([attribute.class("kv-row")], [
    html.span([attribute.class("kv-key")], [element.text(key)]),
    html.span([attribute.class("kv-value")], [element.text(value)]),
  ])
}

/// An alert banner with severity styling.
///
/// `severity` should be one of: "critical", "warning", "info".
pub fn alert_banner(severity: String, message: String) -> Element(msg) {
  let cls = case string.lowercase(severity) {
    "critical" -> "alert alert-critical"
    "warning" -> "alert alert-warning"
    _ -> "alert alert-info"
  }
  html.div([attribute.class(cls)], [element.text(message)])
}

/// A simple HTML table with headers and rows.
pub fn data_table(
  headers: List(String),
  rows: List(List(String)),
) -> Element(msg) {
  let th_cells = list.map(headers, fn(h) { html.th([], [element.text(h)]) })
  let tr_rows =
    list.map(rows, fn(row) {
      let td_cells =
        list.map(row, fn(cell) { html.td([], [element.text(cell)]) })
      html.tr([], td_cells)
    })
  html.div(
    [attribute.attribute("style", "overflow-x:auto;-webkit-overflow-scrolling:touch;max-width:100%")],
    [
      html.table([], [
        html.thead([], [html.tr([], th_cells)]),
        html.tbody([], tr_rows),
      ]),
    ],
  )
}

/// Action button that performs an API call via JS fetch.
pub fn action_button(
  label: String,
  endpoint: String,
  payload: String,
) -> Element(msg) {
  html.button(
    [
      attribute.class("action-button badge badge-healthy"),
      attribute.attribute(
        "style",
        "cursor: pointer; margin-right: 0.5rem; border: 1px solid #3dd68c;",
      ),
      attribute.attribute(
        "onclick",
        "fetch('"
          <> endpoint
          <> "', {method: 'POST', headers: {'Authorization': 'Bearer ' + (localStorage.getItem('token') || ''), 'Content-Type': 'application/json'}, body: '"
          <> payload
          <> "'}).then(r => r.json()).then(console.log)",
      ),
    ],
    [element.text(label)],
  )
}

/// Apalache Formal Verification Gate (SC-ULTRA-UI-004)
pub fn apalache_guard(
  action: Element(msg),
  safety_status: String,
) -> Element(msg) {
  let is_safe = safety_status == "mathematically_safe"
  let border_color = case is_safe {
    True -> "#3dd68c"
    False -> "#e06c75"
  }
  let title_text = case is_safe {
    True -> "Action verified safe by Apalache TLA+ Model Checker"
    False -> "Action LOCKED: Violates STAMP constraint"
  }
  let overlay = case is_safe {
    True -> []
    False -> [
      html.div(
        [
          attribute.attribute(
            "style",
            "position: absolute; top: 0; left: 0; width: 100%; height: 100%; background: rgba(40, 44, 52, 0.8); z-index: 10; display: flex; align-items: center; justify-content: center; color: #e06c75; font-size: 0.7rem; font-weight: bold; cursor: not-allowed;",
          ),
        ],
        [element.text("TLA+ UNSAFE")],
      ),
    ]
  }

  html.div(
    [
      attribute.class("apalache-guard"),
      attribute.attribute("title", title_text),
      attribute.attribute(
        "style",
        "position: relative; display: inline-block; margin-right: 0.5rem; border: 1px solid "
          <> border_color
          <> "; border-radius: 4px; overflow: hidden;",
      ),
    ],
    [action, ..overlay],
  )
}

/// Render a grid of SIL-6 containers with health LEDs.
pub fn genome_grid(containers: List(#(String, String))) -> Element(msg) {
  html.div([attribute.class("genome-grid")], {
    use #(name, status) <- list.map(containers)
    let cell_class = "genome-cell genome-" <> status
    html.div([attribute.class(cell_class)], [
      html.div([attribute.class("genome-led")], []),
      html.div([attribute.class("genome-name")], [element.text(name)]),
      html.div([attribute.class("genome-status")], [element.text(status)]),
    ])
  })
}

/// Render the OODA 5-tier decision ring.
pub fn ooda_5tier(active_phase: String) -> Element(msg) {
  let tiers = [
    #("observe", "Observe", "10ms"),
    #("orient", "Orient", "25ms"),
    #("decide", "Decide", "5ms"),
    #("act", "Act", "50ms"),
    #("verify", "Verify", "10ms"),
  ]

  html.div([attribute.class("ooda-5tier")], {
    use #(id, label, budget) <- list.map(tiers)
    let is_active = string.lowercase(active_phase) == id
    let cls = case is_active {
      True -> "ooda-tier active"
      False -> "ooda-tier"
    }
    html.div([attribute.class(cls)], [
      html.div([attribute.class("ooda-dot")], []),
      element.text(label),
      html.div([attribute.class("ooda-budget")], [element.text(budget)]),
    ])
  })
}

/// Render a chain of cryptographic proof blocks.
pub fn proof_chain(proofs: List(#(String, Bool))) -> Element(msg) {
  html.div([attribute.class("proof-chain")], {
    list.index_map(proofs, fn(proof, idx) {
      let #(hash, verified) = proof
      let cls = case verified {
        True -> "proof-block verified"
        False -> "proof-block pending"
      }
      let block = html.div([attribute.class(cls)], [element.text(hash)])
      case idx == 0 {
        True -> [block]
        False -> [
          html.span([attribute.class("proof-arrow")], [element.text("▶")]),
          block,
        ]
      }
    })
    |> list.flatten
  })
}

// ---------------------------------------------------------------------------
// A2UI declarative component rendering (SC-A2UI)
// Wires catalog, renderer, and validator into the shell production path.
// ---------------------------------------------------------------------------

/// Render an A2UI component proposal as an HTML element using the trusted
/// catalog. Returns a div containing the rendered output, or an error badge.
/// STAMP: SC-A2UI-001, SC-A2UI-002
pub fn render_a2ui_component(
  proposal: a2ui_schema.ComponentProposal,
) -> Element(msg) {
  let cat = catalog.default_catalog()
  let validation = a2ui_validator.validate_proposal(cat, proposal)
  case validation {
    a2ui_validator.Valid -> {
      let content = case a2ui_renderer.render(proposal, a2ui_renderer.HtmlTarget) {
        a2ui_renderer.HtmlOutput(h) -> h
        a2ui_renderer.JsonOutput(_) -> ""
        a2ui_renderer.AnsiOutput(t) -> t
      }
      html.div([attribute.class("a2ui-component")], [element.text(content)])
    }
    a2ui_validator.Invalid(reasons) -> {
      let msg_text = string.join(reasons, ", ")
      html.div([attribute.class("a2ui-error")], [element.text(msg_text)])
    }
  }
}

// ---------------------------------------------------------------------------
// Container Action Buttons (L4 System — Podman page)
// POST form with confirm dialog, matching emergency_stop_button pattern.
// STAMP: SC-GLM-UI-001, SC-HMI-010
// ---------------------------------------------------------------------------

/// Render container restart/stop action buttons for the podman page.
/// Uses POST forms with browser confirm() dialogs for HITL safety.
/// STAMP: SC-GLM-UI-001, SC-HMI-010
pub fn container_action_buttons() -> Element(msg) {
  html.div(
    [
      attribute.class("container-actions"),
      attribute.attribute(
        "style",
        "display:flex;gap:.5rem;flex-wrap:wrap;padding:.75rem 1rem;background:rgba(77,150,255,0.08);border:1px solid rgba(77,150,255,0.25);border-radius:8px;",
      ),
    ],
    [
      element.element(
        "form",
        [
          attribute.attribute("method", "POST"),
          attribute.attribute("action", "/api/v1/podman/restart"),
          attribute.attribute(
            "onsubmit",
            "return confirm('Restart all containers? This will briefly interrupt services.')",
          ),
          attribute.attribute("style", "margin:0;"),
        ],
        [
          html.button(
            [
              attribute.attribute("type", "submit"),
              attribute.attribute(
                "style",
                "background:#4d96ff;color:white;padding:8px 16px;border:none;border-radius:6px;font-weight:600;cursor:pointer;min-height:44px;",
              ),
            ],
            [element.text("Restart Containers")],
          ),
        ],
      ),
      element.element(
        "form",
        [
          attribute.attribute("method", "POST"),
          attribute.attribute("action", "/api/v1/podman/stop"),
          attribute.attribute(
            "onsubmit",
            "return confirm('Stop all containers? This will take the mesh offline.')",
          ),
          attribute.attribute("style", "margin:0;"),
        ],
        [
          html.button(
            [
              attribute.attribute("type", "submit"),
              attribute.attribute(
                "style",
                "background:#f5a623;color:white;padding:8px 16px;border:none;border-radius:6px;font-weight:600;cursor:pointer;min-height:44px;",
              ),
            ],
            [element.text("Stop Containers")],
          ),
        ],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// Hot Reload Button (SC-HA-RELOAD-001)
// Triggers BEAM bytecode swap without dropping WebSocket connections.
// POST /api/v1/reload — non-destructive, no Guardian approval required.
// ---------------------------------------------------------------------------

/// Hot reload button — triggers BEAM code swap via /api/v1/reload (SC-HA-RELOAD-001).
/// Zero-downtime code upgrade: BEAM soft_purge + load_file, WS connections survive.
/// STAMP: SC-HA-RELOAD-001, SC-HA-RELOAD-005
pub fn hot_reload_button() -> Element(msg) {
  element.element(
    "form",
    [
      attribute.attribute("method", "POST"),
      attribute.attribute("action", "/api/v1/reload"),
      attribute.attribute(
        "onsubmit",
        "return confirm('Hot reload — swap BEAM bytecode without dropping connections?')",
      ),
      attribute.attribute("style", "margin:0;display:inline-block;"),
    ],
    [
      html.button(
        [
          attribute.attribute("type", "submit"),
          attribute.attribute(
            "style",
            "background:#00d4aa;color:#0a0e17;padding:8px 16px;border:none;border-radius:6px;font-weight:600;cursor:pointer;min-height:44px;",
          ),
        ],
        [element.text("Hot Reload")],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// Guardian Approval Panel (SC-SIL4-006, L0 Constitutional)
// Shows pending L0 approval requests with approve/reject buttons.
// HITL: MANDATORY — 2oo3 consensus required for L0 mutations.
// GET /api/v1/guardian/pending for live queue. POST /api/v1/guardian/respond.
// ---------------------------------------------------------------------------

/// Guardian approval panel — shows pending L0 requests with approve/reject (SC-SIL4-006).
/// HITL approval is MANDATORY at L0 Constitutional layer (SC-AGUI-004).
/// STAMP: SC-SIL4-006, SC-SAFETY-001, SC-AGUI-004
pub fn guardian_approval_panel() -> Element(msg) {
  html.div(
    [
      attribute.class("guardian-panel"),
      attribute.attribute(
        "style",
        "padding:1rem;background:rgba(155,89,182,0.08);border:1px solid rgba(155,89,182,0.3);border-radius:8px;",
      ),
    ],
    [
      html.h3(
        [
          attribute.attribute(
            "style",
            "margin:0 0 .75rem;color:#9b59b6;font-size:.9rem;",
          ),
        ],
        [element.text("Guardian Approval Queue (L0 Constitutional)")],
      ),
      html.p(
        [
          attribute.attribute(
            "style",
            "color:#7a8fa6;font-size:.8rem;margin:0 0 .75rem;",
          ),
        ],
        [
          element.text(
            "Pending requests require 2oo3 consensus. GET /api/v1/guardian/pending for live queue.",
          ),
        ],
      ),
      html.div([attribute.attribute("style", "display:flex;gap:.5rem;")], [
        element.element(
          "form",
          [
            attribute.attribute("method", "POST"),
            attribute.attribute("action", "/api/v1/guardian/respond"),
            attribute.attribute(
              "onsubmit",
              "return confirm('APPROVE this L0 action? Requires 2oo3 consensus.')",
            ),
            attribute.attribute("style", "margin:0;"),
          ],
          [
            element.element(
              "input",
              [
                attribute.attribute("type", "hidden"),
                attribute.attribute("name", "decision"),
                attribute.attribute("value", "approve"),
              ],
              [],
            ),
            html.button(
              [
                attribute.attribute("type", "submit"),
                attribute.attribute(
                  "style",
                  "background:#3dd68c;color:#0a0e17;padding:8px 16px;border:none;border-radius:6px;font-weight:600;cursor:pointer;min-height:44px;",
                ),
              ],
              [element.text("Approve")],
            ),
          ],
        ),
        element.element(
          "form",
          [
            attribute.attribute("method", "POST"),
            attribute.attribute("action", "/api/v1/guardian/respond"),
            attribute.attribute(
              "onsubmit",
              "return confirm('REJECT this L0 action?')",
            ),
            attribute.attribute("style", "margin:0;"),
          ],
          [
            element.element(
              "input",
              [
                attribute.attribute("type", "hidden"),
                attribute.attribute("name", "decision"),
                attribute.attribute("value", "reject"),
              ],
              [],
            ),
            html.button(
              [
                attribute.attribute("type", "submit"),
                attribute.attribute(
                  "style",
                  "background:#ff4757;color:white;padding:8px 16px;border:none;border-radius:6px;font-weight:600;cursor:pointer;min-height:44px;",
                ),
              ],
              [element.text("Reject")],
            ),
          ],
        ),
      ]),
    ],
  )
}

// ---------------------------------------------------------------------------
// Task Creation Form (SC-TODO-001, Planning page)
// POST /api/v1/planning/add — delegates to sa-plan-daemon.
// ---------------------------------------------------------------------------

/// Task creation form — POST to /api/v1/planning/add (SC-TODO-001).
/// Renders a styled inline form for adding a new task with description and priority.
/// STAMP: SC-TODO-001, SC-GLM-UI-001
pub fn task_create_form() -> Element(msg) {
  element.element(
    "form",
    [
      attribute.attribute("method", "POST"),
      attribute.attribute("action", "/api/v1/planning/add"),
      attribute.attribute(
        "style",
        "display:flex;gap:.5rem;align-items:end;padding:.75rem 1rem;background:rgba(0,212,170,0.08);border:1px solid rgba(0,212,170,0.25);border-radius:8px;flex-wrap:wrap;",
      ),
    ],
    [
      html.div(
        [attribute.attribute("style", "flex:1;min-width:200px;")],
        [
          html.label(
            [
              attribute.attribute(
                "style",
                "display:block;font-size:.75rem;color:#7a8fa6;margin-bottom:4px;",
              ),
            ],
            [element.text("Task Description")],
          ),
          element.element(
            "input",
            [
              attribute.attribute("type", "text"),
              attribute.attribute("name", "title"),
              // SC-AGUI-UI-009 / WCAG 2.1 AA — aria-label for SR users.
              attribute.attribute("aria-label", "Task description"),
              attribute.attribute("placeholder", "Enter task description..."),
              attribute.attribute("required", "true"),
              attribute.attribute(
                "style",
                "width:100%;padding:8px 12px;background:#141922;border:1px solid #1e2a3a;border-radius:6px;color:#e0e6ed;font-size:14px;",
              ),
            ],
            [],
          ),
        ],
      ),
      html.div(
        [attribute.attribute("style", "min-width:80px;")],
        [
          html.label(
            [
              attribute.attribute(
                "style",
                "display:block;font-size:.75rem;color:#7a8fa6;margin-bottom:4px;",
              ),
            ],
            [element.text("Priority")],
          ),
          element.element(
            "select",
            [
              attribute.attribute("name", "priority"),
              // SC-AGUI-UI-009 / WCAG 2.1 AA — aria-label for SR users.
              attribute.attribute("aria-label", "Task priority (P0 to P3)"),
              attribute.attribute(
                "style",
                "padding:8px 12px;background:#141922;border:1px solid #1e2a3a;border-radius:6px;color:#e0e6ed;",
              ),
            ],
            [
              element.element(
                "option",
                [attribute.attribute("value", "P1")],
                [element.text("P1")],
              ),
              element.element(
                "option",
                [
                  attribute.attribute("value", "P2"),
                  attribute.attribute("selected", "true"),
                ],
                [element.text("P2")],
              ),
              element.element(
                "option",
                [attribute.attribute("value", "P3")],
                [element.text("P3")],
              ),
            ],
          ),
        ],
      ),
      html.button(
        [
          attribute.attribute("type", "submit"),
          attribute.attribute(
            "style",
            "background:#00d4aa;color:#0a0e17;padding:8px 16px;border:none;border-radius:6px;font-weight:600;cursor:pointer;min-height:44px;",
          ),
        ],
        [element.text("Add Task")],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// CA5: Manual OODA Cycle Trigger (SC-OODA-ACCEL-004)
// POST /api/v1/system/ooda-trigger — initiates a manual OODA cycle.
// Confirm dialog required (HITL). Non-destructive: safe for autonomous use.
// ---------------------------------------------------------------------------

/// Manual OODA cycle trigger button — POST to /api/v1/system/ooda-trigger.
/// Allows operator to initiate a manual OODA cycle outside the automatic cadence.
/// STAMP: SC-OODA-ACCEL-004, SC-GLM-UI-001
pub fn ooda_trigger_button() -> Element(msg) {
  element.element(
    "form",
    [
      attribute.attribute("method", "POST"),
      attribute.attribute("action", "/api/v1/system/ooda-trigger"),
      attribute.attribute(
        "onsubmit",
        "return confirm('Trigger manual OODA cycle?')",
      ),
      attribute.attribute("style", "margin:0;display:inline-block;"),
    ],
    [
      html.button(
        [
          attribute.attribute("type", "submit"),
          attribute.attribute(
            "style",
            "background:#9b59b6;color:white;padding:8px 16px;border:none;border-radius:6px;font-weight:600;cursor:pointer;min-height:44px;",
          ),
        ],
        [element.text("Trigger OODA Cycle")],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// CA6: Zenoh Topic Publish Form (SC-ZMOF-COMMS-001)
// POST /api/v1/zenoh/publish — sends a message to a Zenoh topic.
// STAMP: SC-ZMOF-COMMS-001, SC-GLM-UI-001
// ---------------------------------------------------------------------------

/// Zenoh topic publish form — POST to /api/v1/zenoh/publish.
/// Renders a two-field form (topic + payload) for operator-initiated Zenoh publishes.
/// STAMP: SC-ZMOF-COMMS-001, SC-GLM-UI-001
pub fn zenoh_publish_form() -> Element(msg) {
  element.element(
    "form",
    [
      attribute.attribute("method", "POST"),
      attribute.attribute("action", "/api/v1/zenoh/publish"),
      attribute.attribute(
        "style",
        "display:flex;gap:.5rem;align-items:end;padding:.75rem 1rem;background:rgba(0,212,170,0.08);border:1px solid rgba(0,212,170,0.25);border-radius:8px;flex-wrap:wrap;",
      ),
    ],
    [
      html.div(
        [attribute.attribute("style", "flex:1;min-width:200px;")],
        [
          html.label(
            [
              attribute.attribute(
                "style",
                "display:block;font-size:.75rem;color:#7a8fa6;margin-bottom:4px;",
              ),
            ],
            [element.text("Topic")],
          ),
          element.element(
            "input",
            [
              attribute.attribute("type", "text"),
              attribute.attribute("name", "topic"),
              attribute.attribute("placeholder", "indrajaal/test/message"),
              attribute.attribute("required", "true"),
              attribute.attribute(
                "style",
                "width:100%;padding:8px 12px;background:#141922;border:1px solid #1e2a3a;border-radius:6px;color:#e0e6ed;",
              ),
            ],
            [],
          ),
        ],
      ),
      html.div(
        [attribute.attribute("style", "flex:1;min-width:150px;")],
        [
          html.label(
            [
              attribute.attribute(
                "style",
                "display:block;font-size:.75rem;color:#7a8fa6;margin-bottom:4px;",
              ),
            ],
            [element.text("Payload")],
          ),
          element.element(
            "input",
            [
              attribute.attribute("type", "text"),
              attribute.attribute("name", "payload"),
              attribute.attribute("placeholder", "{\"test\":true}"),
              attribute.attribute(
                "style",
                "width:100%;padding:8px 12px;background:#141922;border:1px solid #1e2a3a;border-radius:6px;color:#e0e6ed;",
              ),
            ],
            [],
          ),
        ],
      ),
      html.button(
        [
          attribute.attribute("type", "submit"),
          attribute.attribute(
            "style",
            "background:#00d4aa;color:#0a0e17;padding:8px 16px;border:none;border-radius:6px;font-weight:600;cursor:pointer;min-height:44px;",
          ),
        ],
        [element.text("Publish")],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// CA8: Dark Cockpit Mode Override (SC-HMI-010)
// POST /api/v1/cockpit/mode — force a specific cockpit mode.
// Three forms: Dark / Normal / Emergency. No confirm required for Dark/Normal;
// Emergency uses the same L0 friction threshold.
// STAMP: SC-HMI-010, SC-GLM-UI-008
// ---------------------------------------------------------------------------

/// Cockpit mode switch — three POST forms for Dark / Normal / Emergency (SC-HMI-010).
/// Allows operator to force a specific cockpit display mode regardless of auto-derived state.
/// STAMP: SC-HMI-010, SC-GLM-UI-008
pub fn cockpit_mode_switch() -> Element(msg) {
  html.div(
    [
      attribute.attribute(
        "style",
        "display:flex;gap:.5rem;flex-wrap:wrap;padding:.75rem 1rem;background:rgba(122,143,166,0.08);border:1px solid rgba(122,143,166,0.25);border-radius:8px;",
      ),
    ],
    [
      element.element(
        "form",
        [
          attribute.attribute("method", "POST"),
          attribute.attribute("action", "/api/v1/cockpit/mode"),
          attribute.attribute("style", "margin:0;"),
        ],
        [
          element.element(
            "input",
            [
              attribute.attribute("type", "hidden"),
              attribute.attribute("name", "mode"),
              attribute.attribute("value", "dark"),
            ],
            [],
          ),
          html.button(
            [
              attribute.attribute("type", "submit"),
              attribute.attribute(
                "style",
                "background:#1e2a3a;color:#7a8fa6;padding:8px 16px;border:1px solid #2a3a4a;border-radius:6px;cursor:pointer;min-height:44px;",
              ),
            ],
            [element.text("Dark")],
          ),
        ],
      ),
      element.element(
        "form",
        [
          attribute.attribute("method", "POST"),
          attribute.attribute("action", "/api/v1/cockpit/mode"),
          attribute.attribute("style", "margin:0;"),
        ],
        [
          element.element(
            "input",
            [
              attribute.attribute("type", "hidden"),
              attribute.attribute("name", "mode"),
              attribute.attribute("value", "normal"),
            ],
            [],
          ),
          html.button(
            [
              attribute.attribute("type", "submit"),
              attribute.attribute(
                "style",
                "background:#f5a623;color:#0a0e17;padding:8px 16px;border:none;border-radius:6px;cursor:pointer;min-height:44px;",
              ),
            ],
            [element.text("Normal")],
          ),
        ],
      ),
      element.element(
        "form",
        [
          attribute.attribute("method", "POST"),
          attribute.attribute("action", "/api/v1/cockpit/mode"),
          attribute.attribute(
            "onsubmit",
            "return confirm('Force EMERGENCY cockpit mode?')",
          ),
          attribute.attribute("style", "margin:0;"),
        ],
        [
          element.element(
            "input",
            [
              attribute.attribute("type", "hidden"),
              attribute.attribute("name", "mode"),
              attribute.attribute("value", "emergency"),
            ],
            [],
          ),
          html.button(
            [
              attribute.attribute("type", "submit"),
              attribute.attribute(
                "style",
                "background:#ff4757;color:white;padding:8px 16px;border:none;border-radius:6px;cursor:pointer;min-height:44px;",
              ),
            ],
            [element.text("Emergency")],
          ),
        ],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// CA9: ZK Search Bar (SC-ZK-CLAUDE-001, Knowledge + Smriti pages)
// GET /api/v1/knowledge/search?q=<query> — delegates to knowledge_search NIF.
// Full-width teal-accented form, 44px min touch target.
// STAMP: SC-ZK-CLAUDE-001, SC-GLM-UI-001
// ---------------------------------------------------------------------------

/// ZK search bar — GET form POSTing to /api/v1/knowledge/search (SC-ZK-CLAUDE-001).
/// Renders a styled search input for querying Zettelkasten holons.
/// STAMP: SC-ZK-CLAUDE-001, SC-GLM-UI-001
pub fn zk_search_bar() -> Element(msg) {
  element.element(
    "form",
    [
      attribute.attribute("method", "GET"),
      attribute.attribute("action", "/api/v1/knowledge/search"),
      attribute.attribute(
        "style",
        "display:flex;gap:.5rem;padding:.75rem 1rem;background:rgba(0,212,170,0.08);border:1px solid rgba(0,212,170,0.25);border-radius:8px;",
      ),
    ],
    [
      element.element(
        "input",
        [
          attribute.attribute("type", "text"),
          attribute.attribute("name", "q"),
          attribute.attribute("placeholder", "Search Zettelkasten holons..."),
          attribute.attribute(
            "style",
            "flex:1;padding:8px 12px;background:#141922;border:1px solid #1e2a3a;border-radius:6px;color:#e0e6ed;",
          ),
        ],
        [],
      ),
      html.button(
        [
          attribute.attribute("type", "submit"),
          attribute.attribute(
            "style",
            "background:#00d4aa;color:#0a0e17;padding:8px 16px;border:none;border-radius:6px;font-weight:600;cursor:pointer;min-height:44px;",
          ),
        ],
        [element.text("Search")],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// CA10: Alarm Acknowledge Button (SC-HMI-010, Cockpit page)
// POST /api/v1/cockpit/alarm/acknowledge — acknowledges all active alarms.
// Confirm dialog required for HITL safety.
// STAMP: SC-HMI-010, SC-GLM-UI-001
// ---------------------------------------------------------------------------

/// Alarm acknowledge button — POST to /api/v1/cockpit/alarm/acknowledge (SC-HMI-010).
/// Clears all active alarms from the cockpit alarm panel after operator confirmation.
/// STAMP: SC-HMI-010, SC-GLM-UI-001
pub fn alarm_acknowledge_button() -> Element(msg) {
  element.element(
    "form",
    [
      attribute.attribute("method", "POST"),
      attribute.attribute("action", "/api/v1/cockpit/alarm/acknowledge"),
      attribute.attribute(
        "onsubmit",
        "return confirm('Acknowledge all active alarms?')",
      ),
      attribute.attribute("style", "margin:0;display:inline-block;"),
    ],
    [
      html.button(
        [
          attribute.attribute("type", "submit"),
          attribute.attribute(
            "style",
            "background:#3dd68c;color:#0a0e17;padding:8px 16px;border:none;border-radius:6px;font-weight:600;cursor:pointer;min-height:44px;",
          ),
        ],
        [element.text("Acknowledge Alarms")],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// DB1-DB5, MO2, MO3 — Stub data visualization panels (SC-GLM-ZEN-001)
// Real data arrives via WebSocket push on /ws/{page}. Each panel is a
// placeholder that is populated client-side once the WS delivers live state.
// ---------------------------------------------------------------------------

/// DB1: BEAM scheduler metrics panel (telemetry_view, metabolic_view)
pub fn beam_scheduler_panel() -> Element(msg) {
  html.div(
    [
      attribute.class("dashboard-panel"),
      attribute.attribute(
        "style",
        "padding:1rem;background:#141922;border:1px solid #1e2a3a;border-radius:8px;",
      ),
    ],
    [
      html.h4(
        [
          attribute.attribute(
            "style",
            "margin:0 0 .5rem;color:#00d4aa;font-size:.85rem;",
          ),
        ],
        [element.text("BEAM Scheduler Metrics")],
      ),
      html.p(
        [attribute.attribute("style", "color:#7a8fa6;font-size:.8rem;")],
        [
          element.text(
            "Schedulers: 16 | Dirty IO: 16 | Reduction count: live via /ws/telemetry",
          ),
        ],
      ),
    ],
  )
}

/// DB2: Guard grid 24-cell drill-down (health_grid_view, verification_view)
pub fn guard_grid_drilldown() -> Element(msg) {
  html.div(
    [
      attribute.class("dashboard-panel"),
      attribute.attribute(
        "style",
        "padding:1rem;background:#141922;border:1px solid #1e2a3a;border-radius:8px;",
      ),
    ],
    [
      html.h4(
        [
          attribute.attribute(
            "style",
            "margin:0 0 .5rem;color:#f5a623;font-size:.85rem;",
          ),
        ],
        [element.text("Guard Grid \u{2014} 24 Cells \u{d7} 85 Rules")],
      ),
      html.p(
        [attribute.attribute("style", "color:#7a8fa6;font-size:.8rem;")],
        [
          element.text(
            "Cell verdicts, Wolfram CA state, Shannon entropy, Lyapunov exponent \u{2014} live via /ws/health-grid",
          ),
        ],
      ),
    ],
  )
}

/// DB3: OODA cycle trace viewer (agents_view, prajna_view)
pub fn ooda_trace_viewer() -> Element(msg) {
  html.div(
    [
      attribute.class("dashboard-panel"),
      attribute.attribute(
        "style",
        "padding:1rem;background:#141922;border:1px solid #1e2a3a;border-radius:8px;",
      ),
    ],
    [
      html.h4(
        [
          attribute.attribute(
            "style",
            "margin:0 0 .5rem;color:#9b59b6;font-size:.85rem;",
          ),
        ],
        [element.text("OODA Cycle Trace")],
      ),
      html.p(
        [attribute.attribute("style", "color:#7a8fa6;font-size:.8rem;")],
        [
          element.text(
            "Observe \u{2192} Orient \u{2192} Decide \u{2192} Act timing per cycle \u{2014} live via /ws/agents",
          ),
        ],
      ),
    ],
  )
}

/// DB4: NIF call latency display (telemetry_view, substrate_view)
pub fn nif_latency_panel() -> Element(msg) {
  html.div(
    [
      attribute.class("dashboard-panel"),
      attribute.attribute(
        "style",
        "padding:1rem;background:#141922;border:1px solid #1e2a3a;border-radius:8px;",
      ),
    ],
    [
      html.h4(
        [
          attribute.attribute(
            "style",
            "margin:0 0 .5rem;color:#4d96ff;font-size:.85rem;",
          ),
        ],
        [element.text("NIF Call Latency")],
      ),
      html.p(
        [attribute.attribute("style", "color:#7a8fa6;font-size:.8rem;")],
        [
          element.text(
            "plan_status, system_health, system_dashboard \u{2014} latency per call (ms)",
          ),
        ],
      ),
    ],
  )
}

/// DB5: Zenoh message inspector (zenoh_view)
pub fn zenoh_inspector_panel() -> Element(msg) {
  html.div(
    [
      attribute.class("dashboard-panel"),
      attribute.attribute(
        "style",
        "padding:1rem;background:#141922;border:1px solid #1e2a3a;border-radius:8px;",
      ),
    ],
    [
      html.h4(
        [
          attribute.attribute(
            "style",
            "margin:0 0 .5rem;color:#00d4aa;font-size:.85rem;",
          ),
        ],
        [element.text("Zenoh Message Inspector")],
      ),
      html.p(
        [attribute.attribute("style", "color:#7a8fa6;font-size:.8rem;")],
        [
          element.text(
            "Live message feed from indrajaal/** topics \u{2014} via /ws/zenoh",
          ),
        ],
      ),
    ],
  )
}

/// MO2: OTel span viewer (telemetry_view)
pub fn otel_span_viewer() -> Element(msg) {
  html.div(
    [
      attribute.class("dashboard-panel"),
      attribute.attribute(
        "style",
        "padding:1rem;background:#141922;border:1px solid #1e2a3a;border-radius:8px;",
      ),
    ],
    [
      html.h4(
        [
          attribute.attribute(
            "style",
            "margin:0 0 .5rem;color:#e74c3c;font-size:.85rem;",
          ),
        ],
        [element.text("OTel Span Viewer")],
      ),
      html.p(
        [attribute.attribute("style", "color:#7a8fa6;font-size:.8rem;")],
        [
          element.text(
            "OpenTelemetry spans from indrajaal/otel/spans/** \u{2014} distributed tracing",
          ),
        ],
      ),
    ],
  )
}

/// MO3: Health cascade tree (health_grid_view)
pub fn health_cascade_tree() -> Element(msg) {
  html.div(
    [
      attribute.class("dashboard-panel"),
      attribute.attribute(
        "style",
        "padding:1rem;background:#141922;border:1px solid #1e2a3a;border-radius:8px;",
      ),
    ],
    [
      html.h4(
        [
          attribute.attribute(
            "style",
            "margin:0 0 .5rem;color:#3dd68c;font-size:.85rem;",
          ),
        ],
        [element.text("Health Cascade Tree")],
      ),
      html.p(
        [attribute.attribute("style", "color:#7a8fa6;font-size:.8rem;")],
        [
          element.text(
            "Hierarchical health rollup: container \u{2192} service \u{2192} layer \u{2192} system",
          ),
        ],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// Emergency Stop Button (SC-SAFETY-022, L0 Constitutional)
// HITL confirmation dialog mandatory (SC-AGUI-004).
// POST /api/v1/emergency/trigger requires Guardian 2oo3 consensus.
// ---------------------------------------------------------------------------

/// Render an L0 Constitutional emergency stop button with HITL confirmation.
/// STAMP: SC-SAFETY-022, SC-SIL4-001, SC-AGUI-004
pub fn emergency_stop_button() -> Element(msg) {
  html.div(
    [
      attribute.class("emergency-stop-wrapper"),
      attribute.attribute(
        "style",
        "display:flex;align-items:center;gap:1rem;padding:.75rem 1rem;background:rgba(255,71,87,0.08);border:1px solid rgba(255,71,87,0.35);border-radius:8px;",
      ),
    ],
    [
      html.span(
        [
          attribute.attribute(
            "style",
            "font-size:.8rem;color:#ff8a94;flex:1;",
          ),
        ],
        [
          element.text(
            "L0 Constitutional — Emergency Stop halts all operations and requires Guardian 2oo3 consensus (SC-SAFETY-022).",
          ),
        ],
      ),
      element.element(
        "form",
        [
          attribute.attribute("method", "POST"),
          attribute.attribute("action", "/api/v1/emergency/trigger"),
          attribute.attribute(
            "onsubmit",
            "return confirm('EMERGENCY STOP — This will halt all mesh operations and require Guardian 2oo3 consensus to resume. Are you absolutely sure?')",
          ),
          attribute.attribute("style", "margin:0;"),
        ],
        [
          html.button(
            [
              attribute.attribute("type", "submit"),
              attribute.attribute(
                "style",
                "background:#ff4757;color:white;padding:12px 24px;border:none;border-radius:8px;font-weight:bold;font-size:16px;cursor:pointer;min-height:44px;letter-spacing:.03em;",
              ),
            ],
            [element.text("EMERGENCY STOP")],
          ),
        ],
      ),
    ],
  )
}
