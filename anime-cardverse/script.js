const animePool = [
  { name: "Shadow Hokage", series: "Naruto", rarity: "Epic", power: 92 },
  { name: "Titan Breaker", series: "Attack on Titan", rarity: "Rare", power: 88 },
  { name: "Soul Reaper Prime", series: "Bleach", rarity: "Legendary", power: 96 },
  { name: "Pirate Emperor", series: "One Piece", rarity: "Mythic", power: 99 },
  { name: "Cursed Vessel", series: "Jujutsu Kaisen", rarity: "Epic", power: 93 },
  { name: "Hero Number One", series: "My Hero Academia", rarity: "Rare", power: 85 },
  { name: "Alchemy Storm", series: "Fullmetal Alchemist", rarity: "Legendary", power: 95 },
  { name: "Demon Slayer Flame", series: "Demon Slayer", rarity: "Epic", power: 90 },
  { name: "Death Note Strategist", series: "Death Note", rarity: "Ultra", power: 94 },
  { name: "Chainsaw Vanguard", series: "Chainsaw Man", rarity: "Epic", power: 91 },
  { name: "Phantom Troupe Ace", series: "Hunter x Hunter", rarity: "Legendary", power: 97 }
];

const releaseSchedule = [
  { show: "Solo Leveling S2", date: "2026-03-18T18:00:00" },
  { show: "My Hero Academia Arc", date: "2026-04-05T19:30:00" },
  { show: "Demon Slayer Film", date: "2026-05-02T20:00:00" },
  { show: "Kaiju No. 8 Special", date: "2026-06-20T21:00:00" }
];

const globalNames = ["Akira", "Nobu", "Yuna", "Sora", "Kento", "Mika", "Ren", "Aoi"];
const themes = [
  {
    name: "Neo Tokyo",
    vars: {
      "--bg-start": "#1d093d",
      "--bg-mid": "#111f52",
      "--bg-end": "#2d0d42",
      "--cyan": "#41f8ff",
      "--pink": "#ff5dcf",
      "--yellow": "#ffe04d",
      "--orange": "#ff9a4d",
      "--line": "rgba(138, 255, 224, 0.28)"
    }
  },
  {
    name: "Cyber Sunset",
    vars: {
      "--bg-start": "#2f1022",
      "--bg-mid": "#46201b",
      "--bg-end": "#2d183f",
      "--cyan": "#6cf9ff",
      "--pink": "#ff4d8a",
      "--yellow": "#ffd166",
      "--orange": "#ff8f3f",
      "--line": "rgba(255, 209, 102, 0.32)"
    }
  },
  {
    name: "Aqua Pop",
    vars: {
      "--bg-start": "#0a2636",
      "--bg-mid": "#153d4f",
      "--bg-end": "#173159",
      "--cyan": "#45ffe9",
      "--pink": "#ff69b7",
      "--yellow": "#fff07a",
      "--orange": "#ffb85a",
      "--line": "rgba(69, 255, 233, 0.32)"
    }
  }
];

const missionsConfig = [
  { id: "open_packs", title: "Pack Hunter", goal: 5, reward: 120, metric: "packsOpened" },
  { id: "send_messages", title: "Chat Sprinter", goal: 8, reward: 90, metric: "messagesSent" },
  { id: "pull_mythic", title: "Mythic Fever", goal: 1, reward: 160, metric: "mythicsPulled" }
];

const rarityStyles = {
  Rare: { bg: "rgba(65,248,255,.24)", color: "#84fcff" },
  Epic: { bg: "rgba(255,93,207,.24)", color: "#ff90dd" },
  Legendary: { bg: "rgba(255,224,77,.26)", color: "#ffe67c" },
  Mythic: { bg: "rgba(255,92,64,.28)", color: "#ffb0a0" },
  Ultra: { bg: "rgba(128,255,196,.25)", color: "#a8ffd8" }
};

const drawWeights = [
  { rarity: "Mythic", weight: 4 },
  { rarity: "Legendary", weight: 12 },
  { rarity: "Ultra", weight: 14 },
  { rarity: "Epic", weight: 30 },
  { rarity: "Rare", weight: 40 }
];

const STORAGE_KEYS = {
  collection: "anime-cardverse:collection",
  packs: "anime-cardverse:packs",
  chat: "anime-cardverse:chat",
  shards: "anime-cardverse:shards",
  missions: "anime-cardverse:missions",
  streak: "anime-cardverse:streak",
  globalFeed: "anime-cardverse:global-feed",
  theme: "anime-cardverse:theme"
};

