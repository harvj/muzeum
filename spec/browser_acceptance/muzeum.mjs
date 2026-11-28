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
  return url.origin === issuer ? ['/login', '/otp-auth', '/authorize'].includes(url.pathname) : ['/session', '/resolution/293137/decide', '/resolution/293209/decide', '/resolution/293210/decide'].includes(url.pathname);
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
        assert.equal(await page.locator('.archive-summary .stat').filter({ hasText: 'Imported scrobbles' }).locator('strong').textContent(), '34');
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
      await step(name + '-birthday-evidence-route', async () => {
        await page.setViewportSize({ width, height });
        await page.goto(origin + '/resolution/293137?section=evidence');
        await page.getByText('8 matching observations', { exact: true }).waitFor();
        const checkbox = page.getByRole('checkbox', { name: /^Birthday/ });
        const release = page.locator('.resolution-release-evidence');
        const action = page.getByRole('button', { name: 'Resolve all 8 observations', exact: true });
        assert.equal(await checkbox.isChecked(), false);
        assert.equal(await action.count(), 0);
        assert.equal(await release.evaluate(el => el.open), false);
        assert.equal(await page.getByText('Proposed original release', { exact: true }).count(), 0);
        await checkbox.scrollIntoViewIfNeeded();
        await screenshot(name + '-recording-unselected', [trigger]);
        await checkbox.press('Space');
        await page.waitForURL(url => url.searchParams.has('candidate'));
        await action.waitFor();
        assert.equal(await action.isDisabled(), true);
        assert.equal(await checkbox.isChecked(), true);
        assert.equal(await checkbox.evaluate(el => getComputedStyle(el).backgroundColor), 'rgb(23, 24, 23)');
        assert.equal(await release.evaluate(el => el.open), false);
        assert.ok(await action.evaluate(el => el.getBoundingClientRect().top <
          document.querySelector('.resolution-release-evidence').getBoundingClientRect().top));
        await checkbox.scrollIntoViewIfNeeded();
        await screenshot(name + '-recording-selected', [trigger]);
        await action.scrollIntoViewIfNeeded();
        await screenshot(name + '-confirmation-preview', [trigger]);
        await release.locator(':scope > summary').click();
        const uk = release.getByText(/Leisure · August 27, 1991/).first();
        await uk.waitFor();
        await release.getByText(/Leisure · September 24, 1991/).first().waitFor();
        await release.getByText(/Leisure · September 20, 1991/).first().waitFor();
        await release.getByText(/Disputed source · August 26, 1991/).waitFor();
        await release.getByText(/She.s So High · October/).first().waitFor();
        assert.equal(await release.locator('details[open]').count(), 0);
        await screenshot(name + '-release-evidence-expanded', [trigger]);
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
      });
    }
    await step('admit-album-with-configurations-and-singles', async () => {
      await page.goto(origin + '/resolution/293137?section=evidence');
      await page.getByRole('checkbox', { name: /^Birthday/ }).check();
      await page.getByRole('button', { name: 'Resolve all 8 observations', exact: true }).waitFor();
      const release = page.locator('.resolution-release-evidence');
      await release.locator(':scope > summary').click();
      for (const date of ['August 27, 1991', 'September 24, 1991']) {
        const summary = release.locator('summary').filter({ hasText: 'Leisure · ' + date });
        await summary.click();
        await summary.locator('..').getByRole('checkbox', { name: 'Select configuration' }).check();
      }
      const uk = release.locator('summary').filter({ hasText: 'Leisure · August 27, 1991' }).locator('..');
      await uk.getByRole('radio', { name: 'Use as the admitted base and my preferred configuration' }).check();
      for (const program of [/She.s So High · October/, /There.s No Other Way · April/, /Bang · July/]) {
        const summary = release.locator('summary').filter({ hasText: program });
        await summary.click();
        await summary.locator('..').getByRole('checkbox', { name: 'Select independent release' }).check();
      }
      await page.getByText(/Admit one canonical album using the preferred configuration as its base/).waitFor();
      const response = page.waitForResponse(item => item.url() === origin + '/resolution/293137/decide' &&
        item.request().method() === 'POST' && item.status() === 303);
      await page.getByRole('button', { name: 'Resolve all 8 observations', exact: true }).click();
      await response;
      await page.getByText('Recording and release decisions saved.', { exact: true }).waitFor();
      await page.goto(origin + '/artists');
      await page.getByRole('link', { name: 'Blur', exact: true }).click();
      const ranked = page.locator('#artist-releases');
      const album = ranked.getByRole('link', { name: 'Leisure', exact: true });
      await album.waitFor();
      const first = ranked.locator('tbody tr').first();
      assert.match(await first.innerText(), /Leisure/);
      assert.match(await first.innerText(), /8 plays/);
      assert.equal(await ranked.locator('tbody tr').count(), 4);
      for (const { name, width, height } of viewports) {
        await page.setViewportSize({ width, height });
        await ranked.scrollIntoViewIfNeeded();
        await screenshot(name + '-artist-ranked-leisure', [trigger]);
      }
      await album.click();
      await page.getByText('8 distinct resolved observations', { exact: false }).first().waitFor();
      await page.locator('summary').filter({ hasText: 'Compare release configurations' }).click();
      await page.locator('summary').filter({ hasText: 'GB · 1991-08-27' }).filter({ hasText: '(preferred)' }).waitFor();
      await page.locator('summary').filter({ hasText: 'US · 1991-09-24' }).waitFor();
    });
    for (const [id, title, recordingId, count] of [
      [293209, 'Crash', '5639cdb3-7f91-4a04-bf16-b536ff7c040e', 19],
      [293210, 'Heartland', 'a79f2c69-4372-4ac3-a357-8b52764a3373', 4],
    ]) {
      await step('resolve-release-backed-' + title.toLowerCase(), async () => {
        const path = '/resolution/' + id;
        const action = page.locator('#recording-resolution-confirmation').getByRole('button', { name: 'Resolve all ' + count });
        for (const { name, width, height } of viewports) {
          await page.setViewportSize({ width, height });
          await page.goto(origin + path + '?candidate=' + recordingId);
          await action.waitFor();
          await page.getByText('Admit 1 new release', { exact: false }).first().waitFor();
          assert.equal(await page.locator('input[type="radio"][name="construct_release"]').count(), 0);
          const sources = page.locator('.release-configuration-sources').first();
          const expectedSources = title === 'Crash' ? 16 : 2;
          await sources.locator('summary').getByText(expectedSources + ' verified MusicBrainz source', { exact: false }).waitFor();
          await sources.locator('summary').click();
          assert.equal(await sources.getByRole('link').count(), expectedSources);
          await sources.locator('summary').click();
          await action.scrollIntoViewIfNeeded();
          await screenshot(name + '-release-backed-' + title.toLowerCase(), [trigger]);
        }
        await action.click();
        await page.getByText('Recording decision saved.', { exact: true }).waitFor();
        await page.goto(origin + path + '?section=observations');
        const table = page.getByRole('table', { name: 'Matching observations' });
        assert.equal(await table.getByRole('link', { name: title, exact: true }).count(), count);
      });
    }
    await step('same-title-observation-remains-ambiguous', async () => {
      await page.goto(origin + '/resolution/293200?section=evidence');
      await page.getByText('Competing recording identities are possible.', { exact: false }).waitFor();
      assert.equal(await page.locator('input[name=candidate]:checked').count(), 0);
      assert.equal(await page.locator('#recording-resolution-confirmation').count(), 0);
      const choices = page.locator('.resolution-choices').first();
      await choices.scrollIntoViewIfNeeded();
      await screenshot('mobile-ambiguous-recordings', [trigger]);
      await page.goto(origin + '/archive');
    });
    await step('logout-and-private-boundary', async () => {
      const disclosure = page.locator('.harvj-session');
      if (!(await disclosure.evaluate(el => el.open))) await trigger.click();
      await logout.waitFor();
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
