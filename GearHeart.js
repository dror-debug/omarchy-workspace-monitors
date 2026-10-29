.pragma library

// Heart outline whose rim is cut into gear teeth, plus a smooth inner heart
// for the hole. Both are returned as point lists in a unit box (0..1, y down)
// so the caller only has to scale them; draw with the even-odd fill rule.

function heartPoint(t) {
  var s = Math.sin(t)
  return {
    x: 16 * s * s * s,
    y: -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t))
  }
}

function smoothstep(a, b, x) {
  var k = Math.max(0, Math.min(1, (x - a) / (b - a)))
  return k * k * (3 - 2 * k)
}

function build(teeth, toothDepth, holeScale) {
  var n = 720
  var base = []
  for (var i = 0; i < n; i++) base.push(heartPoint(2 * Math.PI * i / n))

  // Arc length, so teeth are evenly spaced around the rim.
  var lengths = [0]
  for (i = 1; i <= n; i++) {
    var a = base[i - 1], b = base[i % n]
    lengths.push(lengths[i - 1] + Math.hypot(b.x - a.x, b.y - a.y))
  }
  var total = lengths[n]

  var outer = []
  for (i = 0; i < n; i++) {
    var prev = base[(i - 3 + n) % n], next = base[(i + 3) % n]
    var dx = next.x - prev.x, dy = next.y - prev.y
    var len = Math.hypot(dx, dy) || 1
    // Outward normal for a clockwise-on-screen curve.
    var nx = -dy / len, ny = dx / len
    // Phase 0 sits on the top dip and (with an even tooth count) on the tip,
    // so both cusps fall in a gap instead of under a tooth.
    var pos = lengths[i] / total * teeth
    var phase = pos % 1
    var tooth = smoothstep(0.2, 0.32, phase) * (1 - smoothstep(0.68, 0.8, phase))
    // Teeth flanking a cusp point into each other; leave the dip and tip smooth.
    var index = Math.floor(pos) % teeth
    if (index === 0 || index === teeth - 1 || index === teeth / 2 || index === teeth / 2 - 1) tooth = 0
    var d = toothDepth * tooth
    outer.push({ x: base[i].x + nx * d, y: base[i].y + ny * d })
  }

  // Inner heart, scaled about the visual centre of the shape.
  var cy = -1.5
  var inner = []
  for (i = 0; i < n; i += 4) {
    var p = base[i]
    inner.push({ x: p.x * holeScale, y: cy + (p.y - cy) * holeScale })
  }

  // Normalise everything into a 0..1 box.
  var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity
  outer.forEach(function(p) {
    minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x)
    minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y)
  })
  var size = Math.max(maxX - minX, maxY - minY)
  var ox = minX - (size - (maxX - minX)) / 2, oy = minY - (size - (maxY - minY)) / 2
  function norm(p) { return { x: (p.x - ox) / size, y: (p.y - oy) / size } }
  return { outer: outer.map(norm), inner: inner.map(norm) }
}
