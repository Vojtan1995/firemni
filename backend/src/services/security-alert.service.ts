import { config } from '../config.js';
import { logger } from '../lib/logger.js';

export type SecurityAlertKind = 'mfa_recovery_used' | 'mfa_reset';

const descriptions: Record<SecurityAlertKind, string> = {
  mfa_recovery_used: 'Byl použit jednorázový MFA recovery kód.',
  mfa_reset: 'Byl proveden administrativní reset MFA.',
};

export async function sendSecurityAlert(kind: SecurityAlertKind) {
  const token = config.securityAlerts.telegramBotToken;
  const chatId = config.securityAlerts.telegramChatId;
  if (!token || !chatId) return;

  try {
    const response = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId,
        text: `UNIFAST security alert\n${descriptions[kind]}\n${new Date().toISOString()}`,
      }),
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error(`Telegram returned HTTP ${response.status}`);
  } catch (error) {
    logger.warn(
      {
        kind,
        error: error instanceof Error ? error.message : String(error),
      },
      'Security alert delivery failed',
    );
  }
}
