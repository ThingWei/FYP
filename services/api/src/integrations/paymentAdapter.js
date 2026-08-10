export const paymentAdapter = { async charge({ amount }) { return { id: `sim_${Date.now()}`, amount, status: 'succeeded', simulated: true }; } };

