// dev only: what client/client.lua sends when a player opens the counter (openbank with the page's words), so
// dev.html shows the board without the game. ?lang=ar|en, ?savings=0 (no savings account yet).
import ar from '../../../locales/ar.json';
import en from '../../../locales/en.json';

const q = new URLSearchParams(location.search);
const lang = q.get('lang') === 'en' ? 'en' : 'ar';
const flat = (o, p = '', r = {}) => {
  for (const [k, v] of Object.entries(o)) {
    if (v && typeof v === 'object' && !Array.isArray(v)) flat(v, p + k + '.', r);
    else r[p + k] = v;
  }
  return r;
};
const strings = Object.fromEntries(
  Object.entries(flat(lang === 'en' ? en : ar)).filter(([k]) => k.startsWith('ui.') || k.startsWith('nui.')),
);
const types = ['Cash deposit', 'Transfer to 10030', 'Cash withdrawal', 'Transfer from 10044', 'To savings', 'From savings'];
const information = {
  name: lang === 'en' ? 'Abdullah Alotaibi' : 'عبدالله العتيبي',
  accountinfo: '10029',
  bankbalance: 8250,
  cash: 450.75,
  taxRate: 2,
  savings: q.get('savings') === '0' ? null : { amount: 2200 },
  history: types.map((type, i) => ({
    date: `2026-11-0${8 - i} 12:3${i}`,
    type,
    account: i === 4 || i === 5 ? 'Savings' : 'Bank',
    deposited: [0, 3, 5].includes(i) ? 100 + i * 10 : 0,
    withdraw: [0, 3, 5].includes(i) ? 0 : 40 + i,
    balance: 8250 - i * 60,
  })),
};
// the page's callbacks go to https://w_banking/<name>; answer them here
const realFetch = window.fetch.bind(window);
window.GetParentResourceName = () => 'w_banking';
window.fetch = (url, init) =>
  String(url).startsWith('https://w_banking/')
    ? Promise.resolve(new Response(JSON.stringify({ information }), { headers: { 'Content-Type': 'application/json' } }))
    : realFetch(url, init);
setTimeout(() => window.postMessage({ status: 'openbank', locale: lang, dir: lang === 'en' ? 'ltr' : 'rtl', strings, information }, '*'), 200);
