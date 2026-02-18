const STORAGE = {
  profile: "acv:profile",
  inventory: "acv:inventory",
  progression: "acv:progression",
  chat: "acv:chat",
  history: "acv:history",
  pulls: "acv:pulls",
  event: "acv:event"
};

const BASE_CARDS = [
  { name: "Shadow Hokage", series: "Naruto", rarity: "Epic", power: 86, ability: "Phantom Clone Barrage" },
  { name: "Titan Breaker", series: "Attack on Titan", rarity: "Rare", power: 72, ability: "Skyhook Rend" },
  { name: "Soul Reaper Prime", series: "Bleach", rarity: "Legendary", power: 94, ability: "Bankai Eclipse" },
  { name: "Pirate Emperor", series: "One Piece", rarity: "Mythic", power: 102, ability: "Conqueror Tidal Wave" },
  { name: "Cursed Vessel", series: "Jujutsu Kaisen", rarity: "Epic", power: 84, ability: "Domain Lock" },
  { name: "Hero Number One", series: "My Hero Academia", rarity: "Rare", power: 70, ability: "Detroit Nova" },
  { name: "Alchemy Storm", series: "Fullmetal Alchemist", rarity: "Legendary", power: 95, ability: "Transmute Barricade" },
  { name: "Demon Slayer Flame", series: "Demon Slayer", rarity: "Epic", power: 82, ability: "Ninth Form Inferno" },
  { name: "Death Note Strategist", series: "Death Note", rarity: "Epic", power: 80, ability: "Predestination Gambit" },
  { name: "Chainsaw Vanguard", series: "Chainsaw Man", rarity: "Epic", power: 85, ability: "Overdrive Rip" },
  { name: "Phantom Troupe Ace", series: "Hunter x Hunter", rarity: "Legendary", power: 92, ability: "Thread Mirage" }
];

const ART = {
  Naruto: ["#ff933d", "#f84f7f", "#6f2dff"],
  "Attack on Titan": ["#83614f", "#403151", "#db6a2f"],
  Bleach: ["#7d5fff", "#2f2ba8", "#5fe9ff"],
  "One Piece": ["#00b4ff", "#005ce6", "#ffd65b"],
  "Jujutsu Kaisen": ["#8a5dff", "#3eb489", "#9ba5c1"],
  "My Hero Academia": ["#f6d34f", "#ef6b4f", "#2f5c88"],
  "Fullmetal Alchemist": ["#cc935d", "#9a6f58", "#3a3f5f"],
  "Demon Slayer": ["#1ea995", "#2a4563", "#f17457"],
  "Death Note": ["#6e6a83", "#201e34", "#e1e5ee"],
  "Chainsaw Man": ["#ff4b4b", "#3f739f", "#ff8d34"],
  "Hunter x Hunter": ["#4cc89d", "#4f78aa", "#ffd45d"]
};

const BADGES = [
  { id: "mythic_hunter", name: "Mythic Hunter", check: (s) => s.mythics >= 3 },
  { id: "card_master", name: "Card Master", check: (s) => s.collectionCount >= 18 },
  { id: "esports_grind", name: "Esports Grind", check: (s) => s.totalPower >= 1700 },
  { id: "energy_architect", name: "Energy Architect", check: (s) => s.energyUsed >= 15 }
];

const MISSIONS = [
  { id: "open3", title: "Open 3 Packs", goal: 3, metric: "packsOpened", reward: { shards: 110 } },
  { id: "mythic1", title: "Pull 1 Mythic", goal: 1, metric: "mythics", reward: { energyBoosters: 2 } },
  { id: "chat6", title: "Send 6 Messages", goal: 6, metric: "messages", reward: { xp: 120 } }
];

const RARITY_FLOW = ["Rare", "Epic", "Legendary", "Mythic"];
const DRAW_WEIGHTS = { Rare: 57, Epic: 28, Legendary: 11, Mythic: 4 };

const profileDefault = {
  username: "NeonHunter",
  title: "Rookie Summoner",
  avatar: "",
  rank: "Diamond Rank"
};

const invDefault = {
  packs: 5,
  shards: 300,
  energyBoosters: 3,
  collection: []
};

