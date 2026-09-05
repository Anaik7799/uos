//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/telegram/theme</module></identity>
////   <fractal-topology><layer>L2_COMPONENT</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-OPENCLAW-001</stamp-controls></compliance>
//// </c3i-module>
////
//// TeleNative CSS variable constants for Telegram Mini App theming.
//// All colors use Telegram's injected CSS variables — no hardcoded hex.
//// STAMP: SC-GLM-UI-001, SC-OPENCLAW-001

/// Main app background.
pub fn bg_color() -> String {
  "var(--tg-theme-bg-color)"
}

/// Grouping elements, cards, inset backgrounds.
pub fn secondary_bg() -> String {
  "var(--tg-theme-secondary-bg-color)"
}

/// Primary text (headers, body).
pub fn text_color() -> String {
  "var(--tg-theme-text-color)"
}

/// Secondary text, placeholders, sub-labels.
pub fn hint_color() -> String {
  "var(--tg-theme-hint-color)"
}

/// Primary buttons, active icons, toggles.
pub fn button_color() -> String {
  "var(--tg-theme-button-color)"
}

/// Text inside primary buttons.
pub fn button_text_color() -> String {
  "var(--tg-theme-button-text-color)"
}

/// Text links and secondary button text.
pub fn link_color() -> String {
  "var(--tg-theme-link-color)"
}

/// Destructive action color.
pub fn destructive_text_color() -> String {
  "var(--tg-theme-destructive-text-color, #e05252)"
}

/// TeleNative system font stack — matches native OS sans-serif.
pub fn font_family() -> String {
  "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Roboto\", \"Helvetica Neue\", sans-serif"
}

/// Full TeleNative CSS stylesheet for Mini App HTML shell.
/// Uses 8pt grid system, Telegram CSS variables, touch-optimized targets.
pub fn mini_app_css() -> String {
  "
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Roboto', 'Helvetica Neue', sans-serif;
  background: var(--tg-theme-bg-color, #0a0e17);
  color: var(--tg-theme-text-color, #e0e6ed);
  padding: 16px;
  padding-top: calc(16px + env(safe-area-inset-top, 0px));
  padding-bottom: calc(72px + env(safe-area-inset-bottom, 0px));
  -webkit-text-size-adjust: 100%;
  -webkit-tap-highlight-color: transparent;
}
a { color: var(--tg-theme-link-color, #00d4aa); text-decoration: none; }
.tg-card {
  background: var(--tg-theme-secondary-bg-color, #141922);
  border-radius: 12px;
  padding: 16px;
  margin-bottom: 8px;
}
.tg-btn {
  background: var(--tg-theme-button-color, #00d4aa);
  color: var(--tg-theme-button-text-color, #ffffff);
  border: none;
  border-radius: 12px;
  min-height: 48px;
  width: 100%;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  padding: 0 16px;
}
.tg-btn-tonal {
  background: color-mix(in srgb, var(--tg-theme-button-color, #00d4aa) 15%, transparent);
  color: var(--tg-theme-button-color, #00d4aa);
  border: none;
  border-radius: 12px;
  min-height: 48px;
  width: 100%;
  font-size: 16px;
  cursor: pointer;
}
.tg-btn-text {
  background: none;
  color: var(--tg-theme-link-color, #00d4aa);
  border: none;
  font-size: 16px;
  cursor: pointer;
  padding: 8px;
}
.tg-action-btn {
  min-height: 60px;
  font-size: 18px;
  font-weight: 700;
}
.tg-hint { color: var(--tg-theme-hint-color, #7a8fa6); font-size: 14px; }
.tg-link { color: var(--tg-theme-link-color, #00d4aa); }
.tg-status-hero {
  font-size: 28px;
  font-weight: bold;
  padding: 16px 0 8px;
}
.tg-status-sub {
  font-size: 14px;
  color: var(--tg-theme-hint-color, #7a8fa6);
  padding-bottom: 16px;
}
.tg-list-cell {
  display: flex;
  align-items: center;
  padding: 12px 0;
  gap: 12px;
}
.tg-list-cell + .tg-list-cell {
  border-top: 1px solid color-mix(in srgb, var(--tg-theme-hint-color, #7a8fa6) 20%, transparent);
}
.tg-list-icon {
  width: 40px;
  height: 40px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 20px;
  flex-shrink: 0;
}
.tg-list-body { flex: 1; min-width: 0; }
.tg-list-title { font-size: 16px; font-weight: 500; }
.tg-list-subtitle { font-size: 14px; color: var(--tg-theme-hint-color, #7a8fa6); }
.tg-list-chevron { color: var(--tg-theme-hint-color, #7a8fa6); font-size: 14px; flex-shrink: 0; }
.tg-badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 6px;
  font-size: 12px;
  font-weight: 600;
}
.tg-badge-ok { background: rgba(61,214,140,0.2); color: #3dd68c; }
.tg-badge-warn { background: rgba(245,166,35,0.2); color: #f5a623; }
.tg-badge-crit { background: rgba(224,82,82,0.2); color: #e05252; }
.tg-section-title {
  font-size: 14px;
  color: var(--tg-theme-hint-color, #7a8fa6);
  text-transform: uppercase;
  letter-spacing: 0.5px;
  padding: 16px 0 8px;
}
.tg-nav-bar {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background: var(--tg-theme-bg-color, #0a0e17);
  border-top: 1px solid color-mix(in srgb, var(--tg-theme-hint-color, #7a8fa6) 20%, transparent);
  display: flex;
  justify-content: space-around;
  padding: 8px 0;
  padding-bottom: calc(8px + env(safe-area-inset-bottom, 0px));
}
.tg-nav-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;
  font-size: 10px;
  color: var(--tg-theme-hint-color, #7a8fa6);
  text-decoration: none;
  padding: 4px 12px;
}
.tg-nav-item.active { color: var(--tg-theme-button-color, #00d4aa); }
.tg-nav-icon { font-size: 22px; }
.tg-grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.tg-metric-value { font-size: 24px; font-weight: 700; }
.tg-metric-label { font-size: 12px; color: var(--tg-theme-hint-color, #7a8fa6); }
"
}
