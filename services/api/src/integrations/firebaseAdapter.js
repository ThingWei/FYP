export const firebaseAdapter = {
  async upload() { throw new Error('Configure Firebase Admin SDK before using uploads'); },
  async notify() { return { queued: true, provider: 'placeholder' }; },
};