const pack = document.getElementById("pack");
const openPackBtn = document.getElementById("openPackBtn");
const buyPackBtn = document.getElementById("buyPackBtn");
const cycleThemeBtn = document.getElementById("cycleThemeBtn");
const packStock = document.getElementById("packStock");
const revealGrid = document.getElementById("revealGrid");
const collectionGrid = document.getElementById("collectionGrid");
const collectionCount = document.getElementById("collectionCount");
const ticker = document.getElementById("ticker");
const chatFeed = document.getElementById("chatFeed");
const chatForm = document.getElementById("chatForm");
const chatInput = document.getElementById("chatInput");
const chatName = document.getElementById("chatName");
const rarityFilter = document.getElementById("rarityFilter");
const clearCollectionBtn = document.getElementById("clearCollectionBtn");
const globalFeed = document.getElementById("globalFeed");
const missions = document.getElementById("missions");
const totalPowerEl = document.getElementById("totalPower");
const mythicCountEl = document.getElementById("mythicCount");
const hypeStreakEl = document.getElementById("hypeStreak");
const shardStockEl = document.getElementById("shardStock");
const toast = document.getElementById("toast");
const cardTemplate = document.getElementById("cardTemplate");

const collection = loadStored(STORAGE_KEYS.collection, []);
const chatHistory = loadStored(STORAGE_KEYS.chat, []);
const worldEvents = loadStored(STORAGE_KEYS.globalFeed, []);
let packs = loadStored(STORAGE_KEYS.packs, 5);
let shards = loadStored(STORAGE_KEYS.shards, 260);
let missionState = loadStored(STORAGE_KEYS.missions, {
  packsOpened: 0,
  messagesSent: 0,
  mythicsPulled: 0,
  claimed: {}
});
let streakState = loadStored(STORAGE_KEYS.streak, { day: "", count: 0 });
let announcementIndex = 0;
let toastTimer = null;
let themeIndex = loadStored(STORAGE_KEYS.theme, 0);

const liveChannel = typeof BroadcastChannel !== "undefined" ? new BroadcastChannel("anime-cardverse-chat") : null;

function loadStored(key, fallback) {
  try {
    const raw = window.localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}

function store(key, value) {
  window.localStorage.setItem(key, JSON.stringify(value));
}

function clampFeed(feed, max = 35) {
  return feed.slice(0, max);
}

function showToast(message) {
  toast.textContent = message;
  toast.classList.add("show");
  if (toastTimer) window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => toast.classList.remove("show"), 1600);
}

function applyTheme(index) {
  const safeIndex = ((index % themes.length) + themes.length) % themes.length;
  themeIndex = safeIndex;
  const theme = themes[safeIndex];
  Object.entries(theme.vars).forEach(([key, value]) => {
    document.documentElement.style.setProperty(key, value);
  });
  store(STORAGE_KEYS.theme, themeIndex);
  if (cycleThemeBtn) {
    cycleThemeBtn.textContent = `Theme: ${theme.name}`;
  }
}

function weightedRarityPick() {
  const totalWeight = drawWeights.reduce((total, item) => total + item.weight, 0);
  let roll = Math.random() * totalWeight;
  for (const item of drawWeights) {
    if (roll < item.weight) return item.rarity;
    roll -= item.weight;
  }
  return "Rare";
}

function drawCard() {
  const rarity = weightedRarityPick();
  const candidates = animePool.filter((card) => card.rarity === rarity);
  return candidates[Math.floor(Math.random() * candidates.length)] || animePool[0];
}

function randomCards(total) {
  return Array.from({ length: total }, () => drawCard());
}

function buildCard(card, delay = 0) {
  const node = cardTemplate.content.firstElementChild.cloneNode(true);
  node.style.animationDelay = `${delay}ms`;
  node.querySelector("h3").textContent = card.name;
  node.querySelector(".series").textContent = `Series: ${card.series}`;
  node.querySelector(".power").textContent = `Power: ${card.power}`;

  const pill = node.querySelector(".rarity-pill");
  const style = rarityStyles[card.rarity] || rarityStyles.Rare;
  pill.textContent = card.rarity;
  pill.style.background = style.bg;
  pill.style.color = style.color;

  return node;
}

function updateStreakForToday() {
  const now = new Date();
  const today = now.toISOString().slice(0, 10);
  if (streakState.day === today) return;

  const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  streakState.count = streakState.day === yesterday ? streakState.count + 1 : 1;
  streakState.day = today;
  store(STORAGE_KEYS.streak, streakState);
}

function updatePackStock() {
  packStock.textContent = `Packs: ${packs}`;
}

function updateShardStock() {
  shardStockEl.textContent = String(shards);
}

function drawCollection() {
  const activeFilter = rarityFilter.value;
  collectionGrid.innerHTML = "";

  const filtered = activeFilter === "All"
    ? collection
    : collection.filter((card) => card.rarity === activeFilter);

  filtered.forEach((card, index) => collectionGrid.appendChild(buildCard(card, index * 20)));
  collectionCount.textContent = `${collection.length} cards collected`;
}

