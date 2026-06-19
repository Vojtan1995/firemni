import { SealTrade } from '@prisma/client';

/** Řemeslo – české popisky pro UI a exporty. */
export const SEAL_TRADE_LABELS: Record<SealTrade, string> = {
  [SealTrade.elektrikari]: 'Elektrikáři',
  [SealTrade.vzduchari]: 'Vzduchaři',
  [SealTrade.vodari]: 'Vodaři',
  [SealTrade.topenari]: 'Topenáři',
  [SealTrade.plynari]: 'Plynaři',
  [SealTrade.ostatni]: 'Ostatní',
  [SealTrade.neurceno]: 'Neurčeno',
};

export function sealTradeLabel(trade: SealTrade | string | null | undefined): string {
  if (!trade) return SEAL_TRADE_LABELS[SealTrade.neurceno];
  return SEAL_TRADE_LABELS[trade as SealTrade] ?? String(trade);
}
