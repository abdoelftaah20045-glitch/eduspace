// Deki course-list import on the server. The app saves the list of YouTube playlist links as a job; the database
// timer calls this function every minute with {auto:true, job_id, secret}. Each call works for ~100 s: it reads one
// playlist from YouTube's public page (no API key), creates the draft course + lessons, then fills the real video
// descriptions 8 at a time. Progress is saved after every step, so Stop / crash / restart loses nothing.
// Deploy with "Verify JWT" OFF (same as quiz-gen and exam-gen): the timer calls it with a shared secret instead.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (o: unknown) =>
  new Response(JSON.stringify(o), { headers: { ...cors, 'Content-Type': 'application/json' } });
const H = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
  'Accept-Language': 'en-US,en;q=0.9',
  'Cookie': 'CONSENT=YES+1; SOCS=CAI',
};
const BUDGET_MS = 100000;

const dec = (s: string) =>
  s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&#(\d+);/g, (_m, n) => String.fromCodePoint(Number(n)));

function collect(node: any, key: string, out: any[]) {
  if (Array.isArray(node)) for (const v of node) collect(v, key, out);
  else if (node && typeof node === 'object') {
    for (const [k, v] of Object.entries(node)) {
      if (k === key && v && typeof v === 'object') out.push(v);
      collect(v, key, out);
    }
  }
}
const text = (n: any): string => {
  if (!n) return '';
  if (typeof n.simpleText === 'string') return n.simpleText;
  if (Array.isArray(n.runs)) return n.runs.map((r: any) => r?.text ?? '').join('');
  return '';
};
function findToken(n: any): string | null {
  if (Array.isArray(n)) { for (const v of n) { const r = findToken(v); if (r) return r; } }
  else if (n && typeof n === 'object') {
    if (typeof n.token === 'string' && n.token.length > 20) return n.token;
    for (const v of Object.values(n)) { const r = findToken(v); if (r) return r; }
  }
  return null;
}
function nextToken(data: any): string | null {
  const vm: any[] = [];
  collect(data, 'continuationItemViewModel', vm);
  for (const e of vm) { const t = findToken(e); if (t) return t; }
  const out: any[] = [];
  collect(data, 'continuationItemRenderer', out);
  for (const e of out) { const t = e?.continuationEndpoint ? findToken(e.continuationEndpoint) : null; if (t) return t; }
  return null;
}
function clock(t: string): number {
  const p = t.trim().split(':');
  if (p.length < 2 || p.length > 3) return 0;
  let n = 0;
  for (const x of p) { const v = parseInt(x, 10); if (isNaN(v)) return 0; n = n * 60 + v; }
  return n;
}
function badge(n: any): string | null {
  if (Array.isArray(n)) { for (const v of n) { const r = badge(v); if (r) return r; } }
  else if (n && typeof n === 'object') {
    if (typeof n.text === 'string' && /^\d{1,2}(:\d{2}){1,2}$/.test(n.text.trim())) return n.text.trim();
    for (const v of Object.values(n)) { const r = badge(v); if (r) return r; }
  }
  return null;
}
type Vid = { id: string; title: string; seconds: number };
function videosOf(data: any, seen: Set<string>): Vid[] {
  const list: Vid[] = [];
  const lk: any[] = [];
  collect(data, 'lockupViewModel', lk);
  for (const r of lk) {
    if (r.contentType !== 'LOCKUP_CONTENT_TYPE_VIDEO') continue;
    const id = r.contentId;
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const t = r.metadata?.lockupMetadataViewModel?.title?.content ?? '';
    list.push({ id, title: dec(t || id), seconds: clock(badge(r.contentImage) ?? '') });
  }
  const out: any[] = [];
  collect(data, 'playlistVideoRenderer', out);
  for (const r of out) {
    const id = r.videoId;
    if (!id || seen.has(id)) continue;
    seen.add(id);
    list.push({ id, title: dec(text(r.title) || id), seconds: parseInt(r.lengthSeconds ?? '0', 10) || 0 });
  }
  return list;
}
const listId = (u: string): string | null => {
  const t = u.trim();
  const m = t.match(/[?&]list=([A-Za-z0-9_-]+)/);
  if (m) return m[1];
  return /^(PL|UU|OL|FL|RD)[A-Za-z0-9_-]{8,}$/.test(t) ? t : null;
};

