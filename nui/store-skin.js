/* Cosmetic DOM adapter. No input handlers, network requests or business state. */
(() => {
  'use strict';
  const classes = {
    "wst-panel": "#bank,dialog",
    "wst-header": ".content>header,dialog h2",
    "wst-title": "h1,dialog h2",
    // Reading text, labels, the accounts strip and the summary card carry their own theme roles in
    // style.css / store-skin.css (no wst-sub, no wst-plate). Big figures only are wst-num: the account
    // number and the statement's figures are EB Garamond, lining and tabular.
    "wst-num": ".balance strong",
    "wst-tab": "nav button",
    "wst-card": ".quick button",
    "wst-input": "input,select",
    "wst-close": "#close",
    "store-footer": ".content>footer"
};
  const frameParts = ['t','b','l','r','tl','tr','bl','br'];
  function decorate() {
    for (const [name, selector] of Object.entries(classes)) {
      document.querySelectorAll(selector).forEach(node => node.classList.add(name));
    }
    document.querySelectorAll('.wst-plate,.wst-close').forEach(node => {
      if (getComputedStyle(node).position === 'static') node.classList.add('store-positioned');
    });
    document.querySelectorAll('button:not(.wst-tab):not(.wst-card):not(.wst-close)').forEach(node => {
      node.classList.add('wst-button');
      if (node.matches('.red,.is-primary,.light')) node.classList.add('primary');
      if (node.matches('.is-danger')) node.classList.add('danger');
    });
    document.querySelectorAll('input.wst-input,select.wst-input').forEach(input => {
      if (!input.parentElement.classList.contains('wst-field')) {
        const plate = document.createElement('span'); plate.className = 'store-input-wrap wst-field';
        input.before(plate); plate.append(input);
      }
      const plate = input.parentElement;
      if (plate.classList.contains('store-input-wrap') && plate.hidden !== input.hidden) plate.hidden = input.hidden;
    });
    document.querySelectorAll('.wst-panel').forEach(panel => {
      if (panel.querySelector(':scope > .wst-frame')) return;
      const frame = document.createElement('div');
      frame.className = 'wst-frame'; frame.setAttribute('aria-hidden', 'true');
      for (const part of frameParts) {
        const edge = document.createElement('span'); edge.className = 'wst-fr-' + part; frame.append(edge);
      }
      panel.prepend(frame);
    });
  }
  decorate();
  // Reapply before paint. Only hidden attributes are observed, never our cosmetic classes.
  new MutationObserver(decorate).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['hidden'] });
})();
