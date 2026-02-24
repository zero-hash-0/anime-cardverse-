const revealElements = document.querySelectorAll('.reveal');

const revealObserver = new IntersectionObserver(
  entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        revealObserver.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.2 }
);

revealElements.forEach(el => revealObserver.observe(el));

const countEls = document.querySelectorAll('[data-count]');
countEls.forEach(el => {
  const target = parseInt(el.dataset.count, 10);
  if (Number.isNaN(target)) return;

  let current = 0;
  const step = Math.max(1, Math.round(target / 36));
  const tick = () => {
    current = Math.min(target, current + step);
    el.textContent = current;
    if (current < target) {
      requestAnimationFrame(tick);
    }
  };
  tick();
});

const salesChartCanvas = document.getElementById('salesChart');
let salesChart;

const parsePrice = price => {
  if (!price) return null;
  const match = price.match(/([0-9.]+)/);
  return match ? parseFloat(match[1]) : null;
};

const buildChartData = sales => {
  const sorted = [...sales].reverse();
  const labels = sorted.map(item => item.timestamp);
  const data = sorted.map(item => parsePrice(item.price));
  return { labels, data };
};

const renderSalesChart = sales => {
  if (!salesChartCanvas || typeof Chart === 'undefined') return;
  const { labels, data } = buildChartData(sales);
  const chartData = {
    labels,
    datasets: [
      {
        label: 'Sale price (SOL)',
        data,
        borderColor: '#f6c067',
        backgroundColor: 'rgba(246, 192, 103, 0.2)',
        tension: 0.32,
        fill: true,
        pointRadius: 3,
      },
    ],
  };

  if (salesChart) {
    salesChart.data = chartData;
    salesChart.update();
    return;
  }

  salesChart = new Chart(salesChartCanvas, {
    type: 'line',
    data: chartData,
    options: {
      responsive: true,
      scales: {
        x: { ticks: { color: '#b7c7c2' }, grid: { color: 'rgba(255,255,255,0.06)' } },
        y: { ticks: { color: '#b7c7c2' }, grid: { color: 'rgba(255,255,255,0.06)' } },
      },
      plugins: {
        legend: { labels: { color: '#f4f7f4' } },
      },
    },
  });
};

const renderSalesTable = sales => {
  const container = document.getElementById('recentSales');
  const countEl = document.getElementById('salesCount');
  if (!container) return;

  container.innerHTML = '';
  if (!sales.length) {
    const empty = document.createElement('div');
    empty.className = 'table-empty';
    empty.textContent = 'No sales recorded yet.';
    container.appendChild(empty);
  } else {
    sales.forEach(sale => {
      const row = document.createElement('div');
      row.className = 'table-row';
      const traits =
        sale.traits && sale.traits.length
          ? `<span class="traits">${sale.traits.map(t => `<em>${t}</em>`).join('')}</span>`
          : '';
      const preview = sale.image
        ? `<img src="${sale.image}" alt="${sale.name}" loading="lazy" />`
        : `<div class="preview-fallback">GG</div>`;
      row.innerHTML = `
        <span class="preview">${preview}</span>
        <span>${sale.name}${traits}</span>
        <span>${sale.price}</span>
        <span>${sale.marketplace}</span>
        <span>${sale.buyer}</span>
        <span>${sale.timestamp}</span>
      `;
      container.appendChild(row);
    });
  }

  if (countEl) {
    countEl.textContent = `${sales.length} events`;
  }
};

