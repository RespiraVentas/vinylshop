// Configuración de los tests de navegador (Playwright).
// Cada test corre dos veces: en una pantalla de escritorio y en un celular.
'use strict';
const { defineConfig, devices } = require('@playwright/test');

const PUERTO = Number(process.env.PUERTO || 4173);

module.exports = defineConfig({
  testDir: './navegador',
  timeout: 30_000,
  expect: { timeout: 7_000 },
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : [['list']],
  use: {
    baseURL: `http://127.0.0.1:${PUERTO}`,
    locale: 'es-AR',
    timezoneId: 'America/Argentina/Buenos_Aires',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'escritorio', use: { ...devices['Desktop Chrome'], viewport: { width: 1366, height: 800 } } },
    { name: 'celular',    use: { ...devices['Pixel 7'] } },
  ],
  // Levanta el sitio local antes de correr (ver servidor.js).
  webServer: {
    command: `node servidor.js ${PUERTO}`,
    url: `http://127.0.0.1:${PUERTO}/`,
    reuseExistingServer: !process.env.CI,
    timeout: 20_000,
  },
});
