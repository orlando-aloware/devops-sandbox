// Quick test version with 10 second wait instead of 3 hours
describe('Quick test', () => {
  it('visits app and waits 10 seconds', { defaultCommandTimeout: 60000 }, () => {
    cy.visit('/')
    cy.contains('DevOps Sandbox Sample App')
    
    cy.log('Starting 10 second wait...')
    cy.wait(10000)
    
    cy.log('Quick test complete')
  })
})