const renderListingsTable = listings => {
  const container = document.getElementById('recentListings');
  const countEl = document.getElementById('listingCount');
  if (!container) return;

  container.innerHTML = '';
  if (!listings.length) {
    const empty = document.createElement('div');
    empty.className = 'table-empty';
    empty.textContent = 'No listings recorded yet.';
    container.appendChild(empty);
  } else {
    listings.forEach(listing => {
      const row = document.createElement('div');
      row.className = 'table-row';
      const traits =
        listing.traits && listing.traits.length
          ? `<span class="traits">${listing.traits.map(t => `<em>${t}</em>`).join('')}</span>`
          : '';
      const preview = listing.image
        ? `<img src="${listing.image}" alt="${listing.name}" loading="lazy" />`
        : `<div class="preview-fallback">GG</div>`;
      row.innerHTML = `
        <span class="preview">${preview}</span>
        <span>${listing.name}${traits}</span>
        <span>${listing.price}</span>
        <span>${listing.marketplace}</span>
        <span>${listing.seller}</span>
        <span>${listing.timestamp}</span>
      `;
      container.appendChild(row);
    });
  }

  if (countEl) {
    countEl.textContent = `${listings.length} events`;
  }
};

const updateStatusPage = payload => {
  const stats = payload.stats || {};
  const recentSales = payload.recent_sales || [];
  const recentListings = payload.recent_listings || [];

  const setText = (id, value) => {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  };

  setText('salesSeen', stats.sales_seen ?? '0');
  setText('salesSent', stats.sales_sent ?? '0');
  setText('lastEvent', stats.last_event_time ?? 'No sales yet');
  setText('mintCount', stats.watch_mints_count ?? '0');
  setText('volume24h', stats.volume_24h ?? '0');
  setText('sales24h', stats.sales_24h ?? '0');
  setText('watchSources', (stats.watch_sources || []).join(', '));
  setText('mintlistUrl', stats.mintlist_url ?? 'Not set');

  renderSalesTable(recentSales);
  renderListingsTable(recentListings);
  renderSalesChart(recentSales);
  renderTicker(recentSales);
};

const pollStatus = async () => {
  try {
    const response = await fetch('/api/status');
    if (!response.ok) return;
    const payload = await response.json();
    updateStatusPage(payload);
  } catch (err) {
    console.warn('Status poll failed', err);
  }
};

if (salesChartCanvas) {
  if (window.__recentSales) {
    renderSalesChart(window.__recentSales);
  }
  if (window.EventSource) {
    const source = new EventSource('/api/stream');
    source.onmessage = event => {
      try {
        const payload = JSON.parse(event.data);
        updateStatusPage(payload);
      } catch (err) {
        console.warn('Stream parse failed', err);
      }
    };
    source.onerror = () => {
      source.close();
      pollStatus();
      setInterval(pollStatus, 10000);
    };
  } else {
    pollStatus();
    setInterval(pollStatus, 10000);
  }
}

const renderTicker = sales => {
  const ticker = document.getElementById('tickerContent');
  const spotlight = document.getElementById('spotlightContent');
  if (!ticker || !spotlight) return;

  if (!sales.length) {
    ticker.innerHTML = '<div class="ticker-empty">Waiting for the first sale.</div>';
    spotlight.innerHTML = '<div class="spotlight-empty">No sales yet.</div>';
    return;
  }

  const latest = sales[0];
  const preview = latest.image
    ? `<img src="${latest.image}" alt="${latest.name}" loading="lazy" />`
    : `<div class="preview-fallback">GG</div>`;
  const tags = latest.tags && latest.tags.length ? `<span class="tags">${latest.tags.map(t => `<em>${t}</em>`).join('')}</span>` : '';
  const traits =
    latest.traits && latest.traits.length
      ? `<div class="traits">${latest.traits.map(t => `<em>${t}</em>`).join('')}</div>`
      : '';

  ticker.innerHTML = `
    <div class="ticker-item">
      <div class="ticker-image">${preview}</div>
      <div class="ticker-info">
        <strong>${latest.name}</strong>
        <span>${latest.price} · ${latest.marketplace}</span>
        ${tags}
      </div>
    </div>
  `;

  spotlight.innerHTML = `
    <div class="spotlight-card">
      <div class="spotlight-image">${preview}</div>
      <div class="spotlight-info">
        <h3>${latest.name}</h3>
        <p>${latest.price} · ${latest.marketplace}</p>
        ${traits}
      </div>
    </div>
  `;
};
