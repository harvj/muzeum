import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';
import { chromium } from 'playwright-core';

const shared = process.env.INFRA_BROWSER_TOOLS;
const { runCandidate } = await import(pathToFileURL(shared + '/run.mjs'));
const { nativeLogin } = await import(pathToFileURL(shared + '/native-auth.mjs'));
const env = process.env;
const origin = 'https://muzeum.fm';
const issuer = 'https://auth.harvj.com';
const callback = origin + '/oidc/callback';
const identity = JSON.parse(fs.readFileSync('identity.json'));
const binding = JSON.parse(fs.readFileSync('binding.json'));
const hash = path => createHash('sha256').update(fs.readFileSync(path)).digest('hex');
assert.equal(hash('environment.json'), binding.environment_sha256);
const chrome = {
  launch(options) {
    return chromium.launch({ ...options, executablePath: env.CHROME_BINARY,
      proxy: { server: 'http://127.0.0.1:55495' }, args: [...options.args,
        '--ignore-certificate-errors-spki-list=' + fs.readFileSync('spki', 'utf8').trim()] });
  },
};
function permits(method, raw) {
  const url = new URL(raw);
  if (url.username || url.password || ![origin, issuer].includes(url.origin)) return false;
  if (['GET', 'HEAD'].includes(method)) return true;
  if (url.search || url.hash || method !== 'POST') return false;
  return url.origin === issuer ? ['/login', '/otp-auth', '/authorize'].includes(url.pathname) : ['/session', '/resolution/293137/decide'].includes(url.pathname);
}

