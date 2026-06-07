import { describe, it, expect } from '@jest/globals';
import { multiplyMoney } from '../dist/lib/decimal.js';

describe('decimal helpers', () => {
  it('multiplyMoney rounds to 2 decimal places without float drift', () => {
    expect(multiplyMoney(0.1, 3)).toBe(0.3);
    expect(multiplyMoney(19.99, 3)).toBe(59.97);
    expect(multiplyMoney('123.456', 2)).toBe(246.91);
  });
});
