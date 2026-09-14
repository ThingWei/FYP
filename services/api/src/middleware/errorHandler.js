export const notFound = (req, _res, next) =>
  next(
    Object.assign(new Error(`Route not found: ${req.method} ${req.path}`), {
      status: 404,
      code: 'NOT_FOUND',
    }),
  );

export const errorHandler = (error, _req, res, _next) => {
  let status = error.status ?? 500;
  let code = error.code ?? 'INTERNAL_ERROR';
  let message = error.message;
  let details = error.details;

  if (error.code === 11000) {
    status = 409;
    code = 'DUPLICATE_RECORD';
    message = `A user with that ${Object.keys(error.keyPattern ?? {})[0] ?? 'value'} already exists`;
  } else if (error.name === 'ValidationError' || error.name === 'StrictModeError') {
    status = 400;
    code = 'VALIDATION_ERROR';
    message = 'Request data is invalid';
    details = Object.values(error.errors ?? {}).map((item) => ({
      field: item.path,
      message: item.message,
    }));
  } else if (error instanceof SyntaxError && error.status === 400) {
    code = 'INVALID_JSON';
    message = 'Request body contains invalid JSON';
  }

  if (status >= 500) {
    console.error(error);
    message = 'Unexpected server error';
  }

  res.status(status).json({
    success: false,
    error: {
      code,
      message,
      ...(details && { details }),
    },
  });
};

