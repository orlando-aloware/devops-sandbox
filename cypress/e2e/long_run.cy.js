describe('Long running test', () => {
  it('visits app and waits ~3 hours total', { defaultCommandTimeout: 4 * 60 * 60 * 1000, watchForFileChanges: false }, () => {
    // Visit the simple Express app
    cy.visit('/')
    cy.contains('DevOps Sandbox Sample App')

    // Simulate ~1 hour of test activities (60 minutes = 3,600,000 ms)
    cy.log('Starting 1 hour active wait...')
    cy.wait(60 * 60 * 1000)

    // Then a long idle period to extend the run by ~2 hours
    cy.log('Starting 2 hour idle wait...')
    cy.wait(2 * 60 * 60 * 1000)

    cy.log('Long-run test complete')
  })
})
