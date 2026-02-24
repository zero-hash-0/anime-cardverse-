document.body.classList.add('js-ready');

const profileImage = document.getElementById('profile-image');

async function resolveProfileImage() {
  if (!profileImage) return;

  const candidates = [
    './assets/profile-nottokyo.jpg',
    './assets/profile-nottokyo.png',
    './assets/profile-nottokyo.jpeg',
    './assets/profile-nottokyo.webp',
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
      profileImage.classList.remove('image-fallback');
      return;
    }
  }

  profileImage.src = './assets/profile-placeholder.svg';
  profileImage.classList.add('image-fallback');
}

resolveProfileImage();

const revealed = document.querySelectorAll('.reveal');

const observer = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add('in-view');
        observer.unobserve(entry.target);
      }
    }
  },
  {
    threshold: 0.2,
    rootMargin: '0px 0px -40px 0px',
  }
);

revealed.forEach((item, i) => {
  item.style.transitionDelay = `${Math.min(i * 70, 350)}ms`;
  observer.observe(item);
});
