document.body.classList.add('js-ready');

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
