export const config = {
  port: parseInt(process.env.PORT || '3000', 10),
  nodeEnv: process.env.NODE_ENV || 'development',
  databaseUrl: process.env.DATABASE_URL || '',
  jwtSecret: process.env.JWT_SECRET || 'dev-secret-change-me',
  uploadPath: process.env.UPLOAD_PATH || './uploads',
  corsOrigin: process.env.CORS_ORIGIN || '*',
  sessionDays: 7,
};