const progDefault = {
  xp: 0,
  level: 1,
  packsOpened: 0,
  mythics: 0,
  messages: 0,
  energyUsed: 0,
  claimedMissions: {}
};

const historyDefault = [];

const pullsDefault = [];

const eventDefault = (() => {
  const now = Date.now();
  return {
    startsAt: now + 1000 * 60 * 3,
    endsAt: now + 1000 * 60 * 9,
    active: false,
    announced: false
  };
})();

const el = {
  particleCanvas: document.getElementById("particleCanvas"),
  profileAvatar: document.getElementById("profileAvatar"),
  profileName: document.getElementById("profileName"),
  profileRank: document.getElementById("profileRank"),
  profileTitle: document.getElementById("profileTitle"),
  xpFill: document.getElementById("xpFill"),
  xpText: document.getElementById("xpText"),
  playerLevel: document.getElementById("playerLevel"),
  missionList: document.getElementById("missionList"),
  badgeList: document.getElementById("badgeList"),
  eventTitle: document.getElementById("eventTitle"),
  eventDesc: document.getElementById("eventDesc"),
  eventCountdownMain: document.getElementById("eventCountdownMain"),
  eventCountdownSide: document.getElementById("eventCountdownSide"),
  eventPhase: document.getElementById("eventPhase"),
  featuredBanner: document.getElementById("featuredBanner"),
  packStockText: document.getElementById("packStockText"),
  openPackBtn: document.getElementById("openPackBtn"),
  openPackBtnTop: document.getElementById("openPackBtnTop"),
  buyPackBtn: document.getElementById("buyPackBtn"),
  packStage: document.getElementById("packStage"),
  packModel: document.getElementById("packModel"),
  mythicBurst: document.getElementById("mythicBurst"),
  recentPullsTicker: document.getElementById("recentPullsTicker"),
  revealRow: document.getElementById("revealRow"),
  collectionGrid: document.getElementById("collectionGrid"),
  collectionStats: document.getElementById("collectionStats"),
  chatFeed: document.getElementById("chatFeed"),
  chatForm: document.getElementById("chatForm"),
  chatName: document.getElementById("chatName"),
  chatInput: document.getElementById("chatInput"),
  leaderboard: document.getElementById("leaderboard"),
  historyLog: document.getElementById("historyLog"),
  cardTemplate: document.getElementById("cardTemplate"),
  inspectModal: document.getElementById("inspectModal"),
  inspectCardHost: document.getElementById("inspectCardHost"),
  dailyReward: document.getElementById("dailyReward"),
  collectRewardBtn: document.getElementById("collectRewardBtn"),
  rewardText: document.getElementById("rewardText"),
  toast: document.getElementById("toast"),
  flashLayer: document.getElementById("flashLayer"),
  xpFloat: document.getElementById("xpFloat"),
  musicToggle: document.getElementById("musicToggle")
};

const state = {
  profile: load(STORAGE.profile, profileDefault),
  inventory: load(STORAGE.inventory, invDefault),
  progression: load(STORAGE.progression, progDefault),
  chat: load(STORAGE.chat, [
    { user: "Aoi", msg: "Saving for event-limited Mythic..." },
    { user: "Rin", msg: "Legendary flame border is insane." }
  ]),
  history: load(STORAGE.history, historyDefault),
  pulls: load(STORAGE.pulls, pullsDefault),
  event: load(STORAGE.event, eventDefault),
  busyOpening: false,
  musicOn: false,
  toastTimer: null
};

const liveChannel = typeof BroadcastChannel !== "undefined" ? new BroadcastChannel("acv:chat") : null;

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

