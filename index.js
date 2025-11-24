const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.send('<h1>DevOps Sandbox Sample App</h1>\n<p>This is a simple Express server used for long-running Cypress tests.</p>');
});

app.get('/health', (req, res) => res.json({ status: 'ok' }));

app.listen(port, () => {
  console.log(`Server listening on http://0.0.0.0:${port}`);
});
