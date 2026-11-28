// Deki course-list import on the server, using the official YouTube Data API v3 (no page scraping).
// Secret needed: YOUTUBE_API_KEY (free Google Cloud key, "YouTube Data API v3" enabled). The app saves the list of
// playlist links as a job; the database timer calls this function every minute with {auto:true, job_id, secret}.
// Each call creates draft courses + lessons (titles, durations and real descriptions come from the API).
// Progress is saved after every step, so Stop / crash / restart loses nothing. Free quota: 10,000 units/day,
// about 6 units per 100-video playlist.
// Deploy with "Verify JWT" OFF (same as quiz-gen and exam-gen): the timer calls it with a shared secret instead.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (o: unknown) =>
  new Response(JSON.stringify(o), { headers: { ...cors, 'Content-Type': 'application/json' } });
const API = 'https://www.googleapis.com/youtube/v3';
const BUDGET_MS = 100000;

const dec = (s: string) =>
  s.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&#(\d+);/g, (_m, n) => String.fromCodePoint(Number(n)));

class ApiErr extends Error {
  constructor(public kind: string, msg: string) { super(msg); }
}
// Official YouTube Data API v3 (free quota 10,000 units/day; each call below costs 1 unit).
async function yt(path: string, params: Record<string, string>, key: string): Promise<any> {
  const q = new URLSearchParams({ ...params, key });
  const r = await fetch(`${API}/${path}?${q}`, { signal: AbortSignal.timeout(25000) });
  const j = await r.json().catch(() => ({}));
  if (r.status === 200) return j;
  const reason = String(j?.error?.errors?.[0]?.reason ?? '');
  if (/quota|rateLimit/i.test(reason)) throw new ApiErr('quota', 'quota ' + reason);
  if (r.status === 404 || reason === 'playlistNotFound') throw new ApiErr('gone', 'playlist not found or private');
  if (r.status === 400 && /keyInvalid|API key/i.test(JSON.stringify(j))) throw new ApiErr('key', 'bad YouTube API key');
  if (r.status === 403) throw new ApiErr('key', `403 ${reason || 'forbidden'} (is YouTube Data API v3 enabled for the key?)`);
  throw new Error(`HTTP ${r.status} ${reason}`);
}
const isoSec = (d: string): number => {
  const m = String(d).match(/^P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/);
  if (!m) return 0;
  return (+(m[1] ?? 0)) * 86400 + (+(m[2] ?? 0)) * 3600 + (+(m[3] ?? 0)) * 60 + (+(m[4] ?? 0));
};
const listId = (u: string): string | null => {
  const t = u.trim();
  const m = t.match(/[?&]list=([A-Za-z0-9_-]+)/);
  if (m) return m[1];
  return /^(PL|UU|OL|FL|RD)[A-Za-z0-9_-]{8,}$/.test(t) ? t : null;
};
type Vid = { id: string; title: string; seconds: number; description: string };

