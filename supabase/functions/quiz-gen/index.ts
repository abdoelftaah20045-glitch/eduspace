// Deki practice-quiz generator (Google Gemini free tier). One lesson per call.
// Runs with the CALLER's login, so database policies decide: only an admin of
// the lesson's organization can read the lesson and create the exam.
// Grounding: lesson title + description (+ chapters in it) + course title and
// field. No captions are fetched. Questions test the topic, not what the
// speaker said at a given minute.
//
// Secret needed (same as ai-assistant): GEMINI_API_KEY
// SUPABASE_URL and SUPABASE_ANON_KEY are provided automatically.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (o: unknown) =>
  new Response(JSON.stringify(o), { headers: { ...cors, 'Content-Type': 'application/json' } });
const BASE = 'https://generativelanguage.googleapis.com/v1beta';
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function pickModels(key: string): Promise<string[]> {
  const fixed = ['gemini-flash-latest', 'gemini-flash-lite-latest'];
  try {
    const r = await fetch(`${BASE}/models?pageSize=200&key=${key}`, { signal: AbortSignal.timeout(6000) });
    const j = await r.json();
    const ver = (n: string) => parseFloat((n.match(/gemini-(\d+(?:\.\d+)?)/) ?? [])[1] ?? '0');
    const listed: string[] = (j?.models ?? [])
      .filter((m: any) => (m.supportedGenerationMethods ?? []).includes('generateContent'))
      .map((m: any) => String(m.name).replace('models/', ''))
      .filter((n: string) => /flash/.test(n) && !/(image|tts|live|audio|embed|robotics|computer|preview|exp)/.test(n))
      .sort((a: string, b: string) => ver(b) - ver(a) || a.length - b.length);
    const full = listed.filter((n) => !/lite/.test(n)).slice(0, 1);
    const lite = listed.filter((n) => /lite/.test(n)).slice(0, 1);
    return [...new Set([...full, ...lite, ...fixed])];
  } catch (_) {
    return fixed;
  }
}

