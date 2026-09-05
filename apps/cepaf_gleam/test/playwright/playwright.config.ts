/**
 * Playwright configuration for C3I Gleam web UI E2E tests.
 *
 * Target server: Gleam Wisp HTTP server on port 4100 (SC-GLM-UI-006).
 * All 31 pages are tested across Chromium (primary), Firefox, and WebKit.
 *
 * STAMP: SC-GLM-UI-001, SC-GLM-UI-006, SC-UIGT-001
 */

import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./",
  testMatch: "**/*.spec.ts",

  // Allow up to 30 s per test — server may be slow on first load (NIF init).
  timeout: 30_000,
  expect: { timeout: 10_000 },

  // Fail the suite fast if the server is not reachable.
  fullyParallel: false,
  retries: 1,
  workers: 2,

  reporter: [
    ["list"],
    ["html", { outputFolder: "playwright-report", open: "never" }],
  ],

  use: {
    baseURL: "http://localhost:4100",

    // Capture trace on first retry for debugging.
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "off",

    // Match the dark-cockpit color scheme (dark background).
    colorScheme: "dark",
  },

  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "firefox",
      use: { ...devices["Desktop Firefox"] },
    },
    {
      name: "webkit",
      use: { ...devices["Desktop Safari"] },
    },
  ],
});