async function fetchPlaylist(id: string) {
  const res = await fetch(`https://www.youtube.com/playlist?list=${id}&hl=en`, { headers: H, signal: AbortSignal.timeout(25000) });
  if (res.status !== 200) throw new Error(`HTTP ${res.status}`);
  const html = await res.text();
  const start = html.indexOf('ytInitialData = ');
  if (start < 0) throw new Error('page_not_readable' + (html.includes('consent.youtube.com') ? ' consent' : '') + (html.includes('unusual traffic') ? ' bot-check' : ''));
  const from = html.indexOf('{', start);
  let end = html.indexOf(';</script>', from);
  if (end < 0) end = html.length;
  const data = JSON.parse(html.slice(from, end));
  const seen = new Set<string>();
  const videos = videosOf(data, seen);
  let title = '', channel = '';
  const hs: any[] = [];
  collect(data, 'playlistHeaderRenderer', hs);
  if (hs.length) { title = text(hs[0].title); channel = text(hs[0].ownerText); }
  if (!title) title = (html.match(/<meta property="og:title" content="([^"]*)"/) ?? [])[1] ?? id;
  if (!channel) { const b: any[] = []; collect(data, 'playlistVideoRenderer', b); if (b.length) channel = text(b[0].shortBylineText); }
  if (!channel) { const o: any[] = []; collect(data, 'videoOwnerRenderer', o); if (o.length) channel = text(o[0].title); }
  const key = (html.match(/"INNERTUBE_API_KEY":"([^"]+)"/) ?? [])[1];
  const ver = (html.match(/"INNERTUBE_CONTEXT_CLIENT_VERSION":"([^"]+)"/) ?? [])[1] ?? '2.20240101.00.00';
  let token = nextToken(data);
  let guard = 0;
  while (token && key && videos.length < 500 && guard < 6) {
    guard++;
    const r = await fetch(`https://www.youtube.com/youtubei/v1/browse?key=${key}`, {
      method: 'POST', headers: { ...H, 'Content-Type': 'application/json' },
      body: JSON.stringify({ context: { client: { clientName: 'WEB', clientVersion: ver, hl: 'en' } }, continuation: token }),
      signal: AbortSignal.timeout(25000),
    });
    if (r.status !== 200) break;
    const d = await r.json();
    const more = videosOf(d, seen);
    if (!more.length) break;
    videos.push(...more);
    token = nextToken(d);
  }
  if (!videos.length) throw new Error('no_videos (private or empty playlist?)');
  let avatar = '';
  const ow: any[] = [];
  collect(data, 'videoOwnerRenderer', ow);
  for (const o of ow) {
    const th = o?.thumbnail?.thumbnails;
    if (Array.isArray(th) && th.length) { const u = String(th[th.length - 1]?.url ?? ''); if (u.startsWith('http')) { avatar = u; break; } }
  }
  return { id, title: dec(title), channel: dec(channel), avatar, videos };
}