function uid() {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function clamp(n, min, max) {
  return Math.max(min, Math.min(max, n));
}

function playSfx(name) {
  // Placeholder for future audio assets.
  console.debug(`SFX: ${name}`);
}

function showToast(message) {
  el.toast.textContent = message;
  el.toast.classList.add("show");
  if (state.toastTimer) clearTimeout(state.toastTimer);
  state.toastTimer = setTimeout(() => el.toast.classList.remove("show"), 1400);
}

function showXpGain(amount) {
  el.xpFloat.textContent = `+${amount} XP`;
  el.xpFloat.classList.add("show");
  setTimeout(() => el.xpFloat.classList.remove("show"), 850);
}

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
  const particles = Array.from({ length: 70 }, () => ({
    x: Math.random() * innerWidth,
    y: Math.random() * innerHeight,
    r: Math.random() * 1.7 + 0.6,
    vx: (Math.random() - 0.5) * 0.4,
    vy: (Math.random() - 0.5) * 0.4
  }));

  function resize() {
    c.width = innerWidth;
    c.height = innerHeight;
  }

  function draw() {
    ctx.clearRect(0, 0, c.width, c.height);
    ctx.fillStyle = "rgba(180,225,255,.75)";
    particles.forEach((p) => {
      p.x += p.vx;
      p.y += p.vy;
      if (p.x < 0 || p.x > c.width) p.vx *= -1;
      if (p.y < 0 || p.y > c.height) p.vy *= -1;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fill();
    });
    requestAnimationFrame(draw);
  }

  resize();
  addEventListener("resize", resize);
  requestAnimationFrame(draw);
}

