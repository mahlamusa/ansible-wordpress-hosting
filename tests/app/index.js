// Minimal app used to test deploy.yml.
require('http')
  .createServer((req, res) => res.end('awh-test-app ok\n'))
  .listen(3000, '127.0.0.1');
