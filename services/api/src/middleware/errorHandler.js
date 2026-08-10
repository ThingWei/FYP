export const notFound = (req, _res, next) => next(Object.assign(new Error(`Route not found: ${req.method} ${req.path}`), { status: 404, code: 'NOT_FOUND' }));
export const errorHandler = (error, _req, res, _next) => {
  const status = error.status ?? 500;
  res.status(status).json({ success: false, error: { code: error.code ?? 'INTERNAL_ERROR', message: status === 500 ? 'Unexpected server error' : error.message, ...(error.details && { details: error.details }) } });
};

