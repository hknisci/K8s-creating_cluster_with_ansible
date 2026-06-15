'use strict';

const express = require('express');
const router = express.Router();

router.get('/live', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

router.get('/ready', (req, res) => {
  // Add dependency checks here (DB, cache, etc.)
  res.status(200).json({ status: 'ready' });
});

module.exports = router;
