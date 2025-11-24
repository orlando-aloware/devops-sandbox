const { defineConfig } = require('cypress')

module.exports = defineConfig({
  e2e: {
    baseUrl: 'http://localhost:3000',
    specPattern: 'cypress/e2e/**/*.cy.{js,jsx,ts,tsx}',
    setupNodeEvents(on, config) {
      // no-op
    }
  },
  video: false,
  defaultCommandTimeout: 300000,
  requestTimeout: 300000,
  responseTimeout: 300000,
  pageLoadTimeout: 300000,
  watchForFileChanges: false
})