await runCandidate({ chromium: chrome, artifact: 'candidate.tar.gz', binding, output: 'evidence', permits,
  scenario: async ({ context, page, step, screenshot, viewports }) => {
    const login = page.getByRole('link', { name: /^log in$/i });
    const summaryLink = page.getByRole('link', { name: 'Archive summary', exact: true });
    const trigger = page.locator('.harvj-session > summary');
    const logout = page.getByRole('button', { name: 'Log Out', exact: true });
    await step('anonymous-landing', async () => {
      await page.goto(origin + '/');
      await login.waitFor();
      assert.equal(await summaryLink.count(), 0);
      assert.equal(await page.getByText('Harbor Lights (reported)', { exact: true }).count(), 0);
    });
    await step('native-password-totp-oidc', async () => {
      await nativeLogin(page, { issuer, callback, start: origin + '/', credentials: identity,
        otp: () => execFileSync(env.PILOT_RUBY, ['-rrotp', '-e', 'puts ROTP::TOTP.new(File.read("otp")).now'],
          { encoding: 'utf8' }).trim(),
        verifyAuthorize(raw) {
          const query = new URL(raw).searchParams;
          for (const [name, value] of Object.entries({
            client_id: identity.client_id, redirect_uri: callback, response_type: 'code', code_challenge_method: 'S256',
          })) assert.deepEqual(query.getAll(name), [value]);
          for (const name of ['state', 'nonce', 'code_challenge']) assert.match(query.get(name) ?? '', /^[A-Za-z0-9_-]{32,}$/);
        },
      });
      await page.waitForURL(origin + '/archive');
      await summaryLink.waitFor();
      assert.equal(await login.count(), 0);
    });
    for (const { name, width, height } of viewports) {
      await step(name + '-archive-shell', async () => {
        await page.setViewportSize({ width, height });
        await page.goto(origin + '/archive');
        await summaryLink.click();
        await page.waitForURL(origin + '/archive/summary');
        await page.getByRole('heading', { name: 'Archive summary', exact: true }).waitFor();
        assert.equal(await page.locator('.archive-summary .stat').filter({ hasText: 'Imported scrobbles' }).locator('strong').textContent(), '11');
        await trigger.getByText(identity.username, { exact: true }).waitFor();
        const geometry = await page.evaluate(() => {
          const wordmark = document.querySelector('.harvj-wordmark').getBoundingClientRect();
          const trigger = document.querySelector('.harvj-session > summary').getBoundingClientRect();
          return { left: wordmark.left, right: innerWidth - trigger.right, height: trigger.height,
            gap: Number.parseFloat(getComputedStyle(document.querySelector('.library-nav')).columnGap),
            fits: document.documentElement.scrollWidth <= innerWidth };
        });
        const inset = width <= 700 ? 28 : width * 0.065;
        assert.ok(Math.abs(geometry.left - inset) <= 1 && Math.abs(geometry.right - inset) <= 1);
        assert.ok(geometry.fits && geometry.height >= 44);
        assert.equal(geometry.gap, width <= 700 ? 12 : 20);
        await trigger.focus();
        await page.keyboard.press('Enter');
        await logout.waitFor();
        await screenshot(name, [trigger, page.locator('.archive-summary')]);
        await logout.focus();
        await page.keyboard.press('Escape');
        await page.locator('.harvj-session:not([open])').waitFor();
        assert.equal(await trigger.evaluate(el => document.activeElement === el), true);
      });
    }
    for (const { name, width, height } of viewports) {
      await step(name + '-birthday-resolution', async () => {
        await page.setViewportSize({ width, height });
        await page.goto(origin + '/resolution/293137');
        const release = date => page.getByRole('region', { name: 'Verified album configurations' }).locator('details').filter({
          has: page.locator('summary').filter({ hasText: date }),
        });
        const us = release('September 24, 1991');
        const japan = release('September 20, 1991');
        const single = page.getByRole('region', { name: 'Adjacent recording programs' }).locator('details').filter({
          has: page.locator('summary').filter({ hasText: /She.s So High.*1990/ }),
        });
        const selected = us.getByRole('checkbox', { name: 'Select configuration' });
        const preview = page.getByRole('region', { name: 'Pending release decisions' });
        await us.locator('summary').click();
        await single.locator('summary').click();
        assert.equal(await selected.isChecked(), false);
        await selected.scrollIntoViewIfNeeded();
        await screenshot(name + '-resolution-unselected', [trigger]);
        await selected.focus();
        await selected.press('Space');
        assert.equal(await selected.isChecked(), true);
        await selected.press('Space');
        assert.equal(await selected.isChecked(), false);
        await selected.check();
        await japan.locator('summary').click();
        await japan.getByRole('checkbox', { name: 'Select configuration' }).check();
        await us.getByRole('radio', { name: /Use as the admitted base/ }).check();
        await single.getByRole('checkbox', { name: 'Select independent release' }).check();
        assert.equal(await preview.locator('li').count(), 3);
        assert.match(await us.innerText(), /Album appearance/);
        assert.match(await single.innerText(), /Edit \(Source labeled\)/);
        const labels = await preview.locator('li').allTextContents();
        assert.ok(labels.every(label => !label.includes('<a')));
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
        await selected.scrollIntoViewIfNeeded();
        await screenshot(name + '-resolution-selected', [trigger]);
        await preview.scrollIntoViewIfNeeded();
        await screenshot(name + '-resolution-preview', [trigger]);
      });
    }
    await step('apply-birthday-resolution', async () => {
      const confirm = page.locator('#confirm_recording');
      if (await confirm.count()) await confirm.check();
      const response = page.waitForResponse(item => item.url() === origin + '/resolution/293137/decide' &&
        item.request().method() === 'POST' && item.status() === 303);
      await page.getByRole('button', { name: 'Resolve all 8 observations', exact: true }).click();
      await response;
      await page.getByText('Recording and release decisions saved.', { exact: true }).waitFor();
      await page.getByText('Already in the canonical catalog', { exact: true }).first().waitFor({ state: 'attached' });
      await page.goto(origin + '/archive');
    });
    await step('same-title-observation-remains-ambiguous', async () => {
      await page.goto(origin + '/resolution/293200');
      await page.getByText('Competing recording identities are possible.', { exact: false }).waitFor();
      assert.equal(await page.locator('.resolution-choice[aria-current]').count(), 0);
      assert.equal(await page.locator('#recording-resolution-confirmation').count(), 0);
      const choices = page.locator('.resolution-choices').first();
      await choices.scrollIntoViewIfNeeded();
      await screenshot('mobile-ambiguous-recordings', [trigger]);
      const disputed = page.locator('summary').filter({ hasText: 'Disputed source' });
      await disputed.click();
      const reported = disputed.locator('..').getByText('Variant unresolved', { exact: false });
      await reported.scrollIntoViewIfNeeded();
      await screenshot('mobile-disputed-track-evidence', [trigger]);
      await page.getByRole('link', { name: 'Evidence', exact: true }).click();
      await page.getByRole('region', { name: 'Candidate evidence' }).waitFor();
      await page.getByRole('link', { name: 'Candidates', exact: true }).click();
      await page.locator('.resolution-choice').filter({ hasText: 'Single version' }).click();
      const confirm = page.locator('#confirm_recording');
      assert.equal(await confirm.isChecked(), false);
      assert.equal(await confirm.evaluate(input => input.form.checkValidity()), false);
      await page.goto(origin + '/archive');
    });
    await step('logout-and-private-boundary', async () => {
      await trigger.press('Enter');
      const response = page.waitForResponse(item => item.url() === origin + '/session' &&
        item.request().method() === 'POST' && item.status() === 303);
      await logout.click();
      await response;
      await page.waitForURL(origin + '/', { waitUntil: 'load' });
      await login.waitFor();
      assert.ok(!(await context.cookies(origin)).some(cookie => cookie.name === 'session_id'));
      for (const path of ['/archive', '/archive/summary']) {
        await page.goto(origin + path);
        await login.waitFor();
        assert.equal(await summaryLink.count(), 0);
        assert.equal(await page.locator('.archive-summary, .harvj-session').count(), 0);
        assert.equal(await page.getByText('Harbor Lights (reported)', { exact: true }).count(), 0);
      }
    });
  },
});
