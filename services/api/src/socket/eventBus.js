import events from '../../../../packages/api_contracts/events.json' with { type: 'json' };

let socketServer;

export function setSocketServer(io) {
  socketServer = io;
}

export function emitNewMessage(message, participantIds) {
  if (!socketServer) return;
  let rooms = socketServer.to(`thread:${message.threadId}`);
  for (const userId of participantIds) {
    rooms = rooms.to(`user:${userId}`);
  }
  rooms.emit(events.messageNew, message);
}

export function emitReadReceipt(receipt) {
  socketServer
    ?.to(`thread:${receipt.threadId}`)
    .emit(events.messageRead, receipt);
}

export function emitNotification(notification) {
  socketServer
    ?.to(`user:${notification.userId}`)
    .emit(events.notificationNew, notification);
}

export function disconnectUser(userId) {
  socketServer?.in(`user:${userId}`).disconnectSockets(true);
}

export function disconnectSession(sessionId) {
  socketServer?.in(`session:${sessionId}`).disconnectSockets(true);
}