const decode = (x: string): string => {
  let r = x ?? '';
  for (let i = 0; i < 5 && r.includes('&'); i++) {
    const n = r
      .replace(/&#(\d{1,7});/g, (_m, d) => String.fromCodePoint(parseInt(d, 10)))
      .replace(/&#[xX]([0-9a-fA-F]{1,6});/g, (_m, h) => String.fromCodePoint(parseInt(h, 16)))
      .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'").replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&');
    if (n === r) break;
    r = n;
  }
  return r;
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const key = Deno.env.get('GEMINI_API_KEY');
    if (!key) return json({ error: 'no_key' });
    const body = await req.json();
    let db: any;
    let uid: string | null = null;
    let lessonId = String(body.lesson_id ?? '');
    let publish = body.publish === true;
    let count = Math.min(10, Math.max(3, Number(body.count ?? 6)));
    let auto = false;
    let strict = false; // auto mode: never use text-only unless the setting allows
    let tenantId = '';
    if (body.auto === true) {
      // Called by the database timer. Authenticated by the shared secret.
      auto = true;
      db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
      const { data: sec } = await db.from('quiz_auto_secret').select('secret').limit(1).maybeSingle();
      if (!sec || sec.secret !== body.secret) return json({ error: 'auth' });
      tenantId = String(body.tenant_id ?? '');
      const nowIso = new Date().toISOString();
      const { data: claimed } = await db.from('quiz_auto_config')
        .update({ busy_until: new Date(Date.now() + 4 * 60000).toISOString(), last_run: nowIso })
        .eq('tenant_id', tenantId).eq('enabled', true)
        .or(`busy_until.is.null,busy_until.lt.${nowIso}`)
        .or(`paused_until.is.null,paused_until.lt.${nowIso}`)
        .select('*').maybeSingle();
      if (!claimed) return json({ skipped: 'not_due' });
      publish = claimed.publish === true;
      strict = claimed.text_fallback !== true;
      count = 6;
      const { data: nid } = await db.rpc('quiz_auto_next', { t: tenantId });
      if (!nid) {
        await db.from('quiz_auto_config').update({ enabled: false, busy_until: null, last_error: 'done: every lesson has a quiz or was skipped' }).eq('tenant_id', tenantId);
        return json({ done: true });
      }
      lessonId = String(nid);
    } else {
      const auth = req.headers.get('Authorization') ?? '';
      db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
        global: { headers: { Authorization: auth } },
      });
      const { data: u } = await db.auth.getUser();
      if (!u?.user) return json({ error: 'auth' });
      uid = u.user.id;
    }
    if (!lessonId) return json({ error: 'lesson_id' });
    // Auto mode bookkeeping, then the result goes back to the caller.
    const finish = async (res: any) => {
      if (auto) {
        const { data: cur } = await db.from('quiz_auto_config').select('made,skipped').eq('tenant_id', tenantId).maybeSingle();
        const upd: any = { busy_until: null, last_run: new Date().toISOString() };
        if (res.ok) { upd.made = (cur?.made ?? 0) + 1; upd.last_error = null; }
        if (res.skipped) {
          upd.skipped = (cur?.skipped ?? 0) + 1;
          await db.from('quiz_auto_skip').upsert({ lesson_id: lessonId, tenant_id: tenantId, reason: String(res.skipped) });
        }
        if (res.quota) {
          upd.paused_until = new Date(Date.now() + 2 * 3600000).toISOString();
          upd.last_error = 'quota: paused 2h, retries by itself (free daily video limit)';
        } else if (res.error) {
          upd.paused_until = new Date(Date.now() + 20 * 60000).toISOString();
          upd.last_error = `${res.error} ${res.detail ?? ''}`.slice(0, 300);
        }
        await db.from('quiz_auto_config').update(upd).eq('tenant_id', tenantId);
      }
      return json(res);
    };

    const { data: lesson } = await db.from('lessons')
      .select('id, title, content, course_id, media_url, duration_seconds').eq('id', lessonId).maybeSingle();
    if (!lesson) return await finish({ skipped: 'lesson_missing', error: auto ? undefined : 'lesson_not_found_or_no_access' });
    const { data: course } = await db.from('courses')
      .select('id, title, field, tenant_id').eq('id', lesson.course_id).maybeSingle();
    if (!course) return await finish({ skipped: 'course_missing' });

    const { data: have } = await db.from('exams').select('id').eq('lesson_id', lessonId).limit(1);
    if (have && have.length) return await finish({ skipped: 'has_exam' });

    const title = decode(lesson.title ?? '').trim();
    const desc = decode(lesson.content ?? '').trim().slice(0, 3500);
    const cTitle = decode(course.title ?? '').trim();
    const field = decode(course.field ?? '').trim();
    const ym = String(lesson.media_url ?? '').match(/(?:youtu\.be\/|[?&]v=|embed\/|shorts\/)([A-Za-z0-9_-]{11})/);
    const videoUrl = ym ? `https://www.youtube.com/watch?v=${ym[1]}` : null;
    const mins = Math.round(Number(lesson.duration_seconds ?? 0) / 60);
    // More questions for longer videos (about one per 3 minutes, 4 to 15).
    const vcount = Math.min(15, Math.max(4, Math.ceil((mins || 12) / 3)));
    const vprompt =
      `Course: ${cTitle}${field ? ' (' + field + ')' : ''}\nLesson title: ${title}\n\n` +
      `Watch this video. Write ${vcount} multiple-choice questions that test ONLY what the speaker actually explains in it, spread across the video from start to end and covering each main point. ` +
      `Write in the language of the video/lesson title (Arabic stays Arabic). Do not ask about the channel, timestamps or anything not said in the video. ` +
      `Each question has exactly 4 options, exactly one correct (index 0-3), and a one-sentence explanation based on the video.`;
    let grounded = false;
    let quotaHit = false;
    const prompt =
      `Course: ${cTitle}${field ? ' (' + field + ')' : ''}\nLesson title: ${title}\nLesson description:\n${desc || '(none)'}\n\n` +
      `Write ${count} multiple-choice practice questions for a student who studied this lesson topic. ` +
      `Rules: write in the same language as the lesson title (Arabic stays Arabic). Test understanding of the topic named in the title and the outline/chapters in the description if any. ` +
      `Use only well-established, textbook-level facts. Do NOT ask what the speaker said, about timestamps, the channel, or anything you cannot know from the text. ` +
      `If the title and description are too vague to write good questions, return an empty list. ` +
      `Each question has exactly 4 options, exactly one correct (index 0-3), and a one-sentence explanation.`;
    const schema = {
      type: 'OBJECT',
      properties: {
        questions: {
          type: 'ARRAY',
          items: {
            type: 'OBJECT',
            properties: {
              question: { type: 'STRING' },
              options: { type: 'ARRAY', items: { type: 'STRING' } },
              correct: { type: 'INTEGER' },
              explanation: { type: 'STRING' },
            },
            required: ['question', 'options', 'correct', 'explanation'],
          },
        },
      },
      required: ['questions'],
    };
    let qs: any[] | null = null;
    const errs: string[] = [];
    const started = Date.now();
    const models = (await pickModels(key)).slice(0, 3);
    for (const mode of (videoUrl ? ['video', 'text'] : ['text'])) {
    const isVideo = mode === 'video';
    if (qs) break;
    if (!isVideo && strict) break;
    for (const model of models) {
      for (let attempt = 0; attempt < 2 && !qs; attempt++) {
        if (Date.now() - started > (isVideo ? 140000 : 100000)) break;
        try {
          const r = await fetch(`${BASE}/models/${model}:generateContent?key=${key}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              contents: [{ role: 'user', parts: isVideo ? [{ fileData: { fileUri: videoUrl!, mimeType: 'video/*' } }, { text: vprompt }] : [{ text: prompt }] }],
              generationConfig: { responseMimeType: 'application/json', responseSchema: schema, temperature: 0.3, maxOutputTokens: 6000 },
            }),
            signal: AbortSignal.timeout(isVideo ? 110000 : 60000),
          });
          const j = await r.json();
          const t = (j?.candidates?.[0]?.content?.parts ?? []).filter((p: any) => !p.thought)
            .map((p: any) => p.text ?? '').join('');
          if (t) {
            qs = JSON.parse(t).questions ?? []; grounded = isVideo;
          } else {
            errs.push(`${model}: ${r.status} ${String(j?.error?.message ?? 'empty').slice(0, 80)}`);
            if (isVideo && (r.status === 429 || /quota|limit|hours/i.test(String(j?.error?.message ?? '')))) quotaHit = true;
            if (r.status === 429) { await sleep(8000); continue; }
            if (r.status === 503) { await sleep(1500); continue; }
            break;
          }
        } catch (e) {
          errs.push(`${model}: ${String(e).slice(0, 60)}`);
          break;
        }
      }
      if (qs) break;
    }
    }
    if (qs === null && strict) {
      if (!videoUrl) return await finish({ skipped: 'no_youtube_link' });
      if (quotaHit) return await finish({ quota: true, detail: errs.join(' | ').slice(0, 300) });
      return await finish({ skipped: 'video_unavailable', detail: errs.join(' | ').slice(0, 200) });
    }
    if (qs === null) return await finish({ error: 'gemini', detail: errs.join(' | ').slice(0, 400) });
    const good = qs.filter((q) =>
      q && typeof q.question === 'string' && q.question.trim() && Array.isArray(q.options) &&
      q.options.length === 4 && q.options.every((o: any) => typeof o === 'string' && o.trim()) &&
      Number.isInteger(q.correct) && q.correct >= 0 && q.correct <= 3 &&
      new Set(q.options.map((o: string) => o.trim())).size === 4);
    if (good.length < 3) return await finish({ skipped: 'too_vague', got: good.length });

    const { data: exam, error: e1 } = await db.from('exams').insert({
      course_id: course.id,
      lesson_id: lesson.id,
      tenant_id: course.tenant_id,
      title: `تدريب: ${title}`.slice(0, 200),
      description: grounded ? 'اختبار تدريبي مولّد بالذكاء الاصطناعي من محتوى الفيديو. للتدريب فقط وقد يحتوي على أخطاء.' : 'اختبار تدريبي مولّد بالذكاء الاصطناعي من عنوان الدرس ووصفه. للتدريب فقط.',
      status: publish ? 'published' : 'draft',
      pass_grade: Math.ceil(good.length * 0.6),
      max_attempts: 3,
      created_by: uid,
    }).select('id').single();
    if (e1 || !exam) return await finish({ error: 'exam_insert', detail: String(e1?.message ?? '') });
    let order = 0;
    for (const q of good) {
      const { data: row, error: e2 } = await db.from('questions').insert({
        tenant_id: course.tenant_id,
        type: 'mcq',
        body: q.question.trim(),
        points: 1,
        explanation: String(q.explanation ?? '').trim() || null,
      }).select('id').single();
      if (e2 || !row) continue;
      await db.from('question_options').insert(
        q.options.map((o: string, i: number) => ({
          question_id: row.id, body: o.trim(), is_correct: i === q.correct, sort_order: i,
        })));
      await db.from('exam_questions').insert({ exam_id: exam.id, question_id: row.id, sort_order: order++ });
    }
    return await finish({ ok: true, exam_id: exam.id, questions: order, grounded, status: publish ? 'published' : 'draft' });
  } catch (e) {
    return json({ error: 'handler', detail: String(e).slice(0, 300) });
  }
});
