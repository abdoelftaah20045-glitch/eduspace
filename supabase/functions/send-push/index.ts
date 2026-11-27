// Sends the "new course" push (FCM HTTP v1) to every active member of the
// course's organization. Called by the database trigger (pg_net) right
// after an admin publishes a course with "notify users" on.
// Idempotent: a course is pushed once (courses.push_sent_at is claimed
// atomically), so repeated or forged calls cannot spam users.
//
// Secrets (Supabase > Edge Functions > Secrets):
//   FCM_SERVICE_ACCOUNT  the Firebase service-account JSON (whole file)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const b64url = (b: ArrayBuffer | string) =>
  btoa(typeof b === 'string' ? b : String.fromCharCode(...new Uint8Array(b)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

async function accessToken(sa: { client_email: string; private_key: string }) {
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key,
    new TextEncoder().encode(`${head}.${claim}`));
  const jwt = `${head}.${claim}.${b64url(sig)}`;
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const j = await r.json();
  if (!j.access_token) throw new Error('token: ' + JSON.stringify(j));
  return j.access_token as string;
}

Deno.serve(async (req) => {
  try {
    const { course_id } = await req.json();
    if (!course_id) return new Response('missing course_id', { status: 400 });
    const db = createClient(
      Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    // Claim: only a published course that asked for notification, once.
    const { data: claimed } = await db.from('courses')
      .update({ push_sent_at: new Date().toISOString() })
      .eq('id', course_id).eq('status', 'published')
      .not('notified_at', 'is', null).is('push_sent_at', null)
      .select('id, title, tenant_id, instructor_name');
    if (!claimed || claimed.length === 0) {
      return new Response('nothing to send', { status: 200 });
    }
    const course = claimed[0];
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
    const teacher = decode(course.instructor_name ?? '').trim();
    const body = 'تم إضافة كورس ' + decode(course.title ?? '') +
      (teacher ? ' للمدرس ' + teacher : '');
    const { data: members } = await db.from('tenant_memberships')
      .select('user_id').eq('tenant_id', course.tenant_id).eq('status', 'active');
    const ids = (members ?? []).map((m: { user_id: string }) => m.user_id);
    if (ids.length === 0) return new Response('no members', { status: 200 });
    const tokens: string[] = [];
    for (let i = 0; i < ids.length; i += 200) {
      const { data } = await db.from('push_tokens').select('token')
        .in('user_id', ids.slice(i, i + 200));
      for (const t of data ?? []) tokens.push(t.token);
    }
    const sa = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT')!);
    const at = await accessToken(sa);
    let sent = 0;
    const dead: string[] = [];
    for (const token of [...new Set(tokens)]) {
      const r = await fetch(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${at}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: 'كورس جديد / New course', body: body },
              data: { type: 'new_course', course_id: course.id },
              android: { priority: 'HIGH' },
            },
          }),
        });
      if (r.ok) sent++;
      else if (r.status === 404 || r.status === 400) dead.push(token);
    }
    if (dead.length) await db.from('push_tokens').delete().in('token', dead);
    return new Response(JSON.stringify({ sent, removed: dead.length }), { status: 200 });
  } catch (e) {
    return new Response(String(e), { status: 500 });
  }
});
