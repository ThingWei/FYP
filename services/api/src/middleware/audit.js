export const audit = (req, res, next) => {
  const started = Date.now();
  res.on('finish', () => console.info(JSON.stringify({ type: 'audit', method: req.method, path: req.path, userId: req.user?.id, status: res.statusCode, durationMs: Date.now() - started })));
  next();
};