function updateStats() {
  const totalPower = collection.reduce((sum, card) => sum + card.power, 0);
  const mythicCount = collection.filter((card) => card.rarity === "Mythic").length;
  totalPowerEl.textContent = String(totalPower);
  mythicCountEl.textContent = String(mythicCount);
  hypeStreakEl.textContent = `${streakState.count} days`;
}

function missionProgress(id) {
  const config = missionsConfig.find((mission) => mission.id === id);
  if (!config) return 0;
  return Math.min(missionState[config.metric] || 0, config.goal);
}

function drawMissions() {
  missions.innerHTML = "";
  missionsConfig.forEach((mission) => {
    const progress = missionProgress(mission.id);
    const isReady = progress >= mission.goal;
    const claimed = Boolean(missionState.claimed[mission.id]);

    const card = document.createElement("article");
    card.className = "mission";

    const head = document.createElement("div");
    head.className = "mission-head";

    const title = document.createElement("p");
    title.className = "mission-title";
    title.textContent = mission.title;

    const reward = document.createElement("p");
    reward.className = "mission-meta";
    reward.textContent = `${mission.reward} shards`;

    head.appendChild(title);
    head.appendChild(reward);

    const meta = document.createElement("p");
    meta.className = "mission-meta";
    meta.textContent = `${progress}/${mission.goal}`;

    const track = document.createElement("div");
    track.className = "progress-track";

    const fill = document.createElement("div");
    fill.className = "progress-fill";
    fill.style.width = `${Math.round((progress / mission.goal) * 100)}%`;
    track.appendChild(fill);

    const claim = document.createElement("button");
    claim.type = "button";
    claim.textContent = claimed ? "Claimed" : "Claim";
    claim.disabled = claimed || !isReady;
    claim.addEventListener("click", () => {
      if (claim.disabled) return;
      missionState.claimed[mission.id] = true;
      shards += mission.reward;
      updateShardStock();
      store(STORAGE_KEYS.shards, shards);
      store(STORAGE_KEYS.missions, missionState);
      drawMissions();
      showToast(`Mission complete: +${mission.reward} shards`);
    });

    card.appendChild(head);
    card.appendChild(meta);
    card.appendChild(track);
    card.appendChild(claim);
    missions.appendChild(card);
  });
}

function addMissionProgress(metric, amount = 1) {
  missionState[metric] = (missionState[metric] || 0) + amount;
  store(STORAGE_KEYS.missions, missionState);
  drawMissions();
}

function pushGlobalEvent(text, persist = true) {
  const entry = { text, ts: Date.now() };
  worldEvents.unshift(entry);
  const trimmed = clampFeed(worldEvents);
  worldEvents.length = 0;
  worldEvents.push(...trimmed);

  if (persist) store(STORAGE_KEYS.globalFeed, worldEvents);
  drawGlobalFeed();
}

function drawGlobalFeed() {
  globalFeed.innerHTML = "";
  worldEvents.forEach((entry) => {
    const p = document.createElement("p");
    p.className = "global-item";
    p.innerHTML = entry.text;
    globalFeed.appendChild(p);
  });
}

function openPack() {
  if (pack.classList.contains("burst")) return;
  if (packs <= 0) {
    showToast("No packs left. Buy one with shards.");
    return;
  }

  revealGrid.innerHTML = "";
  pack.classList.add("burst");
  packs -= 1;
  updatePackStock();
  store(STORAGE_KEYS.packs, packs);

  updateStreakForToday();
  addMissionProgress("packsOpened", 1);

  window.setTimeout(() => {
    const pulled = randomCards(3);
    pulled.forEach((card, idx) => {
      revealGrid.appendChild(buildCard(card, idx * 130));
      collection.unshift(card);
      if (card.rarity === "Mythic") {
        addMissionProgress("mythicsPulled", 1);
      }
      pushGlobalEvent(`<b>You</b> pulled <b>${card.name}</b> (${card.rarity})`);
    });

    const duplicateBonus = pulled.filter((card) =>
      collection.slice(3).some((existing) => existing.name === card.name)
    ).length;

    if (duplicateBonus) {
      const bonusShards = duplicateBonus * 15;
      shards += bonusShards;
      updateShardStock();
      store(STORAGE_KEYS.shards, shards);
      showToast(`Duplicate bonus: +${bonusShards} shards`);
    }

    store(STORAGE_KEYS.collection, collection);
    drawCollection();
    updateStats();
    pack.classList.remove("burst");
  }, 700);
}

