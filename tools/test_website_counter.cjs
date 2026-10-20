'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('website/counter.js', 'utf8');
async function run(response, missing = false) {
  const target = {textContent: '—', attrs: {}, setAttribute(name, value) { this.attrs[name] = value; }};
  const calls = [];
  await vm.runInNewContext(source, {
    document: {getElementById: () => missing ? null : target},
    AbortController, setTimeout, clearTimeout, Intl,
    fetch: async (url, options) => {
      calls.push({url, options});
      if (response instanceof Error) throw response;
      return response;
    }
  });
  return {target, calls};
}
(async () => {
  const ok = await run({ok: true, json: async () => ({total: 12345})});
  assert.equal(ok.target.textContent.replace(/\s/g, ''), '12345');
  assert.equal(ok.calls.length, 1);
  assert.equal(ok.calls[0].options.credentials, 'omit');
  assert.equal(ok.calls[0].options.method, 'POST');
  assert.deepEqual(JSON.parse(ok.calls[0].options.body), {event: 'pageview'});
  for (const response of [
    {ok: false},
    {ok: true, json: async () => ({total: -1})},
    new Error('Timeout')
  ]) {
    const failure = await run(response);
    assert.equal(failure.target.textContent, 'Indisponível');
    assert.equal(failure.calls.length, 1, 'Must not retry an uncertain increment');
  }
  assert.equal((await run({}, true)).calls.length, 0);
  console.log('PASS: global total, minimal event, offline state and no duplicate retries.');
})().catch(error => { console.error(error); process.exitCode = 1; });