async function fetchDescription(videoId: string): Promise<string> {
  try {
    const res = await fetch(`https://www.youtube.com/watch?v=${videoId}&hl=en`, { headers: H, signal: AbortSignal.timeout(20000) });
    if (res.status !== 200) return '';
    const html = await res.text();
    const m = html.match(/"shortDescription":"((?:[^"\\]|\\.)*)"/) ?? html.match(/"attributedDescription":\{"content":"((?:[^"\\]|\\.)*)"/);
    if (!m) return '';
    const d = dec(JSON.parse(`"${m[1]}"`) as string);
    return d.length > 1500 ? d.slice(0, 1500) : d;
  } catch (_) { return ''; }
}
const mmss = (s: number) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
const PREFIX = 'الدرس ';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const body = await req.json();

    // ---------- create: called by the admin from the app ----------
    if (body.action === 'create') {
      const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
        global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
      });
      const { data: u } = await db.auth.getUser();
      if (!u?.user) return json({ error: 'auth' });
      const tenantId = String(body.tenant_id ?? '');
      const rows: any[] = Array.isArray(body.items) ? body.items.slice(0, 2000) : [];
      if (!tenantId || !rows.length) return json({ error: 'missing' });
      const items = rows.map((r: any) => ({
        line: r.line ?? 0, category: String(r.category ?? ''), url: String(r.url ?? ''), title: String(r.title ?? ''),
        lang: String(r.lang ?? ''), level: String(r.level ?? ''), state: 'wait', note: '', course_id: '', tries: 0,
      }));
      const { data: job, error } = await db.from('playlist_jobs').insert({
        tenant_id: tenantId, title: String(body.title ?? '').slice(0, 200), with_desc: body.with_desc !== false,
        items, total: items.length, status: 'queued', created_by: u.user.id,
      }).select('id').single();
      if (error || !job) return json({ error: 'not_allowed', detail: String(error?.message ?? '') });
      return json({ ok: true, job_id: job.id, total: items.length });
    }

    // ---------- auto: called by the database timer ----------
    if (body.auto !== true) return json({ error: 'bad_request' });
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: sec } = await db.from('quiz_auto_secret').select('secret').limit(1).maybeSingle();
    if (!sec || sec.secret !== body.secret) return json({ error: 'auth' });
    const t0 = Date.now();
    const nowIso = new Date().toISOString();
    const { data: job } = await db.from('playlist_jobs')
      .update({ busy_until: new Date(t0 + 3 * 60000).toISOString(), status: 'running', updated_at: nowIso })
      .eq('id', String(body.job_id ?? '')).in('status', ['queued', 'running']).eq('stop', false)
      .or(`busy_until.is.null,busy_until.lt.${nowIso}`)
      .or(`paused_until.is.null,paused_until.lt.${nowIso}`)
      .select('*').maybeSingle();
    if (!job) return json({ skipped: 'not_due' });
    const items: any[] = job.items ?? [];
    let pauseUntil: string | null = null;
    let lastErr: string | null = null;

    const save = async (extra: any = {}) => {
      const done = items.filter((i) => i.state === 'ok' || i.state === 'skip').length;
      const failed = items.filter((i) => i.state === 'err').length;
      await db.from('playlist_jobs').update({ items, done, failed, updated_at: new Date().toISOString(), ...extra }).eq('id', job.id);
    };
    const stopped = async () => {
      const { data } = await db.from('playlist_jobs').select('stop').eq('id', job.id).maybeSingle();
      return !!data?.stop;
    };

    const { data: catRows } = await db.from('categories').select('name').eq('tenant_id', job.tenant_id).eq('kind', 'category').limit(2000);
    const known = new Set<string>((catRows ?? []).map((c: any) => String(c.name).trim().toLowerCase()));

    while (Date.now() - t0 < BUDGET_MS) {
      if (await stopped()) { await save({ busy_until: null, status: 'stopped' }); return json({ stopped: true }); }
      const it = items.find((i) => i.state === 'wait' || i.state === 'enrich');
      if (!it) break;
      try {
        if (it.state === 'wait') {
          const id = listId(it.url);
          if (!id) { it.state = 'err'; it.note = 'رابط غير صالح'; await save(); continue; }
          const p = await fetchPlaylist(id);
          if (it.title) p.title = it.title;
          const cat = dec(it.category ?? '');
          if (cat && !known.has(cat.toLowerCase())) {
            await db.from('categories').insert({ tenant_id: job.tenant_id, kind: 'category', name: cat.trim() });
            known.add(cat.toLowerCase());
          }
          // Already imported (even half)? continue that course.
          let courseId = '';
          let sectionId = '';
          const have = new Set<string>();
          const { data: hit } = await db.from('lessons').select('course_id').ilike('media_url', `%list=${id}%`).limit(1);
          if (hit?.length) {
            courseId = String(hit[0].course_id);
            const { data: ls } = await db.from('lessons').select('media_url, section_id').eq('course_id', courseId).limit(5000);
            for (const l of ls ?? []) {
              const m = String(l.media_url ?? '').match(/[?&]v=([A-Za-z0-9_-]{11})/);
              if (m) have.add(m[1]);
              if (!sectionId && l.section_id) sectionId = String(l.section_id);
            }
          }
          const missing = p.videos.map((v, i) => ({ v, i })).filter((x) => !have.has(x.v.id));
          if (courseId && !missing.length) {
            it.course_id = courseId; it.note = `${p.title} (مستورد قبل كده)`;
            it.state = job.with_desc ? 'enrich' : 'skip';
            if (it.state === 'enrich') it.note = `${p.title}: قراءة الأوصاف`;
            await save(); continue;
          }
          if (!courseId) {
            const hours = p.videos.reduce((a, v) => a + v.seconds, 0) / 3600;
            const { data: c, error } = await db.from('courses').insert({
              title: p.title, description: `${p.channel ? p.channel + ' - ' : ''}${p.videos.length} درس, ${hours.toFixed(1)} ساعة`,
              field: cat, instructor_name: p.channel, cover_url: `https://i.ytimg.com/vi/${p.videos[0].id}/hqdefault.jpg`,
              hours: Number(hours.toFixed(1)), price: 0, status: 'draft', created_by: job.created_by, tenant_id: job.tenant_id,
              ...(it.level ? { level: it.level } : {}), ...(it.lang ? { language: it.lang } : {}),
            }).select('id').single();
            if (error || !c) throw new Error('course: ' + String(error?.message ?? ''));
            courseId = String(c.id);
          }
          if (p.avatar) {
            await db.from('courses').update({ instructor_photo_url: p.avatar }).eq('id', courseId).or('instructor_photo_url.is.null,instructor_photo_url.eq.');
          }
          if (!sectionId) {
            const { data: secs } = await db.from('course_sections').select('id').eq('course_id', courseId).order('sort_order').limit(1);
            if (secs?.length) sectionId = String(secs[0].id);
            else {
              const { data: s2, error } = await db.from('course_sections').insert({ course_id: courseId, title: p.title, sort_order: 0 }).select('id').single();
              if (error || !s2) throw new Error('section: ' + String(error?.message ?? ''));
              sectionId = String(s2.id);
            }
          }
          const rowsIns = missing.map(({ v, i }) => ({
            course_id: courseId, section_id: sectionId, title: v.title, type: 'video',
            content: `${PREFIX}${i + 1}/${p.videos.length}: ${v.title} (${mmss(v.seconds)})${p.channel ? ' - ' + p.channel : ''}`,
            media_url: `https://www.youtube.com/watch?v=${v.id}&list=${id}`,
            duration_seconds: v.seconds > 0 ? v.seconds : null, sort_order: i,
          }));
          for (let k = 0; k < rowsIns.length; k += 50) {
            const { error } = await db.from('lessons').insert(rowsIns.slice(k, k + 50));
            if (error) throw new Error('lessons: ' + error.message);
          }
          it.course_id = courseId;
          it.videos = p.videos.length;
          it.state = job.with_desc ? 'enrich' : 'ok';
          it.note = job.with_desc ? `${p.title}: قراءة الأوصاف` : `${p.title} (${rowsIns.length})`;
          it.title_done = p.title;
          await save();
        } else {
          // enrich: real descriptions, 8 at a time, until the time budget ends
          const { data: ls } = await db.from('lessons').select('id, media_url, content').eq('course_id', it.course_id).limit(5000);
          const todo: { id: string; v: string }[] = [];
          for (const l of ls ?? []) {
            const c = String(l.content ?? '');
            const m = String(l.media_url ?? '').match(/[?&]v=([A-Za-z0-9_-]{11})/);
            if (m && (!c.trim() || c.startsWith(PREFIX)) && !String(l.content ?? '').startsWith('\u200b')) todo.push({ id: String(l.id), v: m[1] });
          }
          it.enrich_left = todo.length;
          let progressed = false;
          for (let k = 0; k < todo.length && Date.now() - t0 < BUDGET_MS; k += 8) {
            const part = todo.slice(k, k + 8);
            const res = await Promise.all(part.map((x) => fetchDescription(x.v)));
            await Promise.all(part.map((x, j) => {
              const d = res[j].trim();
              // empty result: mark with a zero-width space so it is not retried forever
              progressed = true;
              return db.from('lessons').update({ content: d || '\u200b' + (ls!.find((l: any) => l.id === x.id)?.content ?? '') }).eq('id', x.id);
            }));
            it.enrich_left = Math.max(0, todo.length - k - part.length);
            it.note = `قراءة الأوصاف: باقي ${it.enrich_left}`;
            await save();
          }
          if (!todo.length || (progressed && it.enrich_left === 0)) {
            it.state = 'ok';
            it.note = `${it.title_done ?? ''} (${it.videos ?? ''})`.trim();
            await save();
          }
        }
      } catch (e) {
        const msg = String(e).slice(0, 200);
        it.tries = (it.tries ?? 0) + 1;
        lastErr = msg;
        if (it.tries >= 5) { it.state = 'err'; it.note = msg; await save({ last_error: msg }); continue; }
        // YouTube slow / blocked for a moment: wait and try the same item again later
        it.note = 'إعادة المحاولة: ' + msg.slice(0, 80);
        pauseUntil = new Date(Date.now() + Math.min(10, it.tries * 2) * 60000).toISOString();
        await save({ last_error: msg });
        break;
      }
    }
    const left = items.some((i) => i.state === 'wait' || i.state === 'enrich');
    await save({
      busy_until: null, last_error: lastErr, paused_until: pauseUntil,
      status: left ? 'running' : 'done',
    });
    return json({ ok: true, left });
  } catch (e) {
    return json({ error: 'fail', detail: String(e).slice(0, 200) });
  }
});
