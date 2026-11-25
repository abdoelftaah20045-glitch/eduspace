-- امنح نفسك صلاحية الأدمن.
-- غيّر البريد الإلكتروني في السطر اللي تحت لبريد حسابك، وبعدين نفّذ الملف كله.
-- Change the email below to your account email, then run this whole file.

insert into public.user_roles (user_id, role_id)
select p.id, r.id
from public.profiles p, public.roles r
where p.email = 'PUT-YOUR-EMAIL-HERE@example.com'
  and r.name = 'admin'
on conflict do nothing;
