const COLS = 12, ROWS = 20, BLOCK = 20;
const canvas = document.getElementById('board');
const ctx = canvas.getContext('2d');
const nextCanvas = document.getElementById('next');
const nextCtx = nextCanvas.getContext('2d');
const scoreEl = document.getElementById('score');
const linesEl = document.getElementById('lines');

const COLORS = [null, '#38bdf8', '#f472b6', '#facc15', '#4ade80', '#a78bfa', '#fb923c', '#f87171'];
const SHAPES = [
  [],
  [[1,1,1,1]],
  [[2,0,0],[2,2,2]],
  [[0,0,3],[3,3,3]],
  [[4,4],[4,4]],
  [[0,5,5],[5,5,0]],
  [[0,6,0],[6,6,6]],
  [[7,7,0],[0,7,7]]
];

let board = Array.from({length: ROWS}, () => Array(COLS).fill(0));
let score = 0, lines = 0;
let current, next, pos;
let dropCounter = 0, dropInterval = 800, lastTime = 0;

function randomPiece() {
  const id = 1 + Math.floor(Math.random() * 7);
  return { shape: SHAPES[id].map(r => [...r]), id };
}

function spawn() {
  current = next || randomPiece();
  next = randomPiece();
  pos = { x: Math.floor(COLS / 2) - Math.ceil(current.shape[0].length / 2), y: 0 };
  if (collide()) { board = Array.from({length: ROWS}, () => Array(COLS).fill(0)); score = 0; lines = 0; updateHUD(); }
}

function collide(shape = current.shape, ox = pos.x, oy = pos.y) {
  for (let y = 0; y < shape.length; y++)
    for (let x = 0; x < shape[y].length; x++)
      if (shape[y][x]) {
        const nx = ox + x, ny = oy + y;
        if (nx < 0 || nx >= COLS || ny >= ROWS || (ny >= 0 && board[ny][nx])) return true;
      }
  return false;
}

function merge() {
  current.shape.forEach((row, y) => row.forEach((v, x) => {
    if (v) board[pos.y + y][pos.x + x] = v;
  }));
}

function rotate() {
  const s = current.shape;
  const rotated = s[0].map((_, i) => s.map(row => row[i]).reverse());
  const old = current.shape;
  current.shape = rotated;
  if (collide()) current.shape = old;
}

function clearLines() {
  let cleared = 0;
  outer: for (let y = ROWS - 1; y >= 0; y--) {
    for (let x = 0; x < COLS; x++) if (!board[y][x]) continue outer;
    board.splice(y, 1);
    board.unshift(Array(COLS).fill(0));
    cleared++; y++;
  }
  if (cleared) {
    score += [0, 100, 300, 500, 800][cleared] || cleared * 200;
    lines += cleared;
    updateHUD();
  }
}

function updateHUD() { scoreEl.textContent = score; linesEl.textContent = lines; }

function drop() {
  pos.y++;
  if (collide()) { pos.y--; merge(); clearLines(); spawn(); }
  dropCounter = 0;
}

function hardDrop() { while (!collide(current.shape, pos.x, pos.y + 1)) pos.y++; drop(); }
function move(dir) { pos.x += dir; if (collide()) pos.x -= dir; }

function draw() {
  ctx.fillStyle = '#1e293b';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  board.forEach((row, y) => row.forEach((v, x) => { if (v) drawBlock(ctx, x, y, COLORS[v]); }));
  current.shape.forEach((row, y) => row.forEach((v, x) => {
    if (v) drawBlock(ctx, pos.x + x, pos.y + y, COLORS[v]);
  }));
  nextCtx.fillStyle = '#1e293b';
  nextCtx.fillRect(0, 0, nextCanvas.width, nextCanvas.height);
  next.shape.forEach((row, y) => row.forEach((v, x) => { if (v) drawBlock(nextCtx, x, y, COLORS[v], 18); }));
}

function drawBlock(c, x, y, color, size = BLOCK) {
  c.fillStyle = color;
  c.fillRect(x * size, y * size, size - 1, size - 1);
}

function loop(time = 0) {
  const delta = time - lastTime;
  lastTime = time;
  dropCounter += delta;
  if (dropCounter > dropInterval) drop();
  draw();
  requestAnimationFrame(loop);
}

document.addEventListener('keydown', e => {
  if (e.key === 'ArrowLeft') move(-1);
  else if (e.key === 'ArrowRight') move(1);
  else if (e.key === 'ArrowDown') drop();
  else if (e.key === 'ArrowUp') rotate();
  else if (e.key === ' ') hardDrop();
});

spawn();
loop();

// Show which pod served this page (reads a header injected via /healthz, fallback hidden)
fetch('/healthz').then(r => r.headers.get('X-Pod-Name')).then(p => {
  if (p) document.getElementById('pod').textContent = 'pod: ' + p;
}).catch(() => {});