function profileAvatarSrc() {
  return state.profile.avatar || "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(`
<svg xmlns='http://www.w3.org/2000/svg' width='120' height='120'>
<defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'><stop stop-color='#41e6ff'/><stop offset='1' stop-color='#8f62ff'/></linearGradient></defs>
<rect width='120' height='120' rx='26' fill='url(#g)'/>
<circle cx='60' cy='46' r='20' fill='rgba(255,255,255,.85)'/>
<rect x='24' y='74' width='72' height='30' rx='15' fill='rgba(255,255,255,.85)'/>
</svg>`);
}

function rarityClass(r) {
  return r.toLowerCase();
}

function abilityForRarity(r) {
  if (r === "Mythic") return "Reality Breaker";
  if (r === "Legendary") return "Ultimate Resonance";
  if (r === "Epic") return "Hyper Surge";
  return "Focused Strike";
}

function evolveTarget(rarity) {
  const idx = RARITY_FLOW.indexOf(rarity);
  return idx >= 0 && idx < RARITY_FLOW.length - 1 ? RARITY_FLOW[idx + 1] : rarity;
}

function evolutionThreshold(rarity) {
  if (rarity === "Rare") return 90;
  if (rarity === "Epic") return 102;
  if (rarity === "Legendary") return 114;
  return Infinity;
}

function cardPower(card) {
  return card.basePower + card.energy * 6;
}

function makeArt(card) {
  const [a, b, c] = ART[card.series] || ["#7f6dff", "#3a4ab3", "#5ae7ff"];
  const sig = card.series.split(" ").map((w) => w[0]).join("").slice(0, 4).toUpperCase();
  const svg = `
<svg xmlns='http://www.w3.org/2000/svg' width='380' height='230'>
<defs>
<linearGradient id='g' x1='0' y1='0' x2='1' y2='1'>
<stop offset='0%' stop-color='${a}'/>
<stop offset='50%' stop-color='${b}'/>
<stop offset='100%' stop-color='${c}'/>
</linearGradient>
</defs>
<rect width='380' height='230' fill='url(#g)'/>
<circle cx='290' cy='62' r='46' fill='rgba(255,255,255,.2)'/>
<path d='M0,175 C95,130 180,225 380,145 L380,230 L0,230 Z' fill='rgba(0,0,0,.28)'/>
<path d='M22 36 L150 36 L104 112 L16 112 Z' fill='rgba(255,255,255,.18)'/>
<text x='24' y='203' fill='rgba(255,255,255,.95)' font-size='34' font-family='Arial Black'>${sig}</text>
<text x='24' y='220' fill='rgba(255,255,255,.86)' font-size='13' font-family='Arial'>${card.series}</text>
</svg>`;
  return `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(svg)}`;
}

function weightedRarity() {
  const entries = Object.entries(DRAW_WEIGHTS);
  const total = entries.reduce((acc, [, v]) => acc + v, 0);
  let roll = Math.random() * total;
  for (const [rarity, weight] of entries) {
    if (roll < weight) return rarity;
    roll -= weight;
  }
  return "Rare";
}

function drawBaseCard() {
  const rarity = weightedRarity();
  const candidates = BASE_CARDS.filter((c) => c.rarity === rarity);
  const chosen = candidates[Math.floor(Math.random() * candidates.length)] || BASE_CARDS[0];
  return {
    id: uid(),
    name: chosen.name,
    series: chosen.series,
    rarity: chosen.rarity,
    basePower: chosen.power,
    ability: chosen.ability || abilityForRarity(chosen.rarity),
    energy: 0,
    slots: 4,
    limited: state.event.active
  };
}

function formatMs(ms) {
  const s = Math.max(0, Math.floor(ms / 1000));
  const h = String(Math.floor(s / 3600)).padStart(2, "0");
  const m = String(Math.floor((s % 3600) / 60)).padStart(2, "0");
  const sec = String(s % 60).padStart(2, "0");
  return `${h}:${m}:${sec}`;
}

function setProfileTitle() {
  if (state.progression.mythics >= 5) state.profile.title = "Mythic Hunter";
  else if (state.inventory.collection.length >= 20) state.profile.title = "Card Master";
  else if (state.progression.level >= 10) state.profile.title = "Arena Challenger";
  else state.profile.title = "Rookie Summoner";
  save(STORAGE.profile, state.profile);
}

function xpToNext(level) {
  return 100 + (level - 1) * 45;
}

function gainXp(amount) {
  state.progression.xp += amount;
  let leveled = false;
  while (state.progression.xp >= xpToNext(state.progression.level)) {
    state.progression.xp -= xpToNext(state.progression.level);
    state.progression.level += 1;
    leveled = true;
  }
  if (leveled) showToast(`Level Up! Lv ${state.progression.level}`);
  save(STORAGE.progression, state.progression);
  renderProfileCard();
  showXpGain(amount);
}

function missionProgress(mission) {
  return clamp(state.progression[mission.metric] || 0, 0, mission.goal);
}

function missionClaim(mission) {
  if (state.progression.claimedMissions[mission.id]) return;
  if (missionProgress(mission) < mission.goal) return;

  state.progression.claimedMissions[mission.id] = true;
  if (mission.reward.shards) state.inventory.shards += mission.reward.shards;
  if (mission.reward.energyBoosters) state.inventory.energyBoosters += mission.reward.energyBoosters;
  if (mission.reward.xp) gainXp(mission.reward.xp);

  save(STORAGE.progression, state.progression);
  save(STORAGE.inventory, state.inventory);
  renderEconomy();
  renderMissions();
  showToast("Mission reward claimed");
}

function renderMissions() {
  el.missionList.innerHTML = "";
  MISSIONS.forEach((mission) => {
    const p = missionProgress(mission);
    const claimed = Boolean(state.progression.claimedMissions[mission.id]);
    const wrap = document.createElement("div");
    wrap.className = "mission";
    wrap.innerHTML = `<div>${mission.title}</div><div>${p}/${mission.goal}</div>`;

    const progress = document.createElement("div");
    progress.className = "progress";
    const bar = document.createElement("i");
    bar.style.width = `${Math.round((p / mission.goal) * 100)}%`;
    progress.appendChild(bar);

    const btn = document.createElement("button");
    btn.className = "pill-btn";
    btn.textContent = claimed ? "Claimed" : "Claim";
    btn.disabled = claimed || p < mission.goal;
    btn.onclick = () => missionClaim(mission);

    wrap.append(progress, btn);
    el.missionList.appendChild(wrap);
  });
}

function calculateSummary() {
  const collection = state.inventory.collection;
  const totalPower = collection.reduce((acc, c) => acc + cardPower(c), 0);
  return {
    collectionCount: collection.length,
    totalPower,
    mythics: collection.filter((c) => c.rarity === "Mythic").length,
    energyUsed: state.progression.energyUsed
  };
}

function renderBadges() {
  const summary = calculateSummary();
  el.badgeList.innerHTML = "";
  BADGES.filter((b) => b.check(summary)).forEach((badge) => {
    const row = document.createElement("div");
    row.className = "badge-item";
    row.textContent = badge.name;
    el.badgeList.appendChild(row);
  });
  if (!el.badgeList.childElementCount) {
    const row = document.createElement("div");
    row.className = "badge-item";
    row.textContent = "No unlocked badges yet";
    el.badgeList.appendChild(row);
  }
}

function renderProfileCard() {
  setProfileTitle();
  el.profileAvatar.src = profileAvatarSrc();
  el.profileName.textContent = state.profile.username;
  el.profileRank.textContent = state.profile.rank;
  el.profileTitle.textContent = state.profile.title;
  el.playerLevel.textContent = state.progression.level;
  const maxXp = xpToNext(state.progression.level);
  el.xpText.textContent = `${state.progression.xp} / ${maxXp} XP`;
  el.xpFill.style.width = `${Math.round((state.progression.xp / maxXp) * 100)}%`;
}

function renderEconomy() {
  el.packStockText.textContent = `Packs: ${state.inventory.packs} | Energy Boosters: ${state.inventory.energyBoosters}`;
  const summary = calculateSummary();
  el.collectionStats.textContent = `${summary.collectionCount} cards | Power ${summary.totalPower} | Shards ${state.inventory.shards}`;
}

function buildEnergySlots(card) {
  const slots = document.createElement("div");
  slots.className = "energy-slots";
  for (let i = 0; i < card.slots; i += 1) {
    const dot = document.createElement("span");
    dot.className = `energy-dot ${i < card.energy ? "active" : ""}`;
    slots.appendChild(dot);
  }
  return slots;
}

function updatePowerMeter(cardEl, card) {
  const meter = cardEl.querySelector(".power-meter");
  const power = cardPower(card);
  const pct = clamp(power / 140, 0, 1);
  meter.style.background = `conic-gradient(var(--cyan) ${pct}turn, rgba(255,255,255,.14) ${pct}turn)`;
  meter.querySelector("span").textContent = String(power);
}

function cardRarityDecor(cardEl, card) {
  cardEl.classList.remove("rare", "epic", "legendary", "mythic");
  cardEl.classList.add(rarityClass(card.rarity));
}

function renderCard(card, { reveal = false } = {}) {
  const node = el.cardTemplate.content.firstElementChild.cloneNode(true);
  node.dataset.cardId = card.id;
  node.querySelector(".rarity-badge").textContent = card.rarity;
  node.querySelector(".logo-badge").textContent = card.series.split(" ").map((s) => s[0]).join("").slice(0, 4).toUpperCase();
  node.querySelector(".card-name").textContent = card.name;
  node.querySelector(".ability").textContent = card.ability;
  const img = node.querySelector(".card-art");
  img.src = makeArt(card);
  img.alt = `${card.series} art`;

  if (card.limited) node.classList.add("limited");
  if (reveal) node.classList.add("reveal-in");
  cardRarityDecor(node, card);

  const energyHost = node.querySelector(".energy-slots");
  energyHost.replaceWith(buildEnergySlots(card));
  updatePowerMeter(node, card);

  node.querySelector(".energy-btn").addEventListener("click", (ev) => {
    ev.stopPropagation();
    attachEnergy(card.id, node);
  });

  node.addEventListener("click", () => openInspect(card.id));
  node.addEventListener("keydown", (e) => {
    if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      openInspect(card.id);
    }
  });

  return node;
}

function renderCollection() {
  el.collectionGrid.innerHTML = "";
  state.inventory.collection.forEach((card) => {
    el.collectionGrid.appendChild(renderCard(card));
  });
}

function addRecentPulls(cards) {
  const line = cards.map((c) => `${c.name} [${c.rarity}]`).join("  |  ");
  state.pulls.unshift(line);
  state.pulls = state.pulls.slice(0, 8);
  save(STORAGE.pulls, state.pulls);
  el.recentPullsTicker.textContent = state.pulls.join("  ||  ");
}

function renderHistory() {
  el.historyLog.innerHTML = "";
  state.history.slice(0, 12).forEach((h) => {
    const row = document.createElement("div");
    row.className = "history-item";
    row.textContent = `${h.time} • ${h.label}`;
    el.historyLog.appendChild(row);
  });
}

function logHistory(label) {
  const now = new Date();
  state.history.unshift({
    label,
    time: now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
  });
  state.history = state.history.slice(0, 40);
  save(STORAGE.history, state.history);
  renderHistory();
}

function renderLeaderboard() {
  const summary = calculateSummary();
  const bots = [
    { name: "AstraZero", power: 1880 },
    { name: "HikariRush", power: 1740 },
    { name: "VoidBlade", power: 1670 },
    { name: "LumaCore", power: 1590 }
  ];
  const all = [{ name: state.profile.username, power: summary.totalPower }, ...bots].sort((a, b) => b.power - a.power);
  el.leaderboard.innerHTML = "";
  all.slice(0, 5).forEach((row, i) => {
    const elRow = document.createElement("div");
    elRow.className = "lb-row";
    elRow.innerHTML = `<b>#${i + 1} ${row.name}</b><span>${row.power} PWR</span>`;
    el.leaderboard.appendChild(elRow);
  });
}

