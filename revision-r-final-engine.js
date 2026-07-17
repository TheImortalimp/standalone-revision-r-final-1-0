(function () {
  const canvas = document.getElementById("fxCanvas");
  const ctx = canvas.getContext("2d", { alpha: true, desynchronized: true });
  const mediaLayer = document.getElementById("mediaLayer");
  const ytFrame = document.getElementById("ytFrame");

  const ytInput = document.getElementById("ytInput");
  const ytStartBtn = document.getElementById("ytStartBtn");
  const fileInput = document.getElementById("fileInput");
  const localStartBtn = document.getElementById("localStartBtn");
  const status = document.getElementById("status");

  const REVISION_WEIGHTS = Object.freeze({
    r2: 0.78,
    r1: 0.08,
    r3: 0.08,
    r4: 0.06
  });

  const TAU_SECONDS = 0.16;
  const MAX_DISPLACEMENT = 7.5;

  const state = {
    frame: 0,
    smoothJitter: 0,
    smoothWarp: 0,
    smoothHue: 0,
    smoothBloom: 0,
    smoothScan: 0,
    lastTime: performance.now(),
    mediaMode: "none"
  };

  function resize() {
    const width = Math.max(1, Math.floor(window.innerWidth));
    const height = Math.max(1, Math.floor(window.innerHeight));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
  }

  function pulse(seed, speed, t) {
    return 0.5 + 0.5 * Math.sin(seed + speed * t);
  }

  function computeBlendTargets(tSec) {
    const r2 = {
      jitter: 0.25 * pulse(0.3, 0.9, tSec),
      warp: 0.18 + 0.12 * pulse(1.6, 0.7, tSec),
      hue: 0.08 + 0.06 * pulse(2.2, 0.5, tSec),
      bloom: 0.12 + 0.08 * pulse(0.9, 0.65, tSec),
      scan: 0.13 + 0.09 * pulse(1.1, 0.55, tSec)
    };

    const r1 = {
      jitter: 0.38 * pulse(2.9, 1.4, tSec),
      warp: 0.33 * pulse(2.1, 1.2, tSec),
      hue: 0.27 * pulse(0.5, 0.8, tSec),
      bloom: 0.21 * pulse(2.7, 1.0, tSec),
      scan: 0.31 * pulse(1.9, 1.1, tSec)
    };

    const r3 = {
      jitter: 0.42 * pulse(4.2, 1.8, tSec),
      warp: 0.26 * pulse(3.3, 1.5, tSec),
      hue: 0.34 * pulse(2.4, 1.1, tSec),
      bloom: 0.19 * pulse(1.5, 1.3, tSec),
      scan: 0.28 * pulse(2.8, 1.0, tSec)
    };

    const r4 = {
      jitter: 0.48 * pulse(5.4, 2.0, tSec),
      warp: 0.31 * pulse(3.9, 1.6, tSec),
      hue: 0.39 * pulse(4.0, 1.2, tSec),
      bloom: 0.17 * pulse(3.1, 1.0, tSec),
      scan: 0.24 * pulse(2.6, 1.25, tSec)
    };

    const w = REVISION_WEIGHTS;

    return {
      jitter: w.r2 * r2.jitter + w.r1 * r1.jitter + w.r3 * r3.jitter + w.r4 * r4.jitter,
      warp: w.r2 * r2.warp + w.r1 * r1.warp + w.r3 * r3.warp + w.r4 * r4.warp,
      hue: w.r2 * r2.hue + w.r1 * r1.hue + w.r3 * r3.hue + w.r4 * r4.hue,
      bloom: w.r2 * r2.bloom + w.r1 * r1.bloom + w.r3 * r3.bloom + w.r4 * r4.bloom,
      scan: w.r2 * r2.scan + w.r1 * r1.scan + w.r3 * r3.scan + w.r4 * r4.scan
    };
  }

  function smoothTo(current, target, dt) {
    const alpha = 1 - Math.exp(-dt / TAU_SECONDS);
    return current + (target - current) * alpha;
  }

  function updateBlendState(nowMs) {
    const dt = Math.max(0.001, Math.min(0.05, (nowMs - state.lastTime) / 1000));
    state.lastTime = nowMs;

    const tSec = nowMs / 1000;
    const target = computeBlendTargets(tSec);

    state.smoothJitter = smoothTo(state.smoothJitter, target.jitter, dt);
    state.smoothWarp = smoothTo(state.smoothWarp, target.warp, dt);
    state.smoothHue = smoothTo(state.smoothHue, target.hue, dt);
    state.smoothBloom = smoothTo(state.smoothBloom, target.bloom, dt);
    state.smoothScan = smoothTo(state.smoothScan, target.scan, dt);
  }

  function drawSourceFrame() {
    if (state.mediaMode !== "local" || mediaLayer.readyState < 2) {
      return;
    }

    const width = canvas.width;
    const height = canvas.height;

    const dx = Math.sin(state.frame * 0.031) * state.smoothWarp * MAX_DISPLACEMENT;
    const dy = Math.cos(state.frame * 0.027) * state.smoothWarp * MAX_DISPLACEMENT;

    ctx.save();
    ctx.globalAlpha = 0.94;
    ctx.filter = "saturate(1.05) contrast(1.04)";
    ctx.drawImage(mediaLayer, dx, dy, width, height, 0, 0, width, height);
    ctx.restore();

    const ch = Math.max(0.2, state.smoothJitter * 3.0);

    ctx.save();
    ctx.globalCompositeOperation = "screen";
    ctx.globalAlpha = 0.07 + state.smoothHue * 0.1;
    ctx.fillStyle = "rgba(255, 80, 80, 0.45)";
    ctx.fillRect(ch, 0, width, height);
    ctx.fillStyle = "rgba(80, 160, 255, 0.3)";
    ctx.fillRect(-ch, 0, width, height);
    ctx.restore();
  }

  function drawScanlines() {
    const width = canvas.width;
    const height = canvas.height;
    const step = 2;
    const alpha = 0.022 + state.smoothScan * 0.03;

    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.fillStyle = "#7fdbff";
    for (let y = state.frame % step; y < height; y += step) {
      ctx.fillRect(0, y, width, 1);
    }
    ctx.restore();
  }

  function drawBloomAndVignette() {
    const width = canvas.width;
    const height = canvas.height;
    const centerX = width * (0.5 + 0.05 * Math.sin(state.frame * 0.0027));
    const centerY = height * (0.5 + 0.05 * Math.cos(state.frame * 0.0021));

    const grad = ctx.createRadialGradient(centerX, centerY, 0, centerX, centerY, Math.max(width, height) * 0.66);
    const energy = 0.08 + state.smoothBloom * 0.13;

    grad.addColorStop(0, "rgba(114, 255, 240, " + energy.toFixed(3) + ")");
    grad.addColorStop(0.65, "rgba(243, 170, 83, " + (energy * 0.55).toFixed(3) + ")");
    grad.addColorStop(1, "rgba(3, 8, 18, 0.44)");

    ctx.save();
    ctx.globalCompositeOperation = "soft-light";
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, width, height);
    ctx.restore();
  }

  function render(nowMs) {
    resize();
    updateBlendState(nowMs);

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    drawSourceFrame();
    drawScanlines();
    drawBloomAndVignette();

    state.frame += 1;
    requestAnimationFrame(render);
  }

  function parseYouTubeId(input) {
    if (!input) return null;
    const trimmed = input.trim();

    const idMatch = trimmed.match(/[?&]v=([a-zA-Z0-9_-]{11})/) ||
      trimmed.match(/youtu\.be\/([a-zA-Z0-9_-]{11})/) ||
      trimmed.match(/embed\/([a-zA-Z0-9_-]{11})/);

    return idMatch ? idMatch[1] : null;
  }

  function startYouTube() {
    const id = parseYouTubeId(ytInput.value);
    if (!id) {
      status.textContent = "Invalid YouTube URL.";
      return;
    }

    const embedUrl = "https://www.youtube.com/embed/" + id + "?autoplay=1&controls=1&rel=0";
    ytFrame.src = embedUrl;
    ytFrame.classList.add("active");

    mediaLayer.pause();
    mediaLayer.removeAttribute("src");
    mediaLayer.load();

    state.mediaMode = "youtube";
    status.textContent = "YouTube mode active. r2 baseline blend running.";
  }

  function startLocal() {
    const file = fileInput.files && fileInput.files[0];
    if (!file) {
      status.textContent = "Select a local MP4/MP3 file first.";
      return;
    }

    const objectUrl = URL.createObjectURL(file);
    mediaLayer.src = objectUrl;
    mediaLayer.muted = false;
    mediaLayer.loop = true;

    mediaLayer.play().catch(function () {
      status.textContent = "Playback blocked until user interaction. Press play again.";
    });

    ytFrame.classList.remove("active");
    ytFrame.removeAttribute("src");

    state.mediaMode = "local";
    status.textContent = "Local media mode active. r2 baseline blend running.";
  }

  ytStartBtn.addEventListener("click", startYouTube);
  localStartBtn.addEventListener("click", startLocal);

  window.addEventListener("resize", resize);
  resize();
  requestAnimationFrame(render);
})();
