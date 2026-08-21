const THEME_KEY = 'gemboy-debug-theme';
const themeMedia = window.matchMedia('(prefers-color-scheme: light)');

// Reads a CSS custom property so canvas drawing follows the active theme.
function themeColor(name) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

function applyTheme(theme) {
  const resolved = theme === 'auto' ? (themeMedia.matches ? 'light' : 'dark') : theme;
  document.documentElement.dataset.theme = resolved;
  document.documentElement.style.colorScheme = resolved;
}

function setTheme(theme) {
  localStorage.setItem(THEME_KEY, theme);
  applyTheme(theme);
  if (typeof render === 'function') render();
}

const storedTheme = localStorage.getItem(THEME_KEY) || 'auto';
applyTheme(storedTheme);

themeMedia.addEventListener('change', () => {
  if ((localStorage.getItem(THEME_KEY) || 'auto') === 'auto') {
    applyTheme('auto');
    if (typeof render === 'function') render();
  }
});

document.addEventListener('DOMContentLoaded', () => {
  const select = document.getElementById('theme');
  select.value = storedTheme;
  select.addEventListener('change', (event) => setTheme(event.target.value));
});