function renderChat() {
  el.chatFeed.innerHTML = "";
  state.chat.slice(-50).forEach((entry) => {
    const p = document.createElement("p");
    p.className = "chat-msg";
    const b = document.createElement("b");
    b.textContent = `${entry.user}:`;
    p.appendChild(b);
    p.appendChild(document.createTextNode(` ${entry.msg}`));
    el.chatFeed.appendChild(p);
  });
  el.chatFeed.scrollTop = el.chatFeed.scrollHeight;
}

function postChat(user, msg, sync = true) {
  state.chat.push({ user, msg });
  state.chat = state.chat.slice(-200);
  save(STORAGE.chat, state.chat);
  renderChat();
  state.progression.messages += 1;
  save(STORAGE.progression, state.progression);
  renderMissions();
  if (sync && liveChannel) liveChannel.postMessage({ user, msg });
}

function addMythicParticles() {
  for (let i = 0; i < 22; i += 1) {
    const dot = document.createElement("span");
    dot.className = "mythic-particle";
    dot.style.left = "50%";
    dot.style.top = "50%";
    dot.style.setProperty("--dx", `${(Math.random() - 0.5) * 240}px`);
    dot.style.setProperty("--dy", `${(Math.random() - 0.5) * 180}px`);
    el.mythicBurst.appendChild(dot);
    setTimeout(() => dot.remove(), 760);
  }
}

