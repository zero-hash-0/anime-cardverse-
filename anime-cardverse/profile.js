const STORAGE = {
  profile: "acv:profile",
  inventory: "acv:inventory",
  progression: "acv:progression",
  event: "acv:event"
};

const BANNERS = [
  "linear-gradient(120deg,#5f2bff,#22d3ff)",
  "linear-gradient(120deg,#ff4fd8,#6c63ff)",
  "linear-gradient(120deg,#ff9f43,#ff5b5b)",
  "linear-gradient(120deg,#00d2ff,#3a47d5)",
  "linear-gradient(120deg,#32d296,#4d7cff)"
];

function load(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function save(key, value) {
  localStorage.setItem(key, JSON.stringify(value));
}

const profile = load(STORAGE.profile, {
  username: "NeonHunter",
  title: "Rookie Summoner",
  rank: "Diamond Rank",
  avatar: "",
  banner: BANNERS[0]
});

const inv = load(STORAGE.inventory, { collection: [], packs: 0, shards: 0, energyBoosters: 0 });
const prog = load(STORAGE.progression, { level: 1, xp: 0, packsOpened: 0, mythics: 0, messages: 0, energyUsed: 0 });
const event = load(STORAGE.event, { active: false });

const el = {
  particleCanvas: document.getElementById("particleCanvas"),
  profileHero: document.getElementById("profileHero"),
  profileAvatar: document.getElementById("profileAvatar"),
  nameInput: document.getElementById("nameInput"),
  titleText: document.getElementById("titleText"),
  levelText: document.getElementById("levelText"),
  xpFill: document.getElementById("xpFill"),
  xpText: document.getElementById("xpText"),
  avatarUpload: document.getElementById("avatarUpload"),
  bannerOptions: document.getElementById("bannerOptions"),
  favoriteCards: document.getElementById("favoriteCards"),
  lifetimeStats: document.getElementById("lifetimeStats")
};

function pageTransitions() {
  document.querySelectorAll("[data-nav]").forEach((a) => {
    a.addEventListener("click", (e) => {
      e.preventDefault();
      document.body.style.opacity = "0";
      setTimeout(() => {
        location.href = a.getAttribute("href");
      }, 180);
    });
  });
}

function initParticles() {
  const c = el.particleCanvas;
  const ctx = c.getContext("2d");
  const dots = Array.from({ length: 55 }, () => ({
    x: Math.random() * innerWidth,
    y: Math.random() * innerHeight,
    r: Math.random() * 1.6 + 0.5,
    vx: (Math.random() - 0.5) * 0.3,
    vy: (Math.random() - 0.5) * 0.3
  }));

  function resize() {
    c.width = innerWidth;
    c.height = innerHeight;
  }

  function draw() {
    ctx.clearRect(0, 0, c.width, c.height);
    ctx.fillStyle = "rgba(174,233,255,.72)";
    dots.forEach((d) => {
      d.x += d.vx;
      d.y += d.vy;
      if (d.x < 0 || d.x > c.width) d.vx *= -1;
      if (d.y < 0 || d.y > c.height) d.vy *= -1;
      ctx.beginPath();
      ctx.arc(d.x, d.y, d.r, 0, Math.PI * 2);
      ctx.fill();
    });
    requestAnimationFrame(draw);
  }

  resize();
  addEventListener("resize", resize);
  requestAnimationFrame(draw);
}

function fallbackAvatar() {
  return "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(`
<svg xmlns='http://www.w3.org/2000/svg' width='120' height='120'>
<defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'><stop stop-color='#ff4fd8'/><stop offset='1' stop-color='#41e6ff'/></linearGradient></defs>
<rect width='120' height='120' rx='22' fill='url(#g)'/>
<circle cx='60' cy='44' r='18' fill='rgba(255,255,255,.88)'/>
<rect x='26' y='70' width='68' height='28' rx='14' fill='rgba(255,255,255,.88)'/>
</svg>`);
}

function xpNeeded(level) {
  return 100 + (level - 1) * 45;
}

function deriveTitle() {
  if (prog.mythics >= 5) return "Mythic Hunter";
  if (inv.collection.length >= 20) return "Card Master";
  if (prog.level >= 10) return "Arena Challenger";
  return "Rookie Summoner";
}

function renderHeader() {
  profile.title = deriveTitle();
  save(STORAGE.profile, profile);

  el.profileHero.style.backgroundImage = `${profile.banner || BANNERS[0]}, linear-gradient(160deg, rgba(20,26,66,.7), rgba(20,26,66,.7))`;
  el.profileAvatar.src = profile.avatar || fallbackAvatar();
  el.nameInput.value = profile.username;
  el.titleText.textContent = profile.title;
  el.levelText.textContent = `${profile.rank} • LV ${prog.level}`;
  el.xpText.textContent = `${prog.xp} / ${xpNeeded(prog.level)} XP`;
  el.xpFill.style.width = `${Math.round((prog.xp / xpNeeded(prog.level)) * 100)}%`;
}

function createCardPreview(card) {
  const wrap = document.createElement("article");
  wrap.className = "gacha-card";
  wrap.innerHTML = `
    <p class="rarity-badge">${card.rarity}</p>
    <h4 class="card-name">${card.name}</h4>
    <p class="ability">${card.series}</p>
  `;
  wrap.classList.add(card.rarity.toLowerCase());
  return wrap;
}

function renderFavorites() {
  el.favoriteCards.innerHTML = "";
  inv.collection.slice(0, 3).forEach((card) => {
    el.favoriteCards.appendChild(createCardPreview(card));
  });
  if (!el.favoriteCards.childElementCount) {
    const p = document.createElement("p");
    p.textContent = "Open packs in Universe view to build favorites.";
    el.favoriteCards.appendChild(p);
  }
}

function renderStats() {
  const totalPower = inv.collection.reduce((sum, c) => sum + (c.basePower + c.energy * 6), 0);
  const stats = [
    ["Cards Collected", inv.collection.length],
    ["Total Power", totalPower],
    ["Packs Opened", prog.packsOpened],
    ["Mythics Pulled", prog.mythics],
    ["Messages Sent", prog.messages],
    ["Energy Used", prog.energyUsed],
    ["Shards", inv.shards],
    ["Event Status", event.active ? "Live" : "Idle"]
  ];

  el.lifetimeStats.innerHTML = "";
  stats.forEach(([k, v]) => {
    const box = document.createElement("div");
    box.className = "stat-box";
    box.innerHTML = `<p>${k}</p><h4>${v}</h4>`;
    el.lifetimeStats.appendChild(box);
  });
}

function initBannerPicker() {
  el.bannerOptions.innerHTML = "";
  BANNERS.forEach((bg) => {
    const swatch = document.createElement("button");
    swatch.className = "banner-swatch";
    swatch.style.background = bg;
    swatch.type = "button";
    swatch.addEventListener("click", () => {
      profile.banner = bg;
      save(STORAGE.profile, profile);
      renderHeader();
    });
    el.bannerOptions.appendChild(swatch);
  });
}

function hookEvents() {
  el.nameInput.addEventListener("change", () => {
    profile.username = (el.nameInput.value || "NeonHunter").trim();
    save(STORAGE.profile, profile);
  });

  el.avatarUpload.addEventListener("change", () => {
    const file = el.avatarUpload.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      profile.avatar = String(reader.result);
      save(STORAGE.profile, profile);
      renderHeader();
    };
    reader.readAsDataURL(file);
  });
}

function init() {
  pageTransitions();
  initParticles();
  initBannerPicker();
  hookEvents();
  renderHeader();
  renderFavorites();
  renderStats();
}

init();
