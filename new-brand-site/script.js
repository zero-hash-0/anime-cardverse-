const items = document.querySelectorAll('.reveal');
const profileImage = document.getElementById('profile-image');

async function resolveProfileImage() {
  if (!profileImage) return;

  const candidates = [
    './assets/alexis-ruiz-profile.jpg',
    './assets/alexis-ruiz-profile.png',
    './assets/alexis-ruiz-profile.jpeg',
    './assets/alexis-ruiz-profile.webp',
    './assets/alexis-ruiz-profile.heic',
  ];

  const exists = (url) =>
    new Promise((resolve) => {
      const img = new Image();
      img.onload = () => resolve(true);
      img.onerror = () => resolve(false);
      img.src = `${url}?v=${Date.now()}`;
    });

  for (const candidate of candidates) {
    if (await exists(candidate)) {
      profileImage.src = candidate;
      return;
    }
  }

  profileImage.src = './assets/profile-placeholder.svg';
}

resolveProfileImage();

const io = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('in');
        io.unobserve(entry.target);
      }
    }
  },
  { threshold: 0.15 }
);

items.forEach((el, idx) => {
  el.style.transitionDelay = `${Math.min(idx * 60, 220)}ms`;
  io.observe(el);
});
