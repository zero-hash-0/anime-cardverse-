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
  chat: "anime-cardverse:chat"
};

const pack = document.getElementById("pack");
const openPackBtn = document.getElementById("openPackBtn");
const buyPackBtn = document.getElementById("buyPackBtn");
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
const cardTemplate = document.getElementById("cardTemplate");

const collection = loadStored(STORAGE_KEYS.collection, []);
const chatHistory = loadStored(STORAGE_KEYS.chat, []);
let packs = loadStored(STORAGE_KEYS.packs, 5);
let announcementIndex = 0;

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

function updatePackStock() {
  packStock.textContent = `Packs: ${packs}`;
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

function openPack() {
  if (pack.classList.contains("burst") || packs <= 0) return;

  revealGrid.innerHTML = "";
  pack.classList.add("burst");
  packs -= 1;
  updatePackStock();
  store(STORAGE_KEYS.packs, packs);

  window.setTimeout(() => {
    const pulled = randomCards(3);
    pulled.forEach((card, idx) => {
      revealGrid.appendChild(buildCard(card, idx * 130));
      collection.unshift(card);
    });
    store(STORAGE_KEYS.collection, collection);
    drawCollection();
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
  item.innerHTML = `<span class="chat-user">${entry.user}:</span> ${entry.message}`;
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
  postMessage("OtakuBot", responses[Math.floor(Math.random() * responses.length)]);
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
  packs += 1;
  updatePackStock();
  store(STORAGE_KEYS.packs, packs);
});

rarityFilter.addEventListener("change", drawCollection);

clearCollectionBtn.addEventListener("click", () => {
  collection.length = 0;
  revealGrid.innerHTML = "";
  store(STORAGE_KEYS.collection, collection);
  drawCollection();
});

chatForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const message = chatInput.value.trim();
  if (!message) return;

  const user = chatName.value.trim() || "You";
  postMessage(user, message);
  chatInput.value = "";

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

updatePackStock();
rotateAnnouncement();
window.setInterval(rotateAnnouncement, 5000);
window.setInterval(() => {
  const current = (announcementIndex - 1 + releaseSchedule.length) % releaseSchedule.length;
  const live = releaseSchedule[current];
  ticker.textContent = `${live.show} ${relativeCountdown(live.date)}`;
}, 60000);

drawCollection();
drawChat();
