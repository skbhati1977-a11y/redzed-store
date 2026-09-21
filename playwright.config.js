const { defineConfig, devices } = require("@playwright/test");

const baseURL = process.env.E2E_BASE_URL ||
  "https://redzed-test65-git-test71-real-chat-e2e-6adad3-skbhati1977-4414.vercel.app";

module.exports = defineConfig({
  testDir: "./tests/e2e",
  timeout: 60_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
    ...devices["Desktop Chrome"]
  },
  projects: [
    {
      name: "auth-setup",
      testMatch: /auth\.setup\.js/
    },
    {
      name: "checkpoint-0",
      testMatch: /checkpoint-0\.spec\.js/,
      dependencies: ["auth-setup"],
      use: { storageState: "playwright/.auth/super-admin.json" }
    },
    {
      name: "checkpoint-1",
      testMatch: /checkpoint-1\.spec\.js/,
      dependencies: ["auth-setup"],
      use: { storageState: "playwright/.auth/super-admin.json" }
    },
    {
      name: "checkpoint-2",
      testMatch: /checkpoint-2\.spec\.js/,
      dependencies: ["auth-setup"],
      use: { storageState: "playwright/.auth/super-admin.json" }
    },
    {
      name: "checkpoint-3",
      testMatch: /checkpoint-3\.spec\.js/,
      dependencies: ["auth-setup"],
      use: { storageState: "playwright/.auth/super-admin.json" }
    },
    {
      name: "checkpoint-4",
      testMatch: /checkpoint-4\.spec\.js/,
      dependencies: ["auth-setup"],
      use: { storageState: "playwright/.auth/super-admin.json" }
    },
    {
      name: "checkpoint-5",
      testMatch: /checkpoint-5\.spec\.js/,
      dependencies: ["auth-setup"],
      use: { storageState: "playwright/.auth/super-admin.json" }
    },
    {
      name: "checkpoint-6",
      testMatch: /checkpoint-6\.spec\.js/,
      dependencies: ["auth-setup"],
      use: { storageState: "playwright/.auth/super-admin.json" }
    },
    {
      name: "checkpoint-7",
      testMatch: /checkpoint-7\.spec\.js/,
      dependencies: ["auth-setup"],
      use: { storageState: "playwright/.auth/super-admin.json" }
    },
    {
      name: "checkpoint-8",
      testMatch: /checkpoint-8-commercial\.spec\.js/,
      dependencies: ["auth-setup"],
      use: { storageState: "playwright/.auth/super-admin.json" }
    },
    {
      name: "mc1",
      testMatch: /mc1-real-chat\.spec\.js/,
      dependencies: ["auth-setup"],
      use: { storageState: "playwright/.auth/super-admin.json" }
    }
  ]
});