async function fetchPlaylist(id: string, key: string) {
  const pl = await yt('playlists', { part: 'snippet', id }, key);
  const p = pl?.items?.[0];
  if (!p) throw new ApiErr('gone', 'playlist not found or private');
  const ids: { id: string; title: string }[] = [];
  let token = '';
  for (let g = 0; g < 12; g++) {
    const r = await yt('playlistItems', { part: 'snippet', playlistId: id, maxResults: '50', ...(token ? { pageToken: token } : {}) }, key);
    for (const it of r.items ?? []) {
      const vid = it?.snippet?.resourceId?.videoId;
      const t = String(it?.snippet?.title ?? '');
      if (!vid || /^(Private video|Deleted video)$/i.test(t)) continue;
      ids.push({ id: vid, title: dec(t) });
    }
    token = r.nextPageToken ?? '';
    if (!token || ids.length >= 600) break;
  }
  if (!ids.length) throw new ApiErr('gone', 'no public videos in this playlist');
  // Durations and full descriptions: 50 videos per call.
  const videos: Vid[] = [];
  for (let k = 0; k < ids.length; k += 50) {
    const part = ids.slice(k, k + 50);
    const r = await yt('videos', { part: 'snippet,contentDetails', id: part.map((x) => x.id).join(',') }, key);
    const by = new Map<string, any>((r.items ?? []).map((v: any) => [v.id, v]));
    for (const x of part) {
      const v = by.get(x.id);
      let d = dec(String(v?.snippet?.description ?? '')).trim();
      if (d.length > 1500) d = d.slice(0, 1500);
      videos.push({ id: x.id, title: x.title, seconds: isoSec(v?.contentDetails?.duration ?? ''), description: d });
    }
  }
  let avatar = '';
  try {
    const chId = String(p.snippet?.channelId ?? '');
    if (chId) {
      const c = await yt('channels', { part: 'snippet', id: chId }, key);
      const th = c?.items?.[0]?.snippet?.thumbnails;
      avatar = String(th?.high?.url ?? th?.medium?.url ?? th?.default?.url ?? '');
    }
  } catch (_) {}
  return { id, title: dec(String(p.snippet?.title ?? id)), channel: dec(String(p.snippet?.channelTitle ?? '')), avatar, videos };
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
    const ytKey = Deno.env.get('YOUTUBE_API_KEY') ?? '';
    const items: any[] = job.items ?? [];
    if (!ytKey) {
      await db.from('playlist_jobs').update({ busy_until: null, status: 'error', last_error: 'no YOUTUBE_API_KEY secret', updated_at: nowIso }).eq('id', job.id);
      return json({ error: 'no_key' });
    }
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
      const it = items.find((i) => i.state === 'wait');
      if (!it) break;
      try {
        if (it.state === 'wait') {
          const id = listId(it.url);
          if (!id) { it.state = 'err'; it.note = 'رابط غير صالح'; await save(); continue; }
          const p = await fetchPlaylist(id, ytKey);
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
            it.state = 'skip';
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
            content: (job.with_desc && v.description) ? v.description
              : `${PREFIX}${i + 1}/${p.videos.length}: ${v.title} (${mmss(v.seconds)})${p.channel ? ' - ' + p.channel : ''}`,
            media_url: `https://www.youtube.com/watch?v=${v.id}&list=${id}`,
            duration_seconds: v.seconds > 0 ? v.seconds : null, sort_order: i,
          }));
          for (let k = 0; k < rowsIns.length; k += 50) {
            const { error } = await db.from('lessons').insert(rowsIns.slice(k, k + 50));
            if (error) throw new Error('lessons: ' + error.message);
          }
          it.course_id = courseId;
          it.videos = p.videos.length;
          it.state = 'ok';
          it.note = `${p.title} (${rowsIns.length})`;
          await save();
        }
      } catch (e) {
        const msg = String(e).slice(0, 200);
        if (e instanceof ApiErr && e.kind === 'quota') {
          // Free daily quota used up: wait and continue by itself (quota resets daily).
          it.note = 'حصة YouTube المجانية خلصت، هيكمل لوحده';
          await save({ last_error: msg, busy_until: null, paused_until: new Date(Date.now() + 60 * 60000).toISOString() });
          return json({ paused: 'quota' });
        }
        if (e instanceof ApiErr && e.kind === 'key') {
          await save({ last_error: msg, busy_until: null, status: 'error' });
          return json({ error: 'key', detail: msg });
        }
        if (e instanceof ApiErr && e.kind === 'gone') { it.state = 'err'; it.note = msg; await save({ last_error: msg }); continue; }
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
    const left = items.some((i) => i.state === 'wait');
    await save({
      busy_until: null, last_error: lastErr, paused_until: pauseUntil,
      status: left ? 'running' : 'done',
    });
    return json({ ok: true, left });
  } catch (e) {
    return json({ error: 'fail', detail: String(e).slice(0, 200) });
  }
});
