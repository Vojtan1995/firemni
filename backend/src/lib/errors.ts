export class AppError extends Error {
  constructor(
    public statusCode: number,
    public code: string,
    message: string,
  ) {
    super(message);
    this.name = 'AppError';
  }
}

export const notFound = (msg = 'Nenalezeno') => new AppError(404, 'NOT_FOUND', msg);
export const forbidden = (msg = 'Zakázáno') => new AppError(403, 'FORBIDDEN', msg);
export const unauthorized = (msg = 'Neautorizováno') => new AppError(401, 'UNAUTHORIZED', msg);
export const conflict = (msg = 'Konflikt') => new AppError(409, 'CONFLICT', msg);
export const badRequest = (msg = 'Neplatný požadavek') => new AppError(400, 'BAD_REQUEST', msg);
