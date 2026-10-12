import axios from 'axios';
import { isAllowedSourceUrl } from './priceSources.registry.js';

const USER_AGENT = 'RentHubPriceSync/1.0';

export async function fetchSourceText(url, signal) {
  const response = await axios.get(url, {
    timeout: 15000, maxContentLength: 2_097_152, maxBodyLength: 2_097_152,
    maxRedirects: 0, responseType: 'text', signal,
    headers: { 'User-Agent': USER_AGENT, Accept: 'text/html,text/plain' },
    transformResponse: [(text) => text],
    validateStatus: () => true,
  });
  if (response.status < 200 || response.status >= 300) {
    const error = new Error(`HTTP_${response.status}`);
    error.status = response.status;
    throw error;
  }
  if (typeof response.data !== 'string' || Buffer.byteLength(response.data) > 2_097_152) throw new Error('PAGE_TOO_LARGE');
  return response.data;
}

export function robotsAllows(text, url) {
  // HTML challenge/error pages are not a robots policy and must fail closed.
  if (/<html|<!doctype/i.test(text)) return false;
  const groups = [];
  let group, hasRules = false;
  for (const line of text.split(/\r?\n/)) {
    const clean = line.replace(/#.*$/, '').trim(), pair = clean.match(/^([\w-]+)\s*:\s*(.*)$/);
    if (!pair) continue;
    const name = pair[1].toLowerCase(), value = pair[2].trim();
    if (name === 'user-agent') {
      if (!group || hasRules) { group = { agents: [], rules: [] }; groups.push(group); hasRules = false; }
      group.agents.push(value.toLowerCase());
    } else if (group && ['allow', 'disallow'].includes(name)) {
      hasRules = true;
      if (value) group.rules.push({ allow: name === 'allow', value });
    }
    if (name === 'content-signal' && /ai-input\s*=\s*no/i.test(value)) return false;
  }
  const specific = groups.filter((entry) => entry.agents.some((agent) => agent !== '*' && USER_AGENT.toLowerCase().includes(agent)));
  const selected = specific.length ? specific : groups.filter((entry) => entry.agents.includes('*'));
  const path = new URL(url).pathname;
  const matches = selected.flatMap((entry) => entry.rules).filter((rule) => {
    const anchored = rule.value.endsWith('$');
    const pattern = rule.value.replace(/\$$/, '').split('*').map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*');
    return new RegExp(`^${pattern}${anchored ? '$' : ''}`).test(path);
  }).sort((a, b) => b.value.replaceAll('*', '').length - a.value.replaceAll('*', '').length || Number(b.allow) - Number(a.allow));
  return matches[0]?.allow ?? true;
}

export async function checkSourceAccess(entry, urls, fetchText = fetchSourceText, signal) {
  const origin = new URL(entry.urls[0]).origin;
  let policy;
  try {
    policy = await fetchText(`${origin}/robots.txt`, signal);
  } catch (error) {
    // RFC 9309 permits collection when robots.txt is unavailable. Deliberately
    // limit that to confirmed absence: never ignore access denials, rate limits,
    // redirects, server failures or timeouts. Maintainer approval is still needed.
    if (error.status !== 404 && error.status !== 410) throw error;
    policy = '';
  }
  for (const url of urls) {
    if (!isAllowedSourceUrl(entry, url)) throw new Error('URL_NOT_ALLOWED');
    if (!robotsAllows(policy, url)) throw new Error('ACCESS_RESTRICTED');
  }
  return policy;
}
