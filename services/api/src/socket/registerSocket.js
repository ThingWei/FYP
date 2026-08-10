import events from '../../../../packages/api_contracts/events.json' with { type: 'json' };
export function registerSocket(io) {
  io.on('connection', (socket) => {
    socket.on('thread:join', (threadId) => socket.join(`thread:${threadId}`));
    socket.on(events.messageNew, (message) => io.to(`thread:${message.threadId}`).emit(events.messageNew, message));
    socket.on(events.messageRead, (receipt) => io.to(`thread:${receipt.threadId}`).emit(events.messageRead, receipt));
  });
}

