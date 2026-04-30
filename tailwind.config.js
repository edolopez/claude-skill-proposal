/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./template.html', './examples/*.html', './vercel-starter/index.html'],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
        serif: ['Fraunces', 'ui-serif', 'Georgia', 'serif'],
      },
    },
  },
  plugins: [],
  // Safelist: critical utilities that may not be statically inferable from
  // template.html alone (used by examples or generated content).
  safelist: [
    'md:grid-cols-2', 'md:grid-cols-3', 'md:grid-cols-4',
    'grid-cols-2', 'grid-cols-3', 'grid-cols-4',
    'sm:flex-row',
  ],
};
