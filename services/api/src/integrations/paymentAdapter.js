import { randomUUID } from 'node:crypto';

function result(operation, amount, status) {
  return {
    id: `sim_${operation}_${randomUUID()}`,
    amount,
    status,
    simulated: true,
  };
}

export const paymentAdapter = {
  async authorize({ amount }) {
    return result('auth', amount, 'authorized');
  },
  async capture({ amount }) {
    return result('capture', amount, 'succeeded');
  },
  async voidAuthorization({ amount }) {
    return result('void', amount, 'voided');
  },
  async refund({ amount }) {
    return result('refund', amount, 'succeeded');
  },
};