function relativeCountdown(targetDateString) {
  const target = new Date(targetDateString).getTime();
  const now = Date.now();
  const diff = target - now;

  if (diff <= 0) return "is live now";

  const days = Math.floor(diff / (1000 * 60 * 60 * 24));
  const hours = Math.floor((diff / (1000 * 60 * 60)) % 24);
  const minutes = Math.floor((diff / (1000 * 60)) % 60);
  return `drops in ${days}d ${hours}h ${minutes}m`;
}

function rotateAnnouncement() {
  const item = releaseSchedule[announcementIndex];
  ticker.textContent = `${item.show} ${relativeCountdown(item.date)}`;
  announcementIndex = (announcementIndex + 1) % releaseSchedule.length;
}

function renderMessage(entry) {
  const item = document.createElement("p");
  item.className = "chat-msg";

  const user = document.createElement("span");
  user.className = "chat-user";
  user.textContent = `${entry.user}:`;

  item.appendChild(user);
  item.appendChild(document.createTextNode(` ${entry.message}`));
  chatFeed.appendChild(item);
}

function drawChat() {
  chatFeed.innerHTML = "";
  chatHistory.slice(-60).forEach((entry) => renderMessage(entry));
  chatFeed.scrollTop = chatFeed.scrollHeight;
}

function postMessage(user, message, sync = true) {
  const entry = { user, message, ts: Date.now() };
  chatHistory.push(entry);
  store(STORAGE_KEYS.chat, chatHistory.slice(-200));
  renderMessage(entry);
  chatFeed.scrollTop = chatFeed.scrollHeight;

  if (sync && liveChannel) {
    liveChannel.postMessage(entry);
  }
}

function addBotReply() {
  const responses = [
    "That drop is going to be wild.",
    "Need that Mythic pull today.",
    "The spring lineup is stacked.",
    "Show me your best Legendary pull."
  ];
  const msg = responses[Math.floor(Math.random() * responses.length)];
  postMessage("OtakuBot", msg);
}

function generateGlobalPull() {
  const player = globalNames[Math.floor(Math.random() * globalNames.length)];
  const card = drawCard();
  pushGlobalEvent(`<b>${player}</b> pulled <b>${card.name}</b> (${card.rarity})`);
}

pack.addEventListener("click", openPack);
pack.addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    openPack();
  }
});

openPackBtn.addEventListener("click", openPack);

buyPackBtn.addEventListener("click", () => {
  const cost = 70;
  if (shards < cost) {
    showToast(`Need ${cost} shards for a pack`);
    return;
  }
  shards -= cost;
  packs += 1;
  updateShardStock();
  updatePackStock();
  store(STORAGE_KEYS.shards, shards);
  store(STORAGE_KEYS.packs, packs);
  showToast("+1 pack added");
});

cycleThemeBtn.addEventListener("click", () => {
  applyTheme(themeIndex + 1);
  showToast("Visual theme shifted");
});

rarityFilter.addEventListener("change", drawCollection);

clearCollectionBtn.addEventListener("click", () => {
  collection.length = 0;
  revealGrid.innerHTML = "";
  store(STORAGE_KEYS.collection, collection);
  drawCollection();
  updateStats();
  showToast("Collection reset");
});

chatForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const message = chatInput.value.trim();
  if (!message) return;

  const user = chatName.value.trim() || "You";
  postMessage(user, message);
  chatInput.value = "";
  addMissionProgress("messagesSent", 1);

  window.setTimeout(addBotReply, 450);
});

if (liveChannel) {
  liveChannel.addEventListener("message", (event) => {
    const entry = event.data;
    if (!entry || !entry.user || !entry.message) return;
    postMessage(entry.user, entry.message, false);
  });
}

if (!chatHistory.length) {
  [
    { user: "Mina", message: "Anyone opening packs tonight?" },
    { user: "Kai", message: "I just pulled Pirate Emperor!" },
    { user: "Riku", message: "Do not miss the trailer drop stream." }
  ].forEach((seed) => chatHistory.push({ ...seed, ts: Date.now() }));
  store(STORAGE_KEYS.chat, chatHistory);
}

if (!worldEvents.length) {
  pushGlobalEvent("<b>System</b> live arena feed initialized");
  generateGlobalPull();
  generateGlobalPull();
}

updatePackStock();
updateShardStock();
applyTheme(themeIndex);
updateStats();
rotateAnnouncement();
drawCollection();
drawChat();
drawMissions();
drawGlobalFeed();

window.setInterval(rotateAnnouncement, 5000);
window.setInterval(() => {
  const current = (announcementIndex - 1 + releaseSchedule.length) % releaseSchedule.length;
  const live = releaseSchedule[current];
  ticker.textContent = `${live.show} ${relativeCountdown(live.date)}`;
}, 60000);
window.setInterval(generateGlobalPull, 4000);
