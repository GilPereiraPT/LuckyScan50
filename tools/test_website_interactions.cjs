'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
class Element {
  constructor(state) {
    this.dataset = {state}; this.attrs = {}; this.handlers = {}; this.classes = new Set();
    this.classList = {
      toggle: (name, enabled) => enabled ? this.classes.add(name) : this.classes.delete(name),
      remove: name => this.classes.delete(name)
    };
    this.focused = false; this.textContent = '';
  }
  addEventListener(name, fn) { this.handlers[name] = fn; }
  getAttribute(name) { return this.attrs[name]; }
  setAttribute(name, value) { this.attrs[name] = value; }
  focus() { this.focused = true; }
  click() { this.handlers.click(); }
}
const menu = new Element();
menu.setAttribute('aria-expanded', 'false');
const nav = new Element(), link = new Element();
nav.querySelectorAll = () => [link];
const buttons = ['pending', 'none', 'prize'].map(state => new Element(state));
const status = new Element(), description = new Element(), handlers = {};
const document = {
  querySelector: selector => ({'.menu-toggle': menu, '#navegacao': nav}[selector]),
  querySelectorAll: selector => selector === '[data-state]' ? buttons : [],
  getElementById: id => ({'demo-status': status, 'demo-description': description}[id]),
  addEventListener: (name, fn) => { handlers[name] = fn; }
};
vm.runInNewContext(fs.readFileSync('website/script.js', 'utf8'), {document});
menu.click();
assert.equal(menu.getAttribute('aria-expanded'), 'true');
assert.ok(nav.classes.has('is-open'));
link.click();
assert.equal(menu.getAttribute('aria-expanded'), 'false');
assert.ok(!nav.classes.has('is-open'));
menu.click();
handlers.keydown({key: 'Escape'});
assert.equal(menu.getAttribute('aria-expanded'), 'false');
assert.equal(menu.focused, true);
for (const button of buttons) {
  button.click();
  assert.equal(buttons.filter(item => item.getAttribute('aria-pressed') === 'true').length, 1);
  assert.equal(button.getAttribute('aria-pressed'), 'true');
  assert.ok(status.textContent.length > 5);
  assert.ok(description.textContent.length > 20);
}
assert.equal(status.textContent, 'Prémio identificado');
console.log('PASS: mobile navigation, Escape focus and all three demo states.');
