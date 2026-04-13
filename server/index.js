const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;
const wss = new WebSocketServer({ port: PORT });

// rooms: Map<roomCode, Map<userId, { ws, name, x, y, active }>>
const rooms = new Map();

wss.on('connection', (ws) => {
  let userId = null;
  let roomCode = null;

  ws.on('message', (data) => {
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return;
    }

    const type = msg.type;

    if (type === 'join') {
      userId = msg.userId;
      roomCode = msg.roomCode?.toUpperCase();
      const name = msg.name || 'Anonymous';

      if (!rooms.has(roomCode)) {
        rooms.set(roomCode, new Map());
      }

      const room = rooms.get(roomCode);
      const theme = typeof msg.theme === 'string' ? msg.theme : 'cat';
      room.set(userId, { ws, name, x: 0.85, y: 0.85, active: false, theme });

      // Send current room members to the new joiner
      const users = [...room.entries()]
        .filter(([id]) => id !== userId)
        .map(([id, peer]) => ({
          userId: id,
          name: peer.name,
          x: peer.x,
          y: peer.y,
          active: peer.active,
          theme: peer.theme,
        }));

      safeSend(ws, { type: 'joined', users });
      console.log(`[join] user=${userId} name=${name} room=${roomCode} roomSize=${room.size}`);

      // Notify others
      broadcast(roomCode, userId, { type: 'user_joined', userId, name, theme });

    } else if (type === 'state') {
      if (!userId || !roomCode) return;
      const room = rooms.get(roomCode);
      if (!room) return;

      const peer = room.get(userId);
      if (peer) {
        peer.x = msg.x ?? peer.x;
        peer.y = msg.y ?? peer.y;
        peer.active = msg.active ?? peer.active;
      }

      const payload = {
        type: 'state',
        userId,
        x: msg.x,
        y: msg.y,
        active: msg.active,
        combo: msg.combo,
        sleeping: msg.sleeping,
      };
      console.log(`[state] from=${userId} active=${msg.active} combo=${msg.combo} -> ${room.size - 1} peers`);
      broadcast(roomCode, userId, payload);

    } else if (type === 'theme') {
      if (!userId || !roomCode) return;
      const room = rooms.get(roomCode);
      if (!room) return;
      const peer = room.get(userId);
      if (!peer) return;
      const newTheme = typeof msg.theme === 'string' ? msg.theme : 'cat';
      peer.theme = newTheme;
      broadcast(roomCode, userId, { type: 'theme', userId, theme: newTheme });

    } else if (type === 'rename') {
      if (!userId || !roomCode) return;
      const room = rooms.get(roomCode);
      if (!room) return;
      const peer = room.get(userId);
      if (!peer) return;
      const newName = typeof msg.name === 'string' ? msg.name.trim().slice(0, 50) : '';
      if (!newName) return;
      peer.name = newName;
      broadcast(roomCode, userId, { type: 'renamed', userId, name: newName });

    } else if (type === 'chat') {
      if (!userId || !roomCode) return;
      const room = rooms.get(roomCode);
      if (!room) return;
      const peer = room.get(userId);
      const senderName = peer ? peer.name : 'Anonymous';
      const text = typeof msg.text === 'string' ? msg.text.trim().slice(0, 500) : '';
      if (!text) return;
      for (const [, p] of room.entries()) {
        safeSend(p.ws, { type: 'chat', userId, name: senderName, text });
      }

    } else if (type === 'leave') {
      handleLeave();
    }
  });

  ws.on('close', () => handleLeave());
  ws.on('error', () => handleLeave());

  function handleLeave() {
    if (!userId || !roomCode) return;
    console.log(`[leave] user=${userId} room=${roomCode}`);
    const room = rooms.get(roomCode);
    if (room) {
      room.delete(userId);
      broadcast(roomCode, userId, { type: 'user_left', userId });
      if (room.size === 0) {
        rooms.delete(roomCode);
      }
    }
    userId = null;
    roomCode = null;
  }
});

function broadcast(roomCode, excludeUserId, message) {
  const room = rooms.get(roomCode);
  if (!room) return;
  const text = JSON.stringify(message);
  for (const [id, peer] of room.entries()) {
    if (id !== excludeUserId) {
      safeSend(peer.ws, text);
    }
  }
}

function safeSend(ws, data) {
  if (ws.readyState !== ws.OPEN) return;
  const text = typeof data === 'string' ? data : JSON.stringify(data);
  ws.send(text);
}

console.log(`catch-catch server running on port ${PORT}`);
