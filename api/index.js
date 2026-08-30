import { server } from '../server/index.js';

export default function handler(req, res) {
  return server.emit('request', req, res);
}