function drawPackCards() {
  return Array.from({ length: 3 }, () => drawBaseCard());
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function openPackSequence() {
  if (state.busyOpening) return;
  if (state.inventory.packs <= 0) {
    showToast("No packs available");
    return;
  }

  state.busyOpening = true;
  state.inventory.packs -= 1;
  state.progression.packsOpened += 1;
  save(STORAGE.inventory, state.inventory);
  save(STORAGE.progression, state.progression);
  renderEconomy();
  renderMissions();

  playSfx("pack_charge");
  el.packModel.classList.add("suspense");
  await delay(700);

  el.packModel.classList.remove("suspense");
  el.packModel.classList.add("opening");
  document.body.classList.add("shake");
  playSfx("pack_flash");
  el.flashLayer.classList.add("on");

  await delay(340);
  el.flashLayer.classList.remove("on");
  document.body.classList.remove("shake");

  const cards = drawPackCards();
  el.revealRow.innerHTML = "";

  let pulledMythic = false;
  for (let i = 0; i < cards.length; i += 1) {
    const card = cards[i];
    if (card.rarity === "Mythic") pulledMythic = true;

    const cardNode = renderCard(card, { reveal: true });
    cardNode.style.animationDelay = `${i * 170}ms`;
    el.revealRow.appendChild(cardNode);
    playSfx("card_flip");
    await delay(210);
  }

  if (pulledMythic) {
    state.progression.mythics += cards.filter((c) => c.rarity === "Mythic").length;
    playSfx("mythic_explosion");
    addMythicParticles();
  }

  state.inventory.collection.unshift(...cards);
  state.inventory.collection = state.inventory.collection.slice(0, 120);
  save(STORAGE.inventory, state.inventory);
  save(STORAGE.progression, state.progression);

  gainXp(40 + cards.filter((c) => c.rarity !== "Rare").length * 25);
  addRecentPulls(cards);
  logHistory(`Opened pack: ${cards.map((c) => c.rarity).join(", ")}`);

  renderCollection();
  renderEconomy();
  renderBadges();
  renderLeaderboard();
  renderMissions();

  await delay(280);
  el.packModel.classList.remove("opening");
  state.busyOpening = false;

  if (pulledMythic) showToast("Mythic pull! Rainbow pulse triggered");
}

function buyPack() {
  if (state.inventory.shards < 120) {
    showToast("Not enough shards");
    return;
  }
  state.inventory.shards -= 120;
  state.inventory.packs += 1;
  save(STORAGE.inventory, state.inventory);
  renderEconomy();
  showToast("+1 Pack acquired");
}

function maybeEvolve(card, cardNode) {
  if (card.rarity === "Mythic") return;
  if (cardPower(card) < evolutionThreshold(card.rarity)) return;

  const next = evolveTarget(card.rarity);
  if (next === card.rarity) return;

  cardNode.classList.add("evolving");
  playSfx("evolve_ignite");
  setTimeout(() => {
    card.rarity = next;
    card.ability = abilityForRarity(card.rarity);
    cardNode.querySelector(".rarity-badge").textContent = card.rarity;
    cardNode.querySelector(".ability").textContent = card.ability;
    cardRarityDecor(cardNode, card);
    updatePowerMeter(cardNode, card);
    save(STORAGE.inventory, state.inventory);
    if (next === "Mythic") state.progression.mythics += 1;
    save(STORAGE.progression, state.progression);
    renderBadges();
    renderLeaderboard();
    showToast(`${card.name} evolved to ${next}`);
  }, 540);
}

function attachEnergy(cardId, cardNode) {
  const card = state.inventory.collection.find((c) => c.id === cardId);
  if (!card) return;

  if (state.inventory.energyBoosters <= 0) {
    showToast("No energy boosters left");
    return;
  }
  if (card.energy >= card.slots) {
    showToast("Energy slots full");
    return;
  }

  state.inventory.energyBoosters -= 1;
  state.progression.energyUsed += 1;
  card.energy += 1;

  save(STORAGE.inventory, state.inventory);
  save(STORAGE.progression, state.progression);

  const newSlots = buildEnergySlots(card);
  cardNode.querySelector(".energy-slots").replaceWith(newSlots);
  updatePowerMeter(cardNode, card);
  maybeEvolve(card, cardNode);

  renderEconomy();
  renderMissions();
  renderBadges();
  renderLeaderboard();
  playSfx("energy_attach");
}

function openInspect(cardId) {
  const card = state.inventory.collection.find((c) => c.id === cardId);
  if (!card) return;
  el.inspectCardHost.innerHTML = "";
  const node = renderCard(card);
  node.querySelector(".energy-btn").remove();
  node.style.width = "260px";
  node.style.margin = "0 auto";
  el.inspectCardHost.appendChild(node);
  el.inspectModal.classList.add("open");
  el.inspectModal.setAttribute("aria-hidden", "false");

  node.addEventListener("mousemove", (e) => {
    const rect = node.getBoundingClientRect();
    const x = (e.clientX - rect.left) / rect.width - 0.5;
    const y = (e.clientY - rect.top) / rect.height - 0.5;
    node.style.transform = `rotateX(${(-y * 16).toFixed(2)}deg) rotateY(${(x * 16).toFixed(2)}deg)`;
  });
  node.addEventListener("mouseleave", () => {
    node.style.transform = "rotateX(0deg) rotateY(0deg)";
  });
}

function closeInspect() {
  el.inspectModal.classList.remove("open");
  el.inspectModal.setAttribute("aria-hidden", "true");
}

function eventCycle() {
  const now = Date.now();
  if (!state.event.active && now >= state.event.startsAt) {
    state.event.active = true;
    state.event.announced = true;
    document.body.classList.add("event-shift");
    el.featuredBanner.classList.add("event-live");
    showToast("Limited-time event is LIVE");
    logHistory("Event phase started");
    save(STORAGE.event, state.event);
  }

  if (state.event.active && now >= state.event.endsAt) {
    state.event.active = false;
    state.event.startsAt = now + 1000 * 60 * 8;
    state.event.endsAt = now + 1000 * 60 * 14;
    state.event.announced = false;
    document.body.classList.remove("event-shift");
    el.featuredBanner.classList.remove("event-live");
    logHistory("Event phase ended");
    save(STORAGE.event, state.event);
  }

  const target = state.event.active ? state.event.endsAt : state.event.startsAt;
  const remaining = formatMs(target - now);
  el.eventCountdownMain.textContent = state.event.active ? `Ends in ${remaining}` : `Starts in ${remaining}`;
  el.eventCountdownSide.textContent = remaining;
  el.eventPhase.textContent = `Phase: ${state.event.active ? "Event Live" : "Pre-Event"}`;
  el.eventDesc.textContent = state.event.active
    ? "Event cards now spawn with LIMITED badge and boosted hype."
    : "Prepare your shards. Limited packs unlock when timer hits zero.";
}

function handleDailyReward() {
  const today = new Date().toISOString().slice(0, 10);
  const last = localStorage.getItem("acv:last-login");
  if (last === today) return;

  el.dailyReward.classList.add("open");
  el.dailyReward.setAttribute("aria-hidden", "false");
  el.collectRewardBtn.onclick = () => {
    state.inventory.packs += 1;
    state.inventory.shards += 50;
    state.inventory.energyBoosters += 1;
    gainXp(35);

    save(STORAGE.inventory, state.inventory);
    localStorage.setItem("acv:last-login", today);

    el.dailyReward.classList.remove("open");
    el.dailyReward.setAttribute("aria-hidden", "true");
    renderEconomy();
    showToast("Daily reward collected");
  };
}

function initMusicToggle() {
  el.musicToggle.addEventListener("click", () => {
    state.musicOn = !state.musicOn;
    el.musicToggle.textContent = `Music: ${state.musicOn ? "On" : "Off"}`;
    playSfx(state.musicOn ? "music_on" : "music_off");
  });
}

function hookEvents() {
  el.openPackBtn.addEventListener("click", openPackSequence);
  el.openPackBtnTop.addEventListener("click", openPackSequence);
  el.buyPackBtn.addEventListener("click", buyPack);
  el.packStage.addEventListener("click", openPackSequence);

  el.chatForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const msg = el.chatInput.value.trim();
    if (!msg) return;
    postChat((el.chatName.value || "You").trim(), msg);
    el.chatInput.value = "";
    setTimeout(() => {
      const botMsg = [
        "Saving shards for legendary flame packs.",
        "Mythic aura pull incoming.",
        "Leaderboard grind never stops.",
        "Event timer is almost ready."
      ];
      postChat("OtakuBot", botMsg[Math.floor(Math.random() * botMsg.length)]);
    }, 420);
  });

  if (liveChannel) {
    liveChannel.addEventListener("message", (ev) => {
      const { user, msg } = ev.data || {};
      if (!user || !msg) return;
      state.chat.push({ user, msg });
      state.chat = state.chat.slice(-200);
      save(STORAGE.chat, state.chat);
      renderChat();
    });
  }

  el.inspectModal.querySelectorAll("[data-close]").forEach((btn) => {
    btn.addEventListener("click", closeInspect);
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeInspect();
  });
}

function ensureSeedCollection() {
  if (state.inventory.collection.length) return;
  state.inventory.collection = [drawBaseCard(), drawBaseCard(), drawBaseCard()];
  save(STORAGE.inventory, state.inventory);
}

function renderAll() {
  renderProfileCard();
  renderEconomy();
  renderMissions();
  renderBadges();
  renderCollection();
  renderChat();
  renderLeaderboard();
  renderHistory();
  el.recentPullsTicker.textContent = state.pulls.length ? state.pulls.join("  ||  ") : "No pulls yet";
}

function init() {
  initParticles();
  pageTransitions();
  initMusicToggle();
  ensureSeedCollection();
  hookEvents();
  handleDailyReward();
  renderAll();
  eventCycle();
  setInterval(eventCycle, 1000);

  setInterval(() => {
    const npc = ["Akira", "Mina", "Riku", "Yui"][Math.floor(Math.random() * 4)];
    const card = drawBaseCard();
    const line = `${npc} pulled ${card.name} (${card.rarity})`;
    state.pulls.unshift(line);
    state.pulls = state.pulls.slice(0, 8);
    save(STORAGE.pulls, state.pulls);
    el.recentPullsTicker.textContent = state.pulls.join("  ||  ");
  }, 5500);
}

init();
